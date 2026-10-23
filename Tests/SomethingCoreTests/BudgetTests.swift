// Budgets: the line counts AGENTS.md promises ("Minimal"), checked at each run of the suite. Every line counts,
// code, comments and blank lines alike, as `wc -l` counts them: a budget is about what a reader has to read.
import Foundation
import Testing

enum Budget {
    static let core = 1_800, host = 2_800, driver = 600, agentsShared = 400, app = 5_500

    /// The lines of a text, counted as `wc -l` counts them, plus a last line without its newline.
    static func lines(_ text: String) -> Int {
        let newlines = text.utf8.filter { $0 == UInt8(ascii: "\n") }.count
        return newlines + (text.isEmpty || text.hasSuffix("\n") ? 0 : 1)
    }

    /// The Swift files under a folder, subfolders included, by path relative to it, with their line counts;
    /// empty when the folder does not exist (`theSourcesHoldTheirBudgets` checks that each one does).
    static func files(in folder: URL) -> [(name: String, lines: Int)] {
        let names = (FileManager.default.enumerator(atPath: folder.path)?.allObjects as? [String]) ?? []
        return names.filter { $0.hasSuffix(".swift") }.sorted().compactMap { name in
            guard let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) else { return nil }
            return (name, lines(text))
        }
    }

    /// The folders of Sources/ under `root` that hold an agent family's target: their names start with Agent.
    static func agentTargets(under root: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Sources").path)) ?? []
        return names.filter { $0.hasPrefix("Agent") }.sorted()
    }

    /// Every budget the sources under `root` exceed, one sentence each; empty when all hold.
    static func problems(under root: URL) -> [String] {
        let sources = root.appendingPathComponent("Sources")
        var problems: [String] = []
        let core = files(in: sources.appendingPathComponent("SomethingCore")).map(\.lines).reduce(0, +)
        if core > Budget.core { problems.append("SomethingCore has \(core) lines; its budget is \(Budget.core).") }
        let host = files(in: sources.appendingPathComponent("SomethingAgents"))
        if host.map(\.lines).reduce(0, +) > Budget.host {
            problems.append("SomethingAgents has \(host.map(\.lines).reduce(0, +)) lines; its budget is \(Budget.host).")
        }
        // The host holds no driver: every file of it, Driver.swift (the contract) included, has a shared file's budget.
        for file in host where file.lines > agentsShared {
            problems.append("\(file.name) has \(file.lines) lines; a shared file has \(agentsShared).")
        }
        // Each agent family's target (Agent*): a driver's budget for its drivers, a file's for the others, none in all.
        for target in agentTargets(under: root) {
            for file in files(in: sources.appendingPathComponent(target)) {
                let isDriver = (file.name as NSString).lastPathComponent.hasSuffix("Driver.swift")
                let (role, budget) = isDriver ? ("driver", driver) : ("file", agentsShared)
                if file.lines > budget { problems.append("\(target)/\(file.name) has \(file.lines) lines; a \(role) has \(budget).") }
            }
        }
        let app = files(in: sources.appendingPathComponent("something")).map(\.lines).reduce(0, +)
        if app > Budget.app { problems.append("The Mac app has \(app) lines; its budget is \(Budget.app).") }
        return problems
    }
}

@Suite struct BudgetTests {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func theSourcesHoldTheirBudgets() {
        // A renamed or misspelled folder would hold its budget with zero lines: each one must be there.
        #expect(Budget.agentTargets(under: root) == ["AgentACP", "AgentClaude", "AgentCodex", "AgentPi"])
        for target in ["SomethingCore", "SomethingAgents", "something"] + Budget.agentTargets(under: root) {
            #expect(!Budget.files(in: root.appendingPathComponent("Sources/\(target)")).isEmpty, "Sources/\(target) has no Swift file")
        }
        let problems = Budget.problems(under: root)
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test func filesInSubfoldersAreCounted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("budget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Sources/SomethingAgents/Readers")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try String(repeating: "let example = 1\n", count: 401).write(to: folder.appendingPathComponent("CodexReader.swift"),
                                                                     atomically: true, encoding: .utf8)
        #expect(Budget.files(in: root.appendingPathComponent("Sources/SomethingAgents")).map(\.name) == ["Readers/CodexReader.swift"])
        #expect(Budget.problems(under: root) == ["Readers/CodexReader.swift has 401 lines; a shared file has 400."])
    }

    /// The host holds 2,600 lines in all, whatever each of its files holds.
    @Test func theHostFailsOneLineOverInAll() throws {
        for (extra, expected) in [(0, [String]()), (1, ["SomethingAgents has 2801 lines; its budget is 2800."])] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("budget-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let folder = root.appendingPathComponent("Sources/SomethingAgents")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (index, count) in [400, 400, 400, 400, 400, 400, 400, extra].enumerated() {
                try String(repeating: "let example = 1\n", count: count).write(to: folder.appendingPathComponent("File\(index).swift"),
                                                                              atomically: true, encoding: .utf8)
            }
            #expect(Budget.problems(under: root) == expected, "\(2_800 + extra) lines")
        }
    }

    @Test func linesAreCountedAsWcCountsThem() {
        #expect(Budget.lines("") == 0)
        #expect(Budget.lines("one\ntwo\n") == 2)
        #expect(Budget.lines("one\n\n// two") == 3)
    }

    /// Invented sources, one line over each budget, in a temporary folder: each one is caught, and only it.
    @Test func eachBudgetFailsOneLineOver() throws {
        let cases: [(folder: String, name: String, lines: Int, problem: String)] = [
            ("SomethingAgents", "Driver.swift", 401, "Driver.swift has 401 lines; a shared file has 400."),
            ("SomethingAgents", "Codex.swift", 401, "Codex.swift has 401 lines; a shared file has 400."),
            ("SomethingAgents", "Tail.swift", 401, "Tail.swift has 401 lines; a shared file has 400."),
            ("SomethingCore", "Contract.swift", 1_801, "SomethingCore has 1801 lines; its budget is 1800."),
            ("something", "App.swift", 5_501, "The Mac app has 5501 lines; its budget is 5500."),
            ("AgentClaude", "ClaudeDriver.swift", 601, "AgentClaude/ClaudeDriver.swift has 601 lines; a driver has 600."),
            ("AgentPi", "PiReader.swift", 401, "AgentPi/PiReader.swift has 401 lines; a file has 400."),
        ]
        for item in cases {
            for (count, expected) in [(item.lines - 1, [String]()), (item.lines, [item.problem])] {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("budget-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: root) }
                let folder = root.appendingPathComponent("Sources/\(item.folder)")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let text = String(repeating: "let example = 1\n", count: count)
                try text.write(to: folder.appendingPathComponent(item.name), atomically: true, encoding: .utf8)
                #expect(Budget.problems(under: root) == expected, "\(item.name) with \(count) lines")
            }
        }
    }
}
