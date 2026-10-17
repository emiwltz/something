// What a space's calls do on this Mac. SomethingCore/Bridge.swift checks each call and decides its answer; this
// BridgeHost acts through the Engine, keeps the space's memory and journal, and asks the person in native windows.
import Foundation
import SomethingAgents
import SomethingCore
import WebKit

extension SpaceWindow: BridgeHost, WKScriptMessageHandlerWithReply {
    /// The modes of each kind whose modes are levels of asking (design 3.3): a mode that keeps asking passes, one that
    /// lowers asking opens a confirmation, and any other is refused, so a misspelt or a new mode never passes unseen.
    /// `bypassPermissions` is in neither list: it is never offered. OpenCode's modes are its agents (build, plan, the
    /// person's own), not levels of asking; pi takes no mode. The Engine does not say these yet, so the app keeps them.
    static let modes: [String: (keeps: Set<String>, lowers: Set<String>)] = [
        "claude": (keeps: ["default", "manual", "plan"], lowers: ["acceptEdits", "auto", "dontAsk"]),
        "codex": (keeps: ["untrusted", "on-request"], lowers: ["never"]),
    ]

    /// What the agents of each kind can never do here (contract 3.7, the false columns), for `granted.limits`. The
    /// Engine does not say it yet, so the app keeps the table until it does.
    static let limits: [String: [String]] = ["claude": ["effort"], "opencode": ["steer"], "pi": ["mode"]]

    /// Only the page of the open space is answered (contract 4.4): never a frame inside it, never the app's page.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard isSpace(message.frameInfo), blocked.isEmpty,
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

    func confirms(mode: String, kind: String, folder: String?) throws -> Bool {
        try SpaceWindow.lowers(mode, kind: kind) ? ask.lowers(mode, kind: kind, folder: folder, space: title) : true
    }

    /// Whether `mode` makes agents of `kind` ask less, so the person must confirm it. Throws a `CodedError`
    /// (VALUE_NOT_OFFERED) for a mode something never offers.
    static func lowers(_ mode: String, kind: String) throws -> Bool {
        guard let known = modes[kind], !known.keeps.contains(mode) else { return false }
        guard known.lowers.contains(mode) else {
            throw CodedError("VALUE_NOT_OFFERED", "\(mode) is not a mode something offers for \(kind); pick one from options.mode in the state.")
        }
        return true
    }
}
