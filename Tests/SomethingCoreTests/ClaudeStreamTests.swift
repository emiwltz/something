import XCTest
@testable import SomethingCore

/// Events shaped like Claude Code 2.1's stream-json output (keys checked against a real run, text invented).
final class ClaudeStreamTests: XCTestCase {
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

    func testATurnIsRead() {
        var agent = fresh()
        XCTAssertNil(agent.model)
        XCTAssertNil(agent.status)
        for event in events() { ClaudeStream.apply(event, to: &agent) }
        XCTAssertEqual(agent.model, "claude-example-1")
        XCTAssertEqual(agent.mode, "default")
        XCTAssertEqual(agent.status, "idle")
        XCTAssertEqual(agent.messages, [Message(from: "agent", text: "Ready.")])
        XCTAssertNil(agent.error)
    }

    func testUnknownEventsChangeNothing() {
        var agent = fresh()
        ClaudeStream.apply(["type": "something_new", "model": "nope"], to: &agent)
        XCTAssertEqual(agent, fresh())
    }

    func testAnErrorResultIsKept() {
        var agent = fresh()
        ClaudeStream.apply(["type": "result", "subtype": "error_during_execution", "is_error": true,
                            "result": "Example failure."], to: &agent)
        XCTAssertEqual(agent.error, "Example failure.")
    }

    func testASyntheticMessageIsAnErrorNotAReply() {
        var agent = fresh()
        ClaudeStream.apply(events()[1], to: &agent)
        ClaudeStream.apply(["type": "assistant", "session_id": "s1",
                            "message": ["model": "<synthetic>", "role": "assistant",
                                        "content": [["type": "text", "text": "Example: this key was refused."]]]],
                           to: &agent)
        XCTAssertEqual(agent.error, "Example: this key was refused.")
        XCTAssertTrue(agent.messages.isEmpty)
        XCTAssertEqual(agent.model, "claude-example-1", "the synthetic model is not the agent's model")
    }

    func testClaudeIsLaunchedWithoutInheritedAPICredentials() {
        let inherited = ["PATH": "/usr/bin", "HOME": "/Users/example",
                         "ANTHROPIC_API_KEY": "example-not-a-key", "ANTHROPIC_AUTH_TOKEN": "example-not-a-token",
                         "ANTHROPIC_MODEL": "claude-example-1"]
        let env = inherited.filter { !ClaudeSession.credentials.contains($0.key) }
        XCTAssertNil(env["ANTHROPIC_API_KEY"])
        XCTAssertNil(env["ANTHROPIC_AUTH_TOKEN"])
        XCTAssertEqual(env["PATH"], "/usr/bin")
        XCTAssertEqual(env["ANTHROPIC_MODEL"], "claude-example-1", "other settings are the person's and stay")
    }

    /// A permission request shaped like Claude Code 2.1's (keys checked against a real run, values invented).
    let askToWrite: [String: Any] = [
        "type": "control_request", "request_id": "r1",
        "request": ["subtype": "can_use_tool", "tool_name": "Write", "display_name": "Write",
                    "input": ["file_path": "/Users/example/try/hello.txt", "content": "hi\n"],
                    "description": "hello.txt", "tool_use_id": "t1",
                    "permission_suggestions": [["type": "setMode", "mode": "acceptEdits", "destination": "session"]]],
    ]

    func testAPermissionRequestMakesTheAgentWait() {
        var agent = fresh()
        ClaudeStream.apply(askToWrite, to: &agent)
        XCTAssertEqual(agent.status, "waiting")
        XCTAssertEqual(agent.request, PermissionRequest(id: "r1", tool: "Write", about: "hello.txt",
                                                        always: "switch to mode \"acceptEdits\" for this conversation"))
    }

    func testAWithdrawnRequestIsCleared() {
        var agent = fresh()
        ClaudeStream.apply(askToWrite, to: &agent)
        ClaudeStream.apply(["type": "control_cancel_request", "request_id": "r1"], to: &agent)
        XCTAssertNil(agent.request)
        XCTAssertEqual(agent.status, "working")
    }

    func testOtherControlRequestsAreNotPermissions() {
        var agent = fresh()
        ClaudeStream.apply(["type": "control_request", "request_id": "r2", "request": ["subtype": "hook_callback"]], to: &agent)
        XCTAssertNil(agent.request)
    }

    func answer(_ answer: PermissionAnswer) throws -> [String: Any] {
        let line = ClaudeStream.permissionLine(id: "r1", request: askToWrite["request"] as! [String: Any], answer: answer)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(line))
        XCTAssertEqual(line["type"] as? String, "control_response")
        let outer = try XCTUnwrap(line["response"] as? [String: Any])
        XCTAssertEqual(outer["request_id"] as? String, "r1")
        return try XCTUnwrap(outer["response"] as? [String: Any])
    }

    func testAllowingOncePassesTheInputBackUnchanged() throws {
        let response = try answer(.once)
        XCTAssertEqual(response["behavior"] as? String, "allow")
        XCTAssertEqual((response["updatedInput"] as? [String: Any])?["content"] as? String, "hi\n")
        XCTAssertNil(response["updatedPermissions"])
    }

    func testAlwaysPassesClaudesOwnSuggestionBack() throws {
        let response = try answer(.always)
        let permissions = try XCTUnwrap(response["updatedPermissions"] as? [[String: Any]])
        XCTAssertEqual(permissions.first?["mode"] as? String, "acceptEdits")
    }

    func testDenyingSaysWhoRefused() throws {
        let response = try answer(.deny)
        XCTAssertEqual(response["behavior"] as? String, "deny")
        XCTAssertNotNil(response["message"] as? String)
        XCTAssertNil(response["updatedInput"])
    }

    func testTheUserLineCarriesTheText() throws {
        let line = ClaudeStream.userLine("hello")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(line))
        XCTAssertEqual(line["type"] as? String, "user")
        XCTAssertEqual((line["message"] as? [String: Any])?["content"] as? String, "hello")
    }
}
