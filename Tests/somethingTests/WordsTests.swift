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

    @Test func theRightsWindowTicksEveryRightAndAllowsFirst() throws {
        let question = RightsQuestion(space: "Morning review", description: nil, rights: ["state", "store"], scope: nil, missing: [],
                                      folder: FolderQuestion(declared: "~/code/shop", found: "/Users/example/code/shop"))
        let window = Ask.rights(question, home: home)
        #expect(window.alert.buttons.map(\.title) == ["Allow", "Not now"])
        #expect(window.alert.buttons[1].keyEquivalent == "\u{1b}", "Escape is Not now")
        #expect(window.alert.buttons[0].keyEquivalent == "", "Return does not allow every ticked right unread")
        #expect(window.answer() == RightsAnswer(allowed: ["state", "store"], refused: [], folder: "/Users/example/code/shop", remap: [:]))
        let paths = labels(in: try #require(window.alert.accessoryView)).filter { $0.toolTip != nil }
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

    /// Past six folders, the scope says how many more, all of them in a tooltip: an alert does not scroll.
    @Test func aLongScopeKeepsTheWindowOnTheScreen() throws {
        let folders = (1...8).map { "/Users/example/code/project-\($0)" }
        let question = RightsQuestion(space: "Board", description: nil, rights: ["state"], scope: .folders(folders), missing: [], folder: nil)
        let shown = labels(in: try #require(Ask.rights(question, home: home).alert.accessoryView)).map(\.stringValue)
        #expect(shown.filter { $0.hasPrefix("~/code/project-") }.count == 6 && shown.contains("and 2 more"))
    }

    func labels(in view: NSView) -> [NSTextField] {
        ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(labels(in:))
    }
}
