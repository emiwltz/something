// Driver: what every launched agent's driver is (design 4.1), and Launched, one agent something launched: its driver
// and its held queue, joined. A driver is a pure function over lines: it reads the program's lines, writes lines
// through the closure it is given, and emits events; it never touches an Agent, and no process is needed to replay it.
// Launched is where the engine and the replays of Tests/Exchanges meet, so both run the same code.
import Foundation
import SomethingCore

/// What a launch asks for. `model` and `mode` are already checked by the bridge (a mode that asks less was confirmed).
public struct Launch: Equatable, Sendable {
    /// The id something gives the agent, opaque to spaces.
    public var agent: String
    public var folder: String
    public var model: String?, mode: String?, effort: String?
    /// The conversation id the program starts with, when the driver picks it before the launch (Claude's --session-id).
    public var thread: String

    public init(agent: String, folder: String, model: String? = nil, mode: String? = nil, effort: String? = nil,
                thread: String = UUID().uuidString.lowercased()) {
        (self.agent, self.folder, self.model, self.mode, self.effort, self.thread) = (agent, folder, model, mode, effort, thread)
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
    /// Answers an open request; returns false when it was no longer open. Throws AGENT_STOPPED.
    func answer(_ request: String, _ answer: Answer) throws -> Bool
    /// The line that asks the program to end by itself, the first step of the stop ladder; nil when closing its
    /// input is the way. Read from any thread: it must not depend on the driver's state.
    var goodbye: Data? { get }
    /// The program ended with `code`; `errors` is the end of its error output.
    func ended(code: Int32, errors: String)
}

extension Driver {
    /// A launched agent before its first event: everything it can do, but for its kind's limits.
    static func fresh(_ launch: Launch) -> Agent {
        var agent = Agent(id: launch.agent, kind: kind, origin: "launched")
        (agent.folder, agent.name, agent.thread) = (launch.folder, (launch.folder as NSString).lastPathComponent, launch.thread)
        var can = Can()
        (can.send, can.steer, can.queue, can.interrupt) = (true, true, true, true)
        (can.model, can.mode, can.effort) = (true, true, true)
        for key in limits.keys {
            switch key {
            case "steer": can.steer = false
            case "queue": can.queue = false
            case "model": can.model = false
            case "mode": can.mode = false
            case "effort": can.effort = false
            default: break
            }
        }
        (agent.can, agent.because) = (can, limits)
        return agent
    }
}

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

    var agent: Agent { queue.fold.agent }

    /// The program started as `pid`: the agent is alive, and the driver writes its first lines. Throws AGENT_STOPPED.
    func begin(pid: Int?) throws {
        record(.started(pid: pid, thread: agent.thread))
        try driver.begin()
    }

    /// Folds one event; a message held for the next turn goes out when the turn it waited for ended.
    func record(_ event: AgentEvent) {
        if let next = queue.record(event, at: now()) {
            // A program that stopped reading takes nothing more; its end comes as `stopped`.
            try? driver.deliver(next.text, steer: false)
        }
        changed()
    }

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

    /// The program ended with `code`. When something asked it to stop, that is no failure, whatever the code.
    func ended(code: Int32, errors: String, asked: Bool) {
        if asked { record(.stopped(nil)) } else { driver.ended(code: code, errors: errors) }
    }

    /// Empties the queue and stops the running turn. Returns whether a turn was running. Throws AGENT_STOPPED.
    func interrupt() throws -> Bool {
        let running = queue.interrupt()
        if running { try driver.interrupt() }
        changed()
        return running
    }
}
