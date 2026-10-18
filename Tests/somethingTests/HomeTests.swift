// Home, the space card and the start, in a throwaway home: a right switched off in the card reaches the open space
// as a `granted` event and the bridge refuses from then on; "Ask again" asks; Make default, Show in Finder and
// "Make a copy"; the start makes its folders and chooses the default space, `agents`, or Home. No window is shown.
import AppKit
import Foundation
import SomethingCore
import Testing
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing)) struct HomeTests {
    init() { NSApplication.shared.setActivationPolicy(.prohibited) }

    /// Home on the test's home, whose root stands for share/: its examples folder and its template may not exist.
    func home(_ test: Home, _ ask: FakeAsk) -> something.Home {
        let home = something.Home(places: test.places, share: test.root, ask: ask)
        home.reveal = { _ in Issue.record("Show in Finder was not expected") }
        home.reload()
        return home
    }

    /// A grant as the rights window leaves it, for a declaration of `declared`.
    func answered(declared: [String], granted: [String]) -> Grant {
        var declaration = Declaration(name: "invented")
        declaration.rights = declared
        var grant = Grant(declared: Asked(declaration), at: "2026-10-17T09:00:00Z")
        grant.granted = granted
        return grant
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
        try await ready(window)
        #expect(try await run(window, "await something.store.set('word', 'invented'); return await something.store.get('word')") as? String == "invented")

        let home = home(test, ask)
        home.card.window = { $0 == "notes" ? window : nil }
        home.table.selectRowIndexes([0], byExtendingSelection: false)
        #expect(home.card.space == space)
        #expect(home.card.rights.map(\.right) == ["state", "store"] && home.card.rights.allSatisfy { $0.standing == .allowed })

        home.card.set("store", allowed: false)
        for _ in 0..<100 where try await run(window, "return heard.length") as? Int != 1 { await wait(0.05) }
        #expect(try await run(window, "return heard") as? [String] == ["state"])
        #expect(try await run(window, "return something.granted.refused") as? [String] == ["store"])
        #expect(try await run(window, "try { await something.store.get('word') } catch (e) { return e.code }") as? String == "RIGHT_NOT_GRANTED")
        let grant = try #require(try AppFile.read(test.places.grants).spaces["notes"])
        #expect(grant.granted == ["state"] && grant.refused == ["store"])
        #expect(home.card.rights.map(\.standing) == [.allowed, .refused])

        // Switched on again: the memory answers again, with what it kept.
        home.card.set("store", allowed: true)
        for _ in 0..<100 where try await run(window, "return heard.length") as? Int != 2 { await wait(0.05) }
        #expect(try await run(window, "return await something.store.get('word')") as? String == "invented")
        #expect(ask.questions.count == 1, "a switch is the person's answer: nothing more is asked")
    }

    @Test func askAgainClearsTheRefusalsOnlyAndAsksThemNow() async throws {
        let test = Home(), ask = FakeAsk()
        defer { test.remove() }
        let space = try test.space("board", page(#"{"contract": 1, "rights": ["state", "store"]}"#, "<script>window.done = true</script>"))
        let window = try await test.window(space, ask)
        defer { window.close() }
        ask.answer = { _ in RightsAnswer(allowed: ["state"], refused: ["store"], folder: nil, remap: [:]) }
        window.load()
        let home = home(test, ask)
        home.card.window = { _ in window }
        home.table.selectRowIndexes([0], byExtendingSelection: false)
        #expect(home.card.rights.map(\.standing) == [.allowed, .refused])

        // "Not now": what was allowed stays, in the file and in the open space; the refusal is no longer remembered.
        ask.answer = nil
        home.card.askAgain()
        #expect(ask.questions.map(\.rights) == [["state", "store"], ["store"]])
        let grant = try #require(try AppFile.read(test.places.grants).spaces["board"])
        #expect(grant.granted == ["state"] && grant.refused.isEmpty)
        #expect(window.granted.rights == ["state"])
        #expect(home.card.rights.map(\.standing) == [.allowed, .notAnswered(inForce: [])])

        // Answered: the card shows the new answer at once.
        ask.answer = { RightsAnswer(allowed: $0, refused: [], folder: nil, remap: [:]) }
        home.card.askAgain()
        #expect(home.card.rights.map(\.standing) == [.allowed, .allowed])
        #expect(window.granted.rights == ["state", "store"])
    }

    @Test func aSwitchChangesOnlyItsOwnRight() throws {
        let test = Home(), ask = FakeAsk()
        defer { test.remove() }
        // "send" was allowed; the space now declares one right per kind, and a launch it was never asked about.
        try test.space("shop", page(#"{"contract": 1, "rights": ["send:claude", "send:codex", "launch:claude"]}"#, ""))
        var file = AppFile()
        let grant = answered(declared: ["send"], granted: ["send"])
        file.spaces["shop"] = grant
        try file.write(test.places.grants)
        let home = home(test, ask)
        home.table.selectRowIndexes([0], byExtendingSelection: false)
        #expect(home.card.rights.map(\.standing) == [.allowed, .allowed, .notAnswered(inForce: [])])

        home.card.set("send:claude", allowed: false)
        let after = try #require(try AppFile.read(test.places.grants).spaces["shop"])
        #expect(after.granted == ["send:codex"] && after.refused == ["send:claude"])
        #expect(home.card.rights.map(\.standing) == [.refused, .allowed, .notAnswered(inForce: [])])
    }

    @Test func aWiderRightDeclaredLaterShowsWhatIsInForce() throws {
        let test = Home(), ask = FakeAsk()
        defer { test.remove() }
        try test.space("shop", page(#"{"contract": 1, "rights": ["send"]}"#, ""))
        var file = AppFile()
        let grant = answered(declared: ["send:claude"], granted: ["send:claude"])
        file.spaces["shop"] = grant
        try file.write(test.places.grants)
        let home = home(test, ask)
        home.table.selectRowIndexes([0], byExtendingSelection: false)
        #expect(home.card.rights.map(\.standing) == [.notAnswered(inForce: ["send:claude"])], "neither on nor off: not asked yet")
    }

    @Test func aGrantsFileThatDoesNotReadIsSaid() async throws {
        let test = Home(), ask = FakeAsk()
        defer { test.remove() }
        let space = try test.space("notes", page(#"{"contract": 1, "rights": ["store"]}"#, "<script>window.done = true</script>"))
        let window = try await test.window(space, ask)
        defer { window.close() }
        window.load()
        #expect(window.granted.rights == ["store"])
        try "not json".write(to: test.places.grants, atomically: true, encoding: .utf8)

        let home = home(test, ask)
        home.reload()
        #expect(ask.told.count == 1 && ask.told[0].hasPrefix("The grants in"), "said once, not at each reload: \(ask.told)")
        #expect(FirstRun.first(test.places) == nil, "no default can be read: Home")
        home.table.selectRowIndexes([0], byExtendingSelection: false)
        #expect(home.card.problem?.hasPrefix("The grants in") == true && home.card.rights.isEmpty)

        window.regrant()
        #expect(window.granted.rights == ["store"], "the rights in force stay")
        #expect(ask.told.count == 2)
    }

    @Test func aSwitchAppliesOnlyTheDeclarationThePersonWasAsked() async throws {
        let test = Home(), ask = FakeAsk()
        defer { test.remove() }
        let space = try test.space("notes", page(#"{"contract": 1, "rights": ["state", "store"], "agents": {"folders": []}}"#,
                                                 "<script>window.done = true</script>"))
        let window = try await test.window(space, ask)
        defer { window.close() }
        window.load()
        // The file widens its scope; the reload that would ask has not run yet.
        try test.space("notes", page(#"{"contract": 1, "rights": ["state", "store"], "agents": {"see": "all"}}"#, ""))
        let home = home(test, ask)
        home.card.window = { _ in window }
        home.table.selectRowIndexes([0], byExtendingSelection: false)
        home.card.set("store", allowed: false)
        #expect(window.granted.rights == ["state"] && window.granted.agents == .folders([]))
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
        let titles = { home.card.view.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue } }
        #expect(!titles().contains("Readers"), "no reader has a note: the section is not shown")
        home.card.kinds = {
            ["omp": Kind(launch: false, installed: true, tested: "18.8.6", seen: "18.9.0", reader: "changed", note: "OMP's files changed shape."),
             "claude": Kind(launch: true, installed: true, tested: "2.1.299", seen: nil, reader: "ok", note: nil)]
        }
        home.reload()
        #expect(home.card.journal.count == 100)
        // The state no longer has a1: the line names its kind alone (WordsTests check the words).
        #expect(home.card.journal.last?.hasSuffix("\twrote to Claude Code: “Invented message 119.”") == true, "\(home.card.journal.last ?? "")")
        #expect(home.card.notes == ["OMP: OMP's files changed shape."])
        #expect(titles().contains("Readers"))
    }

    /// Home cannot be made narrower than its list and its card side by side, and it opens at least that large.
    @Test func homeCannotCutItsCard() throws {
        let test = Home()
        defer { test.remove() }
        let window = home(test, FakeAsk()).makeWindow()
        let card = try #require(window.contentView?.subviews.last)
        #expect(window.contentMinSize.width >= card.fittingSize.width + 400)
        let size = try #require(window.contentView).frame.size
        #expect(size.width >= window.contentMinSize.width && size.height >= window.contentMinSize.height)
    }

    /// A space is always selected while there is one, the default first, and the card follows the selection; an empty
    /// list says how to make a first space.
    @Test func homeAlwaysShowsASpaceOrHowToMakeOne() throws {
        let test = Home()
        defer { test.remove() }
        let home = home(test, FakeAsk())
        _ = home.makeWindow()
        home.reload()
        #expect(home.selected == nil && home.list.isHidden && !home.empty.isHidden)
        #expect(home.empty.stringValue.contains("New") && home.empty.stringValue.contains("something new <name>"))
        try test.space("garden", page(nil, ""))
        try test.space("shop", page(nil, ""))
        home.reload()
        #expect(home.selected?.name == "garden" && home.card.space?.name == "garden")
        #expect(!home.list.isHidden && home.empty.isHidden)
        home.table.selectRowIndexes([1], byExtendingSelection: false)
        #expect(home.card.space?.name == "shop")
        var file = try AppFile.read(test.places.grants)
        file.default = "shop"
        try file.write(test.places.grants)
        let again = self.home(test, FakeAsk())
        #expect(again.selected?.name == "shop" && again.card.space?.name == "shop", "the default space is selected first")
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

        // Answers left by a space named game that was deleted in Finder: the copy must not inherit them.
        var file = try AppFile.read(test.places.grants)
        let old = answered(declared: ["store"], granted: ["store"])
        file.spaces["game"] = old
        try file.write(test.places.grants)
        let examples = test.root.appendingPathComponent("examples/game")
        try FileManager.default.createDirectory(at: examples, withIntermediateDirectories: true)
        try page(nil, "<p>An invented game.</p>").write(to: examples.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        home.reload()
        #expect(home.samples.map(\.name) == ["game"])
        home.sampleTable.selectRowIndexes([0], byExtendingSelection: false)
        home.makeACopy()
        #expect(Spaces(root: test.places.spaces).named("game")?.form == .folder)
        #expect(try AppFile.read(test.places.grants).spaces["game"] == nil, "a copy has no grant")
        #expect(try AppFile.read(test.places.grants).default == "today")
        #expect(home.selected?.name == "game")
        home.makeACopy()
        #expect(home.selectedSample?.name == "game")
        #expect(ask.told.count == 1 && ask.told[0].hasPrefix("A space named game already exists"), "\(ask.told)")
    }

    /// New makes the space as `something new` does: the template, and none of the answers a deleted space of the same
    /// name left in the grants file.
    @Test func newMakesASpaceAsTheCommandDoes() throws {
        let test = Home(), ask = FakeAsk()
        defer { test.remove() }
        let template = test.root.appendingPathComponent("template.html")
        try FileManager.default.createDirectory(at: test.root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Home.share.appendingPathComponent("template.html"), to: template)
        let home = home(test, ask)
        var file = AppFile()
        file.spaces["garden"] = answered(declared: ["state"], granted: ["state"])
        try FileManager.default.createDirectory(at: test.places.support, withIntermediateDirectories: true)
        try file.write(test.places.grants)

        home.newChosen()
        #expect(home.spaces.isEmpty, "a cancelled name makes nothing")
        ask.named = "garden"
        home.newChosen()
        let made = try #require(home.selected)
        #expect(made.name == "garden" && made.form == .file)
        #expect(try Data(contentsOf: made.page) == Data(contentsOf: template))
        #expect(try AppFile.read(test.places.grants).spaces["garden"] == nil)
        for wrong in ["Garden", "garden"] {
            ask.named = wrong
            home.newChosen()
            #expect(ask.told.last?.hasPrefix("The space \(wrong) was not made.") == true, "\(ask.told)")
        }
        #expect(home.spaces.map(\.name) == ["garden"])
    }

    @Test func exportAsksForTheDataAndImportStartsWithoutGrants() throws {
        let test = Home(), ask = FakeAsk()
        defer { test.remove() }
        let folder = test.places.spaces.appendingPathComponent("board")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try page(#"{"contract": 1, "rights": ["store"]}"#, "<p>An invented board.</p>").write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try Memory(folder: test.places.data, space: "board").set("seen", ["a1"])
        let saved = test.root.appendingPathComponent("board.something")
        let home = home(test, ask)
        home.table.selectRowIndexes([0], byExtendingSelection: false)

        ask.withData = nil
        ask.saveTo = saved
        home.exportSelected()
        #expect(ask.shown == [["seen"]] && !FileManager.default.fileExists(atPath: saved.path), "cancelled: nothing saved")
        ask.withData = false
        home.exportSelected()
        let without = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: saved)) as? [String: Any])
        #expect(without["data"] is NSNull && without["name"] as? String == "board", "Without data is the default answer")
        ask.withData = true
        home.exportSelected()
        let with = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: saved)) as? [String: Any])
        #expect(with["data"] as? NSDictionary == ["seen": ["a1"]])

        // Answers kept under the name the import will give: the received space must not inherit them.
        var file = try AppFile.read(test.places.grants)
        file.spaces["board-2"] = answered(declared: ["store"], granted: ["store"])
        try file.write(test.places.grants)
        ask.chosen = saved
        home.importChosen()
        #expect(ask.told.isEmpty, "\(ask.told)")
        #expect(home.selected?.name == "board-2" && home.selected?.form == .folder)
        #expect(try AppFile.read(test.places.grants).spaces["board-2"] == nil, "an imported space has no grant")
        #expect(try Memory(folder: test.places.data, space: "board-2").get("seen") as? [String] == ["a1"])

        // A grants file that does not read: the grant cannot be dropped, so nothing is written, and that is said.
        try "not json".write(to: test.places.grants, atomically: true, encoding: .utf8)
        let before = try FileManager.default.contentsOfDirectory(atPath: test.places.spaces.path).sorted()
        home.importChosen()
        #expect(ask.told.count == 1 && ask.told.last?.hasPrefix("board.something was not imported. The grants in") == true, "\(ask.told)")
        #expect(try FileManager.default.contentsOfDirectory(atPath: test.places.spaces.path).sorted() == before, "no space left")
        #expect(!FileManager.default.fileExists(atPath: Memory(folder: test.places.data, space: "board-3").file.path))
    }

    @Test func anExportNamesTheLinksItLeftOutAndRefusesALinkedMemory() throws {
        let test = Home(), ask = FakeAsk()
        defer { test.remove() }
        let folder = test.places.spaces.appendingPathComponent("board")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try page(nil, "<p>An invented board.</p>").write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let outside = test.root.appendingPathComponent(".claude.json")
        try #"{"note": "invented"}"#.write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("notes.json"), withDestinationURL: outside)
        let saved = test.root.appendingPathComponent("board.something")
        ask.saveTo = saved
        let home = home(test, ask)
        home.table.selectRowIndexes([0], byExtendingSelection: false)
        home.exportSelected()
        #expect(FileManager.default.fileExists(atPath: saved.path))
        #expect(ask.told == ["board was exported without notes.json: a link to somewhere else is never exported. Replace a link with the file itself to export it."])

        try FileManager.default.removeItem(at: saved)
        try FileManager.default.createDirectory(at: test.places.data, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: Memory(folder: test.places.data, space: "board").file, withDestinationURL: outside)
        home.exportSelected()
        #expect(ask.shown.isEmpty && !FileManager.default.fileExists(atPath: saved.path), "a linked memory is never read")
        #expect(ask.told.count == 2 && ask.told[1].hasPrefix("board was not exported.") && ask.told[1].contains("is a link"), "\(ask.told)")
    }

    @Test func aRefusedImportSaysWhyAndAGoneSpaceLosesItsGrants() throws {
        let test = Home(), ask = FakeAsk()
        defer { test.remove() }
        try test.space("notes", page(nil, ""))
        let home = home(test, ask)
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: Home.share.appendingPathComponent("contract/exports/unsafe-path.json"))) as? [String: Any]
        let chosen = test.root.appendingPathComponent("unsafe.something")
        try JSONSerialization.data(withJSONObject: try #require(fixture?["export"])).write(to: chosen)
        ask.chosen = chosen
        home.importChosen()
        #expect(ask.told.count == 1 && ask.told[0].contains("(IMPORT_UNSAFE_PATH)"), "\(ask.told)")
        #expect(home.spaces.map(\.name) == ["notes"])

        var file = try AppFile.read(test.places.grants)
        file.spaces["notes"] = answered(declared: ["store"], granted: ["store"])
        try file.write(test.places.grants)
        home.reload()
        #expect(try AppFile.read(test.places.grants).spaces["notes"] != nil)
        // Deleted, or renamed, in Finder: the next look forgets its answers, so a new space of that name asks again.
        try FileManager.default.removeItem(at: test.places.spaces.appendingPathComponent("notes.html"))
        // A folder whose index.html is being rewritten, and a spaces folder that is not there, keep their answers.
        let board = test.places.spaces.appendingPathComponent("board")
        try FileManager.default.createDirectory(at: board, withIntermediateDirectories: true)
        file = try AppFile.read(test.places.grants)
        file.spaces["board"] = answered(declared: ["store"], granted: ["store"])
        try file.write(test.places.grants)
        home.reload()
        #expect(try AppFile.read(test.places.grants).spaces.keys.sorted() == ["board"])
        try FileManager.default.removeItem(at: test.places.spaces)
        home.reload()
        #expect(try AppFile.read(test.places.grants).spaces.keys.sorted() == ["board"])
        #expect(ask.told.count == 1, "\(ask.told)")
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
