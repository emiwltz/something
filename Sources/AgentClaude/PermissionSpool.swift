// PermissionSpool: the folder between Claude Code's plan B and something. When Claude
// cannot ask something over its own channel, a PermissionRequest hook given at launch runs `something hook permission
// --spool <dir>` for each request. That command (SpoolHook) writes the request to <uuid>.ask.json, waits for
// <uuid>.answer.json, and prints the decision for Claude. The app's side (PermissionSpool) keeps a heartbeat file fresh,
// hands each ask to the driver, and writes the person's answer. Files only: no listener, nothing installed.
// This file uses Foundation alone, so the hook command can be built from it by itself (the tests do so).
import Foundation

/// The names and delays both sides agree on.
enum Spool {
    /// The heartbeat file holds the app's pid, so a hook sees at once that something is gone. Its date, refreshed
    /// every second, is only a backstop for an app that is there but no longer works.
    static let heartbeat = "heartbeat"
    static let ask = ".ask.json", answer = ".answer.json"
    /// Older than this, the heartbeat means nobody can answer. Wider than 5 s: App Nap and a Mac waking
    /// from sleep delay a background app's timer by more than that, and the pid already tells a crash at once.
    static let stale: TimeInterval = 30
    /// Claude's own limit for the hook (`timeout` in the launch's settings), in seconds.
    static let claudeTimeout = 3600
    /// The hook answers a minute before Claude would kill it, so a request left alone ends as a deny it says.
    static let hookTimeout: TimeInterval = 3540

    /// Writes `data` to `path` with mode 0600 through a temporary name, so a reader never sees half of it. Returns
    /// false when the folder refused it.
    static func put(_ data: Data, _ path: String) -> Bool {
        let temporary = path + ".\(ProcessInfo.processInfo.processIdentifier).tmp"
        guard FileManager.default.createFile(atPath: temporary, contents: data, attributes: [.posixPermissions: 0o600]) else { return false }
        guard rename(temporary, path) == 0 else {
            unlink(temporary)
            return false
        }
        return true
    }

    /// Whether the something that wrote `heartbeat` still runs and keeps it fresh.
    static func alive(_ heartbeat: String) -> Bool {
        guard let date = (try? FileManager.default.attributesOfItem(atPath: heartbeat))?[.modificationDate] as? Date,
              Date().timeIntervalSince(date) < stale, let pid = pid(in: heartbeat) else { return false }
        return running(pid)
    }

    /// Removes the spools in `root` that a something now gone left behind (it crashed, or was killed during a
    /// request): nothing else cleans this folder, and their asks hold Claude's requests, which must not outlive the
    /// session. Only the pid is asked, not the date: a something that App Nap slowed is still there. A spool without
    /// a pid yet is kept while it is new, since another something may be making it.
    static func sweep(_ root: String) {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [] {
            let folder = (root as NSString).appendingPathComponent(name)
            if let pid = pid(in: (folder as NSString).appendingPathComponent(heartbeat)) {
                if running(pid) { continue }
            } else {
                let changed = (try? FileManager.default.attributesOfItem(atPath: folder))?[.modificationDate] as? Date ?? .distantPast
                if Date().timeIntervalSince(changed) < stale { continue }
            }
            try? FileManager.default.removeItem(atPath: folder)
        }
    }

