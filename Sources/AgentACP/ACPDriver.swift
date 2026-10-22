// ACPDriver: an agent launched by something over the Agent Client Protocol (ACP): JSON-RPC 2.0, one object per line
// on its input and output, each launch its own program holding one conversation (a "session"). Its profile
// (ACPProfile) says what differs from one agent to another. It turns the agent's raw words into neutral events: a
// session/prompt waiting for its answer is an open turn, the answer's stopReason ends it, and
// session/request_permission is a permission. What each choice rests on (OpenCodeTrial.swift, against OpenCode, the
// first agent proven over ACP) is said where it is made.
import Foundation
import SomethingAgents
import SomethingCore

/// Model, mode and effort never go on the command line (ACPProfile.driving): they go through the channel, where the
/// agent says what it took.
final class ACPDriver: Driver {
    private let profile: ACPProfile
    private let launch: Launch
    private let write: (Data) throws -> Void
    private let emit: (AgentEvent) -> Void
    private let now: () -> String
    /// Calls something made and the agent has not answered yet, by request id.
    private var calls: [Int: Call] = [:]
    private var callsWritten = 0
    private var session: String?
    /// Values to set, in order, one call at a time (a new model changes the efforts offered), and whether one is out.
    private var settings: [(key: String, value: String)] = []
    private var setting = false
    /// Messages handed over before the session and its settings were ready; at most one in practice.
    private var early: [String] = []
    /// Whether something sent session/cancel for the running prompt: its "cancelled" is then an interrupt.
    private var cancelAsked = false
    /// Open requests by the id something shows.
    private var asks: [String: Ask] = [:]
    /// Each tool call's name (the title of its first update), its item while it runs, and the person's decision on it.
    private var names: [String: String] = [:]
    private var tools: [String: Item] = [:]
    private var decisions: [String: Decision] = [:]
    /// The text so far of each message the agent streams, by its messageId.
    private var texts: [String: String] = [:]
    /// Whether the agent wrote any line, which tells a failed start from a later end.
    private var heard = false
    /// Whether the end was already said.
    private var over = false
    /// Messages handed over so far, which names their items.
    private var sent = 0
    /// The program's whole environment, which the profile's quirks read; empty until `join`.
    var environment: [String: String] = [:]
    /// The model a new conversation that names none takes, when the agent offers it (`ACPProfile.lastModel`).
    var recent: String?
    /// Whether a model was asked for, by the launch or later: then the agent's own last model is not something's to pick.
    private var modelAsked: Bool
    /// The model in use and those offered, as the agent last listed them.
    private var model: String?
    private var models: [String] = []
    /// The agent's own id for the entry of each of something's keys ("model", "mode", "effort"), found by its category:
    /// set_config_option names the entry by that id.
    private var ids: [String: String] = [:]
    /// Why the agent would end this turn "cancelled" by itself: a request refused, a question it could not show.
    private var halted: String?
    /// Closes the program's input, after which the agent exits: its program's (`join`), used when the launch cannot go on.
    var quit: () -> Void = {}
    /// Whether a session/prompt waits for its answer. The stop ladder reads it from its own thread.
    var prompting: Bool { lock.withLock { pending } }
    private let lock = NSLock()
    private var pending = false

    private enum Call { case initialize, open, set(key: String, value: String), prompt(String) }

    private struct Ask { var rpcID: Any, options: [[String: Any]], tool: String?, prompt: Prompt }

    init(_ profile: ACPProfile, _ launch: Launch, write: @escaping (Data) throws -> Void, emit: @escaping (AgentEvent) -> Void, now: @escaping () -> String) {
        self.profile = profile
        self.launch = launch
        self.write = write
        self.emit = emit
        self.now = now
        modelAsked = launch.model != nil
        // The mode first, since an agent may bring its own model; the effort last, since the model decides the levels.
        settings = [("mode", launch.mode), ("model", launch.model), ("effort", launch.effort)].compactMap { key, value in value.map { (key, $0) } }
    }

    /// something reads no file and runs no terminal for the agent: it does both itself.
    func begin() throws {
        try invoke(.initialize, "initialize", ["protocolVersion": 1, "clientCapabilities": ["fs": ["readTextFile": false, "writeTextFile": false], "terminal": false]])
    }

