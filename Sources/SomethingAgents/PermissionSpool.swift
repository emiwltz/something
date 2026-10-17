// PermissionSpool: the folder between Claude Code's plan B and something (design 4.1, "Claude plan B"). When Claude
// cannot ask something over its own channel, a PermissionRequest hook given at launch runs `something hook permission
// --spool <dir>` for each request. That command (SpoolHook) writes the request to <uuid>.ask.json, waits for
// <uuid>.answer.json, and prints the decision for Claude. The app's side (PermissionSpool) keeps a heartbeat file fresh,
// hands each ask to the driver, and writes the person's answer. Files only: no listener, nothing installed.
// This file uses Foundation alone, so the hook command can be built from it by itself (the tests do so).
import Darwin
import Foundation

/// The names and delays both sides agree on.
enum Spool {
    static let heartbeat = "heartbeat"
    static let ask = ".ask.json", answer = ".answer.json"
    /// Older than this, the heartbeat means something is gone, and nobody can answer.
    static let stale: TimeInterval = 5
    /// Claude's own limit for the hook (`timeout` in the launch's settings), in seconds.
    static let claudeTimeout = 3600
    /// The hook answers a minute before Claude would kill it, so a request left alone ends as a deny it says.
    static let hookTimeout: TimeInterval = 3540

    /// Where the spools are: $TMPDIR/something. Each launch gets <agent>-<conversation id> in it, since two
    /// something running at once (the app and a `something try`) may both have a claude-1.
    static let root = (NSTemporaryDirectory() as NSString).appendingPathComponent("something")

    /// Writes `data` to `path` with mode 0600 through a temporary name, so a reader never sees half of it. Returns
    /// false when the folder refused it.
    static func put(_ data: Data, _ path: String) -> Bool {
        let temporary = path + ".\(getpid()).tmp"
        guard FileManager.default.createFile(atPath: temporary, contents: data, attributes: [.posixPermissions: 0o600]) else { return false }
        guard rename(temporary, path) == 0 else {
            unlink(temporary)
            return false
        }
        return true
    }

    static func age(_ path: String) -> TimeInterval? {
        guard let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { return nil }
        return Date().timeIntervalSince(date)
    }
}

/// `something hook permission --spool <dir> [--timeout <seconds>]`, run by Claude Code for each permission request.
enum SpoolHook {
    /// `arguments` are the words after `something`, with or without `hook permission` in front. Reads Claude's
    /// request on standard input and prints its decision. Returns 0 when a decision was printed (a deny included,
    /// which is what an unanswerable request gets), 2 when the words are wrong.
    static func main(_ arguments: [String], input: FileHandle = .standardInput, output: FileHandle = .standardOutput) -> Int32 {
        var words = arguments[...]
        if words.first == "hook" { words = words.dropFirst() }
        if words.first == "permission" { words = words.dropFirst() }
        var folder: String?, timeout = Spool.hookTimeout
        while let word = words.popFirst() {
            switch (word, words.popFirst()) {
            case ("--spool", let value?): folder = value
            case ("--timeout", let value?) where TimeInterval(value) != nil: timeout = TimeInterval(value)!
            default: return usage()
            }
        }
        guard let folder else { return usage() }
        let decision = decide(request: input.readDataToEndOfFile(), folder: folder, timeout: timeout)
        let printed = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        output.write((try? JSONSerialization.data(withJSONObject: printed, options: [.sortedKeys])) ?? Data())
        output.write(Data("\n".utf8))
        return 0
    }

    /// The decision for one request: the person's, from the answer file, or a deny that says why nobody answered.
    static func decide(request: Data, folder: String, timeout: TimeInterval) -> [String: Any] {
        guard let asked = try? JSONSerialization.jsonObject(with: request) as? [String: Any] else {
            return deny("something could not read this permission request, so it was refused.")
        }
        let heartbeat = (folder as NSString).appendingPathComponent(Spool.heartbeat)
        guard let age = Spool.age(heartbeat), age < Spool.stale else { return gone }
        let uuid = UUID().uuidString.lowercased()
        let ask = (folder as NSString).appendingPathComponent(uuid + Spool.ask)
        let answer = (folder as NSString).appendingPathComponent(uuid + Spool.answer)
        // The pid lets something see that Claude ended this hook (an interrupt) and close the window.
        guard let data = try? JSONSerialization.data(withJSONObject: ["pid": Int(getpid()), "request": asked]),
              Spool.put(data, ask) else { return deny("something could not hand this request to its window, so it was refused.") }
        defer { unlink(ask) }
        let end = Date().addingTimeInterval(timeout)
        while true {
            if let data = FileManager.default.contents(atPath: answer) {
                unlink(answer)
                let decided = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                guard ["allow", "deny"].contains(decided["behavior"] as? String) else {
                    return deny("something gave an answer Claude Code cannot read, so the request was refused.")
                }
                return decided
            }
            guard let age = Spool.age(heartbeat), age < Spool.stale else { return gone }
            if Date() >= end { return deny("Nobody answered in something in time, so the request was refused.") }
            usleep(100_000)
        }
    }

