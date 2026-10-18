// CodexDriver, replayed over Tests/Exchanges/codex (Replay.swift): each file was recorded in trial T-2 against the real
// codex app-server 0.163.0 and FakeResponsesAPI, with invented text. Then the cases no recording holds, built from the
// recorded shapes: Codex's answers arriving late, an interrupt never answered, requests something does not handle.
import Foundation
import Testing
@testable import SomethingAgents
import SomethingCore

@Suite struct CodexReplayTests {
    @Test func permissionOnce() throws {
        let replay = try Replay.play("permission-once", kind: "codex")
        let tool = try #require(replay.items.first { $0.kind == "tool" })
        #expect(tool.tool == Tool(name: "commandExecution", status: "done"))
        #expect(tool.decision == Decision(by: "person", outcome: "allowed"))
        #expect(replay.items.first?.author == "person", "the person's message opens the turn")
        #expect(replay.fold.turns.map(\.state) == ["done"])
        let reply = try #require(replay.lines().first { $0["result"] != nil })
        #expect(reply["result"] as? [String: String] == ["decision": "accept"])
    }

    @Test func deny() throws {
        let replay = try Replay.play("deny", kind: "codex")
        let tool = try #require(replay.items.first { $0.kind == "tool" })
        #expect(tool.tool?.status == "failed")
        #expect(tool.decision == Decision(by: "person", outcome: "denied"))
        #expect(replay.fold.turns.map(\.state) == ["done"], "a declined command lets the turn go on")
    }

    /// The permissions asked for are sent back, and Codex grants them.
    @Test func morePermissions() throws {
        let replay = try Replay.play("permissions", kind: "codex")
        let reply = try #require(replay.lines().first { $0["result"] != nil }?["result"] as? [String: Any])
        #expect(reply["scope"] as? String == "turn")
        #expect((reply["permissions"] as? [String: Any])?["network"] as? [String: Bool] == ["enabled": true])
    }

    @Test func withdrawn() throws {
        let replay = try Replay.play("withdrawn", kind: "codex")
        #expect(replay.fold.turns.map(\.state) == ["interrupted"])
        #expect(replay.agent.prompt("codex-1:0") == nil)
        #expect(!replay.lines().contains { $0["result"] != nil }, "a withdrawn request is never answered")
    }

    @Test func question() throws {
        let replay = try Replay.play("question", kind: "codex")
        let reply = try #require(replay.lines().first { $0["result"] != nil }?["result"] as? [String: Any])
        #expect(reply["answers"] as? [String: [String: [String]]] == ["colour": ["answers": ["Green"]]])
        #expect(replay.fold.turns.map(\.state) == ["done"])
    }

    @Test func steerAndQueue() throws {
        let replay = try Replay.play("steer-queue", kind: "codex")
        #expect(replay.fold.turns.map(\.state) == ["done", "done", "done"], "the steer joined the first turn")
        let methods = replay.lines().compactMap { $0["method"] as? String }
        #expect(methods.filter { $0.hasPrefix("turn/") } == ["turn/start", "turn/steer", "turn/start", "turn/start"])
        let people = replay.items.filter { $0.author == "person" }.map(\.text)
        #expect(people == ["Please run-sleep for me.", "Steered: use the small one.", "Queued: then the docs.", "Queued: and the tests."])
    }

    @Test func interrupt() throws {
        let replay = try Replay.play("interrupt", kind: "codex")
        #expect(replay.fold.turns.map(\.state) == ["interrupted", "done"])
        let methods = replay.lines().compactMap { $0["method"] as? String }
        #expect(methods.filter { $0 == "turn/interrupt" }.count == 1, "no interrupt goes to a thread whose turn ended")
        #expect(!replay.items.contains { $0.text == "Queued: dropped." })
        #expect(replay.fold.agent.error == nil)
    }

    @Test func set() throws {
        let replay = try Replay.play("set", kind: "codex")
        let agent = replay.fold.agent
        #expect((agent.model, agent.mode, agent.effort) == ("other-model", "never", "high"))
    }

