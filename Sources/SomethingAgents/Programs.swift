// Programs: finds the agent programs something can launch, and what they need to run, whether something was started
// from a Terminal or from the Finder. It only looks for files and never runs an agent's
// program: codex and opencode write into their homes when they start, so `installed` must not depend on running them.
// The one thing it runs is the person's login shell, to learn the PATH their Terminal has, which a Finder launch lacks.
import Foundation
import SomethingCore

/// An agent program found on this Mac.
public struct Program: Equatable, Sendable {
    public let kind: String
    /// Where it was found, as found: a link is kept, since its folder is the one the person installed into.
    public let path: String
    /// The child's PATH: the program's folder first, then the folders it was found through.
    public let folders: [String]

    /// The environment to launch it in: `base` without `removing`, plus `adding`, with this program's PATH.
    public func environment(_ base: [String: String], adding: [String: String] = [:], removing: Set<String> = []) -> [String: String] {
        var environment = base.filter { !removing.contains($0.key) }.merging(adding) { _, added in added }
        environment["PATH"] = folders.joined(separator: ":")
        return environment
    }
}

public final class Programs {
    /// The kinds something looks for. Any other kind is unknown here (nil, never false). omp's file is looked for,
    /// to say whether it is installed; something does not launch it.
    public static let kinds = ["claude", "codex", "opencode", "pi", "omp"]

    /// What to type to install each kind something launches, in Terminal. pi's is its README's (1.0.0), and
    /// `npm view` gives that package name.
    static let install = [
        "claude": "brew install --cask claude-code",
        "codex": "brew install --cask codex",
        "opencode": "brew install opencode",
        "pi": "npm install -g --ignore-scripts @earendil-works/pi-coding-agent",
    ]
    static let names = ["claude": "Claude Code", "codex": "Codex", "opencode": "OpenCode", "pi": "pi", "omp": "OMP"]

    /// The name a person knows the agent `kind` by, in every window and sentence; the kind itself when unknown.
    public static func name(of kind: String) -> String { names[kind] ?? kind }
    /// Interpreters a program needs that its first line does not name: pi's own launcher is a shell script that
    /// starts a node script.
    static let runsOn = ["pi": "node"]
    /// The PATH launchd gives an app opened from the Finder: no folder where agents are installed.
    static let launchdFolders: Set<String> = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    static let shellTimeout: TimeInterval = 3

    private let environment: [String: String]
    /// Homebrew's folders, which tests empty so that this Mac's own programs are not found.
    var systemFolders = ["/opt/homebrew/bin", "/usr/local/bin"]
    private let home: String
    private let lock = NSLock()
    /// The login shell's folders by `interactive`, kept once read, until `until`. A failed login read is tried again.
    /// An interactive shell that ended without the PATH ends so every time: that failure is kept. One that took too
    /// long, login or interactive, is kept a minute, so one look at every kind waits 3 s once, and a busy Mac is not
    /// believed for good.
    private var shellFolders: [Bool: (folders: [String]?, until: Date)] = [:]
    static let slowShellKept: TimeInterval = 60

    /// `environment` is the person's: the Terminal's when something was started from one, else the app's own.
    public init(environment: [String: String]) {
        self.environment = environment
        home = environment["HOME"] ?? NSHomeDirectory()
    }

    /// Whether the program's file was found; nil for a kind something does not look for, and when it was not found
    /// but a shell's PATH, which was needed, could not be read. Never runs the program.
    public func installed(_ kind: String) -> Bool? {
        guard Programs.kinds.contains(kind) else { return nil }
        let search = folders(interactive: false)
        if first(kind, in: search.list) != nil { return true }
        guard search.known else { return nil }
        guard let interactive = interactiveRetry() else { return false }
        if first(kind, in: interactive.list) != nil { return true }
        return interactive.known ? false : nil
    }

    /// The interactive shell's folders, to look again for a program the PATH lacks: nvm and similar tools put what
    /// they installed (and node) on the PATH only in an interactive shell. Nil when the PATH came from a Terminal,
    /// which is that shell's already: the person's startup files are then not run for nothing.
    private func interactiveRetry() -> (list: [String], known: Bool)? {
        given.fromTerminal ? nil : folders(interactive: true)
    }

