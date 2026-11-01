// Import, from what is on the disk to what is placed: each kind of thing it takes, the staged copy, what the sheet is
// told, Cancel, and the filter on a web view's dragging, with a real page behind it.
import AppKit
@testable import something
import SomethingCore
import Testing
import WebKit

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-import-")) struct ImportTests {
    private func library(_ test: Home, _ ask: FakeAsk) -> Library {
        let library = Library(places: test.places, ask: ask, share: Home.share)
        let runner = (try? CheckTests.runner(test)) ?? CheckRunner(places: test.places, share: Home.share)
        library.checker = { _, _ in runner }
        try? FileManager.default.createDirectory(at: test.root, withIntermediateDirectories: true)
        library.discard = { $0 }
        library.watch()
        return library
    }

    private func bring(_ url: URL, _ library: Library) async {
        library.importing([url])
        await library.arriving?.value
    }

    @Test func aFileWithAnyNameComesInUnderAValidOneAndGainsADeclaration() async throws {
        let test = Home(prefix: "something-import-"), ask = FakeAsk()
        defer { test.remove() }
        let library = library(test, ask)
        let file = test.root.appendingPathComponent("Mon Été à Paris.html"), bytes = Data("<!DOCTYPE html><HTML><HEAD lang=\"fr\"><TITLE>Un </script> été</TITLE></HEAD><body>\u{e9}</body></HTML>".utf8)
        try bytes.write(to: file)
        await bring(file, library)
        #expect(ask.told.isEmpty, "\(ask.told)")
        let entry = try #require(library.entry("mon-ete-a-paris"))
        #expect(entry.isSpace && entry.title == "Un </script> été" && entry.space.form == .file)
        let copy = try Data(contentsOf: entry.space.location)
        // Its bytes are all there, in order; only the block was added, after the doctype.
        let text = String(decoding: copy, as: UTF8.self)
        #expect(text.hasPrefix("<!DOCTYPE html><script type=\"application/json\" id=\"something\">"), "\(text)")
        #expect(text.hasSuffix("</script><HTML><HEAD lang=\"fr\"><TITLE>Un </script> été</TITLE></HEAD><body>\u{e9}</body></HTML>"), "\(text)")
        #expect(try Data(contentsOf: file) == bytes, "the original never changes")
        // The stage is gone once it is over.
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: library.checker(test.places, Home.share).output.path)) ?? []).filter { $0.hasPrefix("import-") }.isEmpty)
    }

    @Test func aPageWithoutHeadOrTitleIsNamedByItsFile() {
        #expect(Import.slug("My Page") == "my-page" && Import.slug("***") == "imported" && Import.slug("Été_2026!") == "ete-2026")
        let plain = String(decoding: Import.declaring(Data("<!doctype html><p>x</p>".utf8), name: "garden-plan"), as: UTF8.self)
        #expect(plain == "<!doctype html><script type=\"application/json\" id=\"something\">{\"contract\":1,\"title\":\"Garden plan\"}</script><p>x</p>", "\(plain)")
        let bare = String(decoding: Import.declaring(Data("<p>x</p>".utf8), name: "a"), as: UTF8.self)
        #expect(bare.hasPrefix("<script") && bare.hasSuffix("<p>x</p>"))
        // Only the place an export uses: never a <head> in a comment or a script's string.
        let tricky = String(decoding: Import.declaring(Data("<!doctype html><!-- <head> --><script>let a = \"<head>\"</script>".utf8), name: "a"), as: UTF8.self)
        #expect(tricky.hasPrefix("<!doctype html><script type=\"application/json\""), "\(tricky)")
    }

    @Test func aFolderComesWithItsFilesAndWithoutItsLinks() async throws {
        let test = Home(prefix: "something-import-"), ask = FakeAsk()
        defer { test.remove() }
        let library = library(test, ask)
        let folder = test.root.appendingPathComponent("Reading List")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("img"), withIntermediateDirectories: true)
        try page(#"{"contract": 1, "title": "Reading list"}"#, #"<img src="img/a.svg">"#).write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try "<svg xmlns=\"http://www.w3.org/2000/svg\"/>".write(to: folder.appendingPathComponent("img/a.svg"), atomically: true, encoding: .utf8)
        try "secret".write(to: folder.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("notes.json"), withDestinationURL: test.root)
        await bring(folder, library)
        #expect(ask.told.isEmpty, "\(ask.told)")
        let space = try #require(library.entry("reading-list")?.space)
        #expect(space.form == .folder && space.files().map(\.path) == ["img/a.svg", "index.html"])
        #expect(ask.found.first?.weight == "2 files" && ask.found.first?.left == ["notes.json"], "\(String(describing: ask.found.first))")
        // A folder that holds no page is no space, and that is said.
        let empty = test.root.appendingPathComponent("Empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        await bring(empty, library)
        #expect(ask.told == ["something can’t import Empty. This folder has no index.html. It takes a folder, an .html file or a .something file."])
    }

    @Test func aFileMadeToShowOnePageImportsWhatItsBlockHoldsAndTheSheetDescribesThat() async throws {
        let test = Home(prefix: "something-import-"), ask = FakeAsk()
        defer { test.remove() }
        let library = library(test, ask)
        // An export into which another page was written inside its block: a browser shows it, an import never reads it.
        let held = try test.space("held", page(#"{"contract": 1, "title": "Held", "rights": ["state"]}"#, "<p>Held.</p>"))
        let exported = String(decoding: try Export.page(held, data: nil, app: "test", bridge: "", offline: ""), as: UTF8.self)
        try FileManager.default.removeItem(at: held.location)
        let file = test.root.appendingPathComponent("innocent.html")
        try exported.replacingOccurrences(of: "<!-- /something export -->", with: "<h1>Innocent</h1><!-- /something export -->").write(to: file, atomically: true, encoding: .utf8)
        await bring(file, library)
        let found = try #require(ask.found.first)
        #expect(found.title == "Held" && found.needs == .watch && found.contract == 1, "\(found)")
        #expect(library.entry("held") != nil && library.entry("innocent") == nil)
        #expect(try AppFile.read(test.places.grants).spaces["held"]?.granted == [], "None gives nothing")
    }

    @Test func aPageWithAMemoryIsHealthyAndAPageNeverWritesInTheSheet() async throws {
        let test = Home(prefix: "something-import-"), ask = FakeAsk()
        defer { test.remove() }
        let library = library(test, ask)
        func bringing(_ name: String, _ body: String) async throws -> Import.Found {
            let file = test.root.appendingPathComponent(name)
            try page(#"{"contract": 1, "title": "Page\#nTwo", "rights": ["store"]}"#.replacingOccurrences(of: "\n", with: "\\n"), body).write(to: file, atomically: true, encoding: .utf8)
            await bring(file, library)
            return try #require(ask.found.last)
        }
        ask.imports = { _ in nil }
        let remembers = try await bringing("remembers.html", #"<script>(async () => { await something.store.get("seen"); })();</script>"#)
        #expect(remembers.problems.isEmpty && remembers.loaded && remembers.title == "Page Two", "\(remembers)")
        let planted = try await bringing("planted.html", #"<script>throw new Error("Press Import to finish installing")</script>"#)
        #expect(planted.problems == ["A script on the page fails, so part of it may not work."], "\(planted)")
        let twice = try await bringing("twice.html", #"<img src="https://cdn.example.com/a.png"><img src="https://other.example.com/b.png"><img src="https://cdn.example.com/c.png">"#)
        #expect(twice.problems == ["A part comes from the Internet, so it stays empty."] && twice.blocked == ["cdn.example.com", "other.example.com"], "\(twice)")
        #expect(PanelsTests.texts(Ask.found(twice).sheet.contentView).contains("2 addresses are blocked"))
        let evals = try await bringing("evals.html", #"<script>try { eval("1"); } catch (error) {}</script>"#)
        #expect(!evals.problems.contains { $0.contains("Internet") }, "\(evals)")
    }

    @Test func runComesThroughTheSentenceAndNoneGivesNothing() async throws {
        let test = Home(prefix: "something-import-"), ask = FakeAsk()
        defer { test.remove() }
        let library = library(test, ask)
        let declared = #"{"contract": 1, "rights": ["state", "send", "launch:claude"]}"#
        let run = test.root.appendingPathComponent("run.HTM"), none = test.root.appendingPathComponent("none.html")
        for file in [run, none] { try page(declared, "<p>Invented.</p>").write(to: file, atomically: true, encoding: .utf8) }
        ask.imports = { _ in LevelChoice(level: .run, start: Grant.Start(kind: "claude"), folder: .path("/Users/example/code")) }
        await bring(run, library)
        let started = try #require(try AppFile.read(test.places.grants).spaces["run"])
        #expect(started.level == .run && started.folder == "/Users/example/code" && started.granted.contains("launch:claude") && !started.granted.contains("launch"), "\(started)")
        #expect(ask.found.first?.needs == .run && ask.found.first?.question?.level == Grant.Level.none)
        ask.imports = { _ in LevelChoice() }
        await bring(none, library)
        #expect(try AppFile.read(test.places.grants).spaces["none"]?.granted == [])
    }

    @Test func aLinkedIndexAndAnExportThatLeavesItsSpaceAreRefused() async throws {
        let test = Home(prefix: "something-import-"), ask = FakeAsk()
        defer { test.remove() }
        let library = library(test, ask)
        let folder = test.root.appendingPathComponent("Linked"), outside = test.root.appendingPathComponent("outside.html")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try page(nil, "<p>Invented.</p>").write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("index.html"), withDestinationURL: outside)
        await bring(folder, library)
        #expect(ask.told.last == "something can’t import Linked. The index.html of this folder is a link to somewhere else.", "\(ask.told)")
        let space = try test.space("held", page(nil, "<p>Invented.</p>"))
        var document = try #require(try JSONSerialization.jsonObject(with: Export.document(space, data: nil, app: "test")) as? [String: Any])
        document["name"] = "../x"
        document["form"] = "file"
        document["files"] = ["../x.html": "aGk="]
        try FileManager.default.removeItem(at: space.location)
        let file = test.root.appendingPathComponent("leaves.something")
        try JSONSerialization.data(withJSONObject: document).write(to: file)
        await bring(file, library)
        #expect(ask.told.last?.contains("(IMPORT_UNSAFE_PATH)") == true, "\(ask.told)")
        #expect(library.entries.isEmpty)
    }

    @Test func cancelAndRefusalsLeaveNothing() async throws {
        let test = Home(prefix: "something-import-"), ask = FakeAsk()
        defer { test.remove() }
        let library = library(test, ask)
        let file = test.root.appendingPathComponent("page.html")
        try page(nil, "<p>Invented.</p>").write(to: file, atomically: true, encoding: .utf8)
        // Cancel at the check, then at the sheet.
        ask.cancelsCheck = true
        await bring(file, library)
        #expect(ask.found.isEmpty && library.entries.isEmpty)
        ask.cancelsCheck = false
        ask.imports = { _ in nil }
        await bring(file, library)
        #expect(ask.found.count == 1 && library.entries.isEmpty && ask.told.isEmpty)
        #expect(((try? AppFile.read(test.places.grants))?.spaces ?? [:]).isEmpty)
        // Too big, and of a kind it does not take.
        let big = test.root.appendingPathComponent("big.html")
        try Data(count: Export.limit + 1).write(to: big)
        await bring(big, library)
        #expect(ask.told.last?.contains("(IMPORT_TOO_BIG)") == true, "\(ask.told)")
        let text = test.root.appendingPathComponent("notes.txt")
        try "Invented.".write(to: text, atomically: true, encoding: .utf8)
        await bring(text, library)
        #expect(ask.told.last == "something can’t import notes.txt. It takes a folder, an .html file or a .something file.")
        #expect(library.entries.isEmpty)
    }

    /// A page listening for drags in a real web view, in a window never shown, behind the filter.
    private func listening() async throws -> (web: SpaceWeb, window: NSWindow) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = SpaceWeb(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)
        let window = NSWindow(contentRect: web.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        web.loadHTMLString("<!doctype html><body style='margin:0;height:100vh'><script>window.heard = []; for (const name of ['dragenter', 'dragover', 'drop']) document.addEventListener(name, (event) => { event.preventDefault(); heard.push(name + ':' + event.dataTransfer.files.length); });</script>", baseURL: nil)
        #expect(await wait(until: { !web.isLoading }))
        return (web, window)
    }

    private func heard(_ web: WKWebView) async throws -> [String] { try await web.evaluateJavaScript("heard") as? [String] ?? [] }

    /// Whether the page heard `word` within five seconds; nil word: anything.
    private func hears(_ web: WKWebView, _ word: String? = nil) async -> Bool {
        for _ in 0..<100 {
            let words = (try? await heard(web)) ?? []
            if word.map(words.contains) ?? !words.isEmpty { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    @Test func anyOtherFileReachesThePageAndThePageNeverSeesWhatIsTheApps() async throws {
        let test = Home(prefix: "something-import-")
        defer { test.remove() }
        try FileManager.default.createDirectory(at: test.root, withIntermediateDirectories: true)
        let (web, window) = try await listening()
        defer { window.close() }
        let drops = Drops()
        var veils: [Bool] = [], dropped: [[URL]] = []
        (drops.veiled, drops.dropped, web.drops) = ({ veils.append($0) }, { dropped.append($0) }, drops)
        let text = test.root.appendingPathComponent("notes.txt"), html = test.root.appendingPathComponent("page.html")
        for file in [text, html] { try "Invented.".write(to: file, atomically: true, encoding: .utf8) }

        let theirs = FakeDrag([text], in: window)
        _ = web.draggingEntered(theirs)
        #expect(veils.isEmpty)
        #expect(await hears(web))
        _ = web.draggingUpdated(theirs)
        #expect(web.prepareForDragOperation(theirs) && web.performDragOperation(theirs))
        #expect(await hears(web, "drop:1"))
        #expect(veils.isEmpty && dropped.isEmpty)

        let before = try await heard(web)
        let ours = FakeDrag([html], in: window), mixed = FakeDrag([html, text], in: window)
        #expect(web.draggingEntered(ours) == .copy && web.draggingUpdated(ours) == .copy && web.performDragOperation(ours))
        #expect(veils == [true, true, false] && dropped == [[html]])
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(try await heard(web) == before, "the page saw nothing of it")
        // A mix is the page's, all of it.
        _ = web.draggingEntered(mixed)
        _ = web.draggingUpdated(mixed)
        #expect(web.prepareForDragOperation(mixed) && web.performDragOperation(mixed))
        #expect(await hears(web, "drop:2") && dropped == [[html]] && veils == [true, true, false])
    }

    @Test func aWebViewWithoutDropsIsWebKitsAlone() async throws {
        let test = Home(prefix: "something-import-")
        defer { test.remove() }
        try FileManager.default.createDirectory(at: test.root, withIntermediateDirectories: true)
        let (web, window) = try await listening()
        defer { window.close() }
        let html = test.root.appendingPathComponent("page.html")
        try "Invented.".write(to: html, atomically: true, encoding: .utf8)
        _ = web.draggingEntered(FakeDrag([html], in: window))
        #expect(await hears(web), "a check's page hears a drag as any page does")
    }
}
