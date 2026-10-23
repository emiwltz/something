// Budgets: the line counts AGENTS.md promises ("Minimal"), checked at each run of the suite. Every line counts,
// code, comments and blank lines alike, as `wc -l` counts them: a budget is about what a reader has to read.
import Foundation
import Testing

enum Budget {
    static let core = 1_850, host = 2_750, driver = 650, agentsShared = 450, app = 5_500, described = 40

    /// Whether a file describes an agent by data alone: it extends AgentDescriptor and gives it no driver.
    static func describesOnly(_ text: String) -> Bool { text.contains("extension AgentDescriptor") && !text.contains("driving:") }

    /// The lines of a text, counted as `wc -l` counts them, plus a last line without its newline.
    static func lines(_ text: String) -> Int {
        let newlines = text.utf8.filter { $0 == UInt8(ascii: "\n") }.count
        return newlines + (text.isEmpty || text.hasSuffix("\n") ? 0 : 1)
    }

    /// The Swift files under a folder, subfolders included, by path relative to it, with their line counts;
    /// empty when the folder does not exist (`theSourcesHoldTheirBudgets` checks that each one does).
    static func files(in folder: URL) -> [(name: String, lines: Int, text: String)] {
        let names = (FileManager.default.enumerator(atPath: folder.path)?.allObjects as? [String]) ?? []
        return names.filter { $0.hasSuffix(".swift") }.sorted().compactMap { name in
            guard let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) else { return nil }
            return (name, lines(text), text)
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
                if describesOnly(file.text), file.lines > described {
                    problems.append("\(target)/\(file.name) has \(file.lines) lines; an agent described by data has \(described).")
                }
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
        #expect(Budget.agentTargets(under: root) == ["AgentACP", "AgentAmp", "AgentClaude", "AgentCodex", "AgentPi"])
        for target in ["SomethingCore", "SomethingAgents", "something"] + Budget.agentTargets(under: root) {
            #expect(!Budget.files(in: root.appendingPathComponent("Sources/\(target)")).isEmpty, "Sources/\(target) has no Swift file")
        }
        // The rule finds the agents described by data, and none of the agents with a driver.
        let described = Budget.agentTargets(under: root).flatMap { target in
            Budget.files(in: root.appendingPathComponent("Sources/\(target)")).filter { Budget.describesOnly($0.text) }.map { "\(target)/\($0.name)" }
        }
        #expect(described.contains("AgentACP/Antigravity.swift") && !described.contains("AgentACP/OMP.swift"), "\(described)")
        let problems = Budget.problems(under: root)
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test func filesInSubfoldersAreCounted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("budget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Sources/SomethingAgents/Readers")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let over = Budget.agentsShared + 1
        try String(repeating: "let example = 1\n", count: over).write(to: folder.appendingPathComponent("Reader.swift"), atomically: true, encoding: .utf8)
        #expect(Budget.files(in: root.appendingPathComponent("Sources/SomethingAgents")).map(\.name) == ["Readers/Reader.swift"])
        #expect(Budget.problems(under: root) == ["Readers/Reader.swift has \(over) lines; a shared file has \(Budget.agentsShared)."])
    }

    /// The host holds its budget in all, whatever each of its files holds.
    @Test func theHostFailsOneLineOverInAll() throws {
        let files = Budget.host / Budget.agentsShared, rest = Budget.host % Budget.agentsShared
        for (extra, expected) in [(0, [String]()), (1, ["SomethingAgents has \(Budget.host + 1) lines; its budget is \(Budget.host)."])] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("budget-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let folder = root.appendingPathComponent("Sources/SomethingAgents")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (index, count) in (Array(repeating: Budget.agentsShared, count: files) + [rest + extra]).enumerated() {
                try String(repeating: "let example = 1\n", count: count).write(to: folder.appendingPathComponent("File\(index).swift"),
                                                                              atomically: true, encoding: .utf8)
            }
            #expect(Budget.problems(under: root) == expected, "\(Budget.host + extra) lines")
        }
    }

    @Test func linesAreCountedAsWcCountsThem() {
        #expect(Budget.lines("") == 0)
        #expect(Budget.lines("one\ntwo\n") == 2)
        #expect(Budget.lines("one\n\n// two") == 3)
    }

    /// Invented sources, one line over each budget, in a temporary folder: each one is caught, and only it.
    @Test func eachBudgetFailsOneLineOver() throws {
        let shared = Budget.agentsShared, over = Budget.agentsShared + 1
        let cases: [(folder: String, name: String, lines: Int, problem: String)] = [
            ("SomethingAgents", "Driver.swift", over, "Driver.swift has \(over) lines; a shared file has \(shared)."),
            ("SomethingAgents", "Tail.swift", over, "Tail.swift has \(over) lines; a shared file has \(shared)."),
            ("SomethingCore", "Contract.swift", Budget.core + 1, "SomethingCore has \(Budget.core + 1) lines; its budget is \(Budget.core)."),
            ("something", "App.swift", Budget.app + 1, "The Mac app has \(Budget.app + 1) lines; its budget is \(Budget.app)."),
            ("AgentClaude", "ClaudeDriver.swift", Budget.driver + 1,
             "AgentClaude/ClaudeDriver.swift has \(Budget.driver + 1) lines; a driver has \(Budget.driver)."),
            ("AgentPi", "PiReader.swift", over, "AgentPi/PiReader.swift has \(over) lines; a file has \(shared)."),
            ("AgentACP", "Antigravity.swift", Budget.described + 1,
             "AgentACP/Antigravity.swift has \(Budget.described + 1) lines; an agent described by data has \(Budget.described)."),
        ]
        for item in cases {
            for (count, expected) in [(item.lines - 1, [String]()), (item.lines, [item.problem])] {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("budget-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: root) }
                let folder = root.appendingPathComponent("Sources/\(item.folder)")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                // An agent described by data extends AgentDescriptor; the other invented files are any code.
                let first = item.problem.contains("described by data") ? "extension AgentDescriptor {}\n" : "let example = 1\n"
                let text = first + String(repeating: "let example = 1\n", count: count - 1)
                try text.write(to: folder.appendingPathComponent(item.name), atomically: true, encoding: .utf8)
                #expect(Budget.problems(under: root) == expected, "\(item.name) with \(count) lines")
            }
        }
    }
}
