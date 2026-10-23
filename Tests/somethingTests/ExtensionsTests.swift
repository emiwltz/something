// Extensions.swift is the app's one list of agents: the Agent* targets' descriptors, in their order, and the only file
// of the app that names one. What the windows take from the descriptors gives the words of 0.2.
import Foundation
import Testing
@testable import SomethingAgents
@testable import something

@Suite struct ExtensionsTests {
    @Test func theAppRegistersTheAgentsOf0_2() {
        #expect(Registry.app.agents.map(\.kind) == ["claude", "codex", "opencode", "pi", "omp", "antigravity", "amp"])
        #expect(Registry.app.others.keys.sorted() == ["auggie", "copilot", "crush", "cursor-agent", "droid", "dsh", "gemini", "goose", "qwen", "zcode"])
        #expect(Registry.app.kinds.launchable == ["claude", "codex", "opencode", "pi", "omp", "amp"] && Registry.app.kinds.readOnly == ["antigravity"])
        #expect(Registry.app.builders.map(\.kind) == ["claude", "codex", "opencode", "pi", "omp", "amp"], "0.2's builders, in 0.2's order, then OMP and Amp")
        #expect(InstallList.builders.map(\.name) == ["Claude Code", "Codex", "OpenCode", "pi", "OMP", "Amp"])
        #expect(InstallList.builders.map(\.command) == ["brew install --cask claude-code", "brew install --cask codex", "brew install opencode",
                                                         "npm install -g --ignore-scripts @earendil-works/pi-coding-agent",
                                                         "curl -fsSL https://omp.sh/install | sh", "brew install ampcode/tap/ampcode"])
        #expect(Registry.app.agents.filter(\.neverAsks).map(\.kind) == ["pi", "amp"])
        #expect(Registry.app.agents.filter(\.asksNothingByDefault).map(\.kind) == ["omp"])
        // Only Claude Code's driver reports a refused sign-in (its detail.apiRetry).
        #expect(Registry.app.agents.map { $0.refusesSignIn(status: 401, error: nil) } == [true, false, false, false, false, false, false])
        #expect(Registry.app.agents.map { $0.refusesSignIn(status: nil, error: "authentication_failed") } == [true, false, false, false, false, false, false])
    }

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Emi's rule for 0.3: every agent the app drives builds spaces too, with a build recorded as the person's
    /// assistant, which SomethingAgentsTests' BuildersTests plays through its driver.
    @Test func everyDrivenAgentIsABuilderWithARecordedBuild() {
        for kind in Registry.app.kinds.launchable.sorted() {
            #expect(Registry.app.agent(kind)?.builder != nil, "\(kind) is driven but not a builder")
            let build = Self.root.appendingPathComponent("Tests/Exchanges/\(kind)/assistant-build.jsonl").path
            #expect(FileManager.default.fileExists(atPath: build), "\(kind) is driven without a recorded build")
        }
    }

    /// The README's table of agents is the registry's: each agent in its order, seen (by its files, or by its process
    /// only), driven or why not, and a builder; then, in one row, the agents seen by their process only.
    @Test func theReadmesAgentTableIsTheRegistrys() throws {
        let readme = try String(contentsOf: Self.root.appendingPathComponent("README.md"), encoding: .utf8).components(separatedBy: "\n")
        let rows = readme.drop { $0 != "| | seen | driven | builder |" }.dropFirst(2).prefix { $0.hasPrefix("|") }
            .map { $0.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) } }
        let described: [[String]] = Registry.app.agents.map { agent in
            let seen = agent.reader.map { $0([:]) is OtherReader ? "by its process" : "yes" } ?? "no"
            return [agent.name, seen, agent.driving == nil ? "no: " + (agent.unavailable ?? "") : "yes", agent.builder == nil ? "no" : "yes"]
        }
        #expect(Array(rows.dropLast()) == described)
        let others = try #require(rows.last)
        #expect(others.first?.components(separatedBy: ", ").sorted() == Registry.app.others.values.sorted())
        #expect(others.dropFirst() == ["by its process", "no: something has no extension for them.", "no"])
    }

    /// Every kind the app registers is in the published shape (share/contract/shape.json), as a key of the state's
    /// kinds and a word of an agent's kind: a kind added to the list fails here until the shape grows too.
    @Test func everyKindIsInTheShape() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let shape = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("share/contract/shape.json"))) as? [String: Any]
        let types = try #require(shape?["types"] as? [String: [String: [String]]])
        let kinds = Registry.app.agents.map(\.kind)
        #expect(Set(types["Kinds"]?.keys.map { $0 } ?? []) == Set(kinds))
        #expect(Set(kinds + ["other"]).isSubset(of: Set((types["Agent"]?["kind"] ?? []).map { String($0.dropFirst()) })))
    }

    /// The sheet before a mode that lowers asking says what the mode lets the agent do, as 0.2 did: by the mode's
    /// name, whatever the agent (an OpenCode agent named auto reads as Claude Code's auto); any other mode "asks you less".
    @Test func theModeWordsAreThoseOf0_2() {
        let cases = [("acceptEdits", "edits files without asking you"), ("auto", "decides by itself what to ask you"),
                     ("dontAsk", "never asks you, and does only what your settings already allow"),
                     ("never", "never asks you before it runs a command"), ("invented-agent", "asks you less"), ("default", "asks you less")]
        for (mode, words) in cases { #expect(Ask.words(forMode: mode) == words, "\(mode)") }
        // The rights sheet names every agent that may act without asking: pi and Amp never ask, OMP by its own default.
        #expect(Ask.warning(for: "launch") == "Some of them run commands and edit files without asking you first: pi, OMP by default, and Amp")
        #expect(Ask.warning(for: "launch:pi") == "pi runs commands and edits files without asking you first")
        #expect(Ask.warning(for: "launch:amp") == "Amp runs commands and edits files without asking you first")
        #expect(Ask.warning(for: "launch:omp") == "OMP, by default, runs commands and edits files without asking you first (its own setting)")
        #expect(Ask.warning(for: "launch:claude") == nil && Ask.warning(for: "send:pi") == nil && Ask.warning(for: "state") == nil)
    }

    /// No other file of the app names an agent: its kind as a word, a driver, a descriptor, a family's import, Claude's
    /// hook (SpoolHook), or its name in a sentence. Comments may. A `.pi` after a type (CGFloat.pi) is the number.
    @Test func onlyExtensionsSwiftNamesAnAgent() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/something")
        let names = Registry.app.agents.map(\.name).joined(separator: "|")
        let named = try Regex(#"(?:"(?:claude|codex|opencode|pi|omp)"|(?:Claude|Codex|ACP|Pi)Driver|AgentDescriptor|\bimport\s+Agent\w+|\bSpoolHook\b|(?:^|[^\w.])\.(?:claude|codex|opencode|pi|omp)\b"#
            + #"|"[^"]*\b(?:"# + names + #")\b[^"]*")"#)
        let files = try FileManager.default.contentsOfDirectory(atPath: sources.path).filter { $0.hasSuffix(".swift") }
        #expect(files.count > 20, "the scan reads Sources/something")
        for name in files where name != "Extensions.swift" {
            let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            let code = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            #expect(code.filter { $0.contains(named) }.isEmpty, "\(name) names an agent")
        }
    }
}
