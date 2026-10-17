// ACPDriver: OpenCode launched by something, through `opencode acp`: the Agent Client Protocol (ACP), JSON-RPC 2.0,
// one object per line on its input and output. Each launch is its own `opencode acp`, with its own private server,
// holding one conversation (a "session") in OpenCode's shared database. It turns OpenCode's raw words into neutral
// events (design 3.2): a session/prompt waiting for its answer is an open turn, the answer's stopReason ends it, and
// session/request_permission is a permission. What each choice rests on (notes, channel-opencode, and trial T-3 on
// 2.0.20) is said where it is made.
import Foundation
import SQLite3
import SomethingCore

public final class ACPDriver: Driver {
    public static let kind = "opencode"
    public static let tested = "2.0.20"
    /// Over ACP a second session/prompt during a turn is refused ("Session already has an active ACP prompt"), and
    /// OpenCode has no steer there (D3): a message for later waits in something's own queue.
    public static let limits = ["steer": "OpenCode cannot take a message during a turn; send it with when: \"next\"."]
    /// OpenCode names the session when it starts it.
    public static let picksThread = false
    /// OpenCode offers an effort only for a model that has variants.
    public static let effortOnlyWhenOffered = true
    /// OpenCode's modes are its agents; these two come with it. Others the person wrote show in `options.mode` once
    /// OpenCode lists them, and a space may choose them with `set`, after the person confirmed (Engine.lowersAsking).
    public static let modes = [Option(value: "build", label: "Build"), Option(value: "plan", label: "Plan")]

    /// Nothing else on the line: model, mode and effort go through the channel, where OpenCode says what it took.
    public static func command(_ launch: Launch) -> Command { Command(arguments: ["acp"]) }

    /// The sentence for a conversation OpenCode left marked as running (design 4.1, OPENCODE_CLAIM_LEFT).
    static func claimLeft(_ session: String) -> String {
        "OpenCode ended during a turn and left its conversation \(session) marked as running: the next time OpenCode's background service starts, it may continue that turn by itself. Open the conversation in OpenCode to finish or stop it."
    }

    static let questionDismissed = "OpenCode tried to ask you a question, but when something launches it, OpenCode cannot show questions. Ask it to write its question in its reply instead."

    static let noAllowOnce = "OpenCode offered no one-time allow for this request, and something never allows always: it was refused."

    private let launch: Launch
    private let write: (Data) throws -> Void
    private let emit: (AgentEvent) -> Void
    private let now: () -> String
    /// Calls something made and OpenCode has not answered yet, by request id.
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
    /// The text so far of each message OpenCode streams, by its messageId.
    private var texts: [String: String] = [:]
    /// Whether OpenCode wrote any line, which tells a failed start from a later end.
    private var heard = false
    /// Whether the end was already said.
    private var over = false
    /// Messages handed over so far, which names their items.
    private var sent = 0
    /// Where OpenCode keeps its sessions, from the launch's environment; nil when unknown.
    var database: String?
    /// Closes the program's input, after which OpenCode exits: set by the engine, used when the launch cannot go on.
    var quit: () -> Void = {}
    /// Whether a session/prompt waits for its answer. The stop ladder reads it from its own thread.
    public var prompting: Bool { lock.withLock { pending } }
    private let lock = NSLock()
    private var pending = false

    private enum Call { case initialize, open, set(key: String, value: String), prompt(String) }

    private struct Ask { var rpcID: Any, options: [[String: Any]], tool: String?, prompt: Prompt }

    public init(_ launch: Launch, write: @escaping (Data) throws -> Void, emit: @escaping (AgentEvent) -> Void, now: @escaping () -> String) {
        self.launch = launch
        self.write = write
        self.emit = emit
        self.now = now
        // The mode first, since an agent may bring its own model; the effort last, since the model decides the levels.
        settings = [("mode", launch.mode), ("model", launch.model), ("effort", launch.effort)].compactMap { key, value in value.map { (key, $0) } }
    }

    /// something reads no file and runs no terminal for OpenCode: it does both itself.
    public func begin() throws {
        try invoke(.initialize, "initialize", ["protocolVersion": 1, "clientCapabilities": ["fs": ["readTextFile": false, "writeTextFile": false], "terminal": false]])
    }

