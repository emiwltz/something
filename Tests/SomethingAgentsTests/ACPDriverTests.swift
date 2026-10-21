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

    /// OpenCode ends the turn "cancelled" by itself after a refusal: something did not cancel, and the turn did not
    /// end as a normal one, so it fails with what happened.
    @Test func deny() throws {
        let replay = try Replay.play("deny", kind: "opencode")
        let tool = try #require(replay.items.first { $0.kind == "tool" })
        #expect(tool.tool?.status == "failed")
        #expect(tool.decision == Decision(by: "person", outcome: "denied"))
        #expect(replay.fold.turns.map(\.state) == ["error"])
        #expect(replay.fold.agent.error == AgentError(code: "AGENT_ERROR", message:
            "OpenCode stopped its turn because its request “touch invented.txt” was refused. Tell it what to do instead in a new message."))
        let reply = try #require(replay.lines().first { $0["result"] != nil }?["result"] as? [String: Any])
        #expect(reply["outcome"] as? [String: String] == ["outcome": "selected", "optionId": "reject"])
    }

    @Test func aQuestionIsDismissedByOpenCode() throws {
        let replay = try Replay.play("question", kind: "opencode")
        #expect(replay.fold.agent.error == AgentError(code: "AGENT_ERROR", message: ACPDriver.questionDismissed))
        #expect(replay.fold.turns.map(\.state) == ["error"], "the turn OpenCode cancelled after it is no normal end")
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

    /// Killed during a turn, OpenCode leaves its claim (T-3): the end and the claim are said in one error.
    @Test func killed() throws {
        let folder = try ACPDriverTests.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = "ses_eb42d0ee4ffeck9Fs9cn1jngw7"
        let replay = try Replay.play("killed", kind: "opencode", database: try ACPDriverTests.database(claimed: session, in: folder))
        #expect(replay.fold.agent.state == "error")
        #expect(replay.fold.agent.error == AgentError(code: "AGENT_ERROR", message: "OpenCode ended (code 137). " + ACPDriver.claimLeft(session)))
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
        replay.feed(["jsonrpc": "2.0", "id": 3, "error": ["code": -32000, "message": "Authentication required: provider authentication required"]])
        #expect(replay.fold.turns.map(\.state) == ["error"])
        #expect(replay.fold.agent.error?.message == "OpenCode's model fake/fake-model needs a sign-in to fake, which OpenCode does not have. "
            + "Sign in to fake in OpenCode (`opencode auth login` in a terminal) and send the message again. Or use another model once in OpenCode "
            + "and start a new conversation: something takes the model you used last there.")
        #expect(ACPDriver.failure(["code": -32000], "Authentication required", "Hello.", model: nil, picked: false)
            == "OpenCode's model needs a sign-in to its provider, which OpenCode does not have. Sign in to its provider in OpenCode (`opencode auth login` in a terminal) and send the message again.",
            "a model a space named stays: choosing another in OpenCode would change nothing")
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

    /// OpenCode's model.json, as its terminal app writes it (invented models): the most recent first.
    static let modelFile = #"{"recent": [{"providerID": "fake", "modelID": "other-model"}, {"providerID": "fake", "modelID": "fake-model"}], "favorite": [], "variant": {}}"#

    @Test func theRecentModelIsReadFromOpenCodesStateFile() throws {
        let home = try Self.folder()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(ACPDriver.recentModel(["HOME": home.path]) == nil, "no file")
        let state = home.appendingPathComponent(".local/state/opencode")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        for garbage in ["not json", "[]", #"{"recent": []}"#, #"{"recent": [{"providerID": "fake"}]}"#, #"{"recent": [{"providerID": "", "modelID": "m"}]}"#] {
            try garbage.write(to: state.appendingPathComponent("model.json"), atomically: true, encoding: .utf8)
            #expect(ACPDriver.recentModel(["HOME": home.path]) == nil, "\(garbage)")
        }
        try Self.modelFile.write(to: state.appendingPathComponent("model.json"), atomically: true, encoding: .utf8)
        #expect(ACPDriver.recentModel(["HOME": home.path]) == "fake/other-model")
        #expect(ACPDriver.recentModel(["HOME": "/Users/example", "XDG_STATE_HOME": home.appendingPathComponent(".local/state").path]) == "fake/other-model")
        #expect(ACPDriver.recentModel([:]) == nil)
    }

    /// A new conversation that names no model takes OpenCode's own last model before the first message, when OpenCode
    /// offers it; a model the launch names, a resumed conversation and a model not offered keep today's way.
    @Test func aNewConversationTakesTheRecentModel() throws {
        func opened(_ replay: Replay, recent: String?) throws -> [[String: Any]] {
            try #require(replay.agent.driver as? ACPDriver).recent = recent
            replay.feed(["jsonrpc": "2.0", "id": 1, "result": ["protocolVersion": 1]])
            replay.feed(["jsonrpc": "2.0", "id": 2, "result": ["sessionId": Self.session, "configOptions": [
                ["id": "model", "category": "model", "currentValue": "fake/fake-model", "options": [
                    ["value": "fake/fake-model", "name": "fake/Fake Model"], ["value": "fake/other-model", "name": "fake/Other Model"]]]]]])
            _ = try replay.agent.send("Hello.", when: "next")
            return replay.lines().filter { $0["method"] as? String == "session/set_config_option" || $0["method"] as? String == "session/prompt" }
        }
        let taken = try opened(Replay.opencode(), recent: "fake/other-model")
        #expect(taken.count == 1 && (taken[0]["params"] as? [String: Any])?["value"] as? String == "fake/other-model", "the prompt waits for the model")
        #expect(try opened(Replay.opencode(), recent: "fake/gone-model").map { $0["method"] as? String } == ["session/prompt"])
        #expect(try opened(Replay.opencode(), recent: "fake/fake-model").map { $0["method"] as? String } == ["session/prompt"], "already in use")
        #expect(try opened(Replay.opencode(), recent: nil).map { $0["method"] as? String } == ["session/prompt"])
        let named = try opened(Replay.opencode(model: "fake/fake-model"), recent: "fake/other-model")
        #expect(named.compactMap { ($0["params"] as? [String: Any])?["value"] as? String } == ["fake/fake-model"], "the model asked for wins")
        let replay = Replay.opencode()
        _ = try replay.agent.driver.set(model: "fake/fake-model", mode: nil, effort: "high")
        _ = try opened(replay, recent: "fake/other-model")
        replay.feed(["jsonrpc": "2.0", "id": 3, "result": ["configOptions": [["id": "model", "category": "model", "currentValue": "fake/fake-model"]]]])
        let set = replay.lines().filter { $0["method"] as? String == "session/set_config_option" }
        #expect(set.compactMap { ($0["params"] as? [String: Any])?["value"] as? String } == ["fake/fake-model", "high"], "a model set before the session wins")
        let resumed = try opened(Replay.opencode(resume: Self.session), recent: "fake/other-model")
        #expect(resumed.map { $0["method"] as? String } == ["session/prompt"], "a resumed conversation keeps its model")
    }

    static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("acp-claim-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// An OpenCode database in `folder` where `claimed` is marked as running and ses_released is not.
    static func database(claimed: String, in folder: URL) throws -> String {
        let path = folder.appendingPathComponent("opencode.db").path
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        try #require(sqlite3_open(path, &db) == SQLITE_OK)
        try #require(sqlite3_exec(db, """
            CREATE TABLE session_v2 (id TEXT PRIMARY KEY, time_suspended INTEGER, idle_outcome TEXT);
            INSERT INTO session_v2 VALUES ('\(claimed)', 1792272961952, NULL), ('ses_released', NULL, 'interrupted');
            """, nil, nil, nil) == SQLITE_OK)
        return path
    }

    /// The claim is read from session_v2.time_suspended, the column OpenCode 2.0.20 sets while a run holds the session.
    @Test func theClaimIsRead() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try Self.database(claimed: Self.session, in: folder)
        #expect(ACPDriver.claimed(Self.session, in: path) == true)
        #expect(ACPDriver.claimed("ses_released", in: path) == false)
        #expect(ACPDriver.claimed("ses_unknown", in: path) == nil)
        #expect(ACPDriver.claimed(Self.session, in: folder.appendingPathComponent("missing.db").path) == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("missing.db").path), "never created")
    }

    /// Only a turn of something's still open at the end makes the claim something's to say; a claim found otherwise
    /// (an earlier crash, the person's own OpenCode) is left unsaid.
    @Test func aClaimLeftIsSaidOnlyAfterAnOpenTurn() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try Self.database(claimed: Self.session, in: folder)
        func replay(prompting: Bool) throws -> Replay {
            let replay = Self.opened()
            try #require(replay.agent.driver as? ACPDriver).database = path
            if prompting { _ = try replay.agent.send("Hello.", when: "next") }
            return replay
        }

        let idle = try replay(prompting: false)
        idle.agent.ended(code: 0, errors: "", asked: true)
        #expect(idle.fold.agent.error == nil)
        let crashed = try replay(prompting: false)
        crashed.agent.ended(code: 1, errors: "", asked: false)
        #expect(crashed.fold.agent.error == AgentError(code: "AGENT_ERROR", message: "OpenCode ended (code 1)."))

        let stopped = try replay(prompting: true)
        stopped.agent.ended(code: 0, errors: "", asked: true)
        #expect(stopped.fold.agent.error == AgentError(code: "AGENT_ERROR", message: ACPDriver.claimLeft(Self.session)))
        let killed = try replay(prompting: true)
        killed.agent.ended(code: 137, errors: "", asked: false)
        #expect(killed.fold.agent.error == AgentError(code: "AGENT_ERROR", message: "OpenCode ended (code 137). " + ACPDriver.claimLeft(Self.session)))
    }

    /// A complete list without an effort (a model without variants) leaves no effort in use, not the last one.
    @Test func anEffortNoLongerOfferedIsNone() throws {
        let replay = Self.opened()
        let model: [String: Any] = ["id": "model", "category": "model", "currentValue": "fake/fake-model",
                                    "options": [["value": "fake/fake-model", "name": "fake/Fake Model"], ["value": "fake/other-model", "name": "fake/Other Model"]]]
        replay.feed(Self.update(["sessionUpdate": "config_option_update", "configOptions": [model,
            ["id": "effort", "category": "thought_level", "currentValue": "high", "options": [["value": "high", "name": "High"]]]]]))
        #expect(replay.fold.agent.effort == "high")
        #expect(try replay.agent.driver.set(model: "fake/other-model", mode: nil, effort: nil) == "now")
        var other = model
        other["currentValue"] = "fake/other-model"
        replay.feed(["jsonrpc": "2.0", "id": 3, "result": ["configOptions": [other]]])
        #expect(replay.fold.agent.model == "fake/other-model")
        #expect(replay.fold.agent.effort == nil)
        #expect(replay.agent.agent.can.effort == false)
    }

    /// Without a one-time allow, an allow cannot be sent: the refusal sent is the decision shown, and it is said.
    @Test func anAllowNotOfferedIsARefusal() throws {
        let replay = Self.opened()
        _ = try replay.agent.send("Hello.", when: "next")
        replay.feed(Self.update(["sessionUpdate": "tool_call", "toolCallId": "call_fake1", "title": "touch invented.txt", "kind": "execute", "status": "pending"]))
        replay.feed(["jsonrpc": "2.0", "id": 0, "method": "session/request_permission", "params": ["sessionId": Self.session,
            "options": [["kind": "allow_always", "name": "Always allow", "optionId": "always"], ["kind": "reject_once", "name": "Reject", "optionId": "reject"]],
            "toolCall": ["toolCallId": "call_fake1", "title": "touch invented.txt", "kind": "execute", "rawInput": ["command": "touch invented.txt"]]]])
        let request = try #require(replay.fold.requests.first?.id)
        #expect(try replay.agent.answer(request, .once))
        let reply = try #require(replay.lines().last?["result"] as? [String: Any])
        #expect(reply["outcome"] as? [String: String] == ["outcome": "cancelled"], "never \"always\"")
        #expect(replay.items.first { $0.kind == "tool" }?.decision == Decision(by: "person", outcome: "denied"))
        #expect(replay.fold.agent.error == AgentError(code: "AGENT_ERROR", message: ACPDriver.noAllowOnce))
    }
}
