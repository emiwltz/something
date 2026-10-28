// What the person reads, word for word: a path with ~ and cut between two names, a time in local time, the level
// sheet's answers and New Space's level words. No window is shown.
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

    func time(_ at: String, clock: Locale = Locale(identifier: "en_GB")) -> String {
        Words.time(at, now: now, calendar: calendar, locale: Locale(identifier: "en_GB"), clock: clock).replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test func aTimeIsSaidInLocalTime() {
        #expect(time("2026-10-17T08:00:00Z") == "08:00")
        #expect(time("2026-10-17T08:00:00Z", clock: Locale(identifier: "en_US")) == "8:00 am", "a clock of 12 hours (some systems put a narrow space before am)")
        #expect(time("2026-10-16T08:07:00Z") == "16 Oct 08:07")
        #expect(time("2025-12-31T23:59:00Z") == "31 Dec 2025 23:59")
        #expect(time("not a date") == "not a date", "a date that does not read is shown as it is written")
    }

    /// The level sheet answers the level shown and Run's folder; Allow waits for that folder; a folder is kept only
    /// for Run.
    @Test func theLevelSheetHoldsTheLevelAndRunsFolder() {
        let run = Ask.rights(RightsQuestion(space: "Morning review", description: nil, level: .run, folder: "/Users/example/code/shop"), home: home)
        #expect(run.answer() == RightsAnswer(level: .run, folder: "/Users/example/code/shop") && run.sheet.buttons[1].isEnabled)
        #expect(!Ask.rights(RightsQuestion(space: "Board", description: nil, level: .run, folder: nil), home: home).sheet.buttons[1].isEnabled,
                "Run waits for its folder")
        let watch = Ask.rights(RightsQuestion(space: "Board", description: nil, level: .watch, folder: "/Users/example/code/shop"), home: home)
        #expect(watch.answer() == RightsAnswer(level: .watch, folder: nil) && watch.sheet.buttons[1].isEnabled)
    }

    /// New Space's words pre-set the level, starting before writing before seeing; the agent hears it on a line of its own.
    @Test func aDescriptionPresetsALevel() {
        #expect(Grant.Level.guess("A countdown to Saturday, with what my agents still have to finish before the weekend.") == .watch)
        #expect(Grant.Level.guess("A page that starts a reviewer agent in my shop every morning") == .run)
        #expect(Grant.Level.guess("Let me nudge my agents or send them a note") == .talk)
        #expect(Grant.Level.guess("My reading list") == .none && Grant.Level.guess("Restart my runner, agentless") == .none, "whole words only")
        #expect(Grant.Level.allCases.map(\.title) == ["None", "Watch", "Talk", "Run"])
        #expect(Grant.Level.allCases.map(\.sentence) == ["It shows no agent.", "It sees your agents: their state, folder and last messages.",
                                                          "It sees them and writes to them: send a message, stop one, change its model.",
                                                          "It sees them, writes to them, and starts one in a folder you pick."])
        #expect(Grant.Level.run.line(folder: "/Users/example/code/shop", home: home) == "[something] With your agents: Run, in ~/code/shop.")
        #expect(Grant.Level.watch.line(folder: "/Users/example/code/shop", home: home) == "[something] With your agents: Watch.")
        #expect(AssistantModel.shown("[something] No space is open: the person is on the blank page.\n[something] With your agents: Watch.\nA countdown.")
                == ("on the blank page", "A countdown."), "the conversation shows the person's words only")
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
