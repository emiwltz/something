// Lent: something's own commands, lent as tools to the person's building assistant. something runs each one itself,
// outside the agent's sandbox, and hands back what it printed: an agent whose sandbox reaches no window server (Codex's)
// can still check a space, without asking anyone. The host says what each tool is (its name, what it does, the JSON
// schema of its arguments and the words of the command it runs); the app says how its own program runs, at
// composition time. A driver offers the tools on its agent's own channel (Codex's dynamic tools); nothing is written
// into the agent's configuration, and the same list can be served over MCP later.
import Foundation
import SomethingCore

/// One command something lends. Its arguments are checked before anything runs: a tool never takes a flag or a path.
public struct LentTool: @unchecked Sendable {
    public let name: String, description: String
    /// The JSON schema of its arguments: an object.
    public let schema: [String: Any]
    /// The words of something's command for these arguments (["check", "hello"]); nil when they are wrong.
    let words: ([String: Any]) -> [String]?

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
        guard let name = arguments["name"] as? String, Spaces.isName(name) else { return nil }
        let refuse = arguments["refuse"] as? [String] ?? []
        guard refuse.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLowercase || $0 == ":" } }) else { return nil }
        return ["check", name] + refuse.flatMap { ["--refuse", $0] }
    }
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
    /// Told on the main queue that the agent `kind` cannot take the tools, with the sentence that says why.
    let refused: (_ kind: String, _ because: String) -> Void
    /// Where `run` runs, then where its reply is handed back: off the main queue, then on it. A test runs both at once.
    let hop: (@escaping () -> Void, @escaping () -> Void) -> Void
    /// Where the commands run, one at a time, in the order asked: each check loads a page in a WebKit process of its
    /// own, and parallel calls would add one each beside the app and the agent, on the same snapshot file.
    static let queue = DispatchQueue(label: "something.lent", qos: .userInitiated)

    public init(tools: [LentTool] = [.check], run: @escaping @Sendable ([String]) -> Reply,
                refused: @escaping (_ kind: String, _ because: String) -> Void,
                hop: ((@escaping () -> Void, @escaping () -> Void) -> Void)? = nil) {
        (self.tools, self.run, self.refused) = (tools, run, refused)
        self.hop = hop ?? { work, then in Lent.queue.async { work(); DispatchQueue.main.async(execute: then) } }
    }

    public static func == (left: Lent, right: Lent) -> Bool { left === right }

    /// Runs the tool `name` with the agent's arguments and hands `reply` what the agent reads. A tool something does
    /// not lend, or wrong arguments, get a refusal in words, and nothing runs.
    func call(_ name: String, _ arguments: Any?, reply: @escaping (Reply) -> Void) {
        guard let tool = tools.first(where: { $0.name == name }) else {
            return reply(Reply(ok: false, text: "something lends no tool named \(name)."))
        }
        guard let words = tool.words(arguments as? [String: Any] ?? [:]) else {
            return reply(Reply(ok: false, text: "Wrong arguments for \(name), so nothing was run. It takes: \(Lent.json(tool.schema))"))
        }
        var answer = Reply(ok: false, text: "")
        hop({ answer = self.run(words) }, { reply(answer) })
    }

    /// Runs `program` (something's own) with the tool's words in `environment`, within `seconds`; the report is what it
    /// printed. A status of 2 means it could not run: anything less is a report, problems included. A program stopped
    /// by a signal, or by the time limit, gave no report, and the reply says which.
    public static func program(_ program: String, environment: [String: String], seconds: TimeInterval = 90) -> @Sendable ([String]) -> Reply {
        { words in
            let process = Process(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: program)
            process.arguments = words
            process.environment = environment
            (process.standardOutput, process.standardError, process.standardInput) = (output, output, FileHandle.nullDevice)
            do { try process.run() } catch { return Reply(ok: false, text: "something could not run \(program): \(error.localizedDescription)") }
            let late = Late(), timer = DispatchWorkItem { late.fired = true; process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: timer)
            let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            timer.cancel()
            let command = "something " + words.joined(separator: " ")
            guard process.terminationReason == .exit else {
                return Reply(ok: false, text: late.fired ? "\(command) did not finish within \(Int(seconds)) seconds."
                                                         : "\(command) stopped unexpectedly (signal \(process.terminationStatus)).")
            }
            return Reply(ok: process.terminationStatus < 2, text: text)
        }
    }

    /// Whether the time limit stopped a program: set on the timer's queue, read once the program ended.
    private final class Late: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = false
        var fired: Bool {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    static func json(_ value: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])).map { String(decoding: $0, as: UTF8.self) } ?? "\(value)"
    }
}
