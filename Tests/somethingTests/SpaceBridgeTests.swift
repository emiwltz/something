// Which calls of a space wait for a program lookup before they are answered: only a launch or a resume that may go
// ahead. Any other call, and a launch the bridge refuses at once, never runs the person's login shell. And a space's
// links: one sheet at a time, none after three Cancels until the page reloads. And an older version shown to compare:
// it reads, and every write is refused before the core.
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
        #expect(SpaceView.lookup(["method": "launch", "params": ["kind": "claude"]], host: host) == "claude")
        #expect(SpaceView.lookup(["method": "resume", "params": ["kind": "codex", "thread": "t-1"]], host: host) == "codex")
    }

    @Test func everyOtherCallIsAnsweredAtOnce() throws {
        let host = try host(["state", "launch:claude"])
        #expect(SpaceView.lookup(["method": "launch", "params": ["kind": "claude"]], host: host) == "claude")
        #expect(SpaceView.lookup(["method": "launch", "params": ["kind": "codex"]], host: host) == nil, "a right not granted")
        #expect(SpaceView.lookup(["method": "launch", "params": [:] as [String: Any]], host: host) == nil, "no kind")
        #expect(SpaceView.lookup(["method": "send", "params": ["kind": "claude"]], host: host) == nil, "another method")
        #expect(SpaceView.lookup("launch", host: host) == nil, "not a request")
        let all = try self.host(["launch"])
        #expect(SpaceView.lookup(["method": "launch", "params": ["kind": "opencode"]], host: all) == nil, "not installed")
        #expect(SpaceView.lookup(["method": "launch", "params": ["kind": "omp"]], host: all) == "omp", "launched by something")
        #expect(SpaceView.lookup(["method": "launch", "params": ["kind": "other"]], host: all) == nil, "not a kind")
    }

    /// The version held over the page (Glimpse) reads the state and the memory as the open space's, and is refused
    /// every write before the core: a send the core would deliver, store.set, launch, open, and any call unknown.
    @Test func anOlderVersionShownToCompareOnlyReads() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("something-glimpse-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let memory = Memory(folder: folder, space: "brief")
        try memory.set("seen", 3)
        let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: Home.share.appendingPathComponent("contract/state-example.json")))
        var granted = Granted()
        (granted.rights, granted.agents, granted.folder) = (["state", "send", "store", "launch", "open"], .all, "/Users/example/code/shop")
        let host = CheckHost(state: state, granted: granted, declared: granted.rights, memory: memory)
        let send: [String: Any] = ["id": 1, "method": "send", "params": ["agent": "a1", "text": "Go on"]]
        #expect((Bridge.answer(send, host: host)["result"] as? [String: Any])?["delivery"] != nil, "the core would deliver it")
        for (method, params) in [("send", send["params"]!), ("store.set", ["path": "seen", "value": 4]), ("launch", ["kind": "claude"]),
                                 ("open", ["url": "https://example.com"]), ("interrupt", ["agent": "a1"]), ("other", [:] as [String: Any])] {
            let answer = SpaceView.compared(["id": 2, "method": method, "params": params], host: host)
            #expect((answer["error"] as? [String: Any])?["code"] as? String == "NOT_SUPPORTED" && answer["result"] == nil, "\(method)")
            #expect(answer["id"] as? Int == 2)
        }
        #expect(try memory.get("seen") as? Int == 3)
        #expect(SpaceView.compared(["id": 3, "method": "store.get", "params": ["path": "seen"]], host: host)["result"] as? Int == 3)
        let read = SpaceView.compared(["id": 4, "method": "state"], host: host)["result"] as? [String: Any]
        #expect((read?["agents"] as? [Any])?.isEmpty == false)
    }

    @Test func aLinkWaitsForTheSheetAndASecondIsBusy() throws {
        let links = Links(), url = try #require(URL(string: "https://example.com/a"))
        var nested: Error?
        let opened = try links.open(url) { _ in
            do { _ = try links.open(url) { _ in true } } catch { nested = error }
            return true
        }
        #expect(opened && (nested as? CodedError)?.code == "BUSY")
        #expect(try links.open(url) { _ in false } == false, "Cancel answers false")
    }

    @Test func threeCancelsStopTheSheetsUntilTheReload() throws {
        let links = Links(), url = try #require(URL(string: "https://example.com/a"))
        var asked = 0
        for _ in 0..<5 { #expect(try links.open(url) { _ in asked += 1; return false } == false) }
        #expect(asked == Links.cancels)
        links.reload()
        #expect(try links.open(url) { _ in asked += 1; return true })
        #expect(asked == Links.cancels + 1)
    }

    /// A sheet that could not be shown (no window, another sheet up) is no Cancel: the page keeps its links.
    @Test func aSheetNotShownIsNoCancel() throws {
        let links = Links(), url = try #require(URL(string: "https://example.com/a"))
        var asked = 0
        for _ in 0..<Links.cancels { #expect(try links.open(url) { _ in asked += 1; return nil } == false) }
        #expect(try links.open(url) { _ in asked += 1; return false } == false)
        #expect(asked == Links.cancels + 1)
    }
}
