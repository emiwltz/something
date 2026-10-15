import XCTest
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

final class BridgeTests: XCTestCase {
    func testUnknownValuesAreNullNotMissing() throws {
        let host = FakeHost()
        host.state = State(agents: [Agent(id: "a1", name: "docs", harness: "claude", folder: "/Users/example/docs")])
        let answer = Bridge.answer(["method": "state"], host: host)
        let agents = try XCTUnwrap((answer["result"] as? [String: Any])?["agents"] as? [[String: Any]])
        XCTAssertEqual(agents.count, 1)
        for key in ["model", "status", "mode", "error"] {
            XCTAssertTrue(agents[0].keys.contains(key), "\(key) must be sent as null")
            XCTAssertTrue(agents[0][key] is NSNull)
        }
    }

    func testEmptyStateHasAnEmptyList() throws {
        let answer = Bridge.answer(["method": "state"], host: FakeHost())
        let result = try XCTUnwrap(answer["result"] as? [String: Any])
        XCTAssertEqual((result["agents"] as? [Any])?.count, 0)
    }

    func testSendReachesTheHost() {
        let host = FakeHost()
        let answer = Bridge.answer(["method": "send", "params": ["agent": "claude-1", "text": "hello"]], host: host)
        XCTAssertNil(answer["error"])
        XCTAssertEqual(host.sent.first?.1, "hello")
    }

    func testARefusalIsAnErrorThePageCanShow() {
        let host = FakeHost()
        host.refuse = true
        let answer = Bridge.answer(["method": "send", "params": ["agent": "claude-1", "text": "hello"]], host: host)
        XCTAssertEqual(answer["error"] as? String, "You refused to send this message.")
        XCTAssertTrue(host.sent.isEmpty)
    }

    func testBadRequestsSayWhatToDo() {
        XCTAssertNotNil(Bridge.answer([:], host: FakeHost())["error"])
        XCTAssertNotNil(Bridge.answer(["method": "send", "params": ["agent": "claude-1", "text": "  "]], host: FakeHost())["error"])
        let unknown = Bridge.answer(["method": "nope"], host: FakeHost())["error"] as? String
        XCTAssertEqual(unknown, "Unknown method \"nope\". Known: state, launch, send, store.get, store.set.")
    }

    func testThePageMemoryKeepsValuesAcrossLaunches() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let host = FakeHost()
        host.store = PageStore(file: folder.appendingPathComponent("store.json"))
        let set = Bridge.answer(["method": "store.set", "params": ["key": "mood", "value": ["hunger": 3]]], host: host)
        XCTAssertNil(set["error"])
        host.store = PageStore(file: folder.appendingPathComponent("store.json"))
        let got = Bridge.answer(["method": "store.get", "params": ["key": "mood"]], host: host)
        XCTAssertEqual((got["result"] as? [String: Any])?["hunger"] as? Int, 3)
        XCTAssertTrue(Bridge.answer(["method": "store.get", "params": ["key": "absent"]], host: host)["result"] is NSNull)
    }

    func testAPageWithoutMemorySaysSo() {
        let answer = Bridge.answer(["method": "store.get", "params": ["key": "mood"]], host: FakeHost())
        XCTAssertEqual(answer["error"] as? String, "This page has no memory.")
    }
}
