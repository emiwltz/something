// What a space's calls do on this Mac. SomethingCore/Bridge.swift checks each call and decides its answer; this
// BridgeHost acts through the Engine, keeps the space's memory and journal, and asks the person in native windows.
// It also holds the check of a launch's values that both hosts share, so `something check` refuses what the app does.
import Foundation
import SomethingAgents
import SomethingCore
import WebKit

extension SpaceView: BridgeHost, WKScriptMessageHandlerWithReply {
    /// Only the open space's own page is answered, while it is displayed. A launch or a resume waits for its program,
    /// looked for off the main queue (Engine.lookFor), and is refused if the page reloaded or closed in the meantime.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        let loaded = loads
        let answer = { [weak self] in
            guard let self, self.loads == loaded else { return SpaceView.reply(message, open: false, { $0 }, replyHandler) }
            SpaceView.reply(message, open: self.blocked.isEmpty, { Bridge.answer($0, host: self) }, replyHandler)
        }
        guard SpaceView.isSpace(message.frameInfo), blocked.isEmpty, let kind = SpaceView.lookup(message.body, host: self) else { return answer() }
        engine.lookFor(kind, then: answer)
    }

    /// The kind whose program must be found before the call `body` is answered: a launch or a resume the space may
    /// make, of a kind something launches. nil for any other call, which is answered at once.
    static func lookup(_ body: Any, host: BridgeHost) -> String? {
        guard let request = body as? [String: Any], ["launch", "resume"].contains(request["method"] as? String),
              let kind = (request["params"] as? [String: Any])?["kind"] as? String,
              (try? Bridge.launchable(kind, host)) != nil else { return nil }
        return kind
    }

    var state: State { engine.state }

    var assistants: Set<String> { engine.assistants }

    var memory: Memory? { Memory(folder: places.data, space: space.name) }

    func journal(_ line: JournalLine) {
        defer { journaled() }
        do { try Journal(folder: places.journals).append(line, space: space.name) } catch {
            FileHandle.standardError.write(Data("\(error.sentence)\n".utf8))
            unkept()
        }
    }

    func deliver(_ text: String, to agent: Agent, when: String) throws -> String { try engine.deliver(text, to: agent.id, when: when) }

    func interrupt(_ agent: Agent) throws -> Bool { try engine.interrupt(agent.id) }

    func set(_ agent: Agent, model: String?, mode: String?, effort: String?) throws -> String {
        try engine.set(agent.id, model: model, mode: mode, effort: effort)
    }

    func launch(_ kind: String, folder: String, model: String?, mode: String?, effort: String?) throws -> String {
        let id = try engine.launch(kind, folder: folder, model: model, mode: mode, effort: effort)
        launched.insert(id)
        return id
    }

    func resume(_ kind: String, thread: String, of agent: Agent) throws -> String {
        let id = try engine.resume(kind, thread: thread, of: agent.id)
        launched.insert(id)
        return id
    }

    /// One link sheet at a time for this space: a second call while one is open is BUSY. After "Block links until
    /// reload", every link is answered false without a sheet.
    func open(_ url: URL) throws -> Bool {
        guard !linkOpen else { throw CodedError("BUSY", "A link of this space already waits for the person's answer; try again after it.") }
        guard !linksBlocked else { return false }
        linkOpen = true
        defer { linkOpen = false }
        switch ask.link(url, space: title) {
        case .open: return true
        case .cancel: return false
        case .block:
            linksBlocked = true
            return false
        }
    }

    /// A mode that makes the agent ask less waits for the person's click (Engine.lowersAsking says which).
    func confirms(mode: String, kind: String, folder: String?) throws -> Bool {
        try Engine.lowersAsking(mode: mode, kind: kind) ? ask.lowers(mode, kind: kind, folder: folder, space: title) : true
    }
}

extension BridgeHost {
    /// The engine's own check of a launch's values, for the app's window and the check alike: a launch the app
    /// refuses is refused by `something check` too.
    func checkLaunch(_ kind: String, model: String?, mode: String?, effort: String?) throws {
        try Engine.checkLaunch(kind, model: model, mode: mode, effort: effort)
    }
}
