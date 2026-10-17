// The engine: every agent on this Mac in one contract 1 State, and the hands on the ones something launched.
// The Mac app holds one Engine and talks to agents only through it. This file is the seam between the app and the
// agents: its public API is what the app may use. Until the drivers and readers arrive (slices 11 to 18) it knows
// no agent: the state says which programs are installed, and every write answers NOT_SUPPORTED.
import Foundation
import SomethingCore

/// What a native window shows for one request. Richer than the contract's `Request`, which a space sees: a space
/// never answers a request, the person does.
public struct Prompt: Equatable, Sendable {
    public var request: Request
    /// For a permission: what the agent wants to run or change, as it sent it (a command, a path, a diff).
    public var input: String?
    /// For a question: what the agent asks, in its order.
    public var questions: [Question]

    public init(request: Request, input: String? = nil, questions: [Question] = []) {
        (self.request, self.input, self.questions) = (request, input, questions)
    }
}

public struct Question: Equatable, Sendable {
    public var header: String?, text: String, options: [String], multiple: Bool
    public init(header: String?, text: String, options: [String], multiple: Bool) {
        (self.header, self.text, self.options, self.multiple) = (header, text, options, multiple)
    }
}

/// The person's answer to a request. Permissions are allowed once or denied, never always.
public enum Answer: Equatable, Sendable {
    case once, deny
    /// For a question: the chosen labels (or the typed text) for each question, in its order.
    case choice([[String]])
}

public final class Engine {
    /// Called on the main queue when the state changed. The app decides how often it pushes.
    public var changed: () -> Void = {}

    /// `environment` is the one agents are started in: the terminal's when something was started from one,
    /// otherwise the app's own, and Programs then reads the login shell's PATH.
    public init(environment: [String: String]) { programs = Programs(environment: environment) }

    private let programs: Programs
    /// Whether each kind's program was found; empty until `start` looked (main queue only).
    private var installed: [String: Bool] = [:]
    private var looked = false

    /// Starts watching this Mac. `often` is true while a space is open.
    public func start(often: Bool) {
        guard !looked else { return }
        looked = true
        // Reading the login shell can take 3 s: never on the main queue.
        DispatchQueue.global().async { [self] in
            let found = Dictionary(uniqueKeysWithValues: Programs.kinds.compactMap { kind in programs.installed(kind).map { (kind, $0) } })
            DispatchQueue.main.async { [self] in installed = found; changed() }
        }
    }

    /// The whole state, before any space's scope is applied.
    public var state: State {
        let kinds = ["claude", "codex", "opencode", "pi", "omp"].map { kind in
            (kind, Kind(launch: false, installed: installed[kind], tested: "none", seen: nil, reader: "none", note: nil))
        }
        return State(at: ISO8601DateFormatter().string(from: Date()), kinds: Dictionary(uniqueKeysWithValues: kinds))
    }

    /// The details of an open request, or nil once it closed (the app then closes its window).
    public func prompt(_ request: String) -> Prompt? { nil }
    public func answer(_ request: String, _ answer: Answer) {}

    // What a space asks through the bridge (SomethingCore/Bridge.swift checked the call first). Each throws a
    // `CodedError` with a code of contract 4.3.
    public func deliver(_ text: String, to agent: String, when: String) throws -> String { throw Engine.notYet }
    public func interrupt(_ agent: String) throws -> Bool { throw Engine.notYet }
    public func set(_ agent: String, model: String?, mode: String?, effort: String?) throws -> String { throw Engine.notYet }
    public func launch(_ kind: String, folder: String, model: String?, mode: String?, effort: String?) throws -> String { throw Engine.notYet }
    public func resume(_ kind: String, thread: String, of agent: String) throws -> String { throw Engine.notYet }

    /// Stops every agent something launched, all at once, within `seconds`, then calls `done` on the main queue.
    public func stopAll(within seconds: TimeInterval, done: @escaping () -> Void) { DispatchQueue.main.async(execute: done) }

    static let notYet = CodedError("NOT_SUPPORTED", "something cannot drive agents yet.")
}

/// `something hook permission --spool <dir>`: Claude's plan B (design 4.1). Returns the exit status.
public enum PermissionHook {
    public static func main(_ arguments: [String]) -> Int32 { 2 }
}

/// `something try <kind> [--record <file>] [--plan-b]`: a developer's trial of one driver against a real agent.
public enum Trial {
    public static func main(_ arguments: [String]) -> Int32 {
        FileHandle.standardError.write(Data("something try: no driver yet.\n".utf8))
        return 2
    }
}
