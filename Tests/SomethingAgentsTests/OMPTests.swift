// OMP over ACP: its profile driven over its own recorded exchanges (Tests/Exchanges/omp, trial C1 against the real
// omp 18.8.6): every line something wrote goes out byte for byte as it did, and what OMP said folds as it showed.
// OMP titles its tool calls with sentences, so a tool goes by its kind, and something's tools reach it over MCP.
import Foundation
import Testing
@testable import SomethingAgents
@testable import AgentACP
@testable import AgentPi
import SomethingCore

@Suite struct OMPTests {
    static func play(_ name: String) throws -> Replay { try Replay.play(name, kind: "omp") }

    @Test func itIsDrivenAndBuilds() throws {
        let omp = try #require(Registry.described.agent("omp"))
        let driving = try Registry.described.driving("omp")
        #expect(driving.command(Launch(agent: "omp-1", folder: "/Users/example/shop")) == Command(arguments: ["acp"]))
        #expect(driving.tested == "18.8.6" && driving.modes.map(\.value) == ["default", "plan"] && !driving.listsMoreModes)
        #expect(omp.builder?.lent.map(\.name) == LentTool.all.map(\.name) && omp.builder?.preAllowed == false)
        #expect(!omp.neverAsks, "it asks as its own settings say")
        #expect(omp.reader?(["HOME": "/Users/example"]) is OMPReader)
        #expect(Registry.described.kinds.launchable.contains("omp") && Registry.described.kinds.readOnly.isEmpty)
        #expect(try Registry.described.lowersAsking(mode: "plan", kind: "omp") == false)
    }

    /// A tool OMP needs no permission for (its default, approvalMode yolo) goes by its kind, with OMP's own title.
    @Test func aTurn() throws {
        let replay = try Self.play("turn")
        let agent = replay.fold.agent
        #expect(agent.kind == "omp" && agent.state == "done" && agent.error == nil)
        #expect(agent.thread == "01a167f4-96fd-7411-9049-c6580d66ad69", "its log is named after the session, so the reader leaves it out")
        #expect((agent.model, agent.mode, agent.effort) == ("anthropic/claude-opus-5-5", "default", "xhigh"))
        #expect(agent.options.mode?.map(\.value) == ["default", "plan"] && agent.options.effort?.count == 7)
        #expect(replay.items.map(\.kind) == ["message", "tool", "message"])
        #expect(replay.items[1].tool == Tool(name: "edit", status: "done") && replay.items[1].text == "Creating fruit.txt with pear")
    }

    @Test func aPermissionAllowedOnce() throws {
        let replay = try Self.play("permission-once")
        let tool = try #require(replay.items.first { $0.kind == "tool" })
        #expect(tool.tool == Tool(name: "execute", status: "done") && tool.decision == Decision(by: "person", outcome: "allowed"))
        #expect(replay.fold.requests.isEmpty && replay.fold.agent.state == "done")
    }

    /// Refused, OMP ends its turn normally and says so in its reply: no error is made up.
    @Test func aPermissionDenied() throws {
        let replay = try Self.play("deny")
        let tool = try #require(replay.items.first { $0.kind == "tool" })
        #expect(tool.tool == Tool(name: "execute", status: "failed") && tool.decision == Decision(by: "person", outcome: "denied"))
        #expect(replay.fold.agent.error == nil && replay.fold.turns.last?.state == "done")
    }

    @Test func anInterrupt() throws {
        #expect(try Self.play("interrupt").fold.turns.map(\.state) == ["interrupted"])
    }

    /// The person's assistant gets something's MCP server in session/new; OMP calls a server's tool through the path
    /// xd://mcp__something_<tool>, shown as the command something runs. Reading a tool's docs is a read like any other.
    @Test func theAssistantBuildsWithSomethingsTools() throws {
        let replay = try Self.play("assistant-build")
        let lent = replay.items.filter { $0.tool?.name.hasPrefix("something_") == true }
        #expect(lent.map(\.text) == ["something guide --print", "something new hello", "something check hello"])
        #expect(lent.allSatisfy { $0.tool?.status == "done" })
        #expect(replay.items.filter { $0.tool?.name == "read" }.count == 6, "three docs, the folder's instructions, the page, the snapshot")
        #expect(replay.fold.requests.isEmpty && replay.fold.agent.state == "done")
    }

    /// OMP's MCP call with arguments that are no JSON, or wrong, is shown as every driver shows wrong arguments.
    @Test func wrongArgumentsToALentTool() throws {
        let replay = Replay.omp(assistant: true)
        replay.feed(["jsonrpc": "2.0", "id": 1, "result": ["protocolVersion": 1]])
        replay.feed(["jsonrpc": "2.0", "id": 2, "result": ["sessionId": ACPDriverTests.session, "configOptions": []]])
        for (id, content) in [("call_1", "not json"), ("call_2", #"{"name": "../hello"}"#)] {
            replay.feed(ACPDriverTests.update(["sessionUpdate": "tool_call", "toolCallId": id, "kind": "execute", "title": "Invented title",
                                               "status": "pending", "rawInput": ["path": "xd://mcp__something_check", "content": content]]))
            replay.feed(ACPDriverTests.update(["sessionUpdate": "tool_call_update", "toolCallId": id, "status": "completed"]))
            #expect(replay.items.last?.tool?.name == "something_check" && replay.items.last?.text == "something_check (wrong arguments)")
        }
    }
}
