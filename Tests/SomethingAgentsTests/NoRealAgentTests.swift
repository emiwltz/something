// No test starts a real agent program, unless it is a live trial its SOMETHING_TRIAL_* variable enables: a real
// Claude or Codex started by the suite runs in the person's own environment (their home, their MCP servers) and, with
// the main run loop turned forever, stalls every test after it. The rule, for every file of Tests/:
// - an Engine is made with `Engine.throwaway`, which finds programs on its environment's PATH only, never in the
//   system's install folders (a test puts its fake programs on that PATH);
// - `something try` (the app's DeveloperTrial) is run only with words it refuses: somethingTests' TryTests scans for it.
// A live trial is a file whose suite is `.enabled(if: trial…)`; it starts the program its variable names.
// Behind the scan, Spawn itself refuses under the tests any program that is not a fake (TestRunGuard).
import Foundation
import SomethingCore
import Testing
@testable import SomethingAgents
@testable import AgentACP
@testable import AgentClaude
@testable import AgentCodex
@testable import AgentPi

extension Engine {
    /// An engine for a test: `environment` should be a throwaway home and a PATH of fake programs. The system's
    /// install folders (/opt/homebrew/bin, /usr/local/bin) are not searched, so a kind without its fake on the PATH is
    /// NOT_INSTALLED, never the person's own program.
    static func throwaway(_ environment: [String: String]) -> Engine {
        let engine = Engine(environment: environment, registry: .described)
        engine.programs.systemFolders = []
        return engine
    }
}

extension Registry {
    /// Every agent described by the Agent* targets, as the app registers them (Extensions.swift): DescriptorsTests and
    /// somethingTests' ExtensionsTests hold both lists to 0.2's.
    static let described = Registry([.claude, .codex, .opencode, .pi, .omp(reader: OMP.reader)],
                                     others: ["gemini", "amp", "qwen", "goose", "crush", "cursor-agent", "droid", "copilot", "auggie"])
}

struct NoRealAgentTests {
    static let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Every Swift file of Tests/ but this one, with its text, by path relative to Tests/.
    static func files() -> [(name: String, text: String)] {
        let names = (FileManager.default.enumerator(atPath: tests.path)?.allObjects as? [String]) ?? []
        return names.filter { $0.hasSuffix(".swift") && !$0.hasSuffix("NoRealAgentTests.swift") }.sorted().compactMap { name in
            (try? String(contentsOf: tests.appendingPathComponent(name), encoding: .utf8)).map { (name, $0) }
        }
    }

    /// The code of `text`, without its comments, line by line.
    static func code(_ text: String) -> [String] {
        text.components(separatedBy: "\n").map { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("//") || line.trimmingCharacters(in: .whitespaces).hasPrefix("///") ? "" : line
        }
    }

    @Test func noTestMakesAnEngineThatFindsThePersonsPrograms() {
        let files = NoRealAgentTests.files()
        #expect(files.contains { $0.name.hasSuffix("EngineTests.swift") }, "the scan reads Tests/")
        for file in files where !file.text.contains(".enabled(if: trial") {
            for (number, line) in NoRealAgentTests.code(file.text).enumerated() where line.contains("Engine(environment:") {
                // The one allowed: the app tests' own throwaway factory, which empties the system folders too.
                let factory = file.name.hasSuffix("Support.swift") && line.contains("Engine(environment: environment, registry: .app)")
                #expect(factory, "\(file.name):\(number + 1) makes an Engine directly; use Engine.throwaway with a throwaway PATH.")
            }
        }
    }

    /// Whatever a test does, Spawn starts no program outside the temporary folder and the system's tools, but the one
    /// a SOMETHING_TRIAL_* variable names. sysctl stands in for an agent installed on this Mac: it is never started.
    @Test func spawnRefusesARealProgramUnderTheTests() throws {
        #expect(TestRunGuard.underTests)
        let spawn = Spawn(path: "/usr/sbin/sysctl", arguments: ["-n", "hw.ncpu"], folder: "/", environment: [:], input: false)
        do {
            try spawn.start(lines: { _ in }, ended: { _ in })
            spawn.stop()
            Issue.record("a program outside the temporary folder was started")
        } catch { #expect((error as? CodedError)?.code == "LAUNCH_FAILED") }
        #expect(spawn.pid == 0)
        #expect(TestRunGuard.allowed("/usr/sbin/sysctl", kind: "claude", environment: ["SOMETHING_TRIAL_CLAUDE": "/usr/sbin/sysctl"]))
        #expect(!TestRunGuard.allowed("/usr/sbin/sysctl", kind: "codex", environment: ["SOMETHING_TRIAL_CLAUDE": "/usr/sbin/sysctl"]), "only its own kind's variable")
        #expect(!TestRunGuard.allowed("/usr/sbin/sysctl", kind: nil, environment: ["SOMETHING_TRIAL_CLAUDE": "/usr/sbin/sysctl"]), "a program that is no agent")
        #expect(!TestRunGuard.allowed("/usr/sbin/sysctl", kind: "claude", environment: ["SOMETHING_TRIAL_CLAUDE": "/usr/sbin/other"]))
        #expect(!TestRunGuard.allowed("/usr/sbin/sysctl", kind: "claude", environment: ["SOMETHING_TRIAL_RECORD": "/usr/sbin/sysctl"]), "only a kind's variable names a program")
        #expect(TestRunGuard.allowed(NSTemporaryDirectory() + "fake/claude", kind: "claude", environment: [:]))
        #expect(TestRunGuard.allowed("/bin/sh", kind: nil, environment: [:]) && !TestRunGuard.allowed("/opt/homebrew/bin/claude", kind: "claude", environment: [:]))
    }

    /// The throwaway engine finds no program its PATH lacks, even one installed on this Mac.
    @Test func aThrowawayEngineFindsOnlyItsPath() throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("no-agents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        let engine = Engine.throwaway(["HOME": empty.path, "PATH": "\(empty.path):/usr/bin:/bin", "SHELL": "/bin/sh"])
        for kind in ["claude", "codex", "opencode", "pi"] {
            #expect(throws: CodedError.self, "\(kind)") { try engine.launch(kind, folder: empty.path, model: nil, mode: nil, effort: nil) }
        }
        #expect(engine.state.agents.isEmpty)
    }
}
