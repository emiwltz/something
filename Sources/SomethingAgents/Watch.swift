// Watch: the loop that sees the agents started elsewhere (design 4.2 and 4.3). One timer, every 2 s while a space is
// open and 10 s otherwise: one process snapshot, then each reader stats its files and reads only what changed; every
// 15th tick, readers also walk their folders for what a stat cannot find. The work runs on the watch's own queue and
// its result is handed to the main queue, where the engine drops what it launched itself (dedupe) and folds the rest
// into agents through StateMap.
import Darwin
import Foundation
import SomethingCore

/// A harness's files read without its program's help. A reader keeps its own cursors, on the watch's queue only.
protocol Reader: AnyObject {
    var kind: String { get }
    /// The process names of its program, whose arguments and folder the snapshot reads.
    var programs: Set<String> { get }
    /// Whether `process` runs its program; by default, when its name is one of `programs`.
    func owns(_ process: Running) -> Bool
    /// What its files say now. `discover` asks for the walk of every 15th tick.
    func read(_ snapshot: Snapshot, discover: Bool, now: Date) -> Reading
}

extension Reader {
    func owns(_ process: Running) -> Bool { programs.contains(process.name) }
}

struct Reading: Equatable {
    var sightings: [Sighting] = []
    /// The newest version of the harness found in its files; nil when none says.
    var version: String?
    /// `kinds.<kind>.reader`: "ok", "changed", "unreadable" or "none".
    var health = "none"
    /// One sentence for the person when the health is not "ok" or "none", or when a source beside the files read
    /// cannot be read (OpenCode desktop 1.x's tables).
    var note: String?
}

/// One conversation a reader saw, in neutral facts: StateMap turns them into state words.
struct Sighting: Equatable {
    var kind: String
    /// The harness's own id of the conversation, which a driver also reports for what something launched.
    var key: String
    var pid: Int32?
    /// The process group of `pid`, from the snapshot, for the dedupe.
    var group: Int32?
    var facts: StateMap.Facts
    var folder: String?
    var title: String?
    /// The program's name, the agent's name when neither a title nor a folder gives one (contract 3.2).
    var program: String?
    var model: String?, mode: String?, effort: String?
    var started: Date?
    /// The last activity seen.
    var updated: Date?
    var turns: [Turn] = []
    var complete = true
    var error: AgentError?
    var detail: [String: JSONValue] = [:]
    /// Seen from its process only, as when its reader no longer knows the shape of its files: its state is unknown.
    var processOnly = false
    /// Its holder is known, but not what it does (a status word the reader does not know): its state is unknown.
    var stateKnown = true
    /// Why an entry of `can` is false, beyond what is said of every agent seen elsewhere, by entry.
    var because: [String: String] = [:]
}

/// What one tick saw: the sightings of every reader, and each reader's version, health and note (its sightings moved out).
struct Seen: Equatable {
    var sightings: [Sighting] = []
    var kinds: [String: Reading] = [:]
}

final class Watch {
    /// Seen elsewhere, an agent is listed while alive and for this long after its last activity (contract 3.5).
    static let recent: TimeInterval = 24 * 3600
    static let discoveryEvery = 15

    let readers: [Reader]
    private let snapshot: () -> Snapshot
    private let queue = DispatchQueue(label: "something.watch")
    private var timer: DispatchSourceTimer?
    private var interval: TimeInterval = 0
    private var ticks = 0
    /// The last tick's result, kept for a tick whose snapshot is not whole.
    private var last = Seen()
    /// something's own pid: what descends from it is an agent it launched, or a helper of one. A test names another.
    var own = getpid()

    /// `snapshot` takes the processes of a tick; by default, this Mac's.
    init(readers: [Reader], snapshot: (() -> Snapshot)? = nil) {
        self.readers = readers
        let processes = Processes(known: readers.reduce(into: Set<String>()) { $0.formUnion($1.programs) })
        self.snapshot = snapshot ?? processes.snapshot
    }

    /// The readers for something's own environment: the folders its agents use are found there, never guessed.
    static func readers(_ environment: [String: String]) -> [Reader] {
        [ClaudeReader(environment: environment), CodexReader(environment: environment), OpenCodeReader(environment: environment),
         PiReader(environment: environment), OMPReader(environment: environment), OtherReader()]
    }

