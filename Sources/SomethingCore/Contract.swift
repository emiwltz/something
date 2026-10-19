// Contract 1's state as a space receives it: every key always present, null for what is not known, and the caps
// (10 turns, 50 items, 4,000 characters). share/contract/ holds the same shape as data; the tests keep both in step.
// Words of open vocabularies (states, kinds, evidence) stay strings, so a state written by a newer engine still
// decodes; StateMap.swift is where the engine chooses them.
import Foundation

/// JSONEncoder leaves nil keys out. A space must see `null`: a missing key could pass for a value nobody sent.
/// So the contract types encode every stored property, by name, nil as null, in the order they are declared.
public protocol EveryKey: Encodable {}

extension EveryKey {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: NameKey.self)
        for child in Mirror(reflecting: self).children {
            guard let name = child.label, let value = child.value as? any Encodable else {
                preconditionFailure("\(Self.self) has a property that cannot be encoded")
            }
            try container.encode(value, forKey: NameKey(name))
        }
    }
}

struct NameKey: CodingKey {
    let stringValue: String
    init(_ name: String) { stringValue = name }
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}

public enum Limits {
    public static let turns = 10, items = 50, characters = 4_000
}

/// How the contract, the journal and the grants write a time: ISO 8601 in UTC, to the second. One formatter for every
/// caller, on any thread: making one is slow, and the state is stamped at each change.
public let iso8601 = ISO8601DateFormatter()

public struct State: Codable, Equatable, Sendable, EveryKey {
    public var contract = 1
    public var at: String
    public var kinds: [String: Kind]
    public var agents: [Agent]
    public var threads: [AgentThread]
    public var requests: [Request]

    public init(at: String, kinds: [String: Kind], agents: [Agent] = [], threads: [AgentThread] = [], requests: [Request] = []) {
        (self.at, self.kinds, self.agents, self.threads, self.requests) = (at, kinds, agents, threads, requests)
    }
}

/// One harness, whether or not any agent of it runs.
public struct Kind: Codable, Equatable, Sendable, EveryKey {
    public var launch: Bool
    public var installed: Bool?
    public var tested: String
    public var seen: String?
    /// "ok", "changed", "unreadable" or "none".
    public var reader: String
    public var note: String?

    public init(launch: Bool, installed: Bool?, tested: String, seen: String?, reader: String, note: String?) {
        (self.launch, self.installed, self.tested, self.seen, self.reader, self.note) = (launch, installed, tested, seen, reader, note)
    }
}

public struct Agent: Codable, Equatable, Sendable, EveryKey {
    public var id: String
    public var kind: String
    public var name: String?
    /// "launched" or "elsewhere".
    public var origin: String
    public var folder: String?
    public var pid: Int?
    /// true on proof of a living holder, false on proof of its end, nil otherwise.
    public var alive: Bool?
    public var evidence: String?
    public var state: String
    /// "permission", "answer", "none", or nil when no source can say.
    public var waiting: String?
    public var thread: String?
    /// What the agent last reported, never what was requested.
    public var model: String?
    public var mode: String?
    public var effort: String?
    public var options = Options()
    public var queue: [Queued] = []
    public var can = Can()
    /// One sentence for a false entry of `can` worth explaining.
    public var because: [String: String] = [:]
    public var error: AgentError?
    public var started: String?
    public var updated: String?
    /// Harness-specific facts, outside the contract's promise.
    public var detail: [String: JSONValue] = [:]

    /// An agent that knows nothing yet: every fact nil, `state` "unknown", nothing possible.
    public init(id: String, kind: String, origin: String) {
        (self.id, self.kind, self.origin, self.state) = (id, kind, origin, "unknown")
    }
}

public struct Options: Codable, Equatable, Sendable, EveryKey {
    public var model: [Option]?, mode: [Option]?, effort: [Option]?
    public init() {}
}

public struct Option: Codable, Equatable, Sendable, EveryKey {
    public var value: String, label: String
    public init(value: String, label: String) { (self.value, self.label) = (value, label) }
}

/// A message something holds for the agent's next turn.
public struct Queued: Codable, Equatable, Sendable, EveryKey {
    public var id: String, text: String, at: String
    public init(id: String, text: String, at: String) { (self.id, self.text, self.at) = (id, text, at) }
}

/// What a call would do now. Always booleans: false until something proves the agent can.
public struct Can: Codable, Equatable, Sendable, EveryKey {
    public var send = false, steer = false, queue = false, interrupt = false
    public var model = false, mode = false, effort = false, resume = false
    public init() {}
}

