// Home (design 5): the spaces of the spaces folder in a table, the card of the selected one beside it, and below,
// the examples, read-only, each with "Make a copy" (the section shows nothing while there is none). Open, Export,
// Make default and Show in Finder act on the selected space; Import makes a new one; New is shown, disabled, until it
// exists. A space deleted or renamed in Finder loses its grants here, at the next look: a name never inherits rights.
// A name whose file or folder is still there keeps them, even while it is not a space (a checkout rewriting it).
import AppKit
import SomethingCore

final class Home: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    let places: Places, examples: URL, ask: Asking
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
    private var actions: [NSButton] = []
    private var window: NSWindow?
    /// The last failure to read the grants file that was said: reload runs each time the window becomes key, and a
    /// failure said again at each time would bring its own window back without end.
    private var told: String?

    /// `examples` is share/examples, which may not exist.
    init(places: Places, examples: URL, ask: Asking) {
        (self.places, self.examples, self.ask) = (places, examples, ask)
        card = Card(places: places, ask: ask)
        super.init()
        for list in [table, sampleTable] {
            list.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("space")))
            list.headerView = nil
            list.dataSource = self
            list.delegate = self
        }
        table.target = self
        table.doubleAction = #selector(openSelected)
    }

    var selected: Space? { spaces.indices.contains(table.selectedRow) ? spaces[table.selectedRow] : nil }
    var selectedSample: Space? { samples.indices.contains(sampleTable.selectedRow) ? samples[sampleTable.selectedRow] : nil }

    /// Reads the spaces, the examples and the default space again, keeping the selection by name.
    func reload() {
        let kept = (selected?.name, selectedSample?.name)
        spaces = Spaces(root: places.spaces).list()
        samples = Spaces(root: examples).list()
        preferred = forgetGone()
        Home.reselect(table, spaces, kept.0)
        Home.reselect(sampleTable, samples, kept.1)
        exampleSection.forEach { $0.isHidden = samples.isEmpty }
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
            let message = (error as? SpaceError)?.message ?? "\(error)"
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
            ask.tell((error as? SpaceError)?.message ?? "\(error)")
        }
        reload()
    }

    /// Saves the selected space as a .something file. Its memory goes with it only when the person says so, after
    /// seeing its keys and size; grants and journal never do (contract 8).
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
            ask.tell("\(space.name) was not exported. \(Home.words(error))")
        }
    }

    /// Reads a .something file the person chooses and makes it a new space, selected. It has no grant: what the
    /// grants file kept for the name it gets is dropped before anything is written, so a grants file that cannot be
    /// changed leaves no space, and the space asks for its rights at its first opening (contract 5).
    @objc func importChosen() {
        guard let url = ask.importFile() else { return }
        do {
            // Mapped, not loaded: a huge file is refused by Export.read for its size without being read.
            let received = try Export.read(try Data(contentsOf: url, options: .alwaysMapped))
            let folder = Spaces(root: places.spaces)
            let name = try Export.freeName(received, in: folder, memory: places.data)
            var file = try AppFile.read(places.grants)
            if file.spaces.removeValue(forKey: name) != nil { try file.write(places.grants) }
            try FileManager.default.createDirectory(at: places.spaces, withIntermediateDirectories: true)
            let space = try Export.place(received, as: name, in: folder, memory: places.data)
            reload()
            if let row = spaces.firstIndex(where: { $0.name == space.name }) { table.selectRowIndexes([row], byExtendingSelection: false) }
        } catch {
            ask.tell("\(url.lastPathComponent) was not imported. \(Home.words(error))")
        }
    }

    /// The sentence of a failure, with its code when it has one.
    static func words(_ error: Error) -> String {
        if let coded = error as? CodedError { return "\(coded.message) (\(coded.code)) \(Codes.all[coded.code]?.fix ?? "")" }
        return (error as? SpaceError)?.message ?? error.localizedDescription
    }

    @objc func showInFinder() {
        if let space = selected { reveal(space.location) }
    }

    /// Copies the selected example into the spaces folder, under its own name, and selects the copy. A copy has no
    /// grant: answers left in the grants file by a space of the same name, deleted in Finder, are forgotten first, as
    /// a received space never inherits rights by name (contract 5). It asks its rights at its first opening.
    @objc func makeACopy() {
        guard let sample = selectedSample else { return }
        let target = places.spaces.appendingPathComponent(sample.location.lastPathComponent)
        guard Spaces(root: places.spaces).named(sample.name) == nil, !FileManager.default.fileExists(atPath: target.path) else {
            return ask.tell("A space named \(sample.name) already exists in \(places.spaces.path); rename it to make a new copy.")
        }
        do {
            var file = try AppFile.read(places.grants)
            if file.spaces.removeValue(forKey: sample.name) != nil { try file.write(places.grants) }
        } catch {
            return ask.tell("The example \(sample.name) was not copied. \((error as? SpaceError)?.message ?? "\(error)")")
        }
        do {
            try FileManager.default.createDirectory(at: places.spaces, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sample.location, to: target)
        } catch {
            return ask.tell("The example \(sample.name) could not be copied to \(target.path): \(error.localizedDescription)")
        }
        reload()
        if let row = spaces.firstIndex(where: { $0.name == sample.name }) { table.selectRowIndexes([row], byExtendingSelection: false) }
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

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "something"
        window.isReleasedWhenClosed = false
        window.delegate = self
        func button(_ title: String, _ action: Selector?) -> NSButton {
            let button = NSButton(title: title, target: self, action: action)
            if action == nil {
                button.isEnabled = false
                button.toolTip = "Not in this version yet."
            }
            return button
        }
        actions = [button("Open", #selector(openSelected)), button("Export", #selector(exportSelected)),
                   button("Make default", #selector(makeDefault)), button("Show in Finder", #selector(showInFinder))]
        let bar = NSStackView(views: [actions[0], button("New", nil), button("Import", #selector(importChosen))] + actions[1...])
        let label = Card.header("Examples, read-only")
        let copy = button("Make a copy", #selector(makeACopy))
        exampleSection = [label, Home.scroll(sampleTable, height: 120), copy]
        let left = NSStackView(views: [bar, Card.line("Your spaces, in \(places.spaces.path)"), Home.scroll(table, height: 300)] + exampleSection)
        left.orientation = .vertical
        left.alignment = .leading
        left.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        let content = NSStackView(views: [left, card.view])
        content.alignment = .top
        window.contentView = content
        window.center()
        return window
    }

    static func scroll(_ list: NSTableView, height: CGFloat) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.documentView = list
        scroll.hasVerticalScroller = true
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 420).isActive = true
        return scroll
    }
}
