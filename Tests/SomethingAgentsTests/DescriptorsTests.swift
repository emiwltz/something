// The tables computed from the agents' descriptors (one file per Agent* target) against the literal tables of 0.2, kept here
// only: moving them into descriptors changed no value. The same for what each driver said of itself in 0.2, now its
// kind's Driving.
import Foundation
import Testing
@testable import SomethingAgents
@testable import AgentACP
@testable import AgentAmp
@testable import AgentClaude
@testable import AgentCodex
@testable import AgentPi
import SomethingCore

@Suite struct DescriptorsTests {
    @Test func theTablesAreThoseOf0_2() {
        let agents = Registry.described.agents
        #expect(agents.map(\.kind) == ["claude", "codex", "opencode", "pi", "omp", "antigravity", "amp"])
        #expect(Dictionary(uniqueKeysWithValues: agents.compactMap { agent in agent.install.map { (agent.kind, $0) } }) == [
            "claude": "brew install --cask claude-code",
            "codex": "brew install --cask codex",
            "opencode": "brew install opencode",
            "pi": "npm install -g --ignore-scripts @earendil-works/pi-coding-agent",
            "omp": "curl -fsSL https://omp.sh/install | sh",
            "amp": "brew install ampcode/tap/ampcode",
        ])
        #expect(Dictionary(uniqueKeysWithValues: agents.map { ($0.kind, $0.name) }) == ["claude": "Claude Code", "codex": "Codex", "opencode": "OpenCode", "pi": "pi", "omp": "OMP", "antigravity": "Antigravity", "amp": "Amp"])
        #expect(Dictionary(uniqueKeysWithValues: agents.compactMap { agent in agent.runsOn.map { (agent.kind, $0) } }) == ["pi": "node"])
        #expect(Programs(environment: [:], registry: .described).homeFolders == [".local/bin", ".bun/bin", ".opencode/bin", ".volta/bin"])
        #expect(Dictionary(uniqueKeysWithValues: Registry.described.agents.filter { !$0.asksAsMuch.isEmpty }.map { ($0.kind, $0.asksAsMuch) }) == ["claude": ["default", "plan"], "codex": ["on-request", "untrusted"], "opencode": ["build", "plan"], "omp": ["default", "plan"]])
        #expect(Registry.described.resumable == ["claude", "codex"])
        #expect(Registry.described.others.keys.sorted() == ["auggie", "copilot", "crush", "cursor-agent", "droid", "dsh", "gemini", "goose", "qwen", "zcode"])
        // The core's contract 1 list is the floor, omp launchable since 0.3; amp, added in 0.3, is launched beyond it,
        // and antigravity, added in 0.3, is only seen.
        #expect(Registry.described.kinds.launchable == ["claude", "codex", "opencode", "pi", "omp", "amp"] && Registry.described.kinds.readOnly == ["antigravity"])
    }

    @Test func theSpecialCasesAreThoseOf0_2() {
        // Only Claude refuses another app's copy (ProgramsTests shows both copies refused), only pi has a bundled
        // folder, only Codex continues an unknown holder.
        let agents = Registry.described.agents
        #expect(agents.filter { !$0.refusedCopies.isEmpty }.map(\.kind) == ["claude"])
        #expect(agents.filter { $0.bundled != nil }.map(\.kind) == ["pi"])
        #expect(agents.filter { $0.resume == .unlessKnownHeld }.map(\.kind) == ["codex"])
        #expect(Registry.described.continuable("codex", alive: nil, pid: nil).0)
        #expect(!Registry.described.continuable("claude", alive: nil, pid: nil).0)
        #expect(Registry.described.agent("other") == nil && Registry.described.name(of: "other") == "other")
        // A process another agent's own reader claims, or a described agent's program, is never also an `other` agent.
        let claimed = Set(agents.map(\.kind)).union(agents.compactMap { $0.reader?([:]).programs }.joined()).subtracting(Running.interpreters)
        #expect(Set(Registry.described.others.keys).isDisjoint(with: claimed) && claimed.contains("agy"), "\(claimed)")
        // The readers, in 0.2's order: one per agent, then the one for the others.
        #expect(Registry.described.readers([:]).map(\.kind) == ["claude", "codex", "opencode", "pi", "omp", "antigravity", "amp", "other"])
    }

    @Test func whatEachDriverCanDoIsThatOf0_2() {
        // Each Driving names the kind of the descriptor that holds it.
        #expect(Registry.described.agents.allSatisfy { $0.driving == nil || $0.driving?.kind == $0.kind })
        #expect(Registry.described.launchable.mapValues(\.tested) == ["claude": "2.1.296", "codex": "0.163.0", "opencode": "2.0.20", "pi": "1.0.0", "omp": "18.8.6", "amp": "0.0.1792656060"])
        #expect(Registry.described.launchable.mapValues(\.limits) == [
            "claude": [:], "codex": [:],
            "opencode": ["steer": "OpenCode cannot take a message during a turn; send it with when: \"next\"."],
            "pi": ["mode": "pi has no permission modes: it runs commands and edits files without asking first."],
            "omp": ["steer": "OMP cannot take a message during a turn; send it with when: \"next\"."],
            "amp": ["interrupt": "Amp can't pause mid-task: stopping it ends Amp.",
                    "model": "Amp picks its model by its own agent mode, which something does not set.",
                    "mode": "Amp picks its model by its own agent mode, which something does not set.",
                    "effort": "Amp picks its model by its own agent mode, which something does not set."],
        ])
        #expect(Registry.described.launchable.mapValues { $0.modes.map(\.value) } == [
            "claude": ["default", "acceptEdits", "plan", "auto", "dontAsk"], "codex": ["on-request", "untrusted", "never"],
            "opencode": ["build", "plan"], "pi": [], "omp": ["default", "plan"], "amp": [],
        ])
        #expect(Registry.described.launchable.mapValues { $0.modes.map(\.label) } == [
            "claude": ["Ask before acting", "Accept edits", "Plan only", "Auto (Claude decides what is safe)", "Never ask (refuse what is not allowed)"],
            "codex": ["Ask when needed", "Ask before most commands", "Never ask (refuse what is not allowed)"],
            "opencode": ["Build", "Plan"], "pi": [], "omp": ["Default", "Plan"], "amp": [],
        ])
        // In 0.2 only OpenCode's modes were not its driver's list alone (Engine.lowersAsking cast to ACPDriver).
        #expect(Registry.described.launchable.filter(\.value.listsMoreModes).keys.sorted() == ["opencode"])
        #expect(Registry.described.launchable.filter(\.value.effortOnlyWhenOffered).keys.sorted() == ["claude", "codex", "omp", "opencode"])
        #expect(Registry.described.launchable.filter(\.value.picksThread).keys.sorted() == ["claude"])
        // Each kind's factory makes its own driver.
        let made = Registry.described.launchable.mapValues { driving in
            String(describing: type(of: driving.driver(Launch(agent: "x-1", folder: "/Users/example/shop"), { _ in }, { _ in }, { "" })))
        }
        #expect(made == ["claude": "ClaudeDriver", "codex": "CodexDriver", "opencode": "ACPDriver", "pi": "PiDriver", "omp": "ACPDriver", "amp": "AmpDriver"])
    }

    /// The host knows the agents only through what it is given: no code line of Sources/SomethingAgents names one, by
    /// its kind, its name, its driver, its reader, Claude's spool or a descriptor. Comments may say which kind a hook
    /// serves. A `.pi` after a type (CGFloat.pi) is the number.
    @Test func theHostNamesNoAgent() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/SomethingAgents")
        let words = (Registry.described.agents.flatMap { [$0.kind, $0.name] } + Registry.described.others.keys + Registry.described.others.values).joined(separator: "|")
        let named = try Regex(#"(?:Claude|Codex|ACP|OpenCode|Pi|OMP)(?:Driver|Reader)|Spool|(?:^|[^\w.])\.(?:claude|codex|opencode|pi|omp)\b"#
            + #"|"[^"]*\b(?:"# + words + #")\b[^"]*""#)
        let files = try FileManager.default.contentsOfDirectory(atPath: sources.path).filter { $0.hasSuffix(".swift") }
        #expect(files.contains("Engine.swift") && files.contains("Watch.swift"), "the scan reads Sources/SomethingAgents")
        for name in files {
            let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            let code = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            #expect(code.filter { $0.contains(named) }.isEmpty, "\(name) names an agent")
        }
    }

    /// Each family imports the system, the core and the host, never another family (AGENTS.md, rule 7): SwiftPM
    /// does not check by default that an import is a declared dependency, so a stray one could build.
    @Test func aFamilyImportsNoOtherFamily() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources")
        let allowed: Set<String> = ["Foundation", "Darwin", "SQLite3", "SomethingCore", "SomethingAgents"]
        let imports = try Regex(#"^\s*(?:@\w+\s+)*(?:\w+\s+)?import\s+(?:(?:struct|class|enum|protocol|func|var|let|typealias)\s+)?(\w+)"#)
        let families = try FileManager.default.contentsOfDirectory(atPath: sources.path).filter { $0.hasPrefix("Agent") }
        #expect(families.count == 5, "the scan reads Sources/Agent*")
        for family in families {
            let folder = sources.appendingPathComponent(family)
            for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) where name.hasSuffix(".swift") {
                let text = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
                let modules = text.split(separator: "\n").compactMap { try? imports.firstMatch(in: $0)?.output[1].substring }.map(String.init)
                #expect(!modules.isEmpty && modules.allSatisfy(allowed.contains), "\(family)/\(name) imports \(modules)")
            }
        }
    }

    /// A forced plan B is for a kind that has one: any other is refused before anything starts.
    @MainActor @Test func aPlanBItsKindDoesNotHaveIsRefused() {
        let engine = Engine.throwaway(["HOME": "/Users/example", "PATH": "/nowhere"])
        #expect(throws: CodedError("BAD_PARAMS", "codex has no plan B.")) {
            try engine.launch("codex", folder: "/Users/example/shop", model: nil, mode: nil, effort: nil, planB: true)
        }
    }
}
