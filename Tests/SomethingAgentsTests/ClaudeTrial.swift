// Trial T-1: ClaudeDriver against the REAL claude program, which talks to FakeMessagesAPI instead of a model. It runs
// only when asked, since it needs Claude Code on this Mac:
//
//   SOMETHING_TRIAL_CLAUDE=/opt/homebrew/bin/claude swift test --filter ClaudeTrial
//
// Each case gets a throwaway HOME and CLAUDE_CONFIG_DIR under $TMPDIR, deleted after, whatever the case's outcome:
// no login is there, so the made-up key "test-key", given for the trial only, is the only credential Claude has, and
// ANTHROPIC_BASE_URL sends every request to the fake. No `--bare`: under it Claude runs no hook given in --settings
// and offers no AskUserQuestion, so plan B and the question could not be proven. `--tools` keeps Claude to the tools
// the script uses.
// SOMETHING_TRIAL_RECORD=<folder> also writes each case's lines there, the raw material of Tests/Exchanges/claude.
import Foundation
import Testing
@testable import SomethingAgents
import SomethingCore

final class Stopped: @unchecked Sendable { var done = false }

@MainActor final class ClaudeRun {
    let api: FakeMessagesAPI
    let root: URL
    let agent: Launched
    let spawn: Spawn
    var lines: [(written: Bool, line: String)] = []
    var asked = false

    /// With `planB`, Claude asks through the real hook command (built from PermissionSpool.swift) and a spool.
    init(_ name: String, mode: String = "default", effort: String? = nil, planB: Bool = false) async throws {
        self.name = name
        api = try FakeMessagesAPI()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("claude-trial-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home"), work = root.appendingPathComponent("work/shop")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let program = trialClaude!
        let launch = Launch(agent: "claude-trial", folder: work.path, mode: mode, effort: effort)
        var spool: PermissionSpool?
        var command = ClaudeDriver.command(launch)
        if planB {
            let tools = root.appendingPathComponent("tools"), hook = tools.appendingPathComponent("something").path
            try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
            try await PlanBTests.buildHook(hook, in: tools)
            // The product's own path shape, space included, so the hook command's quoting meets the real shell.
            spool = PermissionSpool(folder: root.appendingPathComponent("Application Support/spool/claude-trial-\(launch.thread)").path)
            command = ClaudeDriver.command(launch, hook: [hook, "hook", "permission", "--spool", spool!.folder])
        }
        var environment = ["HOME": home.path, "CLAUDE_CONFIG_DIR": home.appendingPathComponent(".claude").path,
                           "PATH": "\((program as NSString).deletingLastPathComponent):/usr/bin:/bin", "TMPDIR": root.path,
                           "ANTHROPIC_BASE_URL": api.url, "ANTHROPIC_API_KEY": "test-key",
                           "DISABLE_AUTOUPDATER": "1", "DISABLE_TELEMETRY": "1", "DISABLE_ERROR_REPORTING": "1",
                           "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"]
        environment.merge(command.adding) { _, added in added }
        spawn = Spawn(path: program, arguments: command.arguments + ["--tools", "Bash,Edit,Read,AskUserQuestion"], folder: work.path, environment: environment)
        var record: (Bool, Data) -> Void = { _, _ in }
        agent = try Engine.start(ClaudeDriver.self, launch, spawn, spool: spool, asked: { _ in false }, record: { record($0, $1) })
        record = { [weak self] written, line in
            DispatchQueue.main.async { self?.lines.append((written, String(decoding: line, as: UTF8.self))) }
        }
    }

    let name: String
    var state: Agent { agent.agent }

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

    var request: Request? { agent.queue.fold.requests.first }
    var items: [Item] { agent.queue.fold.turns.flatMap(\.items) }

    /// With SOMETHING_TRIAL_RECORD, writes the lines in (<) and out (>) to <folder>/<case>.log.
    func save() {
        guard let folder = ProcessInfo.processInfo.environment["SOMETHING_TRIAL_RECORD"] else { return }
        let text = lines.map { "\($0.written ? ">" : "<") \($0.line)" }.joined(separator: "\n") + "\n"
        try? text.write(toFile: "\(folder)/\(name).log", atomically: true, encoding: .utf8)
    }

    /// Stops the program by the ladder, and waits for its end.
    func finish() async throws {
        let stopped = Stopped()
        spawn.stop(cap: 8) { stopped.done = true }
        try await until("the end", seconds: 12) { state.alive == false && stopped.done }
        cleanup()
    }