    @Test func resume() throws {
        let replay = try Replay.play("resume", kind: "codex")
        let resume = try #require(replay.lines().first { $0["method"] as? String == "thread/resume" }?["params"] as? [String: Any])
        #expect(replay.fold.agent.thread == resume["threadId"] as? String)
        #expect(resume["excludeTurns"] as? Bool == true, "a long thread's history is not read back")
        #expect(replay.fold.turns.map(\.state) == ["done"])
    }

    @Test func heldElsewhere() throws {
        let replay = try Replay.play("held", kind: "codex")
        #expect(replay.quit, "the program is told to end")
        #expect(replay.fold.agent.error == AgentError(code: "HELD_ELSEWHERE", message: "Codex's background service holds this conversation; run `codex app-server daemon stop` in a terminal, then try again."))
    }

    @Test func stop() throws {
        let replay = try Replay.play("stop", kind: "codex")
        #expect(replay.agent.driver.goodbye == nil, "closing its input is the way")
        #expect(replay.fold.agent.state == "done")
        #expect(replay.fold.agent.error == nil)
    }
}

@Suite struct CodexDriverTests {
    static let thread = "01a14bae-0000-7000-8000-000000000001", turn = "01a14bae-0000-7000-8000-0000000000aa"

    /// A replay whose thread is open: initialize and thread/start answered as the recordings show.
    /// `policy` is the one Codex reports, by default the one asked for or else its own default.
    static func opened(mode: String? = nil, policy: Any? = nil) -> Replay {
        let replay = Replay.codex(mode: mode)
        replay.feed(["id": 1, "result": ["codexHome": "/Users/example/.codex", "platformFamily": "unix", "platformOs": "macos", "userAgent": "something/0.163.0"]])
        replay.feed(["id": 2, "result": ["thread": ["id": thread], "model": "fake-model", "approvalPolicy": policy ?? mode ?? "on-request", "reasoningEffort": NSNull()]])
        return replay
    }

    static func params(_ replay: Replay, _ method: String) -> [String: Any]? {
        replay.lines().last { $0["method"] as? String == method }?["params"] as? [String: Any]
    }

    static func started(_ replay: Replay, call id: Int) {
        replay.feed(["id": id, "result": ["turn": ["id": turn, "status": "inProgress", "items": []]]])
        replay.feed(["method": "thread/status/changed", "params": ["threadId": thread, "status": ["type": "active", "activeFlags": []]]])
        replay.feed(["method": "turn/started", "params": ["threadId": thread, "turn": ["id": turn, "status": "inProgress"]]])
    }

    @Test func theCommandIsTheAppServer() {
        #expect(CodexDriver.command(Launch(agent: "codex-1", folder: "/Users/example/shop")) == Command(arguments: ["app-server"]))
        #expect(Replay.codex().fold.agent.thread == nil, "the thread is unknown until Codex names it")
        #expect(Replay.codex(resume: Self.thread).fold.agent.thread == Self.thread)
    }

    /// A launch without a mode leaves the thread's policy as it is, unless that policy never asks: its first turn
    /// then asks when needed. A mode chosen goes with the thread.
    @Test func aLaunchAsksWhenNeededUnlessToldOtherwise() throws {
        let replay = Self.opened()
        #expect(Self.params(replay, "thread/start")?["approvalPolicy"] == nil, "a resumed thread's own policy is kept")
        #expect(replay.fold.agent.thread == Self.thread)
        #expect(replay.fold.agent.mode == "on-request")
        _ = try replay.agent.send("Hello.", when: "next")
        #expect(Self.params(replay, "turn/start")?["approvalPolicy"] == nil)

        let chosen = Self.opened(mode: "never")
        #expect(Self.params(chosen, "thread/start")?["approvalPolicy"] as? String == "never")
        _ = try chosen.agent.send("Hello.", when: "next")
        #expect(Self.params(chosen, "turn/start")?["approvalPolicy"] == nil, "the person chose it")

        for policy: Any in ["never", ["granular": ["rules": false]], NSNull()] {
            let raised = Self.opened(policy: policy)
            _ = try raised.agent.send("Hello.", when: "next")
            #expect(Self.params(raised, "turn/start")?["approvalPolicy"] as? String == "on-request", "\(policy)")
        }
        #expect(Self.opened(policy: ["granular": ["rules": false]]).fold.agent.mode == "granular")
        #expect(Self.opened(policy: NSNull()).fold.agent.mode == nil, "a null policy is unknown, not granular")
    }