    /// The program to launch for `kind`. Throws NOT_INSTALLED when no file is found (or for an unknown kind), and
    /// INTERPRETER_NOT_FOUND when what it runs on (node, for example) is missing; each says what to type, or, when
    /// the login shell's PATH could not be read, how to start something from Terminal so that it has that PATH.
    public func find(_ kind: String) throws -> Program {
        guard let command = Programs.install[kind] else {
            throw CodedError("NOT_INSTALLED", "something does not know how to launch \(kind).")
        }
        let name = Programs.name(of: kind)
        var search = folders(interactive: false)
        var found = first(kind, in: search.list)
        if found == nil, search.known, let interactive = interactiveRetry() {
            (search, found) = (interactive, first(kind, in: interactive.list))
        }
        guard let path = found else {
            if !search.known { throw CodedError("NOT_INSTALLED", unread(name)) }
            throw CodedError("NOT_INSTALLED", "\(name) was not found on this Mac. To install it, type in Terminal: \(command)")
        }
        var missing = missingInterpreter(of: path, kind: kind, in: search.list + bundled(kind))
        if missing != nil {
            // nvm and similar tools put node on the PATH only in an interactive shell.
            search = folders(interactive: true)
            missing = missingInterpreter(of: path, kind: kind, in: search.list + bundled(kind))
        }
        if let missing {
            if !search.known { throw CodedError("INTERPRETER_NOT_FOUND", unread("what \(name) needs (\(missing))")) }
            let how = missing == "node" ? "To install it, type in Terminal: brew install node"
                : missing.hasPrefix("/") ? "Install \(name) again: \(command)" : "Install \(missing), then try again."
            throw CodedError("INTERPRETER_NOT_FOUND", "\(name) needs \(missing), which was not found on this Mac. \(how)")
        }
        let folder = (path as NSString).deletingLastPathComponent
        return Program(kind: kind, path: path, folders: Programs.unique([folder] + search.list + bundled(kind)))
    }

    /// Where to look, in order: the PATH from the command line when there is one, else the login shell's; then the
    /// folders installers use, for a shell that does not set them. `known` is false when the login shell's PATH was
    /// needed and could not be read: what is not found there is then not known to be missing.
    func folders(interactive: Bool) -> (list: [String], known: Bool) {
        var path = given.folders
        var known = true
        if interactive || !given.fromTerminal {
            if let read = shell(interactive: interactive) { path = read } else { known = false }
        }
        let fixed = systemFolders + [".local/bin", ".bun/bin", ".opencode/bin", ".volta/bin"].map { "\(home)/\($0)" }
        return (Programs.unique(path + (interactive ? given.folders : []) + fixed), known)
    }

    /// The PATH from the command line, and whether it is a Terminal's: launchd's own folders alone are a Finder launch.
    private var given: (folders: [String], fromTerminal: Bool) {
        let folders = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return (folders, folders.contains { !Programs.launchdFolders.contains($0) })
    }

    /// Folders a program's installer filled for it alone: the node pi's installer brings, which pi's launcher puts on
    /// the PATH itself. It goes last on the child's PATH too, so that a pi started by `#!/usr/bin/env node` finds it.
    func bundled(_ kind: String) -> [String] {
        guard kind == "pi" else { return [] }
        let piNode = "\(environment["XDG_DATA_HOME"] ?? "\(home)/.local/share")/pi-node/current/bin"
        return FileManager.default.fileExists(atPath: piNode) ? [piNode] : []
    }

    /// The sentence for something the login shell's PATH was needed to find, and could not be read.
    private func unread(_ what: String) -> String {
        "something could not read the PATH of your login shell (\(environment["SHELL"] ?? "/bin/zsh")), so it cannot tell "
            + "whether \(what) is on this Mac. Quit something, then start it from Terminal by typing: something"
    }

