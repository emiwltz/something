// Driver: what every launched agent's driver is (design 4.1), and Launched, one agent something launched: its driver
// and its held queue, joined. A driver is a pure function over lines: it reads the program's lines, writes lines
// through the closure it is given, and emits events; it never touches an Agent, and no process is needed to replay it.
// Launched is where the engine and the replays of Tests/Exchanges meet, so both run the same code.
import Foundation
import SomethingCore

/// What a launch asks for. The bridge confirmed a mode that asks less; Engine.launch checked that the mode is offered
/// and that the model is no empty word and no option.
public struct Launch: Equatable, Sendable {
    /// The id something gives the agent, opaque to spaces.
    public var agent: String
    public var folder: String
    public var model: String?, mode: String?, effort: String?
    /// The conversation id the program starts with, when the driver picks it before the launch (Claude's --session-id),
    /// or the one it continues when `resume` is true.
    public var thread: String
    /// Whether the launch continues the conversation `thread` instead of starting one.
    public var resume: Bool

    public init(agent: String, folder: String, model: String? = nil, mode: String? = nil, effort: String? = nil,
                thread: String = UUID().uuidString.lowercased(), resume: Bool = false) {
        self.agent = agent
        self.folder = folder
        self.model = model
        self.mode = mode
        self.effort = effort
        self.thread = thread
        self.resume = resume
    }
}

/// The program's arguments for a launch, and what the launch changes in the person's environment.
public struct Command: Equatable, Sendable {
    public var arguments: [String]
    public var adding: [String: String] = [:]
    public var removing: Set<String> = []
}

public protocol Driver: AnyObject {
    static var kind: String { get }
    /// The newest version of the program this driver was proven on (`kinds.<kind>.tested`).
    static var tested: String { get }
    /// The `can` entries that are always false for this kind, each with its sentence (`because`, `granted.limits`).
    static var limits: [String: String] { get }
    /// The modes a launch or `set` may choose; empty when the kind has none.
    static var modes: [Option] { get }
    /// Whether an effort can be set only when `options.effort` lists levels; false by default.
    static var effortOnlyWhenOffered: Bool { get }
    /// Whether the launch picks the conversation id (`Launch.thread`) for the program; true by default. When false,
    /// the thread is unknown until the program names it, unless the launch resumes one.
    static var picksThread: Bool { get }
    static func command(_ launch: Launch) -> Command

    /// `write` hands one whole line (without its newline) to the program and throws AGENT_STOPPED once it no longer
    /// reads; `emit` takes what happened; `now` is the time of each item and request (ISO 8601).
    init(_ launch: Launch, write: @escaping (Data) throws -> Void, emit: @escaping (AgentEvent) -> Void, now: @escaping () -> String)
    /// Writes what the program needs before the first message. Throws AGENT_STOPPED.
    func begin() throws
    /// Reads one line of the program's output; lines it does not know change nothing.
    func receive(_ line: Data)
    /// Hands a message to the program: into the running turn when `steer`, else as a new turn. Throws AGENT_STOPPED.
    func deliver(_ text: String, steer: Bool) throws
    /// Stops the running turn and drops what the program itself holds. Throws AGENT_STOPPED.
    func interrupt() throws
    /// Asks for new values; the state shows them once the agent confirms. Returns when they apply. Throws
    /// AGENT_STOPPED, or NOT_SUPPORTED for a key in `limits`.
    func set(model: String?, mode: String?, effort: String?) throws -> String
    /// What a native window shows for an open request; nil once it closed.
    func prompt(_ request: String) -> Prompt?
    /// Answers an open request; returns false when it was no longer open. Throws AGENT_STOPPED, or BAD_PARAMS for an
    /// answer that does not fit the request (a choice with one entry per question).
    func answer(_ request: String, _ answer: Answer) throws -> Bool
    /// The line that asks the program to end by itself, the first step of the stop ladder; nil when closing its
    /// input is the way. Read from any thread: it must not depend on the driver's state.
    var goodbye: Data? { get }
    /// The program ended with `code`; `errors` is the end of its error output.
    func ended(code: Int32, errors: String)
}

extension Driver {
    public static var effortOnlyWhenOffered: Bool { false }
    public static var picksThread: Bool { true }

