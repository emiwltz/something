// Cursor: seen by its process, not launched yet; its ACP profile is proven over its own recorded exchanges
// (Tests/Exchanges/cursor, trial C3 against the real cursor-agent 2026.10.19-6bbf2c4): every line something wrote goes
// out byte for byte as it did, and what Cursor said folds as it showed. Cursor streams texts without ids, asks without
// the call's input, and names an MCP server's tool only in a later update.
import Foundation
import Testing
@testable import SomethingAgents
@testable import AgentACP
import SomethingCore

@Suite struct CursorTests {
    static func play(_ name: String) throws -> Replay { try Replay.play(name, kind: "cursor", driving: ACPProfile.cursor.driving) }

    /// Under Node, as Homebrew's cursor-agent and the installer's agent both run: the system names the process node,
    /// and its first argument is the link it was started by.
    @MainActor @Test func itIsSeenByItsProcess() throws {
        let started = Date(timeIntervalSince1970: 1_792_224_000)
        let snapshot = Snapshot([
            Running(pid: 56000, parent: 1, group: 56000, started: started, name: "node",
                    arguments: ["/opt/homebrew/bin/cursor-agent", "--use-system-ca", "/opt/homebrew/Caskroom/cursor-cli/1/dist-package/index.js"],
                    folder: "/Users/example/shop"),
            Running(pid: 56100, parent: 1, group: 56100, started: started, name: "node",
                    arguments: ["/Users/example/.local/bin/agent", "/Users/example/.local/share/cursor-agent/versions/1/index.js"],
                    folder: "/Users/example/notes"),
            Running(pid: 56200, parent: 1, group: 56200, started: started, name: "cursor", arguments: ["cursor"], folder: "/Users/example/shop"),
        ])
        let reader = try #require(AgentDescriptor.cursor.reader?([:]))
        let seen = Watch(readers: [reader], snapshot: { snapshot }).tick(now: started)
        let (agents, threads) = Watch.elsewhere(seen, registry: .described, groups: [], keys: [], now: started)
        #expect(Set(agents.map(\.id)) == ["cursor-cursor-agent-56000", "cursor-agent-56100"] && threads.isEmpty, "the editor is not its CLI")
        #expect(agents.allSatisfy { $0.kind == "cursor" && $0.state == "unknown" && $0.evidence == "process" && $0.thread == nil })
    }

    /// Known, never launched, with the reason: no install sentence, no builder, and a launch is refused before anything
    /// starts. No other agent claims its programs: one process is never two agents.
    @Test func itIsNotLaunched() throws {
        let cursor = try #require(Registry.described.agent("cursor"))
        #expect(cursor.name == "Cursor" && cursor.install == nil && cursor.driving == nil && cursor.builder == nil)
        let reason = try #require(cursor.unavailable)
        #expect(throws: CodedError("NOT_SUPPORTED", reason)) { try Registry.described.checkLaunch("cursor", model: nil, mode: nil, effort: nil) }
        #expect(Registry.described.kinds.readOnly.contains("cursor") && !Registry.described.kinds.launchable.contains("cursor"))
        let claimed = Registry.described.readers([:]).map { $0.programs.subtracting(Running.interpreters) }
        #expect(claimed.reduce(0) { $0 + $1.count } == Set(claimed.joined()).count, "\(claimed)")
    }

    /// A text without an id is one item until a tool call or the other kind of text: thoughts and replies apart.
    @Test func aTurn() throws {
        let replay = try Self.play("turn")
        let agent = replay.fold.agent
        #expect(agent.state == "done" && agent.error == nil)
        #expect((agent.model, agent.mode, agent.effort) == ("default[]", "agent", nil))
        #expect(agent.options.mode?.map(\.value) == ["agent", "plan", "ask"] && agent.options.effort == nil)
        #expect(replay.items.map(\.kind) == ["message", "thought", "message", "tool", "thought", "message"])
        #expect(replay.items[1].text.hasPrefix("Invented thought 1. Invented thought 2.") && replay.items[2].text.hasPrefix("Invented reply 1. Invented reply 2."))
        #expect(replay.items[3].tool == Tool(name: "edit", status: "done") && replay.items[3].text == "Edit `/Users/example/shop/fruit.txt`")
    }

