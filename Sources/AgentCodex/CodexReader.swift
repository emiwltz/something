// CodexReader: the Codex conversations started elsewhere (a terminal, Codex's background service, the desktop app),
// read from Codex's own files, never through its program. The thread index, the highest
// `state_N.sqlite`, says which conversations moved in the last 24 hours and where each one's rollout is; the rollout,
// a JSONL file Codex appends to, gives the turns, from whitelisted fields only. A conversation whose writer lock a
// codex process holds is read however long it has been idle: it is listed while alive. When the index changed shape, the
// rollouts of the last three day folders are read instead. Codex compresses a rollout idle for some days (`.zst`):
// such a conversation is old, and it is skipped. A conversation is held by the codex process that holds its writer
// lock or its rollout open; the files Codex writes say nothing of what it waits on, so `waiting` is null.
import Foundation
import SomethingAgents
import SomethingCore

final class CodexReader: Reader {
    let kind = "codex"
    /// The terminal, its background service and the desktop app's helper all run a program named codex.
    let programs: Set<String> = ["codex"]
    /// Codex's folder: CODEX_HOME, else ~/.codex; nil when the environment names no home.
    let folder: String?
    /// Where Codex keeps its databases: CODEX_SQLITE_HOME, else its folder.
    let databases: String?
    /// Sees every path the reader opens.
    var opened: (String) -> Void = { _ in }
    /// something's own pid: its own codex processes hold only what it launched, so they prove no conversation seen
    /// elsewhere alive or ended. A test names another.
    var own = ProcessInfo.processInfo.processIdentifier

