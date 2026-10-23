// Amp: what something knows of it. Its driver (AmpDriver) is the other file of this target. Amp keeps its threads on
// its own servers: this build of it writes none to disk (V: ~/.local/share/amp/threads unchanged by four runs), so
// something sees an Amp started elsewhere by its process only.
import SomethingAgents

extension AgentDescriptor {
    /// The install sentence is Amp's own Homebrew tap (ampcode/homebrew-tap). Amp never asks the person: when
    /// something launches it, a tool its own settings would ask for is refused by Amp itself, and it has no mode
    /// something sets. As a builder, it is lent something's commands over MCP, which it calls from its code_exec tool.
    package static let amp = AgentDescriptor(kind: "amp", name: "Amp", install: "brew install ampcode/tap/ampcode", driving: .amp,
                                             reader: { _ in OtherReader(kind: "amp", names: ["amp"]) },
                                             builder: Builder(lent: LentTool.all), neverAsks: true)
}
