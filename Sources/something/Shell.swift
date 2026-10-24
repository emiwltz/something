// The one window: a split view with the sidebar, the center and Info (the inspector, hidden at first), the window layer
// over all three, a toolbar with the sidebar toggle at the sidebar's edge, the title and file, a slot for the chip of
// waiting requests, Point, Reload, Info and Full Screen. Its backgrounds are the identity's, opaque: no vibrancy lets
// the desktop through. The center holds the open space's web view edge to edge under the toolbar, what keeps a space
// from being shown, the blank page, the templates or the tour, with the glass over it, which holds the assistant
// (Glass.swift; not over the tour).
// Closing the window keeps the app and its agents running, and closes the open space: the Dock icon or `something`
// shows the window again.
import AppKit
import SwiftUI

final class Shell: NSObject, NSToolbarDelegate, NSWindowDelegate {
    let window: NSWindow
    let split = NSSplitViewController()
    /// The center: one of its three states at a time.
    let center = NSView()
    let inspector: NSSplitViewItem
    let assistant: AssistantModel, library: Library
    /// What the center shows, and the page in it when a space is open.
    private var shown: NSView?
    private weak var page: NSView?
    /// The glass over the center, which holds the assistant: its sticker, or its card.
    let glass: Glass
    /// What covers the whole window: the toast, and later the palette and the sheets of keys.
    let layer: WindowLayer
    static let sidebar = NSToolbarItem.Identifier("sidebar"), title = NSToolbarItem.Identifier("title"),
               chip = NSToolbarItem.Identifier("chip"), tools = NSToolbarItem.Identifier("tools"), point = NSToolbarItem.Identifier("point"),
               reload = NSToolbarItem.Identifier("reload"), info = NSToolbarItem.Identifier("info"), full = NSToolbarItem.Identifier("full")
    /// The items that act on the open space, greyed (never hidden) while none is open.
    static let onSpace = [point, reload, info]
    /// The buttons of the group of tools, by their item: the toolbar would take a subitem's own view out of the group.
    private(set) var controls: [NSToolbarItem.Identifier: NSButton] = [:]
    /// The title and the file, on one line: the system's title would put the file under it.
    let titleLine = TitleLine()
    /// How many requests wait, all spaces together; hidden while none does.
    let chip = WaitingChip()
    /// Called when the person closes the window: the app closes the open space, whose page stops.
    var closed: () -> Void = {}
    /// Called with false when nobody can see the window (closed, minimized, hidden, covered), with true when it shows.
    var visible: (Bool) -> Void = { _ in }
    /// The tour while it is shown.
    private(set) var touring: Tour?

