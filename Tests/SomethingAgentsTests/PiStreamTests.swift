import Foundation
import Testing
@testable import SomethingAgents
import SomethingCore

/// Events shaped like pi 1.0's RPC mode (keys checked against a real run, values invented).
struct PiStreamTests {
    func fresh() -> V1Agent { V1Agent(id: "pi-1", name: "try", harness: "pi", folder: "/Users/example/try") }

    @Test func testTheStateGivesTheModel() {
        var agent = fresh()
        PiStream.apply(["type": "response", "command": "get_state", "success": true,
                        "data": ["model": ["id": "model-1", "provider": "example"], "thinkingLevel": "high",
                                 "isStreaming": false, "sessionId": "s1"]], to: &agent)
        #expect(agent.model == "example/model-1")
        #expect(agent.status == "idle")
        #expect(agent.mode == nil, "pi has no permission mode")
    }

    @Test func testATurnIsRead() {
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
        #expect(agent.status == "working", "agent_end is not the end: more may be queued")
        PiStream.apply(["type": "agent_settled"], to: &agent)
        #expect(agent.status == "idle")
        #expect(agent.messages == [Message(from: "agent", text: "Ready.")])
        #expect(agent.model == "example/model-1")
    }

    @Test func testAnErrorMessageIsAnError() {
        var agent = fresh()
        PiStream.apply(["type": "message_end", "message": ["role": "assistant", "stopReason": "error",
                                                           "errorMessage": "Example failure.", "content": []]], to: &agent)
        #expect(agent.error == "Example failure.")
        #expect(agent.messages.isEmpty)
    }

    @Test func testARefusedCommandIsAnError() {
        var agent = fresh()
        agent.status = "working"
        PiStream.apply(["type": "response", "command": "prompt", "success": false, "error": "Example refusal."], to: &agent)
        #expect(agent.error == "Example refusal.")
        #expect(agent.status == "idle")
    }

    @Test func testAMessageWhileWorkingIsAFollowUp() {
        #expect(PiStream.messageCommand("hi", whileWorking: false)["type"] as? String == "prompt")
        #expect(PiStream.messageCommand("hi", whileWorking: true)["type"] as? String == "follow_up")
    }
}
