// Processes: one snapshot of this Mac's processes per tick, read with libproc and sysctl, never by starting a program.
// Every process gives its parent, its group and its start time. Only those whose name a reader
// knows give their arguments and folder, and only the candidates a reader asks for give their open files: reading
// those of every process would cost far more than a tick may.
import Darwin
import Foundation

/// One process, as a snapshot saw it.
public struct Running: Equatable, Sendable {
    public var pid: Int32
    public var parent: Int32
    /// Its process group: something starts each agent in a group of its own, whose id is the agent's pid.
    public var group: Int32
    public var started: Date
    /// The name the system gives it (up to 32 characters), which is the program's file name for most programs.
    public var name: String
    /// Its arguments, the program's first; nil when they were not read (a name no reader knows) or not readable.
    public var arguments: [String]?
    /// Its working folder; nil when not read.
    public var folder: String?

    public init(pid: Int32, parent: Int32, group: Int32, started: Date, name: String, arguments: [String]? = nil, folder: String? = nil) {
        (self.pid, self.parent, self.group, self.started, self.name) = (pid, parent, group, started, name)
        (self.arguments, self.folder) = (arguments, folder)
    }
}

extension Running {
    /// The interpreters a coding agent may run under: the system names its process after them.
    static let interpreters: Set<String> = ["node", "bun"]

    /// Which of `names` this process runs, or nil: its own name, its first argument's file name, or, under an
    /// interpreter, the file name of its first argument that is no option. A Node program that renames itself (pi sets
    /// its title) shows its interpreter's arguments until it does, and the arguments are read once per process.
    func runs(_ names: Set<String>) -> String? {
        let words = (arguments ?? []).map { ($0 as NSString).lastPathComponent }
        if names.contains(name) { return name }
        if let first = words.first, names.contains(first) { return first }
        guard Running.interpreters.contains(name) || words.first.map(Running.interpreters.contains) == true,
              let script = words.dropFirst().first(where: { !$0.hasPrefix("-") }) else { return nil }
        return names.contains(script) ? script : nil
    }
}

/// The processes of one tick. Tests build one by hand, with invented processes.
public struct Snapshot {
    public let processes: [Int32: Running]
    /// false when the system did not give the whole list: a process missing from it is then not proven gone.
    public let whole: Bool
    private let files: (Int32) -> [String]?

    /// `files` gives the paths a process holds open, or nil when they cannot be read.
    public init(_ processes: [Running], whole: Bool = true, files: @escaping (Int32) -> [String]? = { _ in nil }) {
        self.processes = Dictionary(processes.map { ($0.pid, $0) }) { first, _ in first }
        self.whole = whole
        self.files = files
    }

    public subscript(pid: Int32) -> Running? { processes[pid] }

    /// The paths `pid` holds open now, or nil when they cannot be read. Each call reads them again: ask for a
    /// candidate only.
    public func openFiles(_ pid: Int32) -> [String]? { files(pid) }

    /// Whether `pid` descends from `ancestor`, through its parents or the leader of its group: a helper whose parent
    /// ended is reparented, but still runs in its group, and a server that starts a group of its own still has a parent.
    public func descends(_ pid: Int32, from ancestor: Int32) -> Bool {
        var seen: Set<Int32> = [], next = [pid]
        while let current = next.popLast() {
            guard seen.insert(current).inserted, let process = self[current] else { continue }
            if process.parent == ancestor || process.group == ancestor { return true }
            next += [process.parent, process.group]
        }
        return false
    }
}

/// Takes snapshots. Arguments are kept per pid and start time, since a process does not change them once started
/// (a reused pid has another start time); everything else is read again at each snapshot.
public final class Processes {
    /// The names whose arguments and folder are read.
    let known: Set<String>
    private var kept: [Int32: (started: Date, arguments: [String]?)] = [:]

    public init(known: Set<String>) { self.known = known }

    /// The processes running now. A process that ends during the read is left out. The snapshot is `whole` only
    /// when the system gave the list in full and something's own process is in it.
    public func snapshot() -> Snapshot {
        var processes: [Running] = []
        let pids = Processes.pids()
        for pid in pids ?? [] {
            guard var process = Processes.info(pid) else { continue }
            if known.contains(process.name) {
                if let entry = kept[pid], entry.started == process.started {
                    process.arguments = entry.arguments
                } else {
                    process.arguments = Processes.arguments(pid)
                    kept[pid] = (process.started, process.arguments)
                }
                process.folder = Processes.folder(pid)
            }
            processes.append(process)
        }
        let alive = Set(processes.map(\.pid))
        kept = kept.filter { alive.contains($0.key) }
        let whole = pids != nil && processes.contains { $0.pid == getpid() }
        return Snapshot(processes, whole: whole, files: Processes.openFiles)
    }

