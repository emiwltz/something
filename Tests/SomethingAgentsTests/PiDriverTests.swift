// PiDriver, replayed over Tests/Exchanges/pi (Replay.swift): each file was recorded in trial T-4 against the real
// pi --mode rpc 1.0.0 and FakeResponsesAPI's Chat Completions, with invented text. Then the cases no recording holds,
// built from the shapes pi writes: the command line, a refused prompt, a failed retry, an extension's
// dialog, an interrupt before the run starts, a launch that fails, and the placeholder model of a pi with no login.
import Foundation
import Testing
@testable import SomethingAgents
import SomethingCore

@Suite struct PiReplayTests {
    static func types(_ replay: Replay) -> [String] { replay.lines().compactMap { $0["type"] as? String } }

    @Test func aTurn() throws {
        let replay = try Replay.play("turn", kind: "pi")
        let agent = replay.fold.agent
        #expect(replay.items.map(\.author) == ["person", "agent"])
        #expect(replay.items.last?.text == "Invented reply number 5.")
        #expect(agent.thread?.hasPrefix("/Users/example/trial/agent/sessions/--Users-example-shop--/") == true, "the thread is pi's conversation file")
        #expect((agent.model, agent.mode, agent.effort) == ("fake/fake-1", nil, "medium"))
        #expect(agent.options.model?.map(\.value) == ["fake/fake-1", "fake/fake-2"])
        #expect(agent.options.effort?.map(\.value) == ["off", "minimal", "low", "medium", "high"])
        #expect(agent.options.mode == [])
        #expect(agent.state == "done")
        #expect(agent.error == nil)
    }

    /// pi runs the command without asking: a tool item, no request.
    @Test func aCommandRunsWithoutAsking() throws {
        let replay = try Replay.play("tool", kind: "pi")
        let tool = try #require(replay.items.first { $0.kind == "tool" })
        #expect(tool.tool == Tool(name: "bash", status: "done"))
        #expect(tool.text == "touch invented.txt")
        #expect(tool.decision == nil)
        #expect(replay.fold.requests.isEmpty)
        #expect(replay.fold.turns.map(\.state) == ["done"])
    }

    /// The steer goes out as a prompt with streamingBehavior "steer" and joins the run; the held message waits for
    /// agent_settled, then goes out as a plain prompt.
    @Test func aSteerJoinsAndAHeldMessageWaits() throws {
        let replay = try Replay.play("steer-queue", kind: "pi")
        let prompts = replay.lines().filter { $0["type"] as? String == "prompt" }
        #expect(prompts.map { $0["streamingBehavior"] as? String } == [nil, "steer", nil])
        #expect(replay.fold.turns.map(\.state) == ["done", "done"])
        #expect(replay.items.filter { $0.author == "person" }.map(\.text) == ["Please run-sleep for me.", "Steered: also the docs.", "Queued: and the tests."])
        #expect(replay.fold.agent.queue.isEmpty)
    }

    /// clear_queue goes before abort; the held message is dropped and the next one starts a new turn.
    @Test func anInterrupt() throws {
        let replay = try Replay.play("interrupt", kind: "pi")
        #expect(Self.types(replay).filter { $0 != "prompt" }.suffix(2) == ["clear_queue", "abort"])
        #expect(replay.fold.turns.map(\.state) == ["interrupted", "done"])
        #expect(!replay.items.contains { $0.text == "Queued: dropped." })
        #expect(replay.fold.agent.error == nil)
    }

    /// An abort in a tool ends pi's run with stopReason "error": it is an interrupt, not a failure.
    @Test func anInterruptInATool() throws {
        let replay = try Replay.play("interrupt-tool", kind: "pi")
        #expect(replay.fold.turns.map(\.state) == ["interrupted"])
        #expect(replay.items.first { $0.kind == "tool" }?.tool?.status == "failed")
        #expect(replay.fold.agent.state == "interrupted", "a clean stop keeps the interrupted outcome")
        #expect(replay.fold.agent.error == nil)
    }

