// Each space's past, kept in the engine's own folder, never in the spaces folder agents edit: Application
// Support/something/versions/<space>/, an index.json of its versions, newest first, and blobs/<sha256>, each file's
// content kept once however many versions hold it. A version is taken only when the space's files changed: after a turn
// of its assistant, named by the person's sentence, or for a change no turn claims ("Edited outside something").
// Restoring writes a version's files back, sends the files it did not have to the Trash, and is itself a version, so it
// can be undone the same way. A version's picture, once History took it, is kept beside it (thumbs/). The Preferences'
// limits (versions per space, the storage limit) drop the oldest versions first; the latest version of a space is never
// dropped, nor a space or its memory. A space heavier than an export carries (15 MB of files, 500 files) is not
// versioned, and says so; restoring it to an older version sends the files it changes to the Trash instead, so a space
// an agent overfilled can still go back. Clear Old Versions (Settings › Versions & Storage) drops the versions older
// than a date, each space keeping its newest few. Nothing is read or written through a symbolic link: a restore never
// writes outside the space.
import CryptoKit
import Foundation
import SomethingCore

struct Versions {
    /// What made a version: a turn of the assistant, a Quick Change (its temporary session's turn), an edit no turn
    /// claims, or the person restoring an older one.
    enum Kind: String, Codable { case turn, quick, outside, restore }

    struct Version: Codable, Equatable, Identifiable {
        let id: String, kind: Kind
        /// The person's sentence that asked for it; nil outside something and for a restore.
        let sentence: String?
        let when: Date
        /// The agent's name for a turn, "You" for a restore; nil outside something, where nobody is known.
        let who: String?
        /// Each file, by its path in the space, and the SHA-256 of its content: the name of its blob.
        let files: [String: String]
        /// What changed since the version before, in words: "brief.html · one line added".
        let summary: String
        /// The id of the version a restore brought back.
        var restored: String?
        /// The page's picture once History took it: a PNG in the store, `thumbs/<id>.png` of the space's folder.
        var thumb: String?
    }

    /// The most a space may weigh to be versioned: what an export carries, about 15 MB of files and 500 files.
    static let most = 15_000_000

    let root: URL
    /// Versions kept per space, 0 for all of them; the storage limit of the whole store in bytes, 0 for none.
    var keep: Int, limit: Int

    init(root: URL, keep: Int, limit: Int) { (self.root, self.keep, self.limit) = (root, keep, limit) }

    func folder(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }
    private func index(_ name: String) -> URL { folder(name).appendingPathComponent("index.json") }
    private func blob(_ name: String, _ hash: String) -> URL { folder(name).appendingPathComponent("blobs/\(hash)") }

    /// The versions kept for the space `name`, newest first; none when it has none or its index does not read.
    func list(_ name: String) -> [Version] { (try? read(name)) ?? [] }

