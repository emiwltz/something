// Info, docked (X5.1): what its Space part says (the size of a folder space counted over its files, its last change),
// what an agent it shows is doing, the dates' words, and the panel that opens and closes at once beside an empty
// window. A level reaching the open space is LibraryTests'; the drawn panel is x5-1's.
import AppKit
import Foundation
import SomethingCore
import Testing
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-info-")) struct InspectorTests {
    init() { NSApplication.shared.setActivationPolicy(.prohibited) }

    @Test func sizeCountsAFolderSpaceAndChangedIsItsNewestFile() throws {
        let test = Home(prefix: "something-info-")
        defer { test.remove() }
        let folder = test.places.spaces.appendingPathComponent("atlas")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("maps"), withIntermediateDirectories: true)
        try page(#"{"contract": 1, "title": "Atlas", "description": "An invented atlas."}"#, "").write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try String(repeating: "x", count: 1_500).write(to: folder.appendingPathComponent("maps/north.svg"), atomically: true, encoding: .utf8)
        try "hidden".write(to: folder.appendingPathComponent(".cache"), atomically: true, encoding: .utf8)
        let made = Date(timeIntervalSince1970: 1_791_000_000), changed = Date(timeIntervalSince1970: 1_792_000_000)
        try FileManager.default.setAttributes([.modificationDate: changed], ofItemAtPath: folder.appendingPathComponent("maps/north.svg").path)
        try FileManager.default.setAttributes([.modificationDate: made], ofItemAtPath: folder.appendingPathComponent("index.html").path)
        let space = try #require(Spaces(root: test.places.spaces).named("atlas"))
        let info = Info(places: test.places, ask: FakeAsk())
        info.show(space)
        let size = try #require(info.size)
        #expect(size.files == 2 && size.bytes > 1_500, "the hidden file is not counted: \(size)")
        #expect(info.changed == changed && info.about == "An invented atlas." && info.level == Grant.Level.none)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date(timeIntervalSince1970: 1_792_693_200), earlier = now.addingTimeInterval(-3_600)
        let hour = Info.day(earlier, now: now, time: true).dropFirst("Today, ".count)
        #expect(Info.weight(size, form: .folder, changed: nil, now: now).hasSuffix(" · 2 files"))
        #expect(Info.weight(Size(bytes: 14_000, files: 1), form: .file, changed: earlier, now: now) == "14 KB · one file · changed today, \(hour)")
        info.show(nil)
        #expect(info.space == nil && info.size == nil && info.changed == nil && info.shown.isEmpty)
    }

    @Test func theDatesAndWhatAnAgentDoes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = Date(timeIntervalSince1970: 1_792_693_200)   // 22 Oct 2026, 18:20 UTC
        #expect(Info.day(now.addingTimeInterval(-3_600), now: now, time: true, calendar: calendar) == "Today, 17:20")
        #expect(Info.day(now.addingTimeInterval(-86_400), now: now, calendar: calendar) == "Yesterday")
        #expect(Info.day(now.addingTimeInterval(-14 * 86_400), now: now, calendar: calendar) == "8 Oct")
        #expect(Info.day(now.addingTimeInterval(-365 * 86_400), now: now, calendar: calendar) == "22 Oct 2025")
    }

    /// One reading of an agent: each phase, its word and its eyes, what no source gives said as such.
    @Test func anAgentHasOneReading() {
        let runs = RunsIn { _ in [] }
        func reading(_ origin: String = "elsewhere", kind: String = "claude", alive: Bool?, state: String, thread: String? = "t1", resume: Bool = false) -> AgentReading {
            var agent = Agent(id: "a1", kind: kind, origin: origin)
            (agent.alive, agent.state, agent.thread, agent.can.resume) = (alive, state, thread, resume)
            return AgentReading(agent, thread: nil, runs: runs)
        }
        let table: [(AgentReading, AgentReading.Phase, String)] = [
            (reading("launched", alive: true, state: "working"), .here, "Working"),
            (reading("launched", alive: true, state: "waiting"), .here, "Waiting for You"),
            (reading("launched", alive: true, state: "idle"), .here, "Idle"),
            (reading("launched", alive: true, state: "interrupted"), .here, "Idle"),
            (reading("launched", alive: true, state: "error"), .here, "Can’t Tell"),
            (reading("launched", alive: false, state: "done"), .asleep, "Asleep"),
            (reading("launched", alive: false, state: "done", thread: nil), .ended, "Ended"),
            (reading("launched", kind: "pi", alive: false, state: "done"), .ended, "Ended"),
            (reading(alive: true, state: "idle"), .away, "Idle"),
            (reading(alive: true, state: "unknown"), .away, "Can’t Tell"),
            (reading(alive: false, state: "done", resume: true), .asleep, "Asleep"),
            (reading(alive: false, state: "done"), .ended, "Ended"),
            (reading(alive: nil, state: "idle", resume: true), .seen, "Can’t Tell"),
            (reading(alive: nil, state: "done"), .seen, "Can’t Tell"),
            (reading(kind: "cursor", alive: true, state: "unknown", thread: nil), .seen, "Can’t Tell"),
        ]
        for (reading, phase, word) in table {
            #expect((reading.phase, reading.word) == (phase, word), "\(reading.agent.origin) \(String(describing: reading.agent.alive)) \(reading.agent.state ?? "")")
        }
        #expect(reading(alive: nil, state: "idle", resume: true).continues, "Can't Tell, and Continue still offered: its program refuses a second writer")
        #expect(!reading("launched", alive: true, state: "idle").continues && reading("launched", alive: false, state: "done").continues)
        #expect(Set(Sign.State.allCases.map(\.word)) == ["Working", "Waiting for You", "Idle", "Asleep", "Ended", "Can’t Tell"], "one list")
    }

    /// Its title: the reader's, else the person's first words; never the folder's name that stands in for it.
    @Test func anAgentGoesByItsTitle() {
        var agent = Agent(id: "claude-1", kind: "claude", origin: "launched")
        (agent.name, agent.folder, agent.alive, agent.thread) = ("shop", "/Users/example/code/shop", true, "t1")
        let said = { (title: String?, items: [Item]) in
            AgentReading(agent, thread: AgentThread(id: "t1", agent: "claude-1", title: title, started: nil,
                                                    turns: [Turn(id: "u1", state: "done", started: nil, ended: nil, items: items)]), runs: RunsIn { _ in [] })
        }
        let words = Item(id: "m1", kind: "message", author: "person", text: "Fix the cart total\nand the rest", at: "2026-10-19T09:00:00Z")
        #expect((said("Login form", [words]).title, said("Login form", [words]).named) == ("Login form", true))
        #expect(said(nil, [words]).title == "Fix the cart total" && said("shop", [words]).title == "Fix the cart total")
        #expect(said(nil, [Item(id: "m2", kind: "message", author: "person", text: String(repeating: "a", count: 70), at: "2026-10-19T09:00:00Z")]).title.count == 59)
        let none = AgentReading(agent, thread: nil, runs: RunsIn { _ in [] })
        #expect((none.title, none.named, none.program, none.talked, none.tag) == ("Claude Code", false, "Claude Code", false, "In something"))
        #expect(AgentReading(agent, thread: nil, known: "Login form", runs: RunsIn { _ in [] }).title == "Login form", "a title read once stays")
        #expect(none.key == "claude:t1")
    }

    /// Where it runs: the outermost app of the nearest ancestor in one, read once per process; nothing guessed.
    @Test func anAgentRunsInTheAppItsParentsSay() {
        var asked = 0
        var chains: [Int32: [String]] = [
            10: ["/opt/homebrew/bin/claude", "/usr/bin/login", "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", "/sbin/launchd"],
            11: ["/Users/example/.local/bin/claude", "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper", "/sbin/launchd"],
            12: ["/opt/homebrew/bin/codex", "/opt/homebrew/bin/tmux", "/sbin/launchd"],
        ]
        let runs = RunsIn { asked += 1; return chains[$0] ?? [] }
        func app(_ pid: Int?) -> String? {
            var agent = Agent(id: "a\(pid ?? 0)", kind: "claude", origin: "elsewhere")
            agent.pid = pid
            return runs.app(of: agent).map(RunsIn.name)
        }
        #expect(app(10) == "Terminal" && app(11) == "Claude", "past a root login; a helper's app is part of its app")
        #expect(app(12) == nil && app(nil) == nil && app(99) == nil, "a server launchd holds, no process, a process gone")
        chains[10] = []
        #expect(app(10) == "Terminal" && asked == 4, "read once while it runs")
        var other = Agent(id: "a10", kind: "claude", origin: "elsewhere")
        other.pid = 11
        runs.keep([other])
        #expect(app(10) == nil, "a process no longer shown is forgotten")
        var here = Agent(id: "claude-1", kind: "claude", origin: "launched")
        (here.alive, here.pid) = (true, 10)
        #expect(AgentReading(here, thread: nil, runs: runs).tag == "In something" && asked == 5, "no walk for one of something's own")
    }

    @Test func thePanelOpensAtOnce() async throws {
        let test = Home(prefix: "something-info-")
        defer { test.remove() }
        try test.space("board", page(#"{"contract": 1, "title": "Board"}"#, ""))
        let library = Library(places: test.places, ask: FakeAsk(), share: Home.share), info = Info(places: test.places, ask: FakeAsk())
        library.relist()
        let shell = Shell(library: library, info: info, assistant: AssistantModel(engine: test.engine(), places: test.places), autosave: false)
        defer { shell.window.close() }
        info.show(library.entry("board")?.space)
        info.content = .history
        shell.showInfo(true)
        #expect(shell.infoShown && info.content == .info, "⌘I opens Info, whatever the panel held")
        // Default's sizes: read in Stage's drawing turn, which no size test of another suite holds at Large meanwhile.
        await Stage.alone {
            shell.window.layoutIfNeeded()
            #expect(shell.inspector.viewController.view.frame.width == 320 && shell.center.frame.width == 1200 - 236 - 320)
            info.close()
            shell.window.layoutIfNeeded()
            #expect(!shell.infoShown && shell.center.frame.width == 1200 - 236)
        }
    }
}