    /// Ticks every `seconds`, the first one now, and gives each tick's result to `seen` on the main queue. Called
    /// again, it only changes the cadence.
    func start(every seconds: TimeInterval, _ seen: @escaping (Seen) -> Void) {
        guard seconds != interval else { return }
        interval = seconds
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: seconds, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let result = tick(now: Date())
            DispatchQueue.main.async { seen(result) }
        }
        self.timer = timer
        timer.resume()
    }

    deinit { timer?.cancel() }

    /// One tick, on the caller's queue: the watch's own, or a test's. Keeps only recent sightings, and none whose
    /// process descends from something (design 4.3: its children, their descendants and reparented helpers). A
    /// snapshot that is not whole proves no process gone: the readers are not run, and the last result stands.
    func tick(now: Date) -> Seen {
        let processes = snapshot()
        guard processes.whole else { return last }
        let discover = ticks % Watch.discoveryEvery == 0
        ticks += 1
        var seen = Seen()
        for reader in readers {
            var reading = reader.read(processes, discover: discover, now: now)
            // A reader that knows its files changed shape and found nothing else to read (Codex has its rollouts when
            // its index changed) shows its program's processes.
            if reading.health == "changed", reading.sightings.isEmpty {
                reading.sightings = processes.processes.values.filter(reader.owns).map { process in
                    Sighting(kind: reader.kind, key: "pid-\(process.pid)", pid: process.pid, facts: StateMap.Facts(alive: true, evidence: "process"),
                             folder: process.folder, started: process.started, processOnly: true)
                }
            }
            reading.sightings = reading.sightings.filter { sighting in
                Watch.isRecent(alive: sighting.facts.alive, updated: sighting.updated, now: now)
                    && !(sighting.pid.map { processes.descends($0, from: own) } ?? false)
            }
            // Oldest first, in one order from tick to tick: the same agents in another order would be a change.
            reading.sightings.sort { ($0.started ?? .distantPast, $0.key) < ($1.started ?? .distantPast, $1.key) }
            for index in reading.sightings.indices { reading.sightings[index].group = reading.sightings[index].pid.flatMap { processes[$0]?.group } }
            seen.sightings += reading.sightings
            reading.sightings = []
            // A kind with nothing on this Mac is left out: the state says "none" for it, as for a kind without a reader.
            if reading != Reading() { seen.kinds[reader.kind] = reading }
        }
        last = seen
        return seen
    }

    /// Whether a conversation is listed (contract 3.5): alive, or active within `recent`.
    static func isRecent(alive: Bool?, updated: Date?, now: Date) -> Bool {
        alive == true || (updated.map { now.timeIntervalSince($0) < recent } ?? false)
    }

    /// The agents and threads of `seen` that something did not launch: a sighting is dropped when its process is in
    /// the group of one of something's children (`groups`: a helper whose leader ended no longer descends from
    /// something), or when its conversation is one a driver reported (`keys`). Ids are stable while the conversation
    /// is listed.
    static func elsewhere(_ seen: Seen, groups: Set<Int32>, keys: Set<String>, now: Date) -> (agents: [Agent], threads: [AgentThread]) {
        var agents: [Agent] = [], threads: [AgentThread] = []
        for sighting in seen.sightings where !keys.contains(sighting.key) && !(sighting.group.map(groups.contains) ?? false) {
            var agent = Agent(id: "\(sighting.kind)-\(sighting.key)", kind: sighting.kind, origin: "elsewhere")
            // A process proves its holder alive, not what it does: the state words are those of an unknown holder.
            let facts = sighting.processOnly ? StateMap.Facts(alive: nil, evidence: "process")
                : sighting.stateKnown ? sighting.facts : StateMap.Facts(alive: nil, evidence: sighting.facts.evidence)
            let result = StateMap.map(facts, now: now)
            agent.alive = sighting.facts.alive
            agent.evidence = result.evidence
            agent.state = result.state
            agent.waiting = result.waiting
            agent.name = sighting.title ?? sighting.folder.map { ($0 as NSString).lastPathComponent } ?? sighting.program ?? sighting.kind
            agent.folder = sighting.folder
            // An ended process's pid may already be another program's.
            agent.pid = sighting.facts.alive == false ? nil : sighting.pid.map(Int.init)
            agent.thread = sighting.key
            (agent.model, agent.mode, agent.effort) = (sighting.model, sighting.mode, sighting.effort)
            agent.error = sighting.error
            agent.detail = sighting.detail
            agent.started = sighting.started.map(iso)
            agent.updated = sighting.updated.map(iso)
            agent.because = ["send": "This agent was started outside something; something only reads it."]
            if !sighting.processOnly {
                (agent.can.resume, agent.because["resume"]) = Watch.continuable(sighting.kind, alive: sighting.facts.alive, pid: agent.pid)
                if agent.can.resume { agent.because["send"]! += " Continue it here to write to it." }
            }
            // A reader names the holder better (Codex's background service), so its reason wins; but for a kind
            // something cannot continue, that comes first and the reader's note follows, so it never hides why.
            var notes = sighting.because
            if !Engine.continuable.contains(sighting.kind), let reason = agent.because["resume"], let note = notes.removeValue(forKey: "resume") {
                agent.because["resume"] = "\(reason) \(note)"
            }
            agent.because.merge(notes) { _, reader in reader }
            if sighting.processOnly { agent.thread = nil; agents.append(agent); continue }
            var thread = AgentThread(id: sighting.key, agent: agent.id, title: agent.name, started: agent.started, turns: sighting.turns)
            thread.complete = thread.complete && sighting.complete
            agents.append(agent)
            threads.append(thread)
        }
        return (agents, threads)
    }

    /// Whether a conversation seen elsewhere can be continued here (design 4.4), and why not. Only one no process
    /// holds: one still held would get a second writer. Codex refuses a second writer by itself, so a Codex
    /// conversation whose holder is unknown is offered; Codex says so if its background service holds it.
    static func continuable(_ kind: String, alive: Bool?, pid: Int?) -> (Bool, String?) {
        let name = Programs.name(of: kind)
        guard Engine.continuable.contains(kind) else { return (false, "something cannot continue \(name) conversations started elsewhere yet.") }
        switch alive {
        case true?: return (false, "\(name) still runs this conversation\(pid.map { " (pid \($0))" } ?? ""). Quit it there first.")
        case false?: return (true, nil)
        case nil:
            return kind == "codex" ? (true, nil) : (false, "something cannot tell whether \(name) still runs this conversation, so it cannot continue it here.")
        }
    }

    static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}
