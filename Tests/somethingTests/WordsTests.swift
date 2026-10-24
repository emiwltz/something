// What the person reads, word for word: a path with ~ and cut between two names, a journal line in local time with
// the agent's name and the result only when it is not ok, and the rights window's defaults (every right ticked,
// "Allow" first). No window is shown.
import AppKit
import SomethingCore
import Testing
@testable import something

@MainActor @Suite struct WordsTests {
    let home = "/Users/example"

    @Test func aPathIsShownFromHomeAndCutBetweenNames() {
        #expect(Words.path("/Users/example/code/shop", home: home) == "~/code/shop")
        #expect(Words.path("/Users/example", home: home + "/") == "~")
        #expect(Words.path("/srv/example-two", home: "/srv/example") == "/srv/example-two", "another folder that only starts the same")
        #expect(Words.path("/opt/tools/bin", home: home) == "/opt/tools/bin")
        let long = "/Users/example/code/clients/example-agency/website-redesign-2026"
        #expect(Words.path(long, home: home) { $0.count <= 45 } == "~/code/…/example-agency/website-redesign-2026")
        #expect(Words.path(long, home: home) { $0.count <= 40 } == "~/…/example-agency/website-redesign-2026")
        // The first name and the last always stay, and no name is ever cut inside.
        #expect(Words.path(long, home: home) { $0.count <= 10 } == "~/…/website-redesign-2026")
        #expect(Words.path("/var/folders/xy/tmp/a-very-long-name", home: home) { $0.count <= 27 } == "/var/…/tmp/a-very-long-name")
        #expect(Words.path(long + "/", home: home) { $0.count <= 10 } == "~/…/website-redesign-2026", "a final / keeps the last name")
        #expect(Words.path("/", home: home) == "/")
    }

    /// A clock in UTC, in British English: 24 hours, the day before the month.
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    let now = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00Z")!

    func words(_ line: JournalLine, _ names: [String: String] = ["a1": "shop"], clock: Locale = Locale(identifier: "en_GB")) -> String {
        Words.journal(line, names: names, home: home, now: now, calendar: calendar, locale: Locale(identifier: "en_GB"), clock: clock)
    }

