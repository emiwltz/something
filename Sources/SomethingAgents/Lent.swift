// Lent: something's own commands, lent as tools to the person's building assistant. something runs each one itself,
// outside the agent's sandbox, and hands back what it printed: an agent whose sandbox reaches no window server (Codex's)
// can still check a space, without asking anyone. The host says what each tool is (its name, what it does, the JSON
// schema of its arguments and the words of the command it runs); the app says how its own program runs, at
// composition time. A driver offers the tools on its agent's own channel: Codex's dynamic tools, or the MCP server
// `something mcp` (MCP.swift) for an agent that takes MCP servers at launch. Nothing is written into the agent's
// configuration.
import Foundation
import SomethingCore

/// One command something lends. Its arguments are checked before anything runs: a tool never takes a flag or a path.
public struct LentTool: @unchecked Sendable {
    public let name: String, description: String
    /// The JSON schema of its arguments: an object.
    public let schema: [String: Any]
    /// The words of something's command for these arguments (["check", "hello"]); nil when they are wrong.
    package let words: ([String: Any]) -> [String]?

    /// `something_check`: `something check <name>` for a space of the spaces folder, with `--refuse` for each right
    /// in `refuse`. It only reads the space and writes its snapshot in the spaces folder's .check.
    public static let check = LentTool(
        name: "something_check",
        description: "Checks a space of the spaces folder as `something check <name>` does, and returns its report: the problems, and where the snapshot is. something runs it outside your sandbox, where the page can load: use this tool instead of running `something check` in the shell.",
        schema: ["type": "object", "additionalProperties": false, "required": ["name"],
                 "properties": ["name": ["type": "string", "description": "The space's name: lowercase letters, digits and -."],
                                "refuse": ["type": "array", "items": ["type": "string"],
                                           "description": "Rights to refuse during the check, as `--refuse <right>`: state, send, launch, store, or one of them with :<kind>."]]]
    ) { arguments in
        guard let name = word(arguments["name"]) else { return nil }
        let refuse = arguments["refuse"] as? [String] ?? []
        guard refuse.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLowercase || $0 == ":" } }) else { return nil }
        return ["check", name] + refuse.flatMap { ["--refuse", $0] }
    }

    /// `something_new`: `something new <name>`, with `--from <template>` when `from` names one. It only adds a page
    /// to the spaces folder, and refuses a name that is taken.
    public static let new = LentTool(
        name: "something_new",
        description: "Makes a space in the spaces folder as `something new <name>` does, from the empty template or, with `from`, from one of something's templates (AGENTS.md in the spaces folder lists them), and returns what it printed. Use this tool instead of running `something new` in the shell.",
        schema: ["type": "object", "additionalProperties": false, "required": ["name"],
                 "properties": ["name": ["type": "string", "description": "The new space's name: lowercase letters, digits and -."],
                                "from": ["type": "string", "description": "The template to start from, by its name: agents, for instance."]]]
    ) { arguments in
        guard let name = word(arguments["name"]) else { return nil }
        guard let from = arguments["from"] else { return ["new", name] }
        return word(from).map { ["new", name, "--from", $0] }
    }

    /// `something_guide`: `something guide --print`, the guide of a space, which only reads.
    public static let guide = LentTool(
        name: "something_guide",
        description: "Returns something's guide, the contract every space follows, as `something guide --print` prints it. Read it once before you make or change a space.",
        schema: ["type": "object", "additionalProperties": false, "properties": [String: Any]()]
    ) { _ in ["guide", "--print"] }

    /// `value` when it is a space's or a template's name, never a flag.
    static func word(_ value: Any?) -> String? { (value as? String).flatMap { Spaces.isName($0) && !$0.hasPrefix("-") ? $0 : nil } }

    /// Every command something lends, in the order a build uses them.
    public static let all: [LentTool] = [.guide, .new, .check]
}

/// What something lends one launch: the tools, how they run, and whom to tell when the agent cannot take them.
public final class Lent: @unchecked Sendable, Equatable {
    /// What a command run for a tool gave: whether it could run (a report with problems did), and the text it printed.
    public struct Reply: Equatable, Sendable {
        public var ok: Bool, text: String
        public init(ok: Bool, text: String) { (self.ok, self.text) = (ok, text) }
    }

    public let tools: [LentTool]
    /// Runs something's own command with these words, off the main queue, and returns what it gave.
    let run: @Sendable ([String]) -> Reply
    /// The words that start something's MCP server for these tools (`<program> mcp`), and the variables it needs
    /// beyond those of the agent that starts it; nil when no program serves them (a test's tools).
    package let server: (words: [String], environment: [String: String])?
    /// Told on the main queue that the agent `kind` cannot take the tools, with the sentence that says why.
    package let refused: (_ kind: String, _ because: String) -> Void
    /// Where `run` runs, then where its reply is handed back: off the main queue, then on it. A test runs both at once.
    let hop: (@escaping () -> Void, @escaping () -> Void) -> Void
    /// Where the commands run, one at a time, in the order asked: each check loads a page in a WebKit process of its
    /// own, and parallel calls would add one each beside the app and the agent, on the same snapshot file.
    static let queue = DispatchQueue(label: "something.lent", qos: .userInitiated)