    /// Messages sent before Codex answered: the first starts the turn once the thread exists, a steer waits for the
    /// turn's id, and an interrupt for Codex to say the turn is active.
    @Test func earlyCallsWaitForWhatTheyNeed() throws {
        let replay = Replay.codex()
        #expect(try replay.agent.send("First.", when: "next") == "started")
        #expect(try replay.agent.send("Steered.", when: "now") == "steered")
        #expect(replay.written.count == 1, "only initialize so far")
        replay.feed(["id": 1, "result": [:]])
        replay.feed(["id": 2, "result": ["thread": ["id": Self.thread], "model": "fake-model", "approvalPolicy": "on-request"]])
        #expect(replay.lines().compactMap { $0["method"] as? String } == ["initialize", "initialized", "thread/start", "model/list", "turn/start"])
        #expect(try replay.agent.interrupt())
        replay.feed(["id": 4, "result": ["turn": ["id": Self.turn, "status": "inProgress"]]])
        #expect(replay.lines().last?["method"] as? String == "turn/start", "the interrupt dropped the steer, and waits for an active turn")
        replay.feed(["method": "thread/status/changed", "params": ["threadId": Self.thread, "status": ["type": "active", "activeFlags": []]]])
        let interrupt = try #require(replay.lines().last)
        #expect(interrupt["method"] as? String == "turn/interrupt")
        #expect(interrupt["params"] as? [String: String] == ["threadId": Self.thread, "turnId": Self.turn])
    }

    @Test func aSteerWaitsForTheTurnsID() throws {
        let replay = Self.opened()
        _ = try replay.agent.send("First.", when: "next")
        _ = try replay.agent.send("Steered.", when: "now")
        #expect(replay.lines().last?["method"] as? String == "turn/start")
        Self.started(replay, call: 4)
        let steer = try #require(replay.lines().last)
        #expect(steer["method"] as? String == "turn/steer")
        #expect((steer["params"] as? [String: Any])?["expectedTurnId"] as? String == Self.turn)
    }

    /// Codex never answers an interrupt in some states: after 5 s something says so, and can send another.
    @Test func anUnansweredInterruptTimesOut() throws {
        let replay = Self.opened()
        _ = try replay.agent.send("Please run-sleep for me.", when: "next")
        Self.started(replay, call: 4)
        #expect(try replay.agent.interrupt())
        #expect(replay.scheduled.count == 1)
        replay.scheduled.removeFirst()()
        #expect(replay.fold.agent.error?.message == "Codex did not confirm the interrupt within 5 seconds; it may still be working.")
        #expect(try replay.agent.interrupt())
        #expect(replay.lines().filter { $0["method"] as? String == "turn/interrupt" }.count == 2)
        // A late answer to the first leaves the second unanswered: its timer still says so.
        replay.feed(["id": 5, "result": [:]])
        Self.unrelatedError(replay)
        replay.scheduled.removeFirst()()
        #expect(replay.fold.agent.error?.message == "Codex did not confirm the interrupt within 5 seconds; it may still be working.")
        // An interrupt answered in time: its timer says nothing.
        #expect(try replay.agent.interrupt())
        replay.feed(["id": 7, "result": [:]])
        Self.unrelatedError(replay)
        replay.scheduled.removeFirst()()
        #expect(replay.fold.agent.error?.message == "Invented unrelated error.")
    }

    static func unrelatedError(_ replay: Replay) {
        replay.feed(["method": "error", "params": ["threadId": thread, "error": ["message": "Invented unrelated error."], "willRetry": false]])
        #expect(replay.fold.agent.error?.message == "Invented unrelated error.")
    }

