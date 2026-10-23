// Trial T-3: ACPDriver against the REAL opencode program, which talks to FakeResponsesAPI's Chat Completions instead of
// a model. It runs only when asked, since it needs OpenCode on this Mac:
//
//   SOMETHING_TRIAL_OPENCODE=/opt/homebrew/bin/opencode swift test --filter OpenCodeTrial
//
// Each case gets a throwaway HOME, XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_STATE_HOME and XDG_CACHE_HOME under $TMPDIR,
// deleted after, whatever the case's outcome. Its opencode.json declares one OpenAI-compatible provider that points at
// the fake, with a made-up key, and enables no other (a local Ollama would otherwise be listed), so nothing reaches a
// real model or the person's OpenCode folders. Shell commands ask first, so a permission can be seen.
// SOMETHING_TRIAL_RECORD=<folder> also writes each case as an exchange in the format of Tests/Exchanges/opencode, its
// paths made /Users/example: the raw material of a replay.
import Darwin
import Foundation
import Testing
@testable import SomethingAgents
@testable import AgentACP
import SomethingCore

@MainActor final class OpenCodeRun {
    let api: FakeResponsesAPI
    let root: URL
    let agent: Launched
    let spawn: Spawn
    let name: String
    var rows: [[String: Any]] { exchange.rows }
    private let exchange: CodexRun.Exchange
    private let owner: Bool
    /// The session this run continues and the model it was launched with, if any.
    private let resumed: String?, model: String?
    /// Whether the case asked the program to stop: its end is then no failure.
    private let stopAsked: Stopped

    /// The folder OpenCode works in.
    let work: URL
    /// The real program this run placed (AssistantBuild.placeProgram), which its cleanup removes.
    private var placed: URL?
    var database: String { root.appendingPathComponent("data/opencode/opencode.db").path }

