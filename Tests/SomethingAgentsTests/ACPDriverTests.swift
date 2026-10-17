// ACPDriver, replayed over Tests/Exchanges/opencode (Replay.swift): each file was recorded in trial T-3 against the real
// opencode acp 2.0.20 and FakeResponsesAPI's Chat Completions, with invented text. Then the cases no recording holds,
// built from the recorded shapes: a steer, an interrupt before the session exists, requests something does not handle,
// a sub-agent's text, errors in words, and OpenCode's claim read from a database made here.
import Foundation
import SQLite3
import Testing
@testable import SomethingAgents
import SomethingCore

@Suite struct OpenCodeReplayTests {
    static func methods(_ replay: Replay) -> [String] { replay.lines().compactMap { $0["method"] as? String } }

    @Test func aTurn() throws {
        let replay = try Replay.play("turn", kind: "opencode")
        #expect(replay.items.map(\.author) == ["person", "agent"])
        #expect(replay.fold.agent.thread?.hasPrefix("ses_") == true, "OpenCode names the session")
        #expect((replay.fold.agent.model, replay.fold.agent.mode, replay.fold.agent.effort) == ("fake/fake-model", "build", "default"))
        #expect(replay.fold.agent.options.mode?.map(\.value) == ["build", "plan"])
        #expect(replay.fold.agent.state == "done")
        #expect(replay.fold.agent.error == nil)
    }

    @Test func permissionOnce() throws {
        let replay = try Replay.play("permission-once", kind: "opencode")
        let tool = try #require(replay.items.first { $0.kind == "tool" })
        #expect(tool.tool == Tool(name: "shell", status: "done"))
        #expect(tool.text == "touch invented.txt")
        #expect(tool.decision == Decision(by: "person", outcome: "allowed"))
        #expect(replay.fold.turns.map(\.state) == ["done"])
        let reply = try #require(replay.lines().first { $0["result"] != nil }?["result"] as? [String: Any])
        #expect(reply["outcome"] as? [String: String] == ["outcome": "selected", "optionId": "once"], "never \"always\"")
    }

    /// OpenCode ends the turn "cancelled" by itself after a refusal: something did not cancel, so the turn is done.
    @Test func deny() throws {
        let replay = try Replay.play("deny", kind: "opencode")
        let tool = try #require(replay.items.first { $0.kind == "tool" })
        #expect(tool.tool?.status == "failed")
        #expect(tool.decision == Decision(by: "person", outcome: "denied"))
        #expect(replay.fold.turns.map(\.state) == ["done"])
        let reply = try #require(replay.lines().first { $0["result"] != nil }?["result"] as? [String: Any])
        #expect(reply["outcome"] as? [String: String] == ["outcome": "selected", "optionId": "reject"])
    }

    @Test func aQuestionIsDismissedByOpenCode() throws {
        let replay = try Replay.play("question", kind: "opencode")
        #expect(replay.fold.agent.error == AgentError(code: "AGENT_ERROR", message: ACPDriver.questionDismissed))
        #expect(replay.fold.turns.map(\.state) == ["done"])
        #expect(replay.items.first { $0.kind == "tool" }?.tool == Tool(name: "question", status: "failed"))
    }

    @Test func queuedMessagesWaitForTheAnswer() throws {
        let replay = try Replay.play("queue", kind: "opencode")
        #expect(replay.fold.turns.map(\.state) == ["done", "done", "done"])
        #expect(Self.methods(replay).filter { $0 == "session/prompt" }.count == 3)
        #expect(replay.items.filter { $0.author == "person" }.map(\.text) == ["Please run-sleep for me.", "Queued: then the docs.", "Queued: and the tests."])
        let ticks = try #require(replay.items.first { $0.author == "agent" })
        #expect(ticks.text == Array(repeating: "tick", count: 40).joined(separator: " "), "the chunks of one message make one item")
    }

