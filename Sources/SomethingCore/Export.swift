// A space as one `.something` file: one JSON document with its files in base64 and its memory or null,
// written from the space's own files only, never through a link; and the reading and placing of one, which refuses a
// path that is not a plain path inside the space, a newer contract, and a file too big, before anything is written.
// Grants and journals are never read here, so they cannot travel; whoever imports drops the grants of the name the
// space receives before placing it.
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
    /// Past these an import is IMPORT_TOO_BIG. Decimal megabytes, as for the weight of a space. The limit is on the
    /// document, where base64 makes the files a third heavier: about 15 MB of files.
    public static let limit = 20_000_000, most = 500

    /// The document for `space`: its regular files and `data`, the memory, or null. `app` is this engine's version;
    /// `contract` is the one the space declares, so an engine that does not know it refuses the import.
    /// A link is never followed, so a link to an agent's session never travels; `links` names those left out.
    /// Throws a `SpaceError` when a file cannot be read, the space or its index.html is a link, or the document would
    /// be too big to import.
    public static func document(_ space: Space, data: [String: Any]?, app: String, at: Date = Date()) throws -> Data {
        guard !isLink(space.location) else {
            throw SpaceError("\(space.location.path) is a link to somewhere else; something exports only a space's own files.")
        }
        // Space.files() keeps regular files only, so a linked index.html is missing from it.
        let files = space.files()
        guard space.form == .file || files.contains(where: { $0.path == "index.html" }) else {
            throw SpaceError("The index.html of \(space.name) is a link to somewhere else; replace it with the file itself.")
        }
        guard files.count <= most else {
            throw SpaceError("\(space.name) has \(files.count) files; an export holds at most \(most). Remove files the space does not use.")
        }
        var encoded: [String: String] = [:]
        for file in files {
            guard let bytes = try? Data(contentsOf: file.url) else { throw SpaceError("\(file.url.path) cannot be read, so \(space.name) was not exported.") }
            encoded[file.path] = bytes.base64EncodedString()
        }
        // Only the contract number is read, and the kinds do not change it.
        let object: [String: Any] = ["format": format, "contract": Declaration.declared(in: space, kinds: .contract1).contract, "exported": iso8601.string(from: at),
                                     "app": app, "name": space.name, "form": space.form.rawValue, "files": encoded,
                                     "data": data.map { $0 as Any } ?? NSNull()]
        guard JSONSerialization.isValidJSONObject(object) else { throw SpaceError("The memory of \(space.name) is not JSON; it cannot be exported.") }
        let document = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        guard document.count <= limit else {
            throw SpaceError("The export of \(space.name) would weigh \(Size.words(document.count)) with its files in base64; an import takes at most 20 MB, about 15 MB of files.")
        }
        return document
    }

    /// The paths of the links in a folder space, sorted: what its export leaves out. A file space has none here (a
    /// linked one is refused whole). Hidden paths are not part of the space and are not listed.
    public static func links(_ space: Space) -> [String] {
        guard space.form == .folder else { return [] }
        let paths = FileManager.default.enumerator(atPath: space.location.path)?.allObjects as? [String] ?? []
        return paths.filter { !$0.split(separator: "/").contains { $0.hasPrefix(".") } && isLink(space.location.appendingPathComponent($0)) }.sorted()
    }

    /// The memory of the space `name` in `folder`, as an export may carry it; nil when it is empty or there is none.
    /// Throws a `SpaceError` when the memory file is a link (it could lead to an agent's file) or not a JSON object.
    public static func memory(_ name: String, in folder: URL) throws -> [String: Any]? {
        let memory = Memory(folder: folder, space: name)
        guard !isLink(memory.file) else {
            throw SpaceError("\(memory.file.path) is a link to somewhere else; something exports only a space's own memory.")
        }
        let whole = try memory.get("") as? [String: Any] ?? [:]
        return whole.isEmpty ? nil : whole
    }

    /// The space a `.something` document holds, checked whole. Throws a `CodedError`: IMPORT_TOO_BIG (over 20 MB or
    /// 500 files), IMPORT_NOT_A_SPACE (not this format, or a key missing or of the wrong type), IMPORT_TOO_NEW (a
    /// contract higher than this engine knows), IMPORT_UNSAFE_PATH (absolute, `..`, an empty or a hidden segment).
    public static func read(_ document: Data) throws -> Received {
        guard document.count <= limit else { throw CodedError("IMPORT_TOO_BIG", "This file weighs \(Size.words(document.count)); an import takes at most 20 MB.") }
        let notASpace = CodedError("IMPORT_NOT_A_SPACE", "This file is not a space exported by something.")
        guard let object = try? JSONSerialization.jsonObject(with: document) as? [String: Any], object["format"] as? String == format,
              let contract = object["contract"] as? Int else { throw notASpace }
        guard contract <= Declaration.known else {
            throw CodedError("IMPORT_TOO_NEW", "This space needs a newer version of something (it was made for contract \(contract), this one knows \(Declaration.known)).")
        }
        guard let files = object["files"] as? [String: String] else { throw notASpace }
        guard files.count <= most else { throw CodedError("IMPORT_TOO_BIG", "This space has \(files.count) files; an import takes at most \(most).") }
        if let path = files.keys.sorted().first(where: { !isSafe($0) }) {
            throw CodedError("IMPORT_UNSAFE_PATH", "The path \"\(path)\" is not a plain path inside the space.")
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

    /// The name `received` gets under `spaces`' root: its own, or <name>-2, <name>-3... when a space or a memory left
    /// behind has it, so that a received space never takes over what is there. Throws a `SpaceError` past <name>-999.
    public static func freeName(_ received: Received, in spaces: Spaces, memory: URL) throws -> String {
        guard let name = ([received.name] + (2...999).map { "\(received.name)-\($0)" }).first(where: { !taken($0, spaces, memory) }) else {
            throw SpaceError("Every name from \(received.name) to \(received.name)-999 is taken in \(spaces.root.path).")
        }
        return name
    }

    /// Writes `received` under `spaces`' root as the new space `name` (from `freeName`), with its memory in `memory`
    /// when it carries one, and returns it. Throws STORE_FULL past 5 MB of memory, and a `SpaceError` when the name
    /// was taken in the meantime or the space cannot be written; then nothing of it is left.
    public static func place(_ received: Received, as name: String, in spaces: Spaces, memory: URL) throws -> Space {
        let manager = FileManager.default
        guard Spaces.isName(name), !taken(name, spaces, memory) else { throw SpaceError("A space named \(name) already exists in \(spaces.root.path).") }
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

    private static func taken(_ name: String, _ spaces: Spaces, _ memory: URL) -> Bool {
        [spaces.root.appendingPathComponent(name), spaces.root.appendingPathComponent("\(name).html"),
         Memory(folder: memory, space: name).file].contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func isLink(_ url: URL) -> Bool { (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true }

    /// Relative, with "/", and no segment that is empty, "..", or hidden ("." and ".git" alike): an export never holds
    /// a hidden file, and one placed would be neither served, counted nor shown. Two paths that differ only by case
    /// are caught when written: the second one finds the first one there.
    static func isSafe(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.contains("\0") && !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0.isEmpty || $0.hasPrefix(".") }
    }
}