    /// Every pid on this Mac, or nil when the system refuses or the list kept outgrowing the room made for it.
    static func pids() -> [Int32]? {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return nil }
        // The list can grow between the two calls: room is left for more, and a full buffer is tried once bigger.
        for room in [Int(count) + 64, Int(count) * 2 + 256] {
            var pids = [Int32](repeating: 0, count: room)
            let found = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
            guard found > 0 else { return nil }
            if Int(found) < room { return Array(pids.prefix(Int(found))).filter { $0 > 0 } }
        }
        return nil
    }

    /// The process `pid` without its arguments and folder, or nil when it is gone or hidden from this user.
    static func info(_ pid: Int32) -> Running? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let started = Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
        var name = withUnsafeBytes(of: info.pbi_name) { text($0) }
        if name.isEmpty { name = withUnsafeBytes(of: info.pbi_comm) { text($0) } }
        return Running(pid: pid, parent: Int32(info.pbi_ppid), group: Int32(info.pbi_pgid), started: started, name: name)
    }

    /// The arguments of `pid`, the program's first, or nil when the system does not give them (another user's process).
    static func arguments(_ pid: Int32) -> [String]? {
        var mib = [CTL_KERN, KERN_ARGMAX], longest: Int32 = 0, size = MemoryLayout<Int32>.size
        guard sysctl(&mib, 2, &longest, &size, nil, 0) == 0, longest > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(longest))
        mib = [CTL_KERN, KERN_PROCARGS2, pid]
        size = buffer.count
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        // The layout: the count of arguments, the program's path, padding zeros, then the arguments, then the environment.
        let count = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < count, index < size {
            let end = buffer[index..<size].firstIndex(of: 0) ?? size
            arguments.append(String(decoding: buffer[index..<end], as: UTF8.self))
            index = end + 1
        }
        return arguments.count == count ? arguments : nil
    }

    /// The working folder of `pid`, or nil when the system does not give it.
    static func folder(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { text($0) }
        return path.isEmpty ? nil : path
    }

    /// The paths of the files `pid` holds open, or nil when the system does not give them.
    static func openFiles(_ pid: Int32) -> [String]? {
        let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard needed > 0 else { return nil }
        let stride = MemoryLayout<proc_fdinfo>.stride
        // Files opened between the two calls are missed; room is left for some.
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / stride + 16)
        let got = descriptors.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
        guard got > 0 else { return nil }
        var paths: [String] = []
        for descriptor in descriptors.prefix(Int(got) / stride) where descriptor.proc_fdtype == PROX_FDTYPE_VNODE {
            var vnode = vnode_fdinfowithpath()
            let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &vnode, size) == size else { continue }
            let path = withUnsafeBytes(of: vnode.pvip.vip_path) { text($0) }
            if !path.isEmpty { paths.append(path) }
        }
        return paths
    }

    /// A C string held in a fixed-size field: its bytes up to the first zero.
    private static func text(_ bytes: UnsafeRawBufferPointer) -> String {
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}

/// The files some processes hold open, by path, read again only when those processes change or every `every`
/// seconds: a conversation opened in a process that runs on is seen within that time.
final class HeldFiles {
    struct Held: Equatable {
        /// Each path, and the process that holds it (the lowest pid, when several do).
        var files: [String: Int32] = [:]
        /// false when a process did not give its open files: what it holds is unknown.
        var whole = true
    }

    let every: TimeInterval
    private var last: (pids: Set<Int32>, at: Date, held: Held)?

    init(every: TimeInterval = 10) { self.every = every }

    /// `path` with its links resolved, as the system names the files a process holds ("/private/var", not "/var").
    static func real(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// What `pids` hold open, as last read when they are the same processes and that read is recent enough.
    func read(_ snapshot: Snapshot, _ pids: Set<Int32>, now: Date) -> Held {
        if let last, last.pids == pids, now.timeIntervalSince(last.at) < every { return last.held }
        var held = Held()
        for pid in pids.sorted(by: >) {
            guard let files = snapshot.openFiles(pid) else { held.whole = false; continue }
            for path in files { held.files[path] = pid }
        }
        last = (pids, now, held)
        return held
    }
}
