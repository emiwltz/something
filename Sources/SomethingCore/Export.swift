// A space as one file: its page, exact to the byte, with one block after its doctype that holds a `.something` document
// without the page, something.js and offline.js, so a browser shows the page and an import gets the space back. The
// `.something` document itself is one JSON object with its files in base64 and its memory or null, written from the
// space's own files only, never through a link. Reading and placing one refuses a path that is not a plain path inside
// the space, a newer contract, and a file too big, before anything is written.
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

    /// The one HTML file for `space`: its page with the block after its doctype. The block holds what `document` gives,
    /// less the page's own bytes, so an export's page is the page that comes in; `bridge` and `offline` are the texts
    /// of something.js and offline.js. Throws as `document` does, and when the file could not be imported back.
    public static func page(_ space: Space, data: [String: Any]?, app: String, bridge: String, offline: String, at: Date = Date()) throws -> Data {
        let path = space.form == .file ? "\(space.name).html" : "index.html"
        guard var object = try JSONSerialization.jsonObject(with: try document(space, data: data, app: app, at: at)) as? [String: Any],
              var files = object["files"] as? [String: String], let page = files.removeValue(forKey: path).flatMap({ Data(base64Encoded: $0) }) else {
            throw SpaceError("The page of \(space.name) cannot be read, so it was not exported.")
        }
        object["files"] = files
        // Nothing in JSON but a string holds a "<", so no value can end its script.
        let json = String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
            .replacingOccurrences(of: "<", with: "\\u003c")
        let block = """
            <!-- something export -->
            <meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="default-src 'unsafe-inline' data: blob:; form-action 'none'">
            \(opener)\(json)</script>
            <script>if (!window.something) { \(bridge) }</script>
            <script>\(offline)</script>
            <!-- /something export -->

            """
        let at = opening(of: page), html = Data(page[..<at]) + Data(block.utf8) + Data(page[at...])
        guard html.count <= fileLimit else {
            throw SpaceError("The export of \(space.name) would weigh \(Size.words(html.count)); an import takes at most 20 MB, about 15 MB of files.")
        }
        return html
    }

    /// The `.something` document an HTML file from `page` holds, its page put back byte for byte, for `read`; nil when
    /// the file has no block, or one that does not read: then it is a plain page.
    public static func unwrap(_ html: Data) -> Data? {
        // Its files are lighter here than in base64, so past this the document could not be read either.
        guard html.count <= fileLimit else { return nil }
        let at = opening(of: html)
        guard html[at...].starts(with: begin), let end = html.range(of: Data("<!-- /something export -->\n".utf8), in: at..<html.endIndex),
              let from = html.range(of: Data(opener.utf8), in: at..<end.lowerBound),
              let to = html.range(of: Data("</script>".utf8), in: from.upperBound..<end.lowerBound),
              var object = (try? JSONSerialization.jsonObject(with: html[from.upperBound..<to.lowerBound])) as? [String: Any],
              var files = object["files"] as? [String: String], let name = object["name"] as? String else { return nil }
        files[object["form"] as? String == "file" ? "\(name).html" : "index.html"] = (Data(html[..<at]) + Data(html[end.upperBound...])).base64EncodedString()
        object["files"] = files
        return try? JSONSerialization.data(withJSONObject: object)
    }

    /// The most an HTML file may weigh: `limit`, and room for its scripts.
    private static let fileLimit = limit + 1_000_000, begin = Data("<!-- something export -->\n".utf8), opener = "<script type=\"application/json\" id=\"something-export\">"

    /// Where the block goes in `page`, or stands in a file made from one: past a byte order mark, white space, comments
    /// and the doctype, since anything else before a doctype would turn the page to quirks mode. HTML allows the place:
    /// the `<html>` and `<head>` that come after only merge. The same bytes come before it in both, so both find it.
    private static func opening(of page: Data) -> Data.Index {
        var at = page.startIndex + (page.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0)
        while true {
            while at < page.endIndex, [0x09, 0x0A, 0x0C, 0x0D, 0x20].contains(page[at]) { at += 1 }
            let rest = page[at...]
            if rest.starts(with: begin) { return at }
            // HTML ends a comment at "--!>" too, and a block past one would land in the body, where no policy counts.
            let ends = ["-->", "--!>"].compactMap { page.range(of: Data($0.utf8), in: at..<page.endIndex) }
            if rest.starts(with: Data("<!--".utf8)), let end = ends.min(by: { $0.lowerBound < $1.lowerBound }) {
                at = end.upperBound
            } else if String(decoding: rest.prefix(9), as: UTF8.self).lowercased() == "<!doctype", let end = rest.firstIndex(of: 0x3E) {
                return end + 1
            } else {
                return at
            }
        }
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
