// Trial T-2: CodexDriver against the REAL codex program, which talks to FakeResponsesAPI instead of a model. It runs
// only when asked, since it needs Codex on this Mac:
//
//   SOMETHING_TRIAL_CODEX=/opt/homebrew/bin/codex swift test --filter CodexTrial
//
// Each case gets a throwaway HOME and CODEX_HOME under $TMPDIR, deleted after, whatever the case's outcome. Its
// config.toml declares a model provider that points at the fake, with a made-up key given for the trial only; no
// login is there, so nothing reaches a real model or the person's ~/.codex. Two features under development are
// enabled for the trial only, so the fake model can ask a question and ask for more permissions; and the feature that
// starts Codex's background daemon is on, the worst case a stranger may have, for K-X1.
// SOMETHING_TRIAL_RECORD=<folder> also writes each case as an exchange in the format of Tests/Exchanges/codex, its
// paths made /Users/example: the raw material of a replay.
import Foundation
import Testing
@testable import SomethingAgents
import SomethingCore

@MainActor final class CodexRun {
    let api: FakeResponsesAPI
    let root: URL
    let agent: Launched
    let spawn: Spawn
    let name: String
    /// The exchange so far, in the rows of Tests/Exchanges/codex: a call's row comes before the lines it wrote.
    var rows: [[String: Any]] { exchange.rows }
    private let exchange = Exchange()
    private let owner: Bool

    var home: URL { root.appendingPathComponent("codex") }
    var work: URL { root.appendingPathComponent("work/shop") }

