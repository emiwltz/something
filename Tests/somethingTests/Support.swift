// What the app's tests share: a throwaway home with spaces in it, a person who answers without a window, a listener
// on 127.0.0.1 that counts every connection, and the run loop turned until WebKit has answered. No window is shown.
import AppKit
import Darwin
import Foundation
import SomethingCore
import Testing
import WebKit
@testable import SomethingAgents
@testable import something

/// Whether the window suites run: WebKit's views and AppKit's windows need a window server. A Mac where someone is
/// logged in has one, GitHub's macOS runners too; a session opened over ssh before anyone logs in has none, and the
/// suites are skipped there. On CI they always run, so a runner without a window server fails instead of passing
/// while the lockdown test never ran.
let windowServer = CGSessionCopyCurrentDictionary() != nil || ProcessInfo.processInfo.environment["CI"] != nil
let windowServerMissing: Comment = "This session has no window server, and WebKit and AppKit windows cannot run without one."

/// A home in the temporary folder, removed by `remove()`; the person's own folders are never touched. `prefix` names
/// it in $TMPDIR, one per suite, so that each suite's `.leavesNothing` counts only the folders it made.
struct Home {
    let root: URL
    init(prefix: String) { root = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)\(UUID().uuidString)") }
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
        try SpaceWindow(space: space, places: places, engine: engine(), ask: ask, share: Home.share,
                        rules: try await Lockdown.ruleList())
    }

    /// An engine that finds no agent program: its PATH is an empty folder of this home, and the system's install
    /// folders are not searched (NoRealAgentTests), so nothing a space asks reaches a real agent.
    func engine() -> Engine {
        let environment = ["HOME": root.path, "PATH": root.appendingPathComponent("bin").path + ":/usr/bin:/bin", "SHELL": "/bin/sh"]
        let engine = Engine(environment: environment)
        engine.programs.systemFolders = []
        return engine
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
    /// The name typed for a new space; nil cancels.
    var named: String?

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
    func newName() -> String? { named }
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

/// A borderless window at alpha 0, far off the screen, that holds a view to receive real clicks of the mouse. It is
/// never ordered front, so it takes no focus.
@MainActor
struct Offscreen {
    let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 640), styleMask: .borderless,
                          backing: .buffered, defer: false)
    let view: NSView

    init(_ view: NSView) {
        self.view = view
        window.alphaValue = 0
        window.contentView = view
    }

    /// A press and a release of the left button at `x`, `y` in the window (from its bottom left).
    func click(x: Double, y: Double) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [],
                                                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                        context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            type == .leftMouseDown ? view.mouseDown(with: event) : view.mouseUp(with: event)
        }
    }
}

/// Runs `work`, which waits for a child process, on a thread of its own, and returns what it returns or throws. The
/// main actor is never held: every main-actor suite shares it with WebKit and the engine's main queue, and a child
/// that takes seconds on a slow Mac (a 3-core runner) would make their deadlines pass while nothing could run.
func offMain<T>(_ work: @escaping () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        Thread.detachNewThread { continuation.resume(with: Result { try work() }) }
    }
}

/// Waits, without blocking the main actor, until `condition` holds or `seconds` pass; whether it holds. The tests
/// await: turning the run loop by hand inside a test would hold the main queue that WebKit answers on. The default is
/// only a guard against a hang: WebKit's first processes start slowly on a busy Mac.
@MainActor @discardableResult
func wait(_ seconds: Double = 30, until condition: () -> Bool = { false }) async -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while !condition(), Date() < end { try? await Task.sleep(nanoseconds: 20_000_000) }
    return condition()
}

/// Runs `code` as the body of an async function in the space's frame (the app's page while the space is blocked)
/// and returns what it returns.
@MainActor
func run(_ window: SpaceWindow, _ code: String) async throws -> Any? {
    let value = try await window.web.callAsyncJavaScript(code, in: window.frame, contentWorld: .page)
    return value is NSNull ? nil : value
}

/// Waits for the space to finish loading in its frame and `window.done` to be true.
@MainActor
func ready(_ window: SpaceWindow) async throws {
    guard await wait(until: { !window.web.isLoading && window.frame != nil }) else {
        throw SpaceError("The space did not load: \(window.web.isLoading) \(String(describing: window.web.url)).")
    }
    for _ in 0..<100 where try await run(window, "return window.done === true") as? Bool != true { await wait(0.05) }
}

/// An invented permission request of Claude's, as its plan-B hook reads it on its input.
let inventedRequest = #"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"}}"#

/// Runs a built `program` with `words` (as Claude's plan-B hook runs it, for `hook permission`), in `home` with the
/// system's PATH only, `input` on its input; its status and outputs. Stopped after 30 s, so that a program that never
/// answers fails the test.
func runBuilt(_ program: URL, _ words: [String], home: Home, input text: String = inventedRequest) async throws -> (status: Int32, out: String, err: String) {
    try await offMain { try runBuiltWaiting(program, words, home: home, input: text) }
}

private func runBuiltWaiting(_ program: URL, _ words: [String], home: Home, input text: String) throws -> (status: Int32, out: String, err: String) {
    let process = Process(), input = Pipe(), out = Pipe(), err = Pipe()
    process.executableURL = program
    process.arguments = words
    process.environment = ["HOME": home.root.path, "PATH": "/usr/bin:/bin"]
    (process.standardInput, process.standardOutput, process.standardError) = (input, out, err)
    try process.run()
    input.fileHandleForWriting.write(Data(text.utf8))
    try input.fileHandleForWriting.close()
    let deadline = DispatchWorkItem { process.terminate() }
    DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: deadline)
    let printed = out.fileHandleForReading.readDataToEndOfFile(), errors = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    deadline.cancel()
    return (process.terminationStatus, String(decoding: printed, as: UTF8.self), String(decoding: errors, as: UTF8.self))
}

/// The decision a hook printed for Claude: its behavior and its message.
func hookDecision(_ out: String) -> (behavior: String?, message: String?) {
    let printed = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any]
    let decision = (printed?["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
    return (decision?["behavior"] as? String, decision?["message"] as? String)
}
