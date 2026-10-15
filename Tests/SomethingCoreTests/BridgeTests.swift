import Foundation
import Testing
@testable import SomethingCore

/// A host that records what the bridge asked of it.
final class FakeHost: BridgeHost {
    var state = State()
    var sent: [(String, String)] = []
    var refuse = false
    var store: PageStore? = nil

    func launch(harness: String) throws -> String {
        if refuse { throw BridgeError("No folder chosen.") }
        return "claude-1"
    }

    func send(agent: String, text: String) throws {
        if refuse { throw BridgeError("You refused to send this message.") }
        sent.append((agent, text))
    }
}

struct BridgeTests {
    @Test func testUnknownValuesAreNullNotMissing() throws {
        let host = FakeHost()
        host.state = State(agents: [Agent(id: "a1", name: "docs", harness: "claude", folder: "/Users/example/docs")])
        let answer = Bridge.answer(["method": "state"], host: host)
        let agents = try #require((answer["result"] as? [String: Any])?["agents"] as? [[String: Any]])
        #expect(agents.count == 1)
        for key in ["model", "status", "mode", "error"] {
            #expect(agents[0].keys.contains(key), "\(key) must be sent as null")
            #expect(agents[0][key] is NSNull)
        }
    }

    @Test func testEmptyStateHasAnEmptyList() throws {
        let answer = Bridge.answer(["method": "state"], host: FakeHost())
        let result = try #require(answer["result"] as? [String: Any])
        #expect((result["agents"] as? [Any])?.count == 0)
    }

    @Test func testSendReachesTheHost() {
        let host = FakeHost()
        let answer = Bridge.answer(["method": "send", "params": ["agent": "claude-1", "text": "hello"]], host: host)
        #expect(answer["error"] == nil)
        #expect(host.sent.first?.1 == "hello")
    }

    @Test func testARefusalIsAnErrorThePageCanShow() {
        let host = FakeHost()
        host.refuse = true
        let answer = Bridge.answer(["method": "send", "params": ["agent": "claude-1", "text": "hello"]], host: host)
        #expect(answer["error"] as? String == "You refused to send this message.")
        #expect(host.sent.isEmpty)
    }

    @Test func testBadRequestsSayWhatToDo() {
        #expect(Bridge.answer([:], host: FakeHost())["error"] != nil)
        #expect(Bridge.answer(["method": "send", "params": ["agent": "claude-1", "text": "  "]], host: FakeHost())["error"] != nil)
        let unknown = Bridge.answer(["method": "nope"], host: FakeHost())["error"] as? String
        #expect(unknown == "Unknown method \"nope\". Known: state, launch, send, store.get, store.set.")
    }

    @Test func testThePageMemoryKeepsValuesAcrossLaunches() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let host = FakeHost()
        host.store = PageStore(file: folder.appendingPathComponent("store.json"))
        let set = Bridge.answer(["method": "store.set", "params": ["key": "mood", "value": ["hunger": 3]]], host: host)
        #expect(set["error"] == nil)
        host.store = PageStore(file: folder.appendingPathComponent("store.json"))
        let got = Bridge.answer(["method": "store.get", "params": ["key": "mood"]], host: host)
        #expect((got["result"] as? [String: Any])?["hunger"] as? Int == 3)
        #expect(Bridge.answer(["method": "store.get", "params": ["key": "absent"]], host: host)["result"] is NSNull)
    }

    @Test func testAPageWithoutMemorySaysSo() {
        let answer = Bridge.answer(["method": "store.get", "params": ["key": "mood"]], host: FakeHost())
        #expect(answer["error"] as? String == "This page has no memory.")
    }
}
