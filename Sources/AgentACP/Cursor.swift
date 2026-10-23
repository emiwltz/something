// Cursor: what something knows of its CLI, cursor-agent. It is seen by its process: its conversations are in files
// whose shape Cursor documents nowhere (~/.cursor), so no reader of them. It is not launched yet: driven over the Agent
// Client Protocol with the profile here, it works and builds a space, but it asks the person before each of
// something's own tools, which only a settings file of its own could allow (2026.10.19); an agent that
// cannot build without such asks is not offered.
import SomethingAgents
import SomethingCore

extension AgentDescriptor {
    /// Seen while cursor-agent runs, in its folder; Cursor's installer links it as agent too.
    package static let cursor = AgentDescriptor(kind: "cursor", name: "Cursor",
                                                reader: { _ in OtherReader(kind: "cursor", names: ["cursor-agent", "agent"]) },
                                                unavailable: "Cursor asks you before each of something's own tools, so something only sees cursor-agent for now.")
}

extension ACPProfile {
    /// `cursor-agent acp` (2026.10.19): each launch its own program, holding one session. Signed in with
    /// `cursor-agent login`, it needs no `authenticate`. Its model and mode are config options; its effort is part of
    /// the model's name, so none is offered on its own. Its tool calls are titled with their input (a command, a path),
    /// so a tool goes by its kind; an MCP server's tool is first "MCP: tool", then named with its server, its name and
    /// its arguments in a later update. It asks without the call's input, which the driver knows from the updates.
    /// Launching it would also need its program's name: `cursor` is Cursor's editor.
    static let cursor = ACPProfile(
        kind: "cursor", name: "Cursor", tested: "2026.10.19-6bbf2c4", arguments: ["acp"], signIn: "cursor-agent login",
        modes: [Option(value: "agent", label: "Agent"), Option(value: "plan", label: "Plan"), Option(value: "ask", label: "Ask")],
        named: { update in
            let input = update["rawInput"] as? [String: Any]
            if input?["providerIdentifier"] as? String == "something", let tool = input?["toolName"] as? String {
                return (tool, input?["args"] ?? [String: Any]())
            }
            return (update["kind"] as? String).map { ($0, input) }
        })
}
