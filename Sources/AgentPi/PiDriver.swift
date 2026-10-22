// PiDriver: pi launched by something, through `pi --mode rpc`, its official channel: one JSON object per line on its
// input and output. A command carries an id and gets one `response` line that repeats it; events carry none. pi
// never asks the person anything: it runs commands and edits files without asking first, and has no modes. It turns
// pi's raw words into neutral events: agent_start and agent_settled into turns, the last assistant
// message's stopReason into the outcome. What each choice rests on is said where it is made.
import Foundation
import SomethingAgents
import SomethingCore

final class PiDriver: Driver {
    /// A resume continues the conversation file `launch.thread`, which the engine checked first (`resumable`): pi
    /// given a missing file starts an empty conversation at that path instead of refusing.
    static func command(_ launch: Launch) -> Command {
        var arguments = ["--mode", "rpc"]
        if let model = launch.model { arguments += ["--model", model] }
        if let effort = launch.effort { arguments += ["--thinking", effort] }
        if launch.resume { arguments += ["--session", launch.thread] }
        return Command(arguments: arguments)
    }

    /// Returns the folder a resume of the conversation file `file` runs in: the `cwd` of its header line, which a
    /// resumed pi uses whatever folder it was started in (V). Throws THREAD_NOT_FOUND unless `file` is an absolute
    /// path to a pi conversation, which pi writes at the first message. Only the header line is read.
    static func resumable(_ file: String) throws -> String {
        let missing = CodedError("THREAD_NOT_FOUND", "pi has no saved conversation with this id on this Mac.")
        guard file.hasPrefix("/"), let handle = FileHandle(forReadingAtPath: file) else { throw missing }
        defer { try? handle.close() }
        let start = (try? handle.read(upToCount: 64 * 1024)) ?? nil
        guard let header = start?.split(separator: UInt8(ascii: "\n"), maxSplits: 1, omittingEmptySubsequences: false).first,
              let entry = (try? JSONSerialization.jsonObject(with: Data(header))) as? [String: Any],
              entry["type"] as? String == "session", let folder = entry["cwd"] as? String, folder.hasPrefix("/")
        else { throw missing }
        return folder
    }

    private let launch: Launch
    private let write: (Data) throws -> Void
    private let emit: (AgentEvent) -> Void
    private let now: () -> String
    /// Commands something sent and pi has not answered yet, by id.
    private var calls: [String: Call] = [:]
    private var callsWritten = 0
    private var thread: String?
    /// True from agent_start until agent_settled: retries, compaction and queued messages come between agent_end and
    /// agent_settled, and only agent_settled means nothing more happens on its own.
    private var running = false
    /// An interrupt asked before the run started.
    private var abortAsked = false
    /// An abort sent whose run has not settled yet.
    private var aborting = false
    /// The last assistant message's stopReason, which says how the run ended.
    private var stop: String?
    /// The last assistant message's error, or a failed retry's.
    private var stopError: String?
    /// Tool runs not finished yet, by pi's toolCallId.
    private var tools: [String: Item] = [:]
    /// The models pi has a key for, as get_available_models gives them; nil until it answered.
    private var models: [[String: Any]]?
    /// The thinking levels of the model in use; nil until pi said.
    private var levels: [String]?
    /// The model in force, "provider/id", as get_state last reported it.
    private var model: String?
    /// Values `set` asked for and not sent yet, sent one at a time: set_model may change the thinking level, so the
    /// level goes after it.
    private var unsent: [(key: String, value: String)] = []
    /// Values sent, which get_state reads back once none is left to send.
    private var sent: [(key: String, value: String)] = []
    /// How many items this agent showed, for their ids.
    private var count = 0
    /// True once pi wrote a line: a launch that fails writes none.
    private var heard = false
    /// True once the program's end was told.
    private var over = false

    private enum Call {
        case state, models, levels
        case prompt(String), steer(String)
        case set(String, String)
        case readBack([(key: String, value: String)])
        case clearQueue, abort
    }

    /// True while a set_model or set_thinking_level waits for its answer.
    private var setting: Bool { calls.values.contains { if case .set = $0 { true } else { false } } }

    init(_ launch: Launch, write: @escaping (Data) throws -> Void, emit: @escaping (AgentEvent) -> Void, now: @escaping () -> String) {
        (self.launch, self.write, self.emit, self.now) = (launch, write, emit, now)
    }

