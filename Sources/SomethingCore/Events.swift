// The events drivers and readers emit, and their fold into one Agent, its Thread and its Requests. A driver never
// touches an Agent: it says what happened, and the state words come from StateMap here, so every harness means the
// same by "working". The fold also holds the queue of messages for the agent's next turn.
import Foundation

public enum AgentEvent: Equatable, Sendable {
    /// The program runs. `thread` is its conversation, once the harness names it.
    case started(pid: Int?, thread: String?)
    /// Values the agent itself reported; nil leaves a value as it was.
    case reported(model: String?, mode: String?, effort: String?)
    case options(Options)
    /// A turn began; `id` is the harness's own when it has one.
    case turnStarted(id: String?)
    case turnEnded(Outcome)
    case itemAppended(Item)
    /// An item of the thread changed (a tool finished, a message grew): it replaces the item with the same id.
    case itemUpdated(Item)
    case requestOpened(Request)
    case requestClosed(id: String)
    case error(AgentError)
    /// The process ended, with the error that ended it if any.
    case stopped(AgentError?)
}

public enum Outcome: Equatable, Sendable { case done, interrupted, failed(AgentError) }

public struct Fold: Sendable {
    public private(set) var agent: Agent
    /// The last `Limits.turns` turns, oldest first.
    public private(set) var turns: [Turn] = []
    /// false once older turns were left out.
    public private(set) var complete = true
    public private(set) var requests: [Request] = []
    private var facts = StateMap.Facts(alive: nil), count = 0

    /// Starts from what the engine knows before the first event: id, kind, origin, folder, `can` and `because`.
    public init(_ agent: Agent) { self.agent = agent }

    /// The agent's conversation; nil until the harness names it, since a thread without its id cannot be resumed.
    public var thread: AgentThread? {
        guard let id = agent.thread else { return nil }
        var thread = AgentThread(id: id, agent: agent.id, title: agent.name, started: agent.started, turns: turns)
        thread.complete = complete
        return thread
    }

    /// Applies one event that happened at `at` (ISO 8601). Returns the held message to hand over now, when a turn
    /// ended normally or with an error and the queue was not empty; an interrupted turn empties the queue instead.
    @discardableResult public mutating func apply(_ event: AgentEvent, at: String, now: Date = Date()) -> Queued? {
        var next: Queued?
        switch event {
        case .started(let pid, let thread):
            (facts.alive, facts.evidence, facts.waiting) = (true, "child", .nothing)
            (agent.pid, agent.thread, agent.started) = (pid ?? agent.pid, thread ?? agent.thread, agent.started ?? at)
        case .reported(let model, let mode, let effort):
            (agent.model, agent.mode, agent.effort) = (model ?? agent.model, mode ?? agent.mode, effort ?? agent.effort)
        case .options(let options): agent.options = options
        case .turnStarted(let id):
            count += 1
            add(Turn(id: id ?? "\(agent.thread ?? agent.id)#\(count)", state: "working", started: at, ended: nil, items: []))
            (facts.turnOpen, facts.failed, facts.aborted) = (true, false, false)
        case .turnEnded(let outcome):
            switch outcome {
            case .done: close("done", at: at)
            case .interrupted: close("interrupted", at: at); facts.aborted = true
            case .failed(let error): close("error", at: at); facts.failed = true; agent.error = error
            }
            facts.turnOpen = false
            if outcome == .interrupted { agent.queue = [] } else if !agent.queue.isEmpty { next = agent.queue.removeFirst() }
        case .itemAppended(let item):
            // An item before any turn (a resumed conversation's history) goes in a turn nobody saw start.
            if turns.isEmpty { add(Turn(id: "\(agent.thread ?? agent.id)#0", state: "unknown", started: nil, ended: nil, items: [])) }
            turns[turns.count - 1].items = Array((turns[turns.count - 1].items + [item]).suffix(Limits.items))
        case .itemUpdated(let item):
            for t in turns.indices.reversed() {
                if let i = turns[t].items.firstIndex(where: { $0.id == item.id }) { turns[t].items[i] = item; break }
            }
        case .requestOpened(let request):
            requests = requests.filter { $0.id != request.id } + [request]; waitingFromRequests()
        case .requestClosed(let id):
            requests.removeAll { $0.id == id }; waitingFromRequests()
        case .error(let error): agent.error = error
        case .stopped(let error):
            // A process gone mid-turn did not end normally: the open turn makes StateMap say "interrupted".
            if facts.turnOpen == true { close("interrupted", at: at) }
            (facts.alive, facts.ended, facts.failed) = (false, error == nil && facts.turnOpen != true, error != nil)
            agent.error = error ?? agent.error
            // Nobody is left to answer a request or to take a held message.
            (requests, agent.queue, agent.can, agent.because) = ([], [], Can(), [:])
        }
        let result = StateMap.map(facts, now: now)
        (agent.alive, agent.state, agent.waiting, agent.evidence, agent.updated) = (facts.alive, result.state, result.waiting, result.evidence, at)
        return next
    }

    /// Holds `message` for the agent's next turn; `apply` hands it back when the running turn ends.
    public mutating func hold(_ message: Queued) { agent.queue.append(message) }

    /// Drops every held message: an interrupt asked by the person or a space empties the queue, whatever happens next.
    public mutating func emptyQueue() { agent.queue = [] }

    private mutating func add(_ turn: Turn) {
        turns.append(turn)
        if turns.count > Limits.turns { turns.removeFirst(); complete = false }
    }

    private mutating func close(_ state: String, at: String) {
        guard let last = turns.indices.last, turns[last].state == "working" else { return }
        (turns[last].state, turns[last].ended) = (state, at)
    }

    /// A permission outweighs a question: an agent asking both cannot go on until the permission is answered.
    private mutating func waitingFromRequests() {
        facts.waiting = requests.contains { $0.kind == "permission" } ? .permission : requests.isEmpty ? .nothing : .answer
    }
}
