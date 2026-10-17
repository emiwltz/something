// ClaudeDriver: Claude Code launched by something, through `claude -p` with JSON lines in and out (stream-json), the
// channel Anthropic's SDKs use. It turns Claude's raw words into neutral events (design 3.2): its session state into
// turns, `can_use_tool` into a permission or, for AskUserQuestion, a question, `aborted_*` into an interruption. The
// channel is undocumented in places; what each choice rests on is said where it is made.
import Foundation
import SomethingCore

public final class ClaudeDriver: Driver {
    public static let kind = "claude"
    public static let tested = "2.1.296"
    /// Trial T-1 showed that Claude takes an effort (`--effort`, and `apply_flag_settings` with `effortLevel` during a
    /// session); it stays a limit until the guide and contract 1's table say Claude can, which is Emi's decision.
    public static let limits = ["effort": "something cannot change Claude Code's effort yet."]
    /// Removed from the environment Claude Code gets: a key left in a shell profile overrides the subscription the
    /// person signed in with, and a dead one makes every message fail.
    public static let credentials: Set<String> = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"]
    /// The permission modes a space may choose. bypassPermissions is never offered: it cannot be entered unless the
    /// launch allowed it, and something never allows it.
    public static let modes = [Option(value: "default", label: "Ask before acting"), Option(value: "acceptEdits", label: "Accept edits"),
                        Option(value: "plan", label: "Plan only"), Option(value: "auto", label: "Auto (Claude decides what is safe)"),
                        Option(value: "dontAsk", label: "Never ask (refuse what is not allowed)")]