    /// The index columns the reader may use; the guard asks for all of them.
    static let whitelist: [String: Set<String>] = ["threads": ["id", "rollout_path", "created_at", "updated_at", "archived", "source",
                                                               "thread_source", "cwd", "title", "name", "cli_version", "originator",
                                                               "model", "reasoning_effort", "approval_mode"]]
    /// The lines a rollout is read for; the others (token counts, tool outputs, instructions) are never decoded.
    static let wanted = [#""type":"task_started""#, #""type":"task_complete""#, #""type":"turn_aborted""#, #""type":"turn_context""#,
                         #""type":"item_completed""#].map { Data($0.utf8) }
    /// The thread sources of conversations nobody typed into: sub-agents and the reviews Codex runs by itself.
    static let unattended: Set<String> = ["subagent", "guardian_review"]

    struct Thread: Equatable {
        var id: String, rollout: String
        var folder: String?, title: String?, version: String?, originator: String?
        /// The index's settings, for a rollout whose last turn_context lies before what was read.
        var model: String?, effort: String?, mode: String?
        var started: Date?
    }

    private struct Followed {
        var thread: Thread
        var stamp: Stamp?
        var cursor: Cursor?
        var lines: CodexRollout
    }

    /// The index's file and log, and the held locks, as last read, and what they gave.
    private var indexStamps: [Stamp?] = []
    private var indexHeld: [String] = []
    private var indexed: Result<[Thread]?, Failure> = .success(nil)
    private var walked: [String: Thread?]?
    private var followed: [String: Followed] = [:]
    private let held = HeldFiles()

    init(environment: [String: String]) {
        folder = environment["CODEX_HOME"] ?? environment["HOME"].map { ($0 as NSString).appendingPathComponent(".codex") }
        databases = environment["CODEX_SQLITE_HOME"] ?? folder
    }

    func read(_ snapshot: Snapshot, discover: Bool, now: Date) -> Reading {
        guard let folder, CodexReader.isFolder(folder) else { return Reading() }
        var reading = Reading(health: "ok")
        let holders = holders(snapshot, now: now)
        var threads: [Thread]
        switch index(discover: discover, held: CodexReader.locked(holders.files, in: folder), now: now) {
        case .success(let found?): threads = found
        case .success(nil): threads = walk(discover: discover)
        case .failure(let failure):
            threads = walk(discover: discover)
            reading.health = failure == .changed ? "changed" : "unreadable"
            reading.note = failure == .changed
                ? "Codex changed the format of its conversation list; something shows only the conversations of its last three days."
                : "something cannot read Codex's conversation list (state_N.sqlite in ~/.codex); check its permissions. "
                    + "Only the conversations of the last three days are shown."
        }
        threads = threads.filter { FileManager.default.fileExists(atPath: $0.rollout) }
        let ids = Set(threads.map(\.id))
        followed = followed.filter { ids.contains($0.key) }
        for thread in threads {
            follow(thread)
            guard let session = followed[thread.id] else { continue }
            reading.sightings.append(sighting(session, holders))
            if let version = thread.version, version.compare(reading.version ?? "", options: .numeric) == .orderedDescending { reading.version = version }
        }
        return reading
    }

    enum Failure: Error { case changed, unreadable }

    /// The conversations of the index updated in the last 24 hours, and those whose lock is `held`, read again only
    /// when its file, its log or the held locks moved, or for the walk of every 15th tick, as the 24 hours move on;
    /// nil when there is no index.
    private func index(discover: Bool, held: [String], now: Date) -> Result<[Thread]?, Failure> {
        guard let databases, let path = CodexReader.newestIndex(in: databases) else { return .success(nil) }
        let stamps = [Stamp(path), Stamp(path + "-wal")]
        if stamps == indexStamps, held == indexHeld, !discover { return indexed }
        indexStamps = stamps
        indexHeld = held
        indexed = query(path, held: held, now: now)
        return indexed
    }

    /// The thread ids whose writer lock (`thread-writer-locks/<id>.lock`) one of `files` is, sorted.
    static func locked(_ files: [String: Int32], in folder: String) -> [String] {
        let locks = HeldFiles.real((folder as NSString).appendingPathComponent("thread-writer-locks")) + "/"
        return files.keys.filter { $0.hasPrefix(locks) && $0.hasSuffix(".lock") }
            .map { String($0.dropFirst(locks.count).dropLast(5)) }.filter { !$0.hasPrefix(".") }.sorted()
    }

    private func query(_ path: String, held: [String], now: Date) -> Result<[Thread]?, Failure> {
        opened(path)
        guard let db = try? SQLiteRO(path, whitelist: CodexReader.whitelist) else { return .failure(.unreadable) }
        guard (try? db.guarded()) == true else { return .failure(.changed) }
        let since = Int64(now.timeIntervalSince1970 - Watch.recent)
        guard let rows = try? db.rows("""
            SELECT id, rollout_path, created_at, source, thread_source, cwd, title, name, cli_version, originator, model, reasoning_effort, approval_mode
            FROM threads WHERE archived = 0 AND (updated_at >= ? OR id IN (\(held.map { _ in "?" }.joined(separator: ", "))))
            ORDER BY updated_at DESC LIMIT 200
            """, [since] + held) else { return .failure(.unreadable) }
        return .success(rows.compactMap { row in
            guard let id = row["id"] as? String, let rollout = row["rollout_path"] as? String, rollout.hasPrefix("/"),
                  !CodexReader.unattended.contains(row["thread_source"] as? String ?? ""),
                  !(row["source"] as? String ?? "").contains("subagent") else { return nil }
            func text(_ key: String) -> String? { (row[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
            return Thread(id: id, rollout: rollout, folder: text("cwd"), title: text("name") ?? text("title"), version: text("cli_version"),
                          originator: text("originator"), model: text("model"), effort: text("reasoning_effort"), mode: text("approval_mode"),
                          started: SQLiteRO.number(row["created_at"]).map { Date(timeIntervalSince1970: $0) })
        })
    }

    /// The highest `state_N.sqlite` in `folder`: Codex numbers a new index when its shape moves on.
    static func newestIndex(in folder: String) -> String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        let numbered = names.compactMap { name -> (Int, String)? in
            guard name.hasPrefix("state_"), name.hasSuffix(".sqlite"), let number = Int(name.dropFirst(6).dropLast(7)) else { return nil }
            return (number, name)
        }
        return numbered.max { $0.0 < $1.0 }.map { (folder as NSString).appendingPathComponent($0.1) }
    }

    /// Without an index: the rollouts of the three newest day folders (`sessions/YYYY/MM/DD`), each known by its
    /// first line, which says whose it is. Folders are walked on every 15th tick, and on the first.
    private func walk(discover: Bool) -> [Thread] {
        guard let folder else { return [] }
        if discover || walked == nil {
            let sessions = (folder as NSString).appendingPathComponent("sessions")
            func newest(_ path: String) -> [String] {
                ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).filter { Int($0) != nil }.sorted(by: >)
                    .map { (path as NSString).appendingPathComponent($0) }
            }
            let days = newest(sessions).flatMap(newest).flatMap(newest).sorted { $0.suffix(10) > $1.suffix(10) }.prefix(3)
            let files = days.flatMap { day in
                ((try? FileManager.default.contentsOfDirectory(atPath: day)) ?? [])
                    .filter { $0.hasPrefix("rollout-") && $0.hasSuffix(".jsonl") }.map { (day as NSString).appendingPathComponent($0) }
            }
            let known = walked ?? [:]
            walked = Dictionary(uniqueKeysWithValues: files.map { ($0, known[$0] ?? CodexReader.identity($0, opened: opened)) })
        }
        // One id can head several files of a day (an "A_B" segment whose first line is A's, a second copy): one file
        // per conversation, the one named by its id first, then the newest.
        func rank(_ thread: Thread) -> (Int, Date) {
            ((thread.rollout as NSString).lastPathComponent.hasSuffix("-\(thread.id).jsonl") ? 1 : 0, Stamp(thread.rollout)?.modified ?? .distantPast)
        }
        let copies = Dictionary(grouping: (walked ?? [:]).values.compactMap { $0 }, by: \.id)
        return copies.values.compactMap { $0.max { rank($0) < rank($1) } }.sorted { $0.rollout < $1.rollout }
    }

    /// Whose rollout `path` is, from its first line (a `session_meta` of 20 KB or so, read up to 1 MB); nil for a
    /// sub-agent's, or a file whose first line says nothing.
    static func identity(_ path: String, opened: (String) -> Void) -> Thread? {
        opened(path)
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 1 << 20)) ?? Data()
        guard let end = head.firstIndex(of: UInt8(ascii: "\n")),
              let line = (try? JSONSerialization.jsonObject(with: head[..<end])) as? [String: Any], line["type"] as? String == "session_meta",
              let meta = line["payload"] as? [String: Any], let id = meta["id"] as? String else { return nil }
        // A sub-agent's source is an object naming it; a person's is a word.
        guard meta["source"] is String || meta["source"] == nil, !unattended.contains(meta["thread_source"] as? String ?? "") else { return nil }
        return Thread(id: id, rollout: path, folder: meta["cwd"] as? String, title: nil, version: meta["cli_version"] as? String,
                      originator: meta["originator"] as? String, model: nil, effort: nil, mode: nil, started: (meta["timestamp"] as? String).flatMap(CodexReader.date))
    }