    @Test func interrupt() throws {
        let replay = try Replay.play("interrupt", kind: "opencode")
        #expect(replay.fold.turns.map(\.state) == ["interrupted", "done"])
        #expect(Self.methods(replay).filter { $0 == "session/cancel" }.count == 1)
        #expect(!replay.items.contains { $0.text == "Queued: dropped." })
        #expect(replay.fold.agent.error == nil)
    }

    /// A request open at the interrupt is answered "cancelled", as ACP asks, and closes.
    @Test func withdrawn() throws {
        let replay = try Replay.play("withdrawn", kind: "opencode")
        #expect(replay.fold.turns.map(\.state) == ["interrupted"])
        #expect(replay.agent.prompt("opencode-1:0") == nil)
        let reply = try #require(replay.lines().first { $0["result"] != nil }?["result"] as? [String: Any])
        #expect(reply["outcome"] as? [String: String] == ["outcome": "cancelled"])
    }

    /// Values are read back from OpenCode's answers; a model it does not offer is said, and the old one stays.
    @Test func set() throws {
        let replay = try Replay.play("set", kind: "opencode")
        let agent = replay.fold.agent
        #expect((agent.model, agent.mode, agent.effort) == ("fake/other-model", "plan", "high"))
        #expect(agent.error?.code == "VALUE_NOT_OFFERED")
        let keys = replay.lines().compactMap { ($0["params"] as? [String: Any])?["configId"] as? String }
        #expect(keys == ["mode", "model", "effort", "model"], "the mode first, the effort after the model")
    }

    @Test func aLaunchSetsItsModelBeforeTheFirstMessage() throws {
        let replay = try Replay.play("launch-model", kind: "opencode")
        #expect(Self.methods(replay) == ["initialize", "session/new", "session/set_config_option", "session/prompt"])
        #expect(replay.fold.agent.model == "fake/other-model")
    }

    @Test func resume() throws {
        let replay = try Replay.play("resume", kind: "opencode")
        let resume = try #require(replay.lines().first { $0["method"] as? String == "session/resume" }?["params"] as? [String: Any])
        #expect(replay.fold.agent.thread == resume["sessionId"] as? String)
        #expect(resume["cwd"] as? String == "/Users/example/shop")
        #expect(replay.fold.turns.map(\.state) == ["done"])
    }

    @Test func aMissingConversation() throws {
        let replay = try Replay.play("resume-missing", kind: "opencode")
        #expect(replay.quit, "the program is told to end")
        #expect(replay.fold.agent.error?.code == "THREAD_NOT_FOUND")
        #expect(replay.fold.agent.alive == false)
    }

    @Test func killed() throws {
        let replay = try Replay.play("killed", kind: "opencode")
        #expect(replay.fold.agent.state == "error")
        #expect(replay.fold.agent.error == AgentError(code: "AGENT_ERROR", message: "OpenCode ended (code 137)."))
    }

    /// The ladder's first step cancels the running turn; the input is closed after its answer.
    @Test func stop() throws {
        let replay = try Replay.play("stop", kind: "opencode")
        #expect(replay.agent.driver.goodbye == nil)
        #expect(Self.methods(replay).last == "session/cancel")
        #expect(replay.fold.agent.state == "interrupted")
        #expect(replay.fold.agent.error == nil)
    }
}

@Suite struct ACPDriverTests {
    static let session = "ses_invented0000000000000001"

    /// A replay whose session is open: initialize and session/new answered as the recordings show.
    static func opened(model: String? = nil) -> Replay {
        let replay = Replay.opencode(model: model)
        replay.feed(["jsonrpc": "2.0", "id": 1, "result": ["protocolVersion": 1, "agentInfo": ["name": "OpenCode", "version": "2.0.20"]]])
        replay.feed(["jsonrpc": "2.0", "id": 2, "result": ["sessionId": session, "configOptions": [
            ["id": "model", "category": "model", "currentValue": "fake/fake-model", "options": [["value": "fake/fake-model", "name": "fake/Fake Model"]]],
            ["id": "mode", "category": "mode", "currentValue": "build", "options": [["value": "build", "name": "Build"], ["value": "plan", "name": "Plan"]]],
        ]]])
        return replay
    }