    /// `--permission-prompt-tool stdio` sends permission requests on this channel instead of refusing them (the SDKs
    /// pass it; the help does not list it). The mode is always explicit: without it a stranger's settings pick one,
    /// possibly `auto`. The environment variable makes Claude say when a turn starts and ends; it is set for this
    /// launch only.
    public static func command(_ launch: Launch) -> Command {
        var arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                         "--permission-prompt-tool", "stdio", "--include-hook-events",
                         "--permission-mode", launch.mode ?? "default", "--session-id", launch.thread]
        if let model = launch.model { arguments += ["--model", model] }
        return Command(arguments: arguments, adding: ["CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS": "1"], removing: credentials)
    }

    private let launch: Launch
    private let write: (Data) throws -> Void
    private let emit: (AgentEvent) -> Void
    private let now: () -> String
    /// Open requests by the id something shows (the agent's id joined to Claude's, so two agents never share one).
    private var asks: [String: (claudeID: String, request: [String: Any], prompt: Prompt)] = [:]
    /// Tool items by Claude's tool_use id, kept to update when the tool ends or a decision is known.
    private var tools: [String: Item] = [:]
    private var decisions: [String: Decision] = [:]
    /// Control requests something sent and not yet answered, by request id: their subtype and the value asked.
    private var sent: [String: (subtype: String, value: String?)] = [:]
    private var count = 0
    private var turnOpen = false
    /// Whether Claude says when a turn starts and ends; until it does, `system/init` and `result` mark turns.
    private var statesSeen = false
    /// The outcome of the turn, from its `result`, until Claude says it is idle.
    private var outcome: Outcome?
    private var interrupting = false
    private var heard = false

    public init(_ launch: Launch, write: @escaping (Data) throws -> Void, emit: @escaping (AgentEvent) -> Void, now: @escaping () -> String) {
        (self.launch, self.write, self.emit, self.now) = (launch, write, emit, now)
    }

    /// `initialize` is optional, but its answer lists the models this account offers.
    public func begin() throws {
        emit(.options(options(models: nil)))
        try control("initialize", [:])
    }

    public func receive(_ line: Data) {
        guard let frame = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return }
        heard = true
        switch frame["type"] as? String {
        case "system": system(frame)
        case "assistant": assistant(frame)
        case "user": toolResults(frame)
        case "result": result(frame)
        case "control_request": request(frame)
        case "control_cancel_request":
            // Claude withdrew it (the turn was interrupted, a hook answered first): it must not be answered.
            guard let raw = frame["request_id"] as? String, asks.removeValue(forKey: id(raw)) != nil else { return }
            emit(.requestClosed(id: id(raw)))
        case "control_response": response(frame["response"] as? [String: Any] ?? [:])
        default: break   // a newer Claude's frames must not break an older something
        }
    }

    /// Priority "next": Claude reads the message after the running tool calls, in the same turn, or starts a turn
    /// with it. Never "now", which may interrupt the turn; never left out, since the default depends on a flag on
    /// Anthropic's side. `origin` human: an unattributed message fails Claude's own trust checks.
    public func deliver(_ text: String, steer: Bool) throws {
        // A message that starts a turn opens it here, so the person's words are the turn's first item; Claude's
        // own `running` then changes nothing.
        if !steer { turn(open: true) }
        try send(["type": "user", "message": ["role": "user", "content": text], "parent_tool_use_id": NSNull(),
                  "uuid": UUID().uuidString.lowercased(), "priority": "next", "origin": ["kind": "human"]])
        count += 1
        emit(.itemAppended(Item(id: "\(launch.thread)/person/\(count)", kind: "message", author: "person", text: text, at: now())))
    }

    /// `cancel_queued` drops the steered messages Claude still holds, as an interrupt empties something's own queue.
    public func interrupt() throws {
        interrupting = true
        try control("interrupt", ["cancel_queued": true])
    }

    /// A new mode applies at once; a new model from the next turn on.
    public func set(model: String?, mode: String?, effort: String?) throws -> String {
        if effort != nil { throw CodedError("NOT_SUPPORTED", ClaudeDriver.limits["effort"]!) }
        if let mode { try control("set_permission_mode", ["mode": mode], value: mode) }
        if let model { try control("set_model", ["model": model], value: model) }
        return model != nil && turnOpen ? "next-turn" : "now"
    }

    public func prompt(_ request: String) -> Prompt? { asks[request]?.prompt }

    /// Allow passes the input back unchanged, and never one of Claude's suggestions for a lasting rule. A question
    /// is answered by allowing the tool with the answers added to its input, keyed by each question's text.
    public func answer(_ request: String, _ answer: Answer) throws -> Bool {
        guard let ask = asks[request] else { return false }
        let input = ask.request["input"] as? [String: Any] ?? [:]
        let question = ask.prompt.request.kind == "question"
        var allowed: [String: Any]?   // nil: a deny, or an answer that does not fit the request
        switch (answer, question) {
        case (.once, false): allowed = input
        case (.choice(let chosen), true):
            // Several labels of one question are joined as Claude's own panel joins them.
            let texts = ask.prompt.questions.map(\.text)
            allowed = input.merging(["answers": Dictionary(zip(texts, chosen.map { $0.joined(separator: ", ") }),
                                                           uniquingKeysWith: { first, _ in first })]) { _, added in added }
        default: allowed = nil
        }
        let allow = allowed != nil
        let reply: [String: Any] = allowed.map { ["behavior": "allow", "updatedInput": $0] }
            ?? ["behavior": "deny", "message": question ? "The person chose not to answer." : "The person refused this in something."]
        try send(["type": "control_response", "response": ["subtype": "success", "request_id": ask.claudeID, "response": reply]])
        asks[request] = nil
        if let tool = ask.request["tool_use_id"] as? String { decide(tool, Decision(by: "person", outcome: allow ? "allowed" : "denied")) }
        emit(.requestClosed(id: request))
        return true
    }

    /// `end_session` aborts the turn, drops Claude's queue and exits 0: cleaner than a signal, which loses the turn.
    public var goodbye: Data? {
        try? JSONSerialization.data(withJSONObject: ["type": "control_request", "request_id": "something-end",
                                                     "request": ["subtype": "end_session"]], options: [.sortedKeys])
    }

    public func ended(code: Int32, errors: String) {
        guard code != 0 else { return emit(.stopped(nil)) }
        let lines = errors.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // A program that ends before its first line could not start: its first error line says why.
        if !heard { return emit(.stopped(AgentError(code: "LAUNCH_FAILED", message: lines.first.map { "Claude Code could not start: \($0)" }
            ?? "Claude Code stopped at once (code \(code))."))) }
        emit(.stopped(AgentError(code: "AGENT_ERROR", message: lines.last.map { "Claude Code ended: \($0)" } ?? "Claude Code ended (code \(code)).")))
    }

    // MARK: Claude's frames

    private func system(_ frame: [String: Any]) {
        switch frame["subtype"] as? String {
        case "init":
            emit(.reported(model: frame["model"] as? String, mode: frame["permissionMode"] as? String, effort: frame["effort"] as? String))
            if !statesSeen { turn(open: true) }
        case "session_state_changed":
            statesSeen = true
            // `requires_action` is a wait inside the turn: the request itself says it.
            switch frame["state"] as? String {
            case "running": turn(open: true)
            case "idle": turn(open: false)
            default: break
            }
        case "status":
            if let mode = frame["permissionMode"] as? String { emit(.reported(model: nil, mode: mode, effort: nil)) }
        case "permission_denied":
            // Denied without asking anyone: by a rule, by the mode (its classifier included) or by a hook.
            let by = ["rule": "rule", "mode": "mode", "classifier": "mode", "hook": "hook"][frame["decision_reason_type"] as? String ?? ""]
            if let tool = frame["tool_use_id"] as? String, let by { decide(tool, Decision(by: by, outcome: "denied")) }
        default: break
        }
    }

    private func assistant(_ frame: [String: Any]) {
        let message = frame["message"] as? [String: Any] ?? [:]
        let blocks = message["content"] as? [[String: Any]] ?? []
        // Claude Code writes its own failures (a refused key, a reached limit) as a message from a "<synthetic>"
        // model: an error, not the agent speaking, and not its model.
        if message["model"] as? String == "<synthetic>" {
            let text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
            return emit(.error(AgentError(code: "AGENT_ERROR", message: text.isEmpty ? "Claude Code could not answer." : text)))
        }
        if let model = message["model"] as? String { emit(.reported(model: model, mode: nil, effort: nil)) }
        // One frame per block, several frames per message: the frame's own uuid tells the items apart.
        let frameID = frame["uuid"] as? String ?? message["id"] as? String ?? "\(launch.thread)/\(count)"
        let sub = !(frame["parent_tool_use_id"] is NSNull) && frame["parent_tool_use_id"] != nil
        for (index, block) in blocks.enumerated() {
            let at = now()
            switch block["type"] as? String {
            case "text":
                emit(.itemAppended(Item(id: "\(frameID)/\(index)", kind: sub ? "subagent" : "message", author: "agent", text: block["text"] as? String ?? "", at: at)))
            case "thinking":
                guard let text = block["thinking"] as? String, !text.isEmpty else { continue }
                emit(.itemAppended(Item(id: "\(frameID)/\(index)", kind: sub ? "subagent" : "thought", author: "agent", text: text, at: at)))
            case "tool_use":
                let name = block["name"] as? String ?? "a tool", toolID = block["id"] as? String ?? "\(frameID)/\(index)"
                let item = Item(id: toolID, kind: sub ? "subagent" : "tool", author: "agent", text: ClaudeDriver.summary(block["input"]),
                                at: at, tool: Tool(name: name, status: "running"), decision: decisions[toolID])
                tools[toolID] = item
                emit(.itemAppended(item))
            default: break
            }
        }
    }

    private func toolResults(_ frame: [String: Any]) {
        let blocks = (frame["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
        for block in blocks where block["type"] as? String == "tool_result" {
            guard let toolID = block["tool_use_id"] as? String, var item = tools.removeValue(forKey: toolID) else { continue }
            item.tool?.status = block["is_error"] as? Bool == true ? "failed" : "done"
            item.decision = decisions.removeValue(forKey: toolID) ?? ClaudeDriver.decision(frame, toolID) ?? item.decision
            emit(.itemUpdated(item))
        }
    }

    /// The end of a turn's work. Claude says it is idle right after, which is the authoritative turn-over signal.
    private func result(_ frame: [String: Any]) {
        let reason = frame["terminal_reason"] as? String ?? ""
        if frame["subtype"] as? String == "success" && frame["is_error"] as? Bool != true {
            outcome = .done
        } else if interrupting || reason.hasPrefix("aborted") {
            outcome = .interrupted   // looks like an error, but the person asked for it
        } else {
            let errors = (frame["errors"] as? [String] ?? []).joined(separator: " ")
            let text = errors.isEmpty ? frame["result"] as? String ?? "" : errors
            outcome = .failed(AgentError(code: "AGENT_ERROR", message: text.isEmpty ? "Claude Code ended its turn with an error (\(reason))." : text))
        }
        if !statesSeen { turn(open: false) }
    }

    private func request(_ frame: [String: Any]) {
        guard let raw = frame["request_id"] as? String else { return }
        let request = frame["request"] as? [String: Any] ?? [:]
        guard request["subtype"] as? String == "can_use_tool" else {
            // Claude waits for every request it sends: one something never asked for gets a refusal, not silence.
            let subtype = request["subtype"] as? String ?? "?"
            try? send(["type": "control_response", "response": ["subtype": "error", "request_id": raw, "error": "something does not handle \(subtype)."]])
            return
        }
        let tool = request["tool_name"] as? String ?? "a tool", input = request["input"] as? [String: Any] ?? [:]
        let questions = tool == "AskUserQuestion" ? ClaudeDriver.questions(input) : []
        let shown = Request(id: id(raw), agent: launch.agent, kind: tool == "AskUserQuestion" ? "question" : "permission", tool: tool,
                            about: questions.first?.text ?? (input["command"] as? String) ?? (request["description"] as? String)
                                ?? ClaudeDriver.summary(input), at: now())
        asks[shown.id] = (raw, request, Prompt(request: shown, input: questions.isEmpty ? ClaudeDriver.shown(input) : nil, questions: questions))
        emit(.requestOpened(shown))
    }

    private func response(_ response: [String: Any]) {
        guard let raw = response["request_id"] as? String, let asked = sent.removeValue(forKey: raw) else { return }
        guard response["subtype"] as? String == "success" else {
            let words = response["error"] as? String ?? "Claude Code refused \(asked.subtype)."
            return emit(.error(AgentError(code: "AGENT_ERROR", message: words)))
        }
        let payload = response["response"] as? [String: Any] ?? [:]
        switch asked.subtype {
        case "initialize":
            emit(.options(options(models: payload["models"] as? [[String: Any]])))
            if let mode = payload["current_permission_mode"] as? String { emit(.reported(model: nil, mode: mode, effort: nil)) }
        // Claude's success is its word that the new value is in use; set_model answers with no payload.
        case "set_model": emit(.reported(model: asked.value, mode: nil, effort: nil))
        case "set_permission_mode": emit(.reported(model: nil, mode: payload["mode"] as? String ?? asked.value, effort: nil))
        default: break
        }
    }

    // MARK: Helpers

    private func turn(open: Bool) {
        guard open != turnOpen else { return }
        turnOpen = open
        if open { return emit(.turnStarted(id: nil)) }
        let ended = outcome ?? (interrupting ? .interrupted : .done)
        (outcome, interrupting) = (nil, false)
        emit(.turnEnded(ended))
    }

    private func decide(_ tool: String, _ decision: Decision) {
        decisions[tool] = decision
        guard var item = tools[tool] else { return }
        item.decision = decision
        tools[tool] = item
        emit(.itemUpdated(item))
    }

    private func id(_ claudeID: String) -> String { "\(launch.agent):\(claudeID)" }

    private func options(models: [[String: Any]]?) -> Options {
        var options = Options()
        options.mode = ClaudeDriver.modes
        options.model = models?.compactMap { model in
            (model["value"] as? String).map { Option(value: $0, label: model["displayName"] as? String ?? $0) }
        }
        return options
    }

    private func control(_ subtype: String, _ fields: [String: Any], value: String? = nil) throws {
        count += 1
        let id = "something-\(count)"
        sent[id] = (subtype, value)
        try send(["type": "control_request", "request_id": id, "request": fields.merging(["subtype": subtype]) { a, _ in a }])
    }

    /// Lines are built from structures, never by joining strings: one malformed line kills Claude.
    private func send(_ object: [String: Any]) throws {
        try write(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]))
    }

    /// Who let a tool run or stopped it, as the tool's result says (`tool_result_meta`, seen on 2.1.296): its own
    /// settings ("config") are a rule; the person's answers are known already, from `answer`.
    static func decision(_ frame: [String: Any], _ toolID: String) -> Decision? {
        let meta = (frame["tool_result_meta"] as? [[String: Any]] ?? []).first { $0["id"] as? String == toolID }
        guard let decided = meta?["permission_decision"] as? [String: Any],
              let outcome = ["accept": "allowed", "reject": "denied"][decided["decision"] as? String ?? ""],
              let by = ["config": "rule", "rule": "rule", "hook": "hook", "mode": "mode", "classifier": "mode"][decided["source"] as? String ?? ""]
        else { return nil }
        return Decision(by: by, outcome: outcome)
    }

    static func questions(_ input: [String: Any]) -> [Question] {
        (input["questions"] as? [[String: Any]] ?? []).compactMap { question in
            guard let text = question["question"] as? String else { return nil }
            let options = (question["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String }
            return Question(header: question["header"] as? String, text: text, options: options, multiple: question["multiSelect"] as? Bool == true)
        }
    }

    /// One line for a tool's input: the command, path or address it acts on, else its input as JSON.
    static func summary(_ input: Any?) -> String {
        let input = input as? [String: Any] ?? [:]
        for key in ["command", "file_path", "path", "pattern", "url", "query", "description", "prompt"] {
            if let value = input[key] as? String, !value.isEmpty { return value }
        }
        return shown(input) ?? ""
    }

    /// The input as Claude sent it, readable in a native window.
    static func shown(_ input: [String: Any]) -> String? {
        if let command = input["command"] as? String { return command }
        guard let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