    /// The state shows what Codex reports once it took the turn, never what was asked: here Codex took a
    /// different effort than the one asked for.
    @Test func settingsGoWithTheNextTurn() throws {
        let replay = Self.opened()
        #expect(try replay.agent.driver.set(model: "other-model", mode: "untrusted", effort: "low") == "next-turn")
        #expect(replay.fold.agent.model == "fake-model")
        _ = try replay.agent.send("Hello.", when: "next")
        let params = try #require(replay.lines().last?["params"] as? [String: Any])
        #expect((params["model"] as? String, params["approvalPolicy"] as? String, params["effort"] as? String) == ("other-model", "untrusted", "low"))
        Self.started(replay, call: 4)
        #expect((replay.fold.agent.model, replay.fold.agent.mode) == ("fake-model", "on-request"), "nothing is reported yet")
        let read = try #require(replay.lines().first { $0["method"] as? String == "thread/resume" })
        #expect(read["id"] as? Int == 5)
        #expect(read["params"] as? [String: AnyHashable] == ["threadId": Self.thread, "excludeTurns": true], "no override: only a read")
        replay.feed(["id": 5, "result": ["thread": ["id": Self.thread], "model": "other-model", "approvalPolicy": "untrusted", "reasoningEffort": "medium"]])
        #expect((replay.fold.agent.model, replay.fold.agent.mode, replay.fold.agent.effort) == ("other-model", "untrusted", "medium"))
        replay.feed(["method": "turn/completed", "params": ["threadId": Self.thread, "turn": ["id": Self.turn, "status": "completed"]]])
        _ = try replay.agent.send("Again.", when: "next")
        #expect((replay.lines().last?["params"] as? [String: Any])?["model"] == nil, "Codex keeps them: they are sent once")
    }

    /// On a new thread's first turn Codex refuses the read-back (its rollout is still empty): the settings are read
    /// again once that turn completes, so the new model is still reported.
    @Test func aRefusedReadBackIsTriedAgainAtTheTurnEnd() throws {
        let replay = Self.opened()
        _ = try replay.agent.driver.set(model: "other-model", mode: nil, effort: nil)
        _ = try replay.agent.send("Hello.", when: "next")
        Self.started(replay, call: 4)
        replay.feed(["id": 5, "error": ["code": -32600, "message": "Invented: no rollout found for thread"]])
        #expect(replay.fold.agent.model == "fake-model")
        #expect(replay.fold.agent.error == nil, "a refused read-back is no error of the agent")
        replay.feed(["method": "turn/completed", "params": ["threadId": Self.thread, "turn": ["id": Self.turn, "status": "completed"]]])
        let reads = replay.lines().filter { $0["method"] as? String == "thread/resume" }
        #expect(reads.map { $0["id"] as? Int } == [5, 6])
        replay.feed(["id": 6, "result": ["thread": ["id": Self.thread], "model": "other-model", "approvalPolicy": "on-request"]])
        #expect(replay.fold.agent.model == "other-model")
        _ = try replay.agent.send("Again.", when: "next")
        Self.started(replay, call: 7)
        replay.feed(["method": "turn/completed", "params": ["threadId": Self.thread, "turn": ["id": Self.turn, "status": "completed"]]])
        #expect(replay.lines().filter { $0["method"] as? String == "thread/resume" }.count == 2, "read again once only")
    }

    @Test func anEffortGivenAtLaunchGoesWithTheFirstTurn() throws {
        let replay = Replay.codex(effort: "high")
        replay.feed(["id": 1, "result": [:]])
        replay.feed(["id": 2, "result": ["thread": ["id": Self.thread], "model": "fake-model", "approvalPolicy": "on-request"]])
        _ = try replay.agent.send("Hello.", when: "next")
        #expect((replay.lines().last?["params"] as? [String: Any])?["effort"] as? String == "high")
    }