    /// Reads what the rollout gained since the last tick.
    private func follow(_ thread: Thread) {
        var session = followed[thread.id] ?? Followed(thread: thread, lines: CodexRollout(thread: thread.id))
        session.thread = thread
        if let stamp = Stamp(thread.rollout), stamp != session.stamp {
            opened(thread.rollout)
            let enough: ([Data]) -> Bool = { $0.contains { $0.range(of: CodexReader.wanted[0]) != nil } }
            if let read = Tail.read(thread.rollout, after: session.cursor, containing: CodexReader.wanted, enough: enough) {
                if read.fresh { session.lines = CodexRollout(thread: thread.id) }
                if read.gap || (read.fresh && !read.fromStart) { session.lines.complete = false }
                read.lines.forEach { session.lines.add($0) }
                session.cursor = read.cursor
                session.stamp = stamp
            }
        }
        followed[thread.id] = session
    }

    typealias Holders = (files: [String: Int32], others: Bool, services: Set<Int32>)

    /// Which codex process holds which file open, by path, whether a codex process that does not descend from
    /// something runs, and which ones are Codex's background service (`codex app-server`). Read again when the codex processes change, or every 10 s: a conversation started in a
    /// running process takes its lock then. something's own processes stay among the holders: the dedupe drops what
    /// they hold.
    private func holders(_ snapshot: Snapshot, now: Date) -> Holders {
        let codex = snapshot.processes.values.filter { programs.contains($0.name) }
        let pids = Set(codex.map(\.pid)), services = Set(codex.filter { $0.arguments?.contains("app-server") == true }.map(\.pid))
        // A process whose open files the system does not give holds nothing that can be seen.
        return (held.read(snapshot, pids, now: now).files, pids.contains { !snapshot.descends($0, from: own) }, services)
    }

    private func sighting(_ session: Followed, _ holders: Holders) -> Sighting {
        let thread = session.thread, lines = session.lines
        let lock = ((folder ?? "") as NSString).appendingPathComponent("thread-writer-locks/\(thread.id).lock")
        let holder = [lock, thread.rollout].flatMap { [$0, HeldFiles.real($0)] }.lazy.compactMap { holders.files[$0] }.first
        var facts = StateMap.Facts(alive: nil, turnOpen: lines.open, lastWrite: session.stamp?.modified)
        if holder != nil {
            facts.alive = true
            facts.evidence = "lock"
        } else if !holders.others {
            facts.alive = false
            facts.evidence = "process"
        }
        facts.failed = lines.turns.last?.state == "error"
        facts.aborted = lines.turns.last?.state == "interrupted"
        var detail: [String: JSONValue] = [:]
        if let originator = thread.originator { detail["originator"] = .string(originator) }
        var sighting = Sighting(kind: kind, key: thread.id, pid: holder, facts: facts, folder: thread.folder, title: thread.title,
                                model: lines.model ?? thread.model, mode: lines.mode ?? thread.mode, effort: lines.effort ?? thread.effort, started: thread.started,
                                updated: session.stamp?.modified, turns: lines.turns, complete: lines.complete, error: lines.error, detail: detail)
        // A background service has no window to quit it from: the gesture that frees the conversation is said instead.
        if let holder, holders.services.contains(holder) { sighting.because["resume"] = CodexDriver.heldByService }
        return sighting
    }
}

