// The engine: every agent on this Mac in one contract 1 State, and the hands on the ones something launched.
// The Mac app holds one Engine and talks to agents only through it. This file is the seam between the app and the
// agents: its public API is what the app may use. It drives the agents something launched (Claude Code so far), on
// the main queue: each one's program through Spawn, its lines through its driver, its events folded by Launched.
// Agents started elsewhere come with the readers (slices 16 to 18); until then resume answers NOT_SUPPORTED.
import Foundation
import SomethingCore

/// What a native window shows for one request. Richer than the contract's `Request`, which a space sees: a space
/// never answers a request, the person does.
public struct Prompt: Equatable, Sendable {
    public var request: Request
    /// For a permission: what the agent wants to run or change, as it sent it (a command, a path, a diff).
    public var input: String?
    /// For a question: what the agent asks, in its order.
    public var questions: [Question]

    public init(request: Request, input: String? = nil, questions: [Question] = []) {
        (self.request, self.input, self.questions) = (request, input, questions)
    }
}

public struct Question: Equatable, Sendable {
    public var header: String?, text: String, options: [String], multiple: Bool
    public init(header: String?, text: String, options: [String], multiple: Bool) {
        (self.header, self.text, self.options, self.multiple) = (header, text, options, multiple)
    }
}

/// The person's answer to a request. Permissions are allowed once or denied, never always.
public enum Answer: Equatable, Sendable {
    case once, deny
    /// For a question: the chosen labels (or the typed text) for each question, in its order.
    case choice([[String]])
}

public final class Engine {
    /// Called on the main queue when the state changed. The app decides how often it pushes.
    public var changed: () -> Void = {}

    /// `environment` is the one agents are started in: the terminal's when something was started from one,
    /// otherwise the app's own, and Programs then reads the login shell's PATH.
    public init(environment: [String: String]) {
        self.environment = environment
        programs = Programs(environment: environment)
    }

    /// The kinds something can launch, by their driver.
    static let drivers: [String: any Driver.Type] = ["claude": ClaudeDriver.self]

    private let environment: [String: String]
    private let programs: Programs
    /// Whether each kind's program was found; empty until `start` looked (main queue only, as all that follows).
    private var installed: [String: Bool] = [:]
    private var looked = false
    /// The agents something launched, in launch order, with their program.
    private var launched: [(agent: Launched, spawn: Spawn)] = []
    /// The agents whose stop something asked for: their end is no failure.
    private var stopping: Set<String> = []
    private var count = 0

    /// Starts watching this Mac. `often` is true while a space is open.
    public func start(often: Bool) {
        guard !looked else { return }
        looked = true
        // Reading the login shell can take 3 s: never on the main queue.
        DispatchQueue.global().async { [self] in
            let found = Dictionary(uniqueKeysWithValues: Programs.kinds.compactMap { kind in programs.installed(kind).map { (kind, $0) } })
            DispatchQueue.main.async { [self] in installed = found; changed() }
        }
    }

    /// The whole state, before any space's scope is applied.
    public var state: State {
        let kinds = ["claude", "codex", "opencode", "pi", "omp"].map { kind in
            (kind, Kind(launch: Engine.drivers[kind] != nil, installed: installed[kind], tested: Engine.drivers[kind]?.tested ?? "none",
                        seen: nil, reader: "none", note: nil))
        }
        let folds = launched.map(\.agent.queue.fold)
        return State(at: Engine.now(), kinds: Dictionary(uniqueKeysWithValues: kinds), agents: folds.map(\.agent),
                     threads: folds.compactMap(\.thread), requests: folds.flatMap(\.requests))
    }

    /// Per kind, the `can` entries that are always false here: `granted.limits` of contract 4.2.
    public var limits: [String: [String]] { Engine.drivers.mapValues { $0.limits.keys.sorted() } }

    /// The details of an open request, or nil once it closed (the app then closes its window).
    public func prompt(_ request: String) -> Prompt? { launched.lazy.compactMap { $0.agent.prompt(request) }.first }

    /// The person's answer, from a native window. A request that closed meanwhile is left as it is, and so is one
    /// the answer does not fit (its window stays open).
    public func answer(_ request: String, _ answer: Answer) {
        guard let agent = launched.first(where: { $0.agent.prompt(request) != nil })?.agent else { return }
        _ = try? agent.answer(request, answer)
    }

    // What a space asks through the bridge (SomethingCore/Bridge.swift checked the call first). Each throws a
    // `CodedError` with a code of contract 4.3.

    /// Returns the delivery: "started", "steered" or "queued". Throws AGENT_NOT_FOUND, AGENT_STOPPED, BAD_PARAMS.
    public func deliver(_ text: String, to agent: String, when: String) throws -> String { try running(agent).send(text, when: when) }

    /// Returns whether a turn was running; the queue is emptied either way. Throws AGENT_NOT_FOUND, AGENT_STOPPED.
    public func interrupt(_ agent: String) throws -> Bool { try running(agent).interrupt() }

    /// Returns "now" or "next-turn". Throws AGENT_NOT_FOUND, AGENT_STOPPED, NOT_SUPPORTED.
    public func set(_ agent: String, model: String?, mode: String?, effort: String?) throws -> String {
        let applied = try running(agent).driver.set(model: model, mode: mode, effort: effort)
        changed()
        return applied
    }