    @Test func aPermissionAllowedOnce() throws {
        let replay = try Self.play("permission-once")
        let tool = try #require(replay.items.first { $0.kind == "tool" })
        #expect(tool.tool == Tool(name: "execute", status: "done") && tool.decision == Decision(by: "person", outcome: "allowed"))
        #expect(replay.fold.requests.isEmpty && replay.fold.agent.state == "done")
    }

    /// Refused, Cursor says the call "completed": it did not run, so it is shown failed; the turn ends normally.
    @Test func aPermissionDenied() throws {
        let replay = try Self.play("deny")
        let tool = try #require(replay.items.first { $0.kind == "tool" })
        #expect(tool.tool == Tool(name: "execute", status: "failed") && tool.decision == Decision(by: "person", outcome: "denied"))
        #expect(replay.fold.agent.error == nil && replay.fold.turns.last?.state == "done")
    }

    @Test func anInterrupt() throws {
        #expect(try Self.play("interrupt").fold.turns.map(\.state) == ["interrupted"])
    }

    /// The assistant gets something's MCP server in session/new and builds with it; Cursor's own settings asked before
    /// each of something's tools (allowed once here), which is why it is not offered yet.
    @Test func theAssistantBuildsWithSomethingsTools() throws {
        let replay = try Self.play("assistant-build")
        let lent = replay.items.filter { $0.tool?.name.hasPrefix("something_") == true }
        #expect(lent.map(\.text) == ["something guide --print", "something new hello", "something check hello"])
        #expect(lent.allSatisfy { $0.tool?.status == "done" && $0.decision == Decision(by: "person", outcome: "allowed") })
        #expect(!replay.items.contains { $0.tool?.name == "other" || $0.text == "MCP: tool" })
        #expect(replay.fold.requests.isEmpty && replay.fold.agent.state == "done")
    }

    /// Cursor asks with the call's kind and title only: the panel shows the input its updates gave, as the command
    /// something would run for one of its tools (the shapes of permission-once.jsonl and assistant-build.jsonl).
    @Test func anAskShowsTheInputTheUpdatesGave() throws {
        let replay = Replay.launch("cursor", server: Replay.server, driving: ACPProfile.cursor.driving)
        replay.feed(["jsonrpc": "2.0", "id": 1, "result": ["protocolVersion": 1]])
        replay.feed(["jsonrpc": "2.0", "id": 2, "result": ["sessionId": ACPDriverTests.session, "configOptions": []]])
        let calls: [(id: String, kind: String, input: [String: Any], title: String)] = [
            ("call-1", "execute", ["command": "touch invented.txt"], "`touch invented.txt`"),
            ("call-2", "other", ["providerIdentifier": "something", "toolName": "something_new", "args": ["name": "hello"]], "something-something_new: something_new"),
        ]
        for (number, call) in calls.enumerated() {
            replay.feed(ACPDriverTests.update(["sessionUpdate": "tool_call", "toolCallId": call.id, "kind": call.kind, "title": "Invented title",
                                               "status": "pending", "rawInput": [String: Any]()]))
            replay.feed(ACPDriverTests.update(["sessionUpdate": "tool_call_update", "toolCallId": call.id, "rawInput": call.input]))
            replay.feed(["jsonrpc": "2.0", "id": number, "method": "session/request_permission",
                         "params": ["sessionId": ACPDriverTests.session, "toolCall": ["toolCallId": call.id, "kind": call.kind, "title": call.title],
                                    "options": [["kind": "allow_once", "name": "Allow once", "optionId": "allow-once"]]]])
        }
        let shell = try #require(replay.agent.prompt("cursor-1:0")), lent = try #require(replay.agent.prompt("cursor-1:1"))
        #expect(shell.request.tool == "execute" && shell.input == "touch invented.txt")
        #expect(lent.request.tool == "something_new" && lent.input == "something new hello")
    }
}
