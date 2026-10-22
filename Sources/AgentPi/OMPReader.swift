// OMPReader: the OMP (oh-my-pi) conversations on this Mac, read from OMP's own files, never through its program.
// something does not launch OMP in 1.0: every OMP agent is one seen elsewhere. OMP writes one
// JSONL log per conversation under ~/.omp/agent/sessions/<folder>/<time>_<id>.jsonl (a profile's under
// ~/.omp/profiles/<name>/agent/sessions); the first 256 bytes are a title slot OMP rewrites in place, then comes the
// `session` header. Its format is pi's (PiLog). While a conversation is open, its omp process holds the log open, and
// takes a lease, ~/.omp/run/session-owners/<id>.lock, which stays on disk after its end: only a holder counts. What
// OMP waits on (a permission, an answer) is not in its files, so `waiting` is null.
import Foundation
import SomethingAgents
import SomethingCore

final class OMPReader: Reader {
    let kind = "omp"
    let programs: Set<String> = ["omp"]
    /// OMP's title slot, which a change of title rewrites in place.
    static let titleSlot = 256
    /// ~/.omp; nil when the environment names no home.
    let folder: String?
    /// Sees every path the reader opens.
    var opened: (String) -> Void = { _ in }

    /// Each log found, its path with links resolved, as the system names the files a process holds, and the id of
    /// its session, which its name ends with (`<time>_<id>.jsonl`) and its lease names.
    private var found: [(path: String, real: String, id: String)] = []
    /// The logs too old to list when last looked at: a tick looks at them again only when it walks or a process holds one.
    private var old: Set<String> = []
    private var walked = false, pids: Set<Int32> = [], leases = ""
    private var files: [String: PiFile] = [:]
    /// The headers read, by path, with the inode they were read from.
    private var headers: [String: (inode: UInt64, header: PiLog.Header?)] = [:]
    private let held = HeldFiles()

    init(environment: [String: String]) {
        folder = environment["HOME"].map { ($0 as NSString).appendingPathComponent(".omp") }
    }

    func read(_ snapshot: Snapshot, discover: Bool, now: Date) -> Reading {
        guard let folder, OMPReader.isFolder(folder) else { return Reading() }
        let running = Set(snapshot.processes.values.filter(owns).map(\.pid))
        // A session opened since the last walk is held at once: the walk is done again when the omp processes change.
        let walking = discover || !walked || running != pids
        if walking {
            walked = true
            pids = running
            let profiles = ((try? FileManager.default.contentsOfDirectory(atPath: "\(folder)/profiles")) ?? []).map { "\(folder)/profiles/\($0)/agent/sessions" }
            // Only `<cwd folder>/<time>_<id>.jsonl`: a sub-agent's log lies one folder deeper, in its parent's.
            let known = Dictionary(found.map { ($0.path, $0) }) { first, _ in first }
            found = PiLog.logs(in: (["\(folder)/agent/sessions"] + profiles).filter(OMPReader.isFolder))
                .filter { ($0 as NSString).lastPathComponent.contains("_") }
                .map { known[$0] ?? ($0, HeldFiles.real($0), String(($0 as NSString).lastPathComponent.dropLast(".jsonl".count).split(separator: "_").last ?? "")) }
            let paths = Set(found.map(\.path))
            headers = headers.filter { paths.contains($0.key) }
            old.formIntersection(paths)
            leases = HeldFiles.real("\(folder)/run/session-owners") + "/"
        }
        let holding = held.read(snapshot, running, now: now)
        var leased: [String: Int32] = [:]
        for (path, pid) in holding.files where path.hasPrefix(leases) && path.hasSuffix(".lock") { leased[String(path.dropFirst(leases.count).dropLast(5))] = pid }
        var reading = Reading(health: "ok"), followed: [String: PiFile] = [:]
        for (path, real, id) in found {
            let holder = holding.files[path] ?? holding.files[real] ?? leased[id]
            // An old log written again without a holder is seen at the next walk, at most 15 ticks later.
            guard holder != nil || walking || !old.contains(path), let stamp = Stamp(path) else { continue }
            guard holder != nil || Watch.isRecent(alive: nil, updated: stamp.modified, now: now) else { old.insert(path); continue }
            old.remove(path)
            if headers[path]?.inode != stamp.inode { headers[path] = (stamp.inode, PiLog.header(path, line: 1, opened: opened)) }
            guard let header = headers[path]?.header else { continue }
            var file = files[path] ?? PiFile(path: path, header: header, log: PiLog(name: "OMP"))
            file.header = header
            if stamp != file.stamp { file.title = OMPReader.title(path, opened: opened) }
            file.follow(stamp, skip: OMPReader.titleSlot, opened: opened)
            followed[path] = file
            // A full read of every omp process's files without a holder proves the session closed; a process whose
            // files the system did not give leaves it unknown.
            var facts = StateMap.Facts(alive: holder != nil ? true : holding.whole ? false : nil, turnOpen: file.log.open, lastWrite: file.stamp?.modified)
            facts.evidence = facts.alive == nil ? nil : running.isEmpty ? "process" : "open-file"
            facts.ended = file.log.exited
            facts.failed = file.log.turns.last?.state == "error"
            facts.aborted = file.log.turns.last?.state == "interrupted"
            reading.sightings.append(file.sighting(kind, key: header.id, pid: holder, facts: facts))
        }
        files = followed
        return reading
    }

    /// The title in a log's title slot; nil when it is empty or the slot is not one.
    static func title(_ path: String, opened: (String) -> Void) -> String? {
        opened(path)
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let slot = (try? handle.read(upToCount: titleSlot)) ?? Data()
        guard let end = slot.firstIndex(of: UInt8(ascii: "\n")),
              let object = (try? JSONSerialization.jsonObject(with: slot[..<end])) as? [String: Any], object["type"] as? String == "title",
              let title = object["title"] as? String, !title.isEmpty else { return nil }
        return title
    }
}
