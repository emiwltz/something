// ClaudeDriver: Claude Code launched by something, through `claude -p` with JSON lines in and out (stream-json), the
// channel Anthropic's SDKs use. It turns Claude's raw words into neutral events: its session state into
// turns, `can_use_tool` into a permission or, for AskUserQuestion, a question, `aborted_*` into an interruption. The
// channel is undocumented in places; what each choice rests on is said where it is made.
import Foundation
import SomethingAgents
import SomethingCore

final class ClaudeDriver: Driver {
    /// Removed from the environment Claude Code gets: a key left in a shell profile overrides the subscription the
    /// person signed in with, and a dead one makes every message fail.
    static let credentials: Set<String> = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"]

    /// `--permission-prompt-tool stdio` sends permission requests on this channel instead of refusing them (the SDKs
    /// pass it; the help does not list it). The mode is always explicit: without it a stranger's settings pick one,
    /// possibly `auto`. The environment variable makes Claude say when a turn starts and ends; it is set for this
    /// launch only.
    static func command(_ launch: Launch) -> Command { command(launch, hook: nil) }

    /// Plan B's command: the host's hook command, with the launch's own spool folder. Throws LAUNCH_FAILED when the
    /// host does not know its hook command or its spools.
    static func command(_ launch: Launch, host: HostFacts) throws -> Command {
        guard let hook = host.hookCommand else { throw CodedError("LAUNCH_FAILED", "Plan B needs something's own program to answer Claude Code's permission requests, and this launch does not know it; launch Claude Code from the something app.") }
        return command(launch, hook: hook + ["--spool", try spool(launch, host)])
    }

