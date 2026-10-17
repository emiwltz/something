// Trial T-4: PiDriver against the REAL pi program, which talks to FakeResponsesAPI's Chat Completions instead of a
// model. It runs only when asked, since it needs pi on this Mac:
//
//   SOMETHING_TRIAL_PI=$HOME/.pi/agent/install/releases/<version>/node_modules/.bin/pi swift test --filter PiTrial
//
// That is the program pi's launcher ($HOME/.local/bin/pi) runs. Given the launcher, pi also touches its install folder
// in ~/.pi at each start, which the check below rightly refuses.
// Each case gets a throwaway HOME and pi agent folder (PI_CODING_AGENT_DIR) under $TMPDIR, deleted after, whatever the
// case's outcome. Its models.json declares one OpenAI-compatible provider that points at the fake, with a made-up key,
// and PI_OFFLINE stops pi's own catalog refreshes, so nothing reaches a real model or the person's ~/.pi: each case
// compares the names and modification dates under ~/.pi before and after (no file is read).
// SOMETHING_TRIAL_RECORD=<folder> also writes each case as an exchange in the format of Tests/Exchanges/pi, its paths
// made /Users/example, without the lines the driver never reads that carry pi's system prompt (message_update, the
// system message, agent_end's copy of the run): the raw material of a replay.
import Darwin
import Foundation
import Testing
@testable import SomethingAgents
import SomethingCore

@MainActor final class PiRun {
    let api: FakeResponsesAPI
    let root: URL
    let agent: Launched
    let spawn: Spawn
    let name: String
    var rows: [[String: Any]] { exchange.rows }
    private let exchange: CodexRun.Exchange
    private let owner: Bool
    private let note: [String: Any]
    private let stopAsked: Stopped
    /// The person's ~/.pi when the case began.
    private let realPi: [String: Date]

    var work: URL { root.appendingPathComponent("work/shop") }

    /// With `after`, the case runs in that run's home and against its fake (to resume its conversation).
    init(_ name: String, model: String? = nil, effort: String? = nil, resume file: String? = nil, after: PiRun? = nil) throws {
        self.name = name
        owner = after == nil
        realPi = PiRun.realPi()
        note = ["model": model, "effort": effort, "resume": file].compactMapValues { $0 }
        api = try after?.api ?? FakeResponsesAPI()
        api.pi = true
        let root = after?.root ?? FileManager.default.temporaryDirectory.appendingPathComponent("pi-trial-\(UUID().uuidString)")
        self.root = root
        for folder in ["home", "agent", "work/shop"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        let fake: [String: Any] = ["id": "fake-1", "name": "Fake One", "reasoning": true, "input": ["text"], "contextWindow": 32_000, "maxTokens": 4_096]
        var other = fake
        (other["id"], other["name"]) = ("fake-2", "Fake Two")
        let models: [String: Any] = ["providers": ["fake": ["baseUrl": api.url, "api": "openai-completions", "apiKey": "test-key", "models": [fake, other]]]]
        try JSONSerialization.data(withJSONObject: models).write(to: root.appendingPathComponent("agent/models.json"))
        let settings = ["defaultProvider": "fake", "defaultModel": "fake-1"]
        try JSONSerialization.data(withJSONObject: settings).write(to: root.appendingPathComponent("agent/settings.json"))
        let program = trialPi!
        // A resumed pi runs in its conversation's folder, as the engine launches it.
        let folder = try file.map(PiDriver.resumable) ?? root.appendingPathComponent("work/shop").path
        let launch = Launch(agent: "pi-1", folder: folder, model: model, effort: effort, thread: file ?? "", resume: file != nil)
        // pi's launcher is a shell script that runs node from the PATH.
        let node = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init)
            .first { FileManager.default.isExecutableFile(atPath: "\($0)/node") } ?? "/usr/bin"
        let environment = ["HOME": root.appendingPathComponent("home").path, "PI_CODING_AGENT_DIR": root.appendingPathComponent("agent").path,
                           "PI_OFFLINE": "1", "TMPDIR": root.path, "TERM": "dumb", "PATH": "\(node):/usr/bin:/bin"]
        spawn = Spawn(path: program, arguments: PiDriver.command(launch).arguments, folder: launch.folder, environment: environment)
        let (stop, exchange) = (Stopped(), CodexRun.Exchange())
        (stopAsked, self.exchange) = (stop, exchange)
        agent = try Engine.start(PiDriver.self, launch, spawn, asked: { _ in stop.done }, record: { written, line in
            let frame = (try? JSONSerialization.jsonObject(with: line)) ?? String(decoding: line, as: UTF8.self)
            guard written || !PiRun.unread(frame) else { return }
            exchange.rows.append([written ? "something" : "pi": frame])
        })
    }