    private static func usage() -> Int32 {
        FileHandle.standardError.write(Data("usage: something hook permission --spool <folder> [--timeout <seconds>]\n".utf8))
        return 2
    }

    static let gone = deny("something is not running, so nobody can answer; the request was refused.")

    static func deny(_ message: String) -> [String: Any] { ["behavior": "deny", "message": message] }
}

/// The app's side of one agent's spool. Every callback comes on the main queue.
final class PermissionSpool {
    let folder: String
    /// A new request: its uuid and what Claude sent the hook (tool_name, tool_input, ...).
    var asked: (String, [String: Any]) -> Void = { _, _ in }
    /// A request whose hook ended without an answer (Claude stopped it, or it gave up).
    var withdrawn: (String) -> Void = { _ in }

    private let queue = DispatchQueue(label: "something.spool")
    private var timer: DispatchSourceTimer?
    /// The open asks, by uuid, with their hook's pid (queue only).
    private var open: [String: pid_t] = [:]
    private var ticks = 0

    init(folder: String) { self.folder = folder }

    /// Makes the folder (mode 0700, as its parent), keeps its heartbeat fresh and starts reading asks. Throws
    /// LAUNCH_FAILED when the folder cannot be made.
    func start() throws {
        do {
            for path in [(folder as NSString).deletingLastPathComponent, folder] {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
            }
        } catch {
            throw SpoolError.folder(folder, error.localizedDescription)
        }
        beat()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    /// Writes the person's decision for `uuid` (`behavior` allow or deny, as Claude reads it). Returns false when the
    /// hook was gone already, or the file could not be written.
    func answer(_ uuid: String, _ decision: [String: Any]) -> Bool {
        queue.sync {
            guard open.removeValue(forKey: uuid) != nil,
                  let data = try? JSONSerialization.data(withJSONObject: decision, options: [.sortedKeys]) else { return false }
            return Spool.put(data, path(uuid + Spool.answer))
        }
    }

    /// Stops the heartbeat and removes the folder: a hook still waiting then denies within 5 s.
    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
            open = [:]
        }
        try? FileManager.default.removeItem(atPath: folder)
    }

    private func path(_ name: String) -> String { (folder as NSString).appendingPathComponent(name) }

    private func beat() {
        let heartbeat = path(Spool.heartbeat)
        if !FileManager.default.createFile(atPath: heartbeat, contents: nil, attributes: [.posixPermissions: 0o600]) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: heartbeat)
        }
    }

    private func tick() {
        ticks += 1
        if ticks % 4 == 0 { beat() }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        let present = Set(names.filter { $0.hasSuffix(Spool.ask) }.map { String($0.dropLast(Spool.ask.count)) })
        for uuid in present where open[uuid] == nil {
            guard let data = FileManager.default.contents(atPath: path(uuid + Spool.ask)),
                  let ask = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let pid = ask["pid"] as? Int else { continue }
            open[uuid] = pid_t(pid)
            let request = ask["request"] as? [String: Any] ?? [:]
            DispatchQueue.main.async { [weak self] in self?.asked(uuid, request) }
        }
        // A hook that ended takes its ask file with it; one killed leaves it, but its pid is gone.
        for (uuid, pid) in open where !present.contains(uuid) || (kill(pid, 0) == -1 && errno == ESRCH) {
            open[uuid] = nil
            unlink(path(uuid + Spool.ask))
            DispatchQueue.main.async { [weak self] in self?.withdrawn(uuid) }
        }
    }
}

/// Why a spool could not start, in words for the person.
struct SpoolError: Error, CustomStringConvertible {
    let description: String
    static func folder(_ path: String, _ reason: String) -> SpoolError {
        SpoolError(description: "something could not make the folder \(path) for Claude Code's permission requests: \(reason).")
    }
}
