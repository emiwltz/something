// The tables computed from the agents' descriptors (Extension.swift) against the literal tables of 0.2, kept here
// only: moving them into descriptors changed no value.
import Foundation
import Testing
@testable import SomethingAgents

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
        #expect(Engine.asksAsMuch == ["claude": ["default", "plan"], "codex": ["on-request", "untrusted"], "opencode": ["build", "plan"]])
        #expect(Watch.resumable == ["claude", "codex"])
        #expect(OtherReader.names == ["gemini", "amp", "qwen", "goose", "crush", "cursor-agent", "droid", "copilot", "auggie"])
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
}