    /// Lines the driver never reads, which carry pi's whole system prompt or repeat a run.
    static func unread(_ frame: Any) -> Bool {
        guard let frame = frame as? [String: Any] else { return false }
        let role = (frame["message"] as? [String: Any])?["role"] as? String
        return frame["type"] as? String == "message_update" || frame["type"] as? String == "agent_end" || role == "system"
    }

    var state: Agent { agent.agent }
    var items: [Item] { agent.queue.fold.turns.flatMap(\.items) }
    var turns: [String] { agent.queue.fold.turns.map(\.state) }

    /// Adds `row`, runs `call`, then completes the row with what the call returned under `key`.
    private func row<T>(_ row: [String: Any], _ key: String, _ call: () throws -> T) rethrows -> T {
        exchange.rows.append(row)
        let index = exchange.rows.count - 1
        let result = try call()
        exchange.rows[index][key] = result
        return result
    }

    func send(_ text: String, when: String = "next") throws -> String {
        try row(["send": text, "when": when], "delivery") { try agent.send(text, when: when) }
    }

    func interrupt() throws -> Bool { try row([:], "interrupted") { try agent.interrupt() } }

    func set(model: String? = nil, effort: String? = nil) throws -> String {
        try row(["set": ["model": model, "effort": effort].compactMapValues { $0 }], "applied") {
            try agent.driver.set(model: model, mode: nil, effort: effort)
        }
    }

