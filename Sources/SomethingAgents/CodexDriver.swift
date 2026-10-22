// CodexDriver: Codex launched by something, through `codex app-server`, its official channel: JSON-RPC, one object
// per line on its input and output, with no "jsonrpc" key. Each launch is its own private server, which holds one
// conversation (a "thread"); something never joins the background server a terminal Codex shares. It turns Codex's
// raw words into neutral events: turn/started and turn/completed into turns, its approval requests into
// permissions, requestUserInput into a question. What each choice rests on is said where it is
// made.
import Foundation
import SomethingCore

public final class CodexDriver: Driver {
    /// The policy a launch that names none puts on its first turn when the thread's own would never ask ("never",
    /// or a granular set of rules, which asks no more than this): a stricter one is left as the person set it.
    static let defaultMode = "on-request"
    /// How long an interrupt may go unanswered: Codex never answers one sent to a thread with no active turn.
    static let interruptTimeout: TimeInterval = 5

    /// The stdio app-server starts no background daemon, even with the `daemon_auto_start` feature on (seen on
    /// 0.163.0): no flag is needed.
    public static func command(_ launch: Launch) -> Command { Command(arguments: ["app-server"]) }

    private let launch: Launch
    private let write: (Data) throws -> Void
    private let emit: (AgentEvent) -> Void
    private let now: () -> String
    /// Calls something made and Codex has not answered yet, by request id.
    private var calls: [Int: Call] = [:]
    private var callsWritten = 0
    private var thread: String?
    /// The running turn's id, from turn/start's answer or turn/started; nil when no turn runs.
    private var turn: String?
    /// Whether Codex says the thread is active (thread/status/changed). An interrupt is sent only then.
    private var active = false
    /// Messages for before the thread exists, and steers for before the running turn's id is known.
    private var early: [(text: String, steer: Bool)] = [], steers: [String] = []
    /// An interrupt asked before it could be sent, and the request id of the one sent and not yet answered.
    private var interruptAsked = false, interruptSent: Int?
    /// Model, effort and approval policy for the next turn/start: Codex keeps them for the turns after it.
    private var overrides: [String: String] = [:]
    /// Open requests by the id something shows: Codex's own id, the method, its params and the window's details.
    private var asks: [String: Ask] = [:]
    /// Tool items not finished yet, and the person's decisions on them, by Codex's item id.
    private var tools: [String: Item] = [:], decisions: [String: Decision] = [:]
    /// The items as Codex started them: a file change's request names no path, its item does.
    private var started: [String: [String: Any]] = [:]
    private var models: [[String: Any]]?, model: String?
    private var heard = false, over = false
    /// Whether Codex called a tool something lends it in this launch: then it took them.
    private var tookLent = false
    /// Codex refused to read the settings back (a new thread's rollout is empty until its first turn ends): they are
    /// read again when that turn completes.
    private var rereadSettings = false
    /// Runs `work` on the driver's queue after a delay; tests run it by hand.
    var schedule: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }
    /// Closes the program's input, after which Codex exits: set by the engine, used when the launch cannot go on.
    var quit: () -> Void = {}

    private enum Call { case initialize, open, models, start(String, overrides: [String: String]), settings, steer(String), interrupt }

    /// An open request: Codex's own id, its method and params, the window's details, and for a question the ids
    /// Codex gave the questions shown, in their order.
    private struct Ask {
        var codexID: Any, method: String, params: [String: Any], prompt: Prompt, questionIDs: [String] = []
    }

    public init(_ launch: Launch, write: @escaping (Data) throws -> Void, emit: @escaping (AgentEvent) -> Void, now: @escaping () -> String) {
        (self.launch, self.write, self.emit, self.now) = (launch, write, emit, now)
        model = launch.model
        if let effort = launch.effort { overrides["effort"] = effort }
    }

    /// The oldest Codex seen taking the tools something lends (its experimental dynamic tools): an older one would
    /// ignore them without a word, and its model would then ask to run each check outside the sandbox.
    static let lentSince = "0.163.0"

    /// `clientInfo.name` becomes the thread's `originator` in Codex's files: it stays "something". The deltas are
    /// left out: items are read whole, when they complete. Dynamic tools are experimental: only a launch something
    /// lends tools to asks for that part of Codex's channel.
    public func begin() throws {
        emit(.options(options()))
        var capabilities: [String: Any] = ["optOutNotificationMethods": CodexDriver.unread]
        if launch.lent != nil { capabilities["experimentalApi"] = true }
        try invoke(.initialize, "initialize", ["clientInfo": ["name": "something", "title": "something", "version": "1.0"], "capabilities": capabilities])
    }

    public func receive(_ line: Data) {
        guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return }
        heard = true
        let params = message["params"] as? [String: Any] ?? [:]
        switch (message["method"] as? String, message["id"]) {
        case (let method?, let id?): request(method, id, params)
        case (let method?, nil): notification(method, params)
        case (nil, let id as Int): response(id, message)
        default: break   // a newer Codex's lines must not break an older something
        }
    }

    /// A new turn starts with turn/start, carrying what `set` asked for. A steer joins the running turn with
    /// turn/steer, which names that turn: Codex refuses a steer meant for a turn that ended.
    public func deliver(_ text: String, steer: Bool) throws {
        guard let thread else { return early.append((text, steer)) }
        if steer {
            guard let turn else { return steers.append(text) }
            return try invoke(.steer(text), "turn/steer", ["threadId": thread, "expectedTurnId": turn, "input": CodexDriver.input(text)])
        }
        var params: [String: Any] = ["threadId": thread, "input": CodexDriver.input(text)]
        params.merge(overrides) { _, new in new }
        let asked = overrides
        overrides = [:]
        try invoke(.start(text, overrides: asked), "turn/start", params)
    }

    /// Sent only while Codex says a turn is active, and never awaited for more than 5 s; steers not sent yet are
    /// dropped, as the interrupt empties something's own queue.
    public func interrupt() throws {
        steers = []
        guard let thread, let turn, active, interruptSent == nil else { return interruptAsked = true }
        interruptAsked = false
        try invoke(.interrupt, "turn/interrupt", ["threadId": thread, "turnId": turn])
        let sent = callsWritten
        schedule(CodexDriver.interruptTimeout) { [weak self] in
            guard let self, interruptSent == sent else { return }
            interruptSent = nil
            emit(.error(AgentError(code: "AGENT_ERROR", message: "Codex did not confirm the interrupt within 5 seconds; it may still be working.")))
        }
        interruptSent = sent
    }

    /// Codex takes a model, an effort and an approval policy with the next turn it starts, so nothing applies now; the
    /// state shows the new values once Codex, having taken that turn, reports them.
    public func set(model: String?, mode: String?, effort: String?) throws -> String {
        for (key, value) in [("model", model), ("approvalPolicy", mode), ("effort", effort)] { if let value { overrides[key] = value } }
        return "next-turn"
    }

    public func prompt(_ request: String) -> Prompt? { asks[request]?.prompt }

    /// A command or a file change is accepted once or declined (the turn goes on, and the model is told). A request
    /// for more permissions takes the permissions granted, not a decision: all of those asked, or none. A question
    /// takes each answer by its question's id; refused, it gets none.
    public func answer(_ request: String, _ answer: Answer) throws -> Bool {
        guard let ask = asks[request] else { return false }
        let questions = ask.prompt.questions
        if case .choice(let chosen) = answer, chosen.count != questions.count {
            throw CodedError("BAD_PARAMS", "Answer each of the \(questions.count) questions, in their order.")
        }
        let reply: [String: Any], allowed: Bool
        switch (ask.method, answer) {
        case ("item/tool/requestUserInput", .choice(let chosen)):
            let answers = Dictionary(zip(ask.questionIDs, chosen.map { ["answers": $0] }), uniquingKeysWith: { first, _ in first })
            reply = ["answers": answers]
            allowed = true
        case ("item/tool/requestUserInput", _):
            reply = ["answers": [String: Any]()]
            allowed = false
        case ("item/permissions/requestApproval", .once):
            reply = ["permissions": ask.params["permissions"] ?? [:], "scope": "turn"]
            allowed = true
        case ("item/permissions/requestApproval", _):
            reply = ["permissions": [String: Any]()]
            allowed = false
        case (_, .once):
            reply = ["decision": "accept"]
            allowed = true
        default:
            reply = ["decision": "decline"]
            allowed = false
        }
        try send(["id": ask.codexID, "result": reply])
        asks[request] = nil
        if let item = ask.params["itemId"] as? String { decide(item, Decision(by: "person", outcome: allowed ? "allowed" : "denied")) }
        emit(.requestClosed(id: request))
        return true
    }

    /// Closing its input is how Codex ends: it exits 0 (V).
    public var goodbye: Data? { nil }

    public func ended(code: Int32, errors: String) {
        guard !over else { return }
        over = true
        guard code != 0 else { return emit(.stopped(nil)) }
        let lines = errors.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !heard { return emit(.stopped(AgentError(code: "LAUNCH_FAILED", message: lines.first.map { "Codex could not start: \($0)" }
            ?? "Codex stopped at once (code \(code))."))) }
        emit(.stopped(AgentError(code: "AGENT_ERROR", message: lines.last.map { "Codex ended: \($0)" } ?? "Codex ended (code \(code)).")))
    }

    // MARK: Codex's lines

    private func response(_ id: Int, _ message: [String: Any]) {
        guard let call = calls.removeValue(forKey: id) else { return }
        let result = message["result"] as? [String: Any] ?? [:]
        if case .interrupt = call, interruptSent == id { interruptSent = nil }   // answered, or refused: the turn ended meanwhile
        if let error = message["error"] as? [String: Any] { return refused(call, error["message"] as? String ?? "") }
        switch call {
        case .initialize:
            if launch.lent != nil, let version = CodexDriver.version(result["userAgent"]),
               version.compare(CodexDriver.lentSince, options: .numeric) == .orderedAscending {
                return notBuilder("This Codex (\(version)) is too old to build spaces: \(CodexDriver.lentSince) or later is needed. Update Codex, then look for agents again.")
            }
            do {
                try send(["method": "initialized"])
                // A resume's settings persist into the thread: only what the person chose is sent.
                var params: [String: Any] = ["cwd": launch.folder]
                if let mode = launch.mode { params["approvalPolicy"] = mode }
                if let model = launch.model { params["model"] = model }
                // The person's assistant changes files in its folder without asking (E-1); what the sandbox blocks asks.
                if launch.assistant == .building { params["sandbox"] = "workspace-write" }
                // Its sandbox reaches no window server, where `something check` loads a page: something runs it instead.
                if let lent = launch.lent, !launch.resume {
                    params["dynamicTools"] = lent.tools.map { ["type": "function", "name": $0.name, "description": $0.description, "inputSchema": $0.schema] }
                }
                if launch.resume {
                    // Its history is left out: a long thread's answer can weigh megabytes.
                    params.merge(["threadId": launch.thread, "excludeTurns": true]) { _, new in new }
                    try invoke(.open, "thread/resume", params)
                } else {
                    try invoke(.open, "thread/start", params)
                }
                try invoke(.models, "model/list", [:])
            } catch {}   // the program stopped reading: its end comes as `ended`
        case .open:
            thread = (result["thread"] as? [String: Any])?["id"] as? String
            emit(.started(pid: nil, thread: thread))
            reported(model: result["model"], mode: result["approvalPolicy"], effort: result["reasoningEffort"])
            let policy = result["approvalPolicy"] as? String
            if launch.mode == nil, overrides["approvalPolicy"] == nil, policy == nil || policy == "never" {
                overrides["approvalPolicy"] = CodexDriver.defaultMode
            }
            let waiting = early
            early = []
            for message in waiting { try? deliver(message.text, steer: message.steer) }
        case .models:
            models = result["data"] as? [[String: Any]]
            emit(.options(options()))
        case .start(_, let asked):
            if turn == nil, let id = (result["turn"] as? [String: Any])?["id"] as? String { running(id) }
            // Codex takes any word for a model or an effort, and says nothing of its settings when it takes a turn
            // (0.163 sends no thread/settings/updated on this channel). Resuming the thread this server holds loads
            // nothing and answers with the settings in force, policy included, which thread/read leaves out.
            if !asked.isEmpty, let thread { try? invoke(.settings, "thread/resume", ["threadId": thread, "excludeTurns": true]) }
        case .settings: reported(model: result["model"], mode: result["approvalPolicy"], effort: result["reasoningEffort"])
        case .steer, .interrupt: break   // a steer's userMessage item shows it; an interrupt's turn/completed ends the turn
        }
    }

    /// What frees a conversation Codex's background service holds.
    static let heldByService = "Codex's background service holds this conversation; run `codex app-server daemon stop` in a terminal, then try again."

    /// Codex refused a call; each says what became of what was asked.
    private func refused(_ call: Call, _ words: String) {
        switch call {
        case .initialize, .open:
            // The tools went with this thread/start: whatever Codex says, they may be why (a later Codex may name
            // them otherwise, and one that started without them would ask to run each check outside its sandbox).
            if launch.lent != nil, !launch.resume {
                return notBuilder("This Codex did not accept something's check tool, so it can't build spaces. It said: “\(words)”.")
            }
            let held = words.contains("active writer"), missing = words.contains("no rollout found") || words.contains("invalid session id")
            // The messages held for the thread, steers answered "steered" among them, are said lost, never dropped unsaid.
            let lost = early.isEmpty ? "" : "; the \(early.count == 1 ? "message" : "\(early.count) messages") sent to it went nowhere"
            let error = held ? AgentError(code: "HELD_ELSEWHERE", message: CodexDriver.heldByService + lost)
                : missing ? AgentError(code: "THREAD_NOT_FOUND", message: "Codex has no conversation \(launch.thread) on this Mac" + lost + ".")
                : AgentError(code: "AGENT_ERROR", message: "Codex refused to start the conversation: \(words)" + lost)
            over = true
            emit(.stopped(error))
            quit()
        case .settings: rereadSettings = true
        case .models, .interrupt: break   // the values stay as last known; turn/completed says how the turn ended
        case .start(let text, _):
            // The turn this message opened never started on Codex's side: what was held for it goes with it, and
            // the steers answered "steered" while they waited for its id are said lost, never silently dropped.
            let lost = steers.isEmpty ? "" : "; the \(steers.count == 1 ? "message" : "\(steers.count) messages") steered into it went nowhere either"
            reset()
            emit(.turnEnded(.failed(AgentError(code: "AGENT_ERROR", message: "Codex refused the message “\(Launched.short(text))”: \(words)" + lost))))
        case .steer(let text):
            emit(.error(AgentError(code: "AGENT_ERROR", message: "Codex did not take the message “\(Launched.short(text))”: \(words)")))
        }
    }

    private func notification(_ method: String, _ params: [String: Any]) {
        guard params["threadId"] == nil || params["threadId"] as? String == thread else { return }
        switch method {
        case "thread/status/changed":
            active = (params["status"] as? [String: Any])?["type"] as? String == "active"
            flush()
        case "turn/started":
            if let id = (params["turn"] as? [String: Any])?["id"] as? String { running(id) }
            active = true
            flush()
        case "turn/completed": completed(params["turn"] as? [String: Any] ?? [:])
        case "item/started": item(params["item"] as? [String: Any] ?? [:], done: false)
        case "item/completed": item(params["item"] as? [String: Any] ?? [:], done: true)
        case "serverRequest/resolved":
            // Resolved without our answer: Codex withdrew it (the turn ended first).
            guard let id = params["requestId"], asks.removeValue(forKey: self.id(id)) != nil else { return }
            emit(.requestClosed(id: self.id(id)))
        case "error" where params["willRetry"] as? Bool != true && params["turnId"] == nil:
            // An error of a turn comes again with turn/completed; this one belongs to no turn.
            emit(.error(AgentError(code: "AGENT_ERROR", message: (params["error"] as? [String: Any])?["message"] as? String ?? "Codex reported an error.")))
        default: break
        }
    }

    /// Codex cannot take what something lends it, as the sentence `because` says: the launch ends, the app is told,
    /// and the messages held for the thread are said lost.
    private func notBuilder(_ because: String) {
        let lost = early.isEmpty ? "" : " The \(early.count == 1 ? "message" : "\(early.count) messages") sent to it went nowhere."
        over = true
        emit(.stopped(AgentError(code: "AGENT_ERROR", message: because + lost)))
        quit()
        launch.lent?.refused(AgentDescriptor.codex.kind, because)
    }

    /// One of the tools something lends: it runs off the main queue, and its report goes back as the tool's result.
    private func lentCall(_ codexID: Any, _ params: [String: Any]) {
        guard let lent = launch.lent else {
            try? send(["id": codexID, "error": ["code": -32601, "message": "something lends no tool to this conversation."]])
            return
        }
        tookLent = true
        lent.call(params["tool"] as? String ?? "", params["arguments"]) { [weak self] reply in
            try? self?.send(["id": codexID, "result": ["success": reply.ok, "contentItems": [["type": "inputText", "text": reply.text]]]])
        }
    }

    private func request(_ method: String, _ codexID: Any, _ params: [String: Any]) {
        if method == "item/tool/call" { return lentCall(codexID, params) }
        let shownID = id(codexID)
        let kind: String
        var about: String?, input: String?, questions: [Question] = [], questionIDs: [String] = []
        switch method {
        case "item/commandExecution/requestApproval":
            // Asked to run a check outside the sandbox before calling the one something lends: this Codex has not
            // got the tool (its channel changed), and would ask at every check.
            if launch.lent != nil, !tookLent, (params["command"] as? String)?.contains("something check") == true {
                return notBuilder("This Codex did not use something's check tool, so it can't build spaces.")
            }
            kind = "commandExecution"
            about = params["command"] as? String ?? params["reason"] as? String
            input = params["command"] as? String
        case "item/fileChange/requestApproval":
            kind = "fileChange"
            let changes = started[params["itemId"] as? String ?? ""]?["changes"] as? [[String: Any]] ?? []
            about = changes.compactMap { $0["path"] as? String }.joined(separator: ", ")
            input = changes.compactMap { $0["diff"] as? String }.joined(separator: "\n")
            if about?.isEmpty != false { about = params["reason"] as? String }
        case "item/permissions/requestApproval":
            kind = "permissions"
            about = params["reason"] as? String
            input = CodexDriver.json(params["permissions"])
        case "item/tool/requestUserInput":
            kind = "requestUserInput"
            // A question without an id or a text cannot be answered: it is left out, and so is its answer.
            let shown = (params["questions"] as? [[String: Any]] ?? []).compactMap { question -> (String, Question)? in
                guard let id = question["id"] as? String, let text = question["question"] as? String else { return nil }
                let options = (question["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String }
                return (id, Question(header: question["header"] as? String, text: text, options: options, multiple: false))
            }
            questionIDs = shown.map(\.0)
            questions = shown.map(\.1)
            about = questions.first?.text
        default:
            // Codex waits for every request it sends: one something does not handle gets a refusal, not silence.
            try? send(["id": codexID, "error": ["code": -32601, "message": "something does not handle \(method)."]])
            return
        }
        let shown = Request(id: shownID, agent: launch.agent, kind: questions.isEmpty ? "permission" : "question", tool: kind, about: about, at: now())
        asks[shownID] = Ask(codexID: codexID, method: method, params: params, prompt: Prompt(request: shown, input: input, questions: questions),
                            questionIDs: questionIDs)
        emit(.requestOpened(shown))
    }

    /// The turn ended: what it left open closes with it. An item cut by a steer or an interrupt never completes, and
    /// a request still open when the turn was interrupted is withdrawn (Codex's serverRequest/resolved comes after).
    private func completed(_ ended: [String: Any]) {
        for (id, var item) in tools {
            item.tool?.status = nil
            emit(.itemUpdated(item))
            tools[id] = nil
        }
        for id in asks.keys.sorted() {
            asks[id] = nil
            emit(.requestClosed(id: id))
        }
        reset()
        if rereadSettings, let thread {
            rereadSettings = false
            try? invoke(.settings, "thread/resume", ["threadId": thread, "excludeTurns": true])
        }
        switch ended["status"] as? String {
        case "interrupted": emit(.turnEnded(.interrupted))
        case "failed":
            let words = (ended["error"] as? [String: Any])?["message"] as? String
            emit(.turnEnded(.failed(AgentError(code: "AGENT_ERROR", message: words ?? "Codex ended its turn with an error."))))
        default: emit(.turnEnded(.done))
        }
    }

    private func item(_ item: [String: Any], done: Bool) {
        guard let id = item["id"] as? String, let type = item["type"] as? String else { return }
        if !done { started[id] = item }
        switch type {
        case "userMessage":
            let text = (item["content"] as? [[String: Any]] ?? []).compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
            if done { emit(.itemAppended(Item(id: id, kind: "message", author: "person", text: text, at: now()))) }
        case "agentMessage":
            // Every message is shown, "commentary" ones too: about half of a real turn's messages.
            if done, let text = item["text"] as? String, !text.isEmpty { emit(.itemAppended(Item(id: id, kind: "message", author: "agent", text: text, at: now()))) }
        case "reasoning":
            let summary = (item["summary"] as? [String] ?? []).joined(separator: "\n")
            let text = summary.isEmpty ? (item["content"] as? [String] ?? []).joined(separator: "\n") : summary
            if done, !text.isEmpty { emit(.itemAppended(Item(id: id, kind: "thought", author: "agent", text: text, at: now()))) }
        default:
            guard let (name, words) = CodexDriver.tool(item) else { return }
            var text = words
            // A lent tool is shown as the command something ran for it.
            if type == "dynamicToolCall", let tool = launch.lent?.tools.first(where: { $0.name == name }) {
                text = tool.words(item["arguments"] as? [String: Any] ?? [:]).map { (["something"] + $0).joined(separator: " ") } ?? "\(name) (wrong arguments)"
            }
            let status = ["inProgress": "running", "completed": "done", "failed": "failed", "declined": "failed"][item["status"] as? String ?? ""]
            let shown = Item(id: id, kind: "tool", author: "agent", text: text, at: tools[id]?.at ?? now(),
                             tool: Tool(name: name, status: done ? status ?? "done" : status), decision: decisions[id])
            emit(tools[id] == nil ? .itemAppended(shown) : .itemUpdated(shown))
            tools[id] = done ? nil : shown
            if done { decisions[id] = nil }
        }
    }

    // MARK: Helpers

    /// Forgets what belonged to the turn that ended, or to the one Codex refused to start.
    private func reset() {
        turn = nil
        active = false
        interruptAsked = false
        interruptSent = nil
        steers = []
        decisions = [:]
        started = [:]
    }

    /// The running turn is `id`: a steer or an interrupt asked before its id was known goes out now.
    private func running(_ id: String) {
        guard turn != id else { return }
        turn = id
        emit(.turnStarted(id: id))
        flush()
    }

    private func flush() {
        guard turn != nil else { return }
        let waiting = steers
        steers = []
        for text in waiting { try? deliver(text, steer: true) }
        if interruptAsked && active { try? interrupt() }
    }

    private func decide(_ item: String, _ decision: Decision) {
        decisions[item] = decision
        guard var shown = tools[item] else { return }
        shown.decision = decision
        tools[item] = shown
        emit(.itemUpdated(shown))
    }

    /// Codex's approval policy is a word, or a set of rules something shows as "granular"; anything else is unknown.
    private func reported(model: Any?, mode: Any?, effort: Any?) {
        let mode = mode as? String ?? (mode is [String: Any] ? "granular" : nil)
        emit(.reported(model: model as? String, mode: mode, effort: effort as? String))
        if let model = model as? String, model != self.model {
            self.model = model
            if models != nil { emit(.options(options())) }
        }
    }

    private func id(_ codexID: Any) -> String { "\(launch.agent):\(codexID)" }

    /// The models model/list gave (it reads Codex's own catalog, offline), and the efforts of the one in use; nil
    /// until known, and for a model the catalog does not list.
    private func options() -> Options {
        var options = Options()
        options.mode = Driving.codex.modes
        let shown = models?.filter { $0["hidden"] as? Bool != true }
        options.model = shown?.compactMap { entry in (entry["model"] as? String).map { Option(value: $0, label: entry["displayName"] as? String ?? $0) } }
        let entry = models?.first { $0["model"] as? String == model || $0["id"] as? String == model }
        options.effort = (entry?["supportedReasoningEfforts"] as? [[String: Any]])?.compactMap { effort in
            (effort["reasoningEffort"] as? String).map { Option(value: $0, label: ClaudeDriver.effortLabels[$0] ?? $0) }
        }
        return options
    }

    private func invoke(_ call: Call, _ method: String, _ params: [String: Any]) throws {
        callsWritten += 1
        calls[callsWritten] = call
        try send(["id": callsWritten, "method": method, "params": params])
    }

    /// Lines are built from structures, never by joining strings.
    private func send(_ object: [String: Any]) throws {
        try write(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]))
    }

    /// The notifications something never reads: the deltas of items it reads whole, and the account's counters.
    static let unread = ["item/agentMessage/delta", "item/reasoning/textDelta", "item/reasoning/summaryTextDelta",
                         "item/commandExecution/outputDelta", "item/fileChange/outputDelta", "account/rateLimits/updated",
                         "thread/tokenUsage/updated"]

    static func input(_ text: String) -> [[String: Any]] { [["type": "text", "text": text, "text_elements": [Any]()]] }

    /// A tool item's name and one line for it; nil for an item that is no tool.
    static func tool(_ item: [String: Any]) -> (String, String)? {
        switch item["type"] as? String {
        case "commandExecution": return ("commandExecution", item["command"] as? String ?? "")
        case "fileChange": return ("fileChange", (item["changes"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }.joined(separator: ", "))
        case "mcpToolCall": return ("\(item["server"] as? String ?? "mcp")/\(item["tool"] as? String ?? "tool")", json(item["arguments"]) ?? "")
        case "dynamicToolCall": return (item["tool"] as? String ?? "tool", json(item["arguments"]) ?? "")
        case "webSearch": return ("webSearch", item["query"] as? String ?? "")
        case "collabAgentToolCall": return (item["tool"] as? String ?? "agent", item["prompt"] as? String ?? "")
        default: return nil
        }
    }

    /// Codex's version in its user agent ("<client>/0.163.0 (Mac OS …) …"); nil when it is not there.
    static func version(_ agent: Any?) -> String? {
        guard let agent = agent as? String, let slash = agent.firstIndex(of: "/") else { return nil }
        let version = agent[agent.index(after: slash)...].prefix { $0.isNumber || $0 == "." }
        return version.isEmpty ? nil : String(version)
    }

    static func json(_ value: Any?) -> String? {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]) else {
            return value as? String
        }
        return String(decoding: data, as: UTF8.self)
    }
}

extension Driving {
    /// None of `limits`: Codex takes a model, an effort and an approval policy with each turn it starts. The modes are
    /// the approval policies 0.163 accepts ("on-failure" is gone). A model the catalog does not list (a custom
    /// provider's) offers no effort, and Codex would take any word. Codex names the thread when it starts it.
    static let codex = Driving(kind: "codex", tested: "0.163.0",
                               modes: [Option(value: "on-request", label: "Ask when needed"),
                                       Option(value: "untrusted", label: "Ask before most commands"),
                                       Option(value: "never", label: "Never ask (refuse what is not allowed)")],
                               effortOnlyWhenOffered: true, picksThread: false,
                               command: { CodexDriver.command($0) }, driver: { CodexDriver($0, write: $1, emit: $2, now: $3) })
}
