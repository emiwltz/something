// The tables computed from the agents' descriptors (Extension.swift) against the literal tables of 0.2, kept here
// only: moving them into descriptors changed no value. The same for what each driver said of itself in 0.2, now its
// kind's Driving.
import Foundation
import Testing
@testable import SomethingAgents
import SomethingCore

@Suite struct DescriptorsTests {
    @Test func theTablesAreThoseOf0_2() {
        #expect(Programs.kinds == ["claude", "codex", "opencode", "pi", "omp"])
        #expect(Programs.install == [
            "claude": "brew install --cask claude-code",
            "codex": "brew install --cask codex",
            "opencode": "brew install opencode",
            "pi": "npm install -g --ignore-scripts @earendil-works/pi-coding-agent",
        ])
        #expect(Programs.names == ["claude": "Claude Code", "codex": "Codex", "opencode": "OpenCode", "pi": "pi", "omp": "OMP"])
        #expect(Programs.runsOn == ["pi": "node"])
        #expect(Programs.homeFolders == [".local/bin", ".bun/bin", ".opencode/bin", ".volta/bin"])
        #expect(Registry.described.asksAsMuch == ["claude": ["default", "plan"], "codex": ["on-request", "untrusted"], "opencode": ["build", "plan"]])
        #expect(Watch.resumable == ["claude", "codex"])
        #expect(OtherReader.names == ["gemini", "amp", "qwen", "goose", "crush", "cursor-agent", "droid", "copilot", "auggie"])
        // What the core received as its contract 1 list in 0.2: the kinds registered are exactly that floor today.
        #expect(Registry.described.kinds.launchable == ["claude", "codex", "opencode", "pi"] && Registry.described.kinds.readOnly == ["omp"])
    }

    @Test func theSpecialCasesAreThoseOf0_2() {
        // Only Claude refuses another app's copy (ProgramsTests shows both copies refused), only pi has a bundled
        // folder, only Codex continues an unknown holder.
        #expect(AgentDescriptor.all.filter { !$0.refusedCopies.isEmpty }.map(\.kind) == ["claude"])
        #expect(AgentDescriptor.all.filter { $0.bundled != nil }.map(\.kind) == ["pi"])
        #expect(AgentDescriptor.all.filter { $0.resume == .unlessKnownHeld }.map(\.kind) == ["codex"])
        #expect(Watch.continuable("codex", alive: nil, pid: nil).0)
        #expect(!Watch.continuable("claude", alive: nil, pid: nil).0)
        #expect(AgentDescriptor.of("other") == nil && Programs.name(of: "other") == "other")
        // A process another agent's own reader claims is never also an `other` agent.
        #expect(OtherReader.names.isDisjoint(with: AgentDescriptor.all.map(\.kind)))
    }

    @Test func whatEachDriverCanDoIsThatOf0_2() {
        // Each Driving names the kind of the descriptor that holds it.
        #expect(AgentDescriptor.all.allSatisfy { $0.driving == nil || $0.driving?.kind == $0.kind })
        #expect(Registry.described.launchable.mapValues(\.tested) == ["claude": "2.1.296", "codex": "0.163.0", "opencode": "2.0.20", "pi": "1.0.0"])
        #expect(Registry.described.launchable.mapValues(\.limits) == [
            "claude": [:], "codex": [:],
            "opencode": ["steer": "OpenCode cannot take a message during a turn; send it with when: \"next\"."],
            "pi": ["mode": "pi has no permission modes: it runs commands and edits files without asking first."],
        ])
        #expect(Registry.described.launchable.mapValues { $0.modes.map(\.value) } == [
            "claude": ["default", "acceptEdits", "plan", "auto", "dontAsk"], "codex": ["on-request", "untrusted", "never"],
            "opencode": ["build", "plan"], "pi": [],
        ])
        #expect(Registry.described.launchable.mapValues { $0.modes.map(\.label) } == [
            "claude": ["Ask before acting", "Accept edits", "Plan only", "Auto (Claude decides what is safe)", "Never ask (refuse what is not allowed)"],
            "codex": ["Ask when needed", "Ask before most commands", "Never ask (refuse what is not allowed)"],
            "opencode": ["Build", "Plan"], "pi": [],
        ])
        // In 0.2 only OpenCode's modes were not its driver's list alone (Engine.lowersAsking cast to ACPDriver).
        #expect(Registry.described.launchable.filter(\.value.listsMoreModes).keys.sorted() == ["opencode"])
        #expect(Registry.described.launchable.filter(\.value.effortOnlyWhenOffered).keys.sorted() == ["claude", "codex", "opencode"])
        #expect(Registry.described.launchable.filter(\.value.picksThread).keys.sorted() == ["claude"])
        // Each kind's factory makes its own driver.
        let made = Registry.described.launchable.mapValues { driving in
            String(describing: type(of: driving.driver(Launch(agent: "x-1", folder: "/Users/example/shop"), { _ in }, { _ in }, { "" })))
        }
        #expect(made == ["claude": "ClaudeDriver", "codex": "CodexDriver", "opencode": "ACPDriver", "pi": "PiDriver"])
    }

    /// The engine acts on drivers through their hooks only: no file of it names a driver, Claude's spool or one kind.
    @Test func theEngineNamesNoDriver() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/SomethingAgents")
        let named = #/(Claude|Codex|ACP|Pi)Driver|PermissionSpool|Spool\.|AgentDescriptor\.(claude|codex|opencode|pi)\b/#
        for name in ["Engine.swift", "Join.swift", "Driver.swift"] {
            let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            // Comments may say which kind a hook serves; only code is checked.
            let code = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            #expect(code.filter { $0.contains(named) }.isEmpty, "\(name) names a driver")
        }
    }

    /// A forced plan B is for a kind that has one: any other is refused before anything starts.
    @MainActor @Test func aPlanBItsKindDoesNotHaveIsRefused() {
        let engine = Engine.throwaway(["HOME": "/Users/example", "PATH": "/nowhere"])
        #expect(throws: CodedError("BAD_PARAMS", "codex has no plan B.")) {
            try engine.launch("codex", folder: "/Users/example/shop", model: nil, mode: nil, effort: nil, planB: true)
        }
        guard case .failure(let wrong) = DeveloperTrial.parse(["try", "codex", "--plan-b"], registry: .described) else { Issue.record("codex --plan-b was taken"); return }
        #expect(wrong.message == "something try: --plan-b is for claude only.", "the 0.2 wording stays")
    }
}
