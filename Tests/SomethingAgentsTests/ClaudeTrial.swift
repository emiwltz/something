// Trial T-1: ClaudeDriver against the REAL claude program, which talks to FakeMessagesAPI instead of a model. It runs
// only when asked, since it needs Claude Code on this Mac:
//
//   SOMETHING_TRIAL_CLAUDE=/opt/homebrew/bin/claude swift test --filter ClaudeTrial
//
// Each case gets a throwaway HOME under $TMPDIR, deleted after. `--bare` is added to the launch line here only: it
// makes Claude read no OAuth login and no Keychain, so the made-up key "test-key" is the only credential it has;
// `--tools` names AskUserQuestion, which `--bare` leaves out.
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

    init(_ name: String, mode: String = "default") throws {
        self.name = name
        api = try FakeMessagesAPI()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("claude-trial-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home"), work = root.appendingPathComponent("work/shop")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let program = trialClaude!
        let launch = Launch(agent: "claude-trial", folder: work.path, mode: mode)
        let command = ClaudeDriver.command(launch)
        var environment = ["HOME": home.path, "CLAUDE_CONFIG_DIR": home.appendingPathComponent(".claude").path,
                           "PATH": "\((program as NSString).deletingLastPathComponent):/usr/bin:/bin", "TMPDIR": root.path,
                           "ANTHROPIC_BASE_URL": api.url, "ANTHROPIC_API_KEY": "test-key",
                           "DISABLE_AUTOUPDATER": "1", "DISABLE_TELEMETRY": "1", "DISABLE_ERROR_REPORTING": "1",
                           "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"]
        environment.merge(command.adding) { _, added in added }
        spawn = Spawn(path: program, arguments: command.arguments + ["--bare", "--tools", "Bash,Edit,Read,AskUserQuestion"], folder: work.path, environment: environment)
        var record: (Bool, Data) -> Void = { _, _ in }
        agent = try Engine.start(ClaudeDriver.self, launch, spawn, asked: { _ in false }, record: { record($0, $1) })
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
                save()
                spawn.stop(cap: 2) { [root] in try? FileManager.default.removeItem(at: root) }
                api.stop()
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

    /// Stops the program by the ladder and removes the throwaway home.
    func finish() async throws {
        let stopped = Stopped()
        spawn.stop(cap: 8) { stopped.done = true }
        try await until("the end", seconds: 12) { state.alive == false && stopped.done }
        save()
        api.stop()
        try? FileManager.default.removeItem(at: root)
    }
}

/// The claude program the trial runs, when asked for.
let trialClaude = ProcessInfo.processInfo.environment["SOMETHING_TRIAL_CLAUDE"]

