// Extensions: the agents this build of something knows, the one place the app names them. Everything else in the app
// (the builders offered, the words of the windows, the checks of a space's rights and launches) asks this registry.
import AgentACP
import AgentAmp
import AgentClaude
import AgentCodex
import AgentPi
import SomethingAgents

extension Registry {
    /// In the order of the state's kinds; the builders are offered in the same order, by how much each asks before
    /// acting. Built once, at the first use. The app's windows read this value; the engine is given it too, for the
    /// host's own checks. The others are coding agents without an extension, seen from their process only.
    static let app = Registry([.claude, .codex, .opencode, .pi, .omp(reader: OMP.reader), .antigravity, .amp],
                              others: ["gemini", "qwen", "goose", "crush", "cursor-agent", "droid", "copilot", "auggie"])

    /// Answers `something hook permission`, which Claude Code's plan B runs for each request (PermissionSpool.swift).
    static func hook(_ words: [String]) -> Int32 { SpoolHook.main(words) }
}