    /// With `after`, the case runs in that run's home and against its fake (to resume its conversation). With
    /// `assistant`, OpenCode is the person's building assistant, in ~/something/spaces, with OpenCode's own default
    /// permissions, lent something's tools over MCP as the app lends them: served by this clone's real program
    /// (AssistantBuild.placeProgram), with the person's own temporary folder.
    init(_ name: String, model: String? = nil, resume session: String? = nil, after: OpenCodeRun? = nil, assistant: Bool = false) throws {
        self.name = name
        owner = after == nil
        (resumed, self.model) = (session, model)
        api = try after?.api ?? FakeResponsesAPI()
        let root = after?.root ?? FileManager.default.scratch("opencode-trial-")
        self.root = root
        let work = assistant ? AssistantBuild.real(root).appendingPathComponent("home/something/spaces") : root.appendingPathComponent("work/shop")
        self.work = work
        for folder in ["home", "config/opencode", "data", "state", "cache"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let fake: [String: Any] = ["name": "Fake Model", "tool_call": true, "limit": ["context": 100_000, "output": 10_000]]
        var other = fake
        other["name"] = "Other Model"
        other["variants"] = ["low": ["reasoningEffort": "low"], "high": ["reasoningEffort": "high"]]
        var config: [String: Any] = ["autoupdate": false, "model": "fake/fake-model", "enabled_providers": ["fake"],
                                     "permission": ["bash": "ask", "edit": "ask"],
                                     "provider": ["fake": ["name": "Fake", "npm": "@ai-sdk/openai-compatible",
                                                           "options": ["apiKey": "test-key", "baseURL": api.url],
                                                           "models": ["fake-model": fake, "other-model": other]]]]
        if assistant { config["permission"] = nil }
        try JSONSerialization.data(withJSONObject: config).write(to: root.appendingPathComponent("config/opencode/opencode.json"))
        let program = trialOpenCode!
        var launch = Launch(agent: "opencode-1", folder: work.path, model: model, thread: session ?? "", resume: session != nil)
        if assistant {
            launch.assistant = .building
            let program = try AssistantBuild.placeProgram()
            placed = program
            launch.lent = Lent.own(program.path, tools: LentTool.all, environment: ["TMPDIR": NSTemporaryDirectory()], refused: { _, _ in })
        }
        var environment = ["HOME": "home", "XDG_CONFIG_HOME": "config", "XDG_DATA_HOME": "data", "XDG_STATE_HOME": "state",
                           "XDG_CACHE_HOME": "cache"].mapValues { root.appendingPathComponent($0).path }
        environment.merge(["TMPDIR": root.path, "PATH": "\((program as NSString).deletingLastPathComponent):/usr/bin:/bin",
                           "OPENCODE_DISABLE_MODELS_FETCH": "true", "OPENCODE_DISABLE_AUTOUPDATE": "true"]) { _, new in new }
        spawn = Spawn(path: program, arguments: ACPProfile.opencode.driving.command(launch).arguments, folder: work.path, environment: environment)
        let (stop, exchange) = (Stopped(), CodexRun.Exchange())
        (stopAsked, self.exchange) = (stop, exchange)
        agent = try Engine.start(ACPProfile.opencode.driving, launch, spawn, asked: { _ in stop.done }, record: { written, line in
            let frame = (try? JSONSerialization.jsonObject(with: line)) ?? String(decoding: line, as: UTF8.self)
            exchange.rows.append([written ? "something" : "opencode": frame])
        })
    }

    var state: Agent { agent.agent }
    var request: Request? { agent.queue.fold.requests.first }
    var items: [Item] { agent.queue.fold.turns.flatMap(\.items) }
    var turns: [String] { agent.queue.fold.turns.map(\.state) }
    var opencode: ACPDriver { agent.driver as! ACPDriver }
    var claimed: Bool? { state.thread.flatMap { OpenCode.claimed($0, in: database) } }

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

    /// Kills the program's group, as a crash or a force quit would.
    func kill() {
        exchange.rows.append(["kill": true])
        _ = Darwin.kill(-spawn.pid, SIGKILL)
    }

    /// Ends the recording of a case whose end something did not ask for.
    func ended(_ code: Int) {
        exchange.rows.append(["ended": code])
        save()
    }

    func answer(_ answer: Answer) throws -> Bool {
        let id = try #require(request).id
        exchange.rows.append(["answer": id, "with": answer == .once ? "once" : "deny"])
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
        if let placed { AssistantBuild.removeProgram(placed) }
        guard owner else { return }
        api.stop()
        try? FileManager.default.removeItem(at: root)
    }

    /// Whether the program this run placed serves something's tools (`something mcp`), as OpenCode started it.
    func serving() throws -> Bool {
        let serving = Process()
        serving.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        serving.arguments = ["-f", (placed?.path ?? "-") + " mcp"]
        serving.standardOutput = FileHandle.nullDevice
        try serving.run()
        serving.waitUntilExit()
        return serving.terminationStatus == 0
    }

    /// No process of the trial's home is left.
    func nothingLeft() throws -> Bool {
        let left = Process()
        left.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        left.arguments = ["-f", root.path]
        try left.run()
        left.waitUntilExit()
        return left.terminationStatus == 1
    }

    /// With SOMETHING_TRIAL_RECORD, writes the rows to <folder>/<case>.jsonl, with /Users/example paths for the throwaway folders.
    func save() {
        guard let folder = ProcessInfo.processInfo.environment["SOMETHING_TRIAL_RECORD"] else { return }
        var note: [String: Any] = ["note": "Recorded in trial T-3 (opencode \(ACPProfile.opencode.tested), a fake model, invented text, paths made /Users/example)."]
        if let resume = resumed { note["resume"] = resume }
        if let model { note["model"] = model }
        if placed != nil { note["assistant"] = true }
        var text = ([note] + rows).compactMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .withoutEscapingSlashes]) }
            .map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n") + "\n"
        for prefix in ["/private" + root.path, root.path] {
            text = text.replacingOccurrences(of: prefix + "/work/shop", with: "/Users/example/shop").replacingOccurrences(of: prefix, with: "/Users/example/trial")
        }
        try? text.write(toFile: "\(folder)/\(name).jsonl", atomically: true, encoding: .utf8)
    }
}

/// The opencode program the trial runs, when asked for and there.
let trialOpenCode = ProcessInfo.processInfo.environment["SOMETHING_TRIAL_OPENCODE"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }

