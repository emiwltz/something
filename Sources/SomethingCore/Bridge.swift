// The bridge a space talks through (contract 4): one call in, one answer out. It checks the params, the right, the
// scope and what the agent can do, then asks the shell (BridgeHost) to act, and writes a journal line for every write
// action, failed or not. The transport is the shell's (WebKit's message handler on the Mac); the answers are decided here.
import Foundation

/// What the shell around the core provides. Each method acts once the bridge has checked the call, and throws a
/// `CodedError` with a code of contract 4.3 when it cannot (any other error is answered as AGENT_ERROR).
public protocol BridgeHost: AnyObject {
    /// The whole state, before the space's scope is applied.
    var state: State { get }
    var granted: Granted { get }
    /// The agents this space launched or resumed: always in its scope.
    var launched: Set<String> { get }
    /// The space's memory; nil for a space opened by path, outside the spaces folder, which has none.
    var memory: Memory? { get }
    /// Keeps one line of the space's journal; a journal that cannot be written must not fail the call it records.
    func journal(_ line: JournalLine)
    /// Hands `text` to the agent now (`when` "now": steer) or holds it for the next turn ("next"); returns the delivery.
    func deliver(_ text: String, to agent: Agent, when: String) throws -> String
    /// Stops the running turn and empties the agent's queue; returns false when no turn was running.
    func interrupt(_ agent: Agent) throws -> Bool
    /// Asks the agent to change; returns "now" or "next-turn".
    func set(_ agent: Agent, model: String?, mode: String?, effort: String?) throws -> String
    /// Starts an agent in `folder` (absolute, checked) and returns its id.
    func launch(_ kind: String, folder: String, model: String?, mode: String?, effort: String?) throws -> String
    /// Continues the conversation `thread`, which `agent` holds in the state, here; returns the new agent's id.
    func resume(_ kind: String, thread: String, of agent: Agent) throws -> String
    /// Asks the person in a native window whether to open `url`; true when they opened it.
    func open(_ url: URL) throws -> Bool
    /// true when `mode` does not make agents of `kind` ask less, or the person confirmed it in a native window that
    /// names the agent's `folder`. Throws a `CodedError` (VALUE_NOT_OFFERED) for a mode something never offers.
    func confirms(mode: String, kind: String, folder: String?) throws -> Bool
    /// Returns when the engine would try this launch; throws the `CodedError` its launch would give for these values,
    /// so that no window asks the person about a launch that cannot happen.
    func checkLaunch(_ kind: String, model: String?, mode: String?, effort: String?) throws
}

public enum Bridge {
    static let writes: Set = ["send", "interrupt", "set", "launch", "resume", "open"]

    /// The answer to one request of the page, `{id, result}` or `{id, error: {code, message}}`. Never throws.
    public static func answer(_ request: [String: Any], host: BridgeHost) -> [String: Any] {
        let method = request["method"] as? String ?? "", params = request["params"] as? [String: Any] ?? [:]
        var line = Line(agent: params["agent"] as? String, kind: params["kind"] as? String)
        var answer: [String: Any] = ["id": request["id"] ?? NSNull()]
        do {
            if let contract = request["contract"], contract as? Int != 1 { throw CodedError("BAD_PARAMS", "This engine speaks contract 1, not contract \(contract).") }
            answer["result"] = try call(method, Params(values: params), host, &line)
        } catch {
            // Any other error's words may hold a path of this Mac, which a space must not learn.
            let coded = error as? CodedError ?? CodedError("AGENT_ERROR", "something could not do this on this Mac; try again.")
            answer["error"] = ["code": coded.code, "message": coded.message]
            line.result = coded.code
        }
        if writes.contains(method) {
            host.journal(JournalLine(at: ISO8601DateFormatter().string(from: Date()), action: method, agent: line.agent, kind: line.kind,
                                     when: line.when, text: line.text, result: line.result))
        }
        return answer
    }

    /// What the journal line will say, filled as the call learns it.
    struct Line { var agent: String?, kind: String?, when: String?, text: String?, result = "ok" }

