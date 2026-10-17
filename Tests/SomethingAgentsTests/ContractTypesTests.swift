// The contract types can be built from outside SomethingCore, as the engine and the drivers will build them.
// This file imports SomethingCore without @testable on purpose: an internal initializer would fail to compile here.
import Foundation
import SomethingCore
import Testing

struct ContractTypesTests {
    @Test func everyContractTypeCanBeBuiltFromOutside() throws {
        let at = "2026-10-17T09:00:00Z"
        let kind = Kind(launch: true, installed: true, tested: "1.0.0", seen: nil, reader: "ok", note: nil)
        var agent = Agent(id: "a1", kind: "claude", origin: "launched")
        agent.options.mode = [Option(value: "default", label: "Ask before acting")]
        agent.queue = [Queued(id: "q1", text: "Invented.", at: at)]
        agent.error = AgentError(code: "AGENT_ERROR", message: "Invented.")
        let item = Item(id: "i1", kind: "tool", author: "agent", text: "ls", at: at, tool: Tool(name: "Bash", status: "done"),
                        decision: Decision(by: "person", outcome: "allowed"))
        let thread = AgentThread(id: "th1", agent: "a1", title: nil, started: nil,
                                 turns: [Turn(id: "t1", state: "done", started: nil, ended: nil, items: [item])])
        let request = Request(id: "r1", agent: "a1", kind: "permission", tool: "Bash", about: nil, at: at)
        let state = State(at: at, kinds: ["claude": kind], agents: [agent], threads: [thread], requests: [request])
        #expect(try JSONDecoder().decode(State.self, from: state.json()) == state)
    }
}
