// Claude Code: what something knows of it. Its driver (ClaudeDriver), its reader (ClaudeReader) and its plan B
// (PermissionSpool) are the other files of this target.
import SomethingAgents

extension AgentDescriptor {
    /// The Claude desktop app's own copy of `claude` is the app's, updated by the app, and may differ from the
    /// Claude Code the person installed. Modes (2.1.296): acceptEdits, auto, dontAsk and bypassPermissions lower
    /// asking; "default" is the name its channel reports (its help's "manual" is never offered: Driving.claude.modes
    /// leaves it out). As a builder, its rules pre-allow edits in the spaces folder and something's own commands.
    package static let claude = AgentDescriptor(
        kind: "claude", name: "Claude Code", install: "brew install --cask claude-code",
        refusedCopies: ["/Application Support/Claude/", "/Claude.app/"], asksAsMuch: ["default", "plan"], resume: .whenNoneHolds,
        driving: .claude, reader: { ClaudeReader(environment: $0) }, builder: Builder(preAllowed: true),
        tools: ["Bash": .command, "Edit": .file, "Write": .file, "MultiEdit": .file, "NotebookEdit": .file],
        modeWords: ["acceptEdits": "edits files without asking you", "auto": "decides by itself what to ask you",
                    "dontAsk": "never asks you, and does only what your settings already allow"])
}
