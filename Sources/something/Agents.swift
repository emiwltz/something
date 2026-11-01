// One reading of an agent: what every surface says of it, made in one place from the agent as the state shows it, its
// conversation and its program, so a row, a card and ⌘P cannot say it differently. And `RunsIn`, the app it runs in, found
// by walking its parents: the only way that reads no process's environment, whose memory holds keys.
import Foundation
import SomethingAgents
import SomethingCore

struct AgentReading: Equatable {
    /// Where it stands: in something; running in another app; closed, its conversation can continue; closed for good;
    /// or only seen, nothing proving what it does.
    enum Phase { case here, away, asleep, ended, seen }

    let agent: Agent
    /// Its lasting identity (`Rights.key`).
    let key: String
    /// Its title, else its program's name; `named` says it has one of its own.
    let title: String, named: Bool
    let program: String
    let phase: Phase
    /// What its eyes say, and so its word.
    let eyes: Sign.State
    /// Where it runs, "In something", "In Terminal"; nil when that isn't known.
    let tag: String?
    /// Whether its conversation has a turn.
    let talked: Bool
    /// Whether its conversation can go on in something.
    let continues: Bool

    var id: String { agent.id }
    var folder: String? { agent.folder }
    var word: String { eyes.word }

    /// `known` is the title read earlier, which wins: the turns it came from may be gone. `registry` is the app's by default.
    init(_ agent: Agent, thread: AgentThread?, known: String? = nil, runs: RunsIn, registry: Registry = .app) {
        let closed = agent.origin == "launched" && agent.alive == false && agent.thread != nil
        let title = known ?? AgentReading.title(agent, thread)
        self.agent = agent
        key = Rights.key(agent)
        program = registry.agent(agent.kind)?.name ?? agent.name ?? agent.kind
        (self.title, named) = (title ?? program, title != nil)
        talked = thread?.turns.isEmpty == false
        continues = agent.can.resume || closed && registry.continuable(agent.kind, alive: false, pid: nil).0
        phase = switch (agent.origin, agent.alive) {
        case ("launched", let alive) where alive != false: .here
        case (_, false?): continues ? .asleep : .ended
        case (_, true?) where agent.thread != nil: .away
        default: .seen
        }
        eyes = switch phase {
        case .asleep: .sleep
        case .ended: .limit
        default: AgentReading.eyes(agent)
        }
        tag = phase == .here ? "In something" : runs.app(of: agent).map { "In " + RunsIn.name($0) }
    }

    /// What the eyes of an agent not closed say, as an assistant's would. Asleep and Ended are said of a closed
    /// conversation only: a live one that stopped on an error is neither.
    private static func eyes(_ agent: Agent) -> Sign.State {
        let eyes = Presence.state(.init(name: agent.kind), agent, justDone: false).0
        return [.sleep, .limit].contains(eyes) ? .unknown : eyes
    }

    /// The reader's title, else the person's first words. The folder's name, which stands in for a title in the state, is none.
    private static func title(_ agent: Agent, _ thread: AgentThread?) -> String? {
        let place = agent.folder.map { ($0 as NSString).lastPathComponent }
        if let title = thread?.title, !title.isEmpty, title != place, title != agent.kind { return title }
        let first = thread?.turns.lazy.flatMap(\.items).first { $0.kind == "message" && $0.author == "person" }
        guard let line = first?.text.split(whereSeparator: \.isNewline).first.map(String.init), !line.isEmpty else { return nil }
        return line.count > 60 ? String(line.prefix(58)) + "…" : line
    }
}

/// The app each agent runs in, read once per process, only for the agents the panel shows.
final class RunsIn {
    private let lineage: (Int32) -> [String]
    private var kept: [String: URL?] = [:]

    init(lineage: @escaping (Int32) -> [String] = { Processes.lineage($0) }) { self.lineage = lineage }

    /// The outermost `.app` of the nearest of `agent`'s ancestors inside one, or nil: a server launchd holds (tmux), a
    /// service, an agent with no process known. A process keeps its parents: the answer holds while it runs.
    func app(of agent: Agent) -> URL? {
        guard let pid = agent.pid.flatMap(Int32.init(exactly:)), pid > 0 else { return nil }
        let held = "\(agent.id):\(pid)"
        if let known = kept[held] { return known }
        let found = lineage(pid).lazy.compactMap(RunsIn.outermost).first
        kept[held] = .some(found)
        return found
    }

    /// Forgets all but the processes of `agents`.
    func keep(_ agents: [Agent]) {
        let held = Set(agents.compactMap { agent in agent.pid.map { "\(agent.id):\($0)" } })
        kept = kept.filter { held.contains($0.key) }
    }

    /// The outermost `.app` of `path`: a helper's own app inside an app is part of it.
    static func outermost(_ path: String) -> URL? {
        let parts = path.split(separator: "/")
        return parts.firstIndex { $0.hasSuffix(".app") }.map { URL(fileURLWithPath: "/" + parts[...$0].joined(separator: "/")) }
    }

    /// `app`'s name as Finder says it, without its extension.
    static func name(_ app: URL) -> String {
        let name = FileManager.default.displayName(atPath: app.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