    /// set_model, then set_thinking_level, then get_state reads both back; a model pi does not have is said, and
    /// nothing is left to read back.
    @Test func setIsReadBack() throws {
        let replay = try Replay.play("set", kind: "pi")
        let sent = replay.lines().filter { ["set_model", "set_thinking_level", "get_state"].contains($0["type"] as? String ?? "") }
        #expect(sent.map { $0["type"] as! String } == ["get_state", "set_model", "set_thinking_level", "get_state", "set_model"])
        #expect(sent[1]["provider"] as? String == "fake" && sent[1]["modelId"] as? String == "fake-2")
        #expect((replay.fold.agent.model, replay.fold.agent.effort) == ("fake/fake-2", "low"))
        #expect(replay.fold.agent.error?.code == "VALUE_NOT_OFFERED")
        #expect(replay.fold.agent.error?.message.hasPrefix("pi refused fake/missing as its model") == true)
    }

    @Test func aLaunchWithModelAndEffort() throws {
        let replay = try Replay.play("launch-model", kind: "pi")
        #expect((replay.fold.agent.model, replay.fold.agent.effort) == ("fake/fake-2", "high"))
    }

    @Test func aResume() throws {
        let replay = try Replay.play("resume", kind: "pi")
        #expect(replay.fold.agent.thread?.hasSuffix("_01a14bf4-0637-7672-a0d2-cdc41e61f96d.jsonl") == true)
        #expect(replay.fold.turns.map(\.state) == ["done"])
    }

    /// The ladder's graceful step is the input's end: no line is written for it, and the open turn is interrupted.
    @Test func aStopMidRun() throws {
        let replay = try Replay.play("stop", kind: "pi")
        #expect(PiDriver(Launch(agent: "pi-1", folder: "/Users/example/shop"), write: { _ in }, emit: { _ in }, now: { "" }).goodbye == nil)
        #expect(replay.fold.agent.state == "interrupted")
        #expect(replay.fold.agent.error == nil)
    }
}

@Suite struct PiDriverTests {
    static func launch(model: String? = nil, effort: String? = nil, resume: String? = nil) -> Launch {
        Launch(agent: "pi-1", folder: "/Users/example/shop", model: model, effort: effort, thread: resume ?? "", resume: resume != nil)
    }

    static func pi() -> Replay { Replay("pi", launch()) }