    /// With `after`, the case runs in that run's home and against its fake (to resume its thread, or to find it held).
    init(_ name: String, mode: String? = nil, effort: String? = nil, resume thread: String? = nil, after: CodexRun? = nil) throws {
        self.name = name
        owner = after == nil
        api = try after?.api ?? FakeResponsesAPI()
        root = after?.root ?? FileManager.default.temporaryDirectory.appendingPathComponent("codex-trial-\(UUID().uuidString)")
        let folders = [root.appendingPathComponent("codex"), root.appendingPathComponent("home"), root.appendingPathComponent("work/shop")]
        for folder in folders { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try """
            check_for_update_on_startup = false
            model = "fake-model"
            model_provider = "fake"
            [model_providers.fake]
            name = "fake"
            base_url = "\(api.url)"
            env_key = "SOMETHING_TRIAL_KEY"
            wire_api = "responses"
            requires_openai_auth = false
            supports_websockets = false
            [features]
            daemon_auto_start = true

            """.write(to: folders[0].appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let program = trialCodex!
        let launch = Launch(agent: "codex-1", folder: folders[2].path, mode: mode, effort: effort, thread: thread ?? "", resume: thread != nil)
        let environment = ["HOME": folders[1].path, "CODEX_HOME": folders[0].path, "TMPDIR": root.path,
                           "PATH": "\((program as NSString).deletingLastPathComponent):/usr/bin:/bin", "SOMETHING_TRIAL_KEY": "test-key"]
        spawn = Spawn(path: program, arguments: CodexDriver.command(launch).arguments + ["--enable", "default_mode_request_user_input", "--enable", "request_permissions_tool"],
                      folder: folders[2].path, environment: environment)
        agent = try Engine.start(CodexDriver.self, launch, spawn, asked: { _ in false }, record: { [exchange] written, line in
            // Both come on the main queue: written lines from the driver, read ones from the engine.
            let frame = (try? JSONSerialization.jsonObject(with: line)) ?? String(decoding: line, as: UTF8.self)
            exchange.rows.append([written ? "something" : "codex": frame])
        })
    }

    final class Exchange { var rows: [[String: Any]] = [["begin": true]] }

    /// Adds `row`, runs `call`, then completes the row with what the call returned under `key`.
    private func row<T>(_ row: [String: Any], _ key: String, _ call: () throws -> T) rethrows -> T {
        exchange.rows.append(row)
        let index = exchange.rows.count - 1
        let result = try call()
        exchange.rows[index][key] = result
        return result
    }

    var state: Agent { agent.agent }
    var request: Request? { agent.queue.fold.requests.first }
    var items: [Item] { agent.queue.fold.turns.flatMap(\.items) }
    var turns: [String] { agent.queue.fold.turns.map(\.state) }

    func send(_ text: String, when: String = "next") throws -> String {
        try row(["send": text, "when": when], "delivery") { try agent.send(text, when: when) }
    }

    func interrupt() throws -> Bool {
        try row([:], "interrupted") { try agent.interrupt() }
    }

    func answer(_ answer: Answer) throws -> Bool {
        let id = try #require(request).id
        let with: Any = switch answer { case .once: "once"; case .deny: "deny"; case .choice(let chosen): chosen }
        exchange.rows.append(["answer": id, "with": with])
        return try agent.answer(id, answer)
    }

    func set(model: String? = nil, mode: String? = nil, effort: String? = nil) throws -> String {
        try row(["set": ["model": model, "mode": mode, "effort": effort].compactMapValues { $0 }], "applied") {
            try agent.driver.set(model: model, mode: mode, effort: effort)
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

    /// Stops the program by the ladder (its input closed), and waits for its end. The home stays, for a resume.
    func finish() async throws {
        exchange.rows.append(["stop": true])
        let stopped = Stopped()
        spawn.stop(cap: 8) { stopped.done = true }
        try await until("the end", seconds: 12) { state.alive == false && stopped.done }
        exchange.rows.append(["ended": 0])
        save()
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
        guard owner else { return }
        api.stop()
        try? FileManager.default.removeItem(at: root)
    }

    /// With SOMETHING_TRIAL_RECORD, writes the rows to <folder>/<case>.jsonl, with /Users/example paths for the throwaway folders.
    func save() {
        guard let folder = ProcessInfo.processInfo.environment["SOMETHING_TRIAL_RECORD"] else { return }
        var text = rows.compactMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .withoutEscapingSlashes]) }
            .map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n") + "\n"
        for prefix in ["/private" + root.path, root.path] {
            text = text.replacingOccurrences(of: prefix + "/work/shop", with: "/Users/example/shop")
                .replacingOccurrences(of: prefix + "/codex", with: "/Users/example/.codex").replacingOccurrences(of: prefix, with: "/Users/example/trial")
        }
        // Codex names the machine it runs on.
        text = text.replacingOccurrences(of: #""serverName":"[^"]*""#, with: #""serverName":"example-mac""#, options: .regularExpression)
        try? text.write(toFile: "\(folder)/\(name).jsonl", atomically: true, encoding: .utf8)
    }
}

/// The codex program the trial runs, when asked for and there.
let trialCodex = ProcessInfo.processInfo.environment["SOMETHING_TRIAL_CODEX"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }

@Suite(.serialized, .enabled(if: trialCodex != nil, "T-2 needs Codex: set SOMETHING_TRIAL_CODEX to its program's path."))
@MainActor struct CodexTrial {

    @Test func aTurnStartsAndEnds() async throws {
        let run = try CodexRun("turn")
        defer { run.cleanup() }
        try await run.until("the thread") { run.state.thread != nil }
        #expect(try run.send("Hello there.") == "started")
        try await run.until("a reply") { run.items.contains { $0.author == "agent" } && run.state.state == "idle" }
        #expect(run.items.map(\.author) == ["person", "agent"])
        #expect(run.state.model == "fake-model")
        #expect(run.state.mode == "on-request", "a launch without a mode asks when needed")
        #expect(run.state.options.model?.isEmpty == false, "model/list reads Codex's own catalog")
        try await run.finish()
        #expect(run.state.state == "done")
        #expect(run.state.error == nil)
    }

    @Test func aPermissionIsAllowedOnce() async throws {
        let run = try CodexRun("permission-once")
        defer { run.cleanup() }
        _ = try run.send("Please run-echo now.")
        try await run.until("a permission") { run.request != nil }
        #expect((run.state.state, run.state.waiting) == ("waiting", "permission"))
        #expect(run.request?.tool == "commandExecution")
        #expect(run.request?.about?.contains("touch invented.txt") == true, "Codex names the shell it runs the command with")
        #expect(try run.answer(.once))
        try await run.until("the end of the turn") { run.state.state == "idle" && run.turns == ["done"] }
        let tool = try #require(run.items.first { $0.kind == "tool" })
        #expect(tool.tool == Tool(name: "commandExecution", status: "done"))
        #expect(tool.decision == Decision(by: "person", outcome: "allowed"))
        #expect(FileManager.default.fileExists(atPath: run.work.appendingPathComponent("invented.txt").path))
        try await run.finish()
    }

    @Test func aPermissionIsDenied() async throws {
        let run = try CodexRun("deny")
        defer { run.cleanup() }
        _ = try run.send("Please run-echo now.")
        try await run.until("a permission") { run.request != nil }
        #expect(try run.answer(.deny))
        try await run.until("the end of the turn") { run.state.state == "idle" && run.turns == ["done"] }
        let tool = try #require(run.items.first { $0.kind == "tool" })
        #expect(tool.tool?.status == "failed")
        #expect(tool.decision == Decision(by: "person", outcome: "denied"))
        #expect(!FileManager.default.fileExists(atPath: run.work.appendingPathComponent("invented.txt").path))
        try await run.finish()
    }

    /// V1 answered this request with a decision, which Codex takes and grants nothing by: the permissions go back.
    @Test func morePermissionsAreGranted() async throws {
        let run = try CodexRun("permissions")
        defer { run.cleanup() }
        _ = try run.send("Please need-more access.")
        try await run.until("a permission") { run.request != nil }
        #expect(run.request?.tool == "permissions")
        #expect(try run.answer(.once))
        try await run.until("the end of the turn") { run.state.state == "idle" && run.api.toolOutputs.count == 1 }
        #expect(run.api.toolOutputs.first?.contains("true") == true, "tool output: \(run.api.toolOutputs)")
        try await run.finish()
    }

    @Test func anInterruptWithdrawsARequest() async throws {
        let run = try CodexRun("withdrawn")
        defer { run.cleanup() }
        _ = try run.send("Please run-echo now.")
        try await run.until("a permission") { run.request != nil }
        let id = try #require(run.request).id
        #expect(try run.interrupt())
        try await run.until("the request to close") { run.request == nil && run.turns == ["interrupted"] }
        #expect(run.agent.prompt(id) == nil)
        try await run.finish()
    }

    @Test func aQuestionIsAnswered() async throws {
        let run = try CodexRun("question")
        defer { run.cleanup() }
        _ = try run.send("Please ask-me something.")
        try await run.until("a question") { run.request != nil }
        #expect(run.request?.kind == "question")
        #expect(run.state.waiting == "answer")
        #expect(run.agent.prompt(try #require(run.request).id)?.questions == [Question(header: "Colour", text: "Which colour for the invented button?", options: ["Blue", "Green"], multiple: false)])
        #expect(try run.answer(.choice([["Green"]])))
        try await run.until("the end of the turn") { run.state.state == "idle" && run.api.toolOutputs.count == 1 }
        #expect(run.api.toolOutputs.first?.contains("Green") == true, "tool output: \(run.api.toolOutputs)")
        try await run.finish()
    }

    @Test func aSteerJoinsTheTurnAndQueuedMessagesWait() async throws {
        let run = try CodexRun("steer-queue")
        defer { run.cleanup() }
        _ = try run.send("Please run-sleep for me.")
        try await run.until("the turn") { run.turns == ["working"] && run.items.count == 1 }
        #expect(try run.send("Steered: use the small one.", when: "now") == "steered")
        #expect(try run.send("Queued: then the docs.") == "queued")
        #expect(try run.send("Queued: and the tests.") == "queued")
        #expect(run.state.queue.map(\.text) == ["Queued: then the docs.", "Queued: and the tests."])
        try await run.until("three turns") { run.turns == ["done", "done", "done"] && run.state.state == "idle" }
        let received = run.api.received
        let order = ["Steered: use the small one.", "Queued: then the docs.", "Queued: and the tests."].map { text in received.firstIndex { $0.contains(text) } }
        #expect(order.allSatisfy { $0 != nil } && order == order.sorted { ($0 ?? 0) < ($1 ?? 0) }, "received: \(received)")
        try await run.finish()
    }

    /// The hang V1 had: an interrupt sent to a thread whose turn was interrupted is never answered. None is sent.
    @Test func anInterruptStopsTheTurnOnce() async throws {
        let run = try CodexRun("interrupt")
        defer { run.cleanup() }
        _ = try run.send("Please run-sleep for me.")
        try await run.until("the turn") { run.turns == ["working"] && run.items.count == 1 }
        _ = try run.send("Queued: dropped.")
        #expect(try run.interrupt())
        #expect(run.state.queue.isEmpty)
        try await run.until("the interrupted turn") { run.turns == ["interrupted"] }
        #expect(run.state.state == "interrupted")
        let written = run.rows.count
        #expect(try run.interrupt() == false)
        #expect(run.rows.count == written + 1, "nothing is written to Codex")
        _ = try run.send("Hello again.")
        try await run.until("the next turn") { run.turns == ["interrupted", "done"] }
        #expect(!run.api.received.contains { $0.contains("Queued: dropped.") })
        #expect(run.state.error == nil)
        try await run.finish()
    }

    @Test func modelModeAndEffortApplyAtTheNextTurn() async throws {
        let run = try CodexRun("set")
        defer { run.cleanup() }
        try await run.until("the thread") { run.state.thread != nil }
        #expect(try run.set(model: "other-model", mode: "never", effort: "high") == "next-turn")
        #expect(run.state.model == "fake-model", "the state shows a value once Codex reports it")
        _ = try run.send("Hello there.")
        try await run.until("the turn") { run.turns == ["done"] && run.state.model == "other-model" }
        #expect((run.state.mode, run.state.effort) == ("never", "high"))
        #expect(run.api.modelsAsked.last == "other-model")
        #expect(run.api.effortsAsked.last == "high")
        try await run.finish()
    }

    @Test func aConversationIsResumed() async throws {
        let first = try CodexRun("resume-first")
        defer { first.cleanup() }
        _ = try first.send("Hello there.")
        try await first.until("a reply") { first.turns == ["done"] }
        let thread = try #require(first.state.thread)
        try await first.finish()
        let run = try CodexRun("resume", resume: thread, after: first)
        defer { run.cleanup() }
        #expect(run.state.thread == thread, "a resumed thread is known before Codex answers")
        try await run.until("the thread") { run.state.model != nil }
        _ = try run.send("Hello again.")
        try await run.until("a reply") { run.turns == ["done"] && run.state.state == "idle" }
        #expect(first.api.received.last == "Hello again.")
        let sent = first.api.messagesSent
        #expect(sent.count == 2 && sent[1] > sent[0], "the resumed turn carries the first one's words: \(sent)")
        #expect(run.state.error == nil)
        try await run.finish()
    }

    /// One writer at a time: a thread another app-server holds gives HELD_ELSEWHERE and its sentence.
    @Test func aHeldConversationSaysWho() async throws {
        let first = try CodexRun("held-first")
        defer { first.cleanup() }
        _ = try first.send("Hello there.")
        try await first.until("a reply") { first.turns == ["done"] }
        let run = try CodexRun("held", resume: first.state.thread!, after: first)
        defer { run.cleanup() }
        try await run.until("the refusal") { run.state.alive == false }
        #expect(run.state.error?.code == "HELD_ELSEWHERE")
        #expect(run.state.error?.message.contains("codex app-server daemon stop") == true)
        try await first.finish()
    }

    /// Closing its input ends Codex cleanly; and a stdio app-server leaves no background daemon (K-X1).
    @Test func closingTheInputStopsCleanly() async throws {
        let run = try CodexRun("stop")
        defer { run.cleanup() }
        _ = try run.send("Hello there.")
        try await run.until("a reply") { run.turns == ["done"] }
        try await run.finish()
        #expect(run.state.state == "done")
        #expect(run.state.error == nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: run.home.path)
        #expect(!names.contains("packages") && !names.contains("app-server-daemon") && !names.contains("app-server-control"), "\(names.sorted())")
        let left = Process()
        left.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        left.arguments = ["-f", run.root.path]
        try left.run()
        left.waitUntilExit()
        #expect(left.terminationStatus == 1, "no process of the trial is left")
    }
}
