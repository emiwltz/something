// PiReader: the pi conversations started elsewhere (a terminal), read from pi's own files, never through its program.
// pi writes one JSONL log per conversation, under ~/.pi/agent/sessions/<folder>/, or flat in the
// sessions folder of another agent folder (~/.pi/<name>/sessions, which a shell alias can choose); its first line is
// a `session` header that names the conversation's folder. pi holds no file open and takes no lock, so a process is
// tied to a log by its working folder only (evidence "cwd", the weakest): one pi in a folder holds the log of that
// folder written last, if written since it started; two pi in one folder cannot be told apart, and neither claim is
// made. pi writes a log at its first message: a pi with none is seen from its process only. PiLog, the fold of a log,
// is OMP's too.
import Foundation
import SomethingAgents
import SomethingCore

final class PiReader: Reader {
    let kind = "pi"
    /// pi is a Node program that renames itself: the system names its process node, its first argument is pi (pi-rpc
    /// under --mode rpc).
    let programs: Set<String> = ["node", "pi", "pi-rpc"]
    static let names: Set<String> = ["pi", "pi-rpc"]
    /// ~/.pi, whose agent folders each keep a sessions folder; nil when the environment names no home.
    let folder: String?
    /// The sessions folders the environment names (PI_CODING_AGENT_DIR, PI_CODING_AGENT_SESSION_DIR).
    let named: [String]
    /// Sees every path the reader opens.
    var opened: (String) -> Void = { _ in }

    /// The logs the last walk listed.
    private var logs: [String] = []
    /// The headers read, by path, with the inode they were read from: a log replaced since is read again.
    private var headers: [String: (inode: UInt64, header: PiLog.Header?)] = [:]
    private var walked = false
    private var pids: Set<Int32> = []
    private var files: [String: PiFile] = [:]
    /// The logs too old to list when last looked at: a tick looks at them again only when it walks or a pi runs in
    /// their folder.
    private var old: Set<String> = []
    /// Each folder with its links resolved, until the next walk.
    private var real = HeldFiles.remembered()

    init(environment: [String: String]) {
        folder = environment["HOME"].map { ($0 as NSString).appendingPathComponent(".pi") }
        named = [environment["PI_CODING_AGENT_DIR"].map { ($0 as NSString).appendingPathComponent("sessions") },
                 environment["PI_CODING_AGENT_SESSION_DIR"]].compactMap { $0 }
    }

    func owns(_ process: Running) -> Bool { process.runs(PiReader.names) != nil }

    func read(_ snapshot: Snapshot, discover: Bool, now: Date) -> Reading {
        guard folder.map(PiReader.isFolder) == true || !named.isEmpty else { return Reading() }
        // The pi something launched count when the pi of a folder are counted: a log of that folder may be theirs.
        let every = snapshot.processes.values.filter(owns)
        let running = Set(every.map(\.pid))
        // A pi started since the last walk may have begun a log in a folder the walk has not listed.
        let walking = discover || !walked || running != pids
        if walking {
            walked = true
            pids = running
            walk()
        }
        let here = Dictionary(grouping: every) { $0.folder.map(real) ?? "" }
        var stamps: [String: Stamp] = [:], byFolder: [String: [String]] = [:]
        for path in logs {
            // An old log written again where no pi runs is seen at the next walk, at most 15 ticks later.
            guard walking || !old.contains(path) || headers[path]?.header.map({ here[real($0.folder)] != nil }) == true,
                  let stamp = Stamp(path) else { continue }
            if headers[path]?.inode != stamp.inode { headers[path] = (stamp.inode, PiLog.header(path, line: 0, opened: opened)) }
            guard let header = headers[path]?.header else { continue }
            stamps[path] = stamp
            byFolder[real(header.folder), default: []].append(path)
            if Watch.isRecent(alive: nil, updated: stamp.modified, now: now) { old.remove(path) } else { old.insert(path) }
        }
        var reading = Reading(health: "ok"), followed: [String: PiFile] = [:], shown: Set<String> = []
        for (place, paths) in byFolder {
            for (path, holder) in PiReader.holders(paths, stamps, pi: here[place] ?? [])
            where holder.alive == true || Watch.isRecent(alive: nil, updated: stamps[path]?.modified, now: now) {
                guard let header = headers[path]?.header, let stamp = stamps[path] else { continue }
                var file = files[path] ?? PiFile(path: path, header: header, log: PiLog(name: "pi"))
                file.header = header
                file.follow(stamp, skip: 0, opened: opened)
                followed[path] = file
                if holder.alive != false { shown.insert(place) }
                var facts = StateMap.Facts(alive: holder.alive, evidence: holder.alive == true ? "cwd" : holder.alive == false ? "process" : nil,
                                           turnOpen: file.log.open, waiting: .nothing, lastWrite: file.stamp?.modified)
                facts.failed = file.log.turns.last?.state == "error"
                facts.aborted = file.log.turns.last?.state == "interrupted"
                reading.sightings.append(file.sighting(kind, key: path, pid: holder.pid, facts: facts))
            }
        }
        files = followed
        // A pi whose folder shows no log it may hold has not written its log yet, or wrote it too long ago to be
        // listed: it is seen from its process. The pi something launched are its own, and the watch drops them.
        for (place, pi) in here where !shown.contains(place) {
            reading.sightings += pi.map { process in
                Sighting(kind: kind, key: "pid-\(process.pid)", pid: process.pid, facts: StateMap.Facts(alive: true, evidence: "process"),
                         folder: process.folder, started: process.started, processOnly: true)
            }
        }
        return reading
    }

