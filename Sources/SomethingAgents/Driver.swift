// Driver: what every launched agent's driver is, with what the person's windows show of a request and their answer
// (Prompt, Answer), the handle on its program (ProcessHandle), and Launched, one agent something launched: its driver
// and its held queue, joined. A driver is a pure function over lines: it reads the program's lines, writes lines
// through the closure it is given, and emits events; it never touches an Agent, and no process is needed to replay
// it. Launched is where the engine and the replays of Tests/Exchanges meet, so both run the same code.
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
    /// How the person's assistant works, when this is it: launched by the app alone (Engine.launchAssistant), never by
    /// a space, whose launches leave it nil.
    public var assistant: Assistant?
    /// The commands something lends this launch as tools (Lent.swift): only the building assistant has them.
    public var lent: Lent?
    /// Whether the launch takes its kind's plan B (`Driving.planB`): the second way to launch it, when the first one
    /// was refused or a developer forced it (`something try --plan-b`).
    public var planB = false

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

/// How the person's assistant works. `building`: it may change its folder's files and run something's own commands
/// without asking (E-1). `askingEverything` (Ask Before Every Change): it asks as any agent does.
public enum Assistant: Sendable { case building, askingEverything }

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

/// The program's arguments for a launch, and what the launch changes in the person's environment.
public struct Command: Equatable, Sendable {
    public var arguments: [String]
    public var adding: [String: String] = [:]
    public var removing: Set<String> = []

    package init(arguments: [String], adding: [String: String] = [:], removing: Set<String> = []) {
        (self.arguments, self.adding, self.removing) = (arguments, adding, removing)
    }
}

/// One launch's driver, made by its kind's `Driving.driver`, which also says what it can do.
public protocol Driver: AnyObject {
    /// Writes what the program needs before the first message. Throws AGENT_STOPPED.
    func begin() throws
    /// Reads one line of the program's output. Returns whether it knew the line: one it does not know changes nothing.
    @discardableResult func receive(_ line: Data) -> Bool
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
    /// Takes its program, just before it starts, on the main queue. By default it keeps nothing.
    func join(_ program: ProcessHandle) throws
    /// The first step of the stop ladder, on a thread of its own: Spawn gives it 3 s at most, then closes the input.
    /// By default it writes `goodbye`, when there is one, and waits for the program's own exit.
    func graceful(_ program: ProcessHandle)
    /// After a stop something asked for, which is folded without `ended`. By default nothing more is said.
    func afterAskedStop()
    /// Its program ended, or the launch failed after `join`: from the thread that saw it, before an end is folded.
    /// It may come twice (a program that closed its input at once), and must do no harm then. By default there is
    /// nothing to release.
    func released()
}

extension Driver {
    public func join(_ program: ProcessHandle) throws {}

    /// What a tool acts on, as the person reads it: its JSON, keys sorted and indented, or its text.
    package static func json(_ value: Any?) -> String? {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]) else {
            return value as? String
        }
        return String(decoding: data, as: UTF8.self)
    }

    public func graceful(_ program: ProcessHandle) {
        guard let goodbye, program.write(goodbye) else { return }
        while program.running() { usleep(20_000) }
    }

    public func afterAskedStop() {}

    public func released() {}
}

/// One launch's program, as its driver may act on it. The engine joins each launch to its program (Join.swift);
/// a replay has none.
public struct ProcessHandle {
    /// The program's whole environment: the person's, plus what the launch added.
    public var environment: [String: String]
    /// Writes one line to its input, recorded as any other; false when it no longer reads.
    public var write: (Data) -> Bool
    /// Whether it still runs. Read from any thread.
    public var running: () -> Bool
    /// Closes its input, after which it ends by itself: for a launch that cannot go on.
    public var quit: () -> Void
    /// Asks, without waiting, that the running turn be stopped as the bridge's interrupt does, held messages dropped:
    /// the stop runs later on the main queue, and its answer comes as the driver's own lines.
    public var interrupt: () -> Void
    /// What the host knows that a launch may need.
    public var host: HostFacts
    /// Launches the same agent again with its kind's plan B, in place of this launch, whose end then changes
    /// nothing; true when it started. Nil for a launch that is plan B already, or of a kind without one.
    public var relaunch: (() -> Bool)?
}

/// Each `can` entry by its name in the contract. `resume` is false here: a launched agent is running.
let canKeys: [String: WritableKeyPath<Can, Bool>] = ["send": \.send, "steer": \.steer, "queue": \.queue, "interrupt": \.interrupt,
                                                    "model": \.model, "mode": \.mode, "effort": \.effort, "resume": \.resume]

