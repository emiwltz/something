// Serves one space at something://space/: its single file, or the files of its folder, and nothing else. Every answer
// carries the policy that forbids every network origin, so a space can load only its own files, inline code, data: and
// blob:, and what it shows of the agents stays on the machine. It also serves the app's own page, something://app/,
// which holds the space in a sandboxed frame. A space is never the main frame: WebKit connects to the server of a link
// the main frame follows before it asks where that frame may go, while a link the space's frame follows is refused by
// this page's policy before any connection.
import Foundation
import SomethingCore
import WebKit

final class Scheme: NSObject, WKURLSchemeHandler {
    static let name = "something", host = "space", app = "app"
    /// `default-src` covers scripts, styles, images, fonts, media, frames, workers and every connection (fetch, XHR,
    /// WebSocket, EventSource, beacons); `form-action` is not covered by it, so it is said too.
    static let policy = "default-src something: 'unsafe-inline' data: blob:; form-action something:"

    /// The policy of the app's page: it holds the space's frame and nothing else, and that frame may hold only the
    /// space, so a link the space follows is refused before WebKit connects anywhere.
    static let shellPolicy = "default-src 'none'; style-src 'unsafe-inline'; frame-src something://space"

    let space: Space

    init(space: Space) {
        self.space = space
    }

    /// The address of the space's page.
    var page: URL {
        URL(string: "\(Scheme.name)://\(Scheme.host)/\(space.form == .file ? space.location.lastPathComponent : "")")!
    }

    /// The address of the app's page around the space.
    static let shell = URL(string: "\(name)://\(app)/")!

    /// The app's page: the space's frame, filling the window. Another host is another origin, so the space cannot
    /// reach it; the sandbox has neither allow-top-navigation nor allow-popups, so the space cannot replace it or open
    /// a window.
    var shellPage: Data {
        Data("""
            <!doctype html><html><head><meta charset="utf-8"><style>html, body, iframe { margin: 0; border: 0; width: 100%; \
            height: 100%; display: block; }</style></head><body><iframe sandbox="allow-scripts allow-same-origin allow-forms"
            src="\(Scheme.attribute(page.absoluteString))"></iframe></body></html>
            """.utf8)
    }

    /// `text` as the value of a quoted HTML attribute: a file named `a&lt.html` stays that name.
    static func attribute(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        if url == Scheme.shell {
            return respond(task, url, type: "text/html; charset=utf-8", policy: Scheme.shellPolicy, data: shellPage)
        }
        guard let file = file(for: url), let data = try? Data(contentsOf: file) else {
            return task.didFailWithError(URLError(.fileDoesNotExist))
        }
        respond(task, url, type: Scheme.type(of: file), policy: Scheme.policy, data: data)
    }

    private func respond(_ task: WKURLSchemeTask, _ url: URL, type: String, policy: String, data: Data) {
        let headers = ["Content-Type": type, "Content-Security-Policy": policy, "Cache-Control": "no-store"]
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    /// The file of the space an address points to; nil when it points to anything else: another host, a path that
    /// climbs out (`..`, or a link inside the folder that leads outside it), a hidden file, or a file that is not there.
    func file(for url: URL) -> URL? {
        guard url.scheme == Scheme.name, url.host == Scheme.host else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        // Hidden files stay out, as they stay out of a space's stamp and of its export.
        guard !parts.contains(where: { $0.hasPrefix(".") }) else { return nil }
        if space.form == .file {
            return parts.isEmpty || parts == [space.location.lastPathComponent] ? regular(space.location) : nil
        }
        let root = space.location.resolvingSymlinksInPath()
        var file = parts.reduce(root) { $0.appendingPathComponent($1) }.resolvingSymlinksInPath()
        guard file.path == root.path || file.path.hasPrefix(root.path + "/") else { return nil }
        if (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { file.appendPathComponent("index.html") }
        return regular(file)
    }

    private func regular(_ file: URL) -> URL? {
        (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true ? file : nil
    }

    static func type(of file: URL) -> String {
        // WebKit refuses a module script or a WebAssembly stream served as octet-stream.
        let types = ["html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8",
                     "mjs": "text/javascript; charset=utf-8", "wasm": "application/wasm",
                     "css": "text/css; charset=utf-8", "json": "application/json", "svg": "image/svg+xml",
                     "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
                     "webp": "image/webp", "ico": "image/x-icon", "woff2": "font/woff2", "woff": "font/woff",
                     "ttf": "font/ttf", "otf": "font/otf", "mp3": "audio/mpeg", "wav": "audio/wav",
                     "mp4": "video/mp4", "webm": "video/webm"]
        return types[file.pathExtension.lowercased()] ?? "application/octet-stream"
    }
}
