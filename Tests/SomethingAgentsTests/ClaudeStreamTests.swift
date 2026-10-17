import Foundation
import Testing
@testable import SomethingAgents
import SomethingCore

/// Events shaped like Claude Code 2.1's stream-json output (keys checked against a real run, text invented).
struct ClaudeStreamTests {
    func events() -> [[String: Any]] {
        [
            ["type": "system", "subtype": "hook_started", "session_id": "s1"],
            ["type": "system", "subtype": "init", "cwd": "/Users/example/try", "session_id": "s1",
             "model": "claude-example-1", "permissionMode": "default", "tools": ["Read"]],
            ["type": "assistant", "session_id": "s1", "parent_tool_use_id": NSNull(),
             "message": ["model": "claude-example-1", "role": "assistant",
                         "content": [["type": "thinking", "thinking": "…"], ["type": "text", "text": "Ready."]]]],
            ["type": "rate_limit_event", "session_id": "s1"],
            ["type": "result", "subtype": "success", "is_error": false, "result": "Ready.", "session_id": "s1"],
        ]
    }

    func fresh() -> Agent { Agent(id: "claude-1", name: "try", harness: "claude", folder: "/Users/example/try") }

    @Test func testATurnIsRead() {
        var agent = fresh()
        #expect(agent.model == nil)
        #expect(agent.status == nil)
        for event in events() { ClaudeStream.apply(event, to: &agent) }
        #expect(agent.model == "claude-example-1")
        #expect(agent.mode == "default")
        #expect(agent.status == "idle")
        #expect(agent.messages == [Message(from: "agent", text: "Ready.")])
        #expect(agent.error == nil)
    }

    @Test func testUnknownEventsChangeNothing() {
        var agent = fresh()
        ClaudeStream.apply(["type": "something_new", "model": "nope"], to: &agent)
        #expect(agent == fresh())
    }

    @Test func testAnErrorResultIsKept() {
        var agent = fresh()
        ClaudeStream.apply(["type": "result", "subtype": "error_during_execution", "is_error": true,
                            "result": "Example failure."], to: &agent)
        #expect(agent.error == "Example failure.")
    }

    @Test func testASyntheticMessageIsAnErrorNotAReply() {
        var agent = fresh()
        ClaudeStream.apply(events()[1], to: &agent)
        ClaudeStream.apply(["type": "assistant", "session_id": "s1",
                            "message": ["model": "<synthetic>", "role": "assistant",
                                        "content": [["type": "text", "text": "Example: this key was refused."]]]],
                           to: &agent)
        #expect(agent.error == "Example: this key was refused.")
        #expect(agent.messages.isEmpty)
        #expect(agent.model == "claude-example-1", "the synthetic model is not the agent's model")
    }

    @Test func testClaudeIsLaunchedWithoutInheritedAPICredentials() {
        let inherited = ["PATH": "/usr/bin", "HOME": "/Users/example",
                         "ANTHROPIC_API_KEY": "example-not-a-key", "ANTHROPIC_AUTH_TOKEN": "example-not-a-token",
                         "ANTHROPIC_MODEL": "claude-example-1"]
        let env = inherited.filter { !ClaudeSession.credentials.contains($0.key) }
        #expect(env["ANTHROPIC_API_KEY"] == nil)
        #expect(env["ANTHROPIC_AUTH_TOKEN"] == nil)
        #expect(env["PATH"] == "/usr/bin")
        #expect(env["ANTHROPIC_MODEL"] == "claude-example-1", "other settings are the person's and stay")
    }

    /// A permission request shaped like Claude Code 2.1's (keys checked against a real run, values invented).
    let askToWrite: [String: Any] = [
        "type": "control_request", "request_id": "r1",
        "request": ["subtype": "can_use_tool", "tool_name": "Write", "display_name": "Write",
                    "input": ["file_path": "/Users/example/try/hello.txt", "content": "hi\n"],
                    "description": "hello.txt", "tool_use_id": "t1",
                    "permission_suggestions": [["type": "setMode", "mode": "acceptEdits", "destination": "session"]]],
    ]

    @Test func testAPermissionRequestMakesTheAgentWait() {
        var agent = fresh()
        ClaudeStream.apply(askToWrite, to: &agent)
        #expect(agent.status == "waiting")
        #expect(agent.request == PermissionRequest(id: "r1", tool: "Write", about: "hello.txt"))
    }

    @Test func testAWithdrawnRequestIsCleared() {
        var agent = fresh()
        ClaudeStream.apply(askToWrite, to: &agent)
        ClaudeStream.apply(["type": "control_cancel_request", "request_id": "r1"], to: &agent)
        #expect(agent.request == nil)
        #expect(agent.status == "working")
    }

    @Test func testOtherControlRequestsAreNotPermissions() {
        var agent = fresh()
        ClaudeStream.apply(["type": "control_request", "request_id": "r2", "request": ["subtype": "hook_callback"]], to: &agent)
        #expect(agent.request == nil)
    }

    func answer(_ answer: PermissionAnswer) throws -> [String: Any] {
        let line = ClaudeStream.permissionLine(id: "r1", request: askToWrite["request"] as! [String: Any], answer: answer)
        #expect(JSONSerialization.isValidJSONObject(line))
        #expect(line["type"] as? String == "control_response")
        let outer = try #require(line["response"] as? [String: Any])
        #expect(outer["request_id"] as? String == "r1")
        return try #require(outer["response"] as? [String: Any])
    }

    @Test func testAllowingOncePassesTheInputBackUnchanged() throws {
        let response = try answer(.once)
        #expect(response["behavior"] as? String == "allow")
        #expect((response["updatedInput"] as? [String: Any])?["content"] as? String == "hi\n")
        #expect(response["updatedPermissions"] == nil)
    }

    @Test func testDenyingSaysWhoRefused() throws {
        let response = try answer(.deny)
        #expect(response["behavior"] as? String == "deny")
        #expect(response["message"] as? String != nil)
        #expect(response["updatedInput"] == nil)
    }

    @Test func testTheUserLineCarriesTheText() throws {
        let line = ClaudeStream.userLine("hello")
        #expect(JSONSerialization.isValidJSONObject(line))
        #expect(line["type"] as? String == "user")
        #expect((line["message"] as? [String: Any])?["content"] as? String == "hello")
    }
}
