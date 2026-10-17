// ClaudeDriver, replayed over Tests/Exchanges/claude: each file is an exchange recorded in trial T-1 against the real
// claude program and a fake model (invented text, paths made /Users/example), with the calls something made in
// between. The replay runs Launched, the code the engine runs, with no process: Claude's lines go in, and every line
// the driver writes must be the next one the exchange recorded ("*" matches any uuid something made up; "*<uuid>"
// also stands for it in Claude's later lines, which named the uuid of the recording).
import Foundation
import Testing
@testable import SomethingAgents
import SomethingCore

final class Replay {
    var written: [Data] = []
    var agent: Launched!
    /// Recorded uuid → the one something made up this time.
    var bound: [String: String] = [:]

    init(mode: String = "default") {
        let launch = Launch(agent: "claude-1", folder: "/Users/example/shop", mode: mode, thread: "5b2e0000-0000-4000-8000-000000000001")
        agent = Launched(ClaudeDriver.self, launch, write: { [unowned self] in written.append($0) }, now: { "2026-10-17T09:00:00Z" })
        try! agent.begin(pid: 4242)
    }

    var fold: Fold { agent.queue.fold }
    var items: [Item] { fold.turns.flatMap(\.items) }

    /// The lines the driver wrote, as JSON objects, from `start` on.
    func lines(from start: Int = 0) -> [[String: Any]] {
        written[start...].map { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] ?? [:] }
    }

    func feed(_ frame: [String: Any]) {
        var line = String(decoding: try! JSONSerialization.data(withJSONObject: frame), as: UTF8.self)
        for (recorded, made) in bound { line = line.replacingOccurrences(of: recorded, with: made) }
        agent.driver.receive(Data(line.utf8))
    }

    /// Plays an exchange file; each mismatch is an issue that names the file and the line.
    static func play(_ name: String) throws -> Replay {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Exchanges/claude/\(name).jsonl")
        let replay = Replay()
        var read = 0
        for (number, text) in try String(contentsOf: file, encoding: .utf8).split(separator: "\n").enumerated() {
            let row = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            let at = "\(name).jsonl:\(number + 1)"
            // {"begin": true} marks where the launch wrote its first lines: Replay() already began.
            if let frame = row["claude"] as? [String: Any] { replay.feed(frame) }
            if let expected = row["something"] as? [String: Any] {
                guard read < replay.written.count else { Issue.record("\(at): nothing was written"); continue }
                let actual = replay.lines(from: read)[0]
                read += 1
                #expect(replay.matches(expected, actual), "\(at): wrote \(String(decoding: replay.written[read - 1], as: UTF8.self))")
            }
            if let text = row["send"] as? String {
                #expect(try replay.agent.send(text, when: row["when"] as! String) == row["delivery"] as! String, "\(at)")
            }
            if let interrupted = row["interrupted"] as? Bool { #expect(try replay.agent.interrupt() == interrupted, "\(at)") }
            if let request = row["answer"] as? String {
                let with: Answer = row["with"] as? String == "once" ? .once : row["with"] as? String == "deny" ? .deny
                    : .choice(row["with"] as? [[String]] ?? [])
                #expect(try replay.agent.answer(request, with), "\(at): the request was not open")
            }
            if let set = row["set"] as? [String: String] {
                #expect(try replay.agent.driver.set(model: set["model"], mode: set["mode"], effort: nil) == row["applied"] as? String, "\(at)")
            }
            if row["stop"] != nil, let goodbye = replay.agent.driver.goodbye { replay.written.append(goodbye) }
            if let code = row["ended"] as? Int { replay.agent.ended(code: Int32(code), errors: "", asked: row["stop"] != nil) }
            if let check = row["check"] as? [String: Any] { replay.check(check, at) }
        }
        #expect(read == replay.written.count, "\(name): \(replay.written.count - read) line(s) written that the exchange does not have")
        return replay
    }

    func check(_ check: [String: Any], _ at: String) {
        let agent = fold.agent
        if let state = check["state"] as? String { #expect(agent.state == state, "\(at)") }
        if let waiting = check["waiting"] as? String { #expect(agent.waiting == waiting, "\(at)") }
        if let alive = check["alive"] as? Bool { #expect(agent.alive == alive, "\(at)") }
        if let mode = check["mode"] as? String { #expect(agent.mode == mode, "\(at)") }
        if let count = check["requests"] as? Int { #expect(fold.requests.count == count, "\(at)") }
        if let queue = check["queue"] as? [String] { #expect(agent.queue.map(\.text) == queue, "\(at)") }
    }

    /// Equal JSON, but for a string starting with "*", which matches any string ("*<uuid>" binds that uuid to it).
    func matches(_ expected: Any, _ actual: Any) -> Bool {
        switch (expected, actual) {
        case (let e as [String: Any], let a as [String: Any]):
            return Set(e.keys) == Set(a.keys) && e.allSatisfy { key, value in matches(value, a[key]!) }
        case (let e as [Any], let a as [Any]): return e.count == a.count && zip(e, a).allSatisfy { matches($0, $1) }
        case (let e as String, let a as String):
            guard e.hasPrefix("*") else { return e == a }
            if e.count > 1 { bound[String(e.dropFirst())] = a }
            return true
        default: return (expected as? NSObject) == (actual as? NSObject)
        }
    }
}

@Suite struct ClaudeReplayTests {
    @Test func permissionOnce() throws {
        let replay = try Replay.play("permission-once")
        let tool = try #require(replay.items.first { $0.kind == "tool" })
        #expect(tool.tool == Tool(name: "Bash", status: "done"))
        #expect(tool.text == "touch invented.txt")
        #expect(tool.decision == Decision(by: "person", outcome: "allowed"))
        #expect(replay.items.first?.author == "person", "the person's message opens the turn")
        #expect(replay.fold.turns.map(\.state) == ["done"])
    }

    @Test func deny() throws {
        let replay = try Replay.play("deny")
        let tool = try #require(replay.items.first { $0.kind == "tool" })
        #expect(tool.tool?.status == "failed")
        #expect(tool.decision == Decision(by: "person", outcome: "denied"))
    }

    @Test func question() throws {
        let replay = try Replay.play("question")
        #expect(replay.fold.turns.map(\.state) == ["done"])
        let tool = try #require(replay.items.first { $0.kind == "tool" })
        #expect(tool.tool == Tool(name: "AskUserQuestion", status: "done"))
        #expect(tool.decision == Decision(by: "person", outcome: "allowed"))
    }

    @Test func aQuestionIsShownWithItsOptions() throws {
        let replay = Replay()
        _ = try replay.agent.send("Please ask-me something.", when: "next")
        replay.feed(["type": "control_request", "request_id": "q-1", "request": ["subtype": "can_use_tool", "tool_name": "AskUserQuestion", "tool_use_id": "toolu_example",
                     "input": ["questions": [["question": "Which colour?", "header": "Colour", "multiSelect": true,
                                              "options": [["label": "Blue", "description": "Calm"], ["label": "Green", "description": "Fresh"]]]]]]])
        let request = try #require(replay.fold.requests.first)
        #expect(request == Request(id: "claude-1:q-1", agent: "claude-1", kind: "question", tool: "AskUserQuestion", about: "Which colour?", at: "2026-10-17T09:00:00Z"))
        #expect(replay.agent.driver.prompt(request.id)?.questions == [Question(header: "Colour", text: "Which colour?", options: ["Blue", "Green"], multiple: true)])
        #expect(replay.fold.agent.waiting == "answer")
        // Several labels are joined as Claude's own panel joins them.
        #expect(try replay.agent.driver.answer(request.id, .choice([["Blue", "Green"]])))
        let reply = try #require(replay.lines().last?["response"] as? [String: Any])
        let updated = (reply["response"] as? [String: Any])?["updatedInput"] as? [String: Any]
        #expect(updated?["answers"] as? [String: String] == ["Which colour?": "Blue, Green"])
        #expect(try replay.agent.driver.answer(request.id, .once) == false, "an answered request is closed")
    }

    @Test func steerAndQueueOrder() throws {
        let replay = try Replay.play("steer-queue")
        #expect(replay.fold.turns.map(\.state) == ["done", "done", "done"])
        #expect(replay.items.filter { $0.author == "person" }.map(\.text) ==
                ["Please run-sleep for me.", "Steered: use the small one.", "Queued: then the docs.", "Queued: and the tests."])
    }

    @Test func interrupt() throws {
        let replay = try Replay.play("interrupt")
        #expect(replay.fold.turns.last?.state == "interrupted")
        #expect(replay.fold.agent.error == nil, "an interrupt the person asked for is no error")
        // Claude cancels the message it had read with its turn: it stays in the thread.
        #expect(replay.items.first?.text == "Please run-sleep for me.")
    }

    /// Recorded in T-1: the steer Claude still held is cancelled by the interrupt (`cancel_queued`) before it started.
    @Test func aSteerDroppedByAnInterrupt() throws {
        let replay = try Replay.play("steer-interrupt")
        #expect(replay.items.filter { $0.author == "person" }.map(\.text) == ["Please run-sleep for me."], "a steer never read is never shown")
        #expect(replay.fold.turns.map(\.state) == ["interrupted"])
        #expect(replay.fold.agent.error == nil, "the person asked for it")
    }

    @Test func withdrawn() throws {
        let replay = try Replay.play("withdrawn")
        #expect(replay.fold.requests.isEmpty)
        #expect(replay.fold.turns.last?.state == "interrupted")
    }

    @Test func setModeAndModel() throws {
        let replay = try Replay.play("set")
        #expect(replay.fold.agent.mode == "plan")
        #expect(replay.fold.agent.model == nil, "set_model's success names no model: the alias asked for is not shown")
        #expect(replay.fold.agent.options.model?.map(\.value) == ["default", "sonnet"])
        #expect(replay.fold.agent.options.mode?.map(\.value) == ["default", "acceptEdits", "plan", "auto", "dontAsk"])
    }

    @Test func stop() throws {
        let replay = try Replay.play("stop")
        #expect(replay.fold.agent.error == nil)
        #expect(replay.fold.agent.can == Can(), "an ended agent can do nothing")
        #expect(replay.fold.agent.model == "claude-opus-5-5")
    }
}

@Suite struct ClaudeDriverTests {
    @Test func theLaunchLineIsExplicit() {
        let launch = Launch(agent: "claude-1", folder: "/Users/example/shop", model: "sonnet", thread: "5b2e0000-0000-4000-8000-000000000001")
        let command = ClaudeDriver.command(launch)
        #expect(command.arguments == ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                                      "--permission-prompt-tool", "stdio", "--include-hook-events", "--permission-mode", "default",
                                      "--session-id", "5b2e0000-0000-4000-8000-000000000001", "--model=sonnet"])
        #expect(command.adding == ["CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS": "1"])
        #expect(command.removing == ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"])
        #expect(!ClaudeDriver.modes.contains { $0.value == "bypassPermissions" })
    }

    @Test func aFreshAgentCanDoAllButEffort() {
        let agent = Replay().fold.agent
        var can = Can()
        (can.send, can.steer, can.queue, can.interrupt, can.model, can.mode) = (true, true, true, true, true, true)
        #expect(agent.can == can)
        #expect(agent.because == ["effort": "something cannot change Claude Code's effort yet."])
        #expect((agent.origin, agent.thread, agent.name) == ("launched", "5b2e0000-0000-4000-8000-000000000001", "shop"))
    }

    @Test func unknownFramesAndBrokenLinesChangeNothing() {
        let replay = Replay()
        let before = replay.fold.agent
        replay.feed(["type": "something_new", "model": "nope"])
        replay.agent.driver.receive(Data("not json".utf8))
        #expect(replay.fold.agent == before)
    }

    @Test func aSyntheticMessageIsAnErrorNotAReply() throws {
        let replay = Replay()
        _ = try replay.agent.send("Hello.", when: "next")
        replay.feed(["type": "assistant", "uuid": "u1", "message": ["model": "<synthetic>", "content": [["type": "text", "text": "Invented: this key was refused."]]]])
        #expect(replay.fold.agent.error == AgentError(code: "AGENT_ERROR", message: "Invented: this key was refused."))
        #expect(replay.fold.agent.model == nil)
        #expect(!replay.items.contains { $0.author == "agent" })
    }

    @Test func aFailedTurnIsAnError() throws {
        let replay = Replay()
        _ = try replay.agent.send("Hello.", when: "next")
        replay.feed(["type": "system", "subtype": "session_state_changed", "state": "running"])
        replay.feed(["type": "result", "subtype": "error_max_turns", "is_error": true, "terminal_reason": "max_turns", "errors": ["Invented: too many turns."]])
        replay.feed(["type": "system", "subtype": "session_state_changed", "state": "idle"])
        #expect(replay.fold.agent.state == "error")
        #expect(replay.fold.agent.error == AgentError(code: "AGENT_ERROR", message: "Invented: too many turns."))
    }

    /// An older Claude that never says its state: `init` and `result` mark the turn.
    @Test func withoutStateEventsInitAndResultMarkTheTurn() throws {
        let replay = Replay()
        replay.feed(["type": "system", "subtype": "init", "model": "claude-example", "permissionMode": "default"])
        #expect(replay.fold.agent.state == "working")
        replay.feed(["type": "result", "subtype": "success", "is_error": false, "terminal_reason": "completed"])
        #expect(replay.fold.agent.state == "idle")
    }

    @Test func aRequestNobodyAskedForIsRefused() throws {
        let replay = Replay()
        replay.feed(["type": "control_request", "request_id": "x-1", "request": ["subtype": "elicitation"]])
        let reply = try #require(replay.lines().last?["response"] as? [String: Any])
        #expect(reply["subtype"] as? String == "error")
        #expect(reply["request_id"] as? String == "x-1")
        #expect(replay.fold.requests.isEmpty)
    }

    @Test func aRefusedSettingIsTheAgentsError() throws {
        let replay = Replay()
        _ = try replay.agent.driver.set(model: nil, mode: "plan", effort: nil)
        replay.feed(["type": "control_response", "response": ["subtype": "error", "request_id": "something-2",
                                                              "error": "Invented: cannot set permission mode.", "error_code": "invalid_mode"]])
        #expect(replay.fold.agent.error == AgentError(code: "AGENT_ERROR", message: "Claude Code refused the new mode: Invented: cannot set permission mode."))
        #expect(replay.fold.agent.mode == nil, "only what Claude confirms is shown")
        #expect(throws: CodedError.self) { try replay.agent.driver.set(model: nil, mode: nil, effort: "low") }
    }

    @Test func aModelSetDuringATurnAppliesNextTurn() throws {
        let replay = Replay()
        _ = try replay.agent.send("Hello.", when: "next")
        #expect(try replay.agent.driver.set(model: "sonnet", mode: nil, effort: nil) == "next-turn")
        #expect(try replay.agent.driver.set(model: nil, mode: "plan", effort: nil) == "now")
    }

    @Test func anEndBeforeAnyLineIsAFailedLaunch() {
        let replay = Replay()
        replay.agent.ended(code: 1, errors: "error: Invented: unknown option\n", asked: false)
        #expect(replay.fold.agent.error == AgentError(code: "LAUNCH_FAILED", message: "Claude Code could not start: error: Invented: unknown option"))
        #expect(replay.fold.agent.state == "error")
        let other = Replay()
        other.feed(["type": "system", "subtype": "ui_invalidate"])
        other.agent.ended(code: 143, errors: "", asked: true)
        #expect(other.fold.agent.error == nil, "a stop something asked for is no failure")
        #expect(other.fold.agent.state == "done")
    }

    @Test func aSubagentsModelIsNotTheAgents() throws {
        let replay = Replay()
        _ = try replay.agent.send("Hello.", when: "next")
        replay.feed(["type": "assistant", "uuid": "u1", "parent_tool_use_id": NSNull(), "message": ["model": "claude-example", "content": [["type": "text", "text": "Invented."]]]])
        replay.feed(["type": "assistant", "uuid": "u2", "parent_tool_use_id": "toolu_x", "message": ["model": "claude-other", "content": [["type": "text", "text": "Invented, deeper."]]]])
        #expect(replay.fold.agent.model == "claude-example")
        #expect(replay.items.last?.kind == "subagent")
    }

    /// A steer is shown once Claude takes it in; one Claude drops unread is never shown, and is an error unless an
    /// interrupt asked for it.
    @Test func aSteerIsShownOnceClaudeReadsIt() throws {
        let replay = Replay()
        _ = try replay.agent.send("Hello.", when: "next")
        replay.feed(["type": "system", "subtype": "session_state_changed", "state": "running"])
        #expect(try replay.agent.send("Steered: invented.", when: "now") == "steered")
        let steer = try #require(replay.lines().last?["uuid"] as? String)
        #expect(replay.items.map(\.text) == ["Hello."])
        replay.feed(["type": "command_lifecycle", "command_uuid": steer, "state": "queued"])
        replay.feed(["type": "command_lifecycle", "command_uuid": steer, "state": "started"])
        #expect(replay.items.map(\.text) == ["Hello.", "Steered: invented."])

        #expect(try replay.agent.send("Steered: dropped.", when: "now") == "steered")
        let dropped = try #require(replay.lines().last?["uuid"] as? String)
        replay.feed(["type": "command_lifecycle", "command_uuid": dropped, "state": "discarded"])
        #expect(replay.items.map(\.text) == ["Hello.", "Steered: invented."])
        #expect(replay.fold.agent.error == AgentError(code: "AGENT_ERROR", message: "Claude Code dropped the message “Steered: dropped.” without reading it."))
    }

    @Test func aRequestClosesWithTheAgentsEnd() throws {
        let replay = Replay()
        _ = try replay.agent.send("Please run-echo now.", when: "next")
        replay.feed(["type": "control_request", "request_id": "p-1", "request": ["subtype": "can_use_tool", "tool_name": "Bash", "tool_use_id": "toolu_example", "input": ["command": "echo invented"]]])
        #expect(replay.agent.prompt("claude-1:p-1") != nil)
        replay.agent.ended(code: 0, errors: "", asked: true)
        #expect(replay.agent.prompt("claude-1:p-1") == nil, "nobody is left to answer it: its window closes")
        #expect(try replay.agent.answer("claude-1:p-1", .once) == false)
    }

    @Test func aChoiceAnswersEveryQuestion() throws {
        let replay = Replay()
        _ = try replay.agent.send("Please ask-me something.", when: "next")
        replay.feed(["type": "control_request", "request_id": "q-1", "request": ["subtype": "can_use_tool", "tool_name": "AskUserQuestion", "tool_use_id": "toolu_example",
                     "input": ["questions": [["question": "Which colour?", "options": [["label": "Blue"]]], ["question": "Which size?", "options": [["label": "Small"]]]]]]])
        let written = replay.written.count
        #expect(throws: CodedError("BAD_PARAMS", "Answer each of the 2 questions, in their order.")) { try replay.agent.answer("claude-1:q-1", .choice([["Blue"]])) }
        #expect(replay.written.count == written, "nothing is sent")
        #expect(replay.agent.prompt("claude-1:q-1") != nil, "the question is still open")
    }

    @Test func aDecisionByARuleIsShown() throws {
        let replay = Replay()
        _ = try replay.agent.send("Hello.", when: "next")
        replay.feed(["type": "assistant", "uuid": "u1", "message": ["model": "claude-example", "content": [["type": "tool_use", "id": "toolu_example", "name": "Bash", "input": ["command": "ls"]]]]])
        replay.feed(["type": "user", "message": ["content": [["type": "tool_result", "tool_use_id": "toolu_example", "is_error": false, "content": "Invented"]]],
                     "tool_result_meta": [["id": "toolu_example", "permission_decision": ["decision": "accept", "source": "config", "reason_type": "subcommandResults"]]]])
        #expect(replay.items.last?.decision == Decision(by: "rule", outcome: "allowed"))
        #expect(replay.items.last?.tool == Tool(name: "Bash", status: "done"))
    }
}
