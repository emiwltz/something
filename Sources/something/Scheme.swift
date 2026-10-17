// Serves one space at something://space/: its single file, or the files of its folder, and nothing else. Every answer
// carries the policy that forbids every network origin, so a space can load only its own files, inline code, data: and
// blob:, and what it shows of the agents stays on the machine.
import Foundation
import SomethingCore
import WebKit

final class Scheme: NSObject, WKURLSchemeHandler {
    static let name = "something", host = "space"
    /// `default-src` covers scripts, styles, images, fonts, media, frames, workers and every connection (fetch, XHR,
    /// WebSocket, EventSource, beacons); `form-action` is not covered by it, so it is said too.
    static let policy = "default-src something: 'unsafe-inline' data: blob:; form-action something:"

    let space: Space

    init(space: Space) {
        self.space = space
    }

    /// The address of the space's page.
    var page: URL {
        URL(string: "\(Scheme.name)://\(Scheme.host)/\(space.form == .file ? space.location.lastPathComponent : "")")!
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let file = file(for: url), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let headers = ["Content-Type": Scheme.type(of: file), "Content-Security-Policy": Scheme.policy, "Cache-Control": "no-store"]
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