    /// Lists the logs of every sessions folder.
    private func walk() {
        let agentFolders = folder.map { root in ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []).map { "\(root)/\($0)/sessions" } } ?? []
        logs = PiLog.logs(in: (agentFolders + named).filter(PiReader.isFolder))
        let listed = Set(logs)
        headers = headers.filter { listed.contains($0.key) }
        old.formIntersection(listed)
        real = HeldFiles.remembered()
    }

    /// Who holds each of one folder's logs, from the pi running in that folder. One pi holds the log written last,
    /// if written since it started. Several cannot be told apart: a log written since the first started may be any
    /// one's. Any other log is held by none.
    static func holders(_ paths: [String], _ stamps: [String: Stamp], pi: [Running]) -> [String: (alive: Bool?, pid: Int32?)] {
        // A second of slack: a time on disk and a process's start are not taken by the same clock read.
        let since = pi.map(\.started).min().map { $0.addingTimeInterval(-1) } ?? .distantFuture
        let newest = paths.max { (stamps[$0]?.modified ?? .distantPast) < (stamps[$1]?.modified ?? .distantPast) }
        var holders: [String: (alive: Bool?, pid: Int32?)] = [:]
        for path in paths {
            let written = (stamps[path]?.modified ?? .distantPast) >= since
            if pi.count == 1, written, path == newest {
                holders[path] = (true, pi[0].pid)
            } else if pi.count > 1, written {
                holders[path] = (nil, nil)
            } else {
                holders[path] = (false, nil)
            }
        }
        return holders
    }
}

/// One pi or OMP log followed from tick to tick.
struct PiFile {
    let path: String
    var header: PiLog.Header
    var stamp: Stamp?
    var cursor: Cursor?
    var log: PiLog
    /// OMP's title slot, read again whenever the file changes.
    var title: String?

