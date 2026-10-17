// Spawn: one program something launches, and the held queue of its agent (design 4.1).
// The program runs in its own process group, so a stop reaches the children it started, even reparented ones. It is
// spoken to in whole lines on one serial queue: a line written in two pieces kills Claude. Only something holds the
// write end of its input, so if something crashes the program reads end of file and stops.
// HeldQueue is pure: a driver keeps one next to its Spawn and replays it in tests without any process.
import Darwin
import Foundation
import SomethingCore

public final class Spawn {
    public let path: String
    public let arguments: [String]
    public let folder: String
    public let environment: [String: String]
    /// The process id, which is also the id of its group; 0 before `start`.
    public var pid: pid_t { lock.withLock { child } }
    /// The driver's own first step of the stop ladder (a goodbye line, a cancel and its answer); it may block, and
    /// gets at most 3 s. Set it before `start`.
    public var graceful: (() -> Void)?

    static let keptErrors = 65_536
    private let input: Bool
    private let lock = NSLock()
    private let writes = DispatchQueue(label: "something.spawn.writes")
    private var child: pid_t = 0
    /// The write end of the program's input; -1 once closed. Whoever sets it to -1 closes the old descriptor.
    private var stdin: Int32 = -1
    private var errors = Data()
    private var exited = false
    /// Set just before `ended` is called: a line something left behind writes after it is dropped.
    private var finished = false
    /// Held while a line is handed over, so that no line is handed over once `finished` is set.
    private let delivery = NSLock()
    /// The `done` of each stop asked while a ladder runs; nil when none runs.
    private var stopping: [() -> Void]?
    /// When the running ladder kills what is left; a later stop with a smaller cap brings it forward.
    private var deadline = Date.distantFuture

    /// `path` is absolute (Programs found it); `environment` is the whole environment of the program, the person's
    /// plus what this launch adds. With `input` false the program reads /dev/null.
    public init(path: String, arguments: [String], folder: String, environment: [String: String], input: Bool = true) {
        self.path = path
        self.arguments = arguments
        self.folder = folder
        self.environment = environment
        self.input = input
    }