    /// The pid a heartbeat file names; nil when it is missing or unreadable.
    static func pid(in heartbeat: String) -> pid_t? {
        FileManager.default.contents(atPath: heartbeat).flatMap { pid_t(String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// Whether `pid` is a process (EPERM: one of another user, which is still there).
    static func running(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 || errno == EPERM }
}

/// `something hook permission --spool <dir> [--timeout <seconds>]`, run by Claude Code for each permission request.
package enum SpoolHook {
    /// `arguments` are every word after `something`, `hook permission` first. Reads Claude's request on standard
    /// input and prints its decision. Returns 0 when a decision was printed (a deny included, which is what an
    /// unanswerable request gets), 2 when the words are wrong.
    package static func main(_ arguments: [String], input: FileHandle = .standardInput, output: FileHandle = .standardOutput) -> Int32 {
        guard arguments.starts(with: ["hook", "permission"]) else { return usage() }
        var words = arguments.dropFirst(2)
        var folder: String?, timeout = Spool.hookTimeout
        while let word = words.popFirst() {
            switch (word, words.popFirst()) {
            case ("--spool", let value?): folder = value
            case ("--timeout", let value?):
                guard let seconds = TimeInterval(value) else { return usage() }
                timeout = seconds
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
        guard Spool.alive(heartbeat) else { return gone }
        let uuid = UUID().uuidString.lowercased()
        let ask = (folder as NSString).appendingPathComponent(uuid + Spool.ask)
        let answer = (folder as NSString).appendingPathComponent(uuid + Spool.answer)
        // The pid lets something see that Claude ended this hook (an interrupt) and close the window.
        guard let data = try? JSONSerialization.data(withJSONObject: ["pid": Int(ProcessInfo.processInfo.processIdentifier), "request": asked]),
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
            guard Spool.alive(heartbeat) else { return gone }
            // Claude ended the shell that ran this hook without ending the hook: nobody reads what it prints.
            if getppid() == 1 { return deny("Claude Code stopped waiting for this request.") }
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
    /// The asks answered whose hook has not read the answer yet: their ask file is still there, and must not open a
    /// second window for a request the person already answered (queue only).
    private var answered: [String: pid_t] = [:]
    private var ticks = 0

    init(folder: String) { self.folder = folder }

    /// Removes the spools left behind next to it, makes the folder (mode 0700, as its parent), keeps its heartbeat
    /// fresh and starts reading asks. Throws a SpoolError when the folder cannot be made.
    func start() throws {
        Spool.sweep((folder as NSString).deletingLastPathComponent)
        do {
            for path in [(folder as NSString).deletingLastPathComponent, folder] {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
            }
        } catch {
            throw SpoolError.folder(folder, error.localizedDescription)
        }
        guard Spool.put(Data("\(ProcessInfo.processInfo.processIdentifier)\n".utf8), path(Spool.heartbeat)) else {
            throw SpoolError.folder(folder, "its heartbeat file could not be written")
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    enum Delivery { case written, gone, unwritten }

    /// Writes the person's decision for `uuid` (`behavior` allow or deny, as Claude reads it). Returns `gone` when the
    /// hook was gone already, `unwritten` when the file could not be written (the ask then stays open).
    func answer(_ uuid: String, _ decision: [String: Any]) -> Delivery {
        queue.sync {
            guard let pid = open[uuid] else { return .gone }
            guard let data = try? JSONSerialization.data(withJSONObject: decision, options: [.sortedKeys]),
                  Spool.put(data, path(uuid + Spool.answer)) else { return .unwritten }
            open[uuid] = nil
            answered[uuid] = pid
            return .written
        }
    }

    /// Stops the heartbeat and removes the folder: a hook still waiting then denies within a moment.
    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
            open = [:]
            answered = [:]
        }
        try? FileManager.default.removeItem(atPath: folder)
    }

    private func path(_ name: String) -> String { (folder as NSString).appendingPathComponent(name) }

    private func beat() { try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path(Spool.heartbeat)) }

    private func tick() {
        ticks += 1
        if ticks % 4 == 0 { beat() }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        let present = Set(names.filter { $0.hasSuffix(Spool.ask) }.map { String($0.dropLast(Spool.ask.count)) })
        // An answered ask is over once its hook took the answer, or died before.
        for (uuid, pid) in answered where !present.contains(uuid) || !Spool.running(pid) {
            answered[uuid] = nil
            unlink(path(uuid + Spool.ask))
            unlink(path(uuid + Spool.answer))
        }
        for uuid in present where open[uuid] == nil && answered[uuid] == nil {
            guard let data = FileManager.default.contents(atPath: path(uuid + Spool.ask)),
                  let ask = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let pid = ask["pid"] as? Int else { continue }
            open[uuid] = pid_t(pid)
            let request = ask["request"] as? [String: Any] ?? [:]
            DispatchQueue.main.async { [weak self] in self?.asked(uuid, request) }
        }
        // A hook that ended takes its ask file with it; one killed leaves it, but its pid is gone.
        for (uuid, pid) in open where !present.contains(uuid) || !Spool.running(pid) {
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
