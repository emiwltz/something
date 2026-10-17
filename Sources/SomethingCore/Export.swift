// A space as one `.something` file (contract 8): one JSON document with its files in base64 and its memory or null,
// written from the space's own files only; and the reading and placing of one, which refuses a path that would leave
// the space, a newer contract, and a file too big, before anything is written. Grants and journals are never read
// here, so they cannot travel; whoever imports drops the grants of the name the space receives (contract 5).
import Foundation

/// A `.something` document once read and checked: what an import writes.
public struct Received {
    public let name: String, form: Space.Form
    /// Each file by its path relative to the space, using "/".
    public let files: [String: Data]
    /// The memory, when the export carried it.
    public let data: [String: Any]?
}

public enum Export {
    public static let format = "something-space"
    /// Past these an import is IMPORT_TOO_BIG. Decimal megabytes, as for the weight of a space.
    public static let limit = 20_000_000, most = 500

    /// The document for `space`: its regular files (a link is not one, so a link to an agent's session never
    /// travels) and `data`, the memory, or null. `app` is this engine's version.
    /// Throws a `SpaceError` when a file cannot be read, the space is a link, or the document would be too big to
    /// import.
    public static func document(_ space: Space, data: [String: Any]?, app: String, at: Date = Date()) throws -> Data {
        guard (try? space.location.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == false else {
            throw SpaceError("\(space.location.path) is a link to somewhere else; something exports only a space's own files.")
        }
        let files = space.files()
        guard files.count <= most else {
            throw SpaceError("\(space.name) has \(files.count) files; an export holds at most \(most). Remove files the space does not use.")
        }
        var encoded: [String: String] = [:]
        for file in files {
            let kind = try? file.url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard kind?.isRegularFile == true, kind?.isSymbolicLink != true, let bytes = try? Data(contentsOf: file.url) else {
                throw SpaceError("\(file.url.path) is not a file of its own that can be read; something exports only the space's own files.")
            }
            encoded[file.path] = bytes.base64EncodedString()
        }
        let object: [String: Any] = ["format": format, "contract": Declaration.known, "exported": ISO8601DateFormatter().string(from: at),
                                     "app": app, "name": space.name, "form": space.form.rawValue, "files": encoded,
                                     "data": data.map { $0 as Any } ?? NSNull()]
        guard JSONSerialization.isValidJSONObject(object) else { throw SpaceError("The memory of \(space.name) is not JSON; it cannot be exported.") }
        let document = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        guard document.count <= limit else {
            throw SpaceError("The export of \(space.name) would weigh \(Size.words(document.count)); an import takes at most 20 MB.")
        }
        return document
    }

    /// The space a `.something` document holds, checked whole. Throws a `CodedError`: IMPORT_TOO_BIG (over 20 MB or
    /// 500 files), IMPORT_NOT_A_SPACE (not this format, or a key missing or of the wrong type), IMPORT_TOO_NEW (a
    /// contract higher than this engine knows), IMPORT_UNSAFE_PATH (absolute, `..`, `.` or an empty segment).
    public static func read(_ document: Data) throws -> Received {
        guard document.count <= limit else { throw CodedError("IMPORT_TOO_BIG", "This file weighs \(Size.words(document.count)); an import takes at most 20 MB.") }
        let notASpace = CodedError("IMPORT_NOT_A_SPACE", "This file is not a space exported by something.")
        guard let object = try? JSONSerialization.jsonObject(with: document) as? [String: Any], object["format"] as? String == format,
              let contract = object["contract"] as? Int else { throw notASpace }
        guard contract <= Declaration.known else {
            throw CodedError("IMPORT_TOO_NEW", "This space was exported for contract \(contract); this something knows contract \(Declaration.known).")
        }
        guard let files = object["files"] as? [String: String] else { throw notASpace }
        guard files.count <= most else { throw CodedError("IMPORT_TOO_BIG", "This space has \(files.count) files; an import takes at most \(most).") }
        if let path = files.keys.sorted().first(where: { !isSafe($0) }) {
            throw CodedError("IMPORT_UNSAFE_PATH", "The path \"\(path)\" would leave the space.")
        }
        guard let name = object["name"] as? String, Spaces.isName(name), let form = (object["form"] as? String).flatMap(Space.Form.init),
              form == .file ? Set(files.keys) == ["\(name).html"] : files["index.html"] != nil else { throw notASpace }
        var decoded: [String: Data] = [:]
        for (path, text) in files {
            guard let bytes = Data(base64Encoded: text) else { throw notASpace }
            decoded[path] = bytes
        }
        let data = object["data"]
        guard data is NSNull || data is [String: Any] else { throw notASpace }
        return Received(name: name, form: form, files: decoded, data: data as? [String: Any])
    }

    /// Writes `received` under `spaces`' root as a new space, with its memory in `memory` when it carries one, and
    /// returns it. A name already taken, by a space or by a memory left behind, becomes <name>-2, <name>-3...: a
    /// received space never takes over what is there. Throws STORE_FULL past 5 MB of memory, and a `SpaceError` when
    /// it cannot be written; then nothing of it is left.
    public static func place(_ received: Received, in spaces: Spaces, memory: URL) throws -> Space {
        let manager = FileManager.default
        func taken(_ name: String) -> Bool {
            [spaces.root.appendingPathComponent(name), spaces.root.appendingPathComponent("\(name).html"),
             Memory(folder: memory, space: name).file].contains { manager.fileExists(atPath: $0.path) }
        }
        guard let name = ([received.name] + (2...999).map { "\(received.name)-\($0)" }).first(where: { !taken($0) }) else {
            throw SpaceError("Every name from \(received.name) to \(received.name)-999 is taken in \(spaces.root.path).")
        }
        // Written in a hidden folder of the root first, then moved at once: a failure leaves no half space.
        let staging = spaces.root.appendingPathComponent(".import-\(UUID().uuidString)")
        let location = received.form == .file ? spaces.root.appendingPathComponent("\(name).html") : spaces.root.appendingPathComponent(name)
        defer { try? manager.removeItem(at: staging) }
        do {
            for (path, bytes) in received.files {
                let target = staging.appendingPathComponent(received.form == .file ? "\(name).html" : path)
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: target, options: .withoutOverwriting)
            }
            try manager.moveItem(at: received.form == .file ? staging.appendingPathComponent("\(name).html") : staging, to: location)
        } catch {
            throw SpaceError("The space \(name) could not be written to \(location.path): \(error.localizedDescription)")
        }
        do {
            if let data = received.data { try Memory(folder: memory, space: name).set("", data) }
        } catch {
            try? manager.removeItem(at: location)
            throw error
        }
        return Space(name: name, form: received.form, location: location)
    }

    /// Relative, with "/", and no segment that is empty, "." or "..". Two paths that differ only by case are caught
    /// when written: the second one finds the first one there.
    static func isSafe(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.contains("\0") && !path.split(separator: "/", omittingEmptySubsequences: false).contains { ["", ".", ".."].contains($0) }
    }
}
