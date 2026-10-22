// Watch: the loop that sees the agents started elsewhere. One timer, every 2 s while a space is open, 10 s otherwise,
// paused while no window shows: one process snapshot, then each reader stats the files it may list and reads only what
// changed; every 15th tick, readers also walk their folders for what a stat cannot find, and look again at the files
// too old to list. The work runs on the watch's own queue and its result is handed to the main queue, where the
// engine drops what it launched itself (dedupe) and folds the rest into agents through StateMap.
// One reader failing never takes the others down: each runs on a queue of its own within a deadline, and what it
// throws becomes its kind's "unreadable" with a sentence (Lane).
import Foundation
import SomethingCore

/// A harness's files read without its program's help. A reader keeps its own cursors, on its own queue only.
package protocol Reader: AnyObject {
    var kind: String { get }
    /// The process names of its program, whose arguments and folder the snapshot reads.
    var programs: Set<String> { get }
    /// Whether `process` runs its program; by default, when its name is one of `programs`.
    func owns(_ process: Running) -> Bool
    /// What its files say now. `discover` asks for the walk of every 15th tick. Throws when they cannot be read at
    /// all (a folder refused, a database that does not open): `Unreadable`, whose words the watch says.
    func read(_ snapshot: Snapshot, discover: Bool, now: Date) throws -> Reading
}

/// Why a reader cannot read its agent's files, in words that follow "something could not read <Name>'s files: ".
package struct Unreadable: Error {
    package var why: String
    package init(_ why: String) { self.why = why }
}

extension Reader {
    package func owns(_ process: Running) -> Bool { programs.contains(process.name) }

    /// Whether `path` is a folder: a reader looks for its files only where a folder of its agent is.
    package static func isFolder(_ path: String) -> Bool {
        var folder: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &folder) && folder.boolValue
    }

    /// A time as Codex and pi write it: ISO 8601 in UTC, with milliseconds or without.
    package static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

package struct Reading: Equatable {
    package var sightings: [Sighting] = []
    /// The newest version of the harness found in its files; nil when none says.
    package var version: String?
    /// `kinds.<kind>.reader`: "ok", "changed", "unreadable" or "none".
    package var health = "none"
    /// One sentence for the person when the health is not "ok" or "none", or when a source beside the files read
    /// cannot be read (OpenCode desktop 1.x's tables).
    package var note: String?

    package init(sightings: [Sighting] = [], version: String? = nil, health: String = "none", note: String? = nil) {
        (self.sightings, self.version, self.health, self.note) = (sightings, version, health, note)
    }
}

/// One conversation a reader saw, in neutral facts: StateMap turns them into state words.
package struct Sighting: Equatable {
    package var kind: String
    /// The harness's own id of the conversation, which a driver also reports for what something launched.
    package var key: String
    package var pid: Int32?
    /// The process group of `pid`, from the snapshot, for the dedupe.
    package var group: Int32?
    package var facts: StateMap.Facts
    package var folder: String?
    package var title: String?
    /// The program's name, the agent's name when neither a title nor a folder gives one.
    package var program: String?
    package var model: String?, mode: String?, effort: String?
    package var started: Date?
    /// The last activity seen.
    package var updated: Date?
    package var turns: [Turn] = []
    package var complete = true
    package var error: AgentError?
    package var detail: [String: JSONValue] = [:]
    /// Seen from its process only, as when its reader no longer knows the shape of its files: its state is unknown.
    package var processOnly = false
    /// Its holder is known, but not what it does (a status word the reader does not know): its state is unknown.
    package var stateKnown = true
    /// Why an entry of `can` is false, beyond what is said of every agent seen elsewhere, by entry.
    package var because: [String: String] = [:]

    package init(kind: String, key: String, pid: Int32? = nil, group: Int32? = nil, facts: StateMap.Facts, folder: String? = nil,
                 title: String? = nil, program: String? = nil, model: String? = nil, mode: String? = nil, effort: String? = nil,
                 started: Date? = nil, updated: Date? = nil, turns: [Turn] = [], complete: Bool = true, error: AgentError? = nil,
                 detail: [String: JSONValue] = [:], processOnly: Bool = false, stateKnown: Bool = true, because: [String: String] = [:]) {
        (self.kind, self.key, self.pid, self.group, self.facts, self.folder, self.title) = (kind, key, pid, group, facts, folder, title)
        (self.program, self.model, self.mode, self.effort, self.started, self.updated) = (program, model, mode, effort, started, updated)
        (self.turns, self.complete, self.error, self.detail) = (turns, complete, error, detail)
        (self.processOnly, self.stateKnown, self.because) = (processOnly, stateKnown, because)
    }
}

