// What the app remembers for the person apart from the grants, in window.json: the window's memory (the last space
// open, the recent ones, the groups of the sidebar and their folding, the names Rename… shows in place of a space's
// title, since a space's own name is its file and its grants are keyed by it),
// whether the welcome and each hint were seen, and the settings, whose defaults are the approved mockup's. One copy per file, read once
// and shared by every model of the window, so that no write undoes another's; each change is written at once,
// atomically, over the keys this version knows: a key it does not know is kept as it was.
import Foundation
import Observation
import SomethingCore

@dynamicMemberLookup @Observable final class Preferences {
    enum Appearance: String, Codable { case system, light, dark }
    typealias Motion = Look.Motion
    /// A group of the sidebar: its name and the names of its spaces, in order. The files never move.
    struct Group: Codable, Equatable { var name: String, spaces: [String] }
    /// Where the sticker rests, the same over every space: against the trailing or the leading side, its surface
    /// `offset` points from the bottom or the top edge of the center under the toolbar, whichever is nearer, so that it
    /// keeps its place against those edges when the center resizes.
    struct StickerPlace: Codable, Equatable { var trailing: Bool, bottom: Bool, offset: Double }

    /// Every value kept. A missing key, or one this version cannot read, has its default.
    struct Values: Codable, Equatable {
        var lastOpen: String?
        /// The kind of the default agent; nil for the first builder found. The model and effort are nil for the
        /// agent's own.
        var assistant: String?, model: String?, effort: String?
        /// The models and efforts each kind's agent last listed, by kind: the model chip offers them before it runs.
        var listed: [String: Options] = [:]
        /// The commands each kind's agent last listed, by kind: "/" in the card offers them before it runs.
        var commands: [String: [Option]] = [:]
        var askEverything = false, resume = true, toured = false
        /// Full Access: something allows every permission the person's assistant asks, by itself (Settings › Advanced).
        var fullAccess = false
        /// The hints already shown (Hint.swift), each once.
        var hinted: [String] = []
        var groups: [Group] = [], folded: [String] = [], names: [String: String] = [:], recents: [String] = []
        /// "last", "new", or the name of a space.
        var openAtStart = "last"
        /// Motion is no longer a setting (the Mac's Reduce Motion lowers it, Look.motion); an older file's choice holds.
        var appearance = Appearance.system, motion = Motion.calm, size = Look.Size.standard, notify = false
        /// What a new space may do with the agents when its words name none (Grant.Level.guess): None, as before
        /// Settings had the row, so that a page sees no agent unless asked.
        var level = Grant.Level.none
        /// Whether an export carries a space's memory, until the person answers for that space (`memoryExport`).
        var exportMemory = false
        /// What the person last answered, by space, at Include Its Memory.
        var memoryExport: [String: Bool] = [:]
        /// nil while it rests at its first place, the bottom trailing corner.
        var sticker: StickerPlace?
        /// Minutes; 0 for never.
        var sleepAfter = 10
        var awakeAtMost = 3
        /// Versions kept per space, 0 for all of them; the storage limit in MB.
        var versionsKept = 50, storageLimit = 500

        enum CodingKeys: String, CodingKey, CaseIterable {
            case lastOpen, assistant, model, effort, listed, commands, askEverything, fullAccess, resume, toured, hinted, groups, folded, names,
                 recents, openAtStart, appearance, motion, size, notify, level, exportMemory, memoryExport, sticker, sleepAfter, awakeAtMost,
                 versionsKept, storageLimit
        }

    }

    /// How many recent spaces are kept, the most recent first.
    static let recentLimit = 10

    @ObservationIgnored let file: URL
    private(set) var values: Values
    /// What the file held, the keys this version does not know included.
    @ObservationIgnored private var kept: [String: Any]
    private static var shared: [String: Preferences] = [:]
    private static let lock = NSLock()

