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
        var agent = Agent(id: "a1", kind: "claude", origin: "elsewhere")
        #expect(Info.doing(agent) == "state unknown", "what no source gives is said, never guessed")
        for (state, words) in [("working", "working"), ("waiting", "waits for you"), ("idle", "idle"), ("error", "stopped on an error")] {
            agent.state = state
            #expect(Info.doing(agent) == words)
        }
        agent.alive = false
        #expect(Info.doing(agent) == "ended")
    }

    @Test func thePanelOpensAtOnce() throws {
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
        shell.window.layoutIfNeeded()
        #expect(shell.inspector.viewController.view.frame.width == 320 && shell.center.frame.width == 1200 - 236 - 320)
        info.close()
        shell.window.layoutIfNeeded()
        #expect(!shell.infoShown && shell.center.frame.width == 1200 - 236)
    }
}