@Suite(.serialized, .enabled(if: trialOpenCode != nil, "T-3 needs OpenCode: set SOMETHING_TRIAL_OPENCODE to its program's path."))
@MainActor struct OpenCodeTrial {

    /// The standard build of a space by the person's assistant, launched as the app launches it,
    /// through the tools something lends OpenCode over MCP (the real `something mcp`, which OpenCode starts from
    /// session/new, running the real guide, new and check), with OpenCode's own default permissions: nothing is asked.
    @Test func theAssistantsStandardBuildAsksNothing() async throws {
        let run = try OpenCodeRun("assistant-build", assistant: true)
        defer { run.cleanup() }
        run.api.build = AssistantBuild.lentSteps(run.work.path, opencode: true).map { ($0.name, $0.input) }
        try await run.until("the session") { run.state.thread != nil }
        // OpenCode connects a session's MCP servers in the background: a model that calls a tool at once (only this
        // fake does) could find none. The server is waited for, then a second for OpenCode to list its tools.
        try await run.until("something's MCP server") { (try? run.serving()) == true }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        #expect(try run.send("Please run-build a board of my agents.") == "started")
        var asked: [String] = []
        try await run.until("the build", seconds: 120) {
            if let request = run.request, !asked.contains(request.id) { asked.append(request.id); _ = try? run.answer(.once) }
            return run.state.state == "idle" && run.items.contains { $0.author == "agent" && $0.text.contains("the board is ready") }
        }
        #expect(asked.isEmpty, "asked: \(asked)")
        let tools = run.items.filter { $0.kind == "tool" }
        #expect(tools.map(\.tool?.status) == Array(repeating: "done", count: 13), "\(tools.map { "\($0.tool?.name ?? "-") \($0.text) \($0.tool?.status ?? "-")" })")
        #expect(tools.filter { $0.tool?.name == "something_check" }.map(\.text) == AssistantBuild.checks)
        #expect(tools.first?.text == "something guide --print" && tools[2].text == "something new agents-board --from agents", "\(tools.map(\.text))")
        #expect(try String(contentsOf: run.work.appendingPathComponent("agents-board.html"), encoding: .utf8).contains("Invented three"))
        #expect(FileManager.default.fileExists(atPath: run.work.appendingPathComponent(".check/agents-board.png").path), "the check loaded the page")
        try await run.finish()
    }

    @Test func aTurnStartsAndEnds() async throws {
        let run = try OpenCodeRun("turn")
        defer { run.cleanup() }
        try await run.until("the session") { run.state.thread != nil && run.state.model != nil }
        #expect((run.state.model, run.state.mode) == ("fake/fake-model", "build"))
        #expect(run.state.options.model?.map(\.value) == ["fake/fake-model", "fake/other-model"])
        #expect(run.state.options.effort?.map(\.value) == ["low", "medium", "high", "default"], "OpenCode's levels for a model with tools")
        #expect(try run.send("Hello there.") == "started")
        try await run.until("a reply") { run.items.contains { $0.author == "agent" } && run.state.state == "idle" }
        #expect(run.items.map(\.author) == ["person", "agent"])
        #expect(run.items.last?.text == "Invented reply number 5.")
        try await run.finish()
        #expect(run.state.state == "done")
        #expect(run.state.error == nil)
        #expect(run.claimed == false)
    }

    @Test func aPermissionIsAllowedOnce() async throws {
        let run = try OpenCodeRun("permission-once")
        defer { run.cleanup() }
        _ = try run.send("Please run-echo now.")
        try await run.until("a permission") { run.request != nil }
        #expect((run.state.state, run.state.waiting) == ("waiting", "permission"))
        #expect(run.request?.tool == "shell")
        #expect(run.request?.about == "touch invented.txt")
        #expect(run.agent.prompt(try #require(run.request).id)?.input == "touch invented.txt")
        #expect(try run.answer(.once))
        try await run.until("the end of the turn") { run.state.state == "idle" && run.turns == ["done"] }
        let tool = try #require(run.items.first { $0.kind == "tool" })
        #expect(tool.tool == Tool(name: "shell", status: "done"))
        #expect(tool.decision == Decision(by: "person", outcome: "allowed"))
        #expect(FileManager.default.fileExists(atPath: run.work.appendingPathComponent("invented.txt").path))
        try await run.finish()
    }

