// ClaudeDriver, replayed over Tests/Exchanges/claude (Replay.swift): each file is an exchange recorded in trial T-1
// against the real claude program and a fake model (invented text, paths made /Users/example), with the calls
// something made in between.
import Foundation
import Testing
@testable import SomethingAgents
import SomethingCore

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

    /// The person's assistant builds a space (ClaudeTrial, T-2): twelve steps, none of which asks the person; each
    /// shows it was allowed by a rule (the launch's, or Claude's own for `ls` and the read).
    @Test func assistantBuild() throws {
        let replay = try Replay.play("assistant-build")
        let tools = replay.items.filter { $0.kind == "tool" }
        #expect(tools.count == 12 && tools.allSatisfy { $0.tool?.status == "done" })
        #expect(tools.allSatisfy { $0.decision == Decision(by: "rule", outcome: "allowed") }, "\(tools.map { [$0.text, $0.decision?.by ?? "-"] })")
        #expect(tools.map(\.tool?.name) == ["Bash", "Bash", "Bash", "Read", "Edit", "Edit", "Edit", "Bash", "Bash", "Bash", "Bash", "Bash"])
        #expect(replay.fold.turns.map(\.state) == ["done"])
    }

    /// With Ask Before Every Change, the same build asks before ten of its twelve steps: all but `ls` and the read.
    @Test func assistantAskEverything() throws {
        let replay = try Replay.play("assistant-ask-everything")
        let tools = replay.items.filter { $0.kind == "tool" }
        #expect(tools.count == 12 && tools.allSatisfy { $0.tool?.status == "done" })
        #expect(tools.filter { $0.decision == Decision(by: "person", outcome: "allowed") }.count == 10)
        #expect(tools.filter { $0.decision?.by == "rule" }.map(\.text) == ["ls", "/Users/example/something/spaces/agents-board.html"])
    }

    /// S12: the model's server was busy twice (529); the assistant's detail says each retry, then nothing once the
    /// model answered.
    @Test func assistantRetry() throws {
        let replay = try Replay.play("assistant-retry")
        #expect(replay.fold.turns.map(\.state) == ["done"])
        #expect(replay.fold.agent.error == nil)
    }

    /// A space's own Claude gets no new fact: only the person's assistant says its retries.
    @Test func aSpacesAgentKeepsItsRetriesToItself() throws {
        let replay = Replay()
        _ = try replay.agent.send("Hello.", when: "next")
        replay.feed(["type": "system", "subtype": "session_state_changed", "state": "running"])
        replay.feed(["type": "system", "subtype": "api_retry", "attempt": 1, "max_retries": 10, "retry_delay_ms": 512, "error_status": 529, "error": "overloaded"])
        #expect(replay.fold.agent.detail.isEmpty)
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

    /// The person's assistant (E-1): exactly six rules, its folder's files by their absolute path ("//", which trial
    /// T-2 showed Claude matches) and four of something's commands; none with Ask Before Every Change, nor for a
    /// launch a space asks for, where `assistant` is always nil.
    @Test func theAssistantMayBuildSpacesWithoutAsking() {
        var launch = Launch(agent: "claude-1", folder: "/Users/example/something/spaces", thread: "5b2e0000-0000-4000-8000-000000000001")
        let plain = ClaudeDriver.command(launch).arguments
        launch.assistant = .building
        #expect(ClaudeDriver.command(launch).arguments == plain + [
            "--allowedTools", "Edit(//Users/example/something/spaces/**)", "Write(//Users/example/something/spaces/**)",
            "Bash(something new:*)", "Bash(something check:*)", "Bash(something open:*)", "Bash(something guide:*)"])
        #expect(ClaudeDriver.command(launch, hook: ["/Users/example/something", "hook", "permission"]).arguments.contains("--allowedTools"), "plan B too")
        launch.assistant = .askingEverything
        #expect(ClaudeDriver.command(launch).arguments == plain)
        #expect(!plain.contains("--allowedTools"))
    }

    @Test func aFreshAgentCanDoAll() {
        let agent = Replay().fold.agent
        var can = Can()
        (can.send, can.steer, can.queue, can.interrupt, can.model, can.mode, can.effort) = (true, true, true, true, true, true, true)
        #expect(agent.can == can)
        #expect(agent.because.isEmpty)
        #expect(agent.options.effort == nil, "no effort is offered before Claude lists its models")
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

    /// The shape Claude Code 2.1.296 writes before each retry of a request the model's server refused (S11, a fake
    /// server answering 401): the turn fails at the first one, not after ten retries over four minutes.
    @Test func aRefusedSignInFailsTheTurnAtTheFirstRetry() throws {
        let replay = Replay(assistant: true)
        _ = try replay.agent.send("Hello.", when: "next")
        replay.feed(["type": "system", "subtype": "session_state_changed", "state": "running"])
        let retry: [String: Any] = ["type": "system", "subtype": "api_retry", "attempt": 1, "max_retries": 10, "retry_delay_ms": 512,
                                    "error_status": 401, "error": "authentication_failed", "uuid": "u-retry", "session_id": "s-example"]
        replay.feed(retry)
        replay.feed(retry.merging(["attempt": 2]) { $1 })
        let interrupts = replay.lines().filter { ($0["request"] as? [String: Any])?["subtype"] as? String == "interrupt" }
        #expect(interrupts.count == 1, "Claude is told once to stop retrying")
        replay.feed(["type": "result", "subtype": "error_during_execution", "is_error": true, "terminal_reason": "aborted_streaming"])
        replay.feed(["type": "system", "subtype": "session_state_changed", "state": "idle"])
        #expect(replay.fold.agent.state == "error")
        #expect(replay.fold.agent.error == AgentError(code: "AGENT_ERROR", message: "The model's server refused Claude Code's sign-in (error 401)."))
        #expect(replay.fold.agent.detail["apiRetry"] == .object(["attempt": .number(2), "maxRetries": .number(10), "errorStatus": .number(401),
                                                                   "error": .string("authentication_failed")]), "the failed turn keeps why")
        _ = try replay.agent.send("Again.", when: "next")
        replay.feed(["type": "system", "subtype": "session_state_changed", "state": "running"])
        #expect(replay.fold.agent.detail.isEmpty, "a new turn starts without it")
    }

    @Test func aRetryForAnotherReasonIsLeftToClaude() throws {
        let replay = Replay()
        _ = try replay.agent.send("Hello.", when: "next")
        replay.feed(["type": "system", "subtype": "session_state_changed", "state": "running"])
        let sent = replay.lines().count
        replay.feed(["type": "system", "subtype": "api_retry", "attempt": 1, "max_retries": 10, "retry_delay_ms": 512, "error_status": 529, "error": "overloaded"])
        #expect(replay.lines().count == sent)
        #expect(replay.fold.agent.state == "working")
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
    }

    /// The efforts offered are the model's, from `initialize`; one is set with apply_flag_settings, and shown once
    /// Claude took it. A new model brings its own efforts.
    @Test func anEffortIsOfferedAndSet() throws {
        let replay = Replay()
        let initialize = ["type": "control_response", "response": ["subtype": "success", "request_id": "something-1", "response": [
            "current_permission_mode": "default", "models": [
                ["value": "default", "resolvedModel": "claude-example", "displayName": "Default", "supportedEffortLevels": ["low", "high"]],
                ["value": "small", "resolvedModel": "claude-small-example", "displayName": "Small"]]]]] as [String: Any]
        replay.feed(initialize)
        #expect(replay.fold.agent.options.effort == nil, "the person's settings may pick another model than default")
        #expect(replay.agent.agent.can.effort == false)
        #expect(replay.agent.agent.because["effort"] == "This model offers no effort level.")
        replay.feed(["type": "assistant", "parent_tool_use_id": NSNull(), "message": ["model": "claude-example", "content": []]])
        #expect(replay.fold.agent.options.effort == [Option(value: "low", label: "Low"), Option(value: "high", label: "High")])
        #expect(replay.agent.agent.can.effort == true)
        #expect(replay.agent.agent.because["effort"] == nil)
        #expect(try replay.agent.driver.set(model: nil, mode: nil, effort: "low") == "now")
        let sent = try #require(replay.lines().last)
        #expect(sent["request"] as? [String: Any] as NSDictionary? == ["subtype": "apply_flag_settings", "settings": ["effortLevel": "low"]])
        #expect(replay.fold.agent.effort == nil, "only what Claude confirms is shown")
        replay.feed(["type": "control_response", "response": ["subtype": "success", "request_id": try #require(sent["request_id"] as? String)]])
        #expect(replay.fold.agent.effort == "low")
        _ = try replay.agent.driver.set(model: "small", mode: nil, effort: nil)
        replay.feed(["type": "control_response", "response": ["subtype": "success", "request_id": try #require(replay.lines().last?["request_id"] as? String)]])
        #expect(replay.fold.agent.options.effort == nil, "this model lists no effort")
        #expect(replay.agent.agent.can.effort == false)
        _ = try replay.agent.send("Hello.", when: "next")
        #expect(try replay.agent.driver.set(model: nil, mode: nil, effort: "high") == "next-turn")
    }

    /// Launched without a model, Claude runs the one the person's settings name: its init says which, and the
    /// efforts offered are that one's (none, for the small model here). Claude's own words for a level are kept.
    @Test func theEffortsAreThoseOfTheModelClaudeRuns() throws {
        let replay = Replay()
        replay.feed(["type": "control_response", "response": ["subtype": "success", "request_id": "something-1", "response": ["models": [
            ["value": "default", "resolvedModel": "claude-example", "displayName": "Default", "supportedEffortLevels": ["xhigh", "turbo"]],
            ["value": "small", "resolvedModel": "claude-small-example", "displayName": "Small"]]]]] as [String: Any])
        replay.feed(["type": "system", "subtype": "init", "model": "claude-small-example", "permissionMode": "default"])
        #expect(replay.fold.agent.options.effort == nil)
        #expect(replay.agent.agent.can.effort == false)
        replay.feed(["type": "system", "subtype": "init", "model": "claude-example", "permissionMode": "default"])
        #expect(replay.fold.agent.options.effort == [Option(value: "xhigh", label: "Extra high"), Option(value: "turbo", label: "turbo")])
    }

    @Test func aLaunchPassesItsEffort() {
        let command = ClaudeDriver.command(Launch(agent: "claude-1", folder: "/Users/example/shop", effort: "high"))
        #expect(command.arguments.last == "--effort=high")
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
