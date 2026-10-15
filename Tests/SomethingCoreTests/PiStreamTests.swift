import XCTest
@testable import SomethingCore

/// Events shaped like pi 1.0's RPC mode (keys checked against a real run, values invented).
final class PiStreamTests: XCTestCase {
    func fresh() -> Agent { Agent(id: "pi-1", name: "try", harness: "pi", folder: "/Users/example/try") }

    func testTheStateGivesTheModel() {
        var agent = fresh()
        PiStream.apply(["type": "response", "command": "get_state", "success": true,
                        "data": ["model": ["id": "model-1", "provider": "example"], "thinkingLevel": "high",
                                 "isStreaming": false, "sessionId": "s1"]], to: &agent)
        XCTAssertEqual(agent.model, "example/model-1")
        XCTAssertEqual(agent.status, "idle")
        XCTAssertNil(agent.mode, "pi has no permission mode")
    }

    func testATurnIsRead() {
        var agent = fresh()
        for event: [String: Any] in [
            ["type": "agent_start"],
            ["type": "message_end", "message": ["role": "system", "content": "…"]],
            ["type": "message_end", "message": ["role": "user", "content": [["type": "text", "text": "hello"]]]],
            ["type": "message_end", "message": ["role": "assistant", "provider": "example", "model": "model-1",
                                                "stopReason": "stop", "content": [["type": "thinking", "thinking": "…"],
                                                                                  ["type": "text", "text": "Ready."]]]],
            ["type": "agent_end", "messages": []],
        ] {
            PiStream.apply(event, to: &agent)
        }
        XCTAssertEqual(agent.status, "working", "agent_end is not the end: more may be queued")
        PiStream.apply(["type": "agent_settled"], to: &agent)
        XCTAssertEqual(agent.status, "idle")
        XCTAssertEqual(agent.messages, [Message(from: "agent", text: "Ready.")])
        XCTAssertEqual(agent.model, "example/model-1")
    }

    func testAnErrorMessageIsAnError() {
        var agent = fresh()
        PiStream.apply(["type": "message_end", "message": ["role": "assistant", "stopReason": "error",
                                                           "errorMessage": "Example failure.", "content": []]], to: &agent)
        XCTAssertEqual(agent.error, "Example failure.")
        XCTAssertTrue(agent.messages.isEmpty)
    }

    func testARefusedCommandIsAnError() {
        var agent = fresh()
        agent.status = "working"
        PiStream.apply(["type": "response", "command": "prompt", "success": false, "error": "Example refusal."], to: &agent)
        XCTAssertEqual(agent.error, "Example refusal.")
        XCTAssertEqual(agent.status, "idle")
    }

    func testAMessageWhileWorkingIsAFollowUp() {
        XCTAssertEqual(PiStream.messageCommand("hi", whileWorking: false)["type"] as? String, "prompt")
        XCTAssertEqual(PiStream.messageCommand("hi", whileWorking: true)["type"] as? String, "follow_up")
    }
}
