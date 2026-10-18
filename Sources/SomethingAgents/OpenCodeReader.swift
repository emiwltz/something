// OpenCodeReader: the OpenCode conversations started elsewhere (a terminal, OpenCode's background service), read from
// OpenCode's own database, never through its program. OpenCode 2 keeps every session in one SQLite file:
// `session_v2` for the sessions, `session_message` for their messages, whose `data` is read only through the JSON
// paths named here. The database is queried again only when its file or its log moved. A run takes a claim on its
// session (`time_suspended`) and releases it at its end; a run cut by a crash or a shutdown leaves it set, so a claim
// counts only when a live OpenCode process could hold it. The database says nothing of what a session waits on,
// so `waiting` is null.
import Darwin
import Foundation
import SomethingCore

final class OpenCodeReader: Reader {
    let kind = "opencode"
    let programs: Set<String> = ["opencode"]
    /// $OPENCODE_DB, else opencode.db in OpenCode's data folder; nil when the environment names no home.
    let database: String?
    /// something's own pid: the agents it launched run in groups whose leader is its child, and hold no claim of
    /// a conversation seen elsewhere. A test names another.
    var own = getpid()
    /// Sees every path the reader opens.
    var opened: (String) -> Void = { _ in }

    /// The columns the reader may use, and the guard asks for; `data` is read only through json_extract.
    static let whitelist: [String: Set<String>] = [
        "session_v2": ["id", "parent_id", "directory", "title", "agent", "model", "time_created", "time_updated", "time_archived",
                       "time_suspended", "time_idle", "idle_outcome", "version"],
        "session_message": ["id", "session_id", "type", "seq", "time_created", "time_updated"],
        "migration": ["id"],
    ]
    /// The messages a session's turns are folded from: at most this many of its last.
    static let messages = 300
    static let mayResume = "OpenCode's background service may continue this conversation by itself the next time it starts."
    static let desktop = "OpenCode desktop 1.x still writes conversations in the 1.x format, which something does not read: they are not shown."

    struct Session: Equatable {
        var id: String, folder: String?, title: String?, model: String?, effort: String?, mode: String?
        var started: Date?, updated: Date?
        /// When a run claimed the session (`time_suspended`); nil when no run holds it.
        var claimed: Date?
        var outcome: String?
        /// Its turns, folded from its last messages.
        var fold: OpenCodeTurns
    }

    private var stamps: [Stamp?] = []
    private var last = Reading()
    private var sessions: [Session] = []

    init(environment: [String: String]) { database = ACPDriver.database(environment) }

    func read(_ snapshot: Snapshot, discover: Bool, now: Date) -> Reading {
        guard let database else { return Reading() }
        let current = [Stamp(database), Stamp(database + "-wal")]
        guard current[0] != nil else { return Reading() }
        if current != stamps {
            (last, sessions) = query(database, now: now)
            // A refusal may pass (a checkpoint holding the file past the busy timeout): the next tick asks again.
            if last.health != "unreadable" { stamps = current }
        }
        var reading = last
        reading.sightings = sessions.map { sighting($0, snapshot) }
        return reading
    }

