// A page's own memory (the mood of a Tamagotchi, a chosen tab): JSON values by key, kept in one file
// in the person's data folder (~/something/data/<name>.json). Agents never see it; it is not state.
import Foundation

public final class PageStore {
    public let file: URL
    private var values: [String: Any]

    /// Reads `file` if it exists. A missing or unreadable file starts an empty store: the page loses
    /// its memory, never its window.
    public init(file: URL) {
        self.file = file
        let data = try? Data(contentsOf: file)
        values = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    /// The value kept under `key`, or nil when there is none.
    public func get(_ key: String) -> Any? { values[key] }

    /// Keeps `value` under `key` and writes the file. NSNull removes the key.
    /// Throws a `BridgeError` when the value is not JSON or the file cannot be written.
    public func set(_ key: String, _ value: Any) throws {
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