public struct AgentError: Codable, Equatable, Sendable, EveryKey {
    public var code: String, message: String
    public init(code: String, message: String) { (self.code, self.message) = (code, message) }
}

/// The agent's current conversation, its last `Limits.turns` turns: `Thread` in the contract, renamed here so it does
/// not clash with Foundation.Thread.
public struct AgentThread: Codable, Equatable, Sendable, EveryKey {
    public var id: String
    public var agent: String
    public var title: String?
    public var started: String?
    /// false when older turns were left out.
    public var complete: Bool
    public var turns: [Turn]

    /// Keeps the last turns only, and says so in `complete`.
    public init(id: String, agent: String, title: String?, started: String?, turns: [Turn]) {
        (self.id, self.agent, self.title, self.started) = (id, agent, title, started)
        self.turns = Array(turns.suffix(Limits.turns))
        complete = turns.count <= Limits.turns
    }
}

public struct Turn: Codable, Equatable, Sendable, EveryKey {
    public var id: String
    /// "working", "done", "error", "interrupted" or "unknown".
    public var state: String
    public var started: String?
    public var ended: String?
    public var items: [Item]

    /// Keeps the last `Limits.items` items.
    public init(id: String, state: String, started: String?, ended: String?, items: [Item]) {
        (self.id, self.state, self.started, self.ended) = (id, state, started, ended)
        self.items = Array(items.suffix(Limits.items))
    }
}

public struct Item: Codable, Equatable, Sendable, EveryKey {
    public var id: String
    /// "message", "thought", "tool" or "subagent".
    public var kind: String
    /// "person" or "agent".
    public var author: String
    public var text: String
    public var at: String
    public var truncated: Bool
    public var tool: Tool?
    public var decision: Decision?

    /// Cuts `text` to `Limits.characters` characters, as a person counts them (Swift characters), and says so.
    public init(id: String, kind: String, author: String, text: String, at: String, tool: Tool? = nil, decision: Decision? = nil) {
        (self.id, self.kind, self.author, self.at, self.tool, self.decision) = (id, kind, author, at, tool, decision)
        truncated = text.count > Limits.characters
        self.text = truncated ? String(text.prefix(Limits.characters)) : text
    }
}

public struct Tool: Codable, Equatable, Sendable, EveryKey {
    public var name: String
    /// "running", "done", "failed", or nil.
    public var status: String?
    public init(name: String, status: String?) { (self.name, self.status) = (name, status) }
}

/// Who decided a permission, when the agent's own stream says it.
public struct Decision: Codable, Equatable, Sendable, EveryKey {
    /// "person", "hook", "rule" or "mode".
    public var by: String
    /// "allowed" or "denied".
    public var outcome: String
    public init(by: String, outcome: String) { (self.by, self.outcome) = (by, outcome) }
}

/// A permission or a question waiting for the person in a native window. A space sees it and never answers it.
public struct Request: Codable, Equatable, Sendable, EveryKey {
    public var id: String
    public var agent: String
    /// "permission" or "question".
    public var kind: String
    public var tool: String?
    public var about: String?
    public var at: String

    public init(id: String, agent: String, kind: String, tool: String?, about: String?, at: String) {
        (self.id, self.agent, self.kind, self.tool, self.about, self.at) = (id, agent, kind, tool, about, at)
    }
}

/// What the person allowed this space, and what can never be done here.
public struct Granted: Codable, Equatable, Sendable, EveryKey {
    public var rights: [String] = [], refused: [String] = [], unavailable: [String] = []
    /// Per kind, the `can` entries that are always false here.
    public var limits: [String: [String]] = [:]
    public var agents: Scope = .folders([])
    public var folder: String?
    public init() {}
}

/// Which agents a space may see: `{"see":"all"}` or `{"folders":[...]}`.
public enum Scope: Codable, Equatable, Sendable {
    case all
    case folders([String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: NameKey.self)
        if let folders = try container.decodeIfPresent([String].self, forKey: NameKey("folders")) {
            self = .folders(folders)
        } else if try container.decodeIfPresent(String.self, forKey: NameKey("see")) == "all" {
            self = .all
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "agents is neither {\"see\":\"all\"} nor {\"folders\":[...]}"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: NameKey.self)
        switch self {
        case .all: try container.encode("all", forKey: NameKey("see"))
        case .folders(let folders): try container.encode(folders, forKey: NameKey("folders"))
        }
    }
}

/// Any JSON value, for `detail`, which the contract does not shape. Numbers are Doubles: an integer above 2^53 loses
/// precision, which is acceptable outside the contract.
public enum JSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

extension State {
    /// The state as JSON with sorted keys and plain slashes, the bytes a space receives.
    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