    @Test func theCommandLine() {
        #expect(PiDriver.command(Self.launch()).arguments == ["--mode", "rpc"])
        #expect(PiDriver.command(Self.launch(model: "fake/fake-2", effort: "high", resume: "/Users/example/.pi/agent/sessions/--Users-example-shop--/a.jsonl")).arguments
                == ["--mode", "rpc", "--model", "fake/fake-2", "--thinking", "high", "--session", "/Users/example/.pi/agent/sessions/--Users-example-shop--/a.jsonl"])
        #expect(PiDriver.command(Self.launch()).adding.isEmpty && PiDriver.command(Self.launch()).removing.isEmpty, "pi needs nothing in its environment")
    }

    @Test func piNeverAsksAndHasNoMode() throws {
        let replay = Self.pi()
        #expect(replay.fold.agent.can.mode == false)
        #expect(replay.fold.agent.because["mode"]?.contains("without asking") == true)
        #expect(replay.fold.agent.waiting == "none")
        #expect(throws: CodedError("NOT_SUPPORTED", Driving.pi.limits["mode"]!)) { try replay.agent.driver.set(model: nil, mode: "plan", effort: nil) }
        #expect(try replay.agent.answer("pi-1:1", .once) == false)
    }

    /// With no login, pi shows the placeholder model "unknown/unknown", and its first prompt is refused with words
    /// that point at a terminal command and a long path: the model is null, the error the gesture.
    @Test func aPiWithNoLogin() throws {
        let replay = Self.pi()
        replay.feed(["id": "s1", "type": "response", "command": "get_state", "success": true,
                     "data": ["model": ["provider": "unknown", "id": "unknown"], "thinkingLevel": "medium", "sessionFile": "/Users/example/.pi/agent/sessions/--Users-example-shop--/b.jsonl"]])
        #expect(replay.fold.agent.model == nil)
        #expect(try replay.agent.send("Hello there.", when: "next") == "started")
        #expect(try replay.agent.send("Queued: then the docs.", when: "next") == "queued")
        replay.feed(["id": "s4", "type": "response", "command": "prompt", "success": false,
                     "error": "No API key found for the selected model.\n\nUse /login to log into a provider via OAuth or API key. See:\n  /Users/example/providers.md"])
        #expect(replay.fold.agent.error?.message == "pi refused the message “Hello there.”: pi has no key for this model. Open pi once in Terminal and use /login, then launch it again.")
        #expect(replay.lines(from: 4).first?["message"] as? String == "Queued: then the docs.", "the held message goes on")
    }

    /// A retry that fails for good ends the run in an error, with pi's last words.
    @Test func aFailedRetryIsAnError() throws {
        let replay = Self.pi()
        _ = try replay.agent.send("Hello there.", when: "next")
        replay.feed(["type": "agent_start"])
        replay.feed(["type": "message_end", "message": ["role": "assistant", "content": [], "stopReason": "error", "errorMessage": "503: invented outage"]])
        replay.feed(["type": "agent_end", "willRetry": true])
        replay.feed(["type": "agent_start"])
        #expect(replay.fold.turns.count == 1, "a retry is the same turn")
        replay.feed(["type": "auto_retry_end", "success": false, "attempt": 3, "finalError": "503: still out"])
        replay.feed(["type": "agent_settled"])
        #expect(replay.fold.turns.map(\.state) == ["error"])
        #expect(replay.fold.agent.error == AgentError(code: "AGENT_ERROR", message: "503: still out"))
    }

    /// An extension's dialog would block it: it is cancelled at once, and the person told.
    @Test func anExtensionDialogIsCancelled() {
        let replay = Self.pi()
        replay.feed(["type": "extension_ui_request", "id": "ui-1", "method": "confirm", "title": "Invented: clear the list?"])
        replay.feed(["type": "extension_ui_request", "id": "ui-2", "method": "notify", "message": "Invented note"])
        let replies = replay.lines().filter { $0["type"] as? String == "extension_ui_response" }
        #expect(replies.count == 1)
        #expect(replies.first?["id"] as? String == "ui-1" && replies.first?["cancelled"] as? Bool == true)
        #expect(replay.fold.agent.error?.message.contains("Invented: clear the list?") == true)
    }

    /// An interrupt that comes before pi started the run is sent when it starts.
    @Test func anInterruptBeforeTheRun() throws {
        let replay = Self.pi()
        _ = try replay.agent.send("Hello there.", when: "next")
        #expect(try replay.agent.interrupt())
        #expect(PiReplayTests.types(replay).suffix(2) == ["prompt", "clear_queue"])
        replay.feed(["type": "agent_start"])
        #expect(PiReplayTests.types(replay).last == "abort")
        replay.feed(["type": "message_end", "message": ["role": "assistant", "content": [["type": "text", "text": "Invented"]], "stopReason": "aborted"]])
        replay.feed(["type": "agent_settled"])
        #expect(replay.fold.turns.map(\.state) == ["interrupted"])
    }

    /// A message an extension ran as its command starts no run: the turn ends at its answer, and what was held goes.
    @Test func aMessageAnExtensionHandled() throws {
        let replay = Self.pi()
        #expect(try replay.agent.send("/invented-command", when: "next") == "started")
        #expect(try replay.agent.send("Queued: then the docs.", when: "next") == "queued")
        replay.feed(["id": "s4", "type": "response", "command": "prompt", "success": true, "data": ["disposition": "handled"]])
        #expect(replay.fold.agent.queue.isEmpty)
        #expect(replay.lines(from: 4).first?["message"] as? String == "Queued: then the docs.")
    }

    /// pi takes any thinking level and keeps the closest its model supports: the read-back says so.
    @Test func anEffortPiKeptOtherwise() throws {
        let replay = Self.pi()
        #expect(try replay.agent.driver.set(model: nil, mode: nil, effort: "high") == "now")
        #expect(replay.lines(from: 3).map { $0["type"] as? String } == ["set_thinking_level"])
        replay.feed(["id": "s4", "type": "response", "command": "set_thinking_level", "success": true])
        #expect(replay.lines(from: 4).map { $0["type"] as? String } == ["get_state"])
        replay.feed(["id": "s5", "type": "response", "command": "get_state", "success": true,
                     "data": ["model": ["provider": "fake", "id": "fake-1"], "thinkingLevel": "off", "sessionFile": "/Users/example/.pi/agent/sessions/--Users-example-shop--/b.jsonl"]])
        #expect(replay.fold.agent.error == AgentError(code: "VALUE_NOT_OFFERED", message: "pi kept off as its effort, not high."))
        #expect(replay.fold.agent.effort == "off")
        #expect(throws: CodedError("VALUE_NOT_OFFERED", "pi names a model provider/id, such as one of the agent's options.model.")) {
            try replay.agent.driver.set(model: "fake-2", mode: nil, effort: nil)
        }
    }

    /// A refused clear_queue is said: what pi queued would go with the next prompt.
    @Test func aQueuePiKept() throws {
        let replay = Self.pi()
        _ = try replay.agent.send("Hello there.", when: "next")
        replay.feed(["type": "agent_start"])
        #expect(try replay.agent.interrupt())
        #expect(replay.lines(from: 4).map { $0["type"] as? String } == ["clear_queue", "abort"])
        replay.feed(["id": "s5", "type": "response", "command": "clear_queue", "success": false, "error": "Invented failure"])
        #expect(replay.fold.agent.error == AgentError(code: "AGENT_ERROR", message: "pi kept the messages it had queued: Invented failure"))
    }

    /// A resume runs in the folder the conversation's header names; a file that is no pi conversation is refused.
    @Test func whereAResumeRuns() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pi-header-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("a.jsonl")
        let lines = #"{"type":"session","version":3,"id":"01a1","timestamp":"2026-10-17T09:00:00Z","cwd":"/Users/example/shop"}"# + "\n" + #"{"type":"message"}"# + "\n"
        try Data(lines.utf8).write(to: file)
        #expect(try PiDriver.resumable(file.path) == "/Users/example/shop")
    }

    /// A wrong --model or --session ends pi before it answers, with one line on its error output.
    @Test func aLaunchThatFails() {
        let replay = Self.pi()
        replay.agent.ended(code: 1, errors: "Error: Model \"fake/nothing\" not found. Use --list-models to see available models.\n", asked: false)
        #expect(replay.fold.agent.error == AgentError(code: "LAUNCH_FAILED", message: "pi could not start: Error: Model \"fake/nothing\" not found. Use --list-models to see available models."))
        #expect(replay.fold.agent.state == "error")
    }

    /// Thinking blocks are thoughts; the system prompt and tool results are no items.
    @Test func whatIsShown() {
        let replay = Self.pi()
        replay.feed(["type": "message_end", "message": ["role": "system", "content": "Invented system prompt"]])
        replay.feed(["type": "message_end", "message": ["role": "user", "content": "Hello there."]])
        replay.feed(["type": "message_end", "message": ["role": "assistant", "stopReason": "stop",
                                                        "content": [["type": "thinking", "thinking": "Invented thought"], ["type": "text", "text": "Invented reply"]]]])
        replay.feed(["type": "message_end", "message": ["role": "toolResult", "content": [["type": "text", "text": "Invented output"]]]])
        #expect(replay.items.map { "\($0.kind)/\($0.author): \($0.text)" } == ["message/person: Hello there.", "thought/agent: Invented thought", "message/agent: Invented reply"])
    }
}

