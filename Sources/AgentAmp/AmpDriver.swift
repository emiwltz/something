// AmpDriver: Amp launched by something, through `amp --execute --stream-json --stream-json-input`, its official machine
// channel: one JSON object per line each way, Claude Code's stream-json shapes. something writes only the person's
// messages (`{"type":"user", "steer"?, "message"}`): the channel takes nothing else, so there is no way to pause a turn,
// to answer a request or to change a value, and Amp never asks permission (a tool its own settings would ask for is
// refused by Amp itself in this mode). Its ask_user_choice tool is not refused: Amp then waits for an answer the
// channel cannot carry, and takes no other message (V), so something says so and the person stops it. Amp writes `system/init` (its thread) with the first message, then
// the person's messages as it takes them, the assistant's messages and the tools' results; a turn ends at the
// assistant's last message (`stop_reason` end_turn). `result` comes only once its input is closed. What each choice
// rests on (V: the real amp 0.0.1792656060, 22 October 2026) is said where it is made.
import Foundation
import SomethingAgents
import SomethingCore

final class AmpDriver: Driver {
    /// `--no-ide`: by default Amp adds the open editor's file and selection to every message, which the person did
    /// not write to this agent. The thinking blocks are an extension of Amp's stream (V). Something's tools, for the
    /// person's assistant, go in `--mcp-config` for this launch only: Amp takes the servers by name (V: the
    /// `{"mcpServers": ...}` wrapper of Claude Code is refused).
    static func command(_ launch: Launch) -> Command {
        var arguments = ["--execute", "--stream-json", "--stream-json-input", "--stream-json-thinking", "--no-ide"]
        if let server = launch.lent?.server, let program = server.words.first {
            arguments += ["--mcp-config", Lent.json(["something": ["command": program, "args": Array(server.words.dropFirst()), "env": server.environment]])]
        }
        return Command(arguments: arguments)
    }

    static let noInterrupt = "Amp can't pause mid-task: stopping it ends Amp."
    static let noSettings = "Amp picks its model by its own agent mode, which something does not set."

    private let launch: Launch
    private let write: (Data) throws -> Void
    private let emit: (AgentEvent) -> Void
    private let now: () -> String
    private var thread: String?
    private var turnOpen = false
    /// Tool items not finished yet, by Amp's tool_use id.
    private var tools: [String: Item] = [:]
    /// How many items this agent showed, for their ids.
    private var count = 0
    /// True once Amp wrote a line: a launch that fails writes none.
    private var heard = false
    /// True once Amp reported an error since the last turn started: the run's `result` repeats it.
    private var failed = false

    init(_ launch: Launch, write: @escaping (Data) throws -> Void, emit: @escaping (AgentEvent) -> Void, now: @escaping () -> String) {
        (self.launch, self.write, self.emit, self.now) = (launch, write, emit, now)
    }

    /// Amp writes nothing before the first message (V). It offers nothing something can choose.
    func begin() throws {
        var options = Options()
        (options.model, options.mode, options.effort) = ([], [], [])
        emit(.options(options))
    }