    /// `autosave` keeps the window's frame and the columns' widths in the app's defaults: never in a test, whose
    /// program has no bundle and would write them into the person's own preferences.
    init(library: Library, info: Info, assistant: AssistantModel, autosave: Bool) {
        (self.assistant, self.library) = (assistant, library)
        let sidebar = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: SidebarView(library: library, assistant: assistant)))
        (sidebar.minimumThickness, sidebar.maximumThickness) = (190, 320)
        let content = NSViewController()
        content.view = center
        inspector = NSSplitViewItem(inspectorWithViewController: NSHostingController(rootView: InspectorView(info: info)))
        (inspector.minimumThickness, inspector.maximumThickness) = (320, 320)
        [sidebar, NSSplitViewItem(viewController: content), inspector].forEach(split.addSplitViewItem)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        layer = WindowLayer(over: split.view)
        glass = Glass(over: center, model: assistant)
        super.init()
        library.heading = { [weak self] in self?.heading($0, $1, space: false) }
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1200, height: 760))
        // The columns' first widths; collapsed, Info keeps its width for when it is shown.
        window.layoutIfNeeded()
        split.splitView.setPosition(236, ofDividerAt: 0)
        split.splitView.setPosition(1200 - 320, ofDividerAt: 1)
        inspector.isCollapsed = true
        window.contentMinSize = NSSize(width: 640, height: 480)
        // The toolbar lies over the columns' own backgrounds, with the window's under the center.
        (window.backgroundColor, window.titlebarAppearsTransparent, window.titleVisibility) = (Look.Token.bg.color, true, .hidden)
        NotificationCenter.default.addObserver(self, selector: #selector(columnsMoved), name: NSSplitView.didResizeSubviewsNotification, object: split.splitView)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior.insert(.fullScreenPrimary)
        let toolbar = NSToolbar(identifier: "main")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.center()
        if autosave {
            window.setFrameAutosaveName("main")
            split.splitView.autosaveName = "main"
        }
        glass.motion = { [weak library] in library?.preferences.motion ?? .calm }
        glass.page = { [weak self] in self?.page }
        // One place for the sticker over every space, kept for the next start unless the person asked otherwise.
        let preferences = library.preferences
        glass.spot = preferences.rememberSticker ? preferences.sticker : nil
        glass.moved = { [weak preferences] spot in if preferences?.rememberSticker == true { preferences?.sticker = spot } }
        // The toolbar's lower edge, over the center only: the sidebar runs up to the window's top.
        let edge = NSBox()
        (edge.boxType, edge.borderWidth, edge.fillColor, edge.translatesAutoresizingMaskIntoConstraints) = (.custom, 0, Look.Token.line.color, false)
        center.addSubview(edge)
        NSLayoutConstraint.activate([edge.heightAnchor.constraint(equalToConstant: 1), edge.leadingAnchor.constraint(equalTo: center.leadingAnchor),
                                     edge.trailingAnchor.constraint(equalTo: center.trailingAnchor),
                                     edge.bottomAnchor.constraint(equalTo: center.safeAreaLayoutGuide.topAnchor)])
        show(nil)
    }

    /// ⌘J: shows or hides the conversation, opening the card when it was closed.
    @objc func toggleConversation(_ sender: Any?) {
        assistant.threadShown = !(assistant.threadShown && assistant.open)
        assistant.open = true
    }

    /// ⌘\: closes the card, or opens it.
    @objc func reduceAssistant(_ sender: Any?) { assistant.open.toggle() }

    func windowWillClose(_ notification: Notification) {
        visible(false)
        closed()
    }

    /// The sidebar changed width: the title measures the room it has again.
    @objc private func columnsMoved() { titleLine.invalidateIntrinsicContentSize() }

    /// The window changed size, which does not always move the columns: the title measures its room again.
    func windowDidResize(_ notification: Notification) { titleLine.invalidateIntrinsicContentSize() }

    /// something's sheets hang under the toolbar, centred over the space beside the sidebar; the system's own where
    /// it puts them.
    func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect) -> NSRect {
        let side = split.splitViewItems.first.flatMap { $0.isCollapsed ? nil : $0.viewController.view.frame.width } ?? 0
        return sheet is Sheet ? Sheet.place(in: window, sidebar: side) : rect
    }

    func windowDidChangeOcclusionState(_ notification: Notification) { visible(window.occlusionState.contains(.visible)) }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Shell.sidebar, .sidebarTrackingSeparator, Shell.title, .flexibleSpace,
         Shell.chip, Shell.tools]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    /// The mockup's toolbar items: plain icons in `ink2`, with the words of its tooltips and the keys of the command
    /// table. Point waits for its slice (T14), greyed as its menu item is; the chip's slot stays hidden while empty.
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        func item(_ id: NSToolbarItem.Identifier, _ label: String, _ symbol: String, _ tip: String, _ action: Selector?, words: String? = nil) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: id)
            let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(), target: nil, action: action)
            (button.isBordered, button.contentTintColor, button.toolTip) = (false, Look.Token.ink2.color, tip)
            button.symbolConfiguration = .init(pointSize: 13, weight: .medium)
            // The mockup's .ib is 28 points square; Point is its .chip, 9 points of padding around the icon and words.
            var width: CGFloat = 28
            if let words {
                let font = Look.font(.ui, size: 12, weight: .medium)
                // The space before the words makes the mockup's 6 points with the button's own gap after the icon.
                (button.title, button.imagePosition, button.imageHugsTitle, button.font) = (" " + words, .imageLeading, true, font)
                width = 9 + 13 + 6 + ceil(words.size(withAttributes: [.font: font]).width) + 9
            }
            NSLayoutConstraint.activate([button.heightAnchor.constraint(equalToConstant: 28), button.widthAnchor.constraint(equalToConstant: width)])
            // The image and action serve the overflow menu, where the toolbar puts an item without its view.
            (item.view, item.label, item.isBordered, item.autovalidates, item.image, item.action) = (button, label, false, false, button.image, action)
            return item
        }
        switch id {
        case Shell.title:
            let item = NSToolbarItem(itemIdentifier: id)
            (item.view, item.isBordered) = (titleLine, false)
            return item
        case Shell.chip:
            let item = NSToolbarItem(itemIdentifier: id)
            (item.view, item.isBordered, item.isHidden, item.label) = (chip, false, chip.count == 0, "Waiting")
            return item
        // The system's own sidebar item would sit by the traffic lights, in a capsule.
        case Shell.sidebar:
            let sidebar = item(id, "Sidebar", "sidebar.left", Keys.tooltip("sidebar", "Sidebar"), Keys.command("sidebar")?.action)
            (sidebar.view as? NSButton)?.target = split
            sidebar.target = split
            return sidebar
        case Shell.tools:
            // One item, since the toolbar would put its own gap between items: the mockup's are 4 points apart, and a
            // thin line parts Point, which closes the group of what reads the space, from Reload.
            let tools = [item(Shell.point, "Point", "scope", Keys.tooltip("pointpart", "Point"), Keys.command("pointpart")?.action, words: "Point"),
                         item(Shell.reload, "Reload", "arrow.clockwise", Keys.tooltip("reload", "Reload"), #selector(App.reloadSpace(_:))),
                         item(Shell.info, "Info", "info.circle", Keys.tooltip("insp", "Info"), #selector(App.toggleInfo(_:))),
                         item(Shell.full, "Full Screen", "viewfinder", Keys.tooltip("full", "Full Screen"), #selector(NSWindow.toggleFullScreen(_:)))]
            let line = NSBox()
            (line.boxType, line.borderWidth, line.fillColor) = (.custom, 0, Look.Token.line2.color)
            NSLayoutConstraint.activate([line.widthAnchor.constraint(equalToConstant: 1), line.heightAnchor.constraint(equalToConstant: 18)])
            let buttons = tools.compactMap { $0.view as? NSButton }, row = NSStackView(views: [buttons[0], line] + buttons.dropFirst().map { $0 as NSView })
            tools.forEach { $0.view = nil }
            self.controls = Dictionary(uniqueKeysWithValues: zip(tools.map(\.itemIdentifier), buttons))
            row.spacing = 4
            // The mockup's toolbar ends 10 points from the window's edge; the toolbar keeps 8.
            row.edgeInsets.right = 2
            [buttons[0], line].forEach { row.setCustomSpacing(8, after: $0) }
            titleLine.reserve = row.fittingSize.width + 24
            let group = NSToolbarItemGroup(itemIdentifier: id)
            (group.subitems, group.view, group.isBordered, group.autovalidates) = (tools, row, false, false)
            return group
        default: return nil
        }
    }

    /// The toolbar's items, those of the group of tools one by one.
    var toolbarItems: [NSToolbarItem] { (window.toolbar?.items ?? []).flatMap { ($0 as? NSToolbarItemGroup)?.subitems ?? [$0] } }

    /// Writes the title and the file in the toolbar, for the window menu and VoiceOver too, and greys what acts on a
    /// space when none is open (Point too when `point` is false: the page stopped).
    func heading(_ title: String, _ file: String, space: Bool, point: Bool = true) {
        (window.title, window.subtitle) = (title, file)
        let line = NSMutableAttributedString(string: title, attributes: [.font: Look.font(.ui, size: 13.5, weight: .semibold),
                                                                         .foregroundColor: Look.Token.ink.color, .kern: -0.135])
        if !file.isEmpty {
            line.append(NSAttributedString(string: "  " + file, attributes: [.font: Look.font(.ui, size: 11.5),
                                                                              .foregroundColor: Look.Token.ink3.color]))
        }
        titleLine.line = line
        titleLine.setAccessibilityLabel(file.isEmpty ? title : "\(title), \(file)")
        // Point stays greyed until its slice gives it an action, and while the page is stopped: nothing to point at.
        toolbarItems.filter { Shell.onSpace.contains($0.itemIdentifier) }.forEach {
            let control = controls[$0.itemIdentifier]
            $0.isEnabled = space && control?.action != nil && (point || $0.itemIdentifier != Shell.point)
            control?.isEnabled = $0.isEnabled
            // A borderless button with a tint draws the same enabled or not; the mockup's disabled .ib is at .32.
            control?.alphaValue = $0.isEnabled ? 1 : 0.32
        }
    }

    /// Says in the toolbar's chip that `count` requests wait, every space's (the chip goes away at 0), and on the
    /// sticker's badge that `mine` are the open space's.
    func waiting(_ count: Int, mine: Int) {
        glass.mine = mine
        guard chip.count != count else { return }
        chip.count = count
        window.toolbar?.items.first { $0.itemIdentifier == Shell.chip }?.isHidden = count == 0
        titleLine.invalidateIntrinsicContentSize()
    }

    /// Shows `words` at the bottom of the center for a moment; see Toast.
    @discardableResult
    func toast(_ words: String, action: Toast.Action? = nil, quiet: Bool = false, seconds: TimeInterval = 3.2) -> Toast {
        Toast.show(words, action: action, quiet: quiet, seconds: seconds, motion: library.preferences.motion, in: layer, under: center)
    }

    /// Shows `space` in the center, or the blank page for nil (the templates with `templates`), with its title and file
    /// in the toolbar. It ends the tour, and the sidebar the tour folded comes back.
    func show(_ space: SpaceView?, templates: Bool = false) {
        if touring != nil { split.splitViewItems[0].isCollapsed = false }
        touring = nil
        guard let space else {
            page = nil
            put(templates ? Shell.hosted(GalleryView(library: library)) : Shell.hosted(BlankView(model: assistant, library: library)))
            return templates ? bare("Templates", "Start from one, then make it yours") : bare("New Space", "")
        }
        page = space.blocked.isEmpty ? space.web : nil
        if space.blocked.isEmpty {
            put(space.area)
            space.cover(space.stopped ? Stopped(space, assistant: assistant, motion: library.preferences.motion) : nil)
            space.show(strip: ScriptError(space, assistant: assistant))
        } else {
            let fault = AssistantModel.Fault(title: space.title, name: space.space.name, codes: space.blocked.map(\.code))
            put(Shell.hosted(Unshown(problems: space.blocked.map { "\($0.message) \($0.fix) (\($0.code))" }, fault: fault, assistant: assistant)))
        }
        heading(space.title, space.space.location.lastPathComponent, space: true, point: !space.stopped)
    }

    /// Shows the tour in the center, alone: the sidebar folded, Info and the assistant hidden.
    func show(_ tour: Tour) {
        touring = tour
        put(Shell.hosted(TourView(tour: tour, assistant: assistant, templates: library.templates)))
        glass.isHidden = true
        split.splitViewItems[0].isCollapsed = true
        bare("something", "")
    }

    /// The toolbar's title and subtitle when no space is shown, its space's items greyed, and Info closed.
    private func bare(_ title: String, _ subtitle: String) {
        heading(title, subtitle, space: false)
        inspector.isCollapsed = true
    }

    /// Puts `shown` in the center in place of what was there, under the assistant.
    private func put(_ shown: NSView) {
        self.shown?.removeFromSuperview()
        glass.isHidden = false
        shown.translatesAutoresizingMaskIntoConstraints = false
        center.addSubview(shown, positioned: .below, relativeTo: glass)
        self.shown = shown
        // A space starts under the toolbar, never behind it.
        NSLayoutConstraint.activate([shown.topAnchor.constraint(equalTo: center.safeAreaLayoutGuide.topAnchor),
                                     shown.bottomAnchor.constraint(equalTo: center.bottomAnchor),
                                     shown.leadingAnchor.constraint(equalTo: center.leadingAnchor),
                                     shown.trailingAnchor.constraint(equalTo: center.trailingAnchor)])
    }

    /// `view` in the center: it takes the window's size, and never asks the window for its own.
    static func hosted(_ view: some View) -> NSView {
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        return host
    }

    /// Ends the sheets on `window`, the innermost first, as their Cancel would.
    static func endSheets(of window: NSWindow) {
        guard let sheet = window.attachedSheet else { return }
        endSheets(of: sheet)
        window.endSheet(sheet, returnCode: .cancel)
    }

    /// Brings the window to the front, made again if it was closed.
    func front() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        visible(true)
    }
}

/// The toolbar's title: drawn here, since a text field in a toolbar is greyed while its window is not the key one. It
/// gives way first when the window narrows, the file cut with an ellipsis, so that the tools never leave the toolbar.
final class TitleLine: NSView {
    /// 18 points from the sidebar's edge, as the mockup's toolbar starts; the toolbar gives the other 8.
    static let indent: CGFloat = 10
    var line = NSAttributedString() {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }

    /// What the tools need on its right, with the gap before them: the toolbar would rather move them to its overflow
    /// menu than narrow a view that asks for more.
    var reserve: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: NSSize {
        let whole = ceil(line.size().width) + TitleLine.indent
        let room = window.map { $0.frame.width - convert(NSPoint.zero, to: nil).x - reserve } ?? whole
        return NSSize(width: max(TitleLine.indent, min(whole, room)), height: ceil(line.size().height))
    }
    override func draw(_ dirtyRect: NSRect) {
        let cut = NSMutableAttributedString(attributedString: line), style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        cut.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: cut.length))
        cut.draw(in: NSRect(x: TitleLine.indent, y: 0, width: bounds.width - TitleLine.indent, height: bounds.height))
    }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
}

