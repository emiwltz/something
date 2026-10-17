// ClaudeDriver: Claude Code launched by something, through `claude -p` with JSON lines in and out (stream-json), the
// channel Anthropic's SDKs use. It turns Claude's raw words into neutral events (design 3.2): its session state into
// turns, `can_use_tool` into a permission or, for AskUserQuestion, a question, `aborted_*` into an interruption. The
// channel is undocumented in places; what each choice rests on is said where it is made.
import Foundation
import SomethingCore

public final class ClaudeDriver: Driver {
    public static let kind = "claude"
    public static let tested = "2.1.296"
    /// None: trial T-1 showed that Claude takes an effort at launch (`--effort`) and during a session
    /// (`apply_flag_settings` with `effortLevel`, from its next request to the model).
    public static let limits: [String: String] = [:]
    /// Claude refuses an effort its model does not list: `can.effort` follows `options.effort`.
    public static let effortOnlyWhenOffered = true
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
    public static func command(_ launch: Launch) -> Command { command(launch, hook: nil) }

    /// Plan B, when `hook` is the command something answers Claude's hook with (`<abs>/something hook permission
    /// --spool <dir>`): no prompt tool, and a PermissionRequest hook, passed in `--settings` for this launch only,
    /// asks something through files instead (PermissionSpool.swift). Nothing is written in Claude's settings.
    static func command(_ launch: Launch, hook: [String]?) -> Command {
        var arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose"]
        if let hook {
            // Claude runs a hook's command through a shell: each word is quoted, so a space in a path stays inside it.
            let line = hook.map { "'" + $0.replacingOccurrences(of: "'", with: #"'\''"#) + "'" }.joined(separator: " ")
            let settings = ["hooks": ["PermissionRequest": [["matcher": "*", "hooks": [["type": "command", "command": line, "timeout": Spool.claudeTimeout]]]]]]
            let json = (try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
            arguments += ["--settings", String(decoding: json, as: UTF8.self)]
        } else {
            arguments += ["--permission-prompt-tool", "stdio"]
        }
        arguments += ["--include-hook-events", "--permission-mode", launch.mode ?? "default", "--session-id", launch.thread]
        // One argument, so a model is never read as an option.
        if let model = launch.model { arguments.append("--model=\(model)") }
        if let effort = launch.effort { arguments.append("--effort=\(effort)") }
        return Command(arguments: arguments, adding: ["CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS": "1"], removing: credentials)
    }

    private let launch: Launch
    private let write: (Data) throws -> Void
    private let emit: (AgentEvent) -> Void
    private let now: () -> String
    /// Open requests by the id something shows (the agent's id joined to Claude's, so two agents never share one).
    /// `hook` is true for a request that came through plan B's spool, whose claudeID is the spool's uuid.
    private var asks: [String: (claudeID: String, request: [String: Any], prompt: Prompt, hook: Bool)] = [:]
    /// Tool items by Claude's tool_use id, kept to update when the tool ends or a decision is known.
    private var tools: [String: Item] = [:]
    private var decisions: [String: Decision] = [:]
    /// Control requests something sent and not yet answered, by request id: their subtype and the value asked.
    private var sent: [String: (subtype: String, value: String?)] = [:]
    /// Messages something wrote and Claude has not finished with, by the uuid each line carries.
    private var messages: [String: (text: String, steer: Bool, started: Bool)] = [:]
    /// How many messages and control requests something wrote, for their ids.
    private var messagesWritten = 0, controlsWritten = 0
    private var turnOpen = false
    /// Whether Claude says when a turn starts and ends; until it does, `system/init` and `result` mark turns.
    private var statesSeen = false
    /// The outcome of the turn, from its `result`, until Claude says it is idle.
    private var outcome: Outcome?
    private var interrupting = false
    private var heard = false
    /// The models `initialize` listed, and the one in use: the one asked for (an alias such as "opus"), then the one
    /// Claude reports running (a model id, an entry's resolvedModel). The efforts offered are that model's; nil until
    /// one is known, since the person's own settings may pick a model other than "default".
    private var models: [[String: Any]]?
    private var model: String?
    /// Plan B's answer: writes a decision for a spool uuid. Set by the engine.
    var hookReply: ((String, [String: Any]) -> PermissionSpool.Delivery)?
    /// Asks the engine to launch again with plan B; true when it does, and this launch's failure is then no error.
    /// Called once at most, when Claude refused `initialize` or did not know the prompt tool, before any message.
    /// Both triggers are guesses, not seen from a real Claude: no version without `stdio` was recorded.
    var fallback: (() -> Bool)?

    public init(_ launch: Launch, write: @escaping (Data) throws -> Void, emit: @escaping (AgentEvent) -> Void, now: @escaping () -> String) {
        (self.launch, self.write, self.emit, self.now) = (launch, write, emit, now)
        model = launch.model
    }

    /// `initialize` is optional, but its answer lists the models this account offers.
    public func begin() throws {
        emit(.options(options()))
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
        case "command_lifecycle": lifecycle(frame)
        default: break   // a newer Claude's frames must not break an older something
        }
    }

    /// Priority "next": Claude reads the message after the running tool calls, in the same turn, or starts a turn
    /// with it. Never "now", which may interrupt the turn; never left out, since the default depends on a flag on
    /// Anthropic's side. `origin` human: an unattributed message fails Claude's own trust checks.
    /// The uuid lets Claude say what became of the message (`command_lifecycle`).
    public func deliver(_ text: String, steer: Bool) throws {
        let uuid = UUID().uuidString.lowercased()
        try send(["type": "user", "message": ["role": "user", "content": text], "parent_tool_use_id": NSNull(),
                  "uuid": uuid, "priority": "next", "origin": ["kind": "human"]])
        messages[uuid] = (text, steer, false)
        // A steer is shown once Claude takes it in: until then it may still be dropped unread. A message that starts
        // a turn opens it here, so the person's words are the turn's first item; Claude's own `running` then
        // changes nothing.
        if !steer {
            turn(open: true)
            appendPerson(text)
        }
    }

    /// `cancel_queued` drops the steered messages Claude still holds, as an interrupt empties something's own queue.
    public func interrupt() throws {
        interrupting = true
        try control("interrupt", ["cancel_queued": true])
    }

    /// A new mode applies at once; a new model or effort from Claude's next request to the model, which is the next
    /// turn when one runs. What is returned is what Claude was asked: only the state, once Claude reports the new
    /// value, says it applied, and a refusal comes as the agent's error.
    public func set(model: String?, mode: String?, effort: String?) throws -> String {
        if let mode { try control("set_permission_mode", ["mode": mode], value: mode) }
        if let model { try control("set_model", ["model": model], value: model) }
        if let effort { try control("apply_flag_settings", ["settings": ["effortLevel": effort]], value: effort) }
        return (model != nil || effort != nil) && turnOpen ? "next-turn" : "now"
    }

    public func prompt(_ request: String) -> Prompt? { asks[request]?.prompt }

    /// Allow passes the input back unchanged, and never one of Claude's suggestions for a lasting rule. A question
    /// is answered by allowing the tool with the answers added to its input, keyed by each question's text.
    public func answer(_ request: String, _ answer: Answer) throws -> Bool {
        guard let ask = asks[request] else { return false }
        let input = ask.request["input"] as? [String: Any] ?? [:]
        let question = ask.prompt.request.kind == "question"
        if case .choice(let chosen) = answer, chosen.count != ask.prompt.questions.count {
            throw CodedError("BAD_PARAMS", "Answer each of the \(ask.prompt.questions.count) questions, in their order.")
        }
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
        if ask.hook {
            switch hookReply?(ask.claudeID, reply) ?? .gone {
            case .written: asks[request] = nil
            case .gone:
                // The hook ended meanwhile: the request was withdrawn, and its window closes.
                asks[request] = nil
                emit(.requestClosed(id: request))
                return false
            case .unwritten:
                emit(.error(AgentError(code: "AGENT_ERROR", message: "something could not pass your answer to Claude Code; answer again.")))
                return false
            }
        } else {
            try send(["type": "control_response", "response": ["subtype": "success", "request_id": ask.claudeID, "response": reply]])
            asks[request] = nil
        }
        if let tool = ask.request["tool_use_id"] as? String ?? hookTool(ask.request) { decide(tool, Decision(by: "person", outcome: allow ? "allowed" : "denied")) }
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
        // An older Claude that does not know `stdio` as a prompt tool ends at once, naming the flag (a guess: see `fallback`).
        if !heard, errors.contains("permission-prompt-tool"), fallingBack() { return }
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
            if let model = frame["model"] as? String { running(model) }
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
            // Denied without asking anyone: by a rule, by the mode (its classifier included) or by a hook. Plan B's
            // hook carries the person's deny, which `answer` recorded already: it stays theirs.
            let by = ["rule": "rule", "mode": "mode", "classifier": "mode", "hook": "hook"][frame["decision_reason_type"] as? String ?? ""]
            if let tool = frame["tool_use_id"] as? String, let by, decisions[tool]?.by != "person" { decide(tool, Decision(by: by, outcome: "denied")) }
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
        // A subagent's frames carry the tool call that started it; its model (often a smaller one) is not the agent's.
        let sub = !(frame["parent_tool_use_id"] is NSNull) && frame["parent_tool_use_id"] != nil
        if !sub, let model = message["model"] as? String {
            emit(.reported(model: model, mode: nil, effort: nil))
            running(model)
        }
        // One frame per block, several frames per message: the frame's own uuid tells the items apart.
        let frameID = frame["uuid"] as? String ?? message["id"] as? String ?? "\(launch.thread)/\(UUID().uuidString.lowercased())"
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
            outcome = .failed(AgentError(code: "AGENT_ERROR", message: text.isEmpty ? "Claude Code ended its turn with an error\(reason.isEmpty ? "" : " (\(reason))")." : text))
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
        open(raw, request, hook: false)
    }

    /// Plan B: Claude's hook asked through the spool. `asked` is the hook's input (tool_name, tool_input, ...), which
    /// names no tool_use id: the tool is found by its name and input among the running ones.
    func hookAsked(_ uuid: String, _ asked: [String: Any]) {
        var request: [String: Any] = ["tool_name": asked["tool_name"] as? String ?? "a tool", "input": asked["tool_input"] as? [String: Any] ?? [:]]
        request["tool_use_id"] = hookTool(request)
        open(uuid, request, hook: true)
    }

    /// Plan B: the hook ended without an answer (Claude stopped it, or it gave up and denied).
    func hookWithdrawn(_ uuid: String) {
        guard asks.removeValue(forKey: id(uuid)) != nil else { return }
        emit(.requestClosed(id: id(uuid)))
    }

    /// The one running tool this ask is about; nil when none or several match, so no decision lands on a guess.
    private func hookTool(_ request: [String: Any]) -> String? {
        let name = request["tool_name"] as? String, text = ClaudeDriver.summary(request["input"])
        let matching = tools.filter { $0.value.tool?.name == name && $0.value.text == text && $0.value.decision == nil }
        return matching.count == 1 ? matching.first?.key : nil
    }

    private func open(_ raw: String, _ request: [String: Any], hook: Bool) {
        let tool = request["tool_name"] as? String ?? "a tool", input = request["input"] as? [String: Any] ?? [:]
        let questions = tool == "AskUserQuestion" ? ClaudeDriver.questions(input) : []
        let shown = Request(id: id(raw), agent: launch.agent, kind: tool == "AskUserQuestion" ? "question" : "permission", tool: tool,
                            about: questions.first?.text ?? (input["command"] as? String) ?? (request["description"] as? String)
                                ?? ClaudeDriver.summary(input), at: now())
        asks[shown.id] = (raw, request, Prompt(request: shown, input: questions.isEmpty ? ClaudeDriver.shown(input) : nil, questions: questions), hook)
        emit(.requestOpened(shown))
    }

    private func response(_ response: [String: Any]) {
        guard let raw = response["request_id"] as? String, let asked = sent.removeValue(forKey: raw) else { return }
        guard response["subtype"] as? String == "success" else {
            if asked.subtype == "initialize", fallingBack() { return }
            let refused = ClaudeDriver.refusals[asked.subtype] ?? "Claude Code refused what something asked"
            let words = (response["error"] as? String).map { "\(refused): \($0)" } ?? "\(refused)."
            return emit(.error(AgentError(code: "AGENT_ERROR", message: words)))
        }
        let payload = response["response"] as? [String: Any] ?? [:]
        switch asked.subtype {
        case "initialize":
            models = payload["models"] as? [[String: Any]]
            emit(.options(options()))
            if let mode = payload["current_permission_mode"] as? String { emit(.reported(model: nil, mode: mode, effort: nil)) }
        // set_model's success says nothing of the model in use: the next `init` or reply names it, so nothing is
        // reported here (an alias such as "opus" is not a model). The efforts offered become the new model's.
        case "set_model":
            model = asked.value ?? model
            emit(.options(options()))
        case "set_permission_mode": emit(.reported(model: nil, mode: payload["mode"] as? String ?? asked.value, effort: nil))
        // Claude took the setting; its success carries no value, and no later frame names the effort.
        case "apply_flag_settings": emit(.reported(model: nil, mode: nil, effort: asked.value))
        default: break
        }
    }

    /// What became of a message something wrote (msg_lifecycle_v1, seen on 2.1.296). `cancelled` also ends a message
    /// Claude had read, when its turn is interrupted: only one dropped before `started` was never read.
    private func lifecycle(_ frame: [String: Any]) {
        guard let uuid = frame["command_uuid"] as? String, let message = messages[uuid] else { return }
        switch frame["state"] as? String {
        case "started":
            messages[uuid]?.started = true
            if message.steer { appendPerson(message.text) }
        case "completed": messages[uuid] = nil
        case "cancelled", "discarded", "refused":
            messages[uuid] = nil
            // An interrupt drops the steers Claude holds, as the person asked (cancel_queued): nothing to say.
            guard !message.started, !interrupting else { return }
            let error = AgentError(code: "AGENT_ERROR", message: "Claude Code dropped the message “\(Launched.short(message.text))” without reading it.")
            if message.steer { return emit(.error(error)) }
            // The turn this message opened never started on Claude's side.
            outcome = .failed(error)
            turn(open: false)
        default: break
        }
    }

    // MARK: Helpers

    /// Hands the launch to plan B when nothing was sent yet; true when the engine took it.
    private func fallingBack() -> Bool {
        guard let fallback, messagesWritten == 0, messages.isEmpty else { return false }
        self.fallback = nil
        return fallback()
    }

    private func appendPerson(_ text: String) {
        messagesWritten += 1
        emit(.itemAppended(Item(id: "\(launch.thread)/person/\(messagesWritten)", kind: "message", author: "person", text: text, at: now())))
    }

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

    /// Claude reports running `reported`: the efforts offered become that model's, unless the one known already is it.
    private func running(_ reported: String) {
        guard entry(model).map({ ClaudeDriver.names($0).contains(reported) }) != true, reported != model else { return }
        model = reported
        if models != nil { emit(.options(options())) }
    }

    /// The entry `initialize` listed for `name`, by its value or its resolved model.
    private func entry(_ name: String?) -> [String: Any]? {
        guard let name else { return nil }
        return models?.first { ClaudeDriver.names($0).contains(name) }
    }

    private static func names(_ entry: [String: Any]) -> [String] { [entry["value"], entry["resolvedModel"]].compactMap { $0 as? String } }

    private func id(_ claudeID: String) -> String { "\(launch.agent):\(claudeID)" }

    /// The efforts are those of the model in use, as `initialize` listed them; nil until it did and the model is
    /// known, or when Claude names none for that model (an older Claude), so a space cannot ask for one.
    private func options() -> Options {
        var options = Options()
        options.mode = ClaudeDriver.modes
        options.model = models?.compactMap { model in
            (model["value"] as? String).map { Option(value: $0, label: model["displayName"] as? String ?? $0) }
        }
        options.effort = (entry(model)?["supportedEffortLevels"] as? [String]).map { $0.map { Option(value: $0, label: ClaudeDriver.effortLabels[$0] ?? $0) } }
        return options
    }

    private func control(_ subtype: String, _ fields: [String: Any], value: String? = nil) throws {
        controlsWritten += 1
        let id = "something-\(controlsWritten)"
        sent[id] = (subtype, value)
        try send(["type": "control_request", "request_id": id, "request": fields.merging(["subtype": subtype]) { a, _ in a }])
    }

    /// Lines are built from structures, never by joining strings: one malformed line kills Claude.
    private func send(_ object: [String: Any]) throws {
        try write(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]))
    }

    /// Words for the levels Claude names; a level not here is shown as Claude names it.
    static let effortLabels = ["low": "Low", "medium": "Medium", "high": "High", "xhigh": "Extra high", "max": "Max"]

    /// The start of the sentence for a control request Claude refused.
    static let refusals = ["initialize": "Claude Code refused to start the session", "interrupt": "Claude Code refused to stop the turn",
                           "set_model": "Claude Code refused the new model", "set_permission_mode": "Claude Code refused the new mode",
                           "apply_flag_settings": "Claude Code refused the new effort"]

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