    /// The versions of `name`, newest first; none when it has no index. Throws a `SpaceError` when its index is there
    /// but does not read: a version saved over it would lose the whole history.
    private func read(_ name: String) throws -> [Version] {
        guard FileManager.default.fileExists(atPath: index(name).path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do { return try decoder.decode([Version].self, from: Data(contentsOf: index(name))) } catch {
            throw SpaceError("The versions of \(name) do not read in \(index(name).path), so no new one was kept: \(error.localizedDescription)")
        }
    }

    /// Takes a version of `space` when its files differ from its latest version, or for a restore, and returns it; nil
    /// when nothing changed. Throws a `SpaceError` when the space is a link or too heavy to be versioned, or its store
    /// does not read or cannot be written.
    @discardableResult
    func capture(_ space: Space, kind: Kind, sentence: String? = nil, who: String? = nil, restored: String? = nil,
                 at when: Date = Date()) throws -> Version? {
        guard !Versions.isLink(space.location) else {
            throw SpaceError("something keeps no versions of \(space.name): it is a link to somewhere else.")
        }
        guard Versions.fits(space) else {
            let size = space.size()
            throw SpaceError("something keeps no versions of \(space.name): it has \(size.files) files weighing \(Size.words(size.bytes)), and versions are kept up to 15 MB and \(Export.most) files.")
        }
        var contents: [String: Data] = [:]
        for file in space.files() { contents[file.path] = try Data(contentsOf: file.url) }
        let files = contents.mapValues(Versions.hash)
        var versions = try read(space.name)
        // A restore is always said, even when the latest version already holds its files (a space too heavy had none).
        guard kind == .restore || files != versions.first?.files else { return nil }
        do {
            try FileManager.default.createDirectory(at: folder(space.name).appendingPathComponent("blobs"), withIntermediateDirectories: true)
            for (path, hash) in files where !FileManager.default.fileExists(atPath: blob(space.name, hash).path) {
                try contents[path]?.write(to: blob(space.name, hash), options: .atomic)
            }
        } catch {
            throw SpaceError("A version of \(space.name) could not be kept: \(error.localizedDescription)")
        }
        let before = versions.first.map { $0.files.compactMapValues { try? Data(contentsOf: blob(space.name, $0)) } }
        var version = Version(id: UUID().uuidString.lowercased(), kind: kind, sentence: sentence, when: when, who: who, files: files,
                              summary: Versions.summary(before, contents))
        version.restored = restored
        versions.insert(version, at: 0)
        try save(space.name, versions)
        prune()
        return version
    }

    /// Brings `space` back to its version `id`: what it is now is kept first when no version holds it, each file of
    /// the version is written back, and the files it did not have go to the Trash through `recycle`. A space too heavy
    /// to be versioned sends each file the restore changes or removes to the Trash first instead. Returns the restore's
    /// own version, nil when the space was already that version. Throws a `SpaceError` when the version is gone,
    /// incomplete, of the other form (a single page for a folder, or the reverse) or would write outside the space
    /// (nothing is written then), or a file cannot be written.
    @discardableResult
    func restore(_ id: String, of space: Space, recycle: (URL) throws -> Void, at when: Date = Date()) throws -> Version? {
        guard let chosen = list(space.name).first(where: { $0.id == id }) else {
            throw SpaceError("This version of \(space.name) is no longer kept.")
        }
        // Read whole before anything is written: a missing blob or a path out of the space restores nothing.
        var contents: [String: Data] = [:]
        for (path, hash) in chosen.files {
            let parts = path.split(separator: "/")
            guard !path.hasPrefix("/"), !parts.contains(".."), let data = try? Data(contentsOf: blob(space.name, hash)) else {
                throw SpaceError("This version of \(space.name) is incomplete in \(folder(space.name).path); nothing was restored.")
            }
            contents[path] = data
        }
        guard space.form == .file ? contents.count == 1 : contents["index.html"] != nil else {
            throw SpaceError(space.form == .file
                ? "This version of \(space.name) was a folder; the space is one file now, so nothing was restored."
                : "This version of \(space.name) was a single page; the space is a folder now, so nothing was restored.")
        }
        // A folder of the space replaced by a link would carry a write elsewhere on the Mac.
        guard !Versions.isLink(space.location), space.form == .file || contents.keys.allSatisfy({ inside(space.location.appendingPathComponent($0), space) }) else {
            throw SpaceError("\(space.name) holds a link to somewhere else where this version would write; nothing was restored.")
        }
        let wanted = { (file: (path: String, url: URL)) in space.form == .file ? contents.values.first : contents[file.path] }
        let heavy = !Versions.fits(space)
        if !heavy {
            let now = try Dictionary(uniqueKeysWithValues: space.files().map { ($0.path, Versions.hash(try Data(contentsOf: $0.url))) })
            if now == chosen.files { return nil }
            try capture(space, kind: .outside, at: when)
        }
        do {
            if heavy {
                // No version can hold it: each file the restore would overwrite or leave behind goes to the Trash.
                for file in space.files() where wanted(file) != (try? Data(contentsOf: file.url)) { try recycle(file.url) }
            }
            if space.form == .file, let data = contents.values.first {
                try data.write(to: space.location, options: .atomic)
            } else {
                for (path, data) in contents {
                    let url = space.location.appendingPathComponent(path)
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: url, options: .atomic)
                }
                for file in space.files() where contents[file.path] == nil { try recycle(file.url) }
            }
        } catch {
            throw SpaceError("\(space.name) was not fully restored: \(error.localizedDescription)")
        }
        return try capture(space, kind: .restore, who: "You", restored: chosen.id, at: when)
    }

