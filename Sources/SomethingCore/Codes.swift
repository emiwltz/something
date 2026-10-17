// Every code of contract 1 with its level and its sentence (a copy of share/contract/codes.json, which a test keeps
// equal), the problems that carry them, and the report of `something check` as a person reads it and as --json gives it.
// The report is only formatted here; the check that fills it runs in the app.
import Foundation

public enum Level: String, Codable, Sendable { case fatal, error, warning, info }

/// One code: where it comes from ("bridge", "check" or "import"), its level, whether it blocks the display, when it
/// is given, and what to do.
public struct Code: Equatable, Sendable {
    public let from: String, level: Level, blocks: Bool, when: String, fix: String
    init(_ from: String, _ level: Level, blocks: Bool = false, _ when: String, _ fix: String) {
        (self.from, self.level, self.blocks, self.when, self.fix) = (from, level, blocks, when, fix)
    }
}

public enum Codes {
    /// Within contract 1 codes are added here, never removed or renamed.
    public static let all: [String: Code] = [
        "BAD_PARAMS": Code("bridge", .error, "A parameter is missing or of the wrong type.", "Pass the parameters the guide lists for this function, with their types."),
        "UNKNOWN_METHOD": Code("bridge", .error, "The function is not in this contract.", "Use only the functions of something.js listed in the guide."),
        "UNKNOWN_EVENT": Code("bridge", .error, "on with an event other than change or granted.", "Listen to \"change\" or \"granted\"."),
        "NO_HOST": Code("bridge", .error, "The page is not open in something.", "Open the space in something; a browser alone has no agents to give it."),
        "RIGHT_NOT_GRANTED": Code("bridge", .error, "The right was not declared, was refused, or was revoked.", "Declare the right, and read something.granted to hide what the person did not allow."),
        "AGENT_NOT_FOUND": Code("bridge", .error, "No such agent in this space's scope.", "Use an id from the latest state; agents come and go."),
        "READ_ONLY_AGENT": Code("bridge", .error, "A write to an agent started elsewhere.", "Check can before writing; offer resume to continue this conversation here."),
        "NOT_SUPPORTED": Code("bridge", .error, "This agent cannot do it (its can says false).", "Check can and because before the call, and hide what this agent cannot do."),
        "VALUE_NOT_OFFERED": Code("bridge", .error, "set with a value not in options, or the agent replied with a different value.", "Pick a value from the agent's options."),
        "AGENT_STOPPED": Code("bridge", .error, "The agent has ended.", "Launch or resume an agent to go on."),
        "FOLDER_NOT_GRANTED": Code("bridge", .error, "launch with a folder outside the granted one.", "Launch in something.granted.folder or a folder inside it."),
        "NOT_INSTALLED": Code("bridge", .error, "The agent's program was not found on this Mac.", "Tell the person to install this agent; kinds says which ones are installed."),
        "INTERPRETER_NOT_FOUND": Code("bridge", .error, "The program was found, but what it needs to run was not.", "Show the message to the person: it names what to install."),
        "LAUNCH_FAILED": Code("bridge", .error, "The program started and stopped at once.", "Show the message to the person: it carries the agent's first error line."),
        "THREAD_NOT_FOUND": Code("bridge", .error, "No conversation with this id can be resumed.", "Use a thread id from the latest state."),
        "STILL_RUNNING": Code("bridge", .error, "Another process still holds this conversation.", "Show the message to the person: it says which process and what to do."),
        "HELD_ELSEWHERE": Code("bridge", .error, "A background service of the agent holds the conversation.", "Show the message to the person: it names the gesture that frees it."),
        "REFUSED": Code("bridge", .error, "The person said no in a native window.", "Accept the answer; do not ask again in a loop."),
        "BUSY": Code("bridge", .error, "A link confirmation is already open for this space.", "Wait for the first link's answer before opening another."),
        "STORE_FULL": Code("bridge", .error, "The memory would exceed 5 MB.", "Store less: remove old values with store.set(path, null)."),
        "AGENT_ERROR": Code("bridge", .error, "The agent refused the request.", "Show the message to the person: it keeps the agent's own words."),

        "SPACE_NOT_FOUND": Code("check", .fatal, "No space by that name or path.", "Give the name of a space in ~/something/spaces, or the path of its file or folder."),
        "NO_WINDOW_SERVER": Code("check", .fatal, "No logged-in Mac session to render in; only the static checks ran.", "Run the check from a logged-in session of the Mac."),
        "STATE_FILE_UNREADABLE": Code("check", .fatal, "The --state file is not a valid state.", "Start from share/contract/state-example.json and keep every key."),
        "DECLARATION_UNREADABLE": Code("check", .error, blocks: true, "The declaration is not valid JSON.", "Fix the JSON of the declaration; the space does not open until it parses."),
        "CONTRACT_TOO_NEW": Code("check", .error, blocks: true, "contract is higher than this engine knows.", "Write \"contract\": 1, or update something."),
        "SCRIPT_ERROR": Code("check", .error, "An uncaught error, with file, line and column.", "Fix the code at this line; the page stops running at this error."),
        "PROMISE_REJECTED": Code("check", .error, "An unhandled promise rejection.", "Catch the rejection and show its message to the person."),
        "RESOURCE_MISSING": Code("check", .error, "A file of the space that does not exist.", "Add the file to the space, or fix the path that names it."),
        "LOAD_FAILED": Code("check", .error, "The page did not load.", "Check that the space's HTML file exists and is readable."),
        "LOAD_TIMEOUT": Code("check", .error, "No load within 15 seconds.", "Make the page load faster: no endless loop before the first paint."),
        "PAGE_CRASHED": Code("check", .error, "The web process ended.", "Look for code that uses too much memory or loops without end."),
        "DECLARATION_MISSING": Code("check", .warning, "No declaration: the space opens with no right.", "Add <script type=\"application/json\" id=\"something\">{\"contract\": 1}</script>."),
        "DECLARATION_TWICE": Code("check", .warning, "Both a block and something.json; something.json is used.", "Keep one declaration: remove the block or something.json."),
        "CONTRACT_MISSING": Code("check", .warning, "No contract key; read as 1.", "Add \"contract\": 1 to the declaration."),
        "SCOPE_INVALID": Code("check", .warning, "agents is not one of the two shapes; the space sees only what it launches.", "Write \"agents\": {\"see\": \"all\"} or {\"folders\": [\"~/code/example\"]}."),
        "UNKNOWN_RIGHT": Code("check", .warning, "A word that is not a right of contract 1.", "Use one of: state, send, launch, store, optionally with :kind."),
        "RIGHT_UNAVAILABLE": Code("check", .warning, "A known right this engine cannot honour.", "Read something.granted.unavailable and hide what depends on it."),
        "RIGHT_NOT_DECLARED": Code("check", .warning, "The page called a function whose right it did not declare.", "Declare the right in rights, or do not call this function."),
        "RIGHT_REFUSED": Code("check", .warning, "With --refuse: the page threw instead of adapting to granted.", "Read something.granted and hide what the person refused."),
        "RESOURCE_BLOCKED": Code("check", .warning, "A load outside the space was blocked (spaces have no network).", "Put the file in the space, or embed the library at an exact version."),
        "NAVIGATION_BLOCKED": Code("check", .warning, "The page tried to leave the space.", "Use something.open(url) for links that leave the space."),
        "BRIDGE_ERROR": Code("check", .warning, "A bridge call a real engine would also reject (with its code).", "Read the code's own sentence, and check granted and can before the call."),
        "CONSOLE_ERROR": Code("check", .warning, "console.error was called.", "Show the problem to the person on the page, or fix its cause."),
        "FOLDER_MISSING": Code("check", .warning, "The declared folder does not exist on this Mac.", "Declare a folder that exists, or leave folder out and let the person choose one."),
        "TOO_HEAVY": Code("check", .warning, "The space weighs more than 5 MB.", "Remove files the space does not use, or make its images smaller."),
        "UNKNOWN_KEY": Code("check", .info, "A declaration key this engine does not know; ignored.", "Remove the key, or check its spelling."),

        "IMPORT_NOT_A_SPACE": Code("import", .error, "The file is not a .something export.", "Import a file made by something's export."),
        "IMPORT_TOO_NEW": Code("import", .error, "The export carries a contract higher than this engine knows.", "Update something, then import again."),
        "IMPORT_UNSAFE_PATH": Code("import", .error, "A file path is absolute, has .., or an empty segment.", "Export the space again from something; this file was changed by hand."),
        "IMPORT_TOO_BIG": Code("import", .error, "Over 20 MB or 500 files.", "Remove files the space does not use, then export it again."),
    ]
}

