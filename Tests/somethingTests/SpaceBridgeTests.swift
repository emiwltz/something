// Which calls of a space wait for a program lookup before they are answered: only a launch or a resume that may go
// ahead. Any other call, and a launch the bridge refuses at once, never runs the person's login shell.
import Foundation
import SomethingCore
import Testing
@testable import something

@Suite struct SpaceBridgeTests {
    /// A host from the contract's invented state (claude and codex installed, opencode not, omp not launched).
    func host(_ rights: [String]) throws -> CheckHost {
        let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: Home.share.appendingPathComponent("contract/state-example.json")))
        var granted = Granted()
        (granted.rights, granted.agents, granted.folder) = (rights, .all, "/Users/example/code/shop")
        return CheckHost(state: state, granted: granted, declared: rights, memory: nil)
    }

    @Test func aLaunchOrAResumeThatMayGoAheadLooksForItsProgram() throws {
        let host = try host(["state", "launch"])
        #expect(SpaceWindow.lookup(["method": "launch", "params": ["kind": "claude"]], host: host) == "claude")
        #expect(SpaceWindow.lookup(["method": "resume", "params": ["kind": "codex", "thread": "t-1"]], host: host) == "codex")
    }

    @Test func everyOtherCallIsAnsweredAtOnce() throws {
        let host = try host(["state", "launch:claude"])
        #expect(SpaceWindow.lookup(["method": "launch", "params": ["kind": "claude"]], host: host) == "claude")
        #expect(SpaceWindow.lookup(["method": "launch", "params": ["kind": "codex"]], host: host) == nil, "a right not granted")
        #expect(SpaceWindow.lookup(["method": "launch", "params": [:] as [String: Any]], host: host) == nil, "no kind")
        #expect(SpaceWindow.lookup(["method": "send", "params": ["kind": "claude"]], host: host) == nil, "another method")
        #expect(SpaceWindow.lookup("launch", host: host) == nil, "not a request")
        let all = try self.host(["launch"])
        #expect(SpaceWindow.lookup(["method": "launch", "params": ["kind": "opencode"]], host: all) == nil, "not installed")
        #expect(SpaceWindow.lookup(["method": "launch", "params": ["kind": "omp"]], host: all) == nil, "not launched by something")
        #expect(SpaceWindow.lookup(["method": "launch", "params": ["kind": "other"]], host: all) == nil, "not a kind")
    }
}
