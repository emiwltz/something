// The sidebar's list and Info, in a throwaway home: the spaces sorted by title with the pages that are not spaces yet,
// the folder watched, the last space open remembered (and 1.0's default read once), Show in Finder, Move to Trash
// into the test's own home, export and import; a right switched off in Info reaches the open space as a `granted`
// event and the bridge refuses from then on, "Ask Again" asks, and the activity is the journal, newest first.
// No window is shown, and nothing reaches the person's Finder or Trash.
import AppKit
import Foundation
import SomethingCore
import Testing
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-library-")) struct LibraryTests {
    init() { NSApplication.shared.setActivationPolicy(.prohibited) }

    /// The library of the test's home; its Trash is the folder `Trash` of that home, and Finder is never opened.
    func library(_ test: Home, _ ask: FakeAsk) -> Library {
        let library = Library(places: test.places, ask: ask, share: Home.share)
        library.reveal = { _ in Issue.record("Show in Finder was not expected") }
        let trash = test.root.appendingPathComponent("Trash")
        library.recycle = { url in
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
        }
        library.relist()
        return library
    }

    /// Info on the test's home, showing `space`, which `view` holds when it is open.
    func info(_ test: Home, _ ask: FakeAsk, _ space: Space?, view: SpaceView? = nil) -> Info {
        let info = Info(places: test.places, ask: ask)
        info.current = { view }
        info.show(space)
        return info
    }

    /// A grant as the rights sheet leaves it, for a declaration of `declared`.
    func answered(declared: [String], granted: [String]) -> Grant {
        var declaration = Declaration(name: "invented")
        declaration.rights = declared
        var grant = Grant(declared: Asked(declaration), at: "2026-10-17T09:00:00Z")
        grant.granted = granted
        return grant
    }

    // MARK: The list

    @Test func theSpacesAreSortedByTitleWithThePagesThatAreNotSpacesYet() throws {
        let test = Home(prefix: "something-library-")
        defer { test.remove() }
        try Library.prepare(test.places)
        let library = library(test, FakeAsk())
        #expect(library.entries.isEmpty, "the sidebar then says: No spaces yet.")
        try test.space("zebra", page(#"{"contract": 1, "title": "apple pie"}"#, ""))
        try test.space("alpha", page(#"{"contract": 1, "title": "Zoo"}"#, ""))
        try test.space("middle", page(#"{"contract": 1, "title": "Éclair"}"#, ""))
        try test.space("draft", page(nil, "<p>Scratch, without a declaration.</p>"))
        library.relist()
        #expect(library.entries.map(\.title) == ["apple pie", "draft", "Éclair", "Zoo"], "case and accents do not change the order")
        #expect(library.entries.map(\.isSpace) == [true, false, true, true])
    }

    /// A space made in the folder, by an agent or in Finder, is listed at the watch's next look, and so is a page
    /// rewritten in place; one removed goes away, and the open one is closed; a spaces folder removed and made again is
    /// still watched.
    @Test func theFolderWatchSeesASpaceComeAndGo() async throws {
        let test = Home(prefix: "something-library-")
        defer { test.remove() }
        try Library.prepare(test.places)
        let library = library(test, FakeAsk())
        var opened: [String?] = []
        library.opened = { opened.append($0) }
        library.watch()
        defer { library.stop() }
        // The watch looks every half second. Each wait gives it ten seconds and ends as soon as it sees: while the
        // other suites start agents and WebKit at once, a 3-core runner's main queue was seen late by more than a
        // second (CI, 19 October 2026), and a clean clone's first run missed three seconds (S12).
        let soon: Double = 10
        try test.space("garden", page(#"{"contract": 1, "title": "Garden"}"#, ""))
        #expect(await wait(soon, until: { library.entries.map(\.id) == ["garden"] }))
        library.select("garden")
        #expect(await wait(soon, until: { opened == ["garden"] }), "the space opens just after it is selected")

        // Rewritten in place, as an editor without an atomic save does: no entry of the folder changes.
        let file = test.places.spaces.appendingPathComponent("garden.html")
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(page(#"{"contract": 1, "title": "Kitchen garden"}"#, "").utf8))
        try handle.close()
        #expect(await wait(soon, until: { library.entries.map(\.title) == ["Kitchen garden"] }))

        try FileManager.default.removeItem(at: file)
        #expect(await wait(soon, until: { library.entries.isEmpty && opened == ["garden", nil] }))
        #expect(library.selection == nil)

        try FileManager.default.removeItem(at: test.places.spaces)
        try Library.prepare(test.places)
        try test.space("pond", page(#"{"contract": 1, "title": "Pond"}"#, ""))
        #expect(await wait(soon, until: { library.entries.map(\.id) == ["pond"] }))

        // While nobody can see the window, the folder is not looked at; it is again when the window shows.
        library.watching(false)
        try test.space("reeds", page(#"{"contract": 1, "title": "Reeds"}"#, ""))
        await wait(1.5)
        #expect(library.entries.map(\.id) == ["pond"])
        library.watching(true)
        #expect(await wait(soon, until: { library.entries.map(\.id) == ["pond", "reeds"] }))
    }

    /// The snapshots `something check` keeps in the spaces folder's hidden .check are no space: the library does not
    /// list them, even a page there, the folder watch does not see them change, and an export does not carry them.
    @Test func theCheckFolderIsNoSpace() throws {
        let test = Home(prefix: "something-library-")
        defer { test.remove() }
        try Library.prepare(test.places)
        let garden = try test.space("garden", page(#"{"contract": 1, "title": "Garden"}"#, ""))
        let check = test.places.spaces.appendingPathComponent(".check")
        try FileManager.default.createDirectory(at: check, withIntermediateDirectories: true)
        for name in ["garden.png", "index.html", "stray.html"] { try Data("invented".utf8).write(to: check.appendingPathComponent(name)) }
        let library = library(test, FakeAsk())
        #expect(library.entries.map(\.id) == ["garden"])
        let stamp = Library.stamp(test.places.spaces)
        try Data("invented again".utf8).write(to: check.appendingPathComponent("garden.png"))
        try Data("invented".utf8).write(to: check.appendingPathComponent("pond.html"))
        #expect(Library.stamp(test.places.spaces) == stamp)
        let export = try JSONSerialization.jsonObject(with: Export.document(garden, data: nil, app: "0.0.0")) as? [String: Any]
        #expect((export?["files"] as? [String: String])?.keys.sorted() == ["garden.html"])
    }

    /// The last space open is opened at the next start; 1.0's default space, kept in app.json, is read once in its place.
    @Test func theLastSpaceOpenIsRemembered() throws {
        let test = Home(prefix: "something-library-")
        defer { test.remove() }
        try test.space("shop", page(nil, ""))
        try test.space("today", page(nil, ""))
        try FileManager.default.createDirectory(at: test.places.support, withIntermediateDirectories: true)
        try #"{"app": 1, "default": "today", "spaces": {}}"#.write(to: test.places.grants, atomically: true, encoding: .utf8)
        #expect(library(test, FakeAsk()).last() == "today", "1.0's default, read once")
        try #"{"app": 1, "default": "shop", "spaces": {}}"#.write(to: test.places.grants, atomically: true, encoding: .utf8)
        let library = library(test, FakeAsk())
        #expect(library.last() == "today", "window.json now says it")
        library.select("shop")
        #expect(self.library(test, FakeAsk()).last() == "shop")
        try FileManager.default.removeItem(at: test.places.spaces.appendingPathComponent("shop.html"))
        #expect(self.library(test, FakeAsk()).last() == nil, "a space gone is passed over")
        #expect(try AppFile.read(test.places.grants) == AppFile(), "app.json is read, never written for the window")
    }

    @Test func showInFinderAndMoveToTrash() throws {
        let test = Home(prefix: "something-library-"), ask = FakeAsk()
        defer { test.remove() }
        try test.space("today", page(#"{"contract": 1, "title": "Today", "rights": ["store"]}"#, ""))
        try Memory(folder: test.places.data, space: "today").set("seen", ["a1"])
        var file = AppFile()
        file.spaces["today"] = answered(declared: ["store"], granted: ["store"])
        try file.write(test.places.grants)
        let library = library(test, ask)
        var revealed: [URL] = []
        library.reveal = { revealed.append($0) }
        library.showInFinder("today")
        #expect(revealed == [test.places.spaces.appendingPathComponent("today.html")])

        library.select("today")
        library.trash("today")
        let trash = test.root.appendingPathComponent("Trash")
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.path).sorted() == ["today.html", "today.json"])
        #expect(library.entries.isEmpty && library.selection == nil)
        #expect(try AppFile.read(test.places.grants).spaces["today"] == nil, "a space made again under its name asks again")
        #expect(ask.told.isEmpty)
    }

    @Test func exportAsksForTheDataAndImportStartsWithoutGrants() async throws {
        let test = Home(prefix: "something-library-"), ask = FakeAsk()
        defer { test.remove() }
        let folder = test.places.spaces.appendingPathComponent("board")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try page(#"{"contract": 1, "rights": ["store"]}"#, "<p>An invented board.</p>").write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try Memory(folder: test.places.data, space: "board").set("seen", ["a1"])
        let saved = test.root.appendingPathComponent("board.something")
        let library = library(test, ask)

        ask.withData = nil
        ask.saveTo = saved
        library.export("board")
        #expect(ask.shown == [["seen"]] && !FileManager.default.fileExists(atPath: saved.path), "cancelled: nothing saved")
        ask.withData = false
        library.export("board")
        let without = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: saved)) as? [String: Any])
        #expect(without["data"] is NSNull && without["name"] as? String == "board", "Without Data is the default answer")
        ask.withData = true
        library.export("board")
        let with = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: saved)) as? [String: Any])
        #expect(with["data"] as? NSDictionary == ["seen": ["a1"]])

        // Answers kept under the name the import will give: the received space must not inherit them.
        var file = try AppFile.read(test.places.grants)
        file.spaces["board-2"] = answered(declared: ["store"], granted: ["store"])
        try file.write(test.places.grants)
        var opened: [String?] = []
        library.opened = { opened.append($0) }
        ask.chosen = saved
        library.importChosen()
        #expect(ask.told.isEmpty, "\(ask.told)")
        #expect(library.selection == "board-2" && library.entry("board-2")?.space.form == .folder)
        #expect(await wait(1, until: { opened == ["board-2"] }))
        #expect(try AppFile.read(test.places.grants).spaces["board-2"] == nil, "an imported space has no grant")
        #expect(try Memory(folder: test.places.data, space: "board-2").get("seen") as? [String] == ["a1"])

        // A grants file that does not read: the grant cannot be dropped, so nothing is written, and that is said.
        try "not json".write(to: test.places.grants, atomically: true, encoding: .utf8)
        let before = try FileManager.default.contentsOfDirectory(atPath: test.places.spaces.path).sorted()
        library.importChosen()
        #expect(ask.told.count == 1 && ask.told.last?.hasPrefix("board.something was not imported. The grants in") == true, "\(ask.told)")
        #expect(try FileManager.default.contentsOfDirectory(atPath: test.places.spaces.path).sorted() == before, "no space left")
        #expect(!FileManager.default.fileExists(atPath: Memory(folder: test.places.data, space: "board-3").file.path))
    }

    @Test func anExportNamesTheLinksItLeftOutAndRefusesALinkedMemory() throws {
        let test = Home(prefix: "something-library-"), ask = FakeAsk()
        defer { test.remove() }
        let folder = test.places.spaces.appendingPathComponent("board")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try page(nil, "<p>An invented board.</p>").write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let outside = test.root.appendingPathComponent(".claude.json")
        try #"{"note": "invented"}"#.write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("notes.json"), withDestinationURL: outside)
        let saved = test.root.appendingPathComponent("board.something")
        ask.saveTo = saved
        let library = library(test, ask)
        library.export("board")
        #expect(FileManager.default.fileExists(atPath: saved.path))
        #expect(ask.told == ["board was exported without notes.json: a link to somewhere else is never exported. Replace a link with the file itself to export it."])

        try FileManager.default.removeItem(at: saved)
        try FileManager.default.createDirectory(at: test.places.data, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: Memory(folder: test.places.data, space: "board").file, withDestinationURL: outside)
        library.export("board")
        #expect(ask.shown.isEmpty && !FileManager.default.fileExists(atPath: saved.path), "a linked memory is never read")
        #expect(ask.told.count == 2 && ask.told[1].hasPrefix("board was not exported.") && ask.told[1].contains("is a link"), "\(ask.told)")
    }

    @Test func aRefusedImportSaysWhyAndAGoneSpaceLosesItsGrants() throws {
        let test = Home(prefix: "something-library-"), ask = FakeAsk()
        defer { test.remove() }
        try test.space("notes", page(nil, ""))
        let library = library(test, ask)
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: Home.share.appendingPathComponent("contract/exports/unsafe-path.json"))) as? [String: Any]
        let chosen = test.root.appendingPathComponent("unsafe.something")
        try JSONSerialization.data(withJSONObject: try #require(fixture?["export"])).write(to: chosen)
        ask.chosen = chosen
        library.importChosen()
        #expect(ask.told.count == 1 && ask.told[0].contains("(IMPORT_UNSAFE_PATH)"), "\(ask.told)")
        #expect(library.entries.map(\.id) == ["notes"])

        var file = try AppFile.read(test.places.grants)
        file.spaces["notes"] = answered(declared: ["store"], granted: ["store"])
        try file.write(test.places.grants)
        try Library.forgetGone(test.places)
        #expect(try AppFile.read(test.places.grants).spaces["notes"] != nil)
        // Deleted, or renamed, in Finder: the next start forgets its answers, so a new space of that name asks again.
        try FileManager.default.removeItem(at: test.places.spaces.appendingPathComponent("notes.html"))
        // A folder whose index.html is being rewritten, and a spaces folder that is not there, keep their answers.
        let board = test.places.spaces.appendingPathComponent("board")
        try FileManager.default.createDirectory(at: board, withIntermediateDirectories: true)
        file = try AppFile.read(test.places.grants)
        file.spaces["board"] = answered(declared: ["store"], granted: ["store"])
        try file.write(test.places.grants)
        try Library.forgetGone(test.places)
        #expect(try AppFile.read(test.places.grants).spaces.keys.sorted() == ["board"])
        try FileManager.default.removeItem(at: test.places.spaces)
        try Library.forgetGone(test.places)
        #expect(try AppFile.read(test.places.grants).spaces.keys.sorted() == ["board"])
    }

    @Test func theStartMakesItsFolders() throws {
        let test = Home(prefix: "something-library-")
        defer { test.remove() }
        try Library.prepare(test.places)
        for folder in [test.places.spaces, test.places.data] {
            #expect(FileManager.default.fileExists(atPath: folder.path), "\(folder.path)")
            #expect(folder.path.hasPrefix(test.root.path))
        }
        try Library.prepare(test.places)
    }

    // MARK: Info

    @Test func aRevokedRightReachesTheOpenSpace() async throws {
        let test = Home(prefix: "something-library-"), ask = FakeAsk()
        defer { test.remove() }
        let space = try test.space("notes", page(#"{"contract": 1, "rights": ["state", "store"]}"#, """
            <script>window.heard = []; something.on("granted", (g) => heard.push(g.rights.join(","))); window.done = true</script>
            """))
        let window = try await test.window(space, ask)
        defer { window.close() }
        window.open()
        try await ready(window)
        #expect(try await run(window, "await something.store.set('word', 'invented'); return await something.store.get('word')") as? String == "invented")

        let info = info(test, ask, space, view: window)
        #expect(info.rights.map(\.right) == ["state", "store"] && info.rights.allSatisfy { $0.standing == .allowed })

        info.set("store", allowed: false)
        for _ in 0..<100 where try await run(window, "return heard.length") as? Int != 1 { await wait(0.05) }
        #expect(try await run(window, "return heard") as? [String] == ["state"])
        #expect(try await run(window, "return something.granted.refused") as? [String] == ["store"])
        #expect(try await run(window, "try { await something.store.get('word') } catch (e) { return e.code }") as? String == "RIGHT_NOT_GRANTED")
        let grant = try #require(try AppFile.read(test.places.grants).spaces["notes"])
        #expect(grant.granted == ["state"] && grant.refused == ["store"])
        #expect(info.rights.map(\.standing) == [.allowed, .refused])

        // Switched on again: the memory answers again, with what it kept.
        info.set("store", allowed: true)
        for _ in 0..<100 where try await run(window, "return heard.length") as? Int != 2 { await wait(0.05) }
        #expect(try await run(window, "return await something.store.get('word')") as? String == "invented")
        #expect(ask.questions.count == 1, "a switch is the person's answer: nothing more is asked")
    }

    @Test func askAgainClearsTheRefusalsOnlyAndAsksThemNow() async throws {
        let test = Home(prefix: "something-library-"), ask = FakeAsk()
        defer { test.remove() }
        let space = try test.space("board", page(#"{"contract": 1, "rights": ["state", "store"]}"#, "<script>window.done = true</script>"))
        let window = try await test.window(space, ask)
        defer { window.close() }
        ask.answer = { _ in RightsAnswer(allowed: ["state"], refused: ["store"], folder: nil, remap: [:]) }
        window.load()
        let info = info(test, ask, space, view: window)
        #expect(info.rights.map(\.standing) == [.allowed, .refused])

        // "Not Now": what was allowed stays, in the file and in the open space; the refusal is no longer remembered.
        ask.answer = nil
        info.askAgain()
        #expect(await wait(1, until: { ask.questions.count == 2 }), "asked just after the click")
        #expect(ask.questions.map(\.rights) == [["state", "store"], ["store"]])
        let grant = try #require(try AppFile.read(test.places.grants).spaces["board"])
        #expect(grant.granted == ["state"] && grant.refused.isEmpty)
        #expect(window.granted.rights == ["state"])
        #expect(info.rights.map(\.standing) == [.allowed, .notAnswered(inForce: [])])

        // Answered: Info shows the new answer at once.
        ask.answer = { RightsAnswer(allowed: $0, refused: [], folder: nil, remap: [:]) }
        info.askAgain()
        #expect(await wait(1, until: { ask.questions.count == 3 }))
        #expect(info.rights.map(\.standing) == [.allowed, .allowed])
        #expect(window.granted.rights == ["state", "store"])
    }

    @Test func aSwitchChangesOnlyItsOwnRight() throws {
        let test = Home(prefix: "something-library-"), ask = FakeAsk()
        defer { test.remove() }
        // "send" was allowed; the space now declares one right per kind, and a launch it was never asked about.
        let space = try test.space("shop", page(#"{"contract": 1, "rights": ["send:claude", "send:codex", "launch:claude"]}"#, ""))
        var file = AppFile()
        file.spaces["shop"] = answered(declared: ["send"], granted: ["send"])
        try file.write(test.places.grants)
        let info = info(test, ask, space)
        #expect(info.rights.map(\.standing) == [.allowed, .allowed, .notAnswered(inForce: [])])

        info.set("send:claude", allowed: false)
        let after = try #require(try AppFile.read(test.places.grants).spaces["shop"])
        #expect(after.granted == ["send:codex"] && after.refused == ["send:claude"])
        #expect(info.rights.map(\.standing) == [.refused, .allowed, .notAnswered(inForce: [])])
    }

    /// A space that declares no right is never asked about: Info does not say it will be.
    @Test func aSpaceWithoutRightsAsksForNothing() throws {
        let test = Home(prefix: "something-library-"), ask = FakeAsk()
        defer { test.remove() }
        let plain = try test.space("clock", page(#"{"contract": 1}"#, ""))
        let info = info(test, ask, plain)
        #expect(info.asksNothing && info.rights.isEmpty && info.problem == nil)
        info.show(try test.space("notes", page(#"{"contract": 1, "rights": ["store"]}"#, "")))
        #expect(!info.asksNothing && info.rights.isEmpty, "declared, never answered: it asks when it opens")
    }

    /// Closing the window closes the open space: its page stops, and nothing asks from a window nobody sees.
    @Test func closingTheWindowIsSaid() throws {
        let test = Home(prefix: "something-library-"), ask = FakeAsk()
        defer { test.remove() }
        let shell = Shell(library: library(test, ask), info: Info(places: test.places, ask: ask),
                          assistant: AssistantModel(engine: test.engine(), places: test.places), autosave: false)
        var closed = 0
        shell.closed = { closed += 1 }
        shell.window.close()
        #expect(closed == 1)
    }

    @Test func aWiderRightDeclaredLaterShowsWhatIsInForce() throws {
        let test = Home(prefix: "something-library-"), ask = FakeAsk()
        defer { test.remove() }
        let space = try test.space("shop", page(#"{"contract": 1, "rights": ["send"]}"#, ""))
        var file = AppFile()
        file.spaces["shop"] = answered(declared: ["send:claude"], granted: ["send:claude"])
        try file.write(test.places.grants)
        #expect(info(test, ask, space).rights.map(\.standing) == [.notAnswered(inForce: ["send:claude"])], "neither on nor off: not asked yet")
    }

    @Test func aGrantsFileThatDoesNotReadIsSaid() async throws {
        let test = Home(prefix: "something-library-"), ask = FakeAsk()
        defer { test.remove() }
        let space = try test.space("notes", page(#"{"contract": 1, "rights": ["store"]}"#, "<script>window.done = true</script>"))
        let window = try await test.window(space, ask)
        defer { window.close() }
        window.load()
        #expect(window.granted.rights == ["store"])
        try "not json".write(to: test.places.grants, atomically: true, encoding: .utf8)
        let info = info(test, ask, space, view: window)
        #expect(info.problem?.hasPrefix("The grants in") == true && info.rights.isEmpty)
        window.regrant()
        #expect(window.granted.rights == ["store"], "the rights in force stay")
        #expect(ask.told.count == 1)
    }

    @Test func aSwitchAppliesOnlyTheDeclarationThePersonWasAsked() async throws {
        let test = Home(prefix: "something-library-"), ask = FakeAsk()
        defer { test.remove() }
        let space = try test.space("notes", page(#"{"contract": 1, "rights": ["state", "store"], "agents": {"folders": []}}"#,
                                                 "<script>window.done = true</script>"))
        let window = try await test.window(space, ask)
        defer { window.close() }
        window.load()
        // The file widens its scope; the reload that would ask has not run yet.
        try test.space("notes", page(#"{"contract": 1, "rights": ["state", "store"], "agents": {"see": "all"}}"#, ""))
        info(test, ask, space, view: window).set("store", allowed: false)
        #expect(window.granted.rights == ["state"] && window.granted.agents == .folders([]))
    }

    @Test func theActivityIsTheJournalNewestFirst() throws {
        let test = Home(prefix: "something-library-"), ask = FakeAsk()
        defer { test.remove() }
        let space = try test.space("board", page(#"{"contract": 1, "title": "Board", "description": "An invented board."}"#, ""))
        #expect(info(test, ask, space).activity.isEmpty)
        let journal = Journal(folder: test.places.journals)
        for index in 0..<120 {
            try journal.append(JournalLine(at: "2026-10-17T09:00:00Z", action: "send", agent: "a1", kind: "claude", when: "next",
                                           text: "Invented message \(index).", result: "ok"), space: "board")
        }
        let info = info(test, ask, space)
        #expect(info.title == "Board" && info.about == "An invented board.")
        #expect(info.activity.count == 100)
        // The state no longer has a1: the line names its kind alone (WordsTests check the words).
        #expect(info.activity.first?.what == "wrote to Claude Code: “Invented message 119.”", "\(info.activity.first?.what ?? "")")
        #expect(info.activity.last?.what == "wrote to Claude Code: “Invented message 20.”")
        #expect(info.activity.allSatisfy { !$0.time.isEmpty })
    }
}
