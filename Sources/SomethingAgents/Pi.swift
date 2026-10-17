// pi, launched by something through its official channel: `pi --mode rpc`, JSON lines in and out.
// One program per conversation. pi never asks permission, by design: it has no request to show.
import Foundation
import SomethingCore

public enum PiStream {
    /// Folds one event or response from pi into what is known of the agent.
    /// Events it does not know are ignored: a newer pi must not break an older something.
    public static func apply(_ event: [String: Any], to agent: inout V1Agent) {
        switch event["type"] as? String {
        case "response":
            if event["success"] as? Bool == false {
                agent.error = (event["error"] as? String) ?? "pi refused a command."
                if agent.status == "working" { agent.status = "idle" }
            }
            guard event["command"] as? String == "get_state", let data = event["data"] as? [String: Any] else { return }
            if let model = data["model"] as? [String: Any] { agent.model = name(provider: model["provider"], id: model["id"]) }
            if agent.status == nil { agent.status = (data["isStreaming"] as? Bool == true) ? "working" : "idle" }
        case "agent_start":
            agent.status = "working"
        case "message_end":
            let message = event["message"] as? [String: Any] ?? [:]
            guard message["role"] as? String == "assistant" else { return }
            if message["stopReason"] as? String == "error" {
                agent.error = (message["errorMessage"] as? String) ?? "pi could not answer."
                return
            }
            let blocks = message["content"] as? [[String: Any]] ?? []
            let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if !text.isEmpty { agent.messages.append(Message(from: "agent", text: text)) }
            if let model = name(provider: message["provider"], id: message["model"]) { agent.model = model }
        case "agent_settled":
            // pi's own signal that the turn and everything queued after it are over.
            agent.status = "idle"
        default:
            break
        }
    }

    static func name(provider: Any?, id: Any?) -> String? {
        guard let id = id as? String else { return nil }
        return (provider as? String).map { "\($0)/\(id)" } ?? id
    }

    /// The command for one message from the person: a prompt, or a follow-up when pi is still working.
    public static func messageCommand(_ text: String, whileWorking: Bool) -> [String: Any] {
        ["type": whileWorking ? "follow_up" : "prompt", "message": text]
    }
}

/// One pi conversation, owned by something.
public final class PiSession: AgentProcess {
    /// `model` is passed to pi for this conversation; nil, pi uses the person's configuration.
    public init(id: String, folder: URL, model: String? = nil) {
        super.init(agent: V1Agent(id: id, name: folder.lastPathComponent, harness: "pi", folder: folder.path),
                   arguments: ["pi", "--mode", "rpc"] + (model.map { ["--model", $0] } ?? []))
    }

    public override func started() {
        write(["type": "get_state"])
    }

    public override func received(_ event: [String: Any]) {
        update { PiStream.apply(event, to: &$0) }
        if event["type"] as? String == "agent_settled" { write(["type": "get_state"]) }
    }

    public override func send(_ text: String) throws {
        guard isRunning else { throw BridgeError("This pi has stopped. Launch a new one.") }
        let working = agent.status == "working"
        update {
            $0.messages.append(Message(from: "you", text: text))
            $0.status = "working"
            $0.error = nil
        }
        write(PiStream.messageCommand(text, whileWorking: working))
    }

    public override func answer(_ id: String, _ answer: PermissionAnswer) throws {
        throw BridgeError("pi does not ask permission.")
    }
}