    func until(_ what: String, seconds: Double = 40, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < end else {
                cleanup()
                Issue.record("\(name): timed out waiting for \(what); state \(state.state), error \(String(describing: state.error)); stderr: \(spawn.errorTail.suffix(400))")
                throw CancellationError()
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Stops the program by the ladder, and waits for its end. Returns how long the ladder took. The home stays.
    @discardableResult func finish() async throws -> TimeInterval {
        exchange.rows.append(["stop": true])
        stopAsked.done = true
        let stopped = Stopped()
        let begun = Date()
        spawn.stop(cap: 8) { stopped.done = true }
        try await until("the end", seconds: 12) { state.alive == false && stopped.done }
        exchange.rows.append(["ended": 0])
        save()
        return Date().timeIntervalSince(begun)
    }

    private var cleaned = false

    /// Stops what the case started and, for the run that made it, removes the throwaway home; once.
    func cleanup() {
        guard !cleaned else { return }
        cleaned = true
        save()
        let stopped = DispatchSemaphore(value: 0)
        spawn.stop(cap: 2) { stopped.signal() }
        _ = stopped.wait(timeout: .now() + 3)
        if PiRun.realPi() != realPi { Issue.record("\(name): the person's ~/.pi changed during the case") }
        guard owner else { return }
        api.stop()
        try? FileManager.default.removeItem(at: root)
    }

    /// Each name under the person's ~/.pi with its modification date; their contents are never read.
    static func realPi() -> [String: Date] {
        let home = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".pi")
        var found: [String: Date] = [:]
        let names = FileManager.default.enumerator(at: home, includingPropertiesForKeys: [.contentModificationDateKey])
        while let url = names?.nextObject() as? URL {
            found[url.path] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
        return found
    }

    /// True once no process of pi's group (Spawn gives it its own) is left, within two seconds.
    func nothingLeft() async throws -> Bool {
        let group = spawn.pid
        for _ in 0..<40 {
            if kill(-group, 0) == -1 && errno == ESRCH { return true }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    /// True once no process runs `command`, within two seconds.
    static func gone(_ command: String) async throws -> Bool {
        for _ in 0..<40 {
            let left = Process()
            left.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            left.arguments = ["-fx", command]
            left.standardOutput = FileHandle.nullDevice
            try left.run()
            left.waitUntilExit()
            if left.terminationStatus == 1 { return true }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    /// With SOMETHING_TRIAL_RECORD, writes the rows to <folder>/<case>.jsonl, with /Users/example paths for the throwaway
    /// folders, the work folder in pi's dashed form (its sessions folder) included, and for this Mac's home.
    func save() {
        guard let folder = ProcessInfo.processInfo.environment["SOMETHING_TRIAL_RECORD"] else { return }
        let first = note.merging(["note": "Recorded in trial T-4 (pi \(PiDriver.tested), a fake model, invented text, paths made /Users/example)."]) { _, new in new }
        var text = ([first] + rows).compactMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .withoutEscapingSlashes]) }
            .map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n") + "\n"
        func dashed(_ path: String) -> String { path.dropFirst().replacingOccurrences(of: "/", with: "-") }
        for prefix in ["/private" + root.path, root.path] {
            text = text.replacingOccurrences(of: prefix + "/work/shop", with: "/Users/example/shop").replacingOccurrences(of: prefix, with: "/Users/example/trial")
                .replacingOccurrences(of: dashed(prefix + "/work/shop"), with: "Users-example-shop")
        }
        text = text.replacingOccurrences(of: NSHomeDirectory(), with: "/Users/example")
        try? text.write(toFile: "\(folder)/\(name).jsonl", atomically: true, encoding: .utf8)
    }
}

/// The pi program the trial runs, when asked for and there.
let trialPi = ProcessInfo.processInfo.environment["SOMETHING_TRIAL_PI"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }

@Suite(.serialized, .enabled(if: trialPi != nil, "T-4 needs pi: set SOMETHING_TRIAL_PI to its program's path."))
@MainActor struct PiTrial {

    @Test func aTurnStartsAndEnds() async throws {
        let run = try PiRun("turn")
        defer { run.cleanup() }
        try await run.until("the state") { run.state.thread != nil && run.state.model != nil && run.state.options.effort != nil }
        let sessions = run.root.appendingPathComponent("agent/sessions").resolvingSymlinksInPath().path + "/"
        #expect(run.state.thread.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path.hasPrefix(sessions) } == true, "pi writes in the throwaway folder")
        #expect((run.state.model, run.state.mode) == ("fake/fake-1", nil))
        #expect(run.state.options.model?.map(\.value) == ["fake/fake-1", "fake/fake-2"])
        #expect(run.state.options.mode == [])
        #expect(run.state.can.mode == false && run.state.because["mode"] == PiDriver.limits["mode"])
        #expect(try run.send("Hello there.") == "started")
        try await run.until("a reply") { run.items.contains { $0.author == "agent" } && run.state.state == "idle" }
        #expect(run.items.map(\.author) == ["person", "agent"])
        #expect(run.items.last?.text == "Invented reply number 5.")
        #expect(run.state.waiting == "none", "pi never asks")
        try await run.finish()
        #expect(run.state.state == "done")
        #expect(run.state.error == nil)
    }

    /// pi runs a command without asking: no request ever opens, and the tool is shown.
    @Test func aCommandRunsWithoutAsking() async throws {
        let run = try PiRun("tool")
        defer { run.cleanup() }
        _ = try run.send("Please run-echo now.")
        try await run.until("the end of the turn") { run.turns == ["done"] && run.state.state == "idle" }
        let tool = try #require(run.items.first { $0.kind == "tool" })
        #expect(tool.tool == Tool(name: "bash", status: "done"))
        #expect(tool.text == "touch invented.txt")
        #expect(run.agent.queue.fold.requests.isEmpty)
        #expect(FileManager.default.fileExists(atPath: run.work.appendingPathComponent("invented.txt").path))
        #expect(run.items.last?.text.hasPrefix("Invented summary") == true)
        try await run.finish()
    }

    /// A steer joins the running turn; a message for later waits in something's queue for the next one.
    @Test func aSteerJoinsAndQueuedMessagesWait() async throws {
        let run = try PiRun("steer-queue")
        defer { run.cleanup() }
        _ = try run.send("Please run-sleep for me.")
        try await run.until("the stream") { run.api.received.count == 1 && run.state.state == "working" }
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(try run.send("Steered: also the docs.", when: "now") == "steered")
        #expect(try run.send("Queued: and the tests.") == "queued")
        #expect(run.state.queue.map(\.text) == ["Queued: and the tests."])
        try await run.until("two turns", seconds: 60) { run.turns == ["done", "done"] && run.state.state == "idle" }
        #expect(run.api.received == ["Please run-sleep for me.", "Steered: also the docs.", "Queued: and the tests."])
        #expect(run.items.filter { $0.author == "person" }.map(\.text) == ["Please run-sleep for me.", "Steered: also the docs.", "Queued: and the tests."])
        #expect(run.state.error == nil)
        try await run.finish()
    }

    @Test func anInterruptStopsTheTurn() async throws {
        let run = try PiRun("interrupt")
        defer { run.cleanup() }
        _ = try run.send("Please run-sleep for me.")
        try await run.until("the stream") { run.api.received.count == 1 && run.state.state == "working" }
        try await Task.sleep(nanoseconds: 500_000_000)
        _ = try run.send("Queued: dropped.")
        #expect(try run.interrupt())
        #expect(run.state.queue.isEmpty)
        try await run.until("the interrupted turn") { run.turns == ["interrupted"] }
        #expect(run.state.state == "interrupted")
        #expect(try run.interrupt() == false)
        _ = try run.send("Hello again.")
        try await run.until("the next turn") { run.turns == ["interrupted", "done"] && run.state.state == "idle" }
        #expect(!run.api.received.contains("Queued: dropped."))
        #expect(run.state.error == nil)
        try await run.finish()
    }

    /// An abort in a tool ends pi's run with stopReason "error": it is still the interrupt something asked for.
    @Test func anInterruptStopsATool() async throws {
        let run = try PiRun("interrupt-tool")
        defer { run.cleanup() }
        _ = try run.send("Please run-wait now.")
        try await run.until("the tool") { run.items.contains { $0.tool?.status == "running" } }
        #expect(try run.interrupt())
        try await run.until("the interrupted turn") { run.turns == ["interrupted"] && run.state.state == "interrupted" }
        #expect(run.items.first { $0.kind == "tool" }?.tool?.status == "failed")
        #expect(run.state.error == nil)
        #expect(try await PiRun.gone(FakeResponsesAPI.piWait), "the abort ends the tool's command")
        try await run.finish()
        #expect(try await run.nothingLeft(), "no process of the trial is left")
    }

    /// Each value is read back with get_state; one pi does not take is said, and the value in force stays.
    @Test func modelAndEffortAreReadBack() async throws {
        let run = try PiRun("set")
        defer { run.cleanup() }
        try await run.until("the state") { run.state.model != nil && run.state.options.effort != nil }
        #expect(throws: CodedError("NOT_SUPPORTED", PiDriver.limits["mode"]!)) { try run.agent.driver.set(model: nil, mode: "plan", effort: nil) }
        #expect(try run.set(model: "fake/fake-2", effort: "low") == "now")
        try await run.until("the values") { run.state.model == "fake/fake-2" && run.state.effort == "low" }
        _ = try run.send("Hello there.")
        try await run.until("the turn") { run.turns == ["done"] && run.state.state == "idle" }
        #expect(run.api.modelsAsked.last == "fake-2")
        #expect(run.state.error == nil)
        #expect(try run.set(model: "fake/missing") == "now")
        try await run.until("the refusal") { run.state.error != nil }
        #expect(run.state.error?.code == "VALUE_NOT_OFFERED")
        #expect(run.state.model == "fake/fake-2")
        try await run.finish()
    }

    /// A model and a thinking level given at launch are the ones pi reports.
    @Test func aLaunchTakesItsModelAndEffort() async throws {
        let run = try PiRun("launch-model", model: "fake/fake-2", effort: "high")
        defer { run.cleanup() }
        try await run.until("the state") { run.state.model != nil && run.state.effort != nil }
        #expect((run.state.model, run.state.effort) == ("fake/fake-2", "high"))
        try await run.finish()
    }

    @Test func aConversationIsResumed() async throws {
        let first = try PiRun("resume-first")
        defer { first.cleanup() }
        _ = try first.send("Hello there.")
        try await first.until("a reply") { first.turns == ["done"] && first.state.state == "idle" }
        let file = try #require(first.state.thread)
        try await first.finish()
        let folder = try PiDriver.resumable(file)
        #expect(URL(fileURLWithPath: folder).resolvingSymlinksInPath() == first.work.resolvingSymlinksInPath(), "the header names the first run's folder")
        let run = try PiRun("resume", resume: file, after: first)
        #expect(run.state.folder == folder)
        defer { run.cleanup() }
        #expect(run.state.thread == file, "a resumed conversation is known before pi answers")
        try await run.until("the state") { run.state.model != nil }
        _ = try run.send("Hello again.")
        try await run.until("a reply") { run.turns == ["done"] && run.state.state == "idle" }
        #expect(first.api.messagesSent == [1, 2], "the resumed turn carries the first one's words")
        #expect(run.state.thread == file)
        try await run.finish()
    }

    /// The ladder closes pi's input mid-run: it exits at once, without a signal, and leaves nothing behind.
    @Test func theLadderClosesTheInput() async throws {
        let run = try PiRun("stop")
        defer { run.cleanup() }
        _ = try run.send("Please run-sleep for me.")
        try await run.until("the stream") { run.api.received.count == 1 && run.state.state == "working" }
        try await Task.sleep(nanoseconds: 500_000_000)
        let took = try await run.finish()
        #expect(took < 3, "the input's end, without SIGTERM: \(took) s")
        #expect(run.state.state == "interrupted")
        #expect(run.state.error == nil)
        #expect(try await run.nothingLeft(), "no process of the trial is left")
    }
}