    /// Reads what the file gained since `self.stamp`. The first `skip` bytes are a slot the harness rewrites in place
    /// (OMP's title): their change is no rewrite of the file.
    mutating func follow(_ now: Stamp, skip: Int, opened: (String) -> Void) {
        guard now != stamp else { return }
        opened(path)
        guard let read = Tail.read(path, after: cursor, containing: [PiLog.typed], skippingHead: skip,
                                   enough: { $0.contains { $0.range(of: Data(#""role":"user""#.utf8)) != nil } }) else { return }
        // A read from the file's end starts the conversation over; one past a gap keeps it. Either way, entries before
        // what was read may be missing.
        if read.fresh { log = PiLog(name: log.name) }
        if read.gap || (read.fresh && !read.fromStart) { log.readFromStart = false }
        log.add(read.lines)
        cursor = read.cursor
        stamp = now
    }

    func sighting(_ kind: String, key: String, pid: Int32?, facts: StateMap.Facts) -> Sighting {
        Sighting(kind: kind, key: key, pid: pid, facts: facts, folder: header.folder, title: title ?? log.title, model: log.model, effort: log.effort,
                 started: header.started, updated: stamp?.modified, turns: log.turns, complete: log.complete, error: log.error)
    }
}

/// The conversation of one pi or OMP log, folded from whitelisted fields only: the person's and the agent's texts,
/// thoughts, tool names and what they act on, the model and the thinking level. The log is a tree: each entry names
/// its parent, and the conversation is the branch that ends at the entry written last, as pi and OMP show it; the
/// entries of a branch left behind (a message edited or retried) stay in the file and are not shown.
struct PiLog {
    /// What a log line is known by before it is decoded.
    static let typed = Data(#""type":""#.utf8)
    /// The keys of a tool call's arguments that say what it acts on, in order of preference; nothing else is shown.
    static let targets = ["command", "path", "pattern", "url", "query"]
    /// Entries kept, so that a log of hours keeps its last turns without holding every line.
    static let kept = 5_000

    struct Header: Equatable {
        var id: String, folder: String, started: Date?
    }

    private struct Message {
        var role: String, at: String
        var items: [Item] = []
        var stop: String?, error: String?
        var call: String?, failed = false
    }

    /// "pi" or "OMP", for the sentences.
    let name: String
    private var parents: [String: String?] = [:], messages: [String: Message] = [:], order: [String] = []
    private(set) var turns: [Turn] = []
    private(set) var model: String?, effort: String?, title: String?, error: AgentError?
    /// The session's end marker (OMP's session_exit) is the last entry: it closed, normally or on a signal.
    private(set) var exited = false
    /// false once lines before those read were left out.
    var readFromStart = true
    private var whole = true

    init(name: String) { self.name = name }

    /// false when turns before those shown are missing.
    var complete: Bool { readFromStart && whole }
    /// Whether the last turn runs; nil when no turn was seen.
    var open: Bool? { turns.last.map { $0.state == "working" } }

    mutating func add(_ lines: [Data]) {
        lines.forEach { add($0) }
        if order.count > PiLog.kept {
            for id in order.prefix(order.count - PiLog.kept) { parents[id] = nil; messages[id] = nil }
            order.removeFirst(order.count - PiLog.kept)
            readFromStart = false
        }
        settle()
    }

    /// Every line is decoded, since every entry is a node of the tree (pi writes a custom entry's data before its
    /// id); only whitelisted fields are kept.
    private mutating func add(_ line: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return }
        let id = object["id"] as? String, at = object["timestamp"] as? String ?? ""
        switch object["type"] as? String {
        // The header and OMP's title slot are no entries of the tree.
        case "session", "title": return
        case "model_change":
            // OMP writes "provider/model"; pi writes the model on its own.
            model = object["modelId"] as? String ?? (object["model"] as? String).map { String($0.split(separator: "/", maxSplits: 1).last ?? "") } ?? model
        case "thinking_level_change": effort = object["thinkingLevel"] as? String ?? effort
        case "session_info": title = (object["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? title
        case "message": if let id { messages[id] = PiLog.message(object["message"] as? [String: Any] ?? [:], id: id, at: at) }
        default: break
        }
        if let id { node(id, parent: object["parentId"] as? String, exits: object["customType"] as? String == "session_exit") }
    }

    private mutating func node(_ id: String, parent: String?, exits: Bool) {
        if parents[id] == nil { order.append(id) }
        parents[id] = .some(parent)
        exited = exits
    }

    /// What a message entry shows; nil for one that shows nothing (the program's own words, a system prompt).
    private static func message(_ message: [String: Any], id: String, at: String) -> Message? {
        let blocks = message["content"] as? [[String: Any]] ?? []
        switch message["role"] as? String {
        case "user":
            let text = message["content"] as? String ?? blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
            // OMP marks what the program or a parent agent wrote as the agent's: not the person speaking.
            guard !text.isEmpty, message["attribution"] as? String != "agent" else { return nil }
            return Message(role: "user", at: at, items: [Item(id: id, kind: "message", author: "person", text: text, at: at)])
        case "assistant":
            var items: [Item] = []
            for (index, block) in blocks.enumerated() {
                let key = "\(id)/\(index)"
                switch block["type"] as? String {
                case "text": if let text = block["text"] as? String, !text.isEmpty { items.append(Item(id: key, kind: "message", author: "agent", text: text, at: at)) }
                case "thinking": if let text = block["thinking"] as? String, !text.isEmpty { items.append(Item(id: key, kind: "thought", author: "agent", text: text, at: at)) }
                case "toolCall":
                    let name = block["name"] as? String ?? "a tool", arguments = block["arguments"] as? [String: Any] ?? [:]
                    let target = targets.lazy.compactMap { arguments[$0] as? String }.first { !$0.isEmpty } ?? block["intent"] as? String ?? name
                    // OMP's task tool starts sub-agents.
                    items.append(Item(id: block["id"] as? String ?? key, kind: name == "task" ? "subagent" : "tool", author: "agent", text: target, at: at,
                                      tool: Tool(name: name, status: "running")))
                default: break
                }
            }
            return Message(role: "assistant", at: at, items: items, stop: message["stopReason"] as? String, error: message["errorMessage"] as? String)
        case "toolResult":
            guard let call = message["toolCallId"] as? String else { return nil }
            return Message(role: "toolResult", at: at, call: call, failed: message["isError"] as? Bool == true)
        default: return nil
        }
    }

    /// The turns of the branch that ends at the last entry.
    private mutating func settle() {
        var branch: Set<String> = [], next = order.last
        whole = order.isEmpty
        while let id = next, branch.insert(id).inserted, let parent = parents[id] {
            guard let parent else { whole = true; break }
            next = parent
        }
        var turns: [Turn] = [], error: AgentError?
        func close(_ state: String, _ at: String?) {
            guard let last = turns.indices.last, turns[last].state == "working" else { return }
            turns[last].state = state
            turns[last].ended = at.flatMap { $0.isEmpty ? nil : $0 }
        }
        for id in order where branch.contains(id) {
            guard let message = messages[id] else { continue }
            switch message.role {
            case "user":
                close("unknown", nil)
                error = nil
                turns.append(Turn(id: id, state: "working", started: message.at.isEmpty ? nil : message.at, ended: nil, items: message.items))
            case "assistant":
                // A reply whose question lies before what was read still opens a turn.
                if turns.last?.state != "working" { turns.append(Turn(id: id, state: "working", started: message.at.isEmpty ? nil : message.at, ended: nil, items: [])) }
                turns[turns.count - 1].items = Array((turns[turns.count - 1].items + message.items).suffix(Limits.items))
                switch message.stop {
                case "stop": close("done", message.at)
                case "aborted": close("interrupted", message.at)
                case "error":
                    error = AgentError(code: "AGENT_ERROR", message: message.error ?? "\(name) could not answer.")
                    close("error", message.at)
                default: break
                }
            default:
                guard let call = message.call, let t = turns.indices.last(where: { turns[$0].items.contains { $0.id == call } }),
                      let i = turns[t].items.firstIndex(where: { $0.id == call }) else { continue }
                turns[t].items[i].tool?.status = message.failed ? "failed" : "done"
            }
        }
        if turns.count > Limits.turns { turns.removeFirst(turns.count - Limits.turns); whole = false }
        self.turns = turns
        self.error = error
    }

    /// The header of a pi or OMP log, its line `line` (pi writes it first, OMP after its title slot); nil when
    /// `path` is no such log. Only the first 64 KB are read.
    static func header(_ path: String, line: Int, opened: (String) -> Void) -> Header? {
        opened(path)
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let start = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
        let lines = start.split(separator: UInt8(ascii: "\n"), maxSplits: line + 1, omittingEmptySubsequences: false)
        guard lines.count > line + 1, let object = (try? JSONSerialization.jsonObject(with: Data(lines[line]))) as? [String: Any],
              object["type"] as? String == "session", let id = object["id"] as? String, let folder = object["cwd"] as? String, folder.hasPrefix("/")
        else { return nil }
        return Header(id: id, folder: folder, started: (object["timestamp"] as? String).flatMap(PiReader.date))
    }

    /// The logs in each of `folders` and in their sub-folders: `.jsonl` files whose name does not start with a dot.
    static func logs(in folders: [String]) -> [String] {
        func jsonl(_ folder: String) -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { !$0.hasPrefix(".") }.map { "\(folder)/\($0)" }
        }
        return folders.flatMap { folder in
            jsonl(folder).flatMap { PiReader.isFolder($0) ? jsonl($0) : [$0] }.filter { $0.hasSuffix(".jsonl") }
        }.sorted()
    }
}
