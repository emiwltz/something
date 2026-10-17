// The bridge: every case of share/contract/bridge/ through Bridge with a fake host, then each function against a
// granted right, a refused one, an agent out of scope, an agent started elsewhere and a `can` that says false.
import Foundation
import Testing
@testable import SomethingCore

/// A host that answers as a real engine would, from the invented state, and records what the bridge asked of it.
final class FakeHost: BridgeHost {
    var state: State
    var granted: Granted
    var launched: Set<String> = []
    var memory: Memory?
    var lines: [JournalLine] = []
    var calls: [String] = []
    var confirmsModes = true

    init(granted: Granted, memory: Memory? = nil) throws {
        state = try JSONDecoder().decode(State.self, from: ContractFiles.data("state-example.json"))
        (self.granted, self.memory) = (granted, memory)
    }

    /// A host whose space was granted `rights` over every agent, launches in the shop folder.
    convenience init(_ rights: [String], scope: Scope = .all) throws {
        var granted = Granted()
        (granted.rights, granted.agents, granted.folder) = (rights, scope, "/Users/example/code/shop")
        try self.init(granted: granted)
    }

    func journal(_ line: JournalLine) { lines.append(line) }
    func deliver(_ text: String, to agent: Agent, when: String) throws -> String {
        calls.append("deliver \(agent.id) \(when)")
        return when == "now" ? "steered" : ["working", "waiting"].contains(agent.state) ? "queued" : "started"
    }
    func interrupt(_ agent: Agent) throws -> Bool { calls.append("interrupt \(agent.id)"); return agent.state == "working" }
    func set(_ agent: Agent, model: String?, mode: String?, effort: String?) throws -> String {
        calls.append("set \(agent.id) \(model ?? "-") \(mode ?? "-")"); return "now"
    }
    func launch(_ kind: String, folder: String, model: String?, mode: String?, effort: String?) throws -> String {
        calls.append("launch \(kind) \(folder)"); return "n1"
    }
    func resume(_ kind: String, thread: String, of agent: Agent) throws -> String { calls.append("resume \(thread)"); return "n2" }
    func open(_ url: URL) throws -> Bool { calls.append("open \(url.absoluteString)"); return true }
    func confirms(mode: String, kind: String) -> Bool { mode != "acceptEdits" || confirmsModes }
}

/// The code of the answer, or "ok" for a result.
func code(_ method: String, _ params: [String: Any], _ host: FakeHost) -> String {
    let answer = Bridge.answer(["contract": 1, "id": 1, "method": method, "params": params], host: host)
    return (answer["error"] as? [String: Any])?["code"] as? String ?? (answer["result"] != nil ? "ok" : "no answer")
}

