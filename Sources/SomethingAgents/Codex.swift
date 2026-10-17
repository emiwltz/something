// Codex, launched by something through its official channel: `codex app-server`, JSON-RPC in lines on
// its input and output. something starts its own private server, one per conversation, and never joins
// the server a Codex in a terminal may share.
import Foundation
import SomethingCore

public enum CodexStream {
    /// The permission requests Codex sends, and how a person knows them.
    static let approvals = ["item/commandExecution/requestApproval": "a command",
                            "item/fileChange/requestApproval": "a file change",
                            "item/permissions/requestApproval": "more permissions"]

    /// Folds one notification or request from Codex into what is known of the agent.
    /// Messages it does not know are ignored: a newer Codex must not break an older something.
    public static func apply(_ message: [String: Any], to agent: inout Agent) {
        let params = message["params"] as? [String: Any] ?? [:]
        switch message["method"] as? String {
        case "turn/started":
            agent.status = "working"
        case "item/completed":
            let item = params["item"] as? [String: Any] ?? [:]
            if item["type"] as? String == "agentMessage", let text = item["text"] as? String, !text.isEmpty {
                agent.messages.append(Message(from: "agent", text: text))
            }
        case "turn/completed":
            // The end of a turn is the agent's own signal, never a silence.
            agent.status = "idle"
            agent.request = nil
            let turn = params["turn"] as? [String: Any] ?? [:]
            if turn["status"] as? String == "failed" {
                agent.error = ((turn["error"] as? [String: Any])?["message"] as? String) ?? "Codex ended its turn with an error."
            }
        case "error" where params["willRetry"] as? Bool != true:
            agent.error = ((params["error"] as? [String: Any])?["message"] as? String) ?? "Codex reported an error."
        case "serverRequest/resolved":
            if let id = params["requestId"], agent.request?.id == "\(id)" {
                agent.request = nil
                agent.status = "working"
            }
        case let method? where approvals[method] != nil:
            guard let id = message["id"] else { return }
            agent.request = PermissionRequest(
                id: "\(id)",
                tool: approvals[method]!,
                about: (params["command"] as? String) ?? (params["reason"] as? String))
            agent.status = "waiting"
        default:
            break
        }
    }

    /// Folds the answer to `thread/start` into the agent and returns the thread's id, or nil when there is none.
    public static func threadStarted(_ result: [String: Any], to agent: inout Agent) -> String? {
        agent.model = result["model"] as? String
        // Codex's mode is its approval policy: "untrusted", "on-request", "never", or a finer set of rules.
        agent.mode = (result["approvalPolicy"] as? String) ?? (result["approvalPolicy"] != nil ? "granular" : nil)
        agent.status = "idle"
        return (result["thread"] as? [String: Any])?["id"] as? String
    }

    /// Codex's word for the person's answer.
    public static func decision(_ answer: PermissionAnswer) -> String {
        switch answer {
        case .once: return "accept"
        case .deny: return "decline"
        }
    }

    /// The message that starts a turn with the person's text.
    public static func turnStart(id: Int, thread: String, text: String) -> [String: Any] {
        ["id": id, "method": "turn/start", "params": ["threadId": thread, "input": [["type": "text", "text": text]]]]
    }
}

/// One Codex conversation, owned by something.
public final class CodexSession: AgentProcess {
    private let threadOptions: [String: Any]
    private var thread: String?
    private var waiting: [String] = []
    private var nextId = 0
    private let lock = NSLock()

    /// `threadOptions` are added to `thread/start`; empty, Codex uses the person's own configuration.
    public init(id: String, folder: URL, threadOptions: [String: Any] = [:]) {
        self.threadOptions = threadOptions
        super.init(agent: Agent(id: id, name: folder.lastPathComponent, harness: "codex", folder: folder.path),
                   arguments: ["codex", "app-server"])
    }

    private func request(_ method: String, _ params: [String: Any]) {
        write(["id": newId(), "method": method, "params": params])
    }

    private func newId() -> Int {
        lock.lock()
        defer { lock.unlock() }
        nextId += 1
        return nextId
    }

    public override func started() {
        request("initialize", ["clientInfo": ["name": "something", "version": "0.1"]])
    }

    public override func received(_ message: [String: Any]) {
        let id = message["id"]
        if message["method"] == nil, let id = id as? Int {
            responded(id, message)
        } else if let method = message["method"] as? String, let id {
            if CodexStream.approvals[method] != nil {
                keep(id, for: "\(id)")
                update { CodexStream.apply(message, to: &$0) }
            } else {
                // A question something cannot show yet: say so, so that Codex does not wait forever.
                write(["id": id, "error": ["code": -32601, "message": "something cannot answer \(method) yet."]])
            }
        } else {
            update { CodexStream.apply(message, to: &$0) }
        }
    }

    private func responded(_ id: Int, _ message: [String: Any]) {
        if let error = message["error"] as? [String: Any] {
            update { $0.error = (error["message"] as? String) ?? "Codex refused a request." }
            return
        }
        let result = message["result"] as? [String: Any] ?? [:]
        if id == 1 {
            write(["method": "initialized"])
            var params = threadOptions
            params["cwd"] = agent.folder
            request("thread/start", params)
        } else if result["thread"] != nil {
            var started: String?
            update { started = CodexStream.threadStarted(result, to: &$0) }
            lock.lock()
            thread = started
            let queued = waiting
            waiting = []
            lock.unlock()
            queued.forEach { startTurn($0) }
        }
    }

    private func startTurn(_ text: String) {
        guard let thread else { return }
        write(CodexStream.turnStart(id: newId(), thread: thread, text: text))
    }

    public override func send(_ text: String) throws {
        guard isRunning else { throw BridgeError("This Codex has stopped. Launch a new one.") }
        update {
            $0.messages.append(Message(from: "you", text: text))
            $0.status = "working"
            $0.error = nil
        }
        lock.lock()
        let ready = thread != nil
        if !ready { waiting.append(text) }
        lock.unlock()
        if ready { startTurn(text) }
    }

    public override func answer(_ id: String, _ answer: PermissionAnswer) throws {
        guard let raw = take(id), isRunning else { throw BridgeError("This request was already answered or withdrawn.") }
        write(["id": raw, "result": ["decision": CodexStream.decision(answer)]])
        update {
            if $0.request?.id == id { $0.request = nil }
            $0.status = "working"
        }
    }
}
