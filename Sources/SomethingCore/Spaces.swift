// Where spaces live and what they are made of: a single file <name>.html or a folder <name>/index.html under one
// root (~/something/spaces by default), each one's stamp (to know when to reload it), its weight, and `new`, which
// starts a space from the template. The root is a parameter so tests never touch a real home.
import Foundation

public struct Space: Equatable, Sendable {
    public enum Form: String, Sendable { case file, folder }

    public let name: String
    public let form: Form
    /// The .html file of a single-file space, or the folder of a folder space.
    public let location: URL

    /// The page to load: the file itself, or the folder's index.html.
    public var page: URL { form == .file ? location : location.appendingPathComponent("index.html") }

    /// Every file of the space, hidden files and folders left out, by path relative to the space, sorted.
    public func files() -> [(path: String, url: URL)] {
        guard form == .folder else { return [(location.lastPathComponent, location)] }
        // Relative paths from the walk itself: an absolute URL may come back resolved (/private/var for /var).
        let paths = FileManager.default.enumerator(atPath: location.path)?.allObjects as? [String] ?? []
        return paths.filter { !$0.split(separator: "/").contains { $0.hasPrefix(".") } }
            .map { (path: $0, url: location.appendingPathComponent($0)) }
            .filter { (try? $0.url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.path < $1.path }
    }

    /// The latest modification among the space's files; nil when none can be read. A change of any file, an image
    /// as much as the page, changes it, so the window reloads.
    public func stamp() -> Date? {
        files().compactMap { try? $0.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
    }

    /// What the space weighs: its files' bytes and how many files it has.
    public func size() -> Size {
        let files = files()
        let bytes = files.compactMap { try? $0.url.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
        return Size(bytes: bytes, files: files.count)
    }
}

public struct Size: Codable, Equatable, Sendable, EveryKey {
    public var bytes: Int, files: Int
    public init(bytes: Int, files: Int) { (self.bytes, self.files) = (bytes, files) }

    /// Above this a space is TOO_HEAVY. Decimal megabytes, as the person reads sizes in Finder.
    public static let heavy = 5_000_000

    /// "812 bytes", "48 KB", "6.2 MB": decimal units, as Finder writes them.
    public static func words(_ bytes: Int) -> String {
        if bytes < 1_000 { return "\(bytes) bytes" }
        if bytes < 1_000_000 { return "\(Int((Double(bytes) / 1_000).rounded())) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }
}

/// A failure that has no code in the contract, said in one sentence.
public struct SpaceError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

public struct Spaces: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }

    /// ~/something/spaces under `home`.
    public static func root(home: URL) -> URL { home.appendingPathComponent("something/spaces") }

    /// Lowercase letters, digits and "-": a name that is the same on every disk and safe in a file name.
    public static func isName(_ name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    /// Every space under the root, by name. A missing root has none. When a name has both forms, the folder is the
    /// space: it is the one that can hold more than a page.
    public func list() -> [Space] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let found = Set(names.compactMap { $0.hasSuffix(".html") ? String($0.dropLast(5)) : $0 }.filter(Self.isName))
        return found.sorted().compactMap(named)
    }

    /// The space with this name under the root, or nil.
    public func named(_ name: String) -> Space? {
        guard Self.isName(name) else { return nil }
        let folder = root.appendingPathComponent(name), file = root.appendingPathComponent("\(name).html")
        if isFile(folder.appendingPathComponent("index.html")) {
            return Space(name: name, form: .folder, location: folder)
        }
        return isFile(file) ? Space(name: name, form: .file, location: file) : nil
    }

    /// A space by name, or by the path of its .html file or its folder (anywhere, any name); nil when there is none.
    /// Memory and journal go by name and belong to spaces under the root, so a caller gives a space outside it neither.
    public func locate(_ nameOrPath: String) -> Space? {
        guard nameOrPath.contains("/") || nameOrPath.hasSuffix(".html") else { return named(nameOrPath) }
        let url = URL(fileURLWithPath: nameOrPath).standardizedFileURL
        if isFile(url.appendingPathComponent("index.html")) {
            return Space(name: url.lastPathComponent, form: .folder, location: url)
        }
        guard url.pathExtension == "html", isFile(url) else { return nil }
        return Space(name: url.deletingPathExtension().lastPathComponent, form: .file, location: url)
    }

    /// Writes a new single-file space, a copy of `template`, and returns it.
    /// Throws a `SpaceError` when the name breaks the rule, is taken, or the file cannot be written.
    public func new(_ name: String, from template: URL) throws -> Space {
        guard Self.isName(name) else {
            throw SpaceError("\"\(name)\" is not a space name: use lowercase letters, digits and -, for example morning-review.")
        }
        let file = root.appendingPathComponent("\(name).html")
        if named(name) != nil || FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) {
            throw SpaceError("A space named \(name) already exists in \(root.path); choose another name.")
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data(contentsOf: template).write(to: file, options: .withoutOverwriting)
        } catch {
            throw SpaceError("The space \(name) could not be written to \(file.path): \(error.localizedDescription)")
        }
        return Space(name: name, form: .file, location: file)
    }

    private func isFile(_ url: URL) -> Bool {
        var folder: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &folder) && !folder.boolValue
    }
}