    /// The first executable file named `kind` in `folders`. The Claude desktop app's own copy is never used: it is
    /// the app's, updated by the app, and may differ from the Claude Code the person installed.
    func first(_ kind: String, in folders: [String]) -> String? {
        folders.lazy.map { "\($0)/\(kind)" }.first { path in
            var folder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &folder), !folder.boolValue,
                  FileManager.default.isExecutableFile(atPath: path) else { return false }
            let real = (path as NSString).resolvingSymlinksInPath
            return !(kind == "claude" && (real.contains("/Application Support/Claude/") || real.contains("/Claude.app/")))
        }
    }

    /// The interpreter the program needs and `folders` lack, by name or absolute path; nil when nothing is missing.
    func missingInterpreter(of path: String, kind: String, in folders: [String]) -> String? {
        var needs = Programs.runsOn[kind].map { [$0] } ?? []
        if let named = Programs.interpreter(of: (path as NSString).resolvingSymlinksInPath) { needs.insert(named, at: 0) }
        return needs.first { need in
            if need.hasPrefix("/") { return !FileManager.default.isExecutableFile(atPath: need) }
            return !folders.contains { FileManager.default.isExecutableFile(atPath: "\($0)/\(need)") }
        }
    }

    /// What a script's first line runs: the name after `/usr/bin/env` (its options and assignments skipped), or the
    /// interpreter's absolute path; nil for a binary or a file that cannot be read.
    static func interpreter(of file: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: file) else { return nil }
        defer { try? handle.close() }
        let head = String(decoding: handle.readData(ofLength: 512), as: UTF8.self)
        guard head.hasPrefix("#!"), let line = head.dropFirst(2).split(separator: "\n").first else { return nil }
        let words = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let first = words.first else { return nil }
        guard (first as NSString).lastPathComponent == "env" else { return first }
        return words.dropFirst().first { !$0.hasPrefix("-") && !$0.contains("=") }
    }

    /// The login shell's PATH folders (`-l`, and `-i` too when `interactive`), kept as `shellFolders` says; nil when
    /// the shell is not absolute, fails, prints no marker or takes longer than 3 s.
    func shell(interactive: Bool) -> [String]? {
        if let kept = lock.withLock({ shellFolders[interactive] }), kept.until > Date() { return kept.folders }
        let read = readShell(interactive: interactive)
        let until: Date? = switch read {
        case .path: .distantFuture
        case .ended: interactive ? .distantFuture : nil
        case .slow: Date().addingTimeInterval(Programs.slowShellKept)
        }
        if let until { lock.withLock { shellFolders[interactive] = (read.folders, until) } }
        return read.folders
    }

    enum ShellRead {
        case path([String])
        /// The shell could not start, or ended without printing the PATH.
        case ended
        /// It was still running after 3 s.
        case slow

        var folders: [String]? { if case .path(let folders) = self { folders } else { nil } }
    }

    private func readShell(interactive: Bool) -> ShellRead {
        let shell = environment["SHELL"] ?? "/bin/zsh"
        guard shell.hasPrefix("/") else { return .ended }
        // A POSIX child prints the PATH it inherits, which every shell exports joined by colons (fish's own "$PATH"
        // is joined by spaces). The marker is new at each read, so nothing the startup files print passes for it.
        let marker = "<<something-\(UUID().uuidString)>>"
        let command = #"/bin/sh -c 'printf "\#(marker)%s\n" "$PATH"'"#
        let spawn = Spawn(path: shell, arguments: (interactive ? ["-l", "-i"] : ["-l"]) + ["-c", command],
                          folder: FileManager.default.fileExists(atPath: home) ? home : "/", environment: environment, input: false)
        let found = NSLock()
        var path: String?
        let answered = DispatchSemaphore(value: 0)
        do {
            try spawn.start(lines: { line in
                let text = String(decoding: line, as: UTF8.self)
                guard text.hasPrefix(marker) else { return }
                found.withLock { path = String(text.dropFirst(marker.count)) }
                answered.signal()
            }, ended: { _ in answered.signal() })
        } catch { return .ended }
        let slow = answered.wait(timeout: .now() + Programs.shellTimeout) == .timedOut
        // Taken as soon as it is printed: the shell, and anything its startup files left running, is not waited for.
        spawn.stop(cap: 0)
        if let path = found.withLock({ path }) { return .path(path.split(separator: ":").map(String.init)) }
        return slow ? .slow : .ended
    }

    static func unique(_ folders: [String]) -> [String] {
        var seen = Set<String>()
        return folders.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