    /// Plan B's spool folder for `launch`: <agent>-<conversation id> in the host's spools (PermissionSpool.swift), since
    /// two something running at once (the app and a `something try`) may both have a claude-1. Throws LAUNCH_FAILED
    /// when the host has no spools.
    static func spool(_ launch: Launch, _ host: HostFacts) throws -> String {
        guard let spools = host.spools else { throw CodedError("LAUNCH_FAILED", "Plan B needs a folder of something's own for Claude Code's permission requests, and this launch has none; launch Claude Code from the something app.") }
        return (spools as NSString).appendingPathComponent("\(launch.agent)-\(launch.thread)")
    }

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
        // A resume keeps the conversation's id: Claude forks a new one only when asked (--fork-session).
        arguments += ["--include-hook-events", "--permission-mode", launch.mode ?? "default", launch.resume ? "--resume" : "--session-id", launch.thread]
        // One argument, so a model is never read as an option.
        if let model = launch.model { arguments.append("--model=\(model)") }
        if let effort = launch.effort { arguments.append("--effort=\(effort)") }
        if let config = launch.lent?.mcpConfig { arguments += ["--mcp-config", config] }
        if launch.assistant == .building { arguments += ["--allowedTools"] + building(launch.folder, launch.lent) }
        return Command(arguments: arguments, adding: ["CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS": "1"], removing: credentials)
    }

    /// What the person's assistant may do without asking (AGENTS.md, rule 2): change files in
    /// `folder`, the spaces folder, and call the tools something lends it (`lent`), served by its MCP server
    /// "something". The rules fail toward asking: any other command, tool or path still asks. In Claude's rules "//"
    /// starts an absolute path ("/" alone is the project's root).
    static func building(_ folder: String, _ lent: Lent?) -> [String] {
        ["Edit(/\(folder)/**)", "Write(/\(folder)/**)"] + (lent?.tools ?? []).map { "mcp__something__\($0.name)" }
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
    /// Set when the model's server refused Claude's sign-in: the turn fails with it, whatever ends the turn.
    private var refused: AgentError?
    /// The last retry Claude reported in this turn while it could not reach its model, as `detail.apiRetry` shows it
    /// (the assistant's only); empty once the model answered or a new turn started. Kept after a turn that failed: it
    /// says why. Changed through `remember(retry:)`, which tells the state.
    private var retry: [String: JSONValue] = [:]
    private var heard = false
    /// The models `initialize` listed, and the one in use: the one asked for (an alias such as "opus"), then the one
    /// Claude reports running (a model id, an entry's resolvedModel). The efforts offered are that model's; nil until
    /// one is known, since the person's own settings may pick a model other than "default".
    private var models: [[String: Any]]?
    private var model: String?
    /// Plan B's spool, which this launch's hook asks through: started at `join`, stopped when the program is released.
    /// Set once in `join`, before the program starts, and never again: it is then read from any thread (the main
    /// queue, the spool's queue, Spawn's wait), so it must never be replaced or cleared.
    private var spool: PermissionSpool?
    /// Asks the engine to launch again with plan B; true when it does, and this launch's failure is then no error.
    /// Called once at most, when Claude refused `initialize` or did not know the prompt tool, before any message.
    /// Both triggers are guesses, not seen from a real Claude: no version without `stdio` was recorded. Offered only
    /// when the host knows its hook command (`join`).
    var fallback: (() -> Bool)?

    init(_ launch: Launch, write: @escaping (Data) throws -> Void, emit: @escaping (AgentEvent) -> Void, now: @escaping () -> String) {
        (self.launch, self.write, self.emit, self.now) = (launch, write, emit, now)
        model = launch.model
    }

    /// `initialize` is optional, but its answer lists the models this account offers.
    func begin() throws {
        emit(.options(options()))
        try control("initialize", [:])
    }

    @discardableResult func receive(_ line: Data) -> Bool {
        guard let frame = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return false }
        heard = true
        switch frame["type"] as? String {
        case "system": system(frame)
        case "assistant": assistant(frame)
        case "user": toolResults(frame)
        case "result": result(frame)
        case "control_request": request(frame)
        case "control_cancel_request":
            // Claude withdrew it (the turn was interrupted, a hook answered first): it must not be answered.
            guard let raw = frame["request_id"] as? String, asks.removeValue(forKey: id(raw)) != nil else { return true }
            emit(.requestClosed(id: id(raw)))
        case "control_response": response(frame["response"] as? [String: Any] ?? [:])
        case "command_lifecycle": lifecycle(frame)
        default: return false   // a newer Claude's frames must not break an older something
        }
        return true
    }

    /// Priority "next": Claude reads the message after the running tool calls, in the same turn, or starts a turn
    /// with it. Never "now", which may interrupt the turn; never left out, since the default depends on a flag on
    /// Anthropic's side. `origin` human: an unattributed message fails Claude's own trust checks.
    /// The uuid lets Claude say what became of the message (`command_lifecycle`).
    func deliver(_ text: String, steer: Bool) throws {
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
    func interrupt() throws {
        interrupting = true
        try control("interrupt", ["cancel_queued": true])
    }

    /// A new mode applies at once; a new model or effort from Claude's next request to the model, which is the next
    /// turn when one runs. What is returned is what Claude was asked: only the state, once Claude reports the new
    /// value, says it applied, and a refusal comes as the agent's error.
    func set(model: String?, mode: String?, effort: String?) throws -> String {
        if let mode { try control("set_permission_mode", ["mode": mode], value: mode) }
        if let model { try control("set_model", ["model": model], value: model) }
        if let effort { try control("apply_flag_settings", ["settings": ["effortLevel": effort]], value: effort) }
        return (model != nil || effort != nil) && turnOpen ? "next-turn" : "now"
    }

    func prompt(_ request: String) -> Prompt? { asks[request]?.prompt }

    /// Allow passes the input back unchanged, and never one of Claude's suggestions for a lasting rule. A question
    /// is answered by allowing the tool with the answers added to its input, keyed by each question's text.
    func answer(_ request: String, _ answer: Answer) throws -> Bool {
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
            switch spool?.answer(ask.claudeID, reply) ?? .gone {
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
    var goodbye: Data? {
        try? JSONSerialization.data(withJSONObject: ["type": "control_request", "request_id": "something-end",
                                                     "request": ["subtype": "end_session"]], options: [.sortedKeys])
    }

    /// Plan B starts its spool before the program, which then asks through it; plan A keeps the way to plan B.
    func join(_ program: ProcessHandle) throws {
        guard launch.planB else {
            if program.host.hookCommand != nil, program.host.spools != nil { fallback = program.relaunch }
            return
        }
        let spool = PermissionSpool(folder: try ClaudeDriver.spool(launch, program.host))
        spool.asked = { [weak self] uuid, request in self?.hookAsked(uuid, request) }
        spool.withdrawn = { [weak self] uuid in self?.hookWithdrawn(uuid) }
        do { try spool.start() } catch { throw CodedError("LAUNCH_FAILED", "\(error)") }
        self.spool = spool
    }

    /// A hook still waiting then denies within a moment.
    func released() { spool?.stop() }

    func ended(code: Int32, errors: String) {
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
        case "api_retry":
            // Claude retries a refused sign-in or a server out of reach ten times over about four minutes, a busy
            // server (529) three times, saying nothing else meanwhile (measured in S11 and S12). The assistant's window
            // says each retry (`detail.apiRetry`, which no space sees: a space's own agents get no new fact). A refused
            // sign-in never passes by retrying: the turn fails at the first retry, and Claude is told to stop.
            guard turnOpen else { return }
            let status = frame["error_status"] as? Int, error = frame["error"] as? String
            let number = { (key: String) in (frame[key] as? Double).map(JSONValue.number) ?? .null }
            remember(retry: ["attempt": number("attempt"), "maxRetries": number("max_retries"), "errorStatus": number("error_status"),
                             "error": error.map(JSONValue.string) ?? .null])
            // A forbidden key (403) does not pass by retrying either, but signing in again may not cure it.
            guard refused == nil, ClaudeDriver.refusesSignIn(status: status, error: error) || status == 403 else { return }
            refused = AgentError(code: "AGENT_ERROR", message: "The model's server refused Claude Code's sign-in (error \(status.map(String.init) ?? "401")).")
            try? control("interrupt", ["cancel_queued": true])
        default: break
        }
    }

    private func assistant(_ frame: [String: Any]) {
        let message = frame["message"] as? [String: Any] ?? [:]
        let blocks = message["content"] as? [[String: Any]] ?? []
        // Claude Code writes its own failures (a refused key, a reached limit, retries given up) as a message from a
        // "<synthetic>" model: an error, not the agent speaking, and not its model. The retries it gave up stay: they
        // say why. A Claude Code never signed in fails here before any request: the assistant's detail says so too.
        if message["model"] as? String == "<synthetic>" {
            if retry.isEmpty, let error = frame["error"] as? String, ClaudeDriver.refusesSignIn(status: nil, error: error) {
                remember(retry: ["attempt": .null, "maxRetries": .null, "errorStatus": .null, "error": .string(error)])
            }
            let text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
            return emit(.error(AgentError(code: "AGENT_ERROR", message: text.isEmpty ? "Claude Code could not answer." : text)))
        }
        remember(retry: [:])   // the model answered
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
                let lent = launch.lent == nil ? nil : Lent.called(name, block["input"])
                let item = Item(id: toolID, kind: sub ? "subagent" : "tool", author: "agent", text: lent.map { $0.command ?? "\($0.name) (wrong arguments)" } ?? ClaudeDriver.summary(block["input"]),
                                at: at, tool: Tool(name: lent?.name ?? name, status: "running"), decision: decisions[toolID])
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
        if let refused {
            outcome = .failed(refused)
        } else if frame["subtype"] as? String == "success" && frame["is_error"] as? Bool != true {
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

    /// Keeps `retry` and tells the state, for the person's assistant only: a space's own agents get no new fact.
    private func remember(retry: [String: JSONValue]) {
        guard launch.assistant != nil, retry != self.retry else { return }
        self.retry = retry
        emit(.detail(retry.isEmpty ? [:] : ["apiRetry": .object(retry)]))
    }

    /// Whether Claude's failure means the model's server refused its sign-in (a missing or rejected key), which signing
    /// in again in Terminal cures. `status` is the HTTP status when there was one (401 only: a 403 is a key without
    /// access, which signing in may not cure), `error` Claude's error kind otherwise.
    static func refusesSignIn(status: Int?, error: String?) -> Bool {
        if let status { return status == 401 }
        return error == "authentication_failed"
    }

    private func appendPerson(_ text: String) {
        messagesWritten += 1
        emit(.itemAppended(Item(id: "\(launch.thread)/person/\(messagesWritten)", kind: "message", author: "person", text: text, at: now())))
    }

    private func turn(open: Bool) {
        guard open != turnOpen else { return }
        turnOpen = open
        if open {
            remember(retry: [:])
            return emit(.turnStarted(id: nil))
        }
        let ended = refused.map(Outcome.failed) ?? outcome ?? (interrupting ? .interrupted : .done)
        (outcome, interrupting, refused) = (nil, false, nil)
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
        options.mode = Driving.claude.modes
        options.model = models?.compactMap { model in
            (model["value"] as? String).map { Option(value: $0, label: model["displayName"] as? String ?? $0) }
        }
        options.effort = (entry(model)?["supportedEffortLevels"] as? [String]).map { $0.map { Option(value: $0, label: Option.effortLabels[$0] ?? $0) } }
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

extension Driving {
    /// None of `limits`: ClaudeTrial.swift showed that Claude takes an effort at launch (`--effort`) and during a session
    /// (`apply_flag_settings` with `effortLevel`, from its next request to the model). Claude refuses an effort its
    /// model does not list: `can.effort` follows `options.effort`. bypassPermissions is never among the modes: it
    /// cannot be entered unless the launch allowed it, and something never allows it.
    static let claude = Driving(kind: "claude", tested: "2.1.296",
                                modes: [Option(value: "default", label: "Ask before acting"), Option(value: "acceptEdits", label: "Accept edits"),
                                        Option(value: "plan", label: "Plan only"), Option(value: "auto", label: "Auto (Claude decides what is safe)"),
                                        Option(value: "dontAsk", label: "Never ask (refuse what is not allowed)")],
                                effortOnlyWhenOffered: true, command: { ClaudeDriver.command($0) },
                                planB: { try ClaudeDriver.command($0, host: $1) },
                                refusesSignIn: { ClaudeDriver.refusesSignIn(status: $0, error: $1) },
                                driver: { ClaudeDriver($0, write: $1, emit: $2, now: $3) })
}
