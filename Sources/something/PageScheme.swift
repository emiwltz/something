// Serves pages at something:// addresses, so that every page gets the same rules: its own files and
// something.js, nothing from the network. something://app/ is share/.
import Foundation
import WebKit

final class PageScheme: NSObject, WKURLSchemeHandler {
    let app: URL
    /// Scripts, styles, images and fetches only from something:// (and inline, data:, blob:).
    /// A page cannot reach the Internet, so what it shows of the agents stays on the machine.
    static let policy = "default-src something: 'unsafe-inline' data: blob:"

    init(app: URL) {
        self.app = app
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let file = file(for: url), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let headers = ["Content-Type": PageScheme.type(of: file), "Content-Security-Policy": PageScheme.policy,
                       "Cache-Control": "no-store"]
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    /// The file an address points to, or nil when it points outside share/.
    func file(for url: URL) -> URL? {
        guard url.host == "app" else { return nil }
        var file = app.appendingPathComponent(url.path).standardizedFileURL
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: file.path, isDirectory: &isFolder), isFolder.boolValue {
            file.appendPathComponent("index.html")
        }
        return file.path.hasPrefix(app.standardizedFileURL.path + "/") ? file : nil
    }

    static func type(of file: URL) -> String {
        let types = ["html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8",
                     "css": "text/css; charset=utf-8", "json": "application/json", "svg": "image/svg+xml",
                     "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
                     "webp": "image/webp", "woff2": "font/woff2", "mp3": "audio/mpeg", "wav": "audio/wav"]
        return types[file.pathExtension.lowercased()] ?? "application/octet-stream"
    }
}
