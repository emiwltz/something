// The protocol between a page and something: the page sends {"method": ..., "params": ...},
// something answers {"result": ...} or {"error": "..."}. The transport is the shell's business
// (a WebKit message handler on the Mac, HTTP or another webview elsewhere); the answers are decided here.
import Foundation

/// What the shell around the core must provide. Each platform asks the person in its own way:
/// `launch` lets them choose a folder, `send` asks their consent before anything reaches an agent.
public protocol BridgeHost {
    var state: V1State { get }
    /// Starts an agent and returns its id. Throws a `BridgeError` when the person declines or it cannot start.
    func launch(harness: String) throws -> String
    /// Sends a message to an agent. Throws a `BridgeError` when the person declines or the agent is gone.
    func send(agent: String, text: String) throws
    /// The memory of the page that asks; nil when the page has none.
    var store: PageStore? { get }
}

public struct BridgeError: Error, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

public enum Bridge {
    /// Answers one request from a page. Never throws: a failure becomes an `error` answer
    /// that says what happened and what to do.
    public static func answer(_ request: [String: Any], host: BridgeHost) -> [String: Any] {
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
    public static func json(_ state: V1State) -> Any {
        // Encoding these types cannot fail: they hold only strings, optionals and arrays.
        let data = try! JSONEncoder().encode(state)
        return try! JSONSerialization.jsonObject(with: data)
    }
}
