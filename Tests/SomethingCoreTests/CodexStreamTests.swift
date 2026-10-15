import XCTest
@testable import SomethingCore

/// Messages shaped like codex app-server 0.162's (keys checked against its schema and a real run, values invented).
final class CodexStreamTests: XCTestCase {
    func fresh() -> Agent { Agent(id: "codex-1", name: "try", harness: "codex", folder: "/Users/example/try") }

    func testTheThreadGivesModelAndMode() {
        var agent = fresh()
        let thread = CodexStream.threadStarted(["model": "example-model", "approvalPolicy": "on-request",
                                                "sandbox": ["type": "workspaceWrite"], "cwd": "/Users/example/try",
                                                "thread": ["id": "th1", "status": ["type": "idle"]]], to: &agent)
        XCTAssertEqual(thread, "th1")
        XCTAssertEqual(agent.model, "example-model")
        XCTAssertEqual(agent.mode, "on-request")
        XCTAssertEqual(agent.status, "idle")
    }

    func testAGranularPolicyIsNamedNotGuessed() {
        var agent = fresh()
        _ = CodexStream.threadStarted(["approvalPolicy": ["granular": ["rules": true]], "thread": ["id": "th1"]], to: &agent)
        XCTAssertEqual(agent.mode, "granular")
        XCTAssertNil(agent.model)
    }

    func testATurnIsRead() {
        var agent = fresh()
        for message: [String: Any] in [
            ["method": "turn/started", "params": ["threadId": "th1", "turn": ["id": "t1", "status": "inProgress"]]],
            ["method": "item/completed", "params": ["threadId": "th1", "turnId": "t1",
                                                    "item": ["type": "userMessage", "id": "i0", "content": []]]],
            ["method": "item/agentMessage/delta", "params": ["delta": "Rea"]],
            ["method": "item/completed", "params": ["threadId": "th1", "turnId": "t1",
                                                    "item": ["type": "agentMessage", "id": "i1", "text": "Ready."]]],
        ] {
            CodexStream.apply(message, to: &agent)
        }
        XCTAssertEqual(agent.status, "working")
        CodexStream.apply(["method": "turn/completed", "params": ["threadId": "th1", "turn": ["id": "t1", "status": "completed", "items": []]]], to: &agent)
        XCTAssertEqual(agent.status, "idle")
        XCTAssertEqual(agent.messages, [Message(from: "agent", text: "Ready.")])
        XCTAssertNil(agent.error)
    }

    func testAFailedTurnKeepsItsError() {
        var agent = fresh()
        CodexStream.apply(["method": "turn/completed", "params": ["turn": ["status": "failed", "error": ["message": "Example failure."]]]], to: &agent)
        XCTAssertEqual(agent.error, "Example failure.")
    }

    func testAnErrorThatWillBeRetriedIsNotShown() {
        var agent = fresh()
        CodexStream.apply(["method": "error", "params": ["willRetry": true, "error": ["message": "Example blip."]]], to: &agent)
        XCTAssertNil(agent.error)
    }

    let askToRun: [String: Any] = [
        "id": 7, "method": "item/commandExecution/requestApproval",
        "params": ["threadId": "th1", "turnId": "t1", "itemId": "i2", "startedAtMs": 1,
                   "command": "/bin/zsh -lc \"printf 'hi' > hello.txt\"", "cwd": "/Users/example/try",
                   "availableDecisions": ["accept", "acceptForSession", "decline", "cancel"]],
    ]

    func testACommandApprovalMakesTheAgentWait() {
        var agent = fresh()
        CodexStream.apply(askToRun, to: &agent)
        XCTAssertEqual(agent.status, "waiting")
        XCTAssertEqual(agent.request, PermissionRequest(id: "7", tool: "a command", about: "/bin/zsh -lc \"printf 'hi' > hello.txt\"",
                                                        always: "allow it for the rest of this conversation"))
    }

    func testNoAlwaysWhenCodexDoesNotOfferIt() {
        var agent = fresh()
        var message = askToRun
        var params = message["params"] as! [String: Any]
        params["availableDecisions"] = ["accept", "decline"]
        message["params"] = params
        CodexStream.apply(message, to: &agent)
        XCTAssertNil(agent.request?.always)
    }

    func testAResolvedRequestIsCleared() {
        var agent = fresh()
        CodexStream.apply(askToRun, to: &agent)
        CodexStream.apply(["method": "serverRequest/resolved", "params": ["threadId": "th1", "requestId": 7]], to: &agent)
        XCTAssertNil(agent.request)
    }

    func testAnswersUseCodexWords() {
        XCTAssertEqual(CodexStream.decision(.once), "accept")
        XCTAssertEqual(CodexStream.decision(.always), "acceptForSession")
        XCTAssertEqual(CodexStream.decision(.deny), "decline")
    }

    func testATurnCarriesTheText() {
        let message = CodexStream.turnStart(id: 3, thread: "th1", text: "hello")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(message))
        let input = (message["params"] as? [String: Any])?["input"] as? [[String: Any]]
        XCTAssertEqual(input?.first?["text"] as? String, "hello")
    }
}
