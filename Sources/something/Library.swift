// The spaces of ~/something/spaces, sorted by title, and the sidebar's order of them (its groups, then the rest), the one
// order of the sidebar, ⌘1…⌘9, the Go menu and ⌘P; where the window is (a space, New Space or the templates);
// the last space open, kept in the preferences; the folder looked at twice a second, so that a space made, changed, renamed or removed in Finder or
// by an agent shows at once; and what acts on a space: import, export, Show in Finder, Move to Trash (its versions
// with it), and Use Template.
// A space deleted or renamed in Finder loses its grants at the next start: a name never inherits rights. A space made,
// imported or copied under a name forgets what the grants file kept for it first.
import AppKit
import Observation
import SomethingAgents
import SomethingCore

@Observable final class Library {
    /// One row of the sidebar: a space, its title (the name Rename… gave it, else its declared one), and whether it
    /// declares itself ("not a space yet" otherwise).
    struct Entry: Identifiable, Equatable {
        let space: Space, title: String, isSpace: Bool
        /// The title its declaration gives, or its file's name.
        var declared: String
        var id: String { space.name }
    }

    @ObservationIgnored let places: Places
    @ObservationIgnored let ask: Asking
    @ObservationIgnored let preferences: Preferences
    /// share/ and its templates, for the gallery, the blank page and the welcome.
    @ObservationIgnored let share: URL
    /// Where the window is: a space, the blank page of New Space, or the templates. No history is kept: the mockup has
    /// no back or forward.
    enum Destination: Hashable {
        case space(String), newSpace, templates
        /// The space's name, for a space; nil elsewhere.
        var space: String? { if case .space(let name) = self { name } else { nil } }
    }