struct BridgeTests {
    @Test(arguments: ContractFiles.fixtures("bridge"))
    func everyBridgeCaseGivesItsAnswer(_ name: String) throws {
        let fixture = try ContractFiles.object(name)
        let granted = try JSONDecoder().decode(Granted.self, from: JSONSerialization.data(withJSONObject: fixture["granted"]!))
        let host = try FakeHost(granted: granted)
        let request = try #require(fixture["request"] as? [String: Any])
        let expected = try #require(fixture["answer"] as? [String: Any])
        let answer = Bridge.answer(request, host: host)
        #expect(answer["id"] as? Int == expected["id"] as? Int)
        if let error = expected["error"] as? [String: Any] {
            let got = try #require(answer["error"] as? [String: Any], "\(name): \(answer)")
            #expect(got["code"] as? String == error["code"] as? String, "\(name): \(got)")
            #expect((got["message"] as? String)?.hasSuffix(".") == true, "\(name): the message is one sentence")
        } else {
            let got = try JSONSerialization.data(withJSONObject: try #require(answer["result"]), options: [.sortedKeys, .fragmentsAllowed])
            let want = try JSONSerialization.data(withJSONObject: try #require(expected["result"]), options: [.sortedKeys, .fragmentsAllowed])
            #expect(got == want, "\(name): \(String(decoding: got, as: UTF8.self))")
        }
    }

    @Test func sendFollowsRightsScopeOriginAndCan() throws {
        let hello: [String: Any] = ["agent": "a1", "text": "Hello.", "when": "next"]
        #expect(code("send", hello, try FakeHost(["state", "send:claude"])) == "ok")
        #expect(code("send", hello, try FakeHost(["state"])) == "RIGHT_NOT_GRANTED")
        #expect(code("send", hello, try FakeHost(["state", "send:codex"])) == "RIGHT_NOT_GRANTED")
        // Out of scope reads as absent, so a space cannot probe for agents it may not see.
        #expect(code("send", hello, try FakeHost(["state", "send"], scope: .folders(["/Users/example/code/blog"]))) == "AGENT_NOT_FOUND")
        #expect(code("send", hello, try FakeHost(["state", "send"], scope: .folders(["/Users/example/code/sho"]))) == "AGENT_NOT_FOUND")
        #expect(code("send", ["agent": "e1", "text": "Hello."], try FakeHost(["state", "send"])) == "READ_ONLY_AGENT")
        let host = try FakeHost(["state", "send"])
        host.state.agents[0].can.steer = false
        #expect(code("send", ["agent": "a1", "text": "Hello.", "when": "now"], host) == "NOT_SUPPORTED")
        #expect(code("send", ["agent": "a1", "text": "Hello.", "when": "later"], host) == "BAD_PARAMS")
        #expect(code("send", ["agent": "a1", "text": "  "], host) == "BAD_PARAMS")
        host.state.agents[0].alive = false
        #expect(code("send", hello, host) == "AGENT_STOPPED")
    }

    @Test func withoutTheStateRightOnlyItsOwnAgentsExist() throws {
        let host = try FakeHost(["send"])
        #expect(code("send", ["agent": "a1", "text": "Hello."], host) == "AGENT_NOT_FOUND")
        let state = try #require(Bridge.answer(["method": "state"], host: host)["result"] as? [String: Any])
        #expect((state["agents"] as? [Any])?.isEmpty == true && (state["threads"] as? [Any])?.isEmpty == true)
        #expect((state["requests"] as? [Any])?.isEmpty == true)
        host.launched = ["a1"]
        #expect(code("send", ["agent": "a1", "text": "Hello."], host) == "ok")
        let mine = try #require(Bridge.answer(["method": "state"], host: host)["result"] as? [String: Any])
        #expect((mine["agents"] as? [[String: Any]])?.map { $0["id"] as? String } == ["a1"])
        #expect((mine["requests"] as? [Any])?.count == 1)
    }

    @Test func interruptAndSetFollowCan() throws {
        let host = try FakeHost(["state", "send"])
        #expect(code("interrupt", ["agent": "a1"], host) == "ok")
        #expect(code("interrupt", ["agent": "e1"], host) == "READ_ONLY_AGENT")
        #expect(code("interrupt", ["agent": "a1"], try FakeHost(["state"])) == "RIGHT_NOT_GRANTED")
        #expect(code("set", ["agent": "a1", "mode": "plan"], host) == "ok")
        #expect(code("set", ["agent": "a1"], host) == "BAD_PARAMS")
        #expect(code("set", ["agent": "a1", "effort": "high"], host) == "NOT_SUPPORTED")
        #expect(code("set", ["agent": "a1", "mode": "yolo"], host) == "VALUE_NOT_OFFERED")
        #expect(code("set", ["agent": "e1", "model": "gpt-example"], host) == "READ_ONLY_AGENT")
        host.state.agents[0].can.interrupt = false
        #expect(code("interrupt", ["agent": "a1"], host) == "NOT_SUPPORTED")
        #expect(host.calls == ["interrupt a1", "set a1 - plan"])
    }

    @Test func aModeThatLowersAskingNeedsThePersonsYes() throws {
        let host = try FakeHost(["state", "send", "launch"])
        host.state.agents[0].options.mode?.append(Option(value: "acceptEdits", label: "Accept edits"))
        #expect(code("set", ["agent": "a1", "mode": "acceptEdits"], host) == "ok")
        host.confirmsModes = false
        #expect(code("set", ["agent": "a1", "mode": "acceptEdits"], host) == "REFUSED")
        #expect(code("launch", ["kind": "claude", "mode": "acceptEdits"], host) == "REFUSED")
        #expect(host.calls == ["set a1 - acceptEdits"])
    }

    @Test func launchStaysInTheGrantedFolder() throws {
        let host = try FakeHost(["launch:claude", "launch:opencode", "launch:omp"])
        #expect(code("launch", ["kind": "claude"], host) == "ok")
        #expect(code("launch", ["kind": "claude", "folder": "/Users/example/code/shop/web"], host) == "ok")
        #expect(code("launch", ["kind": "claude", "folder": "/Users/example/code/shop2"], host) == "FOLDER_NOT_GRANTED")
        #expect(code("launch", ["kind": "claude", "folder": "/Users/example/code/shop/../blog"], host) == "FOLDER_NOT_GRANTED")
        #expect(code("launch", ["kind": "claude", "folder": "web"], host) == "BAD_PARAMS")
        #expect(code("launch", ["kind": "codex"], host) == "RIGHT_NOT_GRANTED")
        #expect(code("launch", ["kind": "opencode"], host) == "NOT_INSTALLED")
        #expect(code("launch", ["kind": "omp"], host) == "NOT_SUPPORTED")
        #expect(code("launch", ["kind": 3], host) == "BAD_PARAMS")
        host.granted.folder = nil
        #expect(code("launch", ["kind": "claude"], host) == "FOLDER_NOT_GRANTED")
        #expect(host.calls == ["launch claude /Users/example/code/shop", "launch claude /Users/example/code/shop/web"])
    }

    @Test func resumeNeedsAThreadInScopeThatCanBeContinued() throws {
        let thread = "019a0000-0000-7000-8000-000000000002"
        let host = try FakeHost(["state", "launch"])
        host.granted.folder = "/Users/example/code"
        #expect(code("resume", ["kind": "codex", "thread": thread], host) == "ok")
        #expect(code("resume", ["kind": "claude", "thread": thread], host) == "THREAD_NOT_FOUND")
        #expect(code("resume", ["kind": "claude", "thread": "c0ffee00-0000-4000-8000-000000000001"], host) == "STILL_RUNNING")
        #expect(code("resume", ["kind": "codex", "thread": thread], try FakeHost(["state", "launch:claude"])) == "RIGHT_NOT_GRANTED")
        #expect(code("resume", ["kind": "codex", "thread": thread], try FakeHost(["launch"])) == "THREAD_NOT_FOUND")
        // The shop folder is granted, the conversation works in the blog folder.
        #expect(code("resume", ["kind": "codex", "thread": thread], try FakeHost(["state", "launch"])) == "FOLDER_NOT_GRANTED")
        host.state.agents[1].can.resume = false
        #expect(code("resume", ["kind": "codex", "thread": thread], host) == "NOT_SUPPORTED")
        #expect(host.calls == ["resume \(thread)"])
    }

    @Test func storeNeedsItsRightAndAMemory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        var granted = Granted()
        granted.rights = ["store"]
        let host = try FakeHost(granted: granted, memory: Memory(folder: folder, space: "example"))
        #expect(code("store.set", ["path": "seen/a1", "value": true], host) == "ok")
        #expect(Bridge.answer(["method": "store.get", "params": ["path": "seen"]], host: host)["result"] as? [String: Bool] == ["a1": true])
        #expect(Bridge.answer(["method": "store.get", "params": ["path": "absent"]], host: host)["result"] is NSNull)
        #expect(code("store.set", ["path": "seen"], host) == "BAD_PARAMS")
        #expect(code("store.get", ["path": "a//b"], host) == "BAD_PARAMS")
        try Data("not json".utf8).write(to: folder.appendingPathComponent("example.json"))
        #expect(code("store.get", ["path": ""], host) == "STORE_FULL")
        #expect(code("store.get", ["path": ""], try FakeHost(["state"])) == "RIGHT_NOT_GRANTED")
        #expect(code("store.get", ["path": ""], try FakeHost(["store"])) == "RIGHT_NOT_GRANTED")
        #expect(host.lines.isEmpty, "the memory is not a write action of the journal")
    }

    @Test func openTakesWebAndMailLinksOnly() throws {
        let host = try FakeHost([])
        #expect(code("open", ["url": "https://example.com/docs"], host) == "ok")
        #expect(code("open", ["url": "mailto:someone@example.com"], host) == "ok")
        #expect(code("open", ["url": "file:///Users/example/.ssh"], host) == "BAD_PARAMS")
        #expect(code("open", ["url": "something://app/x"], host) == "BAD_PARAMS")
        #expect(host.calls == ["open https://example.com/docs", "open mailto:someone@example.com"])
    }

    @Test func everyWriteActionLeavesOneJournalLineEvenWhenItFails() throws {
        let host = try FakeHost(["state", "send:claude", "launch"])
        _ = code("send", ["agent": "a1", "text": "Then check the footer.", "when": "next"], host)
        _ = code("send", ["agent": "e1", "text": "Hello."], host)
        _ = code("interrupt", ["agent": "zz"], host)
        _ = code("set", ["agent": "a1", "mode": "plan"], host)
        _ = code("launch", ["kind": "claude"], host)
        _ = code("open", ["url": "https://example.com"], host)
        _ = code("state", [:], host)
        _ = code("delete", [:], host)
        #expect(host.lines.map(\.action) == ["send", "send", "interrupt", "set", "launch", "open"])
        #expect(host.lines.map(\.result) == ["ok", "RIGHT_NOT_GRANTED", "AGENT_NOT_FOUND", "ok", "ok", "ok"])
        #expect(host.lines[0] == JournalLine(at: host.lines[0].at, action: "send", agent: "a1", kind: "claude", when: "next", text: "Then check the footer.", result: "ok"))
        #expect(host.lines[3].text == "mode=plan" && host.lines[4].agent == "n1" && host.lines[5].text == "https://example.com")
    }

    @Test func answersCarryTheRequestIdAndACodedError() throws {
        let answer = Bridge.answer(["id": 7, "method": "nope"], host: try FakeHost([]))
        #expect(answer["id"] as? Int == 7)
        let error = try #require(answer["error"] as? [String: String])
        #expect(error["code"] == "UNKNOWN_METHOD" && error["message"]?.isEmpty == false)
        #expect(Bridge.answer([:], host: try FakeHost([]))["id"] is NSNull)
    }
}
