// Agents that speak ACP, the Agent Client Protocol: JSON-RPC in lines on the agent's input and output.
// One protocol for many agents; something uses it for OpenCode (`opencode acp`), and later for others.
import Foundation
import SomethingCore

public enum ACPStream {
    /// Folds one notification or request from an ACP agent into what is known of the agent.
    /// Messages it does not know are ignored: a newer agent must not break an older something.
    public static func apply(_ message: [String: Any], to agent: inout Agent) {
        let params = message["params"] as? [String: Any] ?? [:]
        switch message["method"] as? String {
        case "session/update":
            let update = params["update"] as? [String: Any] ?? [:]
            switch update["sessionUpdate"] as? String {
            case "agent_message_chunk":
                guard let text = (update["content"] as? [String: Any])?["text"] as? String, !text.isEmpty else { return }
                // A turn's text arrives in pieces; each turn starts with the person's message.
                if agent.messages.last?.from == "agent" {
                    agent.messages[agent.messages.count - 1].text += text
                } else {
                    agent.messages.append(Message(from: "agent", text: text))
                }
            case "current_mode_update":
                agent.mode = update["currentModeId"] as? String
            case "config_option_update":
                read(options: update["configOptions"] as? [[String: Any]], into: &agent)
            default:
                break
            }
        case "session/request_permission":
            guard let id = message["id"] else { return }
            let call = params["toolCall"] as? [String: Any] ?? [:]
            agent.request = PermissionRequest(
                id: "\(id)",
                tool: (call["kind"] as? String) ?? "a tool",
                about: call["title"] as? String)
            agent.status = "waiting"
        default:
            break
        }
    }

    /// Folds the answer to `session/new` into the agent and returns the session's id, or nil when there is none.
    public static func sessionStarted(_ result: [String: Any], to agent: inout Agent) -> String? {
        if let modes = result["modes"] as? [String: Any] { agent.mode = modes["currentModeId"] as? String }
        if let models = result["models"] as? [String: Any] { agent.model = models["currentModelId"] as? String }
        read(options: result["configOptions"] as? [[String: Any]], into: &agent)
        agent.status = "idle"
        return result["sessionId"] as? String
    }

    /// Model and mode, from the options an agent says it has (OpenCode: "model", "mode", "thought_level").
    static func read(options: [[String: Any]]?, into agent: inout Agent) {
        for option in options ?? [] {
            switch option["category"] as? String {
            case "model": agent.model = option["currentValue"] as? String
            case "mode": agent.mode = option["currentValue"] as? String
            default: break
            }
        }
    }

    /// The agent's own option for the person's answer, among those it offered; nil when it offered none.
    public static func option(for answer: PermissionAnswer, among options: [[String: Any]]) -> String? {
        let kinds: [String] = switch answer {
        case .once: ["allow_once"]
        case .deny: ["reject_once"]
        }
        for kind in kinds {
            if let id = options.first(where: { $0["kind"] as? String == kind })?["optionId"] as? String { return id }
        }
        return nil
    }
}

/// One conversation with an ACP agent, owned by something.
public final class ACPSession: AgentProcess {
    private let settings: [String: String]
    private var session: String?
    private var waiting: [String] = []
    private var nextId = 0
    private var prompts: Set<Int> = []
    private let lock = NSLock()

    /// `settings` are the agent's own options to set on the new session (for example "model");
    /// empty, the agent uses the person's configuration.
    public init(id: String, folder: URL, harness: String, arguments: [String],
                settings: [String: String] = [:], adding environment: [String: String] = [:]) {
        self.settings = settings
        super.init(agent: Agent(id: id, name: folder.lastPathComponent, harness: harness, folder: folder.path),
                   arguments: arguments, adding: environment)
    }

    @discardableResult
    private func request(_ method: String, _ params: [String: Any]) -> Int {
        lock.lock()
        nextId += 1
        let id = nextId
        lock.unlock()
        write(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        return id
    }

    public override func started() {
        // something reads no file and runs no terminal for the agent: it does both itself.
        request("initialize", ["protocolVersion": 1,
                               "clientCapabilities": ["fs": ["readTextFile": false, "writeTextFile": false], "terminal": false]])
    }

    public override func received(_ message: [String: Any]) {
        let id = message["id"]
        if message["method"] == nil, let id = id as? Int {
            responded(id, message)
        } else if let method = message["method"] as? String, let id {
            if method == "session/request_permission" {
                keep(["id": id, "options": (message["params"] as? [String: Any])?["options"] ?? []], for: "\(id)")
                update { ACPStream.apply(message, to: &$0) }
            } else {
                write(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "something cannot answer \(method) yet."]])
            }
        } else {
            update { ACPStream.apply(message, to: &$0) }
        }
    }

    private func responded(_ id: Int, _ message: [String: Any]) {
        lock.lock()
        let wasPrompt = prompts.remove(id) != nil
        lock.unlock()
        if let error = message["error"] as? [String: Any] {
            update {
                $0.error = (error["message"] as? String) ?? "\($0.harness) refused a request."
                if wasPrompt { $0.status = "idle"; $0.request = nil }
            }
            return
        }
        let result = message["result"] as? [String: Any] ?? [:]
        if id == 1 {
            request("session/new", ["cwd": agent.folder, "mcpServers": []])
        } else if wasPrompt {
            // The answer to session/prompt is the end of the turn: the agent's own signal.
            update { $0.status = "idle"; $0.request = nil }
        } else if result["sessionId"] != nil {
            var started: String?
            update { started = ACPStream.sessionStarted(result, to: &$0) }
            if let started {
                for (option, value) in settings {
                    request("session/set_config_option", ["sessionId": started, "configId": option, "value": value])
                    if option == "model" { update { $0.model = value } }
                }
            }
            lock.lock()
            session = started
            let queued = waiting
            waiting = []
            lock.unlock()
            queued.forEach { prompt($0) }
        }
    }

    private func prompt(_ text: String) {
        guard let session else { return }
        let id = request("session/prompt", ["sessionId": session, "prompt": [["type": "text", "text": text]]])
        lock.lock()
        prompts.insert(id)
        lock.unlock()
    }

    public override func send(_ text: String) throws {
        guard isRunning else { throw BridgeError("This \(agent.harness) has stopped. Launch a new one.") }
        update {
            $0.messages.append(Message(from: "you", text: text))
            $0.status = "working"
            $0.error = nil
        }
        lock.lock()
        let ready = session != nil
        if !ready { waiting.append(text) }
        lock.unlock()
        if ready { prompt(text) }
    }

    public override func answer(_ id: String, _ answer: PermissionAnswer) throws {
        guard let kept = take(id) as? [String: Any], let raw = kept["id"], isRunning else {
            throw BridgeError("This request was already answered or withdrawn.")
        }
        let options = kept["options"] as? [[String: Any]] ?? []
        let outcome: [String: Any] = ACPStream.option(for: answer, among: options)
            .map { ["outcome": "selected", "optionId": $0] } ?? ["outcome": "cancelled"]
        write(["jsonrpc": "2.0", "id": raw, "result": ["outcome": outcome]])
        update {
            if $0.request?.id == id { $0.request = nil }
            $0.status = "working"
        }
    }
}
