// No test starts a real agent program, unless it is a live trial its SOMETHING_TRIAL_* variable enables: a real
// Claude or Codex started by the suite runs in the person's own environment (their home, their MCP servers) and, with
// the main run loop turned forever, stalls every test after it. The rule, for every file of Tests/:
// - an Engine is made with `Engine.throwaway`, which finds programs on its environment's PATH only, never in the
//   system's install folders (a test puts its fake programs on that PATH);
// - `something try` (Trial.main, DeveloperTrial.main, the command's "try") is run only with words it refuses.
// A live trial is a file whose suite is `.enabled(if: trial…)`; it starts the program its variable names.
// Behind the scan, Spawn itself refuses under the tests any program that is not a fake (TestRunGuard).
import Foundation
import SomethingCore
import Testing
@testable import SomethingAgents

extension Engine {
    /// An engine for a test: `environment` should be a throwaway home and a PATH of fake programs. The system's
    /// install folders (/opt/homebrew/bin, /usr/local/bin) are not searched, so a kind without its fake on the PATH is
    /// NOT_INSTALLED, never the person's own program.
    static func throwaway(_ environment: [String: String]) -> Engine {
        let engine = Engine(environment: environment)
        engine.programs.systemFolders = []
        return engine
    }
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

    static func matches(_ pattern: String, in line: String) -> [[String]] {
        let regex = try! NSRegularExpression(pattern: pattern)
        return regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).map { match in
            (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: line).map { String(line[$0]) } ?? "" }
        }
    }

    @Test func noTestMakesAnEngineThatFindsThePersonsPrograms() {
        let files = NoRealAgentTests.files()
        #expect(files.contains { $0.name.hasSuffix("EngineTests.swift") }, "the scan reads Tests/")
        for file in files where !file.text.contains(".enabled(if: trial") {
            for (number, line) in NoRealAgentTests.code(file.text).enumerated() where line.contains("Engine(environment:") {
                // The one allowed: the app tests' own throwaway factory, which empties the system folders too.
                let factory = file.name.hasSuffix("Support.swift") && line.contains("Engine(environment: environment)")
                #expect(factory, "\(file.name):\(number + 1) makes an Engine directly; use Engine.throwaway with a throwaway PATH.")
            }
        }
    }

    @Test func noTestRunsSomethingTryWithWordsThatLaunch() {
        var seen = 0
        for file in NoRealAgentTests.files() where !file.text.contains(".enabled(if: trial") {
            for (number, line) in NoRealAgentTests.code(file.text).enumerated() {
                let calls = NoRealAgentTests.matches(#"(?:DeveloperTrial|Trial)\.main\(([^)]*)\)"#, in: line).map { $0[1] }
                    + NoRealAgentTests.matches(#"Ran\((\[\s*"try"[^\]]*\])"#, in: line).map { $0[1] }
                for call in calls {
                    seen += 1
                    let place = "\(file.name):\(number + 1)"
                    guard call.hasPrefix("[") else {
                        Issue.record("\(place) runs something try with words that are not written out: \(call)")
                        continue
                    }
                    let words = NoRealAgentTests.matches(#""([^"]*)""#, in: call).map { $0[1] }
                    if case .success = DeveloperTrial.parse(words) {
                        Issue.record("\(place) runs something try \(words.dropFirst().joined(separator: " ")), which launches a real agent.")
                    }
                }
            }
        }
        #expect(seen >= 3, "the scan finds the calls of PlanBTests and CommandTests")
    }

    @Test func theRefusedWordsAreRefusedAndTheRightOnesAccepted() {
        for words in [["try"], ["try", "nope"], ["claude"], ["try", "claude", "--bogus"], ["try", "codex", "--plan-b"], ["try", "claude", "--record"]] {
            if case .success = DeveloperTrial.parse(words) { Issue.record("\(words) were accepted") }
        }
        guard case .success(let asked) = DeveloperTrial.parse(["try", "claude", "--record", "out.jsonl", "--plan-b"]) else {
            Issue.record("the right words were refused")
            return
        }
        #expect(asked.kind == "claude" && asked.record == "out.jsonl" && asked.planB)
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
        #expect(TestRunGuard.allowed("/usr/sbin/sysctl", environment: ["SOMETHING_TRIAL_CLAUDE": "/usr/sbin/sysctl"]))
        #expect(!TestRunGuard.allowed("/usr/sbin/sysctl", environment: ["SOMETHING_TRIAL_CLAUDE": "/usr/sbin/other"]))
        #expect(!TestRunGuard.allowed("/usr/sbin/sysctl", environment: ["SOMETHING_TRIAL_RECORD": "/usr/sbin/sysctl"]), "only a kind's variable names a program")
        #expect(TestRunGuard.allowed(NSTemporaryDirectory() + "fake/claude", environment: [:]))
        #expect(TestRunGuard.allowed("/bin/sh", environment: [:]) && !TestRunGuard.allowed("/opt/homebrew/bin/claude", environment: [:]))
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