/// The toolbar's chip: the eyes of a request, how many wait and "wait for you", in a pill with a hairline and no
/// shadow. One meaning only, the count of every request, as the Dock's; a click shows the request (W3 adds its menu).
final class WaitingChip: NSButton {
    var count = 0 {
        didSet {
            setAccessibilityLabel("\(count) \(said)")
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    private var said: String { count == 1 ? "waits for you" : "wait for you" }
    /// The count, then the words, as drawn.
    private var parts: [NSAttributedString] {
        [("\(count)", NSFont.Weight.semibold), (said, .medium)].map { words, weight in
            NSAttributedString(string: words, attributes: [.font: Look.font(.ui, size: 12, weight: weight), .foregroundColor: Look.Token.ink.color])
        }
    }

    init() {
        super.init(frame: .zero)
        (isBordered, title, target, action) = (false, "", nil, #selector(App.showRequest(_:)))
        toolTip = Keys.tooltip("showreq", "Show Request")
    }
    required init?(coder: NSCoder) { nil }

    // The mockup's .wn-chip: 26 high, 8 before the eyes, 6 between the pieces, 10 after the words.
    override var intrinsicContentSize: NSSize {
        NSSize(width: 8 + 16 + parts.reduce(0) { $0 + 6 + ceil($1.size().width) } + 10, height: 26)
    }

    override func draw(_ dirtyRect: NSRect) {
        let pill = bounds.insetBy(dx: 0.5, dy: (bounds.height - 26) / 2 + 0.5), path = NSBezierPath(roundedRect: pill, xRadius: 12.5, yRadius: 12.5)
        Look.Token.bg2.color.setFill()
        path.fill()
        Look.Token.line2.color.setStroke()
        path.lineWidth = 1
        path.stroke()
        Sign.miniEyes(.wait, template: false).draw(in: NSRect(x: 8, y: bounds.midY - 5, width: 16, height: 10))
        var x: CGFloat = 8 + 16
        for piece in parts {
            let size = piece.size()
            piece.draw(at: NSPoint(x: x + 6, y: bounds.midY - size.height / 2))
            x += 6 + ceil(size.width)
        }
    }
}

/// The center when a space cannot be shown: what keeps it from being displayed, one problem per line with its code,
/// and the assistant asked to fix it, with something's own words only.
struct Unshown: View {
    let problems: [String], fault: AssistantModel.Fault
    let assistant: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("“\(fault.title)” can't be shown").font(.title2.weight(.semibold))
            ForEach(problems, id: \.self) { Text($0).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            Text("It reloads by itself when its files change.").foregroundStyle(.secondary)
            if assistant.kind != nil {
                Button("Ask \(assistant.name) to Fix It") { assistant.fix(fault) }
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(28)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
