// Home: the spaces of the spaces folder in a table, one of them always selected while there is one, the
// card of the selected one beside it, and below, the examples, read-only, each with "Make a copy" (the section shows
// nothing while there is none). An empty list says how to make a first space. Open, Export, Make default and Show in
// Finder act on the selected space; New (as `something new`) and Import make a new one.
// A space deleted or renamed in Finder loses its grants here, at the next look: a name never inherits rights.
// A name whose file or folder is still there keeps them, even while it is not a space (a checkout rewriting it), and
// a space made, imported or copied under a name forgets what the grants file kept for it first.
import AppKit
import SomethingCore

final class Home: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    let places: Places, examples: URL, template: URL, ask: Asking
    let card: Card
    /// What Open does: the app opens the space in the space window.
    var open: (Space) -> Void = { _ in }
    /// What Show in Finder does; a test puts its own, so that Finder never opens.
    var reveal: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    private(set) var spaces: [Space] = [], samples: [Space] = []
    /// The space the app opens at its start, from the grants file.
    private(set) var preferred: String?
    let table = NSTableView(), sampleTable = NSTableView()
    private var exampleSection: [NSView] = []
    /// The list of spaces, and the sentence shown in its place while there is none.
    private(set) var list = NSScrollView(), empty = NSTextField()
    private var sampleHeight: NSLayoutConstraint?
    private var actions: [NSButton] = []
    private var window: NSWindow?
    /// The last failure to read the grants file that was said: reload runs each time the window becomes key, and a
    /// failure said again at each time would bring its own window back without end.
    private var told: String?

    /// `share` holds template.html and examples/, which may not exist.
    init(places: Places, share: URL, ask: Asking) {
        self.places = places
        self.ask = ask
        examples = share.appendingPathComponent("examples")
        template = share.appendingPathComponent("template.html")
        card = Card(places: places, ask: ask)
        super.init()
        for list in [table, sampleTable] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("space"))
            column.width = Card.width - 40
            list.addTableColumn(column)
            list.headerView = nil
            list.rowHeight = Home.rowHeight
            list.dataSource = self
            list.delegate = self
        }
        // A click below the rows keeps the selection: the card beside the list always says which space it shows.
        table.allowsEmptySelection = false
        table.target = self
        table.doubleAction = #selector(openSelected)
    }

    var selected: Space? { spaces.indices.contains(table.selectedRow) ? spaces[table.selectedRow] : nil }
    var selectedSample: Space? { samples.indices.contains(sampleTable.selectedRow) ? samples[sampleTable.selectedRow] : nil }

    static let rowHeight: CGFloat = 24

    /// Reads the spaces, the examples and the default space again, then selects the space `name`, or keeps the
    /// selection by name, or selects the default space, or the first: the card always shows a space when there is one.
    func reload(selecting name: String? = nil) {
        let wanted = [name, selected?.name], keptSample = selectedSample?.name
        spaces = Spaces(root: places.spaces).list()
        samples = Spaces(root: examples).list()
        preferred = forgetGone()
        // A name whose space is gone (deleted or renamed in Finder) gives way to the next one, not to whatever space
        // now sits at its row.
        let present = (wanted + [preferred, spaces.first?.name]).compactMap { $0 }.first { name in spaces.contains { $0.name == name } }
        Home.reselect(table, spaces, present)
        Home.reselect(sampleTable, samples, keptSample)
        exampleSection.forEach { $0.isHidden = samples.isEmpty }
        // As tall as its examples, four at most; the list of spaces above takes the rest of the column.
        sampleHeight?.constant = CGFloat(min(max(samples.count, 1), 4)) * (Home.rowHeight + 2) + 4
        list.isHidden = spaces.isEmpty
        empty.isHidden = !spaces.isEmpty
        update()
    }

    /// Drops the grants of the spaces that are gone and returns the default space's name, or nil. A grants file
    /// that does not read or cannot be written is said once, until it reads again: reload runs at each look.
    @discardableResult
    func forgetGone() -> String? {
        do {
            let file = try Home.forgetGone(places)
            told = nil
            return file.default
        } catch {
            let message = error.sentence
            if message != told { ask.tell(message) }
            told = message
            return nil
        }
    }

    /// Drops the grants of every name whose file and folder are both gone from the spaces folder (deleted, or renamed
    /// in Finder), and returns the grants file. A spaces folder that cannot be listed drops nothing.
    /// Throws a `SpaceError` when the grants file does not read or cannot be written.
    static func forgetGone(_ places: Places) throws -> AppFile {
        var file = try AppFile.read(places.grants)
        guard let there = try? Set(FileManager.default.contentsOfDirectory(atPath: places.spaces.path)) else { return file }
        let gone = file.spaces.keys.filter { !there.contains($0) && !there.contains("\($0).html") }
        guard !gone.isEmpty else { return file }
        gone.forEach { file.spaces[$0] = nil }
        try file.write(places.grants)
        return file
    }

    /// Drops what the grants file kept for `name`: a new space of that name never inherits the answers a deleted
    /// one left. Throws a `SpaceError` when the grants file does not read or cannot be written.
    static func forget(_ name: String, in places: Places) throws {
        var file = try AppFile.read(places.grants)
        if file.spaces.removeValue(forKey: name) != nil { try file.write(places.grants) }
    }

    private static func reselect(_ list: NSTableView, _ spaces: [Space], _ name: String?) {
        list.reloadData()
        if let row = spaces.firstIndex(where: { $0.name == name }) { list.selectRowIndexes([row], byExtendingSelection: false) }
    }

    func show() {
        if window == nil { window = makeWindow() }
        reload()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openSelected() {
        if let space = selected { open(space) }
    }

    /// Makes the selected space the one the app opens at its start.
    @objc func makeDefault() {
        guard let space = selected else { return }
        do {
            var file = try AppFile.read(places.grants)
            file.default = space.name
            try file.write(places.grants)
        } catch {
            ask.tell(error.sentence)
        }
        reload()
    }

    /// Saves the selected space as a .something file. Its memory goes with it only when the person says so, after
    /// seeing its keys and size; grants and journal never do.
    @objc func exportSelected() {
        guard let space = selected else { return }
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

    /// Asks a name and makes the space as `something new <name>` does, selected; nothing when the person cancels.
    @objc func newChosen() {
        guard let name = ask.newName() else { return }
        do {
            let space = try Command.new(name, folder: false, places: places, template: template)
            reload(selecting: space.name)
        } catch {
            ask.tell("The space \(name) was not made. \(error.sentence)")
        }
    }

    @objc func importChosen() {
        if let url = ask.importFile() { importSpace(from: url) }
    }

    /// Reads the .something file at `url` and makes it a new space, selected. It has no grant: what the grants file
    /// kept for the name it gets is dropped before anything is written, so a grants file that cannot be changed
    /// leaves no space, and the space asks for its rights at its first opening.
    func importSpace(from url: URL) {
        do {
            // Mapped, not loaded: a huge file is refused by Export.read for its size without being read.
            let received = try Export.read(try Data(contentsOf: url, options: .alwaysMapped))
            let folder = Spaces(root: places.spaces)
            let name = try Export.freeName(received, in: folder, memory: places.data)
            try Home.forget(name, in: places)
            try FileManager.default.createDirectory(at: places.spaces, withIntermediateDirectories: true)
            let space = try Export.place(received, as: name, in: folder, memory: places.data)
            reload(selecting: space.name)
        } catch {
            ask.tell("\(url.lastPathComponent) was not imported. \(error.sentence)")
        }
    }

    @objc func showInFinder() {
        if let space = selected { reveal(space.location) }
    }

    /// Copies the selected example into the spaces folder, under its own name, and selects the copy.
    @objc func makeACopy() {
        guard let sample = selectedSample else { return }
        do { try Home.copy(sample, into: places) } catch { return ask.tell(error.sentence) }
        reload(selecting: sample.name)
    }

    /// Copies the example `sample` into the spaces folder under its own name. A copy has no grant: answers left in
    /// the grants file by a space of the same name, deleted in Finder, are forgotten first, as a received space never
    /// inherits rights by name; it asks its rights at its first opening. Throws a `SpaceError` that says
    /// why when that name is taken, the grants file cannot be changed, or the copy cannot be written.
    static func copy(_ sample: Space, into places: Places) throws {
        let target = places.spaces.appendingPathComponent(sample.location.lastPathComponent)
        guard Spaces(root: places.spaces).named(sample.name) == nil, !FileManager.default.fileExists(atPath: target.path) else {
            throw SpaceError("A space named \(sample.name) already exists in \(places.spaces.path); rename it to make a new copy.")
        }
        do { try Home.forget(sample.name, in: places) } catch {
            throw SpaceError("The example \(sample.name) was not copied. \(error.sentence)")
        }
        do {
            try FileManager.default.createDirectory(at: places.spaces, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sample.location, to: target)
        } catch {
            throw SpaceError("The example \(sample.name) could not be copied to \(target.path): \(error.localizedDescription)")
        }
    }

    // MARK: The table

    func numberOfRows(in list: NSTableView) -> Int { list === table ? spaces.count : samples.count }

    func tableView(_ list: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let space = list === table ? spaces[row] : samples[row]
        let title = Declaration.read(space, home: places.home).declaration?.title ?? space.name
        let mark = list === table && space.name == preferred ? "  (opens at start)" : ""
        return NSTextField(labelWithString: (title == space.name ? title : "\(title) — \(space.name)") + mark)
    }

    func tableViewSelectionDidChange(_ notification: Notification) { update() }

    func windowDidBecomeKey(_ notification: Notification) { reload() }

    /// Shows the selected space's card and enables what acts on a selection.
    private func update() {
        card.show(selected)
        actions.forEach { $0.isEnabled = selected != nil }
    }

    func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "something"
        window.isReleasedWhenClosed = false
        window.delegate = self
        func button(_ title: String, _ action: Selector) -> NSButton { NSButton(title: title, target: self, action: action) }
        actions = [button("Open", #selector(openSelected)), button("Export", #selector(exportSelected)),
                   button("Make default", #selector(makeDefault)), button("Show in Finder", #selector(showInFinder))]
        let bar = NSStackView(views: [actions[0], button("New", #selector(newChosen)), button("Import", #selector(importChosen))] + actions[1...])
        let samplesList = Card.scroll(sampleTable)
        sampleHeight = samplesList.heightAnchor.constraint(equalToConstant: 0)
        sampleHeight?.isActive = true
        exampleSection = [Card.header("Examples, read-only"), samplesList, button("Make a copy", #selector(makeACopy))]
        list = Card.scroll(table)
        // The list takes the height the column has left: it grows with the window, never shorter than five rows.
        let fill = list.heightAnchor.constraint(equalToConstant: 0)
        fill.priority = .defaultLow
        fill.isActive = true
        list.heightAnchor.constraint(greaterThanOrEqualToConstant: 5 * (Home.rowHeight + 2)).isActive = true
        empty = Card.line("No space yet. Click New to make your first one, or type something new <name> in Terminal.")
        // Of the column's lines, the list, or this sentence in its place, takes the height left: the others keep theirs.
        empty.setContentHuggingPriority(.defaultLow - 1, for: .vertical)
        let place = Words.pathLabel("Your spaces, in ", places.spaces.path, home: places.home.path, width: Card.width)
        let left = NSStackView(views: [bar, place, list, empty] + exampleSection)
        left.orientation = .vertical
        left.alignment = .leading
        left.distribution = .fill
        for line in left.arrangedSubviews where line !== list && line !== empty {
            line.setContentHuggingPriority(.required, for: .vertical)
            (line as? NSStackView)?.setHuggingPriority(.required, for: .vertical)
        }
        left.setCustomSpacing(16, after: list)
        left.setCustomSpacing(16, after: empty)
        left.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        let content = NSStackView(views: [left, card.view])
        content.alignment = .top
        content.spacing = 8
        left.heightAnchor.constraint(equalTo: content.heightAnchor).isActive = true
        window.contentView = content
        // Smaller than the list and the card side by side, the card is cut: Home opens at that size, its smallest.
        window.contentMinSize = NSSize(width: content.fittingSize.width, height: max(content.fittingSize.height, 280))
        window.setContentSize(window.contentMinSize)
        window.center()
        return window
    }
}
