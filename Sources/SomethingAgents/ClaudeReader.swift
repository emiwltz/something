// ClaudeReader: the Claude Code sessions started elsewhere (a terminal, the desktop app, an editor), read from Claude's
// own files, never through its program (design 4.2). The registry, `sessions/<pid>.json`, one small file per running
// session, says which process holds which conversation and what it waits on; the transcript,
// `projects/<folder>/<id>.jsonl`, gives its turns, from whitelisted fields only. The `.key` files beside the registry
// hold secrets: only names matching `^\d+\.json$` are ever opened. `claude agents --json` is never run, since it can
// delete records. A stale record (its process gone, or its pid reused) is ignored and never deleted.
import Darwin
import Foundation
import SomethingCore

final class ClaudeReader: Reader {
    let kind = "claude"
    let programs: Set<String> = ["claude"]
    /// Claude's folder: CLAUDE_CONFIG_DIR, else ~/.claude; nil when the environment names no home.
    let folder: String?
    /// Sees every path the reader opens: the tests prove the secrets are never among them.
    var opened: (String) -> Void = { _ in }

    /// The lines a transcript is read for; the others are never decoded.
    static let wanted = [#""type":"user""#, #""type":"assistant""#, #""type":"custom-title""#, #""type":"ai-title""#,
                         #""type":"permission-mode""#, #""queued_command""#, #""subtype":"turn_duration""#].map { Data($0.utf8) }
    /// Claude's own limit for a registry record.
    static let largestRecord = 262_144

    struct Record: Equatable {
        var pid: Int32, session: String, cwd: String?, procStart: Date, domain: String?
        var version: String?, status: String?, waitingFor: String?, name: String?, started: Date?, updated: Date?
    }

    private struct Session {
        var record: Record
        var alive: Bool?
        /// The conversation closed normally: its record was removed, or now names another conversation.
        var ended = false
        var transcript: String?
        var searched = false
        var stamp: Stamp?
        var cursor: Cursor?
        var lines: ClaudeTranscript
    }

    private var records: [String: (stamp: Stamp, record: Record?)] = [:]
    private var sessions: [String: Session] = [:]

    init(environment: [String: String]) {
        folder = environment["CLAUDE_CONFIG_DIR"] ?? environment["HOME"].map { ($0 as NSString).appendingPathComponent(".claude") }
    }

    func read(_ snapshot: Snapshot, discover: Bool, now: Date) -> Reading {
        guard let folder, ClaudeReader.isFolder(folder) else { return Reading() }
        var reading = Reading(health: "ok")
        let registry = (folder as NSString).appendingPathComponent("sessions")
        var names: [String] = []
        if ClaudeReader.isFolder(registry) {
            guard let listed = try? FileManager.default.contentsOfDirectory(atPath: registry) else {
                return Reading(health: "unreadable", note: "something cannot read Claude Code's sessions folder; check its permissions.")
            }
            names = listed.filter { $0.range(of: #"^\d+\.json$"#, options: .regularExpression) != nil }
        }
        records = records.filter { names.contains($0.key) }
        var current: [String: (record: Record, alive: Bool?)] = [:], stale: Set<Int32> = [], unread: Set<String> = []
        for name in names {
            let path = (registry as NSString).appendingPathComponent(name)
            guard let stamp = Stamp(path) else { continue }
            if records[name]?.stamp != stamp {
                // Claude rewrites a record whole at each change: one caught mid-write keeps its last reading (its old
                // stamp makes the next tick try again), and a session never read yet is left as it was, not ended.
                if stamp.size <= UInt64(ClaudeReader.largestRecord), let data = contents(path),
                   let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    if ["interactive", "bg", nil].contains(object["kind"] as? String) {
                        guard let record = ClaudeReader.record(object) else {
                            return Reading(health: "changed", note: "Claude Code's session files changed shape; its agents are shown as processes only.")
                        }
                        // Claude names each record after its pid: another name is no record of Claude's.
                        records[name] = (stamp, "\(record.pid).json" == name ? record : nil)
                    } else {
                        records[name] = (stamp, nil)
                    }
                } else if records[name] == nil {
                    unread.insert(name)
                }
            }
            guard let record = records[name]?.record else { continue }
            let alive = ClaudeReader.alive(record, snapshot)
            if alive == false { stale.insert(record.pid) } else { current[record.session] = (record, alive) }
            if alive == true, let version = record.version, version.compare(reading.version ?? "", options: .numeric) == .orderedDescending {
                reading.version = version
            }
        }
        for (id, (record, alive)) in current {
            // A conversation continued by a new process (a resume) is held again.
            var session = sessions[id] ?? Session(record: record, lines: ClaudeTranscript(session: id))
            session.record = record
            session.alive = alive
            session.ended = false
            sessions[id] = session
        }
        for (id, session) in sessions where current[id] == nil && session.alive != false && !unread.contains("\(session.record.pid).json") {
            // A record left behind by a process that is gone is a crash; one removed or moved on is a normal end.
            sessions[id]!.alive = false
            sessions[id]!.ended = !stale.contains(session.record.pid)
        }
        // A session whose record is there is kept, so that its transcript is not read again from its end; one that
        // ended is forgotten when Watch stops listing it.
        sessions = sessions.filter { current[$0.key] != nil || Watch.isRecent(alive: $0.value.alive, updated: ClaudeReader.updated($0.value), now: now) }
        for id in sessions.keys {
            follow(id, discover: discover)
            reading.sightings.append(sighting(sessions[id]!))
        }
        return reading
    }

    /// Reads what the session's transcript gained since the last tick, once found.
    private func follow(_ id: String, discover: Bool) {
        guard var session = sessions[id], let folder else { return }
        let projects = (folder as NSString).appendingPathComponent("projects")
        if session.transcript.map({ !FileManager.default.fileExists(atPath: $0) }) ?? true {
            let expected = session.record.cwd.map { "\(projects)/\(ClaudeReader.folderName($0))/\(id).jsonl" }
            session.transcript = expected.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
            // A start folder whose name Claude shortened, or that is not the record's, is found by the walk.
            if session.transcript == nil, discover || !session.searched {
                session.searched = true
                let found = ((try? FileManager.default.contentsOfDirectory(atPath: projects)) ?? [])
                    .map { "\(projects)/\($0)/\(id).jsonl" }.filter { FileManager.default.fileExists(atPath: $0) }
                session.transcript = found.count == 1 ? found[0] : nil
            }
        }
        if let path = session.transcript, let stamp = Stamp(path), stamp != session.stamp {
            opened(path)
            if let read = Tail.read(path, after: session.cursor, containing: ClaudeReader.wanted,
                                    enough: { $0.contains { $0.range(of: ClaudeReader.wanted[1]) != nil } }) {
                // A read from the file's end starts the turns over; one past a gap keeps them. Either way, turns
                // before what was read may be missing.
                if read.fresh { session.lines = ClaudeTranscript(session: id) }
                if read.gap || (read.fresh && !read.fromStart) { session.lines.complete = false }
                read.lines.forEach { session.lines.add($0) }
                session.cursor = read.cursor
                session.stamp = stamp
            }
        }
        sessions[id] = session
    }

    private func sighting(_ session: Session) -> Sighting {
        let record = session.record, lines = session.lines
        var facts = StateMap.Facts(alive: session.alive, evidence: session.alive == nil ? nil : "registry", lastWrite: session.stamp?.modified)
        var detail: [String: JSONValue] = [:]
        var known = true
        switch record.status {
        case "busy":
            facts.turnOpen = true
            facts.waiting = .nothing
        // "shell" is a session idle while a background shell it started still runs (notes/format-claude.md 1.3).
        case "idle", "shell":
            facts.turnOpen = false
            facts.waiting = .nothing
            if record.status == "shell" { detail["backgroundShell"] = .bool(true) }
        case "waiting":
            facts.turnOpen = true
            facts.waiting = ["permission prompt", "sandbox request"].contains(record.waitingFor) ? .permission : .answer
            if facts.waiting == .answer, let word = record.waitingFor { detail["waitingFor"] = .string(word) }
        // Older versions write no status: the transcript says whether a turn runs.
        case nil: facts.turnOpen = lines.open
        // A word this reader does not know says nothing it can trust: the state is unknown, never idle.
        case let word?:
            known = false
            detail["status"] = .string(word)
        }
        facts.ended = session.ended
        facts.failed = lines.turns.last?.state == "error"
        facts.aborted = lines.turns.last?.state == "interrupted"
        return Sighting(kind: kind, key: record.session, pid: record.pid, facts: facts, folder: record.cwd, title: lines.title ?? record.name,
                        model: lines.model, mode: lines.mode, effort: lines.effort, started: record.started,
                        updated: ClaudeReader.updated(session), turns: lines.turns, complete: lines.complete,
                        error: lines.error, detail: detail, stateKnown: known)
    }

    /// The last activity seen: the transcript's last write, else the record's own date.
    private static func updated(_ session: Session) -> Date? { session.stamp?.modified ?? session.record.updated }

    private func contents(_ path: String) -> Data? {
        opened(path)
        return FileManager.default.contents(atPath: path)
    }

    /// true when the record's process runs and started when the record says (a reused pid did not); nil when the
    /// pid belongs to another system's numbering (a container, a virtual machine) and cannot be checked here.
    static func alive(_ record: Record, _ snapshot: Snapshot) -> Bool? {
        if let domain = record.domain, domain != "darwin" { return nil }
        guard let process = snapshot[record.pid] else { return false }
        return abs(process.started.timeIntervalSince(record.procStart)) <= 1
    }

    /// The fields of a registry record, or nil when one the reader needs is missing or of another type.
    static func record(_ object: [String: Any]) -> Record? {
        guard let pid = object["pid"] as? Int, pid > 0, pid <= Int(Int32.max), let session = object["sessionId"] as? String,
              session.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil,
              let start = object["procStart"] as? String, let procStart = processStart(start) else { return nil }
        func milliseconds(_ key: String) -> Date? { (object[key] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } }
        return Record(pid: Int32(pid), session: session, cwd: object["cwd"] as? String, procStart: procStart, domain: object["pidDomain"] as? String,
                      version: object["version"] as? String, status: object["status"] as? String, waitingFor: object["waitingFor"] as? String,
                      name: (object["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }, started: milliseconds("startedAt"), updated: milliseconds("updatedAt"))
    }

    /// `procStart` as Claude writes it: `ps -o lstart=` in the C locale and UTC ("Fri Oct  6 19:59:24 2026").
    static func processStart(_ text: String) -> Date? {
        let formatter = DateFormatter()
        (formatter.locale, formatter.timeZone, formatter.dateFormat) = (Locale(identifier: "en_US_POSIX"), TimeZone(identifier: "UTC"), "EEE MMM d HH:mm:ss yyyy")
        return formatter.date(from: text.split(separator: " ").joined(separator: " "))
    }

    /// The name of the folder Claude keeps a project's transcripts in: every UTF-16 unit of the path that is not an
    /// ASCII letter or digit becomes "-". Claude shortens names over 200 units with a hash: those are found by the walk.
    static func folderName(_ path: String) -> String {
        String(decoding: path.utf16.map { unit -> UInt8 in
            switch unit {
            case 48...57, 65...90, 97...122: return UInt8(unit)
            default: return UInt8(ascii: "-")
            }
        }, as: UTF8.self)
    }

    static func isFolder(_ path: String) -> Bool {
        var folder: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &folder) && folder.boolValue
    }
}

/// What tells whether a file changed since the last tick, without reading it.
struct Stamp: Equatable {
    var modified: Date, size: UInt64, inode: UInt64

    init?(_ path: String) {
        var status = stat()
        guard stat(path, &status) == 0 else { return nil }
        modified = Date(timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec) + TimeInterval(status.st_mtimespec.tv_nsec) / 1e9)
        size = UInt64(max(status.st_size, 0))
        inode = UInt64(status.st_ino)
    }
}

/// The turns of one Claude transcript, folded line by line from whitelisted fields only: the person's and the agent's
/// texts, the agent's thoughts, tool names and what they act on, titles, model, effort and mode.
struct ClaudeTranscript {
    let session: String
    private(set) var turns: [Turn] = []
    /// false once turns before those read are missing: dropped past the limit, or never read.
    var complete = true
    private(set) var model: String?, effort: String?, mode: String?, error: AgentError?
    private var customTitle: String?, aiTitle: String?
    /// The message.id of the reply that closed the last turn: Claude writes one reply as one line per block, each
    /// with the reply's final stop_reason, so the blocks after the first that says end_turn still belong to that turn.
    private var closedBy: String?

    init(session: String) { self.session = session }

    /// The person's title wins over the one Claude made up.
    var title: String? { customTitle ?? aiTitle }
    /// Whether the last turn runs; nil when no turn was seen.
    var open: Bool? { turns.last.map { $0.state == "working" } }

    /// The keys of a tool's input that say what it acts on, in order of preference; nothing else of the input is shown.
    static let targets = ["command", "file_path", "path", "pattern", "url", "query", "description", "prompt"]

    mutating func add(_ line: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], object["isSidechain"] as? Bool != true else { return }
        let at = object["timestamp"] as? String ?? "", id = object["uuid"] as? String ?? "\(session)/\(turns.count)"
        switch object["type"] as? String {
        case "custom-title": customTitle = object["customTitle"] as? String ?? customTitle
        case "ai-title": aiTitle = object["aiTitle"] as? String ?? aiTitle
        case "permission-mode": mode = object["permissionMode"] as? String ?? mode
        case "system" where object["subtype"] as? String == "turn_duration": close("done", at: at)
        case "attachment":
            let attachment = object["attachment"] as? [String: Any] ?? [:]
            guard attachment["type"] as? String == "queued_command", let prompt = attachment["prompt"] as? String,
                  ClaudeTranscript.byPerson(attachment["origin"]) else { return }
            append(Item(id: id, kind: "message", author: "person", text: prompt, at: at), at: at)
        case "user": user(object, id: id, at: at)
        case "assistant": assistant(object, id: id, at: at)
        default: break
        }
    }

    private mutating func user(_ object: [String: Any], id: String, at: String) {
        let message = object["message"] as? [String: Any] ?? [:], blocks = message["content"] as? [[String: Any]] ?? []
        mode = object["permissionMode"] as? String ?? mode
        let results = blocks.filter { $0["type"] as? String == "tool_result" }
        for result in results {
            guard let tool = result["tool_use_id"] as? String else { continue }
            update(tool) { $0.tool?.status = result["is_error"] as? Bool == true ? "failed" : "done" }
        }
        guard results.isEmpty, object["isMeta"] as? Bool != true, ClaudeTranscript.byPerson(object["origin"]) else { return }
        let text = message["content"] as? String ?? blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        guard !text.isEmpty else { return }
        // Claude writes the person's interrupt as a message of its own: it ends the turn, and says nothing.
        if text.hasPrefix("[Request interrupted by user") { return close("interrupted", at: at) }
        if turns.last?.state == "working" { close("unknown", at: nil) }
        append(Item(id: id, kind: "message", author: "person", text: text, at: at), at: at)
    }

    private mutating func assistant(_ object: [String: Any], id: String, at: String) {
        let message = object["message"] as? [String: Any] ?? [:], blocks = message["content"] as? [[String: Any]] ?? []
        // Claude writes its own failures, and some notices, as a message from a "<synthetic>" model: not the agent speaking.
        guard message["model"] as? String != "<synthetic>", object["isApiErrorMessage"] as? Bool != true else {
            guard object["isApiErrorMessage"] as? Bool == true else { return }
            let text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
            error = AgentError(code: "AGENT_ERROR", message: text.isEmpty ? "Claude Code could not answer." : text)
            return close("error", at: at)
        }
        model = message["model"] as? String ?? model
        effort = object["effort"] as? String ?? effort
        let reply = message["id"] as? String
        let continuing = reply != nil && reply == closedBy && turns.last?.state == "done"
        for (index, block) in blocks.enumerated() {
            switch block["type"] as? String {
            case "text": append(Item(id: "\(id)/\(index)", kind: "message", author: "agent", text: block["text"] as? String ?? "", at: at), at: at, continuing: continuing)
            case "thinking":
                guard let text = block["thinking"] as? String, !text.isEmpty else { continue }
                append(Item(id: "\(id)/\(index)", kind: "thought", author: "agent", text: text, at: at), at: at, continuing: continuing)
            case "tool_use":
                let name = block["name"] as? String ?? "a tool", input = block["input"] as? [String: Any] ?? [:]
                let target = ClaudeTranscript.targets.lazy.compactMap { input[$0] as? String }.first { !$0.isEmpty } ?? name
                append(Item(id: block["id"] as? String ?? "\(id)/\(index)", kind: ["Agent", "Task"].contains(name) ? "subagent" : "tool",
                            author: "agent", text: target, at: at, tool: Tool(name: name, status: "running")), at: at, continuing: continuing)
            default: break
            }
        }
        if continuing, !at.isEmpty { turns[turns.count - 1].ended = at }
        if message["stop_reason"] as? String == "end_turn", !continuing {
            close("done", at: at)
            closedBy = reply
        }
    }

    /// A message with no origin is the person's (older versions write none); a peer's or a task's is not.
    private static func byPerson(_ origin: Any?) -> Bool {
        guard let kind = (origin as? [String: Any])?["kind"] as? String else { return true }
        return kind == "human"
    }

    /// Adds `item` to the running turn, or to a new one: a reply nobody was seen asking for still opens a turn.
    /// `continuing` adds it to the last turn, closed by the reply the item belongs to.
    private mutating func append(_ item: Item, at: String, continuing: Bool = false) {
        if turns.last?.state != "working" && !continuing {
            turns.append(Turn(id: item.id, state: "working", started: at.isEmpty ? nil : at, ended: nil, items: []))
            if turns.count > Limits.turns { turns.removeFirst(); complete = false }
        }
        turns[turns.count - 1].items = Array((turns[turns.count - 1].items + [item]).suffix(Limits.items))
    }

    private mutating func update(_ id: String, _ change: (inout Item) -> Void) {
        for t in turns.indices.reversed() {
            if let i = turns[t].items.firstIndex(where: { $0.id == id }) { return change(&turns[t].items[i]) }
        }
    }

    private mutating func close(_ state: String, at: String?) {
        guard let last = turns.indices.last, turns[last].state == "working" else { return }
        turns[last].state = state
        turns[last].ended = at.flatMap { $0.isEmpty ? nil : $0 }
    }
}
