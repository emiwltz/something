// V1's state, still what the V1 drivers fill and the template page reads; Contract.swift is contract 1's.
// The V1 prefix keeps both apart until the drivers move to events and this file goes.
// Foundation only: this file must build on any platform Swift runs on.
import Foundation

public struct Message: Codable, Equatable, Sendable {
    /// "you" or "agent".
    public var from: String
    public var text: String

    public init(from: String, text: String) {
        self.from = from
        self.text = text
    }
}

/// A question an agent is waiting on: may it use this tool? Answered in a native window, never by a page.
public struct PermissionRequest: Equatable, Sendable {
    public var id: String
    /// The tool the agent wants to use, as the agent names it ("Write", "Bash", ...).
    public var tool: String
    /// What the agent says it will do with it; nil when it says nothing.
    public var about: String?

    public init(id: String, tool: String, about: String? = nil) {
        self.id = id
        self.tool = tool
        self.about = about
    }
}

extension PermissionRequest: Codable {
    private enum Key: String, CodingKey { case id, tool, about }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(id, forKey: .id)
        try c.encode(tool, forKey: .tool)
        try c.encode(about, forKey: .about)
    }
}

public struct V1Agent: Equatable, Sendable {
    public var id: String
    public var name: String
    /// The program that runs the agent: "claude", later "codex", "opencode", "pi".
    public var harness: String
    /// The folder the agent works in.
    public var folder: String
    /// "working", "waiting" (on `request`), "idle" or "stopped"; nil until the agent has said anything.
    public var status: String?
    /// nil until the agent has said which model it runs.
    public var model: String?
    /// The agent's permission mode ("default", "plan", ...); nil until it has said.
    public var mode: String?
    public var messages: [Message]
    /// The permission the agent is waiting on; nil when it waits on nothing.
    public var request: PermissionRequest?
    /// What went wrong, in one sentence; nil when nothing did.
    public var error: String?

    public init(id: String, name: String, harness: String, folder: String,
                status: String? = nil, model: String? = nil, mode: String? = nil,
                messages: [Message] = [], request: PermissionRequest? = nil, error: String? = nil) {
        self.id = id
        self.name = name
        self.harness = harness
        self.folder = folder
        self.status = status
        self.model = model
        self.mode = mode
        self.messages = messages
        self.request = request
        self.error = error
    }
}

extension V1Agent: Codable {
    private enum Key: String, CodingKey { case id, name, harness, folder, status, model, mode, messages, request, error }

    // JSONEncoder drops nil values by default. A page must see `null`, so that a missing key
    // never passes for a value nobody sent.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(harness, forKey: .harness)
        try c.encode(folder, forKey: .folder)
        try c.encode(status, forKey: .status)
        try c.encode(model, forKey: .model)
        try c.encode(mode, forKey: .mode)
        try c.encode(messages, forKey: .messages)
        try c.encode(request, forKey: .request)
        try c.encode(error, forKey: .error)
    }
}

public struct V1State: Codable, Equatable, Sendable {
    public var agents: [V1Agent]

    public init(agents: [V1Agent] = []) {
        self.agents = agents
    }
}
