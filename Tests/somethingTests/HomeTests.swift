// Home, the space card and the start, in a throwaway home: a right switched off in the card reaches the open space
// as a `granted` event and the bridge refuses from then on; "Ask again" asks; Make default, Show in Finder and
// "Make a copy"; the start makes its folders and chooses the default space, `agents`, or Home. No window is shown.
import AppKit
import Foundation
import SomethingCore
import Testing
@testable import something

@MainActor @Suite(.serialized) struct HomeTests {
    init() { NSApplication.shared.setActivationPolicy(.prohibited) }

    /// Home on the test's home; `examples` is a folder of the test's home, which may not exist.
    func home(_ test: Home, _ ask: FakeAsk) -> something.Home {
        let home = something.Home(places: test.places, examples: test.root.appendingPathComponent("examples"), ask: ask)
        home.reveal = { _ in Issue.record("Show in Finder was not expected") }
        home.reload()
        return home
    }

    @Test func aRevokedRightReachesTheOpenSpace() async throws {
        let test = Home(), ask = FakeAsk()
        defer { test.remove() }
        let space = try test.space("notes", page(#"{"contract": 1, "rights": ["state", "store"]}"#, """
            <script>window.heard = []; something.on("granted", (g) => heard.push(g.rights.join(","))); window.done = true</script>
            """))
        let window = try await test.window(space, ask)
        defer { window.close() }
        window.open()
        try await ready(window.web)
        #expect(try await run(window.web, "await something.store.set('word', 'invented'); return await something.store.get('word')") as? String == "invented")

        let home = home(test, ask)
        home.card.window = { $0 == "notes" ? window : nil }
        home.table.selectRowIndexes([0], byExtendingSelection: false)
        #expect(home.card.space == space)
        #expect(home.card.rights.map(\.right) == ["state", "store"] && home.card.rights.allSatisfy(\.allowed))

        home.card.set("store", allowed: false)
        for _ in 0..<100 where try await run(window.web, "return heard.length") as? Int != 1 { await wait(0.05) }
        #expect(try await run(window.web, "return heard") as? [String] == ["state"])
        #expect(try await run(window.web, "return something.granted.refused") as? [String] == ["store"])
        #expect(try await run(window.web, "try { await something.store.get('word') } catch (e) { return e.code }") as? String == "RIGHT_NOT_GRANTED")
        let grant = try #require(try AppFile.read(test.places.grants).spaces["notes"])
        #expect(grant.granted == ["state"] && grant.refused == ["store"])
        #expect(home.card.rights.map(\.allowed) == [true, false])

        // Switched on again: the memory answers again, with what it kept.
        home.card.set("store", allowed: true)
        for _ in 0..<100 where try await run(window.web, "return heard.length") as? Int != 2 { await wait(0.05) }
        #expect(try await run(window.web, "return await something.store.get('word')") as? String == "invented")
        #expect(ask.questions.count == 1, "a switch is the person's answer: nothing more is asked")
    }

    @Test func askAgainForgetsTheAnswersAndAsksNow() async throws {
        let test = Home(), ask = FakeAsk()
        defer { test.remove() }
        let space = try test.space("board", page(#"{"contract": 1, "rights": ["store"]}"#, "<script>window.done = true</script>"))
        let window = try await test.window(space, ask)
        defer { window.close() }
        window.open()
        let home = home(test, ask)
        home.card.window = { _ in window }
        home.table.selectRowIndexes([0], byExtendingSelection: false)
        #expect(home.card.rights.count == 1)
        ask.answer = nil
        home.card.askAgain()
        #expect(ask.questions.map(\.rights) == [["store"], ["store"]])
        #expect(try AppFile.read(test.places.grants).spaces["board"] == nil)
        #expect(home.card.rights.isEmpty, "a space not answered has no switch")
        #expect(window.granted.rights.isEmpty)
    }

    @Test func theCardShowsTheJournalAndTheReadersNotes() throws {
        let test = Home(), ask = FakeAsk()
        defer { test.remove() }
        try test.space("board", page(nil, ""))
        let journal = Journal(folder: test.places.journals)
        for index in 0..<120 {
            try journal.append(JournalLine(at: "2026-10-17T09:00:00Z", action: "send", agent: "a1", kind: "claude", when: "next",
                                           text: "Invented message \(index).", result: "ok"), space: "board")
        }
        let home = home(test, ask)
        home.card.kinds = {
            ["omp": Kind(launch: false, installed: true, tested: "18.8.6", seen: "18.9.0", reader: "changed", note: "OMP's files changed shape."),
             "claude": Kind(launch: true, installed: true, tested: "2.1.299", seen: nil, reader: "ok", note: nil)]
        }
        home.table.selectRowIndexes([0], byExtendingSelection: false)
        #expect(home.card.journal.count == 100)
        #expect(home.card.journal.last == "2026-10-17T09:00:00Z  send claude a1 next  ok  “Invented message 119.”")
        #expect(home.card.notes == ["OMP: OMP's files changed shape."])
    }

    @Test func makeDefaultShowInFinderAndCopies() throws {
        let test = Home(), ask = FakeAsk()
        defer { test.remove() }
        try test.space("agents", page(nil, ""))
        try test.space("today", page(#"{"contract": 1, "title": "Today"}"#, ""))
        let home = home(test, ask)
        #expect(home.spaces.map(\.name) == ["agents", "today"])
        #expect(home.samples.isEmpty, "there are no examples yet: the section shows nothing")
        home.table.selectRowIndexes([1], byExtendingSelection: false)
        home.makeDefault()
        #expect(try AppFile.read(test.places.grants).default == "today" && home.preferred == "today")
        #expect(home.selected?.name == "today", "the selection is kept")
        var revealed: [URL] = []
        home.reveal = { revealed.append($0) }
        home.showInFinder()
        #expect(revealed == [test.places.spaces.appendingPathComponent("today.html")])

        let examples = test.root.appendingPathComponent("examples/game")
        try FileManager.default.createDirectory(at: examples, withIntermediateDirectories: true)
        try page(nil, "<p>An invented game.</p>").write(to: examples.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        home.reload()
        #expect(home.samples.map(\.name) == ["game"])
        home.sampleTable.selectRowIndexes([0], byExtendingSelection: false)
        home.makeACopy()
        #expect(Spaces(root: test.places.spaces).named("game")?.form == .folder)
        #expect(home.selected?.name == "game")
        home.makeACopy()
        #expect(home.selectedSample?.name == "game")
        #expect(ask.told.count == 1 && ask.told[0].hasPrefix("A space named game already exists"), "\(ask.told)")
    }

    @Test func theStartMakesItsFoldersAndChoosesWhatToShow() throws {
        let test = Home()
        defer { test.remove() }
        try FirstRun.prepare(test.places)
        for folder in [test.places.spaces, test.places.data] {
            #expect(FileManager.default.fileExists(atPath: folder.path), "\(folder.path)")
            #expect(folder.path.hasPrefix(test.root.path))
        }
        try FirstRun.prepare(test.places)
        #expect(FirstRun.first(test.places) == nil, "no space: Home")
        try test.space("agents", page(nil, ""))
        #expect(FirstRun.first(test.places)?.name == "agents", "agents while it is the only space")
        try test.space("notes", page(nil, ""))
        #expect(FirstRun.first(test.places) == nil, "two spaces and no default: Home")
        var file = AppFile()
        file.default = "notes"
        try file.write(test.places.grants)
        #expect(FirstRun.first(test.places)?.name == "notes")
        file.default = "gone"
        try file.write(test.places.grants)
        #expect(FirstRun.first(test.places) == nil, "a default that names no space is passed over")
    }
}