    @Test func aFileChangeShowsItsPaths() throws {
        let replay = Self.opened()
        _ = try replay.agent.send("Please patch it.", when: "next")
        Self.started(replay, call: 4)
        replay.feed(["method": "item/started", "params": ["threadId": Self.thread, "item": ["type": "fileChange", "id": "call_1", "status": "inProgress",
                                                                                        "changes": [["path": "/Users/example/shop/notes.txt", "kind": ["type": "add"], "diff": "+invented line\n"]]]]])
        replay.feed(["id": 0, "method": "item/fileChange/requestApproval", "params": ["threadId": Self.thread, "turnId": Self.turn, "itemId": "call_1", "reason": NSNull()]])
        let prompt = try #require(replay.agent.prompt("codex-1:0"))
        #expect(prompt.request.about == "/Users/example/shop/notes.txt")
        #expect(prompt.input == "+invented line\n")
        #expect(try replay.agent.answer("codex-1:0", .deny))
        #expect(replay.lines().last?["result"] as? [String: String] == ["decision": "decline"])
        #expect(replay.items.first { $0.kind == "tool" }?.decision == Decision(by: "person", outcome: "denied"))
    }

    @Test func refusalsHaveTheirShape() throws {
        let replay = Self.opened()
        _ = try replay.agent.send("Please need-more access.", when: "next")
        Self.started(replay, call: 4)
        replay.feed(["id": 0, "method": "item/permissions/requestApproval", "params": ["threadId": Self.thread, "itemId": "call_2", "permissions": ["network": ["enabled": true]]]])
        #expect(try replay.agent.answer("codex-1:0", .deny))
        #expect(((replay.lines().last?["result"] as? [String: Any])?["permissions"] as? [String: Any])?.isEmpty == true)
        replay.feed(["id": 1, "method": "item/tool/requestUserInput", "params": ["threadId": Self.thread, "itemId": "call_3",
                                                                               "questions": [["id": "colour", "header": "Colour", "question": "Which colour?", "isOther": false, "isSecret": false,
                                                                                              "options": [["label": "Blue", "description": "Calm"]]]]]])
        #expect(replay.fold.agent.waiting == "answer")
        #expect(throws: CodedError.self) { try replay.agent.answer("codex-1:1", .choice([])) }
        #expect(try replay.agent.answer("codex-1:1", .deny))
        #expect(((replay.lines().last?["result"] as? [String: Any])?["answers"] as? [String: Any])?.isEmpty == true)
        replay.feed(["id": 2, "method": "mcpServer/elicitation/request", "params": ["threadId": Self.thread]])
        let error = try #require(replay.lines().last?["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32601)
        #expect(replay.fold.requests.isEmpty, "a request something does not handle is refused, not shown")
    }

    @Test func aMissingThreadAndAFailedStart() throws {
        let replay = Replay.codex(resume: "01a14bae-0000-7000-8000-00000000dead")
        replay.feed(["id": 1, "result": [:]])
        replay.feed(["id": 2, "error": ["code": -32600, "message": "no rollout found for thread id 01a14bae-0000-7000-8000-00000000dead"]])
        #expect(replay.fold.agent.error?.code == "THREAD_NOT_FOUND")
        #expect(replay.quit)
        replay.agent.ended(code: 0, errors: "", asked: false)
        #expect(replay.fold.agent.state == "error")

        let early = Replay.codex()
        early.agent.ended(code: 1, errors: "error: unexpected argument\n", asked: false)
        #expect(early.fold.agent.error == AgentError(code: "LAUNCH_FAILED", message: "Codex could not start: error: unexpected argument"))
    }

    /// An interrupt asked before Codex refused the turn belongs to that turn: the next one is not interrupted.
    @Test func aRefusedTurnTakesItsInterruptAlong() throws {
        let replay = Self.opened()
        _ = try replay.agent.send("First.", when: "next")
        _ = try replay.agent.send("Steered.", when: "now")
        #expect(try replay.agent.interrupt())
        replay.feed(["id": 4, "error": ["code": -32600, "message": "Invalid request: invented refusal"]])
        #expect(try replay.agent.send("Second.", when: "next") == "started")
        Self.started(replay, call: 5)
        let methods = replay.lines().compactMap { $0["method"] as? String }
        #expect(!methods.contains("turn/interrupt") && !methods.contains("turn/steer"), "\(methods)")
    }