    /// Starts an agent of `kind` in `folder` and returns its id. Throws NOT_SUPPORTED for a kind without a driver or
    /// a value its kind never takes, BAD_PARAMS for an empty model or one that starts with "-", VALUE_NOT_OFFERED for a
    /// mode it does not offer (never one that skips every permission), NOT_INSTALLED, INTERPRETER_NOT_FOUND,
    /// LAUNCH_FAILED.
    public func launch(_ kind: String, folder: String, model: String?, mode: String?, effort: String?) throws -> String {
        guard let type = Engine.drivers[kind] else { throw CodedError("NOT_SUPPORTED", "something cannot launch \(kind) yet.") }
        for (key, value) in [("model", model), ("mode", mode), ("effort", effort)] where value != nil {
            if let because = type.limits[key] { throw CodedError("NOT_SUPPORTED", because) }
        }
        if let model, model.isEmpty || model.hasPrefix("-") {
            throw CodedError("BAD_PARAMS", "model is a model's name, such as one of the agent's options.model.")
        }
        if let mode, !type.modes.contains(where: { $0.value == mode }) {
            throw CodedError("VALUE_NOT_OFFERED", "\(mode) is not a mode something offers for \(kind); pick one of \(type.modes.map(\.value).joined(separator: ", ")).")
        }
        let program = try programs.find(kind)
        count += 1
        let launch = Launch(agent: "\(kind)-\(count)", folder: folder, model: model, mode: mode, effort: effort)
        let command = type.command(launch)
        let spawn = Spawn(path: program.path, arguments: command.arguments, folder: folder,
                          environment: program.environment(environment, adding: command.adding, removing: command.removing))
        let agent = try Engine.start(type, launch, spawn) { [weak self] id in self?.stopping.contains(id) == true }
        agent.changed = { [weak self] in self?.changed() }
        launched.append((agent, spawn))
        changed()
        return launch.agent
    }

    public func resume(_ kind: String, thread: String, of agent: String) throws -> String { throw Engine.notYet }

    /// Stops every agent something launched, all at once, within `seconds`, then calls `done` on the main queue.
    public func stopAll(within seconds: TimeInterval, done: @escaping () -> Void) {
        stopping.formUnion(launched.map(\.agent.agent.id))
        Spawn.stopAll(launched.map(\.spawn), cap: seconds) { DispatchQueue.main.async(execute: done) }
    }

    /// Starts `spawn` for one launch and joins it to its driver: lines and the end come back on the main queue.
    /// `asked` says, on the main queue, whether something asked this agent to stop; `record` sees every line, in
    /// (true) and out (false), for `something try --record`. Throws as Spawn.start does, and AGENT_STOPPED when the
    /// program closed its input at once.
    static func start(_ type: any Driver.Type, _ launch: Launch, _ spawn: Spawn, asked: @escaping (String) -> Bool,
                      record: ((_ written: Bool, _ line: Data) -> Void)? = nil) throws -> Launched {
        let agent = Launched(type, launch, write: { [weak spawn] line in
            guard let spawn else { throw CodedError("AGENT_STOPPED", "The agent has ended; launch or resume it to go on.") }
            try spawn.write(line)
            record?(true, line)
        }, now: Engine.now)
        let goodbye = agent.driver.goodbye
        spawn.graceful = { [weak spawn] in
            guard let spawn, let goodbye, (try? spawn.write(goodbye)) != nil else { return }
            record?(true, goodbye)
            // Spawn gives this step 3 s at most: the program's own exit is waited for within them.
            while spawn.running { usleep(20_000) }
        }
        try spawn.start(lines: { line in DispatchQueue.main.async { record?(false, line); agent.driver.receive(line) } },
                        ended: { [weak spawn] code in
                            let errors = spawn?.errorTail ?? ""
                            DispatchQueue.main.async { agent.ended(code: code, errors: errors, asked: asked(launch.agent)) }
                        })
        try agent.begin(pid: Int(spawn.pid))
        return agent
    }

    /// The launched agent `id`, while its program runs.
    private func running(_ id: String) throws -> Launched {
        guard let found = launched.first(where: { $0.agent.agent.id == id }) else {
            throw CodedError("AGENT_NOT_FOUND", "No agent \(id) was launched by something; use an id from the latest state.")
        }
        guard found.agent.agent.alive != false else { throw CodedError("AGENT_STOPPED", "The agent has ended; launch or resume it to go on.") }
        return found.agent
    }

    static func now() -> String { ISO8601DateFormatter().string(from: Date()) }

    static let notYet = CodedError("NOT_SUPPORTED", "something cannot continue a conversation here yet.")
}

/// `something hook permission --spool <dir>`: Claude's plan B (design 4.1). Returns the exit status.
public enum PermissionHook {
    public static func main(_ arguments: [String]) -> Int32 { 2 }
}

/// `something try <kind> [--record <file>] [--plan-b]`: a developer's trial of one driver against a real agent.
public enum Trial {
    public static func main(_ arguments: [String]) -> Int32 {
        FileHandle.standardError.write(Data("something try: no driver yet.\n".utf8))
        return 2
    }
}