/// The turns of one Codex rollout, folded line by line from whitelisted fields only: the turn marks, the settings of
/// each turn, and the finished items (the person's and the agent's texts, the reasoning summaries, the commands, the
/// files changed and the tools called, never their outputs).
struct CodexRollout {
    let thread: String
    private(set) var turns: [Turn] = []
    /// false once turns before those read are missing.
    var complete = true
    private(set) var model: String?, effort: String?, mode: String?, error: AgentError?

    init(thread: String) { self.thread = thread }

    /// Whether the last turn runs; nil when no turn was seen.
    var open: Bool? { turns.last.map { $0.state == "working" } }

    mutating func add(_ line: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else { return }
        let at = object["timestamp"] as? String ?? ""
        switch (object["type"] as? String, payload["type"] as? String) {
        case ("turn_context", _):
            model = payload["model"] as? String ?? model
            effort = payload["effort"] as? String ?? effort
            mode = payload["approval_policy"] as? String ?? mode
        case ("event_msg", "task_started"):
            close("unknown", at: nil)
            // A new turn: an error of an earlier one is past.
            error = nil
            open(payload["turn_id"] as? String ?? "\(thread)/\(turns.count)", at: at)
        case ("event_msg", "task_complete"):
            if let failure = payload["error"] as? [String: Any] {
                error = AgentError(code: "AGENT_ERROR", message: failure["message"] as? String ?? "Codex could not finish the turn.")
                close("error", at: at)
            } else {
                close("done", at: at)
            }
        case ("event_msg", "turn_aborted"): close("interrupted", at: at)
        case ("event_msg", "item_completed"):
            guard let item = payload["item"] as? [String: Any], let made = CodexRollout.item(item, at: at, fallback: "\(thread)/\(at)") else { return }
            if turns.last?.state != "working" { open(payload["turn_id"] as? String ?? made.id, at: at) }
            turns[turns.count - 1].items = Array((turns[turns.count - 1].items + [made]).suffix(Limits.items))
        default: break
        }
    }

    /// The contract's item for one finished Codex item; nil for a kind that shows nothing to the person.
    static func item(_ item: [String: Any], at: String, fallback: String) -> Item? {
        let id = item["id"] as? String ?? fallback
        func texts(_ key: String, type: String) -> String {
            ((item[key] as? [[String: Any]]) ?? []).filter { $0["type"] as? String == type }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        func tool(_ name: String, _ text: String) -> Item {
            let status = ["completed": "done", "failed": "failed"][item["status"] as? String ?? ""] ?? "running"
            return Item(id: id, kind: "tool", author: "agent", text: text.isEmpty ? name : text, at: at, tool: Tool(name: name, status: status))
        }
        switch item["type"] as? String {
        case "UserMessage":
            let text = texts("content", type: "text")
            return text.isEmpty ? nil : Item(id: id, kind: "message", author: "person", text: text, at: at)
        case "AgentMessage":
            let text = texts("content", type: "Text")
            return text.isEmpty ? nil : Item(id: id, kind: "message", author: "agent", text: text, at: at)
        case "Reasoning":
            let text = ((item["summary_text"] as? [String]) ?? []).joined(separator: "\n")
            return text.isEmpty ? nil : Item(id: id, kind: "thought", author: "agent", text: text, at: at)
        case "CommandExecution": return tool("shell", ((item["command"] as? [String]) ?? []).joined(separator: " "))
        case "FileChange": return tool("apply_patch", ((item["changes"] as? [String: Any]) ?? [:]).keys.sorted().joined(separator: ", "))
        case "McpToolCall": return tool([item["server"], item["tool"]].compactMap { $0 as? String }.joined(separator: "."), item["tool"] as? String ?? "")
        case "WebSearch": return tool("web_search", item["query"] as? String ?? "")
        case "SubAgentActivity":
            return Item(id: id, kind: "subagent", author: "agent", text: item["agent_path"] as? String ?? "a sub-agent", at: at,
                        tool: Tool(name: "subagent", status: item["kind"] as? String == "completed" ? "done" : "running"))
        default: return nil
        }
    }

    private mutating func open(_ id: String, at: String) {
        turns.append(Turn(id: id, state: "working", started: at.isEmpty ? nil : at, ended: nil, items: []))
        if turns.count > Limits.turns { turns.removeFirst(); complete = false }
    }

    private mutating func close(_ state: String, at: String?) {
        guard let last = turns.indices.last, turns[last].state == "working" else { return }
        turns[last].state = state
        turns[last].ended = at.flatMap { $0.isEmpty ? nil : $0 }
    }
}
