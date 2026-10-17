// What a space's calls do on this Mac. SomethingCore/Bridge.swift checks each call and decides its answer; this
// BridgeHost acts through the Engine, keeps the space's memory and journal, and asks the person in native windows.
import Foundation
import SomethingAgents
import SomethingCore
import WebKit

extension SpaceWindow: BridgeHost, WKScriptMessageHandlerWithReply {
    /// Modes that make an agent ask less (design 3.3), which always open a confirmation. The Engine does not say
    /// which they are yet, so the app keeps the list until it does.
    static let lowering: [String: Set<String>] = ["claude": ["acceptEdits", "auto", "dontAsk", "bypassPermissions"], "codex": ["never"]]

    /// Only the page of the open space is answered (contract 4.4): never a frame inside it, never another address.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        let from = message.frameInfo.request.url
        guard message.frameInfo.isMainFrame, from?.scheme == Scheme.name, from?.host == Scheme.host, blocked.isEmpty,
              let request = message.body as? [String: Any] else {
            return replyHandler(nil, "something answers only the page of the open space.")
        }
        replyHandler(Bridge.answer(request, host: self), nil)
    }

    var state: State { engine.state }

    var memory: Memory? { kept ? Memory(folder: places.data, space: space.name) : nil }

    func journal(_ line: JournalLine) {
        guard kept else { return }
        do { try Journal(folder: places.journals).append(line, space: space.name) } catch {
            FileHandle.standardError.write(Data("\((error as? SpaceError)?.message ?? "\(error)")\n".utf8))
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

    /// One link window at a time for this space: a second call while one is open is BUSY. After "Block links until
    /// reload", every link is answered false without a window.
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

    func confirms(mode: String, kind: String) -> Bool {
        SpaceWindow.lowering[kind]?.contains(mode) != true || ask.lowers(mode, kind: kind, space: title)
    }
}
