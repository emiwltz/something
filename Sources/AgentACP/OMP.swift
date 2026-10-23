// OMP (oh-my-pi): what something knows of driving it. It is driven over the Agent Client Protocol (`omp acp`, with
// the profile here) and read from its logs by AgentPi's OMPReader, which this target cannot import: the app joins
// the two (Extensions.swift).
import Foundation
import SomethingAgents
import SomethingCore

extension AgentDescriptor {
    /// OMP, read by `reader`. The install sentence is the first of OMP's README (github.com/can1357/oh-my-pi, read again
    /// 23 October 2026, which also gives brew, bun and nix); it puts `omp` in ~/.local/bin.
    /// OMP asks as its own setting tools.approvalMode says, which something never passes: its default, "yolo", asks
    /// nothing (18.8.6). Its modes, default and plan, ask the same. As a builder, it is lent something's commands over MCP.
    package static func omp(reader: @escaping @Sendable ([String: String]) -> any Reader) -> AgentDescriptor {
        AgentDescriptor(kind: "omp", name: "OMP", install: "curl -fsSL https://omp.sh/install | sh", asksAsMuch: ["default", "plan"],
                        driving: ACPProfile.omp.driving, reader: reader, builder: Builder(lent: LentTool.all),
                        asksNothingByDefault: true, tools: ACPProfile.tools)
    }
}

extension ACPProfile {
    /// `omp acp` (18.8.6): each launch its own program, holding one session, which it writes to its log as the
    /// terminal's OMP does. It signs in with the providers already set up in ~/.omp, so it needs no `authenticate`,
    /// and starts on the model and thinking level of the person's own settings. Its tool calls are titled by its
    /// model, in a sentence, so a tool goes by its kind; an MCP server's tool is called through the path
    /// xd://mcp__<server>_<tool> with its arguments as a JSON string (OMP drops a tool's own prefix that repeats the
    /// server's name: something's server "something" lends something_check as xd://mcp__something_check).
    static let omp = ACPProfile(
        kind: "omp", name: "OMP", tested: "18.8.6", arguments: ["acp"], signIn: "omp login",
        modes: [Option(value: "default", label: "Default"), Option(value: "plan", label: "Plan")],
        named: { update in
            guard let kind = update["kind"] as? String else { return nil }
            let input = update["rawInput"] as? [String: Any], path = input?["path"] as? String ?? ""
            guard kind == "execute", path.hasPrefix("xd://mcp__") else { return (kind, input) }
            let arguments = (input?["content"] as? String).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) }
            return (String(path.dropFirst("xd://mcp__".count)), arguments ?? [String: Any]())
        })
}
