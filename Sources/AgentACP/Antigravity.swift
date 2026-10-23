// Antigravity (Google): what something knows of it. Its CLI, agy, is seen by its process only. Its official ACP server
// (agy_acp_server.par, a separate download) is not launched yet: it keeps a Google sign-in of its own, apart from the
// CLI's, and signing it in opens a browser page, which is the person's gesture (trial C2, server 1.4.1, 23 Oct 2026).
import SomethingAgents

extension AgentDescriptor {
    /// Seen while `agy` runs, in its folder. Its conversations are in no file something reads: the CLI 1.4.5 keeps
    /// them under ~/.gemini/antigravity-cli in a shape Google documents nowhere.
    package static let antigravity = AgentDescriptor(kind: "antigravity", name: "Antigravity",
                                                     reader: { _ in OtherReader(kind: "antigravity", names: ["agy"]) })
}
