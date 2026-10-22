// `something try` (DeveloperTrial) launches a real agent from a terminal: under the tests it runs only with words it
// refuses. A scan of every file of Tests/ checks each call written there, as NoRealAgentTests does for engines.
import Foundation
import SomethingAgents
import Testing
@testable import something

struct TryTests {
    static let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// The lines of code of every Swift file of Tests/ but the live trials, comments left out, by path relative to Tests/.
    /// A live trial's suite is enabled only if its variable is set; the words that say so are split here, so that this
    /// file, which runs `something try` too, is scanned.
    static func files() -> [(name: String, lines: [String])] {
        let names = (FileManager.default.enumerator(atPath: tests.path)?.allObjects as? [String]) ?? []
        return names.filter { $0.hasSuffix(".swift") }.sorted().compactMap { name in
            guard let text = try? String(contentsOf: tests.appendingPathComponent(name), encoding: .utf8),
                  !text.contains(".enabled(if: " + "trial") else { return nil }
            return (name, text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") ? "" : $0 })
        }
    }

    static func matches(_ pattern: String, in line: String) throws -> [[String]] {
        try NSRegularExpression(pattern: pattern).matches(in: line, range: NSRange(line.startIndex..., in: line)).map { match in
            (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: line).map { String(line[$0]) } ?? "" }
        }
    }

    /// Plan B's spools, which the app and `something try` give the engine, are in the person's Application Support,
    /// never in $TMPDIR, which a sandboxed agent may write.
    @Test func theSpoolsAreNotInTheTemporaryFolder() {
        let spools = Places(home: URL(fileURLWithPath: "/Users/example")).spools.path
        #expect(spools == "/Users/example/Library/Application Support/something/spool")
        #expect(!spools.hasPrefix(NSTemporaryDirectory()))
    }

    @Test func noTestRunsSomethingTryWithWordsThatLaunch() throws {
        var seen = 0
        for file in TryTests.files() {
            for (number, line) in file.lines.enumerated() {
                let calls = try TryTests.matches(#"(?:DeveloperTrial|Trial)\.main\(([^)]*)\)"#, in: line).map { $0[1] }
                    + TryTests.matches(#"Ran\((\[\s*"try"[^\]]*\])"#, in: line).map { $0[1] }
                for call in calls {
                    seen += 1
                    let place = "\(file.name):\(number + 1)"
                    guard call.hasPrefix("[") else {
                        Issue.record("\(place) runs something try with words that are not written out: \(call)")
                        continue
                    }
                    let words = try TryTests.matches(#""([^"]*)""#, in: call).map { $0[1] }
                    if case .success = DeveloperTrial.parse(words, registry: .app) {
                        Issue.record("\(place) runs something try \(words.dropFirst().joined(separator: " ")), which launches a real agent.")
                    }
                }
            }
        }
        #expect(seen >= 3, "the scan finds the calls of this file and CommandTests")
    }

    @Test func theRefusedWordsAreRefusedAndTheRightOnesAccepted() {
        for words in [["try"], ["try", "nope"], ["claude"], ["try", "claude", "--bogus"], ["try", "codex", "--plan-b"], ["try", "claude", "--record"]] {
            if case .success = DeveloperTrial.parse(words, registry: .app) { Issue.record("\(words) were accepted") }
        }
        guard case .success(let asked) = DeveloperTrial.parse(["try", "claude", "--record", "out.jsonl", "--plan-b"], registry: .app) else {
            Issue.record("the right words were refused")
            return
        }
        #expect(asked.kind == "claude" && asked.record == "out.jsonl" && asked.planB)
    }

    /// Wrong words exit with 2 before anything starts.
    @Test func wrongWords() {
        #expect(DeveloperTrial.main(["try", "nope"], registry: .app) == 2)
        #expect(DeveloperTrial.main(["try", "claude", "--bogus"], registry: .app) == 2)
        #expect(DeveloperTrial.main(["claude", "--record"], registry: .app) == 2, "the words begin with try")
    }

    /// A forced plan B is for a kind that has one: any other is refused, in 0.2's words.
    @Test func aPlanBItsKindDoesNotHaveIsRefused() {
        guard case .failure(let wrong) = DeveloperTrial.parse(["try", "codex", "--plan-b"], registry: .app) else { Issue.record("codex --plan-b was taken"); return }
        #expect(wrong.message == "something try: --plan-b is for claude only.", "the 0.2 wording stays")
    }
}