    /// The preferences kept in `places`, read from window.json now: what a later start would read.
    init(_ places: Places) {
        file = places.window
        kept = (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        // Each key on its own over the defaults: one value of the wrong type falls back to its default, never the whole file.
        func decoded(_ json: [String: Any]) -> Values? {
            (try? JSONSerialization.data(withJSONObject: json)).flatMap { try? JSONDecoder().decode(Values.self, from: $0) }
        }
        var read = (try? JSONEncoder().encode(Values())).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        for (key, value) in kept where Values.CodingKeys(rawValue: key) != nil {
            var tried = read
            tried[key] = value
            if decoded(tried) != nil { read = tried }
        }
        values = decoded(read) ?? Values()
    }

    /// The one copy of the preferences kept in `places`, read the first time it is asked for.
    static func at(_ places: Places) -> Preferences {
        lock.lock()
        defer { lock.unlock() }
        if let known = shared[places.window.path] { return known }
        let preferences = Preferences(places)
        shared[places.window.path] = preferences
        return preferences
    }

    subscript<T>(dynamicMember key: WritableKeyPath<Values, T>) -> T {
        get { values[keyPath: key] }
        set { change { $0[keyPath: key] = newValue } }
    }

    /// Changes the values, then writes them when they changed. A file that cannot be written loses only this
    /// change on disk; the app goes on with it.
    func change(_ body: (inout Values) -> Void) {
        var new = values
        body(&new)
        guard new != values else { return }
        values = new
        let known = Set(Values.CodingKeys.allCases.map(\.rawValue))
        var merged = kept.filter { !known.contains($0.key) }
        let encoded = (try? JSONEncoder().encode(new)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        merged.merge(encoded) { _, written in written }
        kept = merged
        guard let data = try? JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// The space `name` was opened: it is the last one open and the first of the recent ones.
    func opened(_ name: String?) {
        change { values in
            values.lastOpen = name
            if let name { values.recents = Array(([name] + values.recents.filter { $0 != name }).prefix(Preferences.recentLimit)) }
        }
    }

    // MARK: The sidebar's groups, only a view: no file ever moves.

    /// The group `space` shows in: the first that names it; nil when none does.
    func group(of space: String) -> String? { values.groups.first { $0.spaces.contains(space) }?.name }

    /// Puts `space` at the end of the group `name`, made when missing and unfolded so the space shows, and takes it
    /// out of every other group.
    func move(_ space: String, to name: String) {
        change { values in
            for index in values.groups.indices { values.groups[index].spaces.removeAll { $0 == space } }
            if let index = values.groups.firstIndex(where: { $0.name == name }) { values.groups[index].spaces.append(space) }
            else { values.groups.append(Group(name: name, spaces: [space])) }
            values.folded.removeAll { $0 == name }
        }
    }

    /// Makes an empty group under the first free name, "New Group", then "New Group 2"…, and returns that name.
    @discardableResult func newGroup() -> String {
        let taken = Set(values.groups.map(\.name))
        let name = (["New Group"] + (2...999).map { "New Group \($0)" }).first { !taken.contains($0) } ?? "New Group \(taken.count + 1)"
        change { $0.groups.append(Group(name: name, spaces: [])) }
        return name
    }

    /// Renames the group `old` to `new`, trimmed, its spaces and folding kept. Returns false, changing nothing, for an
    /// empty name, a name another group has, or a group that does not exist.
    @discardableResult func renameGroup(_ old: String, to new: String) -> Bool {
        let new = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty, let index = values.groups.firstIndex(where: { $0.name == old }) else { return false }
        guard new == old || !values.groups.contains(where: { $0.name == new }) else { return false }
        change { values in
            values.groups[index].name = new
            values.folded = values.folded.map { $0 == old ? new : $0 }
        }
        return true
    }

    /// Folds or unfolds the group `name`: a folded group keeps its header and its count.
    func fold(_ name: String, _ folded: Bool) {
        change { values in
            values.folded.removeAll { $0 == name }
            if folded { values.folded.append(name) }
        }
    }

    /// Forgets the spaces not in `names`: they leave their groups, the recent ones and their display names. The
    /// groups stay, even empty.
    func keep(only names: Set<String>) {
        change { values in
            for index in values.groups.indices { values.groups[index].spaces.removeAll { !names.contains($0) } }
            values.recents.removeAll { !names.contains($0) }
            values.names = values.names.filter { names.contains($0.key) }
            values.memoryExport = values.memoryExport.filter { names.contains($0.key) }
        }
    }

    /// Whether Include Its Memory starts ticked for `name`.
    func includesMemory(_ name: String) -> Bool { values.memoryExport[name] ?? values.exportMemory }

    /// Keeps the person's answer at Include Its Memory, for `name` alone.
    func includeMemory(_ included: Bool, of name: String) { change { $0.memoryExport[name] = included } }

    /// Forgets `name`, moved to the Trash: a new space of that name inherits neither its group nor its name.
    func forget(_ name: String) {
        let all = Set(values.groups.flatMap(\.spaces) + values.recents + values.names.keys + values.memoryExport.keys)
        keep(only: all.subtracting([name]))
    }

    /// Forgets the spaces whose file and folder are both gone from `spaces` (deleted, or renamed in Finder), as the
    /// grants do at the start. A folder that cannot be listed forgets nothing.
    func forgetGone(in spaces: URL) {
        guard let there = try? FileManager.default.contentsOfDirectory(atPath: spaces.path) else { return }
        keep(only: Set(there.map { $0.hasSuffix(".html") ? String($0.dropLast(5)) : $0 }))
    }
}
