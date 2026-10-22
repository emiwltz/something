// OpenCode: what something knows of it. It is driven over the Agent Client Protocol (ACPDriver) and read from its
// database (OpenCodeReader), the other files of this target.
import SomethingAgents

extension AgentDescriptor {
    /// Modes (2.0.20): a mode is an agent; build and plan ask as the person's settings say, and only `--auto`, which
    /// something never passes, asks less. Its tools are the kinds of the Agent Client Protocol.
    package static let opencode = AgentDescriptor(
        kind: "opencode", name: "OpenCode", install: "brew install opencode", homeFolders: [".opencode/bin"],
        asksAsMuch: ["build", "plan"], driving: .opencode, reader: { OpenCodeReader(environment: $0) }, builder: Builder(),
        tools: ["execute": .command, "edit": .file, "delete": .file, "move": .file])
}