    func receive(_ line: Data) {
        guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return }
        heard = true
        let params = message["params"] as? [String: Any] ?? [:]
        switch (message["method"] as? String, message["id"]) {
        case (let method?, let id?): request(method, id, params)
        case ("session/update"?, nil) where params["sessionId"] as? String == session: update(params["update"] as? [String: Any] ?? [:])
        case (nil, let id as Int): response(id, message)
        default: break   // a newer agent's lines must not break an older something
        }
    }

    /// A message starts a turn; it goes out once the session and the settings asked before it are in place.
    /// Throws NOT_SUPPORTED for a steer, which ACP refuses (`limits`), and AGENT_STOPPED.
    func deliver(_ text: String, steer: Bool) throws {
        guard !steer else { throw CodedError("NOT_SUPPORTED", profile.steerLimit) }
        sent += 1
        emit(.turnStarted(id: nil))
        emit(.itemAppended(Item(id: "\(launch.agent)/sent\(sent)", kind: "message", author: "person", text: text, at: now())))
        early.append(text)
        try flush()
    }

    /// session/cancel stops the running prompt, whose answer then says "cancelled"; a request still open is
    /// answered "cancelled", as ACP asks. A message not sent yet is dropped and its turn ends here.
    func interrupt() throws {
        guard prompting, let session else {
            guard !early.isEmpty else { return }
            early = []
            return emit(.turnEnded(.interrupted))
        }
        cancelAsked = true
        try send(["method": "session/cancel", "params": ["sessionId": session]])
        for id in asks.keys.sorted() {
            try? send(["id": asks[id]!.rpcID, "result": ["outcome": ["outcome": "cancelled"]]])
            asks[id] = nil
            emit(.requestClosed(id: id))
        }
    }

    /// Each value goes out with session/set_config_option, one at a time; the agent answers with all its options, and
    /// the state shows what it took (it may keep another model when its catalog was not ready). A turn
    /// that runs keeps the values it started with.
    func set(model: String?, mode: String?, effort: String?) throws -> String {
        if model != nil { modelAsked = true }
        settings += [("mode", mode), ("model", model), ("effort", effort)].compactMap { key, value in value.map { (key, $0) } }
        try nextSetting()
        return prompting ? "next-turn" : "now"
    }

    func prompt(_ request: String) -> Prompt? { asks[request]?.prompt }

    /// Allow and deny pick the agent's own once-only options by their kind, never "always", which would write a lasting
    /// rule into it; a request without them is answered "cancelled", which OpenCode, the first agent proven, takes as a refusal. The
    /// decision shown is the one sent: an allow that could not be sent is a refusal, and the agent's error says why.
    func answer(_ request: String, _ answer: Answer) throws -> Bool {
        guard let ask = asks[request] else { return false }
        let kind = answer == .once ? "allow_once" : "reject_once"
        let option = ask.options.first { $0["kind"] as? String == kind }?["optionId"] as? String
        try send(["id": ask.rpcID, "result": ["outcome": option.map { ["outcome": "selected", "optionId": $0] } ?? ["outcome": "cancelled"]]])
        asks[request] = nil
        let allowed = answer == .once && option != nil
        if answer == .once, !allowed { emit(.error(AgentError(code: "AGENT_ERROR", message: profile.noAllowOnce))) }
        if !allowed {
            let about = (ask.prompt.request.about ?? ask.prompt.request.tool).map { "its request “\(Launched.short($0))”" } ?? "one of its requests"
            halted = "\(profile.name) stopped its turn because \(about) was refused. Tell it what to do instead in a new message."
        }
        if let tool = ask.tool { decide(tool, Decision(by: "person", outcome: allowed ? "allowed" : "denied")) }
        emit(.requestClosed(id: request))
        return true
    }

    /// No line ends an ACP agent: the first step of the ladder is `graceful`.
    var goodbye: Data? { nil }

    /// Takes the program's environment, the model its profile says a new conversation takes, and the program's input
    /// to close (`quit`).
    func join(_ program: ProcessHandle) {
        quit = program.quit
        environment = program.environment
        recent = profile.lastModel?(environment)
    }

    /// An interrupt and its answer, within Spawn's 3 s, then the input closed (the agent exits at its end); never a
    /// signal first, which may leave the conversation marked as running (seen with OpenCode: `leftRunning`).
    func graceful(_ program: ProcessHandle) {
        program.interrupt()
        while program.running(), prompting { usleep(20_000) }
    }

    /// An end nobody asked for. A claim left behind is said in the same error, after how the agent ended.
    func ended(code: Int32, errors: String) {
        guard !over else { return }
        over = true
        let claim = leftClaim()
        guard code != 0 else { return emit(.stopped(claim.map { AgentError(code: "AGENT_ERROR", message: $0) })) }
        let lines = errors.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !heard { return emit(.stopped(AgentError(code: "LAUNCH_FAILED", message: lines.first.map { "\(profile.name) could not start: \($0)" }
            ?? "\(profile.name) stopped at once (code \(code))."))) }
        let end = lines.last.map { "\(profile.name) ended: \($0)" } ?? "\(profile.name) ended (code \(code))."
        emit(.stopped(AgentError(code: "AGENT_ERROR", message: claim.map { "\(end) \($0)" } ?? end)))
    }

    /// After a stop something asked for, which is folded without `ended`: a claim left behind (the ladder ran out of
    /// time before the cancel was answered) becomes the agent's error.
    func afterAskedStop() {
        guard !over, let claim = leftClaim() else { return }
        emit(.error(AgentError(code: "AGENT_ERROR", message: claim)))
    }

    /// What the profile says of a conversation left marked as running, only when one of something's own turns was
    /// still open at the end: a turn the agent answered, done or cancelled, released it, and a claim no open turn of
    /// something's took (an earlier crash, the person's own agent on the same conversation) is not something's to report.
    private func leftClaim() -> String? {
        guard prompting, let session else { return nil }
        return profile.leftRunning?(session, environment)
    }

    // MARK: The agent's lines

    private func response(_ id: Int, _ message: [String: Any]) {
        guard let call = calls.removeValue(forKey: id) else { return }
        let result = message["result"] as? [String: Any] ?? [:]
        let error = message["error"] as? [String: Any]
        let words = ACPDriver.words(error)
        switch call {
        case .initialize:
            if error != nil { return refused(AgentError(code: "LAUNCH_FAILED", message: "\(profile.name) refused to start: \(words)")) }
            var params: [String: Any] = ["cwd": launch.folder, "mcpServers": [Any]()]
            if launch.resume { params["sessionId"] = launch.thread }
            try? invoke(.open, launch.resume ? "session/resume" : "session/new", params)
        case .open:
            if error != nil {
                // ACP's code for a missing resource, else the words of an agent that answers with another code.
                let missing = error?["code"] as? Int == -32002 || profile.notFoundWords.contains { words.contains($0) }
                return refused(missing ? AgentError(code: "THREAD_NOT_FOUND", message: "\(profile.name) has no conversation \(launch.thread) in \(launch.folder) on this Mac.")
                    : AgentError(code: "AGENT_ERROR", message: "\(profile.name) refused to start the conversation: \(words). If it has no model yet, run `\(profile.signIn)` in a terminal."))
            }
            session = launch.resume ? launch.thread : result["sessionId"] as? String
            emit(.started(pid: nil, thread: session))
            read(result["configOptions"])
            // Before the effort, which depends on the model; a resumed conversation keeps its own model.
            if !modelAsked, !launch.resume, let recent, recent != model, models.contains(recent) {
                settings.insert(("model", recent), at: settings.firstIndex { $0.key == "effort" } ?? settings.endIndex)
            }
            try? flush()
        case .set(let key, let value):
            setting = false
            if error != nil {
                emit(.error(AgentError(code: "VALUE_NOT_OFFERED", message: "\(profile.name) refused \(value) as its \(key): \(words)")))
            } else if let options = result["configOptions"] as? [[String: Any]] {
                read(options)
                let taken = options.first { $0["id"] as? String == ids[key] ?? key }?["currentValue"] as? String
                if taken != value { emit(.error(AgentError(code: "VALUE_NOT_OFFERED", message: "\(profile.name) kept \(taken ?? "no value") as its \(key), not \(value)."))) }
            }
            try? flush()
        case .prompt(let text):
            lock.withLock { pending = false }
            forgetTurn()
            let (cancelled, halted) = (cancelAsked, self.halted)
            (cancelAsked, self.halted) = (false, nil)
            if error != nil {
                return emit(.turnEnded(.failed(AgentError(code: "AGENT_ERROR", message: profile.failure(error, words, text, model: model, picked: profile.lastModel != nil && !modelAsked && !launch.resume)))))
            }
            switch result["stopReason"] as? String {
            case "cancelled" where cancelled: emit(.turnEnded(.interrupted))
            // An agent may also end a turn "cancelled" by itself: OpenCode, the first agent proven, does after a refused
            // permission or a dismissed question (OpenCodeTrial.swift). Its work stopped there, which is no normal end.
            case "cancelled":
                emit(.turnEnded(.failed(AgentError(code: "AGENT_ERROR", message: halted ?? "\(profile.name) stopped its turn before the end without saying why."))))
            case "max_tokens": emit(.turnEnded(.failed(AgentError(code: "AGENT_ERROR", message: "\(profile.name)'s model reached its output limit before the end of its answer."))))
            case "refusal": emit(.turnEnded(.failed(AgentError(code: "AGENT_ERROR", message: "\(profile.name)'s model refused to answer."))))
            default: emit(.turnEnded(.done))
            }
        }
    }

    /// The launch cannot go on: the agent ends with `error`, and its program is told to end.
    private func refused(_ error: AgentError) {
        over = true
        emit(.stopped(error))
        quit()
    }

    private func request(_ method: String, _ rpcID: Any, _ params: [String: Any]) {
        guard method == "session/request_permission", params["sessionId"] as? String == session else {
            // An ACP agent waits for every request it sends: one something does not handle gets a refusal, not silence.
            try? send(["id": rpcID, "error": ["code": -32601, "message": "something does not handle \(method)."]])
            return
        }
        let call = params["toolCall"] as? [String: Any] ?? [:]
        let tool = call["toolCallId"] as? String
        let input = call["rawInput"] as? [String: Any]
        let shown = Request(id: "\(launch.agent):\(rpcID)", agent: launch.agent, kind: "permission",
                            tool: tool.flatMap { names[$0] } ?? call["kind"] as? String, about: call["title"] as? String, at: now())
        asks[shown.id] = Ask(rpcID: rpcID, options: params["options"] as? [[String: Any]] ?? [], tool: tool,
                             prompt: Prompt(request: shown, input: input?["command"] as? String ?? ACPDriver.json(input)))
        emit(.requestOpened(shown))
    }

    private func update(_ update: [String: Any]) {
        // A sub-agent's updates come into its parent's stream, marked only by its profile's key.
        let child = profile.childKey.map { (update["_meta"] as? [String: Any])?[$0] != nil } ?? false
        switch update["sessionUpdate"] as? String {
        case let kind? where kind == "agent_message_chunk" || kind == "agent_thought_chunk":
            guard let text = (update["content"] as? [String: Any])?["text"] as? String, !text.isEmpty else { return }
            let id = update["messageId"] as? String ?? "\(launch.agent)/message"
            let known = texts[id] != nil
            texts[id, default: ""] += text
            let item = Item(id: id, kind: child ? "subagent" : kind == "agent_message_chunk" ? "message" : "thought", author: "agent", text: texts[id]!, at: now())
            emit(known ? .itemUpdated(item) : .itemAppended(item))
        case "tool_call", "tool_call_update":
            guard let id = update["toolCallId"] as? String else { return }
            if names[id] == nil, let title = update["title"] as? String { names[id] = title }
            let status = ["in_progress": "running", "completed": "done", "failed": "failed"][update["status"] as? String ?? ""]
            let old = tools[id]
            let item = Item(id: id, kind: child ? "subagent" : "tool", author: "agent", text: update["title"] as? String ?? old?.text ?? "",
                            at: old?.at ?? now(), tool: Tool(name: names[id] ?? update["kind"] as? String ?? "tool", status: status ?? old?.tool?.status),
                            decision: decisions[id])
            emit(old == nil ? .itemAppended(item) : .itemUpdated(item))
            let done = status == "done" || status == "failed"
            tools[id] = done ? nil : item
            if done, let question = profile.questionTool, item.tool?.name == question {
                halted = profile.questionDismissed
                emit(.error(AgentError(code: "AGENT_ERROR", message: profile.questionDismissed)))
            }
        case "config_option_update": read(update["configOptions"])   // sent from 2.0.25 on
        default: break   // commands, usage, retries: nothing the state shows
        }
    }

    // MARK: Helpers

    /// What a turn streamed belongs to it: a tool cut by its end never finishes, and the next turn names new
    /// messages and tool calls.
    private func forgetTurn() {
        for var item in tools.values {
            item.tool?.status = nil
            emit(.itemUpdated(item))
        }
        tools = [:]
        decisions = [:]
        texts = [:]
        names = [:]
    }

    /// Sends what waits, in order: the settings first, then the message, once the session exists.
    private func flush() throws {
        guard session != nil else { return }
        try nextSetting()
        guard !setting, settings.isEmpty, !prompting, let session, !early.isEmpty else { return }
        let text = early.removeFirst()
        lock.withLock { pending = true }
        try invoke(.prompt(text), "session/prompt", ["sessionId": session, "prompt": [["type": "text", "text": text]]])
    }

    private func nextSetting() throws {
        guard let session, !setting, !settings.isEmpty else { return }
        let (key, value) = settings.removeFirst()
        setting = true
        try invoke(.set(key: key, value: value), "session/set_config_option", ["sessionId": session, "configId": ids[key] ?? key, "value": value])
    }

    /// The agent's options for the session: the values in use and those offered, by their category. Each list it
    /// sends is complete, so a value it no longer lists is none: an effort is dropped with a model without variants.
    private func read(_ list: Any?) {
        guard let list = list as? [[String: Any]] else { return }
        func entry(_ category: String) -> [String: Any]? { list.first { $0["category"] as? String == category } }
        for (key, category) in [("model", "model"), ("mode", "mode"), ("effort", profile.effortCategory)] {
            if let id = entry(category)?["id"] as? String { ids[key] = id }
        }
        func choices(_ entry: [String: Any]?) -> [Option]? {
            (entry?["options"] as? [[String: Any]])?.compactMap { option in
                (option["value"] as? String).map { Option(value: $0, label: option["name"] as? String ?? $0) }
            }
        }
        var options = Options()
        options.model = choices(entry("model"))
        (model, models) = (entry("model")?["currentValue"] as? String, options.model?.map(\.value) ?? [])
        options.mode = choices(entry("mode"))
        options.effort = choices(entry(profile.effortCategory))
        emit(.options(options))
        emit(.settings(model: entry("model")?["currentValue"] as? String, mode: entry("mode")?["currentValue"] as? String,
                       effort: entry(profile.effortCategory)?["currentValue"] as? String))
    }

    private func decide(_ tool: String, _ decision: Decision) {
        decisions[tool] = decision
        guard var shown = tools[tool] else { return }
        shown.decision = decision
        tools[tool] = shown
        emit(.itemUpdated(shown))
    }

    /// The agent's words for an error, without the prefix of JSON-RPC's standard errors ("Invalid params: ", "Internal error: ").
    static func words(_ error: [String: Any]?) -> String {
        let words = error?["message"] as? String ?? "no reason given"
        for prefix in ["Invalid params: ", "Internal error: "] where words.hasPrefix(prefix) { return String(words.dropFirst(prefix.count)) }
        return words
    }

    private func invoke(_ call: Call, _ method: String, _ params: [String: Any]) throws {
        callsWritten += 1
        calls[callsWritten] = call
        try send(["id": callsWritten, "method": method, "params": params])
    }

    /// Lines are built from structures, never by joining strings.
    private func send(_ object: [String: Any]) throws {
        var object = object
        object["jsonrpc"] = "2.0"
        try write(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]))
    }
}