    /// OpenCode ends the turn by itself after a refusal ("cancelled"): not interrupted, and no normal end either.
    @Test func aPermissionIsDenied() async throws {
        let run = try OpenCodeRun("deny")
        defer { run.cleanup() }
        _ = try run.send("Please run-echo now.")
        try await run.until("a permission") { run.request != nil }
        #expect(try run.answer(.deny))
        try await run.until("the end of the turn") { run.state.state == "error" && run.turns == ["error"] }
        let tool = try #require(run.items.first { $0.kind == "tool" })
        #expect(tool.tool?.status == "failed")
        #expect(tool.decision == Decision(by: "person", outcome: "denied"))
        #expect(!FileManager.default.fileExists(atPath: run.work.appendingPathComponent("invented.txt").path))
        try await run.finish()
    }

    /// OpenCode 2.0.20 dismisses its own questions over ACP: no request ever comes, and the agent's error says so.
    @Test func aQuestionIsDismissedByOpenCode() async throws {
        let run = try OpenCodeRun("question")
        defer { run.cleanup() }
        _ = try run.send("Please ask-me something.")
        try await run.until("the end of the turn") { run.turns == ["error"] && run.state.state == "error" }
        #expect(run.state.error?.message == ACPProfile.opencode.questionDismissed)
        #expect(!run.rows.contains { ($0["opencode"] as? [String: Any])?["method"] as? String == "session/request_permission" })
        try await run.finish()
    }

    @Test func aSteerIsRefusedAndQueuedMessagesWait() async throws {
        let run = try OpenCodeRun("queue")
        defer { run.cleanup() }
        _ = try run.send("Please run-sleep for me.")
        try await run.until("the turn") { run.opencode.prompting && run.items.count == 2 }
        #expect(throws: CodedError("NOT_SUPPORTED", ACPProfile.opencode.driving.limits["steer"]!)) { try run.agent.send("Steered: no.", when: "now") }
        #expect(try run.send("Queued: then the docs.") == "queued")
        #expect(try run.send("Queued: and the tests.") == "queued")
        #expect(run.state.queue.map(\.text) == ["Queued: then the docs.", "Queued: and the tests."])
        try await run.until("three turns") { run.turns == ["done", "done", "done"] && run.state.state == "idle" }
        #expect(run.api.received == ["Please run-sleep for me.", "Queued: then the docs.", "Queued: and the tests."])
        #expect(run.state.error == nil)
        try await run.finish()
    }

    @Test func anInterruptStopsTheTurn() async throws {
        let run = try OpenCodeRun("interrupt")
        defer { run.cleanup() }
        _ = try run.send("Please run-sleep for me.")
        try await run.until("the turn") { run.opencode.prompting && run.items.count == 2 }
        _ = try run.send("Queued: dropped.")
        #expect(try run.interrupt())
        #expect(run.state.queue.isEmpty)
        try await run.until("the interrupted turn") { run.turns == ["interrupted"] }
        #expect(run.state.state == "interrupted")
        #expect(try run.interrupt() == false)
        _ = try run.send("Hello again.")
        try await run.until("the next turn") { run.turns == ["interrupted", "done"] }
        #expect(!run.api.received.contains("Queued: dropped."))
        #expect(run.state.error == nil)
        #expect(run.claimed == false, "a cancel releases the claim")
        try await run.finish()
    }

    @Test func anInterruptWithdrawsARequest() async throws {
        let run = try OpenCodeRun("withdrawn")
        defer { run.cleanup() }
        _ = try run.send("Please run-echo now.")
        try await run.until("a permission") { run.request != nil }
        let id = try #require(run.request).id
        #expect(try run.interrupt())
        try await run.until("the request to close") { run.request == nil && run.turns == ["interrupted"] }
        #expect(run.agent.prompt(id) == nil)
        #expect(!FileManager.default.fileExists(atPath: run.work.appendingPathComponent("invented.txt").path))
        try await run.finish()
    }