    /// Starts the program. `lines` gets each line it writes on its output, without the newline, in order, on a
    /// background thread; a last line without a newline comes at its end. `ended` is called once, with the exit code
    /// (128 + the signal when a signal ended it), after the last line and the error output. When what the program
    /// left behind still holds its outputs 2 s after its exit, `ended` comes anyway and that rest of its group is
    /// ended. Throws NOT_INSTALLED when the file is gone, LAUNCH_FAILED when the folder does not exist or the system
    /// refuses to start the program.
    public func start(lines: @escaping (Data) -> Void, ended: @escaping (Int32) -> Void) throws {
        precondition(path.hasPrefix("/") && pid == 0, "Spawn starts an absolute path, once")
        // Checked first: a missing folder makes posix_spawn answer ENOENT, as a missing program does.
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isFolder), isFolder.boolValue else {
            throw CodedError("LAUNCH_FAILED", "The folder \(folder) does not exist on this Mac.")
        }
        var inPipe: [Int32] = [-1, -1]
        var outPipe: [Int32] = [-1, -1]
        var errPipe: [Int32] = [-1, -1]
        guard (!input || pipe(&inPipe) == 0), pipe(&outPipe) == 0, pipe(&errPipe) == 0 else {
            let reason = String(cString: strerror(errno))
            for fd in inPipe + outPipe + errPipe where fd >= 0 { close(fd) }
            throw CodedError("LAUNCH_FAILED", "something could not open pipes to \(name): \(reason).")
        }
        // Our ends must not leak into any other child: a copy of the input's write end would keep a program alive.
        for fd in [inPipe[1], outPipe[0], errPipe[0]] where fd >= 0 { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        if input { _ = fcntl(inPipe[1], F_SETNOSIGPIPE, 1) }   // a program that died must not kill something with SIGPIPE

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        if input { posix_spawn_file_actions_adddup2(&actions, inPipe[0], 0) }
        else { posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0) }
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)
        posix_spawn_file_actions_addchdir_np(&actions, folder)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Its own group (pgid = pid); only the three descriptors above inherited; default signals, none blocked.
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&attributes, Int16(flags))
        posix_spawnattr_setpgroup(&attributes, 0)
        var all = ~sigset_t(0)
        var none = sigset_t(0)
        posix_spawnattr_setsigdefault(&attributes, &all)
        posix_spawnattr_setsigmask(&attributes, &none)

        let argv = ([path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var started: pid_t = 0
        let failure = posix_spawn(&started, path, &actions, &attributes, argv, envp)
        for fd in [inPipe[0], outPipe[1], errPipe[1]] where fd >= 0 { close(fd) }
        guard failure == 0 else {
            for fd in [inPipe[1], outPipe[0], errPipe[0]] where fd >= 0 { close(fd) }
            let reason = String(cString: strerror(failure))
            if failure == ENOENT && !FileManager.default.fileExists(atPath: path) {
                throw CodedError("NOT_INSTALLED", "\(path) is no longer there: \(reason). Install \(name) again.")
            }
            throw CodedError("LAUNCH_FAILED", "\(name) could not be started: \(reason).")
        }
        lock.withLock {
            child = started
            stdin = inPipe[1]
        }

        let readers = DispatchGroup()
        readers.enter()
        readers.enter()
        Thread.detachNewThread { [self] in
            Spawn.readLines(outPipe[0]) { line in delivery.withLock { if !finished { lines(line) } } }
            readers.leave()
        }
        Thread.detachNewThread { [self] in
            Spawn.read(errPipe[0]) { keep(errors: $0) }
            readers.leave()
        }
        Thread.detachNewThread { [self] in
            var status: Int32 = 0
            while waitpid(started, &status, 0) == -1 && errno == EINTR {}
            // Nobody reads the input any more: a later write throws instead of vanishing.
            let fd = lock.withLock { () -> Int32 in
                exited = true
                defer { stdin = -1 }
                return stdin
            }
            if fd >= 0 { writes.async { close(fd) } }   // after a write that may still be using it
            // A grandchild may hold the outputs open after the program ended: its last lines get two seconds.
            let drained = readers.wait(timeout: .now() + 2) == .success
            delivery.withLock { finished = true }
            ended(status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + status & 0x7f)
            // What still holds the outputs came with this launch, and would keep two threads alive as long as it runs.
            if !drained {
                signalGroup(SIGTERM)
                if readers.wait(timeout: .now() + 2) == .timedOut { signalGroup(SIGKILL) }
            }
        }
    }

    /// The program's name, for sentences.
    public var name: String { (path as NSString).lastPathComponent }

    /// Whether the program still runs (its exit was not collected yet).
    public var running: Bool { lock.withLock { child != 0 && !exited } }

    /// The last 64 KB the program wrote on its error output, decoded leniently.
    public var errorTail: String { lock.withLock { String(decoding: errors.suffix(Spawn.keptErrors), as: UTF8.self) } }

    /// Queues `line` and its newline for the program's input, written whole after the lines queued before it.
    /// Throws BAD_PARAMS when `line` holds a newline (it would be two lines), AGENT_STOPPED once the input is closed,
    /// the program ended, or an earlier write failed.
    public func write(_ line: Data) throws {
        guard !line.contains(0x0A) else { throw CodedError("BAD_PARAMS", "A line for \(name) cannot hold a newline.") }
        try lock.withLock {
            guard stdin >= 0 else { throw CodedError("AGENT_STOPPED", "\(name) no longer reads its input.") }
        }
        writes.async { [self] in
            let fd = lock.withLock { stdin }
            guard fd >= 0 else { return }
            var data = line
            data.append(0x0A)
            guard !Spawn.writeAll(fd, data) else { return }
            // The program no longer reads its input: the next write throws AGENT_STOPPED.
            let mine = lock.withLock { () -> Bool in
                guard stdin == fd else { return false }
                stdin = -1
                return true
            }
            if mine { close(fd) }
        }
    }

    /// Closes the program's input once the lines already queued are written: most programs then end.
    public func closeInput() {
        writes.async { [self] in
            let fd = lock.withLock { () -> Int32 in
                defer { stdin = -1 }
                return stdin
            }
            if fd >= 0 { close(fd) }
        }
    }

    /// The stop ladder: `graceful` (given at most 3 s), the input closed, SIGTERM to the group 3 s later, SIGKILL
    /// 2 s after that; each signal only if something of the group is left. With `cap`, the group is killed by `cap`
    /// seconds whatever the steps take. A stop asked while a ladder runs joins it, and its cap still holds. `done` is
    /// called on a background thread once the program and its group are gone, or after SIGKILL.
    public func stop(cap: TimeInterval = .infinity, done: @escaping () -> Void = {}) {
        let firstStop = lock.withLock { () -> Bool? in
            guard child != 0 else { return nil }
            deadline = min(deadline, Date().addingTimeInterval(cap))
            if stopping != nil {
                stopping?.append(done)
                return false
            }
            stopping = [done]
            return true
        }
        guard let firstStop else { return done() }
        guard firstStop else { return }
        Thread.detachNewThread { [self] in
            if let graceful {
                let begun = Date()
                let stepped = DispatchSemaphore(value: 0)
                Thread.detachNewThread { graceful(); stepped.signal() }
                _ = waitUntil({ min(begun + 3, latest - 1) }) { stepped.wait(timeout: .now()) == .success }
            }
            closeInput()
            let closed = Date()
            if !waitUntil({ min(closed + 3, latest - 1) }, { gone }) { signalGroup(SIGTERM) }
            // SIGKILL comes a little before the cap, so that the group is also collected within it.
            if !waitUntil({ min(closed + 5, latest - 0.25) }, { gone }) {
                signalGroup(SIGKILL)
                let killed = Date()
                _ = waitUntil({ min(killed + 1, latest) }, { gone })
            }
            let waiting = lock.withLock { () -> [() -> Void] in
                defer {
                    stopping = nil
                    deadline = .distantFuture
                }
                return stopping ?? []
            }
            waiting.forEach { $0() }
        }
    }

    /// Runs every ladder at once, killing what is left by `cap` seconds (6 at quit), then calls `done`.
    public static func stopAll(_ spawns: [Spawn], cap: TimeInterval = 6, done: @escaping () -> Void) {
        let group = DispatchGroup()
        for spawn in spawns {
            group.enter()
            spawn.stop(cap: cap) { group.leave() }
        }
        group.notify(queue: .global(), execute: done)
    }

    /// True once the program ended and no process is left in its group.
    var gone: Bool {
        let (group, ended) = lock.withLock { (child, exited) }
        return ended && Darwin.kill(-group, 0) == -1 && errno == ESRCH
    }

    private var latest: Date { lock.withLock { deadline } }

    /// Checks `condition` every 20 ms until it holds (true) or `limit`, read again at each check, has passed (false).
    private func waitUntil(_ limit: () -> Date, _ condition: () -> Bool) -> Bool {
        while !condition() {
            if Date() >= limit() { return false }
            usleep(20_000)
        }
        return true
    }

    private func signalGroup(_ signal: Int32) {
        let group = pid
        if group > 0 { _ = Darwin.kill(-group, signal) }
    }

    private func keep(errors more: Data) {
        lock.withLock {
            errors.append(more)
            // Trimmed by halves so a chatty program costs one copy per 64 KB, not one per read.
            if errors.count > 2 * Spawn.keptErrors { errors = errors.suffix(Spawn.keptErrors) }
        }
    }

    /// Writes all of `data` to `fd`; false when the descriptor refused it (the program closed its input or ended).
    private static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { bytes in
            var done = 0
            while done < bytes.count {
                let n = Darwin.write(fd, bytes.baseAddress! + done, bytes.count - done)
                if n > 0 { done += n } else if n == -1 && errno == EINTR { continue } else { return false }
            }
            return true
        }
    }

    /// Splits what `fd` gives on newlines only (U+2028 and other separators stay inside a line), then closes it.
    static func readLines(_ fd: Int32, _ lines: (Data) -> Void) {
        var pending = Data()   // always starts at index 0: it is only ever made by Data() or subdata
        read(fd) { chunk in
            let firstNew = pending.count   // the bytes before it hold no newline
            pending.append(chunk)
            var start = 0
            while let newline = pending[max(start, firstNew)...].firstIndex(of: 0x0A) {
                lines(pending.subdata(in: start..<newline))
                start = newline + 1
            }
            if start > 0 { pending = pending.subdata(in: start..<pending.count) }
        }
        if !pending.isEmpty { lines(pending) }
    }

    /// Reads `fd` to its end, in chunks, then closes it.
    static func read(_ fd: Int32, _ chunk: (Data) -> Void) {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n > 0 { chunk(Data(buffer[0..<n])) } else if n == -1 && errno == EINTR { continue } else { break }
        }
        close(fd)
    }
}