    @discardableResult func receive(_ line: Data) -> Bool {
        guard let frame = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], let type = frame["type"] as? String else { return false }
        heard = true
        switch (type, frame["subtype"] as? String) {
        case ("system", "init"): initialized(frame)
        case ("system", "error_during_execution"), ("system", "error_max_turns"): failure(frame["error"] as? String)
        case ("system", _): break   // a background subagent's end, or a newer Amp's notice
        case ("user", _): person(frame)
        case ("assistant", _): assistant(frame)
        case ("result", _): if frame["is_error"] as? Bool == true { failure(frame["error"] as? String) }
        default: return false   // a newer Amp's lines must not break an older something
        }
        return true
    }

    /// A steer is handled at Amp's next interruption point, in the running turn (V: it shows between two tool calls);
    /// a message on an idle Amp starts a turn, which opens here, before Amp says anything.
    func deliver(_ text: String, steer: Bool) throws {
        var line: [String: Any] = ["type": "user", "message": ["role": "user", "content": [["type": "text", "text": text]]]]
        if steer { line["steer"] = true }
        try write(JSONSerialization.data(withJSONObject: line, options: [.sortedKeys, .withoutEscapingSlashes]))
        if !steer { open() }
    }

    /// The channel takes only messages, and an interrupt signal ends Amp altogether (V): `limits` says so first.
    func interrupt() throws { throw CodedError("NOT_SUPPORTED", AmpDriver.noInterrupt) }

    func set(model: String?, mode: String?, effort: String?) throws -> String { throw CodedError("NOT_SUPPORTED", AmpDriver.noSettings) }

    func prompt(_ request: String) -> Prompt? { nil }

    /// Amp opens no request: nothing is ever open to answer.
    func answer(_ request: String, _ answer: Answer) throws -> Bool { false }

    /// Closing its input is how Amp ends: it finishes the running turn, writes `result` and exits 0 (V).
    var goodbye: Data? { nil }

    func ended(code: Int32, errors: String) {
        let lines = errors.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard code != 0 else { return emit(.stopped(nil)) }
        // A wrong option, or a configuration Amp refuses, ends it before any line, with one line on stderr (V).
        if !heard { return emit(.stopped(AgentError(code: "LAUNCH_FAILED", message: lines.first.map { "Amp could not start: \($0)" }
            ?? "Amp stopped at once (code \(code))."))) }
        emit(.stopped(AgentError(code: "AGENT_ERROR", message: lines.last.map { "Amp ended: \($0)" } ?? "Amp ended (code \(code)).")))
    }

    // MARK: Amp's lines

    /// The thread is Amp's, named at the first message; `agent_mode` is Amp's own word for what it runs as.
    private func initialized(_ frame: [String: Any]) {
        if thread == nil, let id = frame["session_id"] as? String {
            thread = id
            emit(.started(pid: nil, thread: id))
        }
        if let mode = frame["agent_mode"] as? String { emit(.reported(model: nil, mode: mode, effort: nil)) }
    }

    /// The person's words as Amp takes them (a steer shows where it went in), and the results of the tools. A
    /// subagent's prompt (with its `parent_tool_use_id`, as in Claude Code's stream) is the agent's words, not the person's.
    private func person(_ frame: [String: Any]) {
        let sub = frame["parent_tool_use_id"].map { !($0 is NSNull) } ?? false
        for block in blocks(frame) {
            switch block["type"] as? String {
            case "text":
                guard let text = block["text"] as? String, !text.isEmpty else { continue }
                if sub { append("subagent", "agent", text); continue }
                // A steer written as a turn ended starts the next one (V: Amp shows a held message when its turn starts).
                open()
                append("message", "person", text)
            case "tool_result":
                guard let id = block["tool_use_id"] as? String, var item = tools.removeValue(forKey: id) else { continue }
                // A result that does not say whether it failed leaves the outcome unknown.
                item.tool?.status = (block["is_error"] as? Bool).map { $0 ? "failed" : "done" }
                emit(.itemUpdated(item))
            default: break
            }
        }
    }

    /// One whole message of the model: its text, thoughts and tool calls; a subagent's go under its kind. The main
    /// agent's message that ends without calling a tool ends the turn (V: end_turn); `pause_turn` and `tool_use` go on.
    /// A refusal or an answer cut at the length limit ends it failed.
    private func assistant(_ frame: [String: Any]) {
        let sub = frame["parent_tool_use_id"].map { !($0 is NSNull) } ?? false
        for block in blocks(frame) {
            switch block["type"] as? String {
            case "text": append(sub ? "subagent" : "message", "agent", block["text"] as? String ?? "")
            case "thinking": append(sub ? "subagent" : "thought", "agent", block["thinking"] as? String ?? "")
            case "tool_use": tool(block, sub: sub)
            default: break
            }
        }
        let stop = (frame["message"] as? [String: Any])?["stop_reason"] as? String
        guard !sub else { return }
        switch stop {
        case "end_turn", "stop_sequence": close(.done)
        case "refusal": close(.failed(AgentError(code: "AGENT_ERROR", message: "Amp's model refused to answer.")))
        case "max_tokens": close(.failed(AgentError(code: "AGENT_ERROR", message: "Amp's answer was cut off at its length limit.")))
        default: break
        }
    }

    private func tool(_ block: [String: Any], sub: Bool) {
        let name = block["name"] as? String ?? "tool", input = block["input"] as? [String: Any] ?? [:]
        let lent = launch.lent == nil ? nil : Lent.called(name, input)
        count += 1
        let id = block["id"] as? String ?? "\(launch.agent)/\(count)"
        let item = Item(id: id, kind: sub ? "subagent" : "tool", author: "agent", text: lent.map { $0.command ?? "\($0.name) (wrong arguments)" } ?? AmpDriver.summary(input),
                        at: now(), tool: Tool(name: lent?.name ?? name, status: "running"))
        tools[id] = item
        emit(.itemAppended(item))
        if !sub, name == "ask_user_choice" { emit(.error(AgentError(code: "AGENT_ERROR", message: AmpDriver.choice))) }
    }

    static let choice = "Amp asked you to choose, which something cannot show, and waits for your answer: stop Amp, then ask again without a choice."

    /// What a tool acts on: its command, its code (code_exec, which also calls MCP servers' tools), the first file
    /// of a patch, else its input.
    static func summary(_ input: [String: Any]) -> String {
        if let text = input["command"] as? String ?? input["code"] as? String { return text }
        if let patch = input["patchText"] as? String,
           let line = patch.split(separator: "\n").first(where: { $0.hasPrefix("*** ") && $0.contains(" File: ") }),
           let range = line.range(of: " File: ") {
            return String(line[range.upperBound...])
        }
        return json(input) ?? ""
    }

    /// An error Amp reports: the turn fails with it, or it is said when no turn runs. The run's `result` repeats an
    /// error already said, which is said once.
    private func failure(_ words: String?) {
        let error = AgentError(code: "AGENT_ERROR", message: words.map { "Amp: \($0)" } ?? "Amp could not answer.")
        defer { failed = true }
        if turnOpen { return close(.failed(error)) }
        if !failed { emit(.error(error)) }
    }

    // MARK: Helpers

    private func blocks(_ frame: [String: Any]) -> [[String: Any]] {
        (frame["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
    }

    private func open() {
        guard !turnOpen else { return }
        (turnOpen, failed) = (true, false)
        emit(.turnStarted(id: nil))
    }

    /// Ends the turn; a tool still running then has no known outcome.
    private func close(_ outcome: Outcome) {
        guard turnOpen else { return }
        turnOpen = false
        for (id, var item) in tools {
            item.tool?.status = nil
            emit(.itemUpdated(item))
            tools[id] = nil
        }
        emit(.turnEnded(outcome))
    }

    private func append(_ kind: String, _ author: String, _ text: String) {
        guard !text.isEmpty else { return }
        count += 1
        emit(.itemAppended(Item(id: "\(launch.agent)/\(count)", kind: kind, author: author, text: text, at: now())))
    }
}

extension Driving {
    /// Amp names its thread itself, at the first message. Nothing but messages goes through its channel.
    static let amp = Driving(kind: "amp", tested: "0.0.1792656060",
                             limits: ["interrupt": AmpDriver.noInterrupt, "model": AmpDriver.noSettings, "mode": AmpDriver.noSettings,
                                      "effort": AmpDriver.noSettings],
                             picksThread: false, command: { AmpDriver.command($0) }, driver: { AmpDriver($0, write: $1, emit: $2, now: $3) })
}