    /// The picture of the version `id` of `name`, where `keep(picture:)` writes it.
    func picture(_ name: String, _ id: String) -> URL { folder(name).appendingPathComponent("thumbs/\(id).png") }

    /// Keeps `png` as the picture of the version `id` of `name`. Throws a `SpaceError` when the version is gone or the
    /// store cannot be written.
    func keep(picture png: Data, of id: String, in name: String) throws {
        var versions = try read(name)
        guard let index = versions.firstIndex(where: { $0.id == id }) else { throw SpaceError("This version of \(name) is no longer kept.") }
        do {
            try FileManager.default.createDirectory(at: picture(name, id).deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: picture(name, id), options: .atomic)
        } catch {
            throw SpaceError("The picture of a version of \(name) could not be kept: \(error.localizedDescription)")
        }
        versions[index].thumb = "thumbs/\(id).png"
        try save(name, versions)
    }

    /// Whether `space`'s files are now exactly those of `version`.
    func holds(_ space: Space, _ version: Version) -> Bool {
        let files = space.files()
        return files.count == version.files.count && files.allSatisfy { file in
            (try? Data(contentsOf: file.url)).map(Versions.hash) == version.files[file.path]
        }
    }

    /// What the versions of `name` weigh in the store, in bytes: their contents and pictures.
    func weight(_ name: String) -> Int {
        let walk = FileManager.default.enumerator(at: folder(name), includingPropertiesForKeys: [.fileSizeKey])
        return (walk?.allObjects as? [URL] ?? []).reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// Sends the versions of `name` to the Trash with its space, through `recycle`.
    func trash(_ name: String, recycle: (URL) throws -> Void) throws {
        if FileManager.default.fileExists(atPath: folder(name).path) { try recycle(folder(name)) }
    }

    /// Keeps the person's limits: each space its newest `keep` versions, then, while the store is heavier than
    /// `limit`, the oldest version of all goes, a space's latest never; then the contents no version holds. A space
    /// whose index does not read is left whole.
    func prune() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        var all = Dictionary(uniqueKeysWithValues: names.compactMap { name in (try? read(name)).map { (name, $0) } }.filter { !$0.1.isEmpty })
        if keep > 0 { all = all.mapValues { Array($0.prefix(keep)) } }
        func bytes(_ name: String) -> Int { Set(all[name, default: []].flatMap(\.files.values)).reduce(0) { $0 + size(name, $1) } }
        var weights = Dictionary(uniqueKeysWithValues: all.keys.map { ($0, bytes($0)) })
        while limit > 0, weights.values.reduce(0, +) > limit,
              let oldest = all.filter({ $0.value.count > 1 }).min(by: { ($0.value.last?.when ?? .distantFuture) < ($1.value.last?.when ?? .distantFuture) })?.key {
            all[oldest]?.removeLast()
            weights[oldest] = bytes(oldest)
        }
        keep(all)
    }

    /// What Clear Old Versions would take: the contents only the versions it drops hold, in bytes, and from how many
    /// spaces.
    struct Old: Equatable { var bytes = 0, spaces = 0 }

    /// What `clear(before:keeping:)` would drop, measured without changing anything.
    func old(before date: Date, keeping latest: Int) -> Old { weigh(trimmed(before: date, keeping: latest)) }

    /// Drops the versions older than `date`, each space keeping its `latest` newest, then the contents no version
    /// holds. A space whose index does not read is left whole. Returns what it dropped, weighed from the same read.
    @discardableResult func clear(before date: Date, keeping latest: Int) -> Old {
        let trimmed = trimmed(before: date, keeping: latest)
        let dropped = weigh(trimmed)
        keep(trimmed.mapValues(\.kept))
        return dropped
    }

    /// The bytes no kept version holds any more, and in how many spaces.
    private func weigh(_ trimmed: [String: (was: [Version], kept: [Version])]) -> Old {
        trimmed.reduce(into: Old()) { old, space in
            let held = Set(space.value.kept.flatMap(\.files.values))
            old.bytes += Set(space.value.was.flatMap(\.files.values)).subtracting(held).reduce(0) { $0 + size(space.key, $1) }
            old.spaces += 1
        }
    }