/// The queue something holds for a launched agent (contract 4.2, `send` with `when`), kept in the agent's fold so the
/// state shows it: "next" waits while a turn is open, the end of a turn hands the first message over, an interrupt
/// empties it. The driver delivers what this decides.
public struct HeldQueue: Sendable {
    public enum Delivery: String, Sendable { case started, steered, queued }

    public private(set) var fold: Fold
    /// True from the moment a message starts a turn until the driver says the turn ended.
    private var turnOpen = false
    /// True once the agent stopped: it takes nothing more.
    private var ended = false
    /// True from an interrupt of an open turn until that turn ends.
    private var interrupting = false
    /// How many messages were held, for their ids.
    private var count = 0

    public init(_ fold: Fold) { self.fold = fold }

    /// What a message does now: `started` (the driver delivers it), `steered` (the driver delivers it into the running
    /// turn) or `queued` (held). Throws AGENT_STOPPED once the agent ended, BAD_PARAMS for a `when` other than "next"
    /// or "now".
    public mutating func send(_ text: String, when: String, at: String) throws -> Delivery {
        guard !ended else { throw CodedError("AGENT_STOPPED", "The agent has ended; launch or resume it to go on.") }
        guard when == "next" || when == "now" else { throw CodedError("BAD_PARAMS", "when is \"next\" or \"now\".") }
        if !turnOpen {
            turnOpen = true
            return .started
        }
        if when == "now" { return .steered }
        count += 1
        fold.hold(Queued(id: "q\(count)", text: text, at: at))
        return .queued
    }

    /// Applies one event of the driver. Returns the held message the driver delivers now, when a turn ended without
    /// an interrupt, or ended by an interrupt after which a message was held; a new turn is then open.
    public mutating func record(_ event: AgentEvent, at: String) -> Queued? {
        // The queue was emptied at the interrupt: what was held after it was promised to the next turn, and must
        // survive the fold, which empties the queue at an interrupted end.
        let heldAfterInterrupt = interrupting ? fold.agent.queue : []
        var next = fold.apply(event, at: at)
        switch event {
        case .turnStarted:
            turnOpen = true
        case .turnEnded(let outcome):
            if outcome == .interrupted, let first = heldAfterInterrupt.first {
                heldAfterInterrupt.dropFirst().forEach { fold.hold($0) }
                next = first
            }
            turnOpen = next != nil
            interrupting = false
        case .stopped:
            turnOpen = false
            ended = true
            interrupting = false
        default: break
        }
        return next
    }

    /// Empties the queue, whatever happens next. Returns whether a turn was open, so the driver interrupts it.
    public mutating func interrupt() -> Bool {
        fold.emptyQueue()
        interrupting = turnOpen
        return turnOpen
    }
}