    private var cleaned = false

    /// Stops what the case started and removes the throwaway home; once, from wherever the case ended.
    func cleanup() {
        guard !cleaned else { return }
        cleaned = true
        save()
        // Waited for here, so the home is gone before the test process may end.
        let stopped = DispatchSemaphore(value: 0)
        spawn.stop(cap: 2) { stopped.signal() }
        _ = stopped.wait(timeout: .now() + 3)
        api.stop()
        try? FileManager.default.removeItem(at: root)
    }

    /// The model Claude resolves an option to, from its answer to `initialize`.
    func resolved(_ option: String) -> String? {
        for line in lines where !line.written && line.line.contains("resolvedModel") {
            let frame = (try? JSONSerialization.jsonObject(with: Data(line.line.utf8))) as? [String: Any]
            let models = ((frame?["response"] as? [String: Any])?["response"] as? [String: Any])?["models"] as? [[String: Any]]
            if let model = models?.first(where: { $0["value"] as? String == option }) { return model["resolvedModel"] as? String }
        }
        return nil
    }
}

/// The claude program the trial runs, when asked for and there.
let trialClaude = ProcessInfo.processInfo.environment["SOMETHING_TRIAL_CLAUDE"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }

@Suite(.serialized, .enabled(if: trialClaude != nil, "T-1 needs Claude Code: set SOMETHING_TRIAL_CLAUDE to its program's path."))
@MainActor struct ClaudeTrial {

    @Test func aTurnStartsAndEnds() async throws {
        let run = try await ClaudeRun("turn")
        defer { run.cleanup() }
        #expect(try run.agent.send("Hello there.", when: "next") == "started")
        try await run.until("a reply") { run.items.contains { $0.author == "agent" && $0.kind == "message" } && run.state.state == "idle" }
        #expect(run.state.model != nil)
        #expect(run.state.mode == "default")
        #expect(run.state.options.model?.isEmpty == false)
        try await run.finish()
        #expect(run.state.state == "done")
        #expect(run.state.error == nil)
    }

    @Test func aPermissionIsAllowedOnce() async throws {
        let run = try await ClaudeRun("permission-once")
        defer { run.cleanup() }
        _ = try run.agent.send("Please run-echo now.", when: "next")
        try await run.until("a permission") { run.request != nil }
        #expect(run.state.state == "waiting")
        #expect(run.state.waiting == "permission")
        let request = try #require(run.request)
        #expect(request.tool == "Bash")
        #expect(try run.agent.answer(request.id, .once))
        try await run.until("the end of the turn") { run.state.state == "idle" && run.items.contains { $0.tool?.status == "done" } }
        #expect(run.items.first { $0.kind == "tool" }?.decision == Decision(by: "person", outcome: "allowed"))
        try await run.finish()
    }

    @Test func aPermissionIsDenied() async throws {
        let run = try await ClaudeRun("deny")
        defer { run.cleanup() }
        _ = try run.agent.send("Please run-echo now.", when: "next")
        try await run.until("a permission") { run.request != nil }
        #expect(try run.agent.answer(try #require(run.request).id, .deny))
        try await run.until("the end of the turn") { run.state.state == "idle" }
        #expect(run.items.first { $0.kind == "tool" }?.decision == Decision(by: "person", outcome: "denied"))
        #expect(run.items.first { $0.kind == "tool" }?.tool?.status == "failed")
        try await run.finish()
    }

    /// The answer goes back as `updatedInput.answers`, and the model reads it in the tool's result.
    @Test func aQuestionIsAnswered() async throws {
        let run = try await ClaudeRun("question")
        defer { run.cleanup() }
        _ = try run.agent.send("Please ask-me something.", when: "next")
        try await run.until("a question") { run.request != nil }
        let request = try #require(run.request)
        #expect(request.kind == "question")
        #expect(run.state.waiting == "answer")
        let prompt = try #require(run.agent.prompt(request.id))
        #expect(prompt.questions.first?.options == ["Blue", "Green"])
        #expect(try run.agent.answer(request.id, .choice([["Green"]])))
        try await run.until("the end of the turn") { run.state.state == "idle" && run.api.received.count >= 2 }
        let answer = try #require(run.lines.last { $0.written && $0.line.contains("updatedInput") }?.line)
        #expect(answer.contains(#""answers":{"Which colour for the invented button?":"Green"}"#), "\(answer)")
        #expect(run.api.toolResults.contains { $0.contains("Green") }, "tool results: \(run.api.toolResults)")
        try await run.finish()
    }

