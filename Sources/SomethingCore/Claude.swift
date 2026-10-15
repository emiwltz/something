// Claude Code, launched by something through its official channel: `claude -p` with JSON lines
// in and out (the channel Anthropic's SDKs use). One program per conversation.
import Foundation

public enum ClaudeStream {
    /// Folds one event of Claude Code's output into what is known of the agent.
    /// Events it does not know are ignored: a newer Claude must not break an older something.
    public static func apply(_ event: [String: Any], to agent: inout Agent) {
        switch event["type"] as? String {
        case "system" where event["subtype"] as? String == "init":
            agent.model = event["model"] as? String
            agent.mode = event["permissionMode"] as? String
            if agent.status == nil { agent.status = "idle" }
        case "assistant":
            let message = event["message"] as? [String: Any]
            let blocks = message?["content"] as? [[String: Any]] ?? []
            let text = blocks.filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }.joined(separator: "\n")
            // Claude Code writes its own failures (a refused key, a reached limit) as a message from
            // a "<synthetic>" model. That is an error, not the agent speaking, and not its model.
            if message?["model"] as? String == "<synthetic>" {
                agent.error = text.isEmpty ? "Claude Code could not answer." : text
                return
            }
            if !text.isEmpty { agent.messages.append(Message(from: "agent", text: text)) }
            if let model = message?["model"] as? String { agent.model = model }
        case "control_request":
            // Claude asks before using a tool, unless its own mode already allows it: something shows
            // only what Claude asks, so the person's mode is respected as it is.
            guard let id = event["request_id"] as? String,
                  let request = event["request"] as? [String: Any],
                  request["subtype"] as? String == "can_use_tool" else { return }
            let suggestions = request["permission_suggestions"] as? [[String: Any]] ?? []
            agent.request = PermissionRequest(
                id: id,
                tool: (request["display_name"] as? String) ?? (request["tool_name"] as? String) ?? "a tool",
                about: request["description"] as? String,
                always: describe(suggestions))
            agent.status = "waiting"
        case "control_cancel_request":
            if agent.request?.id == event["request_id"] as? String {
                agent.request = nil
                agent.status = "working"
            }
        case "result":
            // The end of a turn is the agent's own signal, never a silence.
            agent.status = "idle"
            if event["is_error"] as? Bool == true {
                agent.error = (event["result"] as? String) ?? "Claude Code ended its turn with an error."
            }
        default:
            break
        }
    }

    /// Claude's own offer for "always", in words; nil when it offers none.
    static func describe(_ suggestions: [[String: Any]]) -> String? {
        let parts = suggestions.map { suggestion -> String in
            switch suggestion["type"] as? String {
            case "setMode": return "switch to mode \"\(suggestion["mode"] as? String ?? "?")\" for this conversation"
            case "addRules": return "always allow this here"
            default: return suggestion["type"] as? String ?? "?"
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", and ")
    }

    /// The line that answers a `can_use_tool` request. `request` is the request as Claude sent it:
    /// allowing passes its input back unchanged, and "always" passes back Claude's own suggestions.
    public static func permissionLine(id: String, request: [String: Any], answer: PermissionAnswer) -> [String: Any] {
        var response: [String: Any]
        switch answer {
        case .deny:
            response = ["behavior": "deny", "message": "The person refused this in something."]
        case .once, .always:
            response = ["behavior": "allow", "updatedInput": request["input"] as? [String: Any] ?? [:]]
            if answer == .always, let suggestions = request["permission_suggestions"] as? [[String: Any]] {
                response["updatedPermissions"] = suggestions
            }
        }
        return ["type": "control_response", "response": ["subtype": "success", "request_id": id, "response": response]]
    }

    /// The line to write on Claude Code's input for one message from the person.
    public static func userLine(_ text: String) -> [String: Any] {
        ["type": "user", "message": ["role": "user", "content": text]]
    }
}

/// One Claude Code conversation, owned by something.
public final class ClaudeSession: AgentProcess {
    /// Removed from the environment Claude Code gets. A key left in a shell profile overrides the Claude
    /// subscription the person signed in with, and a dead one makes every message fail.
    public static let credentials: Set<String> = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"]

    public init(id: String, folder: URL) {
        // `--permission-prompt-tool stdio` makes Claude send its permission requests on this channel
        // instead of refusing them; the SDKs pass it, the CLI's help does not list it.
        super.init(agent: Agent(id: id, name: folder.lastPathComponent, harness: "claude", folder: folder.path),
                   arguments: ["claude", "-p", "--input-format", "stream-json", "--output-format", "stream-json",
                               "--verbose", "--permission-prompt-tool", "stdio"],
                   removing: ClaudeSession.credentials)
    }

    public override func received(_ event: [String: Any]) {
        if event["type"] as? String == "control_request", let id = event["request_id"] as? String,
           let request = event["request"] as? [String: Any] {
            keep(request, for: id)
        }
        update { ClaudeStream.apply(event, to: &$0) }
    }

    public override func send(_ text: String) throws {
        guard isRunning else { throw BridgeError("This Claude Code has stopped. Launch a new one.") }
        update {
            $0.messages.append(Message(from: "you", text: text))
            $0.status = "working"
            $0.error = nil
        }
        write(ClaudeStream.userLine(text))
    }

    public override func answer(_ id: String, _ answer: PermissionAnswer) throws {
        guard let request = take(id) as? [String: Any], isRunning else {
            throw BridgeError("This request was already answered or withdrawn.")
        }
        write(ClaudeStream.permissionLine(id: id, request: request, answer: answer))
        update {
            if $0.request?.id == id { $0.request = nil }
            $0.status = "working"
            if answer == .always {
                let suggestions = request["permission_suggestions"] as? [[String: Any]] ?? []
                if let mode = suggestions.first(where: { $0["type"] as? String == "setMode" })?["mode"] as? String {
                    $0.mode = mode
                }
            }
        }
    }
}