/// A failure a caller can act on: a code of the table and one sentence about this occurrence.
public struct CodedError: Error, Equatable, Sendable {
    public let code: String, message: String
    public init(_ code: String, _ message: String) { (self.code, self.message) = (code, message) }
}

/// Where a problem is, when it has a place in the space's files.
public struct Where: Codable, Equatable, Sendable, EveryKey {
    public var file: String, line: Int?, column: Int?
    public init(file: String, line: Int? = nil, column: Int? = nil) { (self.file, self.line, self.column) = (file, line, column) }
}

/// One problem found in a space. Its level and fix come from the table, so a sentence lives in one place.
public struct Problem: Encodable, Equatable, Sendable {
    public let code: String, message: String, `where`: Where?

    public init(_ code: String, _ message: String, where place: Where? = nil) {
        precondition(Codes.all[code] != nil, "\(code) is not a code of contract 1")
        (self.code, self.message, self.where) = (code, message, place)
    }

    public var level: Level { Codes.all[code]!.level }
    public var fix: String { Codes.all[code]!.fix }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: NameKey.self)
        try c.encode(code, forKey: NameKey("code"))
        try c.encode(level, forKey: NameKey("level"))
        try c.encode(message, forKey: NameKey("message"))
        try c.encode(fix, forKey: NameKey("fix"))
        try c.encode(self.where, forKey: NameKey("where"))
    }
}