    public init(tools: [LentTool] = [.check], run: @escaping @Sendable ([String]) -> Reply, server: ([String], [String: String])? = nil,
                refused: @escaping (_ kind: String, _ because: String) -> Void,
                hop: ((@escaping () -> Void, @escaping () -> Void) -> Void)? = nil) {
        (self.tools, self.run, self.server, self.refused) = (tools, run, server, refused)
        self.hop = hop ?? { work, then in Lent.queue.async { work(); DispatchQueue.main.async(execute: then) } }
    }

    /// `tools`, run by something's own `program` in `environment`, and served by `<program> mcp`. The agent starts
    /// that server with its own environment, plus the folders something's program takes from `environment` when set:
    /// SOMETHING_HOME (README, "Building from the clone") and TMPDIR, where WebKit keeps what a check needs.
    public static func own(_ program: String, tools: [LentTool], environment: [String: String], refused: @escaping (_ kind: String, _ because: String) -> Void) -> Lent {
        Lent(tools: tools, run: Lent.program(program, environment: environment),
             server: ([program, "mcp"], environment.filter { ["SOMETHING_HOME", "TMPDIR"].contains($0.key) }), refused: refused)
    }

    /// Its MCP server in the configuration MCP clients take (Claude Code's --mcp-config): {"mcpServers": {"something":
    /// …}}; nil when none.
    package var mcpConfig: String? {
        server.map { Lent.json(["mcpServers": ["something": ["command": $0.words[0], "args": Array($0.words.dropFirst()), "env": $0.environment]]]) }
    }

    /// The tool something lends that an agent calls `name`: by its own name, or as a tool of the MCP server something
    /// gives it, "something" (Claude Code's mcp__something__something_check, OpenCode's something_something_check, or
    /// something.something_check from its code mode); with the command something runs for `arguments`, nil when they
    /// are wrong. Nil for any other tool.
    package static func called(_ name: String, _ arguments: Any?) -> (name: String, command: String?)? {
        guard let tool = LentTool.all.first(where: { tool in ["", "mcp__something__", "something_", "something."].contains { $0 + tool.name == name } }) else { return nil }
        return (tool.name, tool.words(arguments as? [String: Any] ?? [:]).map { (["something"] + $0).joined(separator: " ") })
    }

    public static func == (left: Lent, right: Lent) -> Bool { left === right }

    /// Runs the tool `name` with the agent's arguments and hands `reply` what the agent reads. A tool something does
    /// not lend, or wrong arguments, get a refusal in words, and nothing runs.
    package func call(_ name: String, _ arguments: Any?, reply: @escaping (Reply) -> Void) {
        guard let tool = tools.first(where: { $0.name == name }) else {
            return reply(Reply(ok: false, text: "something lends no tool named \(name)."))
        }
        guard let words = tool.words(arguments as? [String: Any] ?? [:]) else {
            return reply(Reply(ok: false, text: "Wrong arguments for \(name), so nothing was run. It takes: \(Lent.json(tool.schema))"))
        }
        var answer = Reply(ok: false, text: "")
        hop({ answer = self.run(words) }, { reply(answer) })
    }

    /// Runs `program` (something's own) with the tool's words in `environment`, within `seconds`; the reply is what it
    /// printed. It failed with a status of 1 or more, except `check`, whose 1 is a report with problems (2: it could not
    /// run). A program stopped by a signal, or by the time limit, gave no report, and the reply says which.
    public static func program(_ program: String, environment: [String: String], seconds: TimeInterval = 90) -> @Sendable ([String]) -> Reply {
        { words in
            let process = Process(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: program)
            process.arguments = words
            process.environment = environment
            (process.standardOutput, process.standardError, process.standardInput) = (output, output, FileHandle.nullDevice)
            do { try process.run() } catch { return Reply(ok: false, text: "something could not run \(program): \(error.localizedDescription)") }
            let started = Date(), timer = DispatchWorkItem { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: timer)
            let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            timer.cancel()
            let command = "something " + words.joined(separator: " ")
            guard process.terminationReason == .exit else {
                // Only the time limit stops it that late.
                return Reply(ok: false, text: Date().timeIntervalSince(started) >= seconds ? "\(command) did not finish within \(Int(seconds)) seconds."
                                                                                            : "\(command) stopped unexpectedly (signal \(process.terminationStatus)).")
            }
            return Reply(ok: process.terminationStatus < (words.first == "check" ? 2 : 1), text: text)
        }
    }

    package static func json(_ value: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])).map { String(decoding: $0, as: UTF8.self) } ?? "\(value)"
    }
}