    public func receive(_ line: Data) {
        guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return }
        heard = true
        let params = message["params"] as? [String: Any] ?? [:]
        switch (message["method"] as? String, message["id"]) {
        case (let method?, let id?): request(method, id, params)
        case ("session/update"?, nil) where params["sessionId"] as? String == session: update(params["update"] as? [String: Any] ?? [:])
        case (nil, let id as Int): response(id, message)
        default: break   // a newer OpenCode's lines must not break an older something
        }
    }

    /// A message starts a turn; it goes out once the session and the settings asked before it are in place.
    /// Throws NOT_SUPPORTED for a steer, which OpenCode refuses (`limits`), and AGENT_STOPPED.
    public func deliver(_ text: String, steer: Bool) throws {
        guard !steer else { throw CodedError("NOT_SUPPORTED", ACPDriver.limits["steer"]!) }
        sent += 1
        emit(.turnStarted(id: nil))
        emit(.itemAppended(Item(id: "\(launch.agent)/sent\(sent)", kind: "message", author: "person", text: text, at: now())))
        early.append(text)
        try flush()
    }

    /// session/cancel stops the running prompt, whose answer then says "cancelled"; a request still open is
    /// answered "cancelled", as ACP asks. A message not sent yet is dropped and its turn ends here.
    public func interrupt() throws {
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

    /// Each value goes out with session/set_config_option, one at a time; OpenCode answers with all its options, and
    /// the state shows what it took (it may keep another model when its catalog was not ready, notes 5.1). A turn
    /// that runs keeps the values it started with.
    public func set(model: String?, mode: String?, effort: String?) throws -> String {
        settings += [("mode", mode), ("model", model), ("effort", effort)].compactMap { key, value in value.map { (key, $0) } }
        try nextSetting()
        return prompting ? "next-turn" : "now"
    }

    public func prompt(_ request: String) -> Prompt? { asks[request]?.prompt }

    /// Allow and deny pick OpenCode's own once-only options by their kind, never "always", which would write a lasting
    /// rule into OpenCode; a request without them is answered "cancelled", which OpenCode takes as a refusal. The
    /// decision shown is the one sent: an allow that could not be sent is a refusal, and the agent's error says why.
    public func answer(_ request: String, _ answer: Answer) throws -> Bool {
        guard let ask = asks[request] else { return false }
        let kind = answer == .once ? "allow_once" : "reject_once"
        let option = ask.options.first { $0["kind"] as? String == kind }?["optionId"] as? String
        try send(["id": ask.rpcID, "result": ["outcome": option.map { ["outcome": "selected", "optionId": $0] } ?? ["outcome": "cancelled"]]])
        asks[request] = nil
        let allowed = answer == .once && option != nil
        if answer == .once, !allowed { emit(.error(AgentError(code: "AGENT_ERROR", message: ACPDriver.noAllowOnce))) }
        if let tool = ask.tool { decide(tool, Decision(by: "person", outcome: allowed ? "allowed" : "denied")) }
        emit(.requestClosed(id: request))
        return true
    }

    /// The first step of the ladder is the engine's: an interrupt and its answer, then the input closed (OpenCode
    /// exits 0 at its end); never a signal first, which leaves the conversation marked as running.
    public var goodbye: Data? { nil }

    /// An end nobody asked for. A claim left behind is said in the same error, after how OpenCode ended.
    public func ended(code: Int32, errors: String) {
        guard !over else { return }
        over = true
        let claim = leftClaim()
        guard code != 0 else { return emit(.stopped(claim.map { AgentError(code: "AGENT_ERROR", message: $0) })) }
        let lines = errors.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !heard { return emit(.stopped(AgentError(code: "LAUNCH_FAILED", message: lines.first.map { "OpenCode could not start: \($0)" }
            ?? "OpenCode stopped at once (code \(code))."))) }
        let end = lines.last.map { "OpenCode ended: \($0)" } ?? "OpenCode ended (code \(code))."
        emit(.stopped(AgentError(code: "AGENT_ERROR", message: claim.map { "\(end) \($0)" } ?? end)))
    }

    /// After a stop something asked for, which is folded without `ended`: a claim left behind (the ladder ran out of
    /// time before the cancel was answered) becomes the agent's error.
    func checkClaim() {
        guard !over, let claim = leftClaim() else { return }
        emit(.error(AgentError(code: "AGENT_ERROR", message: claim)))
    }

    /// The claim sentence, when one of something's own turns was still open at the end and OpenCode's database still
    /// marks the conversation as running; nil otherwise, and when the database cannot be read. A turn OpenCode
    /// answered, done or cancelled, released its claim (T-3); a claim no open turn of something's took (an earlier
    /// crash, the person's own OpenCode on the same conversation) is not something's to report.
    private func leftClaim() -> String? {
        guard prompting, let session, let database, ACPDriver.claimed(session, in: database) == true else { return nil }
        return ACPDriver.claimLeft(session)
    }

    // MARK: OpenCode's lines

    private func response(_ id: Int, _ message: [String: Any]) {
        guard let call = calls.removeValue(forKey: id) else { return }
        let result = message["result"] as? [String: Any] ?? [:]
        let error = message["error"] as? [String: Any]
        let words = ACPDriver.words(error)
        switch call {
        case .initialize:
            if error != nil { return refused(AgentError(code: "LAUNCH_FAILED", message: "OpenCode refused to start: \(words)")) }
            var params: [String: Any] = ["cwd": launch.folder, "mcpServers": [Any]()]
            if launch.resume { params["sessionId"] = launch.thread }
            try? invoke(.open, launch.resume ? "session/resume" : "session/new", params)
        case .open:
            if error != nil {
                let missing = words.contains("session not found") || words.contains("does not belong to cwd")
                return refused(missing ? AgentError(code: "THREAD_NOT_FOUND", message: "OpenCode has no conversation \(launch.thread) in \(launch.folder) on this Mac.")
                    : AgentError(code: "AGENT_ERROR", message: "OpenCode refused to start the conversation: \(words). If it has no model yet, run `opencode auth login` in a terminal."))
            }
            session = launch.resume ? launch.thread : result["sessionId"] as? String
            emit(.started(pid: nil, thread: session))
            read(result["configOptions"])
            try? flush()
        case .set(let key, let value):
            setting = false
            if error != nil {
                emit(.error(AgentError(code: "VALUE_NOT_OFFERED", message: "OpenCode refused \(value) as its \(key): \(words)")))
            } else if let options = result["configOptions"] as? [[String: Any]] {
                read(options)
                let taken = options.first { $0["id"] as? String == key }?["currentValue"] as? String
                if taken != value { emit(.error(AgentError(code: "VALUE_NOT_OFFERED", message: "OpenCode kept \(taken ?? "no value") as its \(key), not \(value)."))) }
            }
            try? flush()
        case .prompt(let text):
            lock.withLock { pending = false }
            forgetTurn()
            let cancelled = cancelAsked
            cancelAsked = false
            if error != nil {
                return emit(.turnEnded(.failed(AgentError(code: "AGENT_ERROR", message: ACPDriver.failure(error, words, text)))))
            }
            switch result["stopReason"] as? String {
            // OpenCode also ends a turn "cancelled" by itself after a refused permission or a dismissed question
            // (T-3): only something's own cancel makes it an interrupt.
            case "cancelled" where cancelled: emit(.turnEnded(.interrupted))
            case "max_tokens": emit(.turnEnded(.failed(AgentError(code: "AGENT_ERROR", message: "OpenCode's model reached its output limit before the end of its answer."))))
            case "refusal": emit(.turnEnded(.failed(AgentError(code: "AGENT_ERROR", message: "OpenCode's model refused to answer."))))
            default: emit(.turnEnded(.done))
            }
        }
    }

    /// The launch cannot go on: the agent ends with `error`, and OpenCode is told to end.
    private func refused(_ error: AgentError) {
        over = true
        emit(.stopped(error))
        quit()
    }

    private func request(_ method: String, _ rpcID: Any, _ params: [String: Any]) {
        guard method == "session/request_permission", params["sessionId"] as? String == session else {
            // OpenCode waits for every request it sends: one something does not handle gets a refusal, not silence.
            try? send(["id": rpcID, "error": ["code": -32601, "message": "something does not handle \(method)."]])
            return
        }
        let call = params["toolCall"] as? [String: Any] ?? [:]
        let tool = call["toolCallId"] as? String
        let input = call["rawInput"] as? [String: Any]
        let shown = Request(id: "\(launch.agent):\(rpcID)", agent: launch.agent, kind: "permission",
                            tool: tool.flatMap { names[$0] } ?? call["kind"] as? String, about: call["title"] as? String, at: now())
        asks[shown.id] = Ask(rpcID: rpcID, options: params["options"] as? [[String: Any]] ?? [], tool: tool,
                             prompt: Prompt(request: shown, input: input?["command"] as? String ?? CodexDriver.json(input)))
        emit(.requestOpened(shown))
    }

    private func update(_ update: [String: Any]) {
        // A sub-agent's updates come into its parent's stream, marked only by this key (notes 6.3).
        let child = (update["_meta"] as? [String: Any])?["opencode/child-session"] != nil
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
            if done, item.tool?.name == "question" { emit(.error(AgentError(code: "AGENT_ERROR", message: ACPDriver.questionDismissed))) }
        case "config_option_update": read(update["configOptions"])   // sent from 2.0.25 on
        default: break   // commands, usage, retries: nothing the state shows
        }
    }

    // MARK: Helpers

    /// What a turn streamed belongs to it: a tool cut by its end never finishes, and the next turn names new
    /// messages and tool calls.
    private func forgetTurn() {
        for (id, var item) in tools {
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
        try invoke(.set(key: key, value: value), "session/set_config_option", ["sessionId": session, "configId": key, "value": value])
    }

    /// OpenCode's options for the session: the values in use and those offered, by their category. Each list OpenCode
    /// sends is complete, so a value it no longer lists is none: an effort is dropped with a model without variants.
    private func read(_ list: Any?) {
        guard let list = list as? [[String: Any]] else { return }
        func entry(_ category: String) -> [String: Any]? { list.first { $0["category"] as? String == category } }
        func choices(_ entry: [String: Any]?) -> [Option]? {
            (entry?["options"] as? [[String: Any]])?.compactMap { option in
                (option["value"] as? String).map { Option(value: $0, label: option["name"] as? String ?? $0) }
            }
        }
        var options = Options()
        options.model = choices(entry("model"))
        options.mode = choices(entry("mode"))
        options.effort = choices(entry("thought_level"))
        emit(.options(options))
        emit(.settings(model: entry("model")?["currentValue"] as? String, mode: entry("mode")?["currentValue"] as? String,
                       effort: entry("thought_level")?["currentValue"] as? String))
    }

    private func decide(_ tool: String, _ decision: Decision) {
        decisions[tool] = decision
        guard var shown = tools[tool] else { return }
        shown.decision = decision
        tools[tool] = shown
        emit(.itemUpdated(shown))
    }

    /// OpenCode's words for an error, without the prefix its library adds ("Invalid params: ", "Internal error: ").
    static func words(_ error: [String: Any]?) -> String {
        let words = error?["message"] as? String ?? "no reason given"
        for prefix in ["Invalid params: ", "Internal error: "] where words.hasPrefix(prefix) { return String(words.dropFirst(prefix.count)) }
        return words
    }

    /// A failed turn in words a newcomer can act on; OpenCode's own words otherwise.
    static func failure(_ error: [String: Any]?, _ words: String, _ text: String) -> String {
        if error?["code"] as? Int == -32000 || words.contains("authentication required") {
            return "OpenCode cannot reach its model: run `opencode auth login` in a terminal, then send the message again."
        }
        return "OpenCode did not finish the message “\(Launched.short(text))”: \(words)"
    }

    /// Where OpenCode keeps its sessions for the environment it runs in: $OPENCODE_DB, else opencode.db in its data
    /// folder. A channel other than the default one names its own file, which something does not guess.
    static func database(_ environment: [String: String]) -> String? {
        if let path = environment["OPENCODE_DB"], path.hasPrefix("/") { return path }
        guard let data = environment["XDG_DATA_HOME"].flatMap({ $0.hasPrefix("/") ? $0 : nil }) ?? environment["HOME"].map({ "\($0)/.local/share" }) else { return nil }
        return "\(data)/opencode/opencode.db"
    }

    /// Whether OpenCode's database marks `session` as running (`time_suspended` set: the claim a run takes and
    /// releases at its end); nil when the database or the session cannot be read. Read only, never written.
    /// TODO(slice 17): move onto SQLiteRO and the OpenCode reader's claim query, behind its schema guard, so that one
    /// reader of session_v2 remains and a schema change is said rather than silently read as "unknown".
    static func claimed(_ session: String, in path: String) -> Bool? {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        var row: OpaquePointer?
        defer { sqlite3_finalize(row) }
        guard sqlite3_prepare_v2(db, "SELECT time_suspended IS NOT NULL FROM session_v2 WHERE id = ?", -1, &row, nil) == SQLITE_OK,
              sqlite3_bind_text(row, 1, session, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK,
              sqlite3_step(row) == SQLITE_ROW else { return nil }
        return sqlite3_column_int(row, 0) != 0
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
