// V1's bridge, which the template page (share/v1.js) still talks through until the space window arrives (slice 5):
// the page sends {"method": ..., "params": ...}, something answers {"result": ...} or {"error": "..."}. Contract 1's
// bridge is SomethingCore/Bridge.swift. Also V1's page memory, kept by key in one file.
import Foundation
import SomethingAgents

/// What the shell around the core must provide. Each platform asks the person in its own way:
/// `launch` lets them choose a folder, `send` asks their consent before anything reaches an agent.
protocol V1BridgeHost {
    var state: V1State { get }
    /// Starts an agent and returns its id. Throws a `BridgeError` when the person declines or it cannot start.
    func launch(harness: String) throws -> String
    /// Sends a message to an agent. Throws a `BridgeError` when the person declines or the agent is gone.
    func send(agent: String, text: String) throws
    /// The memory of the page that asks; nil when the page has none.
    var store: PageStore? { get }
}

enum V1Bridge {
    /// Answers one request from a page. Never throws: a failure becomes an `error` answer
    /// that says what happened and what to do.
    static func answer(_ request: [String: Any], host: V1BridgeHost) -> [String: Any] {
        let params = request["params"] as? [String: Any] ?? [:]
        do {
            switch request["method"] as? String {
            case "state":
                return ["result": json(host.state)]
            case "launch":
                return ["result": try host.launch(harness: params["harness"] as? String ?? "claude")]
            case "send":
                guard let agent = params["agent"] as? String, let text = params["text"] as? String,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw BridgeError("send needs an \"agent\" id and a non-empty \"text\".")
                }
                try host.send(agent: agent, text: text)
                return ["result": NSNull()]
            case "store.get", "store.set":
                guard let store = host.store else { throw BridgeError("This page has no memory.") }
                guard let key = params["key"] as? String else { throw BridgeError("\(request["method"]!) needs a \"key\".") }
                if request["method"] as? String == "store.get" { return ["result": store.get(key) ?? NSNull()] }
                try store.set(key, params["value"] ?? NSNull())
                return ["result": NSNull()]
            case let method?:
                throw BridgeError("Unknown method \"\(method)\". Known: state, launch, send, store.get, store.set.")
            case nil:
                throw BridgeError("A request needs a \"method\", for example {\"method\": \"state\"}.")
            }
        } catch let error as BridgeError {
            return ["error": error.message]
        } catch {
            return ["error": "\(error)"]
        }
    }

    /// The state as plain JSON objects, the shape a page receives.
    static func json(_ state: V1State) -> Any {
        // Encoding these types cannot fail: they hold only strings, optionals and arrays.
        let data = try! JSONEncoder().encode(state)
        return try! JSONSerialization.jsonObject(with: data)
    }
}

final class PageStore {
    let file: URL
    private var values: [String: Any]

    /// Reads `file` if it exists. A missing or unreadable file starts an empty store: the page loses
    /// its memory, never its window.
    init(file: URL) {
        self.file = file
        let data = try? Data(contentsOf: file)
        values = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    /// The value kept under `key`, or nil when there is none.
    func get(_ key: String) -> Any? { values[key] }

    /// Keeps `value` under `key` and writes the file. NSNull removes the key.
    /// Throws a `BridgeError` when the value is not JSON or the file cannot be written.
    func set(_ key: String, _ value: Any) throws {
        var next = values
        next[key] = value is NSNull ? nil : value
        guard JSONSerialization.isValidJSONObject(next) else {
            throw BridgeError("store.set takes JSON values: text, numbers, true/false, null, lists and objects.")
        }
        do {
            try JSONSerialization.data(withJSONObject: next, options: [.sortedKeys]).write(to: file, options: .atomic)
        } catch {
            throw BridgeError("The page's memory could not be written to \(file.path).")
        }
        values = next
    }
}
