// What a space keeps between openings: its memory, one JSON object per space (~/something/data/<name>.json), read
// and written by path; and its journal, one JSON line per write action, in a folder the engine chooses, never
// exported. Folders are parameters so tests never touch a real home. Both are keyed by the space's name, so they
// belong to the spaces under the root only; a space located elsewhere by path has neither. Neither takes a lock: a
// read, change and write is not atomic across callers, so callers serialize the calls on one space (the app makes
// them on the main actor).
import Foundation

public struct Memory: Sendable {
    public let file: URL
    /// Above this the memory is STORE_FULL. Decimal megabytes, as for the weight of a space.
    public static let limit = Size.heavy

    public init(folder: URL, space: String) { file = folder.appendingPathComponent("\(space).json") }

    /// ~/something/data under `home`.
    public static func folder(home: URL) -> URL { home.appendingPathComponent("something/data") }

    /// The value at `path` (keys joined by "/"; "" is the whole document), or nil when nothing is there.
    /// Throws BAD_PARAMS for a path with an empty key, and a `SpaceError` when the file is not a JSON object.
    public func get(_ path: String) throws -> Any? {
        var value: Any? = try document()
        for key in try keys(path) { value = (value as? [String: Any])?[key] }
        return value
    }

    /// Puts `value` (any JSON value; NSNull removes) at `path`, making the objects on the way, and writes the whole
    /// document at once, so a crash leaves the old memory or the new one, never half of it.
    /// Throws BAD_PARAMS for a bad path or value, STORE_FULL past 5 MB, and a `SpaceError` when the file is not a
    /// JSON object or cannot be written. The file is unchanged when it throws.
    public func set(_ path: String, _ value: Any) throws {
        let keys = try keys(path)
        var next: [String: Any]
        if keys.isEmpty {
            guard let whole = value is NSNull ? [:] : value as? [String: Any] else {
                throw CodedError("BAD_PARAMS", "The whole memory is one JSON object: store.set(\"\", value) takes an object, or null to empty it.")
            }
            next = whole
        } else {
            next = try put(value, at: keys[...], in: document())
        }
        guard JSONSerialization.isValidJSONObject(next) else {
            throw CodedError("BAD_PARAMS", "store.set takes JSON values: text, numbers, true/false, null, lists and objects.")
        }
        let data = try JSONSerialization.data(withJSONObject: next, options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= Self.limit else {
            throw CodedError("STORE_FULL", "The memory would weigh \(Size.words(data.count)); the limit is 5 MB.")
        }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            throw SpaceError("The memory could not be written to \(file.path): \(error.localizedDescription)")
        }
    }

    /// The document, or an empty one when the file does not exist yet. A file that is there but not a JSON object
    /// throws instead of reading as empty: the next write would erase it.
    private func document() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        guard let data = try? Data(contentsOf: file), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SpaceError("The memory in \(file.path) is not a JSON object; something leaves it as it is. Move it away to start an empty memory.")
        }
        return object
    }

    private func keys(_ path: String) throws -> [String] {
        guard !path.isEmpty else { return [] }
        let keys = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !keys.contains("") else {
            throw CodedError("BAD_PARAMS", "\"\(path)\" has an empty key: a path is keys joined by /, for example settings/theme.")
        }
        return keys
    }

    private func put(_ value: Any, at keys: ArraySlice<String>, in object: [String: Any]) throws -> [String: Any] {
        var object = object
        let key = keys.first!
        guard keys.count > 1 else {
            object[key] = value is NSNull ? nil : value
            return object
        }
        // Removing under a key that is not there changes nothing; it does not make empty objects on the way.
        if object[key] == nil, value is NSNull { return object }
        guard let child = object[key] as? [String: Any] ?? (object[key] == nil ? [:] : nil) else {
            throw CodedError("BAD_PARAMS", "\"\(key)\" holds a value that is not an object, so nothing can be put inside it.")
        }
        object[key] = try put(value, at: keys.dropFirst(), in: child)
        return object
    }
}

/// One line of a space's journal (contract 7). Keys without a value are left out, as shape.json's JournalLine allows:
/// an `open` has no agent.
public struct JournalLine: Codable, Equatable, Sendable {
    public var at: String
    /// "send", "interrupt", "set", "launch", "resume" or "open".
    public var action: String
    public var agent: String?, kind: String?, when: String?, text: String?
    /// "ok" or a bridge code.
    public var result: String

    /// Cuts `text` to `Journal.characters` characters: the journal says what was done, it is not a transcript.
    public init(at: String, action: String, agent: String? = nil, kind: String? = nil, when: String? = nil, text: String? = nil, result: String) {
        (self.at, self.action, self.agent, self.kind, self.when, self.result) = (at, action, agent, kind, when, result)
        self.text = text.map { String($0.prefix(Journal.characters)) }
    }
}

public struct Journal: Sendable {
    public let folder: URL
    /// Past this a journal keeps its newest half, so it never grows without end.
    public static let limit = 1_000_000, characters = 2_000

    public init(folder: URL) { self.folder = folder }

    public func file(_ space: String) -> URL { folder.appendingPathComponent("\(space).jsonl") }

    /// Adds one line at the end of the space's journal, then keeps the newest half if it passed `limit`.
    /// Throws a `SpaceError` when the journal cannot be written.
    public func append(_ line: JournalLine, space: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let url = file(space)
        do {
            let data = try encoder.encode(line) + Data("\n".utf8)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url) }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            if try handle.seekToEnd() + UInt64(data.count) > Self.limit { try rotate(url, adding: data) } else { try handle.write(contentsOf: data) }
        } catch {
            throw SpaceError("The journal could not be written to \(url.path): \(error.localizedDescription)")
        }
    }

    /// The last `count` lines of the space's journal, oldest first; empty when it has none.
    /// A line that does not decode is left out, so fewer than `count` may come back: the engine wrote every line, and
    /// only a hand edit breaks one. Throws a `SpaceError` when the file exists but cannot be read.
    public func last(_ count: Int, space: String) throws -> [JournalLine] {
        guard count > 0 else { return [] }
        let url = file(space)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let data = try? Data(contentsOf: url) else { throw SpaceError("The journal in \(url.path) cannot be read.") }
        let lines = data.split(separator: UInt8(ascii: "\n")).suffix(count)
        return lines.compactMap { try? JSONDecoder().decode(JournalLine.self, from: Data($0)) }
    }

    /// Keeps the newest half of the journal and the new line, cut at a line's start, written at once.
    private func rotate(_ url: URL, adding line: Data) throws {
        let data = try Data(contentsOf: url) + line
        var kept = data.suffix(Self.limit / 2)
        if kept.startIndex > data.startIndex, data[kept.startIndex - 1] != UInt8(ascii: "\n"),
           let end = kept.firstIndex(of: UInt8(ascii: "\n")) {
            kept = kept[(end + 1)...]
        }
        try Data(kept).write(to: url, options: .atomic)
    }
}
