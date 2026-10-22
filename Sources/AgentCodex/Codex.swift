// Codex: what something knows of it. Its driver (CodexDriver) and its reader (CodexReader) are the other files of
// this target.
import SomethingAgents

extension AgentDescriptor {
    /// Codex refuses a second writer by itself, so a conversation whose holder is unknown is offered; Codex says so
    /// if its background service holds it. Modes (0.163): `--ask-for-approval` offers on-request and never;
    /// untrusted, which older versions offered, asks more. As a builder, its sandbox may write in the spaces folder,
    /// and something lends it its check, which the sandbox cannot run.
    package static let codex = AgentDescriptor(
        kind: "codex", name: "Codex", install: "brew install --cask codex", asksAsMuch: ["on-request", "untrusted"],
        resume: .unlessKnownHeld, driving: .codex, reader: { CodexReader(environment: $0) }, builder: Builder(preAllowed: true, lent: [.check]),
        tools: ["commandExecution": .command, "fileChange": .file, "permissions": .permissions],
        modeWords: ["never": "never asks you before it runs a command"])
}
