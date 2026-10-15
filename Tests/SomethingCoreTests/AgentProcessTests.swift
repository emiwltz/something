import Foundation
import Testing
@testable import SomethingCore

struct AgentProcessTests {
    /// A newcomer without the agent installed must read what to do, not a message from /usr/bin/env.
    @Test func aMissingProgramSaysWhatToDo() async throws {
        let session = AgentProcess(agent: Agent(id: "x-1", name: "try", harness: "x", folder: NSTemporaryDirectory()),
                                   arguments: ["something-example-no-such-program"])
        try session.start()
        for _ in 0..<100 where session.agent.status != "stopped" { try await Task.sleep(nanoseconds: 50_000_000) }
        #expect(session.agent.status == "stopped")
        #expect(session.agent.error == "`something-example-no-such-program` is not installed, or something cannot find it in your PATH. Install it, then launch the agent again.")
    }
}
