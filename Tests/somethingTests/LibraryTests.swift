// The sidebar's list and Info, in a throwaway home: the spaces sorted by title with the pages that are not spaces yet,
// the sidebar's order (groups, then the rest), the destinations each opened once, the folder watched, the last space
// open remembered (and 1.0's default read once), Show in Finder, Move to Trash
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

    /// A grant answered right by right, as before levels, for a declaration of `declared`.
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
        var opened: [Library.Destination] = []
        library.opened = { opened.append($0) }
        library.watch()
        defer { library.stop() }
        // The watch looks every half second. Each wait gives it ten seconds and ends as soon as it sees: while the
        // other suites start agents and WebKit at once, a 3-core runner's main queue was seen late by more than a
        // second (CI, 19 October 2026), and a clean clone's first run missed three seconds.
        let soon: Double = 10
        try test.space("garden", page(#"{"contract": 1, "title": "Garden"}"#, ""))
        #expect(await wait(soon, until: { library.entries.map(\.id) == ["garden"] }))
        library.select(.space("garden"))
        #expect(await wait(soon, until: { opened == [.space("garden")] }), "the space opens just after it is selected")

        // Rewritten in place, as an editor without an atomic save does: no entry of the folder changes.
        let file = test.places.spaces.appendingPathComponent("garden.html")
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(page(#"{"contract": 1, "title": "Kitchen garden"}"#, "").utf8))
        try handle.close()
        #expect(await wait(soon, until: { library.entries.map(\.title) == ["Kitchen garden"] }))

        try FileManager.default.removeItem(at: file)
        #expect(await wait(soon, until: { library.entries.isEmpty && opened == [.space("garden"), .newSpace] }))
        #expect(library.selection == .newSpace)

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
        #expect(library(test, FakeAsk()).atStart() == "today", "1.0's default, read once")
        try #"{"app": 1, "default": "shop", "spaces": {}}"#.write(to: test.places.grants, atomically: true, encoding: .utf8)
        let library = library(test, FakeAsk())
        #expect(library.atStart() == "today", "window.json now says it")
        library.select(.space("shop"))
        #expect(self.library(test, FakeAsk()).atStart() == "shop")
        try FileManager.default.removeItem(at: test.places.spaces.appendingPathComponent("shop.html"))
        #expect(self.library(test, FakeAsk()).atStart() == nil, "a space gone is passed over")
        #expect(try AppFile.read(test.places.grants) == AppFile(), "app.json is read, never written for the window")
    }

    /// The groups in their order, each one's spaces by title, then the spaces in no group by title: the one order of
    /// the sidebar, ⌘1…⌘9, the Go menu and ⌘P. A name no space has is passed over; a space two groups name shows once.
    @Test func theOrderIsTheGroupsThenTheRestEachByTitle() throws {
        let test = Home(prefix: "something-library-")
        defer { test.remove() }
        for (name, title) in [("pond", "Pond"), ("brief", "Daily brief"), ("log", "logbook"), ("pet", "Pebble"), ("stack", "Stack")] {
            try test.space(name, page(#"{"contract": 1, "title": "\#(title)"}"#, ""))
        }
        let library = library(test, FakeAsk())
        #expect(library.order().map(\.id) == ["brief", "log", "pet", "pond", "stack"], "no group: by title")
        library.preferences.groups = [.init(name: "Notes", spaces: ["stack", "log", "gone"]), .init(name: "Empty", spaces: []),
                                      .init(name: "Breaks", spaces: ["pet", "stack"])]
        #expect(library.order().map(\.id) == ["log", "stack", "pet", "brief", "pond"])
        #expect(library.entries.map(\.id) == ["brief", "log", "pet", "pond", "stack"], "the entries stay by title")
    }

    /// Selecting where the window already is opens nothing again; of two selections before the first opened, only
    /// the second opens; only a space is remembered as the last one open.
    @Test func eachDestinationOpensOnceAndTheLastOfTwoQuickSelectionsWins() async throws {
        let test = Home(prefix: "something-library-")
        defer { test.remove() }
        try test.space("shop", page(nil, ""))
        try test.space("pond", page(nil, ""))
        let library = library(test, FakeAsk())
        var opened: [Library.Destination] = []
        library.opened = { opened.append($0) }
        #expect(library.selection == .newSpace)
        library.select(.newSpace)
        library.select(.templates)
        library.select(.templates)
        #expect(await wait(until: { opened == [.templates] }))
        library.select(.space("pond"))
        library.select(.space("shop"))
        #expect(await wait(until: { opened == [.templates, .space("shop")] }), "\(opened)")
        library.select(.space("shop"))
        library.select(.newSpace)
        #expect(await wait(until: { opened == [.templates, .space("shop"), .newSpace] }), "\(opened)")
        await wait(0.05)
        #expect(opened.count == 3 && library.selection == .newSpace)
        #expect(library.preferences.lastOpen == "shop" && library.atStart() == "shop", "New Space and the templates are not remembered")
        #expect(library.preferences.recents == ["shop", "pond"])
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

        // What the trash sheet says goes with it: two entries, none for a space with no memory, nil for one that does not read.
        try Memory(folder: test.places.data, space: "today").set("notes/first", "tea")
        try Data("not json".utf8).write(to: Memory(folder: test.places.data, space: "broken").file)
        #expect(library.remembers("today") == 2 && library.remembers("elsewhere") == 0 && library.remembers("broken") == nil)
        try Versions(root: test.places.versions, keep: 50, limit: 0).capture(try #require(library.entry("today")).space, kind: .turn, sentence: "Make it")
        library.select(.space("today"))
        library.trash("today")
        let trash = test.root.appendingPathComponent("Trash")
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.path).sorted() == ["today", "today.html", "today.json"], "its versions go too")
        #expect(library.entries.isEmpty && library.selection == .newSpace)
        #expect(try AppFile.read(test.places.grants).spaces["today"] == nil, "a space made again under its name asks again")
        #expect(ask.told.isEmpty)
    }

    @Test func aSpaceMadeUnderAGoneNameStartsWithoutItsVersions() throws {
        let test = Home(prefix: "something-library-"), ask = FakeAsk()
        defer { test.remove() }
        let old = try test.space("today", page(#"{"contract": 1, "title": "Today"}"#, "<p>Morning</p>"))
        let versions = Versions(root: test.places.versions, keep: 50, limit: 0)
        try versions.capture(old, kind: .turn, sentence: "Say morning")
        let library = library(test, ask)
        // Deleted in Finder, then made again from New Space under the same name: the old past goes to the Trash.
        try FileManager.default.removeItem(at: old.location)
        library.relist()
        let made = try Command.new("today", folder: false, places: test.places, template: Home.share.appendingPathComponent("template.html"),
                                   recycle: library.recycle)
        #expect(versions.list(made.name).isEmpty)
        let trash = test.root.appendingPathComponent("Trash")
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.path) == ["today"], "the old versions are in the Trash, not deleted")
        // Renamed in Finder while the app was closed: the next start sends the versions left under the old name away.
        try versions.capture(made, kind: .turn, sentence: "Say evening")
        try FileManager.default.moveItem(at: made.location, to: test.places.spaces.appendingPathComponent("tonight.html"))
        try FileManager.default.removeItem(at: trash)
        try Library.forgetGone(test.places, recycle: library.recycle)
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.path) == ["today"])
        #expect(versions.list("today").isEmpty && ask.told.isEmpty)
    }

    @Test func exportGoesToDownloadsInOneClickAndImportStartsWithoutGrants() async throws {
        let test = Home(prefix: "something-library-"), ask = FakeAsk()
        defer { test.remove() }
        let folder = test.places.spaces.appendingPathComponent("board")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try page(#"{"contract": 1, "rights": ["store"]}"#, "<p>An invented board.</p>").write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try Memory(folder: test.places.data, space: "board").set("seen", ["a1"])
        let saved = test.places.downloads.appendingPathComponent("board.something")
        let library = library(test, ask)
        var exported: [URL] = []
        library.exported = { exported.append($0) }

        // One click: no question, no panel; its memory stays on the Mac; a Downloads folder made when there is none.
        #expect(!FileManager.default.fileExists(atPath: test.places.downloads.path))
        library.export("board")
        #expect(exported == [saved] && ask.told.isEmpty && ask.folderMessages.isEmpty, "\(ask.told)")
        let without = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: saved)) as? [String: Any])
        #expect(without["data"] is NSNull && without["name"] as? String == "board")
        // Never over a file: the next one takes the next free name, as Finder's copies do.
        library.export("board")
        #expect(exported.last?.lastPathComponent == "board 2.something" && FileManager.default.fileExists(atPath: saved.path))
        try FileManager.default.removeItem(at: exported[1])
        // Settings › Spaces' Include a space's memory: the export carries it.
        library.preferences.exportMemory = true
        library.export("board")
        let with = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: exported[2])) as? [String: Any])
        #expect((with["data"] as? [String: Any])?["seen"] as? [String] == ["a1"] && ask.told.isEmpty)
        try FileManager.default.removeItem(at: exported[2])
        library.preferences.exportMemory = false

        // A file that carries a memory, as one made elsewhere may: the import keeps it.
        let board = try #require(library.entry("board")?.space)
        try Export.document(board, data: ["seen": ["a1"]], app: "test").write(to: saved)

        // Answers kept under the name the import will give: the received space must not inherit them.
        var file = try AppFile.read(test.places.grants)
        file.spaces["board-2"] = answered(declared: ["store"], granted: ["store"])
        try file.write(test.places.grants)
        var opened: [Library.Destination] = []
        library.opened = { opened.append($0) }
        ask.chosen = saved
        library.importChosen()
        #expect(ask.told.isEmpty, "\(ask.told)")
        #expect(library.selection == .space("board-2") && library.entry("board-2")?.space.form == .folder)
        #expect(await wait(30, until: { opened == [.space("board-2")] }))
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

    @Test func anExportNamesTheLinksItLeftOutAndNeverFollowsItsMemorysLink() throws {
        let test = Home(prefix: "something-library-"), ask = FakeAsk()
        defer { test.remove() }
        let folder = test.places.spaces.appendingPathComponent("board")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try page(nil, "<p>An invented board.</p>").write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let outside = test.root.appendingPathComponent(".claude.json")
        try #"{"note": "invented"}"#.write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("notes.json"), withDestinationURL: outside)
        let saved = test.places.downloads.appendingPathComponent("board.something")
        let library = library(test, ask)
        library.export("board")
        #expect(FileManager.default.fileExists(atPath: saved.path))
        #expect(ask.told == ["“board” was exported without notes.json: a link to somewhere else is never exported. Replace a link with the file itself to export it."])

        // A memory that is a link is never read: the export leaves the memory out.
        try FileManager.default.removeItem(at: saved)
        try FileManager.default.createDirectory(at: test.places.data, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: Memory(folder: test.places.data, space: "board").file, withDestinationURL: outside)
        library.export("board")
        let without = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: saved)) as? [String: Any])
        #expect(without["data"] is NSNull && ask.told.count == 2, "\(ask.told)")
        // Asked to carry it, the export stops and says why rather than follow the link.
        library.preferences.exportMemory = true
        library.export("board")
        #expect(ask.told.count == 3 && ask.told.last?.hasPrefix("“board” was not exported.") == true && ask.told.last?.contains("is a link") == true, "\(ask.told)")
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
        try Library.forgetGone(test.places, recycle: { _ in Issue.record("no versions to trash") })
        #expect(try AppFile.read(test.places.grants).spaces["notes"] != nil)
        // Deleted, or renamed, in Finder: the next start forgets its answers, so a new space of that name asks again.
        try FileManager.default.removeItem(at: test.places.spaces.appendingPathComponent("notes.html"))
        // A folder whose index.html is being rewritten, and a spaces folder that is not there, keep their answers.
        let board = test.places.spaces.appendingPathComponent("board")
        try FileManager.default.createDirectory(at: board, withIntermediateDirectories: true)
        file = try AppFile.read(test.places.grants)
        file.spaces["board"] = answered(declared: ["store"], granted: ["store"])
        try file.write(test.places.grants)
        try Library.forgetGone(test.places, recycle: { _ in Issue.record("no versions to trash") })
        #expect(try AppFile.read(test.places.grants).spaces.keys.sorted() == ["board"])
        try FileManager.default.removeItem(at: test.places.spaces)
        try Library.forgetGone(test.places, recycle: { _ in Issue.record("no versions to trash") })
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

    /// A level chosen in Info is the person's answer: kept as the space's grant and heard at once by the open space,
    /// with nothing asked; its memory never stops answering.
    @Test func aLevelChosenInInfoReachesTheOpenSpace() async throws {
        let test = Home(prefix: "something-library-"), ask = FakeAsk()
        defer { test.remove() }
        let space = try test.space("notes", page(#"{"contract": 1, "rights": ["state", "send", "store"]}"#, """
            <script>window.heard = []; something.on("granted", (g) => heard.push(g.rights.join(","))); window.done = true</script>
            """))
        let window = try await test.window(space, ask)
        defer { window.close() }
        window.open()
        try await ready(window)
        #expect(try await run(window, "await something.store.set('word', 'invented'); return await something.store.get('word')") as? String == "invented")

        let info = info(test, ask, space, view: window)
        #expect(info.level == .talk && info.folder == nil && info.problem == nil, "the level its sheet answered")
        info.choose(.none)
        for _ in 0..<600 where try await run(window, "return heard.length") as? Int != 1 { await wait(0.05) }
        #expect(try await run(window, "return heard") as? [String] == ["store"])
        let grant = try #require(try AppFile.read(test.places.grants).spaces["notes"])
        #expect(grant.level == Grant.Level.none && grant.granted.isEmpty && grant.refused == ["state", "send", "launch"])
        #expect(info.level == Grant.Level.none)

        info.choose(.watch)
        for _ in 0..<600 where try await run(window, "return heard.length") as? Int != 2 { await wait(0.05) }
        #expect(try await run(window, "return heard") as? [String] == ["store", "state,store"])
        #expect(try await run(window, "return await something.store.get('word')") as? String == "invented")
        #expect(ask.questions.count == 1 && info.level == .watch, "a level chosen here is the answer: nothing more is asked")
    }

    /// Run needs its folder: the one in force, else the one its page declares when it is on this Mac, else the person
    /// picks one; a folder not picked changes nothing. Leaving Run lets the folder go.
    @Test func runTakesItsFolder() throws {
        let test = Home(prefix: "something-library-"), ask = FakeAsk()
        defer { test.remove() }
        let shop = test.root.appendingPathComponent("code/shop")
        let space = try test.space("shop", page(#"{"contract": 1, "rights": ["state", "send", "launch"], "folder": "/nowhere/invented"}"#, ""))
        let info = info(test, ask, space)
        var picked: String?, asked = 0
        info.pick = { answer in
            asked += 1
            if let picked { answer(picked) }
        }
        #expect(info.level == Grant.Level.none, "never answered")
        info.choose(.run)
        #expect(asked == 1 && info.level == Grant.Level.none, "not picked: nothing changes")
        #expect(try AppFile.read(test.places.grants).spaces["shop"] == nil)
        picked = shop.path
        info.choose(.run)
        #expect(asked == 2 && info.level == .run && info.folder == shop.path)
        #expect(try AppFile.read(test.places.grants).spaces["shop"]?.granted == ["state", "send", "launch"])
        info.choose(.watch)
        #expect(info.level == .watch && info.folder == nil)

        // Declared and on this Mac: taken without asking.
        try FileManager.default.createDirectory(at: shop, withIntermediateDirectories: true)
        let declared = try test.space("shop", page(#"{"contract": 1, "rights": ["launch"], "folder": "\#(shop.path)"}"#, ""))
        info.show(declared)
        info.choose(.run)
        #expect(asked == 2 && info.level == .run && info.folder == shop.path)
    }

    /// A page that declares nothing is at None; a grants file that does not read is said, and the rights in force stay.
    @Test func whatInfoSaysWithoutALevel() async throws {
        let test = Home(prefix: "something-library-"), ask = FakeAsk()
        defer { test.remove() }
        let plain = try test.space("plain", page(nil, ""))
        let info = info(test, ask, plain)
        #expect(info.level == Grant.Level.none && info.problem == nil, "a page that declares nothing still has its level")

        let space = try test.space("notes", page(#"{"contract": 1, "rights": ["state", "store"]}"#, "<script>window.done = true</script>"))
        let window = try await test.window(space, ask)
        defer { window.close() }
        window.load()
        #expect(window.granted.rights == ["state", "store"])
        try "not json".write(to: test.places.grants, atomically: true, encoding: .utf8)
        let broken = self.info(test, ask, space, view: window)
        #expect(broken.problem?.hasPrefix("The grants in") == true && broken.level == nil)
        broken.choose(.none)
        #expect(window.granted.rights == ["state", "store"], "the rights in force stay")
        #expect(ask.told.count == 2, "\(ask.told)")
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
}