    static func call(_ method: String, _ p: Params, _ host: BridgeHost, _ line: inout Line) throws -> Any {
        let granted = host.granted
        switch method {
        case "state":
            return try JSONSerialization.jsonObject(with: visible(host).json())
        case "send":
            let id = try p.string("agent"), text = try p.string("text"), when = try p.optional("when") ?? "next"
            (line.when, line.text) = (when, text)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CodedError("BAD_PARAMS", "send needs a text that is not empty.") }
            guard when == "next" || when == "now" else { throw CodedError("BAD_PARAMS", "when is \"next\" or \"now\", not \"\(when)\".") }
            let agent = try writable(id, host, &line)
            // An idle agent starts a turn with either `when` (contract 4.1); steer and queue only matter during a turn.
            try able(agent, "send"); if ["working", "waiting"].contains(agent.state) { try able(agent, when == "now" ? "steer" : "queue") }
            return ["delivery": try host.deliver(text, to: agent, when: when)]
        case "interrupt":
            let agent = try writable(try p.string("agent"), host, &line); try able(agent, "interrupt")
            return ["interrupted": try host.interrupt(agent)]
        case "set":
            let id = try p.string("agent"), model = try p.optional("model"), mode = try p.optional("mode"), effort = try p.optional("effort")
            let values = [("model", model), ("mode", mode), ("effort", effort)].compactMap { key, value in value.map { (key, $0) } }
            guard !values.isEmpty else { throw CodedError("BAD_PARAMS", "set needs at least one of model, mode or effort.") }
            line.text = values.map { "\($0)=\($1)" }.joined(separator: " ")
            let agent = try writable(id, host, &line)
            for (key, value) in values {
                try able(agent, key)
                let offered = key == "model" ? agent.options.model : key == "mode" ? agent.options.mode : agent.options.effort
                guard offered?.contains(where: { $0.value == value }) == true else {
                    throw CodedError("VALUE_NOT_OFFERED", "\(value) is not a \(key) this agent offers; pick one from options.\(key) in the state.")
                }
            }
            if let mode { try confirm(mode, agent.kind, agent.folder, host) }
            return ["applied": try host.set(agent, model: model, mode: mode, effort: effort)]
        case "launch":
            let kind = try p.string("kind"), folder = try p.optional("folder"), model = try p.optional("model"), mode = try p.optional("mode"), effort = try p.optional("effort")
            line.text = folder
            try launchable(kind, host)
            guard let root = granted.folder else { throw CodedError("FOLDER_NOT_GRANTED", "No folder was granted for launches; the person chooses one when the space asks for a launch right.") }
            let target = folder ?? root
            guard target.hasPrefix("/") else { throw CodedError("BAD_PARAMS", "folder is an absolute path, for example something.granted.folder + \"/web\".") }
            guard Rights.inside(target, root) else { throw CodedError("FOLDER_NOT_GRANTED", "\(target) is outside the folder granted for launches, \(root).") }
            let limits = granted.limits[kind] ?? [], given = [("model", model), ("mode", mode), ("effort", effort)]
            if let (key, _) = given.first(where: { $1 != nil && limits.contains($0) }) { throw CodedError("NOT_SUPPORTED", "\(kind) agents take no \(key) here; launch without it.") }
            try host.checkLaunch(kind, model: model, mode: mode, effort: effort)
            if let mode { try confirm(mode, kind, target, host) }
            line.agent = try host.launch(kind, folder: target, model: model, mode: mode, effort: effort)
            return line.agent!
        case "resume":
            let kind = try p.string("kind"), thread = try p.string("thread")
            line.text = thread
            try launchable(kind, host)
            guard let agent = visible(host).agents.first(where: { $0.thread == thread && $0.kind == kind }) else { throw CodedError("THREAD_NOT_FOUND", "No \(kind) conversation \(thread) in this space; use a thread id from the latest state.") }
            guard agent.can.resume else { throw CodedError(agent.alive == true ? "STILL_RUNNING" : "NOT_SUPPORTED", agent.because["resume"] ?? "This conversation cannot be continued here.") }
            guard let root = granted.folder, let folder = agent.folder, Rights.inside(folder, root) else {
                throw CodedError("FOLDER_NOT_GRANTED", "This conversation works in \(agent.folder ?? "an unknown folder"), outside the folder granted for launches.")
            }
            line.agent = try host.resume(kind, thread: thread, of: agent)
            return line.agent!
        case "store.get", "store.set":
            let path = try p.string("path")
            guard Rights.covers(granted.rights, "store") else { throw CodedError("RIGHT_NOT_GRANTED", "The store right was not granted; read something.granted before using the memory.") }
            guard let memory = host.memory else { throw CodedError("RIGHT_NOT_GRANTED", "This space is not in the spaces folder, so it has no memory.") }
            do {
                if method == "store.get" { return try memory.get(path) ?? NSNull() }
                guard let value = p.values["value"] else { throw CodedError("BAD_PARAMS", "store.set needs a value; null removes the key.") }
                try memory.set(path, value)
                return NSNull()
            } catch is SpaceError {
                // Contract 1 has no code for a memory file the disk will not read or write. Memory's own words name
                // the file's path, which a space must not learn (it could keep it, and an export would carry it).
                throw CodedError("STORE_FULL", "This space's memory cannot be read or written on this Mac.")
            }
        case "open":
            let text = try p.string("url")
            line.text = text
            guard let url = URL(string: text), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { throw CodedError("BAD_PARAMS", "open takes an https:, http: or mailto: link, not \(text).") }
            return try host.open(url)
        default:
            throw CodedError("UNKNOWN_METHOD", "\(method.isEmpty ? "A call without a method" : method) is not a function of contract 1. Known: state, send, interrupt, set, launch, resume, store.get, store.set, open.")
        }
    }

    /// The state as this space sees it.
    static func visible(_ host: BridgeHost) -> State { Rights.visible(host.state, host.granted, launched: host.launched) }

    /// The agent `id` when this space may write to it. A space without any send right learns nothing about ids;
    /// an agent out of scope is reported as not found, so a space cannot probe for it.
    static func writable(_ id: String, _ host: BridgeHost, _ line: inout Line) throws -> Agent {
        let rights = host.granted.rights
        guard rights.contains(where: { $0 == "send" || $0.hasPrefix("send:") }) else { throw CodedError("RIGHT_NOT_GRANTED", "The send right was not granted; read something.granted before writing to an agent.") }
        guard let agent = visible(host).agents.first(where: { $0.id == id }) else { throw CodedError("AGENT_NOT_FOUND", "No agent \(id) in this space; use an id from the latest state.") }
        line.kind = agent.kind
        guard Rights.covers(rights, "send:\(agent.kind)") else { throw CodedError("RIGHT_NOT_GRANTED", "The right send:\(agent.kind) was not granted.") }
        guard agent.origin == "launched" else {
            throw CodedError("READ_ONLY_AGENT", agent.because["send"] ?? "This agent was started outside something; something only reads it.")
        }
        guard agent.alive != false else { throw CodedError("AGENT_STOPPED", "This agent has ended; launch or resume one to go on.") }
        return agent
    }

    static func able(_ agent: Agent, _ key: String) throws {
        let can = agent.can, all = ["send": can.send, "steer": can.steer, "queue": can.queue, "interrupt": can.interrupt, "model": can.model, "mode": can.mode, "effort": can.effort]
        guard all[key] == true else { throw CodedError("NOT_SUPPORTED", agent.because[key] ?? "This agent cannot do this: its can.\(key) is false.") }
    }

    static func launchable(_ kind: String, _ host: BridgeHost) throws {
        guard Rights.covers(host.granted.rights, "launch:\(kind)") else { throw CodedError("RIGHT_NOT_GRANTED", "The right launch:\(kind) was not granted.") }
        guard let known = host.state.kinds[kind] else { throw CodedError("BAD_PARAMS", "\(kind) is not a kind; the state's kinds lists them.") }
        guard known.launch else { throw CodedError("NOT_SUPPORTED", known.note ?? "something cannot launch \(kind).") }
        guard known.installed != false else { throw CodedError("NOT_INSTALLED", "\(kind) was not found on this Mac; install it, then try again.") }
    }

    static func confirm(_ mode: String, _ kind: String, _ folder: String?, _ host: BridgeHost) throws {
        if try !host.confirms(mode: mode, kind: kind, folder: folder) { throw CodedError("REFUSED", "The person did not allow the mode \(mode).") }
    }
}

/// The params of one call, read with their types.
struct Params {
    let values: [String: Any]
    func string(_ key: String) throws -> String {
        guard let value = values[key] as? String else { throw CodedError("BAD_PARAMS", "\(key) is missing or is not a string.") }
        return value
    }
    /// The string at `key`, or nil when it is absent or null.
    func optional(_ key: String) throws -> String? { values[key] == nil || values[key] is NSNull ? nil : try string(key) }
}
