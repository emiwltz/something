// What the app's tests share: a throwaway home with spaces in it, a person who answers without a window, a listener
// on 127.0.0.1 that counts every connection, and the run loop turned until WebKit has answered. No window is shown.
import Darwin
import Foundation
import SomethingAgents
import SomethingCore
import Testing
import WebKit
@testable import something

/// A home in the temporary folder, removed by `remove()`; the person's own folders are never touched.
struct Home {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("something-app-\(UUID().uuidString)")
    var places: Places { Places(home: root) }
    static let share = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("share")

    /// Writes ~/something/spaces/<name>.html and returns the space.
    @discardableResult
    func space(_ name: String, _ html: String) throws -> Space {
        try FileManager.default.createDirectory(at: places.spaces, withIntermediateDirectories: true)
        try html.write(to: places.spaces.appendingPathComponent("\(name).html"), atomically: true, encoding: .utf8)
        return try #require(Spaces(root: places.spaces).named(name))
    }

    @MainActor
    func window(_ space: Space, _ ask: FakeAsk = FakeAsk()) async throws -> SpaceWindow {
        try SpaceWindow(space: space, places: places, engine: Engine(environment: [:]), ask: ask, share: Home.share,
                        rules: try await Lockdown.ruleList())
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

/// A page with a declaration block and a body.
func page(_ declaration: String?, _ body: String) -> String {
    let block = declaration.map { "<script type=\"application/json\" id=\"something\">\($0)</script>" } ?? ""
    return "<!doctype html><html><head><meta charset=\"utf-8\">\(block)</head><body>\(body)</body></html>"
}

/// The person, played by the test: every window it is shown is recorded and answered as told.
final class FakeAsk: Asking {
    var questions: [RightsQuestion] = [], links: [URL] = [], modes: [String] = [], told: [String] = []
    /// nil answers "Not now"; otherwise the rights to allow (the others are refused), the folder and the remap.
    var answer: (([String]) -> RightsAnswer?)? = { RightsAnswer(allowed: $0, refused: [], folder: nil, remap: [:]) }
    var link: LinkChoice = .cancel
    /// Runs while the link window would be open.
    var during: ((URL) -> Void)?
    var lowers = false
    /// The export window's answer (false is "Without data"), and the keys it was shown each time.
    var withData: Bool? = false
    var shown: [[String]] = []
    /// Where the save panel saves, and the file the open panel chooses; nil cancels.
    var saveTo: URL?, chosen: URL?

    func rights(_ question: RightsQuestion) -> RightsAnswer? {
        questions.append(question)
        return answer?(question.rights)
    }
    func lowers(_ mode: String, kind: String, folder: String?, space: String) -> Bool {
        modes.append(mode)
        return lowers
    }
    func link(_ url: URL, space: String) -> LinkChoice {
        links.append(url)
        during?(url)
        return link
    }
    func withData(_ space: String, keys: [String], bytes: Int) -> Bool? {
        shown.append(keys)
        return withData
    }
    func saveAs(_ name: String) -> URL? { saveTo }
    func importFile() -> URL? { chosen }
    func tell(_ message: String) { told.append(message) }
}

/// Listens on 127.0.0.1, on a port the system chooses, and records every connection (with its first line when the
/// client sends one) until `stop()`.
final class Listener {
    private(set) var port: UInt16 = 0
    private let socket: Int32, lock = NSLock()
    private var connections: [String] = [], stopped = false

    init() throws {
        socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(socket, 64) == 0 else { throw SpaceError("The test listener could not listen.") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &length) }
        }
        port = UInt16(bigEndian: address.sin_port)
        _ = fcntl(socket, F_SETFL, O_NONBLOCK)
        Thread.detachNewThread { [self] in serve() }
    }

    var hits: [String] { lock.withLock { connections } }

    func stop() {
        lock.withLock { stopped = true }
        close(socket)
    }

    private func serve() {
        while !lock.withLock({ stopped }) {
            var poller = pollfd(fd: socket, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, 50) > 0 else { continue }
            let client = accept(socket, nil, nil)
            guard client >= 0 else { continue }
            // An accepted socket inherits the listener's O_NONBLOCK; the request is read with a timeout instead.
            _ = fcntl(client, F_SETFL, 0)
            var wait = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = read(client, &buffer, buffer.count)
            let first = count > 0 ? String(decoding: buffer[..<count], as: UTF8.self).components(separatedBy: "\r\n")[0] : "(a connection, no request)"
            lock.withLock { connections.append(first) }
            let reply = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
            _ = reply.withCString { write(client, $0, strlen($0)) }
            close(client)
        }
    }
}

/// Waits, without blocking the main actor, until `condition` holds or `seconds` pass; whether it holds. The tests
/// await: turning the run loop by hand inside a test would hold the main queue that WebKit answers on.
@MainActor @discardableResult
func wait(_ seconds: Double = 10, until condition: () -> Bool = { false }) async -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while !condition(), Date() < end { try? await Task.sleep(nanoseconds: 20_000_000) }
    return condition()
}

/// Runs `code` as the body of an async function in the page and returns what it returns.
@MainActor
func run(_ web: WKWebView, _ code: String) async throws -> Any? {
    let value = try await web.callAsyncJavaScript(code, contentWorld: .page)
    return value is NSNull ? nil : value
}

/// Waits for the page to finish loading and `window.done` to be true.
@MainActor
func ready(_ web: WKWebView) async throws {
    guard await wait(until: { !web.isLoading && web.url != nil }) else {
        throw SpaceError("The page did not load: \(web.isLoading) \(String(describing: web.url)).")
    }
    for _ in 0..<100 where try await run(web, "return window.done === true") as? Bool != true { await wait(0.05) }
}
