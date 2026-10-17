// Programs: finds the agent programs something can launch, and what they need to run, whether something was started
// from a Terminal or from the Finder (design 5, "Agent programs"). It only looks for files and never runs an agent's
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
    /// The kinds something looks for. Any other kind is unknown here (nil, never false).
    public static let kinds = ["claude", "codex", "opencode", "pi"]

    /// What to type to install each one, in Terminal.
    static let install: [String: (name: String, command: String)] = [
        "claude": ("Claude Code", "brew install --cask claude-code"),
        "codex": ("Codex", "brew install --cask codex"),
        "opencode": ("OpenCode", "brew install opencode"),
        "pi": ("pi", "npm install -g @earendil-works/pi-coding-agent"),
    ]
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
    /// The login shell's folders by `interactive`, kept after the first read, a failed one included (nil).
    private var shellFolders: [Bool: [String]?] = [:]

    /// `environment` is the person's: the Terminal's when something was started from one, else the app's own.
    public init(environment: [String: String]) {
        self.environment = environment
        home = environment["HOME"] ?? NSHomeDirectory()
    }

    /// Whether the program's file was found; nil for a kind something does not look for. Never runs the program.
    public func installed(_ kind: String) -> Bool? {
        guard Programs.kinds.contains(kind) else { return nil }
        return first(kind, in: folders(interactive: false)) != nil
    }

    /// The program to launch for `kind`. Throws NOT_INSTALLED when no file is found (or for an unknown kind), and
    /// INTERPRETER_NOT_FOUND when what it runs on (node, for example) is missing; each says what to type.
    public func find(_ kind: String) throws -> Program {
        guard let (name, command) = Programs.install[kind] else {
            throw CodedError("NOT_INSTALLED", "something does not know how to launch \(kind).")
        }
        var folders = folders(interactive: false)
        guard let path = first(kind, in: folders) else {
            throw CodedError("NOT_INSTALLED", "\(name) was not found on this Mac. To install it, type in Terminal: \(command)")
        }
        var missing = missingInterpreter(of: path, kind: kind, in: folders)
        if missing != nil {
            // nvm and similar tools put node on the PATH only in an interactive shell.
            folders = self.folders(interactive: true)
            missing = missingInterpreter(of: path, kind: kind, in: folders)
        }
        if let missing {
            let how = missing == "node" ? "To install it, type in Terminal: brew install node"
                : missing.hasPrefix("/") ? "Install \(name) again: \(command)" : "Install \(missing), then try again."
            throw CodedError("INTERPRETER_NOT_FOUND", "\(name) needs \(missing), which was not found on this Mac. \(how)")
        }
        return Program(kind: kind, path: path, folders: Programs.unique([(path as NSString).deletingLastPathComponent] + folders))
    }

    /// Where to look, in order: the PATH from the command line when there is one, else the login shell's; then the
    /// folders installers use, for a shell that does not set them.
    func folders(interactive: Bool) -> [String] {
        let given = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let fromTerminal = given.contains { !Programs.launchdFolders.contains($0) }
        let path = fromTerminal && !interactive ? given : (shell(interactive: interactive) ?? given)
        let fixed = systemFolders + [".local/bin", ".bun/bin", ".opencode/bin", ".volta/bin"].map { "\(home)/\($0)" }
        return Programs.unique(path + (interactive ? given : []) + fixed)
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
            var places = folders
            // pi's launcher puts the node its installer brought first on the PATH itself.
            if kind == "pi" && need == "node" {
                places.append("\(environment["XDG_DATA_HOME"] ?? "\(home)/.local/share")/pi-node/current/bin")
            }
            return !places.contains { FileManager.default.isExecutableFile(atPath: "\($0)/\(need)") }
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

    /// The login shell's PATH folders (`-l`, and `-i` too when `interactive`), read once and kept; nil when the shell
    /// is not absolute, fails, prints no markers or takes longer than 3 s. The markers set the PATH apart from what
    /// the person's startup files print.
    func shell(interactive: Bool) -> [String]? {
        if case .some(let kept) = lock.withLock({ shellFolders[interactive] }) { return kept }
        let folders = readShell(interactive: interactive)
        lock.withLock { shellFolders[interactive] = .some(folders) }
        return folders
    }

    private func readShell(interactive: Bool) -> [String]? {
        let shell = environment["SHELL"] ?? "/bin/zsh"
        guard shell.hasPrefix("/") else { return nil }
        let spawn = Spawn(path: shell, arguments: (interactive ? ["-l", "-i"] : ["-l"]) + ["-c", "printf '<<%s>>' \"$PATH\""],
                          folder: FileManager.default.fileExists(atPath: home) ? home : "/", environment: environment, input: false)
        let said = NSMutableData(), finished = DispatchSemaphore(value: 0)
        do {
            try spawn.start(lines: { line in said.append(line); said.append(Data([0x0A])) }, ended: { _ in finished.signal() })
        } catch { return nil }
        guard finished.wait(timeout: .now() + Programs.shellTimeout) == .success else {
            spawn.stop(cap: 0)
            return nil
        }
        let text = String(decoding: said as Data, as: UTF8.self)
        guard let end = text.range(of: ">>", options: .backwards),
              let start = text.range(of: "<<", options: .backwards, range: text.startIndex..<end.lowerBound) else { return nil }
        return text[start.upperBound..<end.lowerBound].split(separator: ":").map(String.init)
    }

    static func unique(_ folders: [String]) -> [String] {
        var seen = Set<String>()
        return folders.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
