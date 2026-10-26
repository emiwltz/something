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
    /// Show in Finder; a test puts its own, so that Finder never opens.
    @ObservationIgnored var reveal: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    /// Moves a file to the Trash; a test moves it into its own home, so that nothing reaches the person's Trash.
    @ObservationIgnored var recycle: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
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

    /// The sidebar's sections: each group, even empty, with its spaces by title, then the spaces in no group under no
    /// name (nil), when there are any.
    func sections() -> [(group: String?, entries: [Entry])] {
        var placed = Set<String>()
        let grouped = preferences.groups.map { group in
            (Optional(group.name), entries.filter { group.spaces.contains($0.id) && placed.insert($0.id).inserted })
        }
        let rest = entries.filter { !placed.contains($0.id) }
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
    /// the rights sheet.
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

    /// Moves the space, its memory and its versions to the Trash, where the person can put them back, and forgets its
    /// answers. Says what failed.
    func trash(_ name: String) {
        guard let entry = entry(name) else { return }
        let memory = Memory(folder: places.data, space: name).file
        do {
            try recycle(entry.space.location)
            if FileManager.default.fileExists(atPath: memory.path) { try recycle(memory) }
            preferences.forget(name)
            try Library.forget(name, in: places, recycle: recycle)
        } catch {
            ask.tell("“\(entry.title)” was not moved to the Trash. \(error.sentence)")
        }
        relist()
    }

    /// Saves the space `name` as a .something file. Its memory goes with it only when the person says so, after
    /// seeing its keys and size; grants and journal never do.
    func export(_ name: String) {
        guard let space = entry(name)?.space else { return }
        do {
            var data: [String: Any]?
            if let memory = try Export.memory(space.name, in: places.data) {
                let bytes = try JSONSerialization.data(withJSONObject: memory, options: .sortedKeys).count
                guard let with = ask.withData(space.name, keys: memory.keys.sorted(), bytes: bytes) else { return }
                data = with ? memory : nil
            }
            let document = try Export.document(space, data: data, app: Resources.version)
            guard let url = ask.saveAs("\(space.name).something") else { return }
            do { try document.write(to: url, options: .atomic) } catch {
                throw SpaceError("The export could not be written to \(url.path): \(error.localizedDescription)")
            }
            let links = Export.links(space)
            if !links.isEmpty {
                ask.tell("\(space.name) was exported without \(links.joined(separator: ", ")): a link to somewhere else is never exported. Replace a link with the file itself to export it.")
            }
        } catch {
            ask.tell("\(space.name) was not exported. \(error.sentence)")
        }
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
            // Queued after the opening select asked for, which runs first and may wait for the rights sheet.
            using = true
            DispatchQueue.main.async { [weak self] in self?.using = false }
        } catch {
            ask.tell("“\(template.title)” was not made. \(error.sentence)")
        }
    }

    /// Asks for a .something file and imports it.
    func importChosen() {
        if let url = ask.importFile() { importSpace(from: url) }
    }

    /// Reads the .something file at `url` and makes it a new space, then opens it. It has no grant: what the grants
    /// file kept for the name it gets is dropped before anything is written, so a grants file that cannot be changed
    /// leaves no space, and the space asks for its rights at its first opening.
    func importSpace(from url: URL) {
        do {
            // Mapped, not loaded: a huge file is refused by Export.read for its size without being read.
            let received = try Export.read(try Data(contentsOf: url, options: .alwaysMapped))
            let folder = Spaces(root: places.spaces)
            let name = try Export.freeName(received, in: folder, memory: places.data)
            try Library.forget(name, in: places, recycle: recycle)
            try FileManager.default.createDirectory(at: places.spaces, withIntermediateDirectories: true)
            let space = try Export.place(received, as: name, in: folder, memory: places.data)
            relist()
            select(.space(space.name))
        } catch {
            ask.tell("\(url.lastPathComponent) was not imported. \(error.sentence)")
        }
    }
}