    /// Each value is read back from OpenCode's answer; one it does not offer is said, and the old value stays.
    @Test func modelModeAndEffortAreReadBack() async throws {
        let run = try OpenCodeRun("set")
        defer { run.cleanup() }
        try await run.until("the session") { run.state.model != nil }
        #expect(try run.set(model: "fake/other-model", mode: "plan", effort: "high") == "now")
        try await run.until("the values") { run.state.effort == "high" }
        #expect((run.state.model, run.state.mode) == ("fake/other-model", "plan"))
        #expect(run.state.options.effort?.map(\.value).sorted() == ["default", "high", "low"])
        #expect(run.state.can.effort)
        _ = try run.send("Hello there.")
        try await run.until("the turn") { run.turns == ["done"] && run.state.state == "idle" }
        #expect(run.api.modelsAsked.last == "other-model")
        #expect(run.api.effortsAsked.last == "high")
        #expect(try run.set(model: "fake/missing") == "now")
        try await run.until("the refusal") { run.state.error != nil }
        #expect(run.state.error?.code == "VALUE_NOT_OFFERED")
        #expect(run.state.model == "fake/other-model")
        try await run.finish()
    }

    /// A model given at launch is set before the first message goes out.
    @Test func aLaunchSetsItsModelFirst() async throws {
        let run = try OpenCodeRun("launch-model", model: "fake/other-model")
        defer { run.cleanup() }
        _ = try run.send("Hello there.")
        try await run.until("the turn") { run.turns == ["done"] && run.state.state == "idle" }
        #expect(run.state.model == "fake/other-model")
        #expect(run.api.modelsAsked == ["other-model"])
        try await run.finish()
    }

    @Test func aConversationIsResumed() async throws {
        let first = try OpenCodeRun("resume-first")
        defer { first.cleanup() }
        _ = try first.send("Hello there.")
        try await first.until("a reply") { first.turns == ["done"] }
        let session = try #require(first.state.thread)
        try await first.finish()
        let run = try OpenCodeRun("resume", resume: session, after: first)
        defer { run.cleanup() }
        #expect(run.state.thread == session, "a resumed session is known before OpenCode answers")
        try await run.until("the session") { run.state.model != nil }
        _ = try run.send("Hello again.")
        try await run.until("a reply") { run.turns == ["done"] && run.state.state == "idle" }
        #expect(first.api.messagesSent == [1, 2], "the resumed turn carries the first one's words")
        try await run.finish()
        let missing = try OpenCodeRun("resume-missing", resume: "ses_invented000000000000000", after: first)
        defer { missing.cleanup() }
        try await missing.until("the refusal") { missing.state.alive == false }
        #expect(missing.state.error?.code == "THREAD_NOT_FOUND")
    }

    /// A kill mid-turn leaves OpenCode's claim on the conversation, and the agent's error says it (K-O2).
    @Test func aKillLeavesTheClaimAndSaysSo() async throws {
        let run = try OpenCodeRun("killed")
        defer { run.cleanup() }
        _ = try run.send("Please run-sleep for me.")
        try await run.until("the turn") { run.opencode.prompting && run.items.count == 2 }
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(run.claimed == true, "a running turn holds the claim")
        run.kill()
        try await run.until("the end") { run.state.alive == false && run.state.error?.message.hasSuffix(OpenCode.claimLeft(run.state.thread ?? "")) == true }
        run.ended(137)
        #expect(run.claimed == true)
        #expect(run.state.state == "error", "a killed program is a failure")
    }

    /// The ladder cancels the turn before it closes the input: no claim is left, no process either, and no signal
    /// was needed.
    @Test func theLadderLeavesNoClaim() async throws {
        let run = try OpenCodeRun("stop")
        defer { run.cleanup() }
        _ = try run.send("Please run-sleep for me.")
        try await run.until("the turn") { run.opencode.prompting && run.items.count == 2 }
        try await Task.sleep(nanoseconds: 500_000_000)
        let took = try await run.finish()
        #expect(took < 3, "the cancel's answer and the input's end, without SIGTERM: \(took) s")
        #expect(run.claimed == false)
        #expect(run.state.state == "interrupted")
        #expect(run.state.error == nil)
        #expect(try run.nothingLeft(), "no process of the trial is left")
    }
}
