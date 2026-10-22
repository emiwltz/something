// Extensions.swift is the app's one list of agents: the host's descriptors, in their order, and the only file of the
// app that names one. What the windows take from the descriptors gives the words of 0.2.
import Foundation
import Testing
@testable import SomethingAgents
@testable import something

@Suite struct ExtensionsTests {
    @Test func theAppRegistersTheAgentsTheHostDescribes() {
        // The programs, the watch and the test guard still read the host's own list until each agent is an extension.
        #expect(Registry.app.agents.map(\.kind) == AgentDescriptor.all.map(\.kind))
        #expect(Registry.app.kinds.launchable == ["claude", "codex", "opencode", "pi"] && Registry.app.kinds.readOnly == ["omp"])
        #expect(Registry.app.builders.map(\.kind) == ["claude", "codex", "opencode", "pi"], "0.2's builders, in 0.2's order")
        #expect(InstallList.builders.map(\.name) == ["Claude Code", "Codex", "OpenCode", "pi"])
        #expect(InstallList.builders.map(\.command) == ["brew install --cask claude-code", "brew install --cask codex", "brew install opencode",
                                                         "npm install -g --ignore-scripts @earendil-works/pi-coding-agent"])
        #expect(Registry.app.agents.filter(\.neverAsks).map(\.kind) == ["pi"])
        // Only Claude Code's driver reports a refused sign-in (its detail.apiRetry).
        #expect(Registry.app.agents.map { $0.refusesSignIn(status: 401, error: nil) } == [true, false, false, false, false])
        #expect(Registry.app.agents.map { $0.refusesSignIn(status: nil, error: "authentication_failed") } == [true, false, false, false, false])
    }

    /// The sheet before a mode that lowers asking says what the mode lets the agent do, as 0.2 did for the modes it
    /// knew; any other mode, or another kind's, "asks you less".
    @Test func theModeWordsAreThoseOf0_2() {
        let cases = [("acceptEdits", "claude", "edits files without asking you"), ("auto", "claude", "decides by itself what to ask you"),
                     ("dontAsk", "claude", "never asks you, and does only what your settings already allow"),
                     ("never", "codex", "never asks you before it runs a command"), ("invented-agent", "opencode", "asks you less"),
                     ("default", "pi", "asks you less"), ("anything", "other", "asks you less")]
        for (mode, kind, words) in cases { #expect(Ask.words(forMode: mode, kind: kind) == words, "\(kind) \(mode)") }
        #expect(Ask.warning(for: "launch:claude") == nil && Ask.warning(for: "send:pi") == nil && Ask.warning(for: "state") == nil)
    }

    /// No other file of the app names an agent: its kind as a word, a driver, or a descriptor. Comments may.
    @Test func onlyExtensionsSwiftNamesAnAgent() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/something")
        let named = #/"(claude|codex|opencode|pi|omp)"|(Claude|Codex|ACP|Pi)Driver|AgentDescriptor|\.(claude|codex|opencode|pi|omp)\b/#
        let files = try FileManager.default.contentsOfDirectory(atPath: sources.path).filter { $0.hasSuffix(".swift") }
        #expect(files.count > 20, "the scan reads Sources/something")
        for name in files where name != "Extensions.swift" {
            let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            let code = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            #expect(code.filter { $0.contains(named) }.isEmpty, "\(name) names an agent")
        }
    }
}