@Suite(.serialized, .enabled(if: trialClaude != nil)) @MainActor struct ClaudeTrial {

    @Test func aTurnStartsAndEnds() async throws {
        let run = try ClaudeRun("turn")
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
        let run = try ClaudeRun("permission-once")
        _ = try run.agent.send("Please run-echo now.", when: "next")
        try await run.until("a permission") { run.request != nil }
        #expect(run.state.state == "waiting")
        #expect(run.state.waiting == "permission")
        let request = try #require(run.request)
        #expect(request.tool == "Bash")
        #expect(try run.agent.driver.answer(request.id, .once))
        try await run.until("the end of the turn") { run.state.state == "idle" && run.items.contains { $0.tool?.status == "done" } }
        #expect(run.items.first { $0.kind == "tool" }?.decision == Decision(by: "person", outcome: "allowed"))
        try await run.finish()
    }

    @Test func aPermissionIsDenied() async throws {
        let run = try ClaudeRun("deny")
        _ = try run.agent.send("Please run-echo now.", when: "next")
        try await run.until("a permission") { run.request != nil }
        #expect(try run.agent.driver.answer(run.request!.id, .deny))
        try await run.until("the end of the turn") { run.state.state == "idle" }
        #expect(run.items.first { $0.kind == "tool" }?.decision == Decision(by: "person", outcome: "denied"))
        #expect(run.items.first { $0.kind == "tool" }?.tool?.status == "failed")
        try await run.finish()
    }

    /// Not run: under `--bare`, which keeps the trial away from the Keychain, Claude 2.1.296 offers only Bash, Edit
    /// and Read, and `--tools` cannot add AskUserQuestion. The question path is proven by replay only.
    @Test(.disabled("AskUserQuestion is not offered under --bare")) func aQuestionIsAnswered() async throws {
        let run = try ClaudeRun("question")
        _ = try run.agent.send("Please ask-me something.", when: "next")
        try await run.until("a question") { run.request != nil }
        let request = try #require(run.request)
        #expect(request.kind == "question")
        #expect(run.state.waiting == "answer")
        let prompt = try #require(run.agent.driver.prompt(request.id))
        #expect(prompt.questions.first?.options == ["Blue", "Green"])
        #expect(try run.agent.driver.answer(request.id, .choice([["Green"]])))
        try await run.until("the end of the turn") { run.state.state == "idle" && run.api.received.count >= 2 }
        try await run.finish()
    }

    @Test func aSteerJoinsTheTurnAndAQueuedMessageWaits() async throws {
        let run = try ClaudeRun("steer-queue")
        _ = try run.agent.send("Please run-sleep for me.", when: "next")
        try await run.until("a permission") { run.request != nil }
        _ = try run.agent.driver.answer(run.request!.id, .once)
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
        let run = try ClaudeRun("interrupt")
        _ = try run.agent.send("Please run-sleep for me.", when: "next")
        try await run.until("a permission") { run.request != nil }
        _ = try run.agent.driver.answer(run.request!.id, .once)
        try await run.until("the tool to run") { run.items.contains { $0.tool?.status == "running" } }
        _ = try run.agent.send("Queued: dropped.", when: "next")
        #expect(try run.agent.interrupt())
        #expect(run.state.queue.isEmpty)
        try await run.until("the interrupted turn") { run.agent.queue.fold.turns.last?.state == "interrupted" }
        #expect(run.state.state == "interrupted")
        #expect(!run.api.received.contains { $0.contains("Queued: dropped.") })
        try await run.finish()
    }

    @Test func anInterruptWithdrawsARequest() async throws {
        let run = try ClaudeRun("withdrawn")
        _ = try run.agent.send("Please run-echo now.", when: "next")
        try await run.until("a permission") { run.request != nil }
        let id = run.request!.id
        #expect(try run.agent.interrupt())
        try await run.until("the request to close") { run.request == nil && run.agent.queue.fold.turns.last?.state == "interrupted" }
        #expect(run.agent.driver.prompt(id) == nil)
        #expect(run.lines.contains { !$0.written && $0.line.contains("control_cancel_request") })
        try await run.finish()
    }

    @Test func modeAndModelAreSet() async throws {
        let run = try ClaudeRun("set")
        try await run.until("the models") { run.state.options.model != nil }
        #expect(try run.agent.driver.set(model: nil, mode: "plan", effort: nil) == "now")
        try await run.until("the mode") { run.state.mode == "plan" }
        let model = try #require(run.state.options.model?.first { $0.value != "default" }?.value)
        #expect(try run.agent.driver.set(model: model, mode: nil, effort: nil) == "now")
        try await run.until("the model") { run.state.model == model }
        try await run.finish()
    }

    /// Whether Claude takes an effort through apply_flag_settings; the driver keeps `can.effort` false until it does.
    @Test func effortThroughFlagSettings() async throws {
        let run = try ClaudeRun("effort")
        _ = try run.agent.send("Hello there.", when: "next")
        try await run.until("a reply") { run.state.state == "idle" && run.api.received.count == 1 }
        try run.spawn.write(Data(#"{"request":{"settings":{"effortLevel":"low"},"subtype":"apply_flag_settings"},"request_id":"trial-effort","type":"control_request"}"#.utf8))
        try await run.until("an answer") { run.lines.contains { !$0.written && $0.line.contains("trial-effort") } }
        _ = try run.agent.send("Hello again.", when: "next")
        try await run.until("a reply") { run.state.state == "idle" && run.api.received.count == 2 }
        print("T-1 effort asked of the model, before and after apply_flag_settings: \(run.api.effortsAsked)")
        try await run.finish()
    }

    @Test func endSessionStopsCleanly() async throws {
        let run = try ClaudeRun("stop")
        _ = try run.agent.send("Hello there.", when: "next")
        try await run.until("a reply") { run.state.state == "idle" && run.items.contains { $0.author == "agent" } }
        try await run.finish()
        #expect(run.lines.contains { $0.written && $0.line.contains("end_session") })
        #expect(run.state.state == "done")
        #expect(run.state.error == nil)
    }
}
