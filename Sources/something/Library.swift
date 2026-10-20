// The spaces of ~/something/spaces as the sidebar lists them, sorted by title; the open one; the last one open, kept
// in window.json; the folder looked at twice a second, so that a space made, changed, renamed or removed in Finder or
// by an agent shows at once; and what acts on a space: import, export, Show in Finder, Move to Trash.
// A space deleted or renamed in Finder loses its grants at the next start: a name never inherits rights. A space made,
// imported or copied under a name forgets what the grants file kept for it first.
import AppKit
import Observation
import SomethingCore

@Observable final class Library {
    /// One row of the sidebar: a space, its title, and whether it declares itself ("not a space yet" otherwise).
    struct Entry: Identifiable, Equatable {
        let space: Space, title: String, isSpace: Bool
        var id: String { space.name }
    }

    @ObservationIgnored let places: Places
    @ObservationIgnored let ask: Asking
    private(set) var entries: [Entry] = []
    /// The name of the open space; nil when none is.
    private(set) var selection: String?
    /// What selecting does: the app opens the space, or closes the open one for nil.
    @ObservationIgnored var opened: (String?) -> Void = { _ in }
    /// What Move to Trash… does before it moves anything: the window asks the person.
    @ObservationIgnored var trashing: (Entry) -> Void = { _ in }
    /// Show in Finder; a test puts its own, so that Finder never opens.
    @ObservationIgnored var reveal: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    /// Moves a file to the Trash; a test moves it into its own home, so that nothing reaches the person's Trash.
    @ObservationIgnored var recycle: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var looked: [String: Date] = [:]
    @ObservationIgnored private var looking = false

    init(places: Places, ask: Asking) {
        self.places = places
        self.ask = ask
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
            let reading = Declaration.read(space, home: places.home)
            // A page with no declaration block, or one that does not read, is not a space yet: a scratch file, a draft.
            let declared = reading.declaration != nil && !reading.problems.contains { $0.code == "DECLARATION_MISSING" }
            return Entry(space: space, title: reading.declaration?.title ?? space.name, isSpace: declared)
        }.sorted { one, other in
            let order = one.title.compare(other.title, options: [.caseInsensitive, .diacriticInsensitive])
            return order == .orderedSame ? one.id < other.id : order == .orderedAscending
        }
        if listed != entries { entries = listed }
        if let selection, !entries.contains(where: { $0.id == selection }) { select(nil) }
    }

    /// Lists the spaces, and lists them again each time the folder changes, from now on. The folder is looked at
    /// twice a second, off the main queue: a file rewritten in place, a folder space's page and a spaces folder
    /// removed then made again are seen, which a watch of the folder's own entries would miss.
    func watch() {
        // Taken before the list is read: a change made while it is read is seen at the next look.
        looked = Library.stamp(places.spaces)
        relist()
        timer?.invalidate()
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
        timer?.invalidate()
        timer = nil
    }

    /// Opens the space `name`, or closes the open one for nil, and remembers it for the next start. The space opens
    /// just after: the sidebar calls this while it changes its selection, and opening may wait for the rights sheet.
    func select(_ name: String?) {
        guard name != selection else { return }
        selection = name
        if let name { remember(name) }
        DispatchQueue.main.async { [weak self] in
            // A second click before this one opened: only the last one opens.
            if let self, self.selection == name { self.opened(name) }
        }
    }

    /// What window.json keeps: the UI's own memory, apart from the grants, so that app.json changes only when a grant
    /// does. The assistant keeps its builder and Ask Before Every Change there too, and the tour whether it was
    /// seen and whether it offered the launcher.
    struct WindowFile: Codable {
        var lastOpen: String?, assistant: String?, askEverything: Bool?, toured: Bool?, launcherOffered: Bool?

        /// What `places` keep; nil when window.json is missing or does not read.
        static func read(_ places: Places) -> WindowFile? {
            (try? Data(contentsOf: places.window)).flatMap { try? JSONDecoder().decode(WindowFile.self, from: $0) }
        }

        /// Changes what window.json keeps; a file that cannot be written loses only this memory of the UI.
        static func update(_ places: Places, _ change: (inout WindowFile) -> Void) {
            var file = read(places) ?? WindowFile()
            change(&file)
            try? FileManager.default.createDirectory(at: places.support, withIntermediateDirectories: true)
            try? JSONEncoder().encode(file).write(to: places.window, options: .atomic)
        }
    }

    /// The space to open at the start: the last one open, when it is still listed. 1.0 kept a default space in
    /// app.json instead; it is read once, as the last one open.
    func last() -> String? {
        var name: String?
        if FileManager.default.fileExists(atPath: places.window.path) {
            name = WindowFile.read(places)?.lastOpen
        } else {
            let old = (try? Data(contentsOf: places.grants)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            name = old?["default"] as? String
            remember(name)
        }
        return entries.contains { $0.id == name } ? name : nil
    }

    private func remember(_ name: String?) {
        WindowFile.update(places) { $0.lastOpen = name }
    }

    /// Drops the grants of every name whose file and folder are both gone from the spaces folder (deleted, or renamed
    /// in Finder). A spaces folder that cannot be listed drops nothing. Throws a `SpaceError` when the grants file
    /// does not read or cannot be written.
    static func forgetGone(_ places: Places) throws {
        try Grants(places.grants).update { file in
            guard let there = try? Set(FileManager.default.contentsOfDirectory(atPath: places.spaces.path)) else { return }
            file.spaces = file.spaces.filter { there.contains($0.key) || there.contains("\($0.key).html") }
        }
    }

    /// Drops what the grants file kept for `name`: a new space of that name never inherits the answers a deleted
    /// one left. Throws a `SpaceError` when the grants file does not read or cannot be written.
    static func forget(_ name: String, in places: Places) throws {
        try Grants(places.grants).update { $0.spaces[name] = nil }
    }

    func entry(_ name: String?) -> Entry? { entries.first { $0.id == name } }

    func showInFinder(_ name: String) {
        if let entry = entry(name) { reveal(entry.space.location) }
    }

    /// Moves the space and its memory to the Trash, where the person can put both back, and forgets its answers.
    /// Says what failed.
    func trash(_ name: String) {
        guard let entry = entry(name) else { return }
        let memory = Memory(folder: places.data, space: name).file
        do {
            try recycle(entry.space.location)
            if FileManager.default.fileExists(atPath: memory.path) { try recycle(memory) }
            try Library.forget(name, in: places)
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
            try Library.forget(name, in: places)
            try FileManager.default.createDirectory(at: places.spaces, withIntermediateDirectories: true)
            let space = try Export.place(received, as: name, in: folder, memory: places.data)
            relist()
            select(space.name)
        } catch {
            ask.tell("\(url.lastPathComponent) was not imported. \(error.sentence)")
        }
    }
}
