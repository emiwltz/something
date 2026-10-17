// Home (design 5): the spaces of the spaces folder in a table, the card of the selected one beside it, and below,
// the examples, read-only, each with "Make a copy" (the section shows nothing while there is none). Open, Make
// default and Show in Finder act on the selected space; New, Import and Export are shown, disabled, until they exist.
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
        do {
            preferred = try AppFile.read(places.grants).default
            told = nil
        } catch {
            preferred = nil
            let message = (error as? SpaceError)?.message ?? "\(error)"
            if message != told { ask.tell(message) }
            told = message
        }
        Home.reselect(table, spaces, kept.0)
        Home.reselect(sampleTable, samples, kept.1)
        exampleSection.forEach { $0.isHidden = samples.isEmpty }
        update()
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
        actions = [button("Open", #selector(openSelected)), button("Make default", #selector(makeDefault)),
                   button("Show in Finder", #selector(showInFinder))]
        let bar = NSStackView(views: [actions[0], button("New", nil), button("Import", nil), button("Export", nil), actions[1], actions[2]])
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
