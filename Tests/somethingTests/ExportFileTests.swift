// The one HTML file opened from a file:// address in WebKit, the engine of Safari: the nearest thing to a browser a test
// may start. It has no something handler, as a browser has none. Chrome and Firefox are not tried here: what they do
// with blob: under a file:// page's policy is known only from their specifications.
import Foundation
@testable import something
import SomethingCore
import Testing
import WebKit

@MainActor @Suite struct ExportFileTests {
    final class Loaded: NSObject, WKNavigationDelegate {
        var done: CheckedContinuation<Void, Never>?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done?.resume(); done = nil }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { done?.resume(); done = nil }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { done?.resume(); done = nil }
    }

    /// `space` exported and opened as a file in a folder of its own; `check` runs in the page and gives a JSON text.
    private func open(_ space: Space, data: [String: Any]?, home: Home, check: String) async throws -> [String: Any] {
        let html = try Export.page(space, data: data, app: "1.0.0-test",
                                   bridge: String(contentsOf: Home.share.appendingPathComponent("something.js"), encoding: .utf8),
                                   offline: String(contentsOf: Home.share.appendingPathComponent("offline.js"), encoding: .utf8))
        let folder = home.root.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(space.name).html")
        try html.write(to: file)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)
        let loaded = Loaded()
        web.navigationDelegate = loaded
        await withCheckedContinuation { done in
            loaded.done = done
            web.loadFileURL(file, allowingReadAccessTo: folder)
        }
        let text = try #require(try await web.callAsyncJavaScript(check, contentWorld: .page) as? String)
        return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    @Test func aFolderSpaceIsItsPageOnFile() async throws {
        let home = Home(prefix: "something-exportfile-")
        defer { home.remove() }
        let folder = home.places.spaces.appendingPathComponent("board")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("img"), withIntermediateDirectories: true)
        try """
        <!doctype html><html lang="fr"><head><title>Board</title>
        <script type="application/json" id="something">{"contract": 1, "rights": ["store"]}</script>
        <link rel="stylesheet" href="style.css"><script src="app.js"></script></head>
        <body><p id="kept">Invented</p><img id="logo" src="img/logo.svg"></body></html>
        """.write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try "p { color: rgb(1, 2, 3); }".write(to: folder.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)
        try "window.ranFromItsFile = true;".write(to: folder.appendingPathComponent("app.js"), atomically: true, encoding: .utf8)
        try "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"8\" height=\"8\"><rect width=\"8\" height=\"8\"/></svg>"
            .write(to: folder.appendingPathComponent("img/logo.svg"), atomically: true, encoding: .utf8)
        let check = """
            const image = document.getElementById("logo");
            if (!image.complete) await new Promise((done) => { image.onload = image.onerror = done; });
            await something.store.set("plans", "Market at nine.");
            const refused = await something.state().catch((error) => error.code);
            const network = await new Promise((done) => {
              const probe = new Image(); probe.onload = () => done("loaded"); probe.onerror = () => done("blocked");
              probe.src = "https://example.com/pixel.png";
            });
            return JSON.stringify({
              mode: document.compatMode, lang: document.documentElement.lang, script: window.ranFromItsFile === true,
              color: getComputedStyle(document.getElementById("kept")).color, width: image.naturalWidth,
              seen: await something.store.get("seen"), plans: await something.store.get("plans"), refused, network,
              fetched: await (await fetch("style.css")).text(), rights: something.granted.rights,
              kept: localStorage.length,
            });
            """
        let page = try await open(try #require(Spaces(root: home.places.spaces).named("board")), data: ["seen": ["a1"]], home: home, check: check)
        #expect(page["mode"] as? String == "CSS1Compat" && page["lang"] as? String == "fr", "\(page)")
        #expect(page["script"] as? Bool == true, "a script of the folder ran: \(page)")
        #expect(page["color"] as? String == "rgb(1, 2, 3)", "its stylesheet applied: \(page)")
        #expect(page["width"] as? Int == 8, "its image drew: \(page)")
        #expect(page["seen"] as? [String] == ["a1"] && page["plans"] as? String == "Market at nine.", "\(page)")
        #expect(page["refused"] as? String == "NO_HOST" && page["rights"] as? [String] == ["store"], "\(page)")
        #expect(page["fetched"] as? String == "p { color: rgb(1, 2, 3); }" && page["network"] as? String == "blocked" && page["kept"] as? Int == 1, "\(page)")
    }

    @Test func aFileSpaceWithoutMemoryShowsWhatItIsAndNothingElse() async throws {
        let home = Home(prefix: "something-exportfile-")
        defer { home.remove() }
        let space = try home.space("note", "<!doctype html><title>Note</title><p id=\"p\">Invented</p>"
            + "<script>window.started = something.on('change', () => {}) !== undefined;</script>")
        let page = try await open(space, data: nil, home: home, check: """
            return JSON.stringify({ text: document.getElementById("p").textContent, started: window.started,
              refused: await something.store.get("x").catch((error) => error.code) });
            """)
        #expect(page["text"] as? String == "Invented" && page["started"] as? Bool == true && page["refused"] as? String == "NO_HOST", "\(page)")
    }
}