/// What one tick saw: the sightings of every reader, and each reader's version, health and note (its sightings moved out).
struct Seen: Equatable {
    var sightings: [Sighting] = []
    var kinds: [String: Reading] = [:]
}

package final class Watch {
    /// Seen elsewhere, an agent is listed while alive and for this long after its last activity.
    package static let recent: TimeInterval = 24 * 3600
    static let discoveryEvery = 15

    private let lanes: [Lane]
    private let snapshot: () -> Snapshot
    private let queue = DispatchQueue(label: "something.watch")
    private var cancel: (() -> Void)?
    private var interval: TimeInterval = 0
    /// Calls `fire` on `queue` every `seconds`, the first time now, until the closure it returns is called. A test
    /// gives a clock of its own.
    var repeating: (_ seconds: TimeInterval, _ queue: DispatchQueue, _ fire: @escaping () -> Void) -> () -> Void = { seconds, queue, fire in
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: seconds, leeway: .milliseconds(500))
        timer.setEventHandler(handler: fire)
        timer.resume()
        return timer.cancel
    }
    private var ticks = 0
    /// The last tick's result, kept for a tick whose snapshot is not whole.
    private var last = Seen()
    /// something's own pid: what descends from it is an agent it launched, or a helper of one. A test names another.
    var own = ProcessInfo.processInfo.processIdentifier

    /// `snapshot` takes the processes of a tick; by default, this Mac's. `name` names a kind in the readers' notes.
    init(readers: [Reader], snapshot: (() -> Snapshot)? = nil, name: @escaping (String) -> String = { $0 }) {
        lanes = readers.map { Lane($0, name: name($0.kind)) }
        let processes = Processes(known: readers.reduce(into: Set<String>()) { $0.formUnion($1.programs) })
        self.snapshot = snapshot ?? processes.snapshot
    }

    /// Ticks every `seconds`, the first one now, and gives each tick's result to `seen` on the main queue. Called
    /// again, it only changes the cadence.
    func start(every seconds: TimeInterval, _ seen: @escaping (Seen) -> Void) {
        guard seconds != interval else { return }
        interval = seconds
        cancel?()
        cancel = repeating(seconds, queue) { [weak self] in
            guard let self else { return }
            let result = tick(now: Date(), within: seconds / 2)
            DispatchQueue.main.async { seen(result) }
        }
    }

    /// Stops ticking until `start` is called again, which ticks at once and walks: what changed meanwhile, however
    /// long, is all seen at that tick.
    func pause() {
        cancel?()
        cancel = nil
        interval = 0
        // `ticks` belongs to the watch's queue, where a tick may be running now.
        queue.async { [weak self] in self?.ticks = 0 }
    }

    deinit { cancel?() }

    /// One tick, on the caller's queue: the watch's own, or a test's. Keeps only recent sightings, and none whose
    /// process descends from something (its children, their descendants and reparented helpers). A
    /// snapshot that is not whole proves no process gone: the readers are not run, and the last result stands. The
    /// readers run side by side; one that has not returned `within` seconds keeps its last reading (Lane).
    func tick(now: Date, within deadline: TimeInterval = .infinity) -> Seen {
        let processes = snapshot()
        guard processes.whole else { return last }
        let discover = ticks % Watch.discoveryEvery == 0
        ticks += 1
        let done = DispatchGroup()
        for lane in lanes { lane.read(processes, discover: discover, now: now, done) }
        _ = done.wait(timeout: deadline.isFinite ? .now() + deadline : .distantFuture)
        var seen = Seen()
        for lane in lanes {
            let reader = lane.reader
            var reading = lane.reading
            // A reader that knows its files changed shape, or cannot read them, and found nothing else to read (Codex
            // has its rollouts when its index changed) shows its program's processes.
            if reading.health == "changed" || reading.health == "unreadable", reading.sightings.isEmpty {
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

    /// Whether a conversation is listed: alive, or active within `recent`.
    package static func isRecent(alive: Bool?, updated: Date?, now: Date) -> Bool {
        alive == true || (updated.map { now.timeIntervalSince($0) < recent } ?? false)
    }

    /// The agents and threads of `seen` that something did not launch: a sighting is dropped when its process is in
    /// the group of one of something's children (`groups`: a helper whose leader ended no longer descends from
    /// something), or when its conversation is one a driver reported (`keys`). Ids are stable while the conversation
    /// is listed. `registry` says which conversations can be continued here.
    static func elsewhere(_ seen: Seen, registry: Registry, groups: Set<Int32>, keys: Set<String>, now: Date) -> (agents: [Agent], threads: [AgentThread]) {
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
                (agent.can.resume, agent.because["resume"]) = registry.continuable(sighting.kind, alive: sighting.facts.alive, pid: agent.pid)
                if agent.can.resume { agent.because["send"]! += " Continue it here to write to it." }
            }
            // A reader names the holder better (Codex's background service), so its reason wins; but for a kind
            // something cannot continue, that comes first and the reader's note follows, so it never hides why.
            var notes = sighting.because
            if !registry.resumable.contains(sighting.kind), let reason = agent.because["resume"], let note = notes.removeValue(forKey: "resume") {
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

    package static func iso(_ date: Date) -> String { iso8601.string(from: date) }

    /// What `read` gives, or, when it throws, a reading that says `name`'s files are unreadable, and why.
    package static func contained(_ name: String, _ read: () throws -> Reading) -> Reading {
        do { return try read() } catch {
            return Reading(health: "unreadable", note: "something could not read \(name)'s files: \((error as? Unreadable)?.why ?? error.localizedDescription)")
        }
    }
}

/// One reader on a queue of its own, with what it said last. A read still running when its tick ends is not waited
/// for, and the reader is not asked again before it returns: its last reading stands, said to be late. A throw is
/// said as "unreadable", with the last good sightings kept for one tick (a file replaced mid-read, a busy database).
private final class Lane {
    let reader: Reader
    private let name: String, queue: DispatchQueue, lock = NSLock()
    private var running = false, owed = false, failures = 0
    private var last = Reading(), good = Reading()

    init(_ reader: Reader, name: String) {
        (self.reader, self.name) = (reader, name)
        queue = DispatchQueue(label: "something.watch.\(reader.kind)")
    }

    /// What the reader said last; while it still reads, with a note that says so.
    var reading: Reading {
        lock.lock()
        defer { lock.unlock() }
        guard running else { return last }
        var late = last
        late.note = "something is still reading \(name)'s files; what they say may be late."
        return late
    }

    /// Reads on the lane's queue, inside `done`, unless the last read has not returned; a walk asked meanwhile is
    /// owed to the next read.
    func read(_ snapshot: Snapshot, discover: Bool, now: Date, _ done: DispatchGroup) {
        lock.lock()
        defer { lock.unlock() }
        guard !running else { return owed = owed || discover }
        let walk = discover || owed
        (running, owed) = (true, false)
        done.enter()
        queue.async { [self] in
            let result = Result { try reader.read(snapshot, discover: walk, now: now) }
            lock.lock()
            failures = (try? result.get()) == nil ? failures + 1 : 0
            last = Watch.contained(name) { try result.get() }
            if failures == 0 { good = last } else if failures == 1 { (last.sightings, last.version) = (good.sightings, good.version) }
            running = false
            lock.unlock()
            done.leave()
        }
    }
}