    /// Each space that has versions older than `date` beyond its `latest` newest: all its versions, and those kept.
    private func trimmed(before date: Date, keeping latest: Int) -> [String: (was: [Version], kept: [Version])] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return Dictionary(uniqueKeysWithValues: names.compactMap { name -> (String, ([Version], [Version]))? in
            guard let versions = try? read(name) else { return nil }
            let kept = versions.enumerated().filter { $0.offset < latest || $0.element.when >= date }.map(\.element)
            return kept.count < versions.count ? (name, (versions, kept)) : nil
        })
    }

    /// Writes each space's versions as `all` holds them, then removes the contents none of them holds.
    private func keep(_ all: [String: [Version]]) {
        for (name, versions) in all {
            if versions.count != list(name).count { try? save(name, versions) }
            let held = Set(versions.flatMap(\.files.values))
            let blobs = (try? FileManager.default.contentsOfDirectory(atPath: folder(name).appendingPathComponent("blobs").path)) ?? []
            for hash in blobs where !held.contains(hash) { try? FileManager.default.removeItem(at: blob(name, hash)) }
            let ids = Set(versions.map(\.id)), thumbs = folder(name).appendingPathComponent("thumbs")
            for file in (try? FileManager.default.contentsOfDirectory(atPath: thumbs.path)) ?? [] where !ids.contains(String(file.dropLast(4))) {
                try? FileManager.default.removeItem(at: thumbs.appendingPathComponent(file))
            }
        }
    }

    /// What changed from `before` (nil for a first version) to `after`, by file, in words; three files at most, then
    /// how many more.
    static func summary(_ before: [String: Data]?, _ after: [String: Data]) -> String {
        guard let before else { return after.count == 1 ? after.keys.first ?? "" : "\(after.count) files" }
        let changed = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }.sorted()
        let said = changed.prefix(3).map { path -> String in
            guard let old = before[path] else { return "\(path) · new file" }
            guard let new = after[path] else { return "\(path) · removed" }
            guard let one = String(data: old, encoding: .utf8), let other = String(data: new, encoding: .utf8) else { return "\(path) · changed" }
            let difference = other.components(separatedBy: "\n").difference(from: one.components(separatedBy: "\n"))
            let (added, removed) = (difference.insertions.count, difference.removals.count), both = min(added, removed)
            let lines = { (count: Int) in count == 1 ? "one line" : "\(count) lines" }
            let parts = [(both, "changed"), (added - both, "added"), (removed - both, "removed")].filter { $0.0 > 0 }
            return "\(path) · " + (parts.isEmpty ? "changed" : parts.enumerated().map { $0.offset == 0 ? "\(lines($0.element.0)) \($0.element.1)" : "\($0.element.0) \($0.element.1)" }.joined(separator: ", "))
        }
        return (said + (changed.count > 3 ? ["and \(changed.count - 3) more files"] : [])).joined(separator: "; ")
    }

    /// Whether `url`'s nearest folder that exists is the space's folder or within it, links resolved.
    private func inside(_ url: URL, _ space: Space) -> Bool {
        let root = space.location.resolvingSymlinksInPath().path
        var folder = url.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: folder.path), folder.pathComponents.count > 1 { folder.deleteLastPathComponent() }
        let real = folder.resolvingSymlinksInPath().path
        return real == root || real.hasPrefix(root + "/")
    }

    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// Whether `space` is light enough to be versioned: what an export carries.
    private static func fits(_ space: Space) -> Bool { let size = space.size(); return size.bytes <= most && size.files <= Export.most }

    private static func isLink(_ url: URL) -> Bool { (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true }

    private func size(_ name: String, _ hash: String) -> Int {
        (try? blob(name, hash).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private func save(_ name: String, _ versions: [Version]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { try encoder.encode(versions).write(to: index(name), options: .atomic) } catch {
            throw SpaceError("The versions of \(name) could not be written: \(error.localizedDescription)")
        }
    }
}