    /// pi writes nothing before a command (V): get_state names the conversation and the values in force.
    func begin() throws {
        emit(.options(options()))
        try invoke(.state, ["type": "get_state"])
        try invoke(.models, ["type": "get_available_models"])
        try invoke(.levels, ["type": "get_available_thinking_levels"])
    }

    @discardableResult func receive(_ line: Data) -> Bool {
        guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], let type = message["type"] as? String else { return false }
        heard = true
        switch type {
        case "response": response(message)
        case "agent_start": started()
        case "agent_settled": settled()
        case "message_end": ended(message["message"] as? [String: Any] ?? [:])
        case "tool_execution_start", "tool_execution_end": tool(message, done: type == "tool_execution_end")
        case "auto_retry_end" where message["success"] as? Bool == false:
            stop = "error"
            stopError = message["finalError"] as? String ?? stopError
        case "extension_error": emit(.error(AgentError(code: "AGENT_ERROR", message: "A pi extension failed: \(message["error"] as? String ?? "no reason given").")))
        case "extension_ui_request": dialog(message)
        default: return false   // a newer pi's lines must not break an older something
        }
        return true
    }

    /// A new turn is a plain prompt. A steer is a prompt with streamingBehavior "steer": pi delivers it after the
    /// running step's tool calls, before its next model call; on an idle pi it starts a run, where the steer command
    /// would only queue it (V).
    func deliver(_ text: String, steer: Bool) throws {
        if steer { return try invoke(.steer(text), ["type": "prompt", "message": text, "streamingBehavior": "steer"]) }
        try invoke(.prompt(text), ["type": "prompt", "message": text])
    }

    /// Queued messages survive pi's abort and would go with the next prompt (V): clear_queue goes first. An abort
    /// asked before the run started is sent when it starts.
    func interrupt() throws {
        try invoke(.clearQueue, ["type": "clear_queue"])
        guard running else { return abortAsked = true }
        aborting = true
        try invoke(.abort, ["type": "abort"])
    }

    /// pi applies a model and a thinking level at once; the state shows them once get_state reads them back. Throws
    /// NOT_SUPPORTED for a mode (`limits`), VALUE_NOT_OFFERED for a model that is not "provider/id", AGENT_STOPPED.
    func set(model: String?, mode: String?, effort: String?) throws -> String {
        if mode != nil { throw CodedError("NOT_SUPPORTED", PiDriver.noModes) }
        if let model, model.split(separator: "/", maxSplits: 1).count != 2 {
            throw CodedError("VALUE_NOT_OFFERED", "pi names a model provider/id, such as one of the agent's options.model.")
        }
        unsent += [("model", model), ("effort", effort)].compactMap { key, value in value.map { (key, $0) } }
        if !setting { try nextSetting() }
        return "now"
    }

    func prompt(_ request: String) -> Prompt? { nil }

    /// pi opens no request: nothing is ever open to answer.
    func answer(_ request: String, _ answer: Answer) throws -> Bool { false }

    /// Closing its input is how pi ends: it exits 0 at once, even mid-run (V).
    var goodbye: Data? { nil }

    func ended(code: Int32, errors: String) {
        guard !over else { return }
        over = true
        guard code != 0 else { return emit(.stopped(nil)) }
        let lines = errors.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // A wrong --model or --session ends pi before it answers anything, with one line on stderr (V).
        if !heard { return emit(.stopped(AgentError(code: "LAUNCH_FAILED", message: lines.first.map { "pi could not start: \($0)" }
            ?? "pi stopped at once (code \(code))."))) }
        emit(.stopped(AgentError(code: "AGENT_ERROR", message: lines.last.map { "pi ended: \($0)" } ?? "pi ended (code \(code)).")))
    }

    // MARK: pi's lines

    private func response(_ message: [String: Any]) {
        guard let id = message["id"] as? String, let call = calls.removeValue(forKey: id) else { return }
        let data = message["data"] as? [String: Any] ?? [:]
        guard message["success"] as? Bool != false else { return refused(call, message["error"] as? String ?? "no reason given") }
        switch call {
        case .state: state(data, asked: [])
        case .readBack(let values): state(data, asked: values)
        case .models:
            models = data["models"] as? [[String: Any]]
            emit(.options(options()))
        case .levels:
            levels = data["levels"] as? [String]
            emit(.options(options()))
        case .set: try? nextSetting()
        case .prompt where data["disposition"] as? String == "handled" && !running:
            // An extension ran the message as its command: no run comes, so the turn something opened ends here.
            abortAsked = false
            emit(.turnEnded(.done))
        case .prompt, .steer, .clearQueue, .abort: break   // the run's events say what became of them
        }
    }

    /// pi refused a command; each says what became of what was asked.
    private func refused(_ call: Call, _ words: String) {
        switch call {
        case .state, .models, .levels, .readBack: break   // the values stay as last known
        case .clearQueue:
            emit(.error(AgentError(code: "AGENT_ERROR", message: "pi kept the messages it had queued: \(words)")))
        case .prompt(let text):
            let refusal = AgentError(code: "AGENT_ERROR", message: "pi refused the message “\(Launched.short(text))”: \(PiDriver.plain(words))")
            // A steer written as a run settled may have started a run of its own: that turn goes on.
            guard !running else { return emit(.error(refusal)) }
            // The run this message would open never started: an interrupt asked for it is moot, and what was held
            // for it goes on.
            abortAsked = false
            emit(.turnEnded(.failed(refusal)))
        case .steer(let text):
            emit(.error(AgentError(code: "AGENT_ERROR", message: "pi did not take the message “\(Launched.short(text))”: \(PiDriver.plain(words))")))
        case .set(let key, let value):
            sent.removeAll { $0.key == key }
            emit(.error(AgentError(code: "VALUE_NOT_OFFERED", message: "pi refused \(value) as its \(key): \(words)")))
            try? nextSetting()
        case .abort:
            aborting = false
            emit(.error(AgentError(code: "AGENT_ERROR", message: "pi did not take the interrupt: \(words)")))
        }
    }

    /// get_state's answer: the conversation file, the model and the thinking level in force. With no login pi shows
    /// the model "unknown/unknown": that is no model. A value `set` asked for and pi did not take is said.
    private func state(_ data: [String: Any], asked values: [(key: String, value: String)]) {
        if thread == nil, let file = data["sessionFile"] as? String {
            thread = file
            emit(.started(pid: nil, thread: file))
        }
        let entry = data["model"] as? [String: Any]
        let reported = entry.flatMap { entry -> String? in
            guard let provider = entry["provider"] as? String, let id = entry["id"] as? String, provider != "unknown" else { return nil }
            return "\(provider)/\(id)"
        }
        let effort = data["thinkingLevel"] as? String
        emit(.reported(model: reported, mode: nil, effort: effort))
        if reported != nil, reported != model {
            model = reported
            // The levels depend on the model.
            if models != nil { try? invoke(.levels, ["type": "get_available_thinking_levels"]) }
        }
        for (key, value) in values {
            let taken = key == "model" ? reported : effort
            if taken != value { emit(.error(AgentError(code: "VALUE_NOT_OFFERED", message: "pi kept \(taken ?? "no value") as its \(key), not \(value)."))) }
        }
    }

    /// Several agent_start come in one run (a retry, a message queued during compaction): the turn opens at the first.
    private func started() {
        guard !running else { return }
        running = true
        stop = nil
        stopError = nil
        emit(.turnStarted(id: nil))
        if abortAsked {
            abortAsked = false
            aborting = true
            try? invoke(.abort, ["type": "abort"])
        }
    }

    /// An abort ends the run with stopReason "aborted" while the model streams, and with "error" ("This operation
    /// was aborted") in a tool (V): both are an interrupt something asked for.
    private func settled() {
        guard running else { return }
        running = false
        for (id, var item) in tools {
            item.tool?.status = nil
            emit(.itemUpdated(item))
            tools[id] = nil
        }
        let interrupted = aborting || stop == "aborted"
        aborting = false
        if interrupted { return emit(.turnEnded(.interrupted)) }
        guard stop == "error" else { return emit(.turnEnded(.done)) }
        emit(.turnEnded(.failed(AgentError(code: "AGENT_ERROR", message: PiDriver.plain(stopError ?? "pi could not answer.")))))
    }

    /// A whole message: the person's (a steer shows when pi takes it) or the agent's. The system prompt, tool
    /// results and the copies in agent_end are left out.
    private func ended(_ message: [String: Any]) {
        switch message["role"] as? String {
        case "user":
            let content = message["content"]
            let text = content as? String ?? PiDriver.texts(content, "text", "text")
            append("message", "person", text)
        case "assistant":
            stop = message["stopReason"] as? String
            stopError = message["errorMessage"] as? String
            append("thought", "agent", PiDriver.texts(message["content"], "thinking", "thinking"))
            append("message", "agent", PiDriver.texts(message["content"], "text", "text"))
        default: break
        }
    }

    private func append(_ kind: String, _ author: String, _ text: String) {
        guard !text.isEmpty else { return }
        count += 1
        emit(.itemAppended(Item(id: "\(launch.agent)/\(count)", kind: kind, author: author, text: text, at: now())))
    }

    private func tool(_ event: [String: Any], done: Bool) {
        guard let id = event["toolCallId"] as? String else { return }
        let name = event["toolName"] as? String ?? "tool"
        let args = event["args"] as? [String: Any]
        let text = tools[id]?.text ?? args?["command"] as? String ?? args?["path"] as? String ?? PiDriver.json(args) ?? ""
        let status = done ? (event["isError"] as? Bool == true ? "failed" : "done") : "running"
        let shown = Item(id: id, kind: "tool", author: "agent", text: text, at: tools[id]?.at ?? now(), tool: Tool(name: name, status: status))
        emit(tools[id] == nil ? .itemAppended(shown) : .itemUpdated(shown))
        tools[id] = done ? nil : shown
    }

    /// An extension's dialog blocks it until answered: something cannot show one, so it is cancelled and the
    /// person told. A fire-and-forget method (notify, setStatus, ...) waits for nothing.
    private func dialog(_ request: [String: Any]) {
        guard let id = request["id"] as? String, ["select", "confirm", "input", "editor"].contains(request["method"] as? String ?? "") else { return }
        try? send(["type": "extension_ui_response", "id": id, "cancelled": true])
        let title = request["title"] as? String ?? "a question"
        emit(.error(AgentError(code: "AGENT_ERROR", message: "A pi extension asked “\(Launched.short(title))”; something cannot show an extension's dialog, so it was cancelled.")))
    }

    // MARK: Helpers

    /// Sends the next value `set` asked for or, once none is left, the get_state that reads them back.
    private func nextSetting() throws {
        guard !unsent.isEmpty else {
            guard !sent.isEmpty else { return }
            let values = sent
            sent = []
            return try invoke(.readBack(values), ["type": "get_state"])
        }
        let (key, value) = unsent.removeFirst()
        sent.append((key, value))
        if key == "effort" { return try invoke(.set(key, value), ["type": "set_thinking_level", "level": value]) }
        // A model is "provider/id" (checked in `set`); an id may hold slashes of its own, a provider none.
        let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
        try invoke(.set(key, value), ["type": "set_model", "provider": parts[0], "modelId": parts[1]])
    }

    /// The models pi has a key for, and the thinking levels of the one in use; nil until pi said.
    private func options() -> Options {
        var options = Options()
        options.mode = []
        options.model = models?.compactMap { entry in
            guard let provider = entry["provider"] as? String, let id = entry["id"] as? String else { return nil }
            return Option(value: "\(provider)/\(id)", label: entry["name"] as? String ?? id)
        }
        options.effort = levels?.map { Option(value: $0, label: PiDriver.levelLabels[$0] ?? $0) }
        return options
    }

    static let levelLabels = Option.effortLabels.merging(["off": "Off", "minimal": "Minimal"]) { first, _ in first }
    static let noModes = "pi has no permission modes: it runs commands and edits files without asking first."

    /// pi's words for a missing key point at a terminal command and a long path inside its install: a newcomer
    /// needs the gesture instead.
    static func plain(_ words: String) -> String {
        guard words.hasPrefix("No API key found") else { return words }
        return "pi has no key for this model. Open pi once in Terminal and use /login, then launch it again."
    }

    /// The `field` of each block of `type` in a message's content, joined.
    static func texts(_ content: Any?, _ type: String, _ field: String) -> String {
        (content as? [[String: Any]] ?? []).filter { $0["type"] as? String == type }.compactMap { $0[field] as? String }.joined(separator: "\n")
    }

    private func invoke(_ call: Call, _ command: [String: Any]) throws {
        callsWritten += 1
        let id = "s\(callsWritten)"
        calls[id] = call
        var command = command
        command["id"] = id
        try send(command)
    }

    /// Lines are built from structures, never by joining strings.
    private func send(_ object: [String: Any]) throws {
        try write(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]))
    }
}

extension Driving {
    /// pi asks no permission and has no request to show: the sentence says so, for the consent window. It names its
    /// conversation file itself; something learns it from get_state.
    static let pi = Driving(kind: "pi", tested: "1.0.0",
                            limits: ["mode": PiDriver.noModes],
                            picksThread: false, resumeFolder: { try PiDriver.resumable($0) },
                            command: { PiDriver.command($0) }, driver: { PiDriver($0, write: $1, emit: $2, now: $3) })
}
