import XCTest
@testable import SomethingCore

/// Messages shaped like OpenCode 2.0's ACP server (keys checked against a real run, values invented).
final class ACPStreamTests: XCTestCase {
    func fresh() -> Agent { Agent(id: "opencode-1", name: "try", harness: "opencode", folder: "/Users/example/try") }

    func testTheSessionGivesModelAndMode() {
        var agent = fresh()
        let session = ACPStream.sessionStarted(["sessionId": "s1", "configOptions": [
            ["id": "model", "name": "Model", "category": "model", "type": "select", "currentValue": "example/model-1", "options": []],
            ["id": "effort", "name": "Effort", "category": "thought_level", "type": "select", "currentValue": "default", "options": []],
            ["id": "mode", "name": "Mode", "category": "mode", "type": "select", "currentValue": "build", "options": []],
        ]], to: &agent)
        XCTAssertEqual(session, "s1")
        XCTAssertEqual(agent.model, "example/model-1")
        XCTAssertEqual(agent.mode, "build")
        XCTAssertEqual(agent.status, "idle")
    }

    func testStandardModesAndModelsAreReadToo() {
        var agent = fresh()
        _ = ACPStream.sessionStarted(["sessionId": "s1", "modes": ["currentModeId": "ask", "availableModes": []],
                                      "models": ["currentModelId": "example/model-2"]], to: &agent)
        XCTAssertEqual(agent.mode, "ask")
        XCTAssertEqual(agent.model, "example/model-2")
    }

    func chunk(_ text: String) -> [String: Any] {
        ["jsonrpc": "2.0", "method": "session/update",
         "params": ["sessionId": "s1", "update": ["sessionUpdate": "agent_message_chunk", "content": ["type": "text", "text": text]]]]
    }

    func testChunksOfATurnMakeOneMessage() {
        var agent = fresh()
        agent.messages = [Message(from: "you", text: "hello")]
        ACPStream.apply(chunk("Rea"), to: &agent)
        ACPStream.apply(["method": "session/update", "params": ["update": ["sessionUpdate": "tool_call", "title": "x"]]], to: &agent)
        ACPStream.apply(chunk("dy."), to: &agent)
        XCTAssertEqual(agent.messages, [Message(from: "you", text: "hello"), Message(from: "agent", text: "Ready.")])
    }

    let askToEdit: [String: Any] = [
        "jsonrpc": "2.0", "id": 0, "method": "session/request_permission",
        "params": ["sessionId": "s1",
                   "toolCall": ["toolCallId": "c1", "title": "hello.txt", "kind": "edit", "status": "pending", "locations": []],
                   "options": [["optionId": "once", "kind": "allow_once", "name": "Allow once"],
                               ["optionId": "always", "kind": "allow_always", "name": "Always allow"],
                               ["optionId": "reject", "kind": "reject_once", "name": "Reject"]]],
    ]

    func testAPermissionRequestMakesTheAgentWait() {
        var agent = fresh()
        ACPStream.apply(askToEdit, to: &agent)
        XCTAssertEqual(agent.status, "waiting")
        XCTAssertEqual(agent.request, PermissionRequest(id: "0", tool: "edit", about: "hello.txt", always: "always allow it"))
    }

    func testAnswersPickTheAgentsOwnOptions() {
        let options = (askToEdit["params"] as! [String: Any])["options"] as! [[String: Any]]
        XCTAssertEqual(ACPStream.option(for: .once, among: options), "once")
        XCTAssertEqual(ACPStream.option(for: .always, among: options), "always")
        XCTAssertEqual(ACPStream.option(for: .deny, among: options), "reject")
        XCTAssertNil(ACPStream.option(for: .deny, among: [["optionId": "once", "kind": "allow_once"]]),
                     "without a way to refuse, the answer is to cancel, never to allow")
    }

    func testAModeChangeIsFollowed() {
        var agent = fresh()
        ACPStream.apply(["method": "session/update", "params": ["update": ["sessionUpdate": "current_mode_update", "currentModeId": "plan"]]], to: &agent)
        XCTAssertEqual(agent.mode, "plan")
    }
}