    @ObservationIgnored let templates: [Template]
    private(set) var entries: [Entry] = []
    /// Where the window is, New Space at first.
    private(set) var selection = Destination.newSpace
    /// The space that just arrived (Arrival): its row is ringed a moment in the sidebar.
    var fresh: String?
    /// Whether a template's preview fills the Templates page: the sidebar's Templates is not highlighted then.
    var previewing = false
    /// The template ⌘P asked to see: the Templates page opens on its preview.
    var asked: String?
    /// What the sidebar holds besides the spaces: the row under the pointer, where the keyboard rests, a name being
    /// typed (Sidebar.swift).
    @ObservationIgnored let sidebar = SidebarState()
    /// Told the name of each space made from a template: its assistant offers to make it yours.
    @ObservationIgnored var used: (String) -> Void = { _ in }
    /// What selecting does: the app shows the destination, closing the open space.
    @ObservationIgnored var opened: (Destination) -> Void = { _ in }
    /// What Move to Trash… does before it moves anything: the window asks the person.
    @ObservationIgnored var trashing: (Entry) -> Void = { _ in }
    /// Told the name of a space renamed: the window titles it again when it is the open one.
    @ObservationIgnored var renamed: (String) -> Void = { _ in }
    /// Says a sentence for a moment: the window's toast, quiet.
    @ObservationIgnored var told: (String) -> Void = { _ in }
    /// Whether a space is being built: it comes first in its group, drawn and walked by the keys alike.
    @ObservationIgnored var building: (String) -> Bool = { _ in false }
    /// Told where an export was written and whether it holds the memory: the window's toast, with Show.
    @ObservationIgnored var exported: (URL, Bool) -> Void = { _, _ in }
    /// Told the title of a space imported: the window's toast.
    @ObservationIgnored var imported: (String) -> Void = { _ in }
    /// The agents of this Mac a page could reach, for the sentence at Import: no assistant among them.
    @ObservationIgnored var seen: () -> [Agent] = { [] }
    /// The check of an import, whose output folder holds its stage too, so that the page's copy goes where a check's
    /// files go; a test gives its own.
    @ObservationIgnored var checker: @MainActor (Places, URL) -> CheckRunner = { CheckRunner(places: $0, share: $1) }
    /// The last import under way: they come one at a time, each with its sheets.
    @ObservationIgnored var arriving: Task<Void, Never>?
    /// Show in Finder; a test puts its own, so that Finder never opens.
    @ObservationIgnored var reveal: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    /// Moves a file to the Trash and returns where it went; a test moves it into its own home, so that nothing reaches
    /// the person's Trash.
    @ObservationIgnored var discard: (URL) throws -> URL = { url in
        var went: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &went)
        return went as URL? ?? url
    }
    /// `discard`, for those who never bring a file back.
    var recycle: (URL) throws -> Void { { [discard] in _ = try discard($0) } }
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var watched = false
    @ObservationIgnored private var looked: [String: Date] = [:]
    @ObservationIgnored private var looking = false
    /// True from Use Template until the space it made opened: a double click makes one space, not two.
    @ObservationIgnored private var using = false

    init(places: Places, ask: Asking, share: URL) {
        self.places = places
        self.ask = ask
        preferences = Preferences.at(places)
        (self.share, templates) = (share, Template.all(share))
    }

    /// Makes ~/something/spaces and ~/something/data under the places' home when they are missing. Throws a
    /// `SpaceError` when a folder cannot be made: without them no space can be kept.
    static func prepare(_ places: Places) throws {
        for folder in [places.spaces, places.data] {
            do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch {
                throw SpaceError("something cannot make \(folder.path): \(error.localizedDescription) Check that your home folder can be written.")
            }
        }
    }

    /// Reads the spaces folder again. The open space, once gone, is closed.
    func relist() {
        let listed = Spaces(root: places.spaces).list().map { space in
            let reading = Declaration.read(space, home: places.home, kinds: Registry.app.kinds)
            // A page with no declaration block, or one that does not read, is not a space yet: a scratch file, a draft.
            let declared = reading.declaration != nil && !reading.problems.contains { $0.code == "DECLARATION_MISSING" }
            let own = reading.declaration?.title ?? space.name
            return Entry(space: space, title: preferences.names[space.name] ?? own, isSpace: declared, declared: own)
        }.sorted { one, other in
            let order = one.title.compare(other.title, options: [.caseInsensitive, .diacriticInsensitive])
            return order == .orderedSame ? one.id < other.id : order == .orderedAscending
        }
        if listed != entries { entries = listed }
        if let name = selection.space, entry(name) == nil { select(.newSpace) }
    }

    /// The spaces in the sidebar's order: each group in its order, its spaces by title, then the spaces in no group,
    /// by title. A space two groups name shows in the first.
    func order() -> [Entry] { sections().flatMap(\.entries) }

    /// The sidebar's sections: each group, even empty, with its spaces by title (those being built first), then the
    /// spaces in no group under no name (nil), when there are any.
    func sections() -> [(group: String?, entries: [Entry])] {
        var placed = Set<String>()
        let ordered = entries.filter { building($0.id) } + entries.filter { !building($0.id) }
        let grouped = preferences.groups.map { group in
            (Optional(group.name), ordered.filter { group.spaces.contains($0.id) && placed.insert($0.id).inserted })
        }
        let rest = ordered.filter { !placed.contains($0.id) }
        return grouped + (rest.isEmpty ? [] : [(nil, rest)])
    }

    /// Lists the spaces, and lists them again each time the folder changes, from now on. The folder is looked at
    /// twice a second, off the main queue: a file rewritten in place, a folder space's page and a spaces folder
    /// removed then made again are seen, which a watch of the folder's own entries would miss.
    func watch() {
        // Taken before the list is read: a change made while it is read is seen at the next look.
        looked = Library.stamp(places.spaces)
        relist()
        watched = true
        watching(true)
    }

    /// Looks at the folder twice a second while `on`, and at once when it turns on again: off while nobody can see
    /// the window. Only once `watch` started.
    func watching(_ on: Bool) {
        guard watched, on != (timer != nil) else { return }
        timer?.invalidate()
        timer = nil
        guard on else { return }
        look()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.look() }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func look() {
        guard !looking else { return }
        looking = true
        let root = places.spaces
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let now = Library.stamp(root)
            DispatchQueue.main.async {
                guard let self else { return }
                self.looking = false
                // Paused meanwhile: what it saw waits for the look that comes when the window shows.
                guard self.timer != nil else { return }
                if self.looked != now { self.relist() }
                self.looked = now
            }
        }
    }

    /// What the list depends on: each space's name and when its page last changed.
    static func stamp(_ root: URL) -> [String: Date] {
        let pages = Spaces(root: root).list().map { space in
            (space.name, (try? FileManager.default.attributesOfItem(atPath: space.page.path))?[.modificationDate] as? Date ?? .distantPast)
        }
        return Dictionary(pages) { first, _ in first }
    }

    func stop() {
        watching(false)
        watched = false
    }

    /// Goes to `destination`, once: selecting where the window already is does nothing. A space is remembered for the
    /// next start. It opens just after: the sidebar calls this while it changes its selection, and opening may wait for
    /// the level sheet.
    func select(_ destination: Destination) {
        guard destination != selection else { return }
        selection = destination
        if let name = destination.space { preferences.opened(name) }
        DispatchQueue.main.async { [weak self] in
            // A second click before this one opened: only the last one opens.
            if let self, self.selection == destination { self.opened(destination) }
        }
    }

    /// The space to open at the start, as Settings' "When something opens" says: nil for New Space; the space it
    /// names, when it is still listed; else the last one open, when it is. 1.0 kept a default space in app.json
    /// instead; it is read once, as the last one open.
    func atStart() -> String? {
        let chosen = preferences.openAtStart
        if chosen == "new" { return nil }
        if chosen != "last", entries.contains(where: { $0.id == chosen }) { return chosen }
        var name: String?
        if FileManager.default.fileExists(atPath: places.window.path) {
            name = preferences.lastOpen
        } else {
            let old = (try? Data(contentsOf: places.grants)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            name = old?["default"] as? String
            preferences.opened(name)
        }
        return entries.contains { $0.id == name } ? name : nil
    }

    /// Drops the grants and the assistant's conversation of every name whose file and folder are both gone from the
    /// spaces folder (deleted, or renamed in Finder), and sends its versions to the Trash through `recycle`, where the
    /// person can still find them. A spaces folder that cannot be listed drops nothing. Throws a `SpaceError` when the
    /// grants file does not read or cannot be written, or versions cannot be moved.
    static func forgetGone(_ places: Places, recycle: (URL) throws -> Void) throws {
        guard let there = try? Set(FileManager.default.contentsOfDirectory(atPath: places.spaces.path)) else { return }
        let gone = { (name: String) in !there.contains(name) && !there.contains("\(name).html") }
        for file in (try? FileManager.default.contentsOfDirectory(at: places.assistants, includingPropertiesForKeys: nil)) ?? []
        where file.pathExtension == "json" && gone(file.deletingPathExtension().lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
        let versioned = (try? FileManager.default.contentsOfDirectory(atPath: places.versions.path)) ?? []
        for name in versioned where gone(name) { try Versions(root: places.versions, keep: 0, limit: 0).trash(name, recycle: recycle) }
        try Grants(places.grants).update { file in file.spaces = file.spaces.filter { !gone($0.key) } }
    }

    /// Drops what the grants file kept for `name`, and its assistant's conversation, and sends the versions left under
    /// that name to the Trash through `recycle`: a new space of that name never inherits the answers, the conversation
    /// or the past a deleted one left. Throws a `SpaceError` when the grants file does not read or cannot be written,
    /// or the versions cannot be moved.
    static func forget(_ name: String, in places: Places, recycle: (URL) throws -> Void) throws {
        try? FileManager.default.removeItem(at: Session.file(name, in: places.assistants))
        try Versions(root: places.versions, keep: 0, limit: 0).trash(name, recycle: recycle)
        try Grants(places.grants).update { $0.spaces[name] = nil }
    }

    func entry(_ name: String?) -> Entry? { entries.first { $0.id == name } }

    func showInFinder(_ name: String) {
        if let entry = entry(name) { reveal(entry.space.location) }
    }

    /// How many entries the memory of `name` holds, 0 when it has none; nil when its file does not read.
    func remembers(_ name: String) -> Int? {
        (try? Memory(folder: places.data, space: name).get("")).map { ($0 as? [String: Any])?.count ?? 0 }
    }

    /// A space in the Trash, while Undo can bring it back: where its file and its memory were, and went.
    struct Trashed {
        let name: String, title: String
        let page: (home: URL, trash: URL), memory: (home: URL, trash: URL)?
    }

    /// Moves the space and its memory to the Trash and opens the next space in the sidebar's order, else the one
    /// before, else New Space. All the rest it left stays until `forget`. Says what failed, and nil: both moved, or neither.
    @discardableResult func trash(_ name: String) -> Trashed? {
        guard let entry = entry(name) else { return nil }
        let order = order().map(\.id), at = order.firstIndex(of: name)
        let next = at.flatMap { order.indices.contains($0 + 1) ? order[$0 + 1] : order.indices.contains($0 - 1) ? order[$0 - 1] : nil }
        let home = Memory(folder: places.data, space: name).file, location = entry.space.location
        do {
            let page = try discard(location)
            var memory: (home: URL, trash: URL)?
            do {
                if FileManager.default.fileExists(atPath: home.path) { memory = (home, try discard(home)) }
            } catch {
                try? FileManager.default.moveItem(at: page, to: location)
                throw error
            }
            if selection.space == name { select(next.map { .space($0) } ?? .newSpace) }
            relist()
            return Trashed(name: name, title: entry.title, page: (location, page), memory: memory)
        } catch {
            ask.tell("“\(entry.title)” was not moved to the Trash. \(error.sentence)")
            relist()
            return nil
        }
    }

    /// Undo: puts `trashed` back where it was and opens it, its row ringed. Returns whether it came back, and the toast's
    /// words, which say where it is when it did not.
    func restore(_ trashed: Trashed) -> (back: Bool, words: String) {
        let manager = FileManager.default, title = trashed.title
        guard manager.fileExists(atPath: trashed.page.trash.path) else { return (false, "\(title) is no longer in the Trash") }
        guard !manager.fileExists(atPath: trashed.page.home.path), Spaces(root: places.spaces).named(trashed.name) == nil else {
            return (false, "\(title) stays in the Trash: a new space took its name")
        }
        do { try manager.moveItem(at: trashed.page.trash, to: trashed.page.home) } catch {
            return (false, "\(title) stays in the Trash: \(error.localizedDescription)")
        }
        var words = "\(title) is back"
        if let memory = trashed.memory, (try? manager.moveItem(at: memory.trash, to: memory.home)) == nil {
            words += " · its memory stays in the Trash"
        }
        ring(trashed.name)
        return (true, words)
    }

    /// Lists again and opens `name`, which just came in, its row ringed for the ring's own time, as an arrival lets it go.
    func ring(_ name: String) {
        relist()
        fresh = name
        select(.space(name))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            if self?.fresh == name { self?.fresh = nil }
        }
    }

    /// The Undo of `trashed` is over: its answers, group and versions go, as its conversation does. Says what failed.
    func forget(_ trashed: Trashed) {
        preferences.forget(trashed.name)
        do { try Library.forget(trashed.name, in: places, recycle: recycle) } catch {
            ask.tell("What “\(trashed.title)” left was not cleared. \(error.sentence)")
        }
    }

    /// Saves the space `name` as one HTML file in Downloads (F6.1): under its name, or "name 2" and on when that is
    /// taken, never over a file. A space with a memory first asks whether it goes, ticked as this space's last answer
    /// was, else as Settings › Spaces says; one without exports in one click. Grants and journal never go. The window
    /// says where it is (`exported`), or what failed.
    func export(_ name: String) {
        guard let entry = entry(name) else { return }
        // Said by the title the person sees everywhere, not the file's name.
        let (space, title) = (entry.space, "“\(entry.title)”")
        var carries = false
        if let entries = remembers(name), entries > 0 {
            guard let answer = ask.export(entry, entries: entries, included: preferences.includesMemory(name)) else { return }
            preferences.includeMemory(answer, of: name)
            carries = answer
        }
        do {
            let memory = carries ? try Library.carried(space.name, in: places.data) : nil
            let script = { (file: String) in
                do { return try String(contentsOf: self.share.appendingPathComponent(file), encoding: .utf8) } catch {
                    throw SpaceError("\(file) cannot be read in \(self.share.path): \(error.localizedDescription)")
                }
            }
            let page = try Export.page(space, data: memory, app: Resources.version, bridge: script("something.js"), offline: script("offline.js"))
            let folder = places.downloads
            let url = ([""] + (2...999).map { " \($0)" }).lazy.map { folder.appendingPathComponent("\(space.name)\($0).html") }
                .first { !FileManager.default.fileExists(atPath: $0.path) } ?? folder.appendingPathComponent("\(space.name) \(UUID().uuidString).html")
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try page.write(to: url, options: .withoutOverwriting)
            } catch {
                throw SpaceError("The export could not be written to \(Words.path(url.path, home: places.home.path)): \(error.localizedDescription)")
            }
            exported(url, carries)
            let links = Library.links(space)
            if !links.isEmpty {
                ask.tell("\(title) was exported without \(links.joined(separator: ", ")): a link to somewhere else is never exported. Replace a link with the file itself to export it.")
            }
        } catch {
            ask.tell("\(title) was not exported. \(error.sentence)")
        }
    }

    /// The paths of the links in a folder space, sorted: what its export leaves out. A file space has none here (a
    /// linked one is refused whole). Hidden paths are not part of the space and are not listed.
    static func links(_ space: Space) -> [String] {
        guard space.form == .folder else { return [] }
        let paths = FileManager.default.enumerator(atPath: space.location.path)?.allObjects as? [String] ?? []
        return paths.filter { !$0.split(separator: "/").contains { $0.hasPrefix(".") } && Versions.isLink(space.location.appendingPathComponent($0)) }.sorted()
    }

    /// The memory of the space `name`, as an export may carry it; nil when it is empty. Throws a `SpaceError` when the
    /// memory file is a link (it could lead to an agent's file) or not a JSON object.
    private static func carried(_ name: String, in folder: URL) throws -> [String: Any]? {
        let memory = Memory(folder: folder, space: name)
        guard !Versions.isLink(memory.file) else {
            throw SpaceError("\(memory.file.path) is a link to somewhere else; something exports only a space's own memory.")
        }
        let whole = try memory.get("") as? [String: Any] ?? [:]
        return whole.isEmpty ? nil : whole
    }

    /// Shows `template`'s own file in the Finder.
    func revealTemplate(_ template: Template) {
        reveal(share.appendingPathComponent("templates/\(template.id).html"))
    }

    /// Makes `template` a new space, under its name or the first free one after it (agents-2, agents-3…), and opens
    /// it. A template that follows a folder asks for it first, and the copy follows the one chosen; Cancel makes
    /// nothing. Says what failed. A second call before the first space opened does nothing.
    func use(_ template: Template) {
        guard !using else { return }
        var folder: String?
        if template.follows {
            guard let chosen = ask.folder("Choose the project folder this space follows") else { return }
            folder = Words.path(chosen.path, home: places.home.path)
        }
        let spaces = Spaces(root: places.spaces)
        let free = ([template.id] + (2...99).map { "\(template.id)-\($0)" }).first { spaces.named($0) == nil } ?? template.id
        do {
            let page = share.appendingPathComponent("templates/\(template.id).html")
            let space = try Command.new(free, folder: false, places: places, template: page, following: folder, recycle: recycle)
            relist()
            used(space.name)
            select(.space(space.name))
            // Queued after the opening select asked for, which runs first and may wait for the level sheet.
            using = true
            DispatchQueue.main.async { [weak self] in self?.using = false }
        } catch {
            ask.tell("“\(template.title)” was not made. \(error.sentence)")
        }
    }
}