    /// What the database says now: its version, its health and its recent sessions with their turns. OpenCode desktop
    /// 1.x still writes the 1.x tables, which OpenCode 2 left frozen when it moved its sessions: a write there in the
    /// last 24 hours is a source something does not read, and the person is told.
    private func query(_ path: String, now: Date) -> (Reading, [Session]) {
        opened(path)
        let unreadable = Reading(health: "unreadable", note: "something cannot read OpenCode's database; check its permissions.")
        guard let db = try? SQLiteRO(path, whitelist: OpenCodeReader.whitelist), let tables = try? db.tables() else { return (unreadable, []) }
        // The schema's last migration says which format the file has, not which OpenCode wrote it: it is the version
        // only when no session names its program's.
        let migrations = tables["migration"] == nil ? [] : (try? db.rows("SELECT max(id) AS version FROM migration")) ?? []
        var version = migrations.first?["version"] as? String
        guard tables["session_v2"] != nil || tables["session"] == nil else {
            return (Reading(version: version, health: "changed", note: "This OpenCode database is in the 1.x format, which OpenCode desktop 1.x "
                            + "still writes; something reads OpenCode 2 only, so its agents are shown as processes only."), [])
        }
        guard (try? db.guarded()) == true else {
            return (Reading(version: version, health: "changed", note: "OpenCode's database changed shape; its agents are shown as processes only."), [])
        }
        let newest = try? db.rows("SELECT version FROM session_v2 WHERE version != '' ORDER BY time_updated DESC LIMIT 1")
        version = newest?.first?["version"] as? String ?? version
        let since = (now.timeIntervalSince1970 - Watch.recent) * 1000
        // An aggregate returns no stored column: the 1.x table needs no place on the whitelist.
        let legacy = tables["session"]?.contains("time_updated") == true ? (try? db.rows("SELECT max(time_updated) AS last FROM session")) : nil
        let note = (SQLiteRO.number(legacy?.first?["last"]) ?? 0) >= since ? OpenCodeReader.desktop : nil
        guard let rows = try? db.rows("""
            SELECT s.id, s.directory, s.title, s.agent, json_extract(s.model, '$.id') AS model, json_extract(s.model, '$.variant') AS variant,
                   s.time_created, s.time_suspended, s.idle_outcome,
                   max(s.time_updated, ifnull(s.time_idle, 0),
                       ifnull((SELECT max(m.time_updated) FROM session_message m WHERE m.session_id = s.id), 0)) AS last_write
            FROM session_v2 s WHERE s.parent_id IS NULL AND s.time_archived IS NULL AND (s.time_suspended IS NOT NULL OR last_write >= ?)
            ORDER BY last_write DESC LIMIT 100
            """, [since]) else { return (unreadable, []) }
        var found: [Session] = []
        for row in rows {
            guard let id = row["id"] as? String else { continue }
            func text(_ key: String) -> String? { (row[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
            var session = Session(id: id, folder: text("directory"), title: text("title"), model: text("model"), effort: text("variant"),
                                  mode: text("agent"), started: OpenCodeReader.date(row["time_created"]), updated: OpenCodeReader.date(row["last_write"]),
                                  claimed: OpenCodeReader.date(row["time_suspended"]), outcome: text("idle_outcome"), fold: OpenCodeTurns(session: id))
            // A session whose last write did not move keeps the turns read before.
            if let known = sessions.first(where: { $0.id == id }), known.updated == session.updated, known.claimed == session.claimed {
                session.fold = known.fold
            } else if let fold = turns(of: id, db) {
                session.fold = fold
            } else {
                return (unreadable, [])
            }
            found.append(session)
        }
        return (Reading(version: version, health: "ok", note: note), found)
    }

    /// The turns of `session`, folded from its last messages; nil when the database refused the query.
    private func turns(of session: String, _ db: SQLiteRO) -> OpenCodeTurns? {
        // One message more than kept says whether older ones were left out.
        guard let fetched = try? db.rows("""
            SELECT id, seq, type, time_created, json_extract(data, '$.text') AS text, json_extract(data, '$.outcome') AS outcome,
                   json_extract(data, '$.finish') AS finish, json_extract(data, '$.error.message') AS failure
            FROM session_message WHERE session_id = ? AND type IN ('user', 'assistant', 'idle') ORDER BY seq DESC LIMIT ?
            """, [session, OpenCodeReader.messages + 1]) else { return nil }
        let messages = fetched.prefix(OpenCodeReader.messages)
        let first: Any = messages.last?["seq"] ?? Int64(0)
        // json_each walks an assistant message's blocks; only the paths named here leave the database.
        guard let blocks = try? db.rows("""
            SELECT m.id AS message, json_extract(c.value, '$.type') AS type, json_extract(c.value, '$.text') AS text,
                   json_extract(c.value, '$.id') AS tool, json_extract(c.value, '$.name') AS name, json_extract(c.value, '$.state.status') AS status,
                   coalesce(json_extract(c.value, '$.state.input.command'), json_extract(c.value, '$.state.input.filePath'),
                            json_extract(c.value, '$.state.input.pattern'), json_extract(c.value, '$.state.input.url'),
                            json_extract(c.value, '$.state.input.description'), json_extract(c.value, '$.state.input.prompt')) AS target
            FROM session_message m, json_each(m.data, '$.content') c
            WHERE m.session_id = ? AND m.type = 'assistant' AND m.seq >= ? ORDER BY m.seq, c.key
            """, [session, first]) else { return nil }
        var fold = OpenCodeTurns(session: session)
        fold.complete = fetched.count <= OpenCodeReader.messages
        let byMessage = Dictionary(grouping: blocks) { $0["message"] as? String ?? "" }
        for message in messages.reversed() { fold.add(message, blocks: byMessage[message["id"] as? String ?? ""] ?? []) }
        return fold
    }

    /// The claim-and-holder rule: a claim taken at t is held only by a live OpenCode process started at or
    /// before t, that does not descend from something. Without a claim, no such OpenCode process proves the session
    /// idle in no process; one of them leaves it unknown.
    private func sighting(_ session: Session, _ snapshot: Snapshot) -> Sighting {
        let others = snapshot.processes.values.filter { programs.contains($0.name) && !snapshot.descends($0.pid, from: own) }.sorted { $0.pid < $1.pid }
        var facts = StateMap.Facts(alive: nil, lastWrite: session.updated)
        var turns = session.fold.turns, holder: Int32?, because: [String: String] = [:]
        if let claimed = session.claimed {
            holder = others.first { $0.started <= claimed }?.pid
            facts.alive = holder != nil
            facts.evidence = "claim"
            facts.turnOpen = true
            if holder == nil {
                because["resume"] = OpenCodeReader.mayResume
                OpenCodeReader.close(&turns, "interrupted")
            }
        } else {
            let ended = ["succeeded": "done", "failed": "error", "interrupted": "interrupted"][session.outcome ?? ""]
            OpenCodeReader.close(&turns, ended ?? (session.fold.finish == "stop" ? "done" : "unknown"))
            facts.turnOpen = turns.isEmpty ? nil : false
            facts.failed = session.outcome == "failed"
            facts.aborted = session.outcome == "interrupted"
            if others.isEmpty {
                facts.alive = false
                facts.evidence = "process"
            }
        }
        var sighting = Sighting(kind: kind, key: session.id, pid: holder, facts: facts, folder: session.folder, title: session.title,
                                model: session.model, mode: session.mode, effort: session.effort, started: session.started,
                                updated: session.updated, turns: turns, complete: session.fold.complete, error: session.fold.error)
        sighting.because = because
        return sighting
    }

    /// Ends the last turn as `state`, if it still runs.
    private static func close(_ turns: inout [Turn], _ state: String) {
        guard let last = turns.indices.last, turns[last].state == "working" else { return }
        turns[last].state = state
    }

    /// An OpenCode time, in Unix milliseconds.
    static func date(_ value: Any?) -> Date? { SQLiteRO.number(value).map { Date(timeIntervalSince1970: $0 / 1000) } }
}

/// The turns of one OpenCode session, folded message by message: a person's message opens a turn, an `idle` mark
/// closes it with its outcome, and an assistant message adds its texts, its reasoning and its tool calls (their name
/// and what they act on, never their output).
struct OpenCodeTurns: Equatable {
    let session: String
    private(set) var turns: [Turn] = []
    var complete = true
    private(set) var error: AgentError?
    /// How the last assistant step ended: "stop" ends a turn that OpenCode 1.x closed without an idle mark.
    private(set) var finish: String?

    init(session: String) { self.session = session }

    mutating func add(_ message: [String: Any], blocks: [[String: Any]]) {
        let id = message["id"] as? String ?? "\(session)/\(turns.count)"
        let at = OpenCodeReader.date(message["time_created"]).map(Watch.iso) ?? ""
        switch message["type"] as? String {
        case "user":
            guard let text = message["text"] as? String, !text.isEmpty else { return }
            close(finish == "stop" ? "done" : "unknown", at: nil)
            // A new turn: an error of an earlier one is past.
            error = nil
            open(id, at: at)
            append(Item(id: id, kind: "message", author: "person", text: text, at: at))
        case "assistant":
            finish = message["finish"] as? String
            if finish == "error" { error = AgentError(code: "AGENT_ERROR", message: message["failure"] as? String ?? "OpenCode could not finish the turn.") }
            for (index, block) in blocks.enumerated() {
                let text = block["text"] as? String ?? "", item = "\(id)/\(index)"
                switch block["type"] as? String {
                case "text" where !text.isEmpty: append(Item(id: item, kind: "message", author: "agent", text: text, at: at))
                case "reasoning" where !text.isEmpty: append(Item(id: item, kind: "thought", author: "agent", text: text, at: at))
                case "tool":
                    let name = block["name"] as? String ?? "a tool"
                    let status = ["completed": "done", "error": "failed"][block["status"] as? String ?? ""] ?? "running"
                    append(Item(id: block["tool"] as? String ?? item, kind: name == "task" ? "subagent" : "tool", author: "agent",
                                text: block["target"] as? String ?? name, at: at, tool: Tool(name: name, status: status)))
                default: break
                }
            }
        case "idle":
            close(["succeeded": "done", "failed": "error", "interrupted": "interrupted"][message["outcome"] as? String ?? ""] ?? "unknown", at: at)
        default: break
        }
    }

    private mutating func open(_ id: String, at: String) {
        turns.append(Turn(id: id, state: "working", started: at.isEmpty ? nil : at, ended: nil, items: []))
        if turns.count > Limits.turns { turns.removeFirst(); complete = false }
    }

    /// Adds `item` to the running turn, or to a new one: a step whose person's message was not read still opens one.
    private mutating func append(_ item: Item) {
        if turns.last?.state != "working" { open(item.id, at: item.at) }
        turns[turns.count - 1].items = Array((turns[turns.count - 1].items + [item]).suffix(Limits.items))
    }

    private mutating func close(_ state: String, at: String?) {
        guard let last = turns.indices.last, turns[last].state == "working" else { return }
        turns[last].state = state
        turns[last].ended = at.flatMap { $0.isEmpty ? nil : $0 }
    }
}