    /// A launched agent before its first event: everything it can do, but for its kind's limits.
    static func fresh(_ launch: Launch) -> Agent {
        var agent = Agent(id: launch.agent, kind: kind, origin: "launched")
        agent.folder = launch.folder
        agent.name = (launch.folder as NSString).lastPathComponent
        agent.thread = picksThread || launch.resume ? launch.thread : nil
        var can = Can()
        for key in ["send", "steer", "queue", "interrupt", "model", "mode", "effort"] { can[keyPath: canKeys[key]!] = true }
        // A key outside `canKeys` is a typo in a driver: it must fail the tests, not be dropped.
        for key in limits.keys { can[keyPath: canKeys[key]!] = false }
        agent.can = can
        agent.because = limits
        return agent
    }
}

/// Each `can` entry by its name in the contract. `resume` is false here: a launched agent is running.
let canKeys: [String: WritableKeyPath<Can, Bool>] = ["send": \.send, "steer": \.steer, "queue": \.queue, "interrupt": \.interrupt,
                                                    "model": \.model, "mode": \.mode, "effort": \.effort, "resume": \.resume]

/// One agent something launched: its driver and its held queue, on one queue (the engine's main queue). Events from
/// the driver are folded here, and a held message goes out when a turn ends.
final class Launched {
    let driver: Driver
    private(set) var queue: HeldQueue
    /// Called after each event, so the engine can push the state.
    var changed: () -> Void = {}
    private let now: () -> String

    init<D: Driver>(_ type: D.Type, _ launch: Launch, write: @escaping (Data) throws -> Void, now: @escaping () -> String) {
        self.now = now
        queue = HeldQueue(Fold(D.fresh(launch)))
        var emit: (AgentEvent) -> Void = { _ in }
        driver = D(launch, write: write, emit: { emit($0) }, now: now)
        emit = { [weak self] event in self?.record(event) }
    }

    /// The agent as the state shows it: the fold's, with `can.effort` false while no effort is offered to a kind
    /// that takes only those (contract: `can` says what a call would do now).
    var agent: Agent {
        var agent = queue.fold.agent
        if type(of: driver).effortOnlyWhenOffered, agent.can.effort, agent.options.effort == nil {
            agent.can.effort = false
            agent.because["effort"] = "This model offers no effort level."
        }
        return agent
    }

    /// The program started as `pid`: the agent is alive, and the driver writes its first lines. Throws AGENT_STOPPED.
    func begin(pid: Int?) throws {
        record(.started(pid: pid, thread: agent.thread))
        try driver.begin()
    }

    /// Folds one event; a message held for the next turn goes out when the turn it waited for ended.
    func record(_ event: AgentEvent) {
        if let next = queue.record(event, at: now()) {
            do { try driver.deliver(next.text, steer: false) } catch {
                // The program stopped reading; its end comes as `stopped`, but the message must not vanish unsaid.
                _ = queue.record(.error(AgentError(code: "AGENT_ERROR", message: "The held message “\(Launched.short(next.text))” was not sent: the agent stopped reading.")), at: now())
            }
        }
        changed()
    }

    /// What a native window shows for `request`, while the state still lists it: a request the fold closed (the
    /// agent stopped, Claude withdrew it) is closed, whatever the driver still holds.
    func prompt(_ request: String) -> Prompt? {
        guard queue.fold.requests.contains(where: { $0.id == request }) else { return nil }
        return driver.prompt(request)
    }

    /// Answers `request` when it is still open. Returns false when it was not. Throws as Driver.answer.
    func answer(_ request: String, _ answer: Answer) throws -> Bool {
        guard prompt(request) != nil else { return false }
        return try driver.answer(request, answer)
    }

    /// The start of a message, to name it in a sentence.
    static func short(_ text: String) -> String { text.count > 40 ? String(text.prefix(40)) + "…" : text }

    /// `send` of contract 4.1. Returns the delivery. Throws AGENT_STOPPED, BAD_PARAMS for an unknown `when`.
    func send(_ text: String, when: String) throws -> String {
        let delivery = try queue.send(text, when: when, at: now())
        switch delivery {
        case .started: try driver.deliver(text, steer: false)
        case .steered: try driver.deliver(text, steer: true)
        case .queued: break
        }
        changed()
        return delivery.rawValue
    }

    /// The program ended with `code`. When something asked it to stop, that is no failure, whatever the code; an
    /// OpenCode that still marks its conversation as running is said even then.
    func ended(code: Int32, errors: String, asked: Bool) {
        guard asked else { return driver.ended(code: code, errors: errors) }
        record(.stopped(nil))
        (driver as? ACPDriver)?.checkClaim()
    }

    /// Empties the queue and stops the running turn. Returns whether a turn was running. Throws AGENT_STOPPED.
    func interrupt() throws -> Bool {
        let running = queue.interrupt()
        if running { try driver.interrupt() }
        changed()
        return running
    }
}