/// One agent something launched: its driver and its held queue, on one queue (the engine's main queue). Events from
/// the driver are folded here, and a held message goes out when a turn ends.
package final class Launched {
    let driver: Driver
    /// What its kind's driver can do.
    let driving: Driving
    private(set) var queue: HeldQueue
    /// Called after each event, so the engine can push the state.
    var changed: () -> Void = {}
    private let now: () -> String
    private let resumes: Bool
    /// The program's lines its driver did not know, counted from the launch until one is known (nil from then on).
    private var unknown: Int? = 0
    /// Lines from the start of a launch, none known, after which the program is taken to be a version its driver
    /// does not understand: the state then says so in its kind's note (Engine).
    static let foreignAfter = 20

    /// The errors of a resume whose program never took the conversation.
    static let refusals: Set = ["HELD_ELSEWHERE", "THREAD_NOT_FOUND"]

    /// One launch of `driving`'s kind, whose driver it makes.
    init(_ driving: Driving, _ launch: Launch, write: @escaping (Data) throws -> Void, now: @escaping () -> String) {
        self.now = now
        self.driving = driving
        resumes = launch.resume
        queue = HeldQueue(Fold(Launched.fresh(driving, launch)))
        var emit: (AgentEvent) -> Void = { _ in }
        driver = driving.driver(launch, write, { emit($0) }, now)
        emit = { [weak self] event in self?.record(event) }
    }

    /// A launched agent before its first event: everything it can do, but for its kind's limits.
    private static func fresh(_ driving: Driving, _ launch: Launch) -> Agent {
        var agent = Agent(id: launch.agent, kind: driving.kind, origin: "launched")
        agent.folder = launch.folder
        agent.name = (launch.folder as NSString).lastPathComponent
        agent.thread = driving.picksThread || launch.resume ? launch.thread : nil
        var can = Can()
        for key in ["send", "steer", "queue", "interrupt", "model", "mode", "effort"] { can[keyPath: canKeys[key]!] = true }
        // A key outside `canKeys` is a typo in a driver: it must fail the tests, not be dropped.
        for key in driving.limits.keys { can[keyPath: canKeys[key]!] = false }
        agent.can = can
        agent.because = driving.limits
        return agent
    }

    /// Whether its program refused to continue the conversation it was launched for: it never held it, so it does
    /// not list it, and the conversation stays the one seen elsewhere, which a new resume can try again.
    var refused: Bool { resumes && Launched.refusals.contains(queue.fold.agent.error?.code ?? "") }

    /// Its conversation as the state lists it; nil until the harness names it, or when the resume was refused.
    var thread: AgentThread? { refused ? nil : queue.fold.thread }

    /// The agent as the state shows it: the fold's, with `can.effort` false while no effort is offered to a kind
    /// that takes only those (contract: `can` says what a call would do now), and no thread when it was refused.
    var agent: Agent {
        var agent = queue.fold.agent
        if refused { agent.thread = nil }
        if driving.effortOnlyWhenOffered, agent.can.effort, agent.options.effort == nil {
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

    /// Whether the first `foreignAfter` lines of its program were all unknown to its driver.
    var foreign: Bool { (unknown ?? 0) >= Launched.foreignAfter }

    /// Gives one line of its program to its driver, and counts it while no line was known.
    func receive(_ line: Data) {
        let known = driver.receive(line)
        guard let count = unknown else { return }
        unknown = known ? nil : count + 1
        if unknown == Launched.foreignAfter { changed() }
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
    package static func short(_ text: String) -> String { text.count > 40 ? String(text.prefix(40)) + "…" : text }

    /// `send` of something.js. Returns the delivery. Throws AGENT_STOPPED, BAD_PARAMS for an unknown `when`.
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

    /// The program ended with `code`. When something asked it to stop, that is no failure, whatever the code; what
    /// the driver still has to say comes after (`afterAskedStop`).
    func ended(code: Int32, errors: String, asked: Bool) {
        guard asked else { return driver.ended(code: code, errors: errors) }
        record(.stopped(nil))
        driver.afterAskedStop()
    }

    /// Empties the queue and stops the running turn. Returns whether a turn was running. Throws AGENT_STOPPED.
    func interrupt() throws -> Bool {
        let running = queue.interrupt()
        if running { try driver.interrupt() }
        changed()
        return running
    }
}

extension Option {
    /// Words for the effort levels Claude Code names, which Codex and pi also show; a level not here is shown as the
    /// agent names it.
    package static let effortLabels = ["low": "Low", "medium": "Medium", "high": "High", "xhigh": "Extra high", "max": "Max"]
}