/// The report of one check (contract 9.2 and 9.3). What the check could not learn stays nil and is written null.
public struct Report: Encodable {
    public struct Rights: Codable, Equatable, EveryKey {
        public var granted: [String] = [], refused: [String] = [], unavailable: [String] = [], unknown: [String] = []
        public init() {}
    }
    /// What the page was given: the source of its state ("invented" or a file), and what that state held.
    public struct Received: Codable, Equatable, EveryKey {
        public var source: String, agents: Int, states: [String: Int], requests: Int, nullKeys: [String]
        public init(source: String, agents: Int, states: [String: Int], requests: Int, nullKeys: [String]) {
            (self.source, self.agents, self.states, self.requests, self.nullKeys) = (source, agents, states, requests, nullKeys)
        }
    }

    public var space: String, path: String
    public var declaration: Declaration?
    public var rights = Rights()
    public var received: Received?
    public var problems: [Problem] = []
    public var calls: [JSONValue] = [], console: [JSONValue] = []
    public var size: Size?
    public var snapshot: String?, journal: [JournalLine]?, ms: Int?

    public init(space: String, path: String) { (self.space, self.path) = (space, path) }

    /// Fatal problems count as errors: the check could not say the space is fine.
    public var errors: Int { problems.filter { $0.level == .error || $0.level == .fatal }.count }
    public var warnings: Int { problems.filter { $0.level == .warning }.count }
    /// 2 when the check could not run, 1 when there are errors, 0 otherwise.
    public var exitStatus: Int32 { problems.contains { $0.level == .fatal } ? 2 : errors > 0 ? 1 : 0 }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: NameKey.self)
        func put<T: Encodable>(_ key: String, _ value: T) throws { try c.encode(value, forKey: NameKey(key)) }
        try put("check", 1); try put("contract", 1); try put("space", space); try put("path", path)
        try put("ok", errors == 0); try put("errors", errors); try put("warnings", warnings)
        try put("declaration", declaration); try put("rights", rights); try put("received", received)
        try put("problems", problems); try put("calls", calls); try put("console", console); try put("size", size)
        try put("snapshot", snapshot); try put("journal", journal); try put("ms", ms)
    }

    /// The --json output: pretty, keys sorted, so two runs on the same space give the same bytes.
    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// The human output: one labelled line per fact, each problem with its fix under it, then the counts.
    /// `home` is shortened to `~` in paths.
    public func text(home: String) -> String {
        func row(_ label: String, _ value: String) -> String { "  " + label.padding(toLength: 10, withPad: " ", startingAt: 0) + value }
        func short(_ path: String) -> String { path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path }
        func count(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        var lines = ["something check \(space)"]
        var place = short(path)
        if let size { place += " · \(count(size.files, "file")) · \(Size.words(size.bytes))" }
        lines.append(row("space", place))
        var rights = [self.rights.granted.isEmpty ? "none" : self.rights.granted.joined(separator: ", ")]
        for (word, list) in [("refused", self.rights.refused), ("unavailable", self.rights.unavailable), ("unknown", self.rights.unknown)]
        where !list.isEmpty { rights.append("\(word): \(list.joined(separator: ", "))") }
        lines.append(row("rights", rights.joined(separator: " · ")))
        if let received {
            let order = ["idle", "working", "waiting", "done", "error", "interrupted", "unknown"]
            let words = received.states.keys.sorted { (order.firstIndex(of: $0) ?? order.count, $0) < (order.firstIndex(of: $1) ?? order.count, $1) }
            let states = words.isEmpty ? "" : " (" + words.map { "\(received.states[$0]!) \($0)" }.joined(separator: ", ") + ")"
            lines.append(row("received", "\(count(received.agents, "agent"))\(states), \(count(received.requests, "request")) · \(received.source) state"))
        }
        for problem in problems {
            let place = problem.where.map { w in " " + ([w.file] + [w.line, w.column].compactMap { $0.map(String.init) }).joined(separator: ":") } ?? ""
            lines.append(row(problem.level.rawValue, "\(problem.code)\(place) \(problem.message)"))
            lines.append(row("", problem.fix))
        }
        if let snapshot { lines.append(row("snapshot", short(snapshot))) }
        lines.append("  \(count(errors, "error")), \(count(warnings, "warning")).")
        return lines.joined(separator: "\n") + "\n"
    }
}