    /// For a model the catalog does not list, no effort is offered, so none can be set.
    @Test func noEffortForAModelTheCatalogLacks() throws {
        let replay = Self.opened()
        let entry: [String: Any] = ["id": "other-model", "model": "other-model", "displayName": "Other", "hidden": false,
                                    "supportedReasoningEfforts": [["reasoningEffort": "low", "description": "Invented."]]]
        replay.feed(["id": 3, "result": ["data": [entry]]])
        #expect(replay.agent.agent.can.effort == false)
        #expect(replay.agent.agent.because["effort"] != nil)
        let listed = Replay.codex()
        listed.feed(["id": 1, "result": [:]])
        listed.feed(["id": 2, "result": ["thread": ["id": Self.thread], "model": "other-model", "approvalPolicy": "on-request"]])
        listed.feed(["id": 3, "result": ["data": [entry]]])
        #expect(listed.agent.agent.can.effort == true)
    }

    /// A question Codex sent without its text is not shown, and the answers go to the questions shown.
    @Test func answersGoToTheQuestionsShown() throws {
        let replay = Self.opened()
        _ = try replay.agent.send("Please ask-me something.", when: "next")
        Self.started(replay, call: 4)
        replay.feed(["id": 0, "method": "item/tool/requestUserInput", "params": ["threadId": Self.thread, "itemId": "call_3", "questions": [
            ["id": "blank", "header": "Blank", "options": []],
            ["id": "colour", "header": "Colour", "question": "Which colour?", "options": [["label": "Blue", "description": "Calm"]]]]]])
        #expect(replay.agent.prompt("codex-1:0")?.questions.map(\.text) == ["Which colour?"])
        #expect(try replay.agent.answer("codex-1:0", .choice([["Blue"]])))
        #expect((replay.lines().last?["result"] as? [String: Any])?["answers"] as? [String: [String: [String]]] == ["colour": ["answers": ["Blue"]]])
    }

    @Test func aRefusedTurnEndsItAndTheQueueGoesOn() throws {
        let replay = Self.opened()
        _ = try replay.agent.send("First.", when: "next")
        replay.feed(["id": 4, "error": ["code": -32600, "message": "Invalid request: invented refusal"]])
        #expect(replay.fold.agent.error?.message == "Codex refused the message “First.”: Invalid request: invented refusal")
        #expect(try replay.agent.send("Second.", when: "next") == "started")
    }

    /// Messages sent before Codex opened the thread, when it refuses to: they are said lost with the stop.
    @Test func messagesWaitingForARefusedThreadAreSaidLost() throws {
        let replay = Replay.codex()
        _ = try replay.agent.send("First.", when: "next")
        _ = try replay.agent.send("Steered.", when: "now")
        replay.feed(["id": 1, "result": [:]])
        replay.feed(["id": 2, "error": ["code": -32600, "message": "Invalid request: invented refusal"]])
        #expect(replay.fold.agent.error?.message == "Codex refused to start the conversation: Invalid request: invented refusal; the 2 messages sent to it went nowhere")
        #expect(!replay.lines().contains { ["turn/start", "turn/steer"].contains($0["method"] as? String) })
    }

    /// A steer that waited for the turn's id, when Codex refuses that turn: it is said lost, never dropped unsaid.
    @Test func aSteerWaitingForARefusedTurnIsSaidLost() throws {
        let replay = Self.opened()
        _ = try replay.agent.send("First.", when: "next")
        #expect(try replay.agent.send("Steered.", when: "now") == "steered")
        replay.feed(["id": 4, "error": ["code": -32600, "message": "Invalid request: invented refusal"]])
        #expect(replay.fold.agent.error?.message == "Codex refused the message “First.”: Invalid request: invented refusal; the message steered into it went nowhere either")
        #expect(!replay.lines().contains { $0["method"] as? String == "turn/steer" })
    }
}