    @Test func aJournalLineIsOneSentence() {
        #expect(words(JournalLine(at: "2026-10-17T08:00:00Z", action: "send", agent: "a1", kind: "claude", when: "next",
                                  text: "What changed in the cart overnight?\nList the files.", result: "ok"))
                == "08:00\twrote to Claude Code “shop”: “What changed in the cart overnight? Lis…”")
        #expect(words(JournalLine(at: "2026-10-17T08:00:00Z", action: "interrupt", agent: "a1", kind: "claude", result: "ok"),
                      clock: Locale(identifier: "en_US")).replacingOccurrences(of: "\u{202F}", with: " ")
                == "8:00 am\tinterrupted Claude Code “shop”", "a clock of 12 hours (some systems put a narrow space before am)")
        #expect(words(JournalLine(at: "2026-10-17T08:07:00Z", action: "interrupt", agent: "a1", kind: "claude", result: "AGENT_STOPPED"))
                == "08:07\tinterrupted Claude Code “shop” — failed: the agent had ended")
        #expect(words(JournalLine(at: "2026-10-16T08:07:00Z", action: "set", agent: "a2", kind: "codex", text: "model=gpt-invented mode=plan",
                                  result: "VALUE_NOT_OFFERED"))
                == "16 Oct 08:07\tchanged Codex: model gpt-invented, mode plan — refused: this agent does not offer that value", "an agent the state no longer has")
        #expect(words(JournalLine(at: "2025-12-31T23:59:00Z", action: "launch", agent: "a1", kind: "opencode", text: "/Users/example/code/shop",
                                  result: "ok"))
                == "31 Dec 2025 23:59\tlaunched OpenCode “shop” in ~/code/shop")
        #expect(words(JournalLine(at: "2026-10-17T09:00:00Z", action: "resume", kind: "pi", text: "thread-invented", result: "STILL_RUNNING"))
                == "09:00\tcontinued a conversation of pi here — failed: the conversation is still open elsewhere")
        #expect(words(JournalLine(at: "2026-10-17T09:01:00Z", action: "open", text: "https://example.com/notes", result: "REFUSED"))
                == "09:01\topened a link: https://example.com/notes — you said no")
        #expect(words(JournalLine(at: "not a date", action: "send", agent: "a3", text: "Hi", result: "AGENT_NOT_FOUND"))
                == "not a date\twrote to an agent: “Hi” — refused: the space cannot see this agent")
        #expect(words(JournalLine(at: "2026-10-17T09:02:00Z", action: "interrupt", agent: "a1", kind: "pi", result: "A_LATER_CODE"))
                == "09:02\tinterrupted pi “shop” — failed (A_LATER_CODE)", "a code this version does not know")
    }

    @Test func theRightsSheetShowsTheLaunchFolder() throws {
        let question = RightsQuestion(space: "Morning review", description: nil, rights: ["state", "store"], scope: nil, missing: [],
                                      folder: FolderQuestion(declared: "~/code/shop", found: "/Users/example/code/shop"))
        let window = Ask.rights(question, home: home)
        #expect(window.answer() == RightsAnswer(allowed: [], refused: ["state", "store"], folder: "/Users/example/code/shop", remap: [:]))
        let paths = labels(in: try #require(window.sheet.contentView)).filter { $0.toolTip != nil }
        #expect(paths.map(\.stringValue) == ["~/code/shop"] && paths.map(\.toolTip) == ["/Users/example/code/shop"])
    }

    /// A chosen folder keeps the sentence that says which declared folder it replaces.
    @Test func aChosenFolderSaysWhatItReplaces() {
        let lines = NSStackView()
        var kept: String?
        let chooser = Chooser(lines, "This folder is not on this Mac:", folder: "~/code/shop", then: "In place of ~/code/shop:",
                              button: "Choose a folder in its place…", home: home) { kept = $0 }
        chooser.picked("/Users/example/code/shop-copy")
        #expect(labels(in: lines).map(\.stringValue) == ["In place of ~/code/shop:", "~/code/shop-copy"])
        #expect(kept == "/Users/example/code/shop-copy")
    }

    /// Past six folders, the scope says how many more, all of them in a tooltip: a sheet does not scroll.
    @Test func aLongScopeKeepsTheWindowOnTheScreen() throws {
        let folders = (1...8).map { "/Users/example/code/project-\($0)" }
        let question = RightsQuestion(space: "Board", description: nil, rights: ["state"], scope: .folders(folders), missing: [], folder: nil)
        let shown = labels(in: try #require(Ask.rights(question, home: home).sheet.contentView)).map(\.stringValue)
        #expect(shown.filter { $0.hasPrefix("~/code/project-") }.count == 6 && shown.contains("and 2 more"))
    }

    /// A request in words: its effect by the tool's kind and the space, in the mockup's words, how long ago it was
    /// asked by an injected clock, its place in the queue, and who asks.
    @Test func aRequestSaysItsEffectAgeAndWho() {
        #expect(Words.effect("Bash", space: "My agents") == "It will run one command in the My agents space.")
        #expect(Words.effect("commandExecution", space: nil) == "It will run one command.")
        #expect(Words.effect("Edit", space: "Oracle") == "It will change files in the Oracle space.")
        #expect(Words.effect("Edit", space: nil) == "It will change files.")
        #expect(Words.effect("permissions", space: "Oracle") == "It will change what it may do without asking you.")
        #expect(Words.effect("WebFetch", space: "Oracle") == "It will use WebFetch in the Oracle space.")
        #expect(Words.effect(nil, space: "Oracle") == "It needs your permission to go on.")

        let now = ISO8601DateFormatter().date(from: "2026-10-23T18:20:00Z")!
        #expect(Words.age("2026-10-23T18:19:30Z", now: now) == "just now")
        #expect(Words.age("2026-10-23T18:21:00Z", now: now) == "just now", "a clock a little ahead is not a negative age")
        #expect(Words.age("2026-10-23T18:17:00Z", now: now) == "asked 3 min ago")
        #expect(Words.age("2026-10-23T17:20:00Z", now: now) == "asked 1 hour ago")
        #expect(Words.age("2026-10-23T15:05:00Z", now: now) == "asked 3 hours ago")
        #expect(Words.age("not a date", now: now) == nil, "an unknown age is left out, never guessed")

        #expect(Words.position(0, of: 3) == "1 of 3" && Words.position(2, of: 3) == "3 of 3" && Words.position(0, of: 1) == nil)

        #expect(Words.who(space: "My agents", assistant: true, name: nil, age: "asked 3 min ago") == "My agents · its assistant · asked 3 min ago")
        #expect(Words.who(space: nil, assistant: true, name: nil, age: "just now") == "your assistant · just now")
        #expect(Words.who(space: "Project watch", assistant: false, name: "watcher", age: nil) == "Project watch · “watcher”")
        #expect(Words.who(space: nil, assistant: false, name: nil, age: nil) == "")
    }

    /// The quit alert's four titles, in the singular and the plural, and its last line saying what quitting does.
    @Test func quittingSaysWhatWaitsAndWorks() {
        #expect(Words.quit(requests: 1, working: 2).title == "1 request waits and 2 assistants are working. Quit anyway?")
        #expect(Words.quit(requests: 2, working: 1).title == "2 requests wait and 1 assistant is working. Quit anyway?")
        #expect(Words.quit(requests: 1, working: 0).title == "1 request waits for you. Quit anyway?")
        #expect(Words.quit(requests: 3, working: 0).title == "3 requests wait for you. Quit anyway?")
        #expect(Words.quit(requests: 0, working: 1).title == "1 assistant is working. Quit anyway?")
        #expect(Words.quit(requests: 0, working: 2).title == "2 assistants are working. Quit anyway?")
        #expect(Words.quit(requests: 1, working: 2).fine
                == "Quitting denies this request. It stops those working in the middle of a turn; what they already changed stays.")
        #expect(Words.quit(requests: 2, working: 0).fine == "Quitting denies these requests.")
        #expect(Words.quit(requests: 0, working: 1).fine == "It stops the one working in the middle of a turn; what it already changed stays.")
    }

    func labels(in view: NSView) -> [NSTextField] {
        ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(labels(in:))
    }
}
