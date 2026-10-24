// What the app remembers for the person apart from the grants, in window.json: the window's memory (the last space
// open, the recent ones, the groups of the sidebar and their folding, the names shown in place of a space's title),
// whether the tour was seen, and the settings, whose defaults are the approved mockup's. One copy per file, read once
// and shared by every model of the window, so that no write undoes another's; each change is written at once,
// atomically, over the keys this version knows: a key it does not know is kept as it was.
import Foundation
import Observation
import SomethingCore

@dynamicMemberLookup @Observable final class Preferences {
    enum Appearance: String, Codable { case system, light, dark }
    typealias Motion = Look.Motion
    /// How a space's assistant shows when the space opens: the sticker in a corner, or the open composer.
    enum Opening: String, Codable { case reduced, open }
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
        var askEverything = false, resume = true, toured = false, launcherOffered = false, addToApplications = true
        var groups: [Group] = [], folded: [String] = [], names: [String: String] = [:], recents: [String] = []
        /// "last", "new", or the name of a space.
        var openAtStart = "last"
        var appearance = Appearance.system, motion = Motion.calm, assistantAtOpening = Opening.reduced
        var sidebarEyes = true, rememberSticker = true, holdOption = true, notify = false
        /// nil while it rests at its first place, the bottom trailing corner; kept only while `rememberSticker`.
        var sticker: StickerPlace?
        /// Minutes; 0 for never.
        var sleepAfter = 10
        var awakeAtMost = 3
        /// Versions kept per space, 0 for all of them; the storage limit in MB.
        var versionsKept = 50, storageLimit = 500

        enum CodingKeys: String, CodingKey, CaseIterable {
            case lastOpen, assistant, model, effort, listed, askEverything, resume, toured, launcherOffered, addToApplications, groups,
                 folded, names, recents, openAtStart, appearance, motion, assistantAtOpening, sidebarEyes, rememberSticker,
                 holdOption, notify, sticker, sleepAfter, awakeAtMost, versionsKept, storageLimit
        }

        init() {}

        /// Each key on its own: one value of the wrong type falls back to its default, never the whole file.
        init(from decoder: Decoder) throws {
            let keys = try decoder.container(keyedBy: CodingKeys.self)
            func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? keys.decodeIfPresent(T.self, forKey: key)) ?? fallback }
            let base = Values()
            (lastOpen, assistant, model, effort) = (read(.lastOpen, nil), read(.assistant, nil), read(.model, nil), read(.effort, nil))
            listed = read(.listed, base.listed)
            (askEverything, resume, toured) = (read(.askEverything, base.askEverything), read(.resume, base.resume), read(.toured, base.toured))
            (launcherOffered, addToApplications) = (read(.launcherOffered, base.launcherOffered), read(.addToApplications, base.addToApplications))
            (groups, folded, names, recents) = (read(.groups, base.groups), read(.folded, base.folded), read(.names, base.names), read(.recents, base.recents))
            (openAtStart, appearance, motion) = (read(.openAtStart, base.openAtStart), read(.appearance, base.appearance), read(.motion, base.motion))
            (assistantAtOpening, sidebarEyes) = (read(.assistantAtOpening, base.assistantAtOpening), read(.sidebarEyes, base.sidebarEyes))
            (rememberSticker, holdOption, notify) = (read(.rememberSticker, base.rememberSticker), read(.holdOption, base.holdOption), read(.notify, base.notify))
            (sticker, sleepAfter, awakeAtMost) = (read(.sticker, nil), read(.sleepAfter, base.sleepAfter), read(.awakeAtMost, base.awakeAtMost))
            (versionsKept, storageLimit) = (read(.versionsKept, base.versionsKept), read(.storageLimit, base.storageLimit))
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
        values = (try? JSONSerialization.data(withJSONObject: kept)).flatMap { try? JSONDecoder().decode(Values.self, from: $0) } ?? Values()
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

    /// Forgets the spaces not in `names`: they leave their groups, the recent ones and their display names. The
    /// groups stay, even empty.
    func keep(only names: Set<String>) {
        change { values in
            for index in values.groups.indices { values.groups[index].spaces.removeAll { !names.contains($0) } }
            values.recents.removeAll { !names.contains($0) }
            values.names = values.names.filter { names.contains($0.key) }
        }
    }

    /// Forgets `name`, moved to the Trash: a new space of that name inherits neither its group nor its name.
    func forget(_ name: String) {
        let all = Set(values.groups.flatMap(\.spaces) + values.recents + values.names.keys)
        keep(only: all.subtracting([name]))
    }

    /// Forgets the spaces whose file and folder are both gone from `spaces` (deleted, or renamed in Finder), as the
    /// grants do at the start. A folder that cannot be listed forgets nothing.
    func forgetGone(in spaces: URL) {
        guard let there = try? FileManager.default.contentsOfDirectory(atPath: spaces.path) else { return }
        keep(only: Set(there.map { $0.hasSuffix(".html") ? String($0.dropLast(5)) : $0 }))
    }
}