    static func update(_ update: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "method": "session/update", "params": ["sessionId": session, "update": update]]
    }

    @Test func theCommandIsACP() {
        #expect(ACPDriver.command(Launch(agent: "opencode-1", folder: "/Users/example/shop")) == Command(arguments: ["acp"]))
        #expect(Replay.opencode().fold.agent.thread == nil, "the session is unknown until OpenCode names it")
        #expect(Replay.opencode().fold.agent.can.steer == false)
        #expect(Replay.opencode().fold.agent.because["steer"] == ACPDriver.limits["steer"])
    }

    @Test func aSteerIsRefused() throws {
        let replay = Self.opened()
        #expect(try replay.agent.send("Hello.", when: "next") == "started")
        let written = replay.written.count
        #expect(throws: CodedError("NOT_SUPPORTED", ACPDriver.limits["steer"]!)) { try replay.agent.send("Now.", when: "now") }
        #expect(replay.written.count == written, "nothing reaches OpenCode, which would refuse a second prompt")
    }

    /// A message sent before the session exists waits for it; interrupted then, it is dropped and its turn ends.
    @Test func anEarlyMessageWaitsAndCanBeDropped() throws {
        let replay = Replay.opencode()
        #expect(try replay.agent.send("Hello.", when: "next") == "started")
        #expect(ACPDriverTests.methodsWritten(replay) == ["initialize"])
        #expect(try replay.agent.interrupt())
        #expect(replay.fold.turns.map(\.state) == ["interrupted"])
        replay.feed(["jsonrpc": "2.0", "id": 1, "result": ["protocolVersion": 1]])
        replay.feed(["jsonrpc": "2.0", "id": 2, "result": ["sessionId": Self.session, "configOptions": []]])
        #expect(ACPDriverTests.methodsWritten(replay) == ["initialize", "session/new"], "the dropped message never goes out")
    }

    static func methodsWritten(_ replay: Replay) -> [String] { replay.lines().compactMap { $0["method"] as? String } }

    /// OpenCode waits for every request it sends: one something does not handle gets an error at once.
    @Test func otherRequestsAreRefused() {
        let replay = Self.opened()
        replay.feed(["jsonrpc": "2.0", "id": 7, "method": "fs/read_text_file", "params": ["sessionId": Self.session, "path": "/Users/example/shop/a.txt"]])
        let reply = replay.lines().last
        #expect(reply?["id"] as? Int == 7)
        #expect((reply?["error"] as? [String: Any])?["code"] as? Int == -32601)
        #expect(replay.fold.requests.isEmpty)
    }

    /// A sub-agent's updates come in its parent's stream: they are shown as the sub-agent's, not glued to the reply.
    @Test func aSubAgentsTextIsItsOwn() throws {
        let replay = Self.opened()
        _ = try replay.agent.send("Hello.", when: "next")
        let child: [String: Any] = ["opencode/child-session": ["id": "ses_child", "parentID": Self.session, "depth": 1]]
        replay.feed(Self.update(["sessionUpdate": "agent_message_chunk", "messageId": "m1", "content": ["type": "text", "text": "Main "]]))
        replay.feed(Self.update(["sessionUpdate": "agent_message_chunk", "messageId": "c1", "content": ["type": "text", "text": "Child."], "_meta": child]))
        replay.feed(Self.update(["sessionUpdate": "agent_message_chunk", "messageId": "m1", "content": ["type": "text", "text": "reply."]]))
        replay.feed(Self.update(["sessionUpdate": "agent_thought_chunk", "messageId": "m1:reasoning:0", "content": ["type": "text", "text": "Invented thought."]]))
        #expect(replay.items.map(\.kind) == ["message", "message", "subagent", "thought"])
        #expect(replay.items.map(\.text) == ["Hello.", "Main reply.", "Child.", "Invented thought."])
    }

    /// From 2.0.25 OpenCode says when its options change by themselves.
    @Test func aConfigUpdateIsRead() {
        let replay = Self.opened()
        replay.feed(Self.update(["sessionUpdate": "config_option_update", "configOptions": [
            ["id": "mode", "category": "mode", "currentValue": "plan", "options": [["value": "plan", "name": "Plan"]]]]]))
        #expect(replay.fold.agent.mode == "plan")
    }

    @Test func failedTurnsAreSaidInWords() throws {
        let replay = Self.opened()
        _ = try replay.agent.send("Hello.", when: "next")
        replay.feed(["jsonrpc": "2.0", "id": 3, "error": ["code": -32000, "message": "provider authentication required"]])
        #expect(replay.fold.turns.map(\.state) == ["error"])
        #expect(replay.fold.agent.error?.message.contains("opencode auth login") == true)
        _ = try replay.agent.send("Again.", when: "next")
        replay.feed(["jsonrpc": "2.0", "id": 4, "result": ["stopReason": "max_tokens"]])
        #expect(replay.fold.turns.map(\.state) == ["error", "error"])
        #expect(ACPDriver.words(["message": "Internal error: Internal service failure"]) == "Internal service failure")
    }

    @Test func aRefusedLaunchEndsTheAgent() {
        let replay = Replay.opencode()
        replay.feed(["jsonrpc": "2.0", "id": 1, "result": ["protocolVersion": 1]])
        replay.feed(["jsonrpc": "2.0", "id": 2, "error": ["code": -32603, "message": "Internal error: Internal service failure"]])
        #expect(replay.quit)
        #expect(replay.fold.agent.alive == false)
        #expect(replay.fold.agent.error?.message.hasPrefix("OpenCode refused to start the conversation: Internal service failure.") == true)
    }

    @Test func theDatabaseFollowsTheEnvironment() {
        #expect(ACPDriver.database(["HOME": "/Users/example"]) == "/Users/example/.local/share/opencode/opencode.db")
        #expect(ACPDriver.database(["HOME": "/Users/example", "XDG_DATA_HOME": "/Users/example/data"]) == "/Users/example/data/opencode/opencode.db")
        #expect(ACPDriver.database(["HOME": "/Users/example", "OPENCODE_DB": "/Users/example/other.db"]) == "/Users/example/other.db")
        #expect(ACPDriver.database([:]) == nil)
    }

    /// The claim is read from session_v2.time_suspended, the column OpenCode 2.0.20 sets while a run holds the session.
    @Test func aClaimLeftIsSaid() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("acp-claim-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("opencode.db").path
        var db: OpaquePointer?
        #expect(sqlite3_open(path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, """
            CREATE TABLE session_v2 (id TEXT PRIMARY KEY, time_suspended INTEGER, idle_outcome TEXT);
            INSERT INTO session_v2 VALUES ('\(Self.session)', 1792272961952, NULL), ('ses_released', NULL, 'interrupted');
            """, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        #expect(ACPDriver.claimed(Self.session, in: path) == true)
        #expect(ACPDriver.claimed("ses_released", in: path) == false)
        #expect(ACPDriver.claimed("ses_unknown", in: path) == nil)
        #expect(ACPDriver.claimed(Self.session, in: folder.appendingPathComponent("missing.db").path) == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("missing.db").path), "never created")

        let replay = Self.opened()
        let driver = try #require(replay.agent.driver as? ACPDriver)
        driver.database = path
        replay.agent.ended(code: 0, errors: "", asked: true)
        driver.checkClaim()
        #expect(replay.fold.agent.error == AgentError(code: "AGENT_ERROR", message: ACPDriver.claimLeft(Self.session)))
    }
}