    @Test func aSteerJoinsTheTurnAndAQueuedMessageWaits() async throws {
        let run = try await ClaudeRun("steer-queue")
        defer { run.cleanup() }
        _ = try run.agent.send("Please run-sleep for me.", when: "next")
        try await run.until("a permission") { run.request != nil }
        _ = try run.agent.answer(try #require(run.request).id, .once)
        try await run.until("the tool to run") { run.state.state == "working" && run.items.contains { $0.tool?.status == "running" } }
        #expect(try run.agent.send("Steered: use the small one.", when: "now") == "steered")
        #expect(try run.agent.send("Queued: then the docs.", when: "next") == "queued")
        #expect(try run.agent.send("Queued: and the tests.", when: "next") == "queued")
        #expect(run.state.queue.map(\.text) == ["Queued: then the docs.", "Queued: and the tests."])
        try await run.until("three turns") { run.api.received.contains { $0.contains("Queued: and the tests.") } && run.state.state == "idle" }
        let received = run.api.received
        let order = ["Steered: use the small one.", "Queued: then the docs.", "Queued: and the tests."].map { text in received.firstIndex { $0.contains(text) } }
        #expect(order.allSatisfy { $0 != nil } && order == order.sorted { ($0 ?? 0) < ($1 ?? 0) })
        // The steer joined the running turn: one turn per queued message, none for it.
        #expect(run.agent.queue.fold.turns.map(\.state) == ["done", "done", "done"])
        try await run.finish()
    }

    @Test func anInterruptStopsATool() async throws {
        let run = try await ClaudeRun("interrupt")
        defer { run.cleanup() }
        _ = try run.agent.send("Please run-sleep for me.", when: "next")
        try await run.until("a permission") { run.request != nil }
        _ = try run.agent.answer(try #require(run.request).id, .once)
        try await run.until("the tool to run") { run.items.contains { $0.tool?.status == "running" } }
        _ = try run.agent.send("Queued: dropped.", when: "next")
        #expect(try run.agent.interrupt())
        #expect(run.state.queue.isEmpty)
        try await run.until("the interrupted turn") { run.agent.queue.fold.turns.last?.state == "interrupted" }
        #expect(run.state.state == "interrupted")
        #expect(!run.api.received.contains { $0.contains("Queued: dropped.") })
        try await run.finish()
    }

    /// A steer Claude still holds is dropped by the interrupt (`cancel_queued`): never read, never shown.
    @Test func anInterruptDropsASteer() async throws {
        let run = try await ClaudeRun("steer-interrupt")
        defer { run.cleanup() }
        _ = try run.agent.send("Please run-sleep for me.", when: "next")
        try await run.until("a permission") { run.request != nil }
        _ = try run.agent.answer(try #require(run.request).id, .once)
        try await run.until("the tool to run") { run.items.contains { $0.tool?.status == "running" } }
        #expect(try run.agent.send("Steered: dropped by the interrupt.", when: "now") == "steered")
        try await run.until("the steer to be written") { run.lines.contains { $0.written && $0.line.contains("Steered: dropped") } }
        let steer = try #require(run.lines.last { $0.written && $0.line.contains("Steered: dropped") }?.line)
        let uuid = try #require(((try? JSONSerialization.jsonObject(with: Data(steer.utf8))) as? [String: Any])?["uuid"] as? String)
        #expect(try run.agent.interrupt())
        try await run.until("the interrupted turn") { run.agent.queue.fold.turns.last?.state == "interrupted" && run.state.state == "interrupted" }
        try await run.until("the steer's fate") { run.lines.contains { !$0.written && $0.line.contains(uuid) && $0.line.contains("command_lifecycle") && $0.line.contains(#""state":"cancelled""#) } }
        #expect(!run.items.contains { $0.text.contains("Steered: dropped") })
        #expect(!run.api.received.contains { $0.contains("Steered: dropped") })
        #expect(run.state.error == nil)
        try await run.finish()
    }

    @Test func anInterruptWithdrawsARequest() async throws {
        let run = try await ClaudeRun("withdrawn")
        defer { run.cleanup() }
        _ = try run.agent.send("Please run-echo now.", when: "next")
        try await run.until("a permission") { run.request != nil }
        let id = try #require(run.request).id
        #expect(try run.agent.interrupt())
        try await run.until("the request to close") { run.request == nil && run.agent.queue.fold.turns.last?.state == "interrupted" }
        #expect(run.agent.prompt(id) == nil)
        #expect(run.lines.contains { !$0.written && $0.line.contains("control_cancel_request") })
        try await run.finish()
    }

    @Test func modeAndModelAreSet() async throws {
        let run = try await ClaudeRun("set")
        defer { run.cleanup() }
        try await run.until("the models") { run.state.options.model != nil }
        #expect(try run.agent.driver.set(model: nil, mode: "plan", effort: nil) == "now")
        try await run.until("the mode") { run.state.mode == "plan" }
        let option = try #require(run.state.options.model?.first { $0.value != "default" }?.value)
        let model = try #require(run.resolved(option))
        #expect(run.state.model != model)
        #expect(try run.agent.driver.set(model: option, mode: nil, effort: nil) == "now")
        // set_model's success names no model: the next reply, from the model Claude asked for, does.
        _ = try run.agent.send("Hello there.", when: "next")
        try await run.until("the model") { run.state.model == model }
        try await run.finish()
    }

    /// The effort given at launch reaches the model; one set during the session does from the next request.
    @Test func anEffortIsGivenAndSet() async throws {
        let run = try await ClaudeRun("effort", effort: "high")
        defer { run.cleanup() }
        _ = try run.agent.send("Hello there.", when: "next")
        try await run.until("a reply") { run.state.state == "idle" && !run.api.received.isEmpty }
        // The efforts are known once Claude names the model it runs, which its first turn does.
        #expect(run.state.options.effort?.map(\.value).contains("low") == true, "model \(String(describing: run.state.model))")
        #expect(run.state.can.effort)
        #expect(run.api.effortsAsked.last == "high", "efforts asked: \(run.api.effortsAsked)")
        let asked = run.api.received.count
        #expect(try run.agent.driver.set(model: nil, mode: nil, effort: "low") == "now")
        try await run.until("the effort") { run.state.effort == "low" }
        _ = try run.agent.send("Hello again.", when: "next")
        try await run.until("a reply") { run.state.state == "idle" && run.api.received.count > asked }
        #expect(run.api.effortsAsked.last == "low", "efforts asked: \(run.api.effortsAsked)")
        try await run.finish()
    }

    /// Plan B against the real Claude: its PermissionRequest hook, given in --settings, runs the real hook command,
    /// which asks through the spool.
    @Test func planBAllowsOnce() async throws {
        let run = try await ClaudeRun("plan-b-once", planB: true)
        defer { run.cleanup() }
        _ = try run.agent.send("Please run-echo now.", when: "next")
        try await run.until("a permission") { run.request != nil }
        #expect(run.request?.tool == "Bash")
        #expect(try run.agent.answer(try #require(run.request).id, .once))
        try await run.until("the end of the turn") { run.state.state == "idle" && run.items.contains { $0.tool?.status == "done" } }
        #expect(run.items.first { $0.kind == "tool" }?.decision == Decision(by: "person", outcome: "allowed"))
        try await run.finish()
    }

    @Test func planBDenies() async throws {
        let run = try await ClaudeRun("plan-b-deny", planB: true)
        defer { run.cleanup() }
        _ = try run.agent.send("Please run-echo now.", when: "next")
        try await run.until("a permission") { run.request != nil }
        #expect(try run.agent.answer(try #require(run.request).id, .deny))
        try await run.until("the end of the turn") { run.state.state == "idle" && run.items.contains { $0.tool?.status == "failed" } }
        #expect(run.items.first { $0.kind == "tool" }?.decision == Decision(by: "person", outcome: "denied"))
        try await run.finish()
    }

    @Test func endSessionStopsCleanly() async throws {
        let run = try await ClaudeRun("stop")
        defer { run.cleanup() }
        _ = try run.agent.send("Hello there.", when: "next")
        try await run.until("a reply") { run.state.state == "idle" && run.items.contains { $0.author == "agent" } }
        try await run.finish()
        #expect(run.lines.contains { $0.written && $0.line.contains("end_session") })
        #expect(run.state.state == "done")
        #expect(run.state.error == nil)
    }
}
