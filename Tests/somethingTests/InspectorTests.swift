// Info, docked (W4): what About says of a space (the size of a folder space counted over its files, the creation date,
// the last change, the group from the preferences), the rights in the panel's words with when they were last answered,
// the assistant's sentence, the dates' words, and the panel that opens and closes at once beside an empty window. A
// switch reaching the open space and the activity being the journal are LibraryTests'; the drawn panel is b4's.
import AppKit
import Foundation
import SomethingCore
import Testing
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-info-")) struct InspectorTests {
    init() { NSApplication.shared.setActivationPolicy(.prohibited) }

    @Test func sizeCountsAFolderSpaceAndMadeIsTheCreationDate() throws {
        let test = Home(prefix: "something-info-")
        defer { test.remove() }
        let folder = test.places.spaces.appendingPathComponent("atlas")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("maps"), withIntermediateDirectories: true)
        try page(#"{"contract": 1, "title": "Atlas"}"#, "").write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try String(repeating: "x", count: 1_500).write(to: folder.appendingPathComponent("maps/north.svg"), atomically: true, encoding: .utf8)
        try "hidden".write(to: folder.appendingPathComponent(".cache"), atomically: true, encoding: .utf8)
        let made = Date(timeIntervalSince1970: 1_791_000_000), changed = Date(timeIntervalSince1970: 1_792_000_000)
        try FileManager.default.setAttributes([.creationDate: made], ofItemAtPath: folder.path)
        try FileManager.default.setAttributes([.modificationDate: changed], ofItemAtPath: folder.appendingPathComponent("maps/north.svg").path)
        try FileManager.default.setAttributes([.modificationDate: made], ofItemAtPath: folder.appendingPathComponent("index.html").path)
        let space = try #require(Spaces(root: test.places.spaces).named("atlas"))
        let info = Info(places: test.places, ask: FakeAsk())
        info.show(space)
        let size = try #require(info.size)
        #expect(size.files == 2 && size.bytes > 1_500, "the hidden file is not counted: \(size)")
        #expect(Info.weight(size, form: .folder).hasSuffix(" · 2 files") && Info.weight(Size(bytes: 12_000, files: 1), form: .file) == "12 KB · one page")
        #expect(info.made == made && info.changed == changed, "the newest of its files")
        #expect(info.rights.isEmpty && info.asksNothing && info.answered == nil)
        info.show(nil)
        #expect(info.space == nil && info.size == nil && info.made == nil)
    }

    @Test func theRightsSayWhenTheyWereLastAnswered() throws {
        let test = Home(prefix: "something-info-")
        defer { test.remove() }
        let space = try test.space("board", page(#"{"contract": 1, "rights": ["state", "launch:claude"]}"#, ""))
        var declaration = Declaration(name: "board")
        declaration.rights = ["state", "launch:claude"]
        var grant = Grant(declared: Asked(declaration), at: "2026-10-09T09:00:00Z")
        (grant.granted, grant.refused) = (["state"], ["launch:claude"])
        var file = AppFile()
        file.spaces["board"] = grant
        try file.write(test.places.grants)
        let info = Info(places: test.places, ask: FakeAsk())
        info.clock = { Date(timeIntervalSince1970: 1_792_693_200) }
        info.show(space)
        #expect(info.rights.map(\.standing) == [.allowed, .refused] && info.answered == iso8601.date(from: "2026-10-09T09:00:00Z"))
        #expect(Info.words(for: "launch:claude") == ("Start Claude Code", "Launch one in a folder you choose."))
        #expect(Info.words(for: "launch:pi").detail.hasSuffix("pi runs commands and edits files without asking you first."))
        #expect(Info.words(for: "send").name == "Write to your agents" && Info.words(for: "store").name == "Remember things")
        info.set("launch:claude", allowed: true)
        #expect(info.rights.map(\.standing) == [.allowed, .allowed] && info.answered == info.clock(), "a switch is an answer, dated")
    }

    @Test func theDatesAndTheSentences() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = Date(timeIntervalSince1970: 1_792_693_200)   // 22 Oct 2026, 18:20 UTC
        #expect(Info.day(now.addingTimeInterval(-3_600), now: now, time: true, calendar: calendar) == "Today, 17:20")
        #expect(Info.day(now.addingTimeInterval(-86_400), now: now, calendar: calendar) == "Yesterday")
        #expect(Info.day(now.addingTimeInterval(-14 * 86_400), now: now, calendar: calendar) == "8 Oct")
        #expect(Info.day(now.addingTimeInterval(-365 * 86_400), now: now, calendar: calendar) == "22 Oct 2025")
        #expect(Info.sentence(.unknown) == "something cannot read its state right now, so it does not guess.")
        #expect(Sign.State.allCases.allSatisfy { !Info.sentence($0).isEmpty })
    }

    @Test func theGroupIsThePreferencesAndThePanelOpensAtOnce() throws {
        let test = Home(prefix: "something-info-")
        defer { test.remove() }
        try test.space("board", page(#"{"contract": 1, "title": "Board"}"#, ""))
        let library = Library(places: test.places, ask: FakeAsk(), share: Home.share), info = Info(places: test.places, ask: FakeAsk())
        library.relist()
        library.preferences.move("board", to: "Notes")
        let shell = Shell(library: library, info: info, assistant: AssistantModel(engine: test.engine(), places: test.places), autosave: false)
        defer { shell.window.close() }
        #expect(library.preferences.group(of: "board") == "Notes")
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
