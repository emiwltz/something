// Programs in an environment as bare as `env -i` gives, with a fake login shell and invented programs in a throwaway
// home. Homebrew's folders are emptied, so this Mac's own agents are never found, and the person's shell never runs.
import Foundation
import Testing
@testable import SomethingAgents
import SomethingCore

final class FakeMac {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("programs-\(UUID().uuidString)").path
    var home: String { "\(root)/home" }
    var shellRan: Bool { FileManager.default.fileExists(atPath: "\(root)/shell-ran") }
    /// The words each run of the fake shell was given, in order.
    var shellRuns: [String] { ((try? String(contentsOfFile: "\(root)/shell-runs", encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }

    init() throws { try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(atPath: root) }

    /// An executable file at `path` (under the root) whose first line is `head`.
    @discardableResult func program(_ path: String, _ head: String = "#!/bin/sh") throws -> String {
        let full = "\(root)/\(path)"
        try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try "\(head)\nexit 0\n".write(toFile: full, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: full)
        return full
    }

    /// A login shell that prints rc noise (with decoy markers), then runs its -c command with `login` as PATH, or
    /// `interactive` when -i is given; `before` runs first (to hang it, for example).
    func shell(login: [String], interactive: [String], before: String = "") throws -> String {
        let script = """
            #!/bin/sh
            : > "\(root)/shell-ran"
            echo "$*" >> "\(root)/shell-runs"
            \(before)
            echo '<<something-decoy>>/Users/example/decoy'
            case " $* " in *" -i "*) PATH='\(interactive.map { "\(root)/\($0)" }.joined(separator: ":"))' ;;
              *) PATH='\(login.map { "\(root)/\($0)" }.joined(separator: ":"))' ;; esac
            export PATH   # a login shell always exports it, even when it started without one
            for last; do :; done
            eval "$last"
            echo 'rc noise after'
            """
        let path = "\(root)/fake-shell"
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    func programs(_ environment: [String: String]) -> Programs {
        let programs = Programs(environment: environment.merging(["HOME": home]) { given, _ in given })
        programs.systemFolders = []
        return programs
    }
}

func code(_ body: () throws -> Void) -> CodedError? {
    do { try body() } catch let error as CodedError { return error } catch {}
    return nil
}

@Suite struct ProgramsTests {
    @Test func theTerminalsPathIsUsedAndTheShellIsNotRun() throws {
        let mac = try FakeMac()
        try mac.program("term/claude")
        let shell = try mac.shell(login: [], interactive: [])
        let programs = mac.programs(["PATH": "\(mac.root)/term:/usr/bin:/bin", "SHELL": shell])
        let claude = try programs.find("claude")
        #expect(claude.path == "\(mac.root)/term/claude")
        #expect(claude.folders.first == "\(mac.root)/term")
        #expect(programs.installed("claude") == true)
        #expect(!mac.shellRan)
    }

    @Test func afterAFinderLaunchTheLoginShellsPathIsRead() throws {
        let mac = try FakeMac()
        try mac.program("login/codex")
        let shell = try mac.shell(login: ["login", "other"], interactive: [])
        let programs = mac.programs(["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "SHELL": shell])
        let codex = try programs.find("codex")
        #expect(codex.path == "\(mac.root)/login/codex")
        #expect(codex.folders.prefix(2) == ["\(mac.root)/login", "\(mac.root)/other"])
        #expect(mac.shellRan)
    }

    /// With nvm, node is only on an interactive shell's PATH: the second read finds it and gives its folder to pi.
    @Test func aMissingInterpreterIsLookedForInAnInteractiveShell() throws {
        let mac = try FakeMac()
        try mac.program("login/pi", "#!/usr/bin/env node")
        try mac.program("nvm/node")
        let shell = try mac.shell(login: ["login"], interactive: ["login", "nvm"])
        let pi = try mac.programs(["SHELL": shell]).find("pi")
        #expect(pi.folders.first == "\(mac.root)/login")
        #expect(pi.folders.contains("\(mac.root)/nvm"))
        #expect(pi.environment(["HOME": mac.home])["PATH"]?.hasPrefix("\(mac.root)/login:") == true)
    }

    @Test func aMissingInterpreterSaysWhatToType() throws {
        let mac = try FakeMac()
        try mac.program("login/pi")   // pi's own launcher: a shell script that needs node all the same
        try mac.program("login/opencode", "#!/Users/example/gone/bun")
        let shell = try mac.shell(login: ["login"], interactive: ["login"])
        let programs = mac.programs(["SHELL": shell])
        let pi = code { _ = try programs.find("pi") }
        #expect(pi == CodedError("INTERPRETER_NOT_FOUND", "pi needs node, which was not found on this Mac. To install it, type in Terminal: brew install node"))
        #expect(programs.installed("pi") == true)
        let opencode = code { _ = try programs.find("opencode") }
        #expect(opencode?.code == "INTERPRETER_NOT_FOUND")
        #expect(opencode?.message.hasSuffix("Install OpenCode again: brew install opencode") == true)
    }

    /// The node pi's installer brought is found where pi's launcher looks for it, and is on the child's PATH for a pi
    /// that `env` starts.
    @Test func pisOwnNodeCounts() throws {
        let mac = try FakeMac()
        try mac.program("home/.local/bin/pi")
        try mac.program("term/pi", "#!/usr/bin/env node")
        let piNode = try (mac.program("home/.local/share/pi-node/current/bin/node") as NSString).deletingLastPathComponent
        let fromFinder = try mac.programs(["PATH": "/usr/bin:/bin", "SHELL": "/Users/example/no-shell"]).find("pi")
        #expect(fromFinder.path == "\(mac.home)/.local/bin/pi")
        let fromTerminal = try mac.programs(["PATH": "\(mac.root)/term:/usr/bin:/bin"]).find("pi")
        #expect(fromTerminal.path == "\(mac.root)/term/pi")
        #expect(fromTerminal.folders.last == piNode)
    }

    @Test func aProgramNotFoundSaysWhatToType() throws {
        let mac = try FakeMac()
        let programs = mac.programs(["PATH": "/usr/bin:/bin", "SHELL": try mac.shell(login: [], interactive: [])])
        #expect(code { _ = try programs.find("opencode") } ==
                CodedError("NOT_INSTALLED", "OpenCode was not found on this Mac. To install it, type in Terminal: brew install opencode"))
        #expect(programs.installed("opencode") == false)
        #expect(programs.installed("omp") == false)
        #expect(programs.installed("amp") == nil)
        #expect(code { _ = try programs.find("omp") }?.code == "NOT_INSTALLED")
    }

    @Test func theInstallersFoldersAreSearchedWhenTheShellFails() throws {
        let mac = try FakeMac()
        try mac.program("home/.opencode/bin/opencode")
        try mac.program("home/.bun/bin/codex")
        let programs = mac.programs(["PATH": "/usr/bin:/bin", "SHELL": "relative-shell"])
        #expect(try programs.find("opencode").path == "\(mac.home)/.opencode/bin/opencode")
        #expect(try programs.find("codex").path == "\(mac.home)/.bun/bin/codex")
    }

    @Test func theDesktopAppsClaudeIsNeverUsed() throws {
        let mac = try FakeMac()
        let bundled = try mac.program("home/Library/Application Support/Claude/claude-code/2.1.0/claude")
        try FileManager.default.createDirectory(atPath: "\(mac.root)/term", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: "\(mac.root)/term/claude", withDestinationPath: bundled)
        let programs = mac.programs(["PATH": "\(mac.root)/term:/usr/bin", "SHELL": "/Users/example/no-shell"])
        #expect(code { _ = try programs.find("claude") }?.code == "NOT_INSTALLED")
        #expect(programs.installed("claude") == false)
    }

    /// From the Finder, a shell that hangs is given up after 3 s and ended. What it would have found is then not
    /// known to be missing: installed says nil, and find says how to give something the PATH.
    @Test func aShellThatHangsIsLeftAfterThreeSeconds() throws {
        let mac = try FakeMac()
        try mac.program("login/codex")
        let shell = try mac.shell(login: ["login"], interactive: [], before: "echo $$ > '\(mac.root)/shell-pid'; sleep 30")
        let finder = mac.programs(["PATH": "/usr/bin:/bin", "SHELL": shell])
        let start = Date()
        #expect(finder.installed("codex") == nil)
        let took = Date().timeIntervalSince(start)
        #expect(took > 2.9 && took < 4.5)
        #expect(mac.shellRan)
        let pid = try #require(pid_t((try? String(contentsOfFile: "\(mac.root)/shell-pid", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""))
        let deadline = Date().addingTimeInterval(2)
        while processExists(pid) && Date() < deadline { usleep(20_000) }
        #expect(!processExists(pid))
        let error = code { _ = try finder.find("codex") }
        #expect(error?.code == "NOT_INSTALLED")
        #expect(error?.message.hasSuffix("start it from Terminal by typing: something") == true)
        // From a Terminal, the shell is not needed and what is not found is not there.
        #expect(mac.programs(["PATH": "\(mac.root)/term:/usr/bin:/bin", "SHELL": shell]).installed("codex") == false)
    }

    /// A failed read is not kept: once the shell answers, the program is found.
    @Test func aFailedReadIsTriedAgain() throws {
        let mac = try FakeMac()
        try mac.program("login/codex")
        let shell = try mac.shell(login: ["login"], interactive: [], before: "[ -f '\(mac.root)/ready' ] || exit 1")
        let programs = mac.programs(["PATH": "/usr/bin:/bin", "SHELL": shell])
        #expect(programs.installed("codex") == nil)
        try "".write(toFile: "\(mac.root)/ready", atomically: true, encoding: .utf8)
        #expect(programs.installed("codex") == true)
    }

    /// An npm install under nvm puts the program on an interactive shell's PATH only: it is looked for there, and
    /// that read is kept.
    @Test func aProgramOnlyAnInteractiveShellFindsIsFound() throws {
        let mac = try FakeMac()
        try mac.program("nvm/pi", "#!/usr/bin/env node")
        try mac.program("nvm/node")
        let programs = mac.programs(["SHELL": try mac.shell(login: ["login"], interactive: ["login", "nvm"])])
        #expect(programs.installed("pi") == true)
        let pi = try programs.find("pi")
        #expect(pi.path == "\(mac.root)/nvm/pi")
        #expect(pi.folders.first == "\(mac.root)/nvm")
        #expect(mac.shellRuns.filter { $0.contains("-i") }.count == 1)
    }

    /// An interactive shell that fails is not tried again for each program, and what only it could have found is
    /// not known to be missing.
    @Test func aFailedInteractiveReadIsKept() throws {
        let mac = try FakeMac()
        let shell = try mac.shell(login: ["login"], interactive: ["login"], before: #"case " $* " in *" -i "*) exit 1 ;; esac"#)
        let programs = mac.programs(["SHELL": shell])
        #expect(programs.installed("codex") == nil)
        #expect(programs.installed("omp") == nil)
        #expect(code { _ = try programs.find("codex") }?.message.hasSuffix("start it from Terminal by typing: something") == true)
        #expect(mac.shellRuns.filter { $0.contains("-i") }.count == 1)
    }

    /// From a Terminal, the PATH is the interactive shell's already: a program missing from it is missing, and the
    /// person's startup files are not run to look again.
    @Test func fromATerminalAMissingProgramRunsNoShell() throws {
        let mac = try FakeMac()
        try mac.program("nvm/pi")
        let shell = try mac.shell(login: ["login"], interactive: ["nvm"])
        let programs = mac.programs(["PATH": "\(mac.root)/term:/usr/bin:/bin", "SHELL": shell])
        #expect(programs.installed("pi") == false)
        #expect(code { _ = try programs.find("pi") }?.message.hasSuffix("@earendil-works/pi-coding-agent") == true)
        #expect(mac.shellRuns.isEmpty)
    }

    @Test func theFirstLineNamesTheInterpreter() throws {
        let mac = try FakeMac()
        #expect(Programs.interpreter(of: try mac.program("a", "#!/usr/bin/env -S node --no-warnings")) == "node")
        #expect(Programs.interpreter(of: try mac.program("b", "#!/usr/bin/env NODE_OPTIONS=x bun")) == "bun")
        #expect(Programs.interpreter(of: try mac.program("c", "#!/bin/sh -e")) == "/bin/sh")
        #expect(Programs.interpreter(of: try mac.program("d", "\u{7F}ELF")) == nil)
        #expect(Programs.interpreter(of: "/Users/example/none") == nil)
    }

    @Test func theChildsEnvironmentIsThePersonsPlusTheLaunchs() {
        let program = Program(kind: "claude", path: "/Users/example/bin/claude", folders: ["/Users/example/bin", "/usr/bin"])
        let environment = program.environment(["HOME": "/Users/example", "ANTHROPIC_API_KEY": "invented", "PATH": "/usr/bin"],
                                              adding: ["SOMETHING_AGENT": "a1"], removing: ["ANTHROPIC_API_KEY"])
        #expect(environment == ["HOME": "/Users/example", "SOMETHING_AGENT": "a1", "PATH": "/Users/example/bin:/usr/bin"])
    }
}
