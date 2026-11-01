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
            SpaceView.reply(message, open: self.blocked.isEmpty, { self.readOnly ? SpaceView.compared($0, host: self) : Bridge.answer($0, host: self) },
                            replyHandler)
        }
        guard SpaceView.isSpace(message.frameInfo), blocked.isEmpty, !readOnly, let kind = SpaceView.lookup(message.body, host: self) else { return answer() }
        engine.lookFor(kind, then: answer)
    }

    /// The answer to an older version shown to compare (Glimpse.swift): the state and the memory read as the open
    /// space's, and every other call refused here, before the core, so that nothing acts and the space's journal gets
    /// no line.
    static func compared(_ request: [String: Any], host: BridgeHost) -> [String: Any] {
        guard !["state", "store.get"].contains(request["method"] as? String ?? "") else { return Bridge.answer(request, host: host) }
        return ["id": request["id"] ?? NSNull(), "error": ["code": "NOT_SUPPORTED", "message": "This is an older version of the space, shown to compare: it cannot act."]]
    }

    /// The kind whose program must be found before the call `body` is answered: a launch or a resume the space may
    /// make, of a kind something launches. nil for any other call, which is answered at once.
    static func lookup(_ body: Any, host: BridgeHost) -> String? {
        guard let request = body as? [String: Any], ["launch", "resume"].contains(request["method"] as? String),
              let kind = (request["params"] as? [String: Any])?["kind"] as? String,
              (try? Bridge.launchable(kind, host)) != nil else { return nil }
        return kind
    }

    var state: State {
        var state = engine.state
        if let stagedAt { state.at = stagedAt }
        return state
    }

    var assistants: Set<String> { engine.assistants }

    var memory: Memory? { Memory(folder: places.data, space: space.name) }

    func journal(_ line: JournalLine) {
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
        // What the person chose in the sentence, for a launch whose page names none.
        let start = (try? Grants(places.grants).read().spaces[space.name]?.start).flatMap { $0 }.flatMap { $0.kind == kind ? $0 : nil }
        let id = try engine.launch(kind, folder: folder, model: model ?? start?.model, mode: mode, effort: effort ?? start?.effort)
        launched.insert(id)
        return id
    }

    func resume(_ kind: String, thread: String, of agent: Agent) throws -> String {
        let id = try engine.resume(kind, thread: thread, of: agent.id)
        launched.insert(id)
        return id
    }

    func open(_ url: URL) throws -> Bool { try links.open(url) { ask.link($0, space: title) } }

    /// A mode that makes the agent ask less waits for the person's click (Registry.lowersAsking says which).
    func confirms(mode: String, kind: String, folder: String?) throws -> Bool {
        try Registry.app.lowersAsking(mode: mode, kind: kind) ? ask.lowers(mode, kind: kind, folder: folder, space: title) : true
    }
}

/// A space's links: one sheet at a time, and after three Cancels in one load no more sheets until the page reloads,
/// so a page cannot keep asking. A sheet that could not be shown is no Cancel: the person did not answer it. A class:
/// the person's answer comes back while a second call may already be here.
final class Links {
    static let cancels = 3
    private var waiting = false, cancelled = 0

    /// Asks again from the next load.
    func reload() { cancelled = 0 }

    /// What `ask` answered for `url`, false when it showed no sheet (nil), and false without asking after three
    /// Cancels. Throws BUSY while another link waits.
    func open(_ url: URL, ask: (URL) -> Bool?) throws -> Bool {
        guard !waiting else { throw CodedError("BUSY", "A link of this space already waits for the person's answer; try again after it.") }
        guard cancelled < Self.cancels else { return false }
        waiting = true
        defer { waiting = false }
        switch ask(url) {
        case true?: return true
        case false?: cancelled += 1; return false
        case nil: return false
        }
    }
}

extension BridgeHost {
    /// The registry's check of a launch's values, for the app's window and the check alike: a launch the app
    /// refuses is refused by `something check` too.
    func checkLaunch(_ kind: String, model: String?, mode: String?, effort: String?) throws {
        try Registry.app.checkLaunch(kind, model: model, mode: mode, effort: effort)
    }
}
