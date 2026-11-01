// The one window: a split view with the sidebar, the center and Info (the inspector, hidden at first), the window layer
// over all three, and a calm toolbar: the sidebar toggle at the sidebar's edge, the space's name alone (a click on it
// opens Info), Point (pressed while the person points at the space's parts: PointOverlay.swift; a Quick Change leaves
// its frames at work, QuickFrame.swift, and an answer without a change in a note, MarginNote.swift), Info (pressed
// while it shows) and Page Full Screen (PageFull.swift); before them, while Full Access is on, its orange mark, which
// turns it off (Rules.swift). Off the spaces only the name shows. Reload is in the View menu; what waits for the person
// is said by the panel, the sidebar's Needs You and the Dock, never here. Its backgrounds are the identity's, opaque:
// no vibrancy lets the desktop through. The center holds the open space's web view edge to edge under the toolbar, what
// keeps a space from being shown, New Space or the templates; over a space, the glass, which holds the assistant
// (Glass.swift). Off the spaces the assistant is away: New Space has its own field. While the welcome is open, the
// window is out of sight; it arrives once it ends. In full screen the space is alone: the system hides the toolbar and
// the menu bar until the pointer reaches the top, the sidebar steps aside and the space starts at the screen's top; ⌃⌘S
// lays the sidebar over it (SidebarOver). Page Full Screen does the same inside the window, and a hidden sidebar floats
// (PageFull.swift).
// Closing the window keeps the app and its agents running, and closes the open space: the Dock icon or `something`
// shows the window again.
import AppKit
import SwiftUI

final class Shell: NSObject, NSToolbarDelegate, NSWindowDelegate {
    let window: NSWindow
    let split = Split()
    /// The center: one of its three states at a time.
    let center = NSView()
    /// The docked panel at the right edge, Info or History (Inspector.swift), collapsed at first.
    let inspector: NSSplitViewItem
    let info: Info
    let assistant: AssistantModel, library: Library
    /// What the center shows, and the page in it when a space is open.
    private(set) var shown: NSView?
    private weak var page: NSView?
    /// The space shown in the center, when one is.
    private(set) weak var space: SpaceView?
    /// Quick Change answers without a change, by space name, waiting for their space to be shown (showNote).
    private var unread: [String: (words: String, part: Pointing.Part)] = [:]
    /// The glass over the center, which holds the assistant: its sticker, or its card.
    let glass: Glass
    /// What covers the whole window: the toast, the palette and the shortcut sheet.
    let layer: WindowLayer
    static let sidebar = NSToolbarItem.Identifier("sidebar"), title = NSToolbarItem.Identifier("title"),
               tools = NSToolbarItem.Identifier("tools"), point = NSToolbarItem.Identifier("point"),
               info = NSToolbarItem.Identifier("info"), full = NSToolbarItem.Identifier("full")
    /// The items that act on the open space, hidden while none is open.
    static let onSpace = [point, info, full]
    /// The buttons of the group of tools, by their item: the toolbar would take a subitem's own view out of the group.
    private(set) var controls: [NSToolbarItem.Identifier: NSButton] = [:]
    /// The space's name, which opens Info.
    let titleLine = TitleLine()
    /// Full Access's mark, hidden while it is off.
    let fullMark = FullMark(target: nil, action: #selector(App.turnOffFullAccess(_:)))
    /// Called when the person closes the window: the app closes the open space, whose page stops.
    var closed: () -> Void = {}
    /// Called with false when nobody can see the window (closed, minimized, hidden, covered), with true when it shows.
    var visible: (Bool) -> Void = { _ in }
    /// The welcome window while it is open, this one out of sight.
    private(set) var welcoming: NSWindow?
    /// The space a build just made, until the window shows it: its opening may bring your assistant's hint (Hint.swift).
    var made: String?
    /// The window's undo manager: typing, and the changes of the spaces (Changes.swift).
    let undo = WindowUndo()
    /// Whether the window is in full screen, or entering it; the sidebar's own state before, given back after (also
    /// by Page Full Screen).
    private(set) var full = false
    var sideHidden = false
    /// Whether the page fills the window (Page Full Screen), and whether it will once the Mac's full screen is left.
    var pageFull = false, pageAfterFull = false
    /// The strips at the center's top and left edges that bring back the toolbar in Page Full Screen and the floating
    /// sidebar (PageFull.swift); the toolbar's height, measured while it shows.
    let topEdge = Reveal(delay: 0, leave: 0.6, clicks: false), leftEdge = Reveal(delay: 0.2, clicks: true)
    var bar: CGFloat = 52
    /// The watch on the sidebar column's collapse, which makes it float or not.
    var collapse: NSKeyValueObservation?
    /// The left edge's top: under the toolbar, or the window's top in Page Full Screen.
    var leftTop: (under: NSLayoutConstraint, top: NSLayoutConstraint)?
    /// What holds the top of what the center shows: the toolbar's lower edge, or in full screen the window's top.
    var top: NSLayoutConstraint?
    /// The toolbar's lower edge, over the center only.
    let edge = NSBox()

    /// `autosave` keeps the window's frame and the columns' widths in the app's defaults: never in a test, whose
    /// program has no bundle and would write them into the person's own preferences.
    init(library: Library, info: Info, assistant: AssistantModel, autosave: Bool) {
        (self.assistant, self.library, self.info) = (assistant, library, info)
        let list = SidebarView(library: library, assistant: assistant, eyes: { [unowned assistant] in assistant.eyes(of: $0) })
        let sidebar = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: list))
        (sidebar.minimumThickness, sidebar.maximumThickness) = Shell.sideRange
        let content = NSViewController()
        content.view = center
        inspector = NSSplitViewItem(inspectorWithViewController: InfoController(rootView: InspectorView(info: info, library: library, assistant: assistant)))
        (inspector.minimumThickness, inspector.maximumThickness) = (Shell.infoWidth, Shell.infoWidth)
        // The toolbar stays one band across the window: the panel begins under it, as the mockup draws it.
        inspector.allowsFullHeightLayout = false
        [sidebar, NSSplitViewItem(viewController: content), inspector].forEach(split.addSplitViewItem)
        window = MainWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        layer = WindowLayer(over: split.view)
        glass = Glass(over: center, model: assistant)
        super.init()
        split.over = { [unowned self] in sidebarOver() }
        split.laid = { [unowned self] in full || pageFull ? SidebarOver.shown(in: layer) != nil : nil }
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
        // Its own identifier: toolbars of one identifier share their state, and the tests hold many windows in one process.
        let toolbar = NSToolbar(identifier: "main-" + UUID().uuidString)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.center()
        if autosave {
            window.setFrameAutosaveName("main")
            split.splitView.autosaveName = "main"
        }
        followSize(Look.scale.size)
        assistant.answered = { [weak self] quick, words in self?.note(words, about: quick) }
        info.close = { [weak self] in self?.showInfo(false) }
        titleLine.opened = { [weak self] in self.map { $0.toggleInfo(spaceOpen: $0.space != nil) } }
        info.showHistory = { [weak self] in self?.showHistory() }
        info.converse = { [weak self] in self?.converse() }
        library.renamed = { [weak self] name in if let space = self?.space, space.space.name == name { self?.heading(space) } }
        library.told = { [weak self] words in self?.toast(words, quiet: true) }
        library.exported = { [weak self, weak library] url, memory in
            let words = "\(url.lastPathComponent) is in Downloads · one HTML file\(memory ? ", its memory inside" : "")"
            _ = self?.toast(words, action: Toast.Action(label: "Show") { library?.reveal(url) }, seconds: 6)
        }
        glass.motion = { [weak library] in library?.preferences.motion ?? .calm }
        glass.page = { [weak self] in self?.page }
        // One place for the sticker over every space, kept for the next start.
        let preferences = library.preferences
        glass.spot = preferences.sticker
        glass.moved = { [weak preferences] in preferences?.sticker = $0 }
        // The toolbar's lower edge, over the center only: the sidebar runs up to the window's top.
        (edge.boxType, edge.borderWidth, edge.fillColor, edge.translatesAutoresizingMaskIntoConstraints) = (.custom, 0, Look.Token.line.color, false)
        center.addSubview(edge)
        NSLayoutConstraint.activate([edge.heightAnchor.constraint(equalToConstant: 1), edge.leadingAnchor.constraint(equalTo: center.leadingAnchor),
                                     edge.trailingAnchor.constraint(equalTo: center.trailingAnchor),
                                     edge.bottomAnchor.constraint(equalTo: center.safeAreaLayoutGuide.topAnchor)])
        edges()
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

    /// The columns moved: the title measures the room it has again; Info shown, a note leaves the right edge to it.
    @objc private func columnsMoved() {
        titleLine.invalidateIntrinsicContentSize()
        reveals()
        if !inspector.isCollapsed { space?.note?.dismiss() }
    }

    /// The window changed size, which does not always move the columns: the title measures its room again.
    func windowDidResize(_ notification: Notification) {
        titleLine.invalidateIntrinsicContentSize()
    }

    /// something's sheets hang under the toolbar, centred over the space beside the sidebar; the system's own where
    /// it puts them.
    func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect) -> NSRect {
        let side = split.splitViewItems.first.flatMap { $0.isCollapsed ? nil : $0.viewController.view.frame.width } ?? 0
        return sheet is Sheet ? Sheet.place(in: window, sidebar: side) : rect
    }

    /// Full screen hides the toolbar with the menu bar, as a Mac app's space alone: both come down at the top edge.
    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposed: NSApplication.PresentationOptions = []) -> NSApplication.PresentationOptions {
        proposed.union([.fullScreen, .autoHideToolbar, .autoHideMenuBar])
    }

    func windowWillEnterFullScreen(_ notification: Notification) { fullScreen(true) }
    func windowWillExitFullScreen(_ notification: Notification) { fullScreen(false) }
    // A transition that fails leaves the window as it was: its layout goes back too.
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { fullScreen(false) }
    func windowDidFailToExitFullScreen(_ window: NSWindow) { fullScreen(true) }
    /// Page Full Screen asked for in the Mac's full screen comes once the window is back.
    func windowDidExitFullScreen(_ notification: Notification) {
        if pageAfterFull { pageFullScreen(true) }
    }

    /// Lays the window out for full screen (`on`) or back: the sidebar steps aside and comes back as it was, the space
    /// starts at the window's top, which the hidden toolbar no longer holds, and the Full Screen button turns to leave
    /// it. Pinned to the top rather than to the safe area, the page does not move when the toolbar comes down over it.
    /// The sticker is discreet there.
    func fullScreen(_ on: Bool) {
        guard on != full else { return }
        if on { pageFullScreen(false) }
        full = on
        _ = SidebarOver.close(in: layer)
        let side = split.splitViewItems[0]
        if on { sideHidden = side.isCollapsed }
        side.isCollapsed = on || sideHidden
        top?.isActive = false
        top = shown.map(pin)
        top?.isActive = true
        edge.isHidden = on
        glass.discreet = on
        reveals()
    }

    /// ⌃⌘S in full screen: lays the sidebar over the space, or takes it away. In Page Full Screen the floating sidebar
    /// comes or goes. Returns false elsewhere, where the sidebar column shows or hides as usual: a floating sidebar laid over is kept.
    private func sidebarOver() -> Bool {
        if pageFull {
            if !SidebarOver.close(in: layer) { float() }
            return true
        }
        guard full else {
            _ = SidebarOver.close(in: layer)
            return false
        }
        layOver(floating: false)
        return true
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { undo }

    func windowDidChangeOcclusionState(_ notification: Notification) { visible(window.occlusionState.contains(.visible)) }

    /// The sidebar's least and greatest widths, and Info's width, at the interface size.
    static var sideRange: (CGFloat, CGFloat) { (190 * Look.scale.size.factor, 320 * Look.scale.size.factor) }
    static var infoWidth: CGFloat { 320 * Look.scale.size.factor }

    /// Follows the interface size from `size`: the views that read Look draw again by themselves; the toolbar's name,
    /// the columns' widths and the page's zoom are set here.
    private func followSize(_ size: Look.Size) {
        let now = Look.scale.size
        withObservationTracking { _ = Look.scale.size } onChange: { [weak self] in
            DispatchQueue.main.async { self?.followSize(now) }
        }
        guard now != size else { return }
        // The toolbar's buttons grow in place, kept (they hold Point's pressed state), as item(_:) would make them now;
        // the sticker too.
        for item in toolbarItems {
            guard let button = controls[item.itemIdentifier] ?? item.view as? NSButton else { continue }
            button.constraints.filter { [.width, .height].contains($0.firstAttribute) }.forEach { $0.constant *= now.factor / size.factor }
            button.symbolConfiguration = Shell.symbol(item.itemIdentifier)
            if item.itemIdentifier == Shell.point { button.font = Look.font(.ui, size: 12, weight: .medium) }
            // Its words are an attributed title, written with the font of the moment: written again in the new one.
            if let tool = button as? ToolButton { let on = tool.pressed; tool.pressed = on }
        }
        glass.place()
        heading(window.title, window.subtitle, space: titleLine.space, point: space?.pointable ?? false)
        space?.web.pageZoom = now.factor
        let side = split.splitViewItems[0], width = side.viewController.view.frame.width
        (inspector.minimumThickness, inspector.maximumThickness) = (Shell.infoWidth, Shell.infoWidth)
        (side.minimumThickness, side.maximumThickness) = Shell.sideRange
        if !side.isCollapsed { split.splitView.setPosition(width * now.factor / size.factor, ofDividerAt: 0) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Shell.sidebar, .sidebarTrackingSeparator, Shell.title, .flexibleSpace, Shell.tools]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    /// The mockup's toolbar items: plain icons in `ink2`, with the words of its tooltips and the keys of the command
    /// table.
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        func item(_ id: NSToolbarItem.Identifier, _ label: String, _ symbol: String, _ tip: String, _ action: Selector?, words: String? = nil) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: id)
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage()
            let button = ToolButton(image: image, target: nil, action: action)
            (button.chip, button.isBordered, button.contentTintColor, button.toolTip) = (id == Shell.point, false, Look.Token.ink2.color, tip)
            let k = Look.scale.size.factor
            button.symbolConfiguration = Shell.symbol(id)
            // The mockup's .ib is 28 points square; Point is its .chip, 9 points of padding around the icon and words.
            var width = 28 * k
            if let words {
                let font = Look.font(.ui, size: 12, weight: .medium)
                // The space before the words makes the mockup's 6 points with the button's own gap after the icon.
                (button.title, button.imagePosition, button.imageHugsTitle, button.font) = (" " + words, .imageLeading, true, font)
                width = (9 + 13 + 6 + 9) * k + ceil(words.size(withAttributes: [.font: font]).width)
            }
            NSLayoutConstraint.activate([button.heightAnchor.constraint(equalToConstant: 28 * k), button.widthAnchor.constraint(equalToConstant: width)])
            // The image and action serve the overflow menu, where the toolbar puts an item without its view.
            (item.view, item.label, item.isBordered, item.autovalidates, item.image, item.action) = (button, label, false, false, button.image, action)
            return item
        }
        switch id {
        case Shell.title:
            let item = NSToolbarItem(itemIdentifier: id)
            (item.view, item.isBordered) = (titleLine, false)
            return item
        // The system's own sidebar item would sit by the traffic lights, in a capsule.
        case Shell.sidebar:
            let sidebar = item(id, "Sidebar", "sidebar.left", Keys.tooltip("sidebar", "Sidebar"), Keys.command("sidebar")?.action)
            (sidebar.view as? NSButton)?.target = split
            sidebar.target = split
            return sidebar
        case Shell.tools:
            // One item, since the toolbar would put its own gap between items: the mockup's are 4 points apart.
            let tools = [item(Shell.point, "Point", "scope", Keys.tooltip("pointpart", "Point"), Keys.command("pointpart")?.action, words: "Point"),
                         item(Shell.info, "Info", "info.circle", Keys.tooltip("insp", "Info"), #selector(App.toggleInfo(_:))),
                         item(Shell.full, "Page Full Screen", "viewfinder", Keys.tooltip("pagefull", "Page Full Screen"), Keys.command("pagefull")?.action)]
            let buttons = tools.compactMap { $0.view as? NSButton }, row = NSStackView(views: [fullMark] + buttons)
            tools.forEach { $0.view = nil }
            self.controls = Dictionary(uniqueKeysWithValues: zip(tools.map(\.itemIdentifier), buttons))
            row.spacing = 4
            row.setCustomSpacing(10, after: fullMark)
            fullMark.isHidden = !library.preferences.fullAccess
            // The mockup's toolbar ends 10 points from the window's edge; the toolbar keeps 8.
            row.edgeInsets.right = 2
            titleLine.reserve = row.fittingSize.width + 24
            let group = NSToolbarItemGroup(itemIdentifier: id)
            (group.subitems, group.view, group.isBordered, group.autovalidates) = (tools, row, false, false)
            return group
        default: return nil
        }
    }

    /// A tool's icon at the interface size: thin strokes as the mockup's, Point's target a size below the others', Full
    /// Screen's corners heavier.
    static func symbol(_ id: NSToolbarItem.Identifier) -> NSImage.SymbolConfiguration {
        .init(pointSize: (id == point ? 12 : 13) * Look.scale.size.factor, weight: id == full ? .bold : .regular)
    }

    /// The toolbar's items, those of the group of tools one by one.
    var toolbarItems: [NSToolbarItem] { (window.toolbar?.items ?? []).flatMap { ($0 as? NSToolbarItemGroup)?.subitems ?? [$0] } }

    /// Writes the name in the toolbar, alone, for the window menu and VoiceOver too (`subtitle` only for the window's
    /// own, which nothing draws), and shows what acts on a space only while one is open: off the spaces, the toolbar
    /// holds the name alone. Point is greyed when `point` is false: the page stopped.
    func heading(_ title: String, _ subtitle: String, space: Bool, point: Bool = true) {
        (window.title, window.subtitle) = (title, subtitle)
        titleLine.line = NSAttributedString(string: title, attributes: [.font: Look.font(.ui, size: 13.5, weight: .semibold),
                                                                        .foregroundColor: Look.Token.ink.color, .kern: -0.135])
        titleLine.space = space
        // Point is greyed while the page is stopped or cannot be shown: nothing to point at.
        toolbarItems.filter { Shell.onSpace.contains($0.itemIdentifier) }.forEach {
            let control = controls[$0.itemIdentifier]
            $0.isEnabled = space && control?.action != nil && (point || $0.itemIdentifier != Shell.point)
            control?.isEnabled = $0.isEnabled
            control?.isHidden = !space
            // A borderless button with a tint draws the same enabled or not; the mockup's disabled .ib is at .32.
            control?.alphaValue = $0.isEnabled ? 1 : 0.32
        }
    }

    /// What View's and Space's Info items say: what they will do.
    var infoWords: String { infoShown && info.content == .info ? "Hide Info" : "Show Info" }

    /// Names a menu item as it reads now: the Info items, in View and Space, say Hide Info while Info shows; Page Full
    /// Screen's says Exit while it is on.
    func retitle(_ item: NSMenuItem) {
        if item.identifier?.rawValue == "insp" { item.title = infoWords }
        if item.identifier?.rawValue == "pagefull" { item.title = pageFull ? "Exit Page Full Screen" : "Enter Page Full Screen" }
    }

    /// The requests waiting: `spaces`, the spaces they belong to, oldest first, go to the sidebar's Needs You; `mine`,
    /// the open space's own, to the sticker's label.
    func waiting(_ spaces: [String], mine: Int) {
        glass.mine = mine
        let needs = spaces.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        if library.sidebar.needs != needs { library.sidebar.needs = needs }
    }

    /// Shows `words` at the bottom of the center for a moment; see Toast.
    @discardableResult
    func toast(_ words: String, action: Toast.Action? = nil, quiet: Bool = false, seconds: TimeInterval = 3.2) -> Toast {
        Toast.show(words, action: action, quiet: quiet, seconds: seconds, motion: library.preferences.motion, in: layer, under: center,
                   clearOf: glass.stickerShown)
    }

    /// Shows `space` in the center, or the blank page for nil (the templates with `templates`), with its title and file
    /// in the toolbar.
    func show(_ space: SpaceView?, templates: Bool = false) {
        library.previewing = false
        self.space = space
        // A space picked in the sidebar laid over the page takes its place; off the spaces, the page's full screen ends.
        _ = SidebarOver.close(in: layer)
        HintBubble.close(in: layer)
        if space == nil { pageFullScreen(false) }
        // A reload keeps point mode and its picks (the overlay asks again once the page loaded); only a page that
        // cannot be shown or stopped ends it.
        if let space, !space.pointable { space.point(nil) }
        pressPoint(space?.pointer != nil)
        guard let space else {
            page = nil
            let gallery = Gallery(home: templates ? Gallery.page : ("New Space", ""), told: { [weak self] title, subtitle in
                self?.heading(title, subtitle, space: false)
                self?.library.previewing = templates && title != Gallery.page.0
            })
            put(templates ? Shell.hosted(GalleryView(library: library, model: gallery))
                : Shell.hosted(BlankView(model: assistant, library: library, gallery: gallery)))
            glass.isHidden = true
            return bare(gallery.home.0, gallery.home.1)
        }
        page = space.blocked.isEmpty ? space.web : nil
        if space.blocked.isEmpty {
            put(space.area)
            space.cover(space.stopped ? Stopped(space, assistant: assistant, motion: library.preferences.motion) : nil)
            space.show(strip: ScriptError(space, assistant: assistant))
            // Back on a space whose Quick Change still shows, its frames come back with it.
            if let quick = assistant.quicks[space.space.name], !space.area.subviews.contains(where: { $0 is QuickFrame }) {
                QuickFrame.show(quick, over: space)
            }
            showNote()
            hintLater(space.space.name)
        } else {
            let fault = AssistantModel.Fault(title: space.title, name: space.space.name, codes: space.blocked.map(\.code))
            put(Shell.hosted(Unshown(problems: space.blocked.map { "\($0.message) \($0.fix)" }, fault: fault, assistant: assistant)))
        }
        heading(space)
    }

    /// ⌥⌘S, the toolbar's Point and the card's: starts point mode over the space shown, or stops it. Starting folds
    /// the card away, so that nothing of the assistant stands over the parts, and gives the overlay the keys (Esc).
    func point() {
        guard let space, space.pointable else { return }
        guard space.pointer == nil else { return stopPointing() }
        space.note?.dismiss()
        let overlay = PointOverlay(space, motion: library.preferences.motion)
        overlay.stopped = { [weak self] in self?.stopPointing() }
        let name = space.space.name
        overlay.eyes = { [weak self] in self?.assistant.eyes(of: name) ?? .unknown }
        overlay.quickChange = { [weak self, weak space] words, parts in
            guard let self, let space else { return }
            quickChange(words, parts: parts, on: space)
        }
        overlay.addComment = { [weak self, weak space] words, parts in
            guard let self, let space else { return }
            comments(on: space).add(words, parts)
        }
        overlay.commented = { [weak space] in space.flatMap(Comments.of)?.list.isEmpty == false }
        assistant.open = false
        space.point(overlay)
        pressPoint(true)
        window.makeFirstResponder(overlay)
    }

    /// Quick Change from the composer: a temporary session of the space's assistant takes `words` about `parts`; point
    /// mode closes and the parts keep their frames, at work (QuickFrame). A refusal is said, and the mode stays.
    func quickChange(_ words: String, parts: [Pointing.Part], on space: SpaceView) {
        if let refused = assistant.quickChange(words, parts: parts, at: AssistantModel.place(space)) {
            _ = toast(refused, quiet: true, seconds: 4)
            return
        }
        stopPointing()
        if let quick = assistant.quicks[space.space.name] { QuickFrame.show(quick, over: space) }
    }

    /// The comments over `space`, made at the first: sent to its main assistant, the card then open on the
    /// conversation; a refusal is said, and the comments stay.
    func comments(on space: SpaceView) -> Comments {
        if let kept = Comments.of(space) { return kept }
        let made = Comments.show(over: space), name = space.space.name
        made.outcome = { [weak self] in self?.assistant.commented(on: name) ?? .back }
        made.pointing = { [weak space] in space?.pointer != nil }
        made.send = { [weak self, weak space] list in
            guard let self, let space else { return false }
            if let refused = assistant.comment(list.map { ($0.part, $0.words) }, at: AssistantModel.place(space)) {
                _ = toast(refused, quiet: true, seconds: 4)
                return false
            }
            if self.space === space {
                stopPointing()
                (assistant.open, assistant.threadShown) = (true, true)
            }
            return true
        }
        return made
    }

    /// ⌘↵ in this window: the open space's comments leave together, unless the composer is open (its ⌘↵ adds one).
    /// Returns whether they did, the key then used up. Keys' "send" command names this key; this is where it is handled.
    func sendComments(_ event: NSEvent) -> Bool {
        guard [36, 76].contains(event.keyCode), event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.windowNumber == window.windowNumber, window.attachedSheet == nil, let space, space.pointer?.composer == nil,
              let comments = Comments.of(space), comments.phase == .writing, !comments.list.isEmpty else { return false }
        comments.sendAll()
        return true
    }

    /// A Quick Change that changed nothing answered `words`: a note beside its first part, now on the space shown, or
    /// when its space is shown again. The focus stays where it is: the person may be typing to the main assistant.
    func note(_ words: String, about quick: AssistantModel.Quick) {
        guard let part = quick.parts.first else { return }
        unread[quick.space] = (words, part)
        showNote()
    }

    /// The answer waiting for the space shown, as a note, Info closed for it (the right edge holds one thing at a time).
    private func showNote() {
        guard let space, space.blocked.isEmpty, let waiting = unread.removeValue(forKey: space.space.name) else { return }
        showInfo(false)
        MarginNote.show(waiting.words, about: waiting.part, title: space.title, over: space)
    }

    /// The space `name` left (trashed): an answer still waiting for it never shows for a later space of that name.
    func forget(_ name: String) { unread[name] = nil }

    /// Esc typed in this window, wherever the focus is, closes the top thing: the shortcut sheet or the palette, over
    /// all; else the panel when it has the keys (History's); else point mode's step back; else a margin note, the top
    /// thing over the page. Returns whether one closed, the key then used up (the assistant's nudge waits for an Esc
    /// nothing took).
    func escape(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53, event.windowNumber == window.windowNumber else { return false }
        if ScrimCard.close(in: layer) { return true }
        guard window.attachedSheet == nil, let space else { return false }
        if !inspector.isCollapsed, let held = window.firstResponder as? NSView, held.isDescendant(of: inspector.viewController.view) {
            showInfo(false)
            return true
        }
        if let pointer = space.pointer, pointer.escape() { return true }
        if let note = space.note {
            note.dismiss()
            return true
        }
        // The open card is the last layer: Esc folds it into the sticker wherever the focus is. Inside the card, the
        // card's own Esc does it, after its field had the key (an input method's Esc).
        let inCard = (window.firstResponder as? NSView)?.isDescendant(of: glass.card) == true
        guard !inCard else { return false }
        if assistant.open, assistant.place.space != nil {
            assistant.escape()
            return true
        }
        // Page Full Screen is under everything else, and an input method's Esc ends its composition, not the page's.
        if let typing = window.firstResponder as? NSTextInputClient, typing.hasMarkedText() { return false }
        guard pageFull else { return false }
        pageFullScreen(false)
        return true
    }

    /// Stops point mode, the page's keys back to it.
    func stopPointing() {
        guard let space, space.pointer != nil else { return }
        space.point(nil)
        pressPoint(false)
        window.makeFirstResponder(space.web)
    }

    private func pressPoint(_ on: Bool) {
        (controls[Shell.point] as? ToolButton)?.pressed = on
        if on { HintBubble.close(in: layer, only: .point) }
        space.flatMap(Comments.of)?.changed()
    }

    /// Heads the toolbar with `space`: the name the person gave it in the sidebar, else its declared title.
    private func heading(_ space: SpaceView) {
        heading(library.entry(space.space.name)?.title ?? space.title, "", space: true, point: space.pointable)
    }

    /// Opens `model`'s welcome alone, centred on the screen, this window out of sight until it ends. The welcome takes
    /// the keys; the menus grey this window's commands (App). `onScreen` false leaves both windows as they are, as a
    /// test's. Returns the welcome's window.
    @discardableResult
    func welcome(_ model: WelcomeModel, onScreen: Bool = true) -> NSWindow {
        welcoming?.close()
        model.announce = { [layer] in layer.announce($0) }
        let welcome = Welcome.window(model, assistant: assistant, motion: library.preferences.motion)
        welcome.setFrame(Welcome.place(on: window.screen ?? NSScreen.main), display: false)
        welcoming = welcome
        guard onScreen else { return welcome }
        window.orderOut(nil)
        welcome.makeKeyAndOrderFront(nil)
        return welcome
    }

    /// The welcome ended: it goes, and this window arrives, fading in under Calm motion, on the example or on New
    /// Space, its field taking the keys; or as it was, when Help's welcome was left. Skipped, it says where the story is.
    func welcomed(_ ending: WelcomeModel.Ending = .made) {
        guard let welcome = welcoming else { return }
        welcoming = nil
        welcome.close()
        let example = [.example, .skippedToExample].contains(ending)
        if example, library.entry("agents") != nil {
            library.select(.space("agents"))
        } else if example, let template = library.templates.first(where: { $0.id == "agents" }) {
            library.use(template)
        } else if ending != .left {
            library.select(.newSpace)
        }
        let calm = Look.duration(0.45, Look.motion(library.preferences.motion))
        if !window.isVisible, calm > 0 { window.alphaValue = 0 }
        front()
        if !example, ending != .left { assistant.focus() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = calm
            window.animator().alphaValue = 1
        }
        if [.skipped, .skippedToExample].contains(ending) { toast("Help › Welcome shows this again", quiet: true) }
    }

    /// The toolbar's title and subtitle when no space is shown, its space's items hidden, and Info closed.
    private func bare(_ title: String, _ subtitle: String) {
        heading(title, subtitle, space: false)
        showInfo(false)
    }

    /// Puts `shown` in the center in place of what was there, under the assistant.
    private func put(_ shown: NSView) {
        self.shown?.removeFromSuperview()
        glass.isHidden = false
        shown.translatesAutoresizingMaskIntoConstraints = false
        center.addSubview(shown, positioned: .below, relativeTo: glass)
        self.shown = shown
        let top = pin(shown)
        self.top = top
        NSLayoutConstraint.activate([top, shown.bottomAnchor.constraint(equalTo: center.bottomAnchor),
                                     shown.leadingAnchor.constraint(equalTo: center.leadingAnchor),
                                     shown.trailingAnchor.constraint(equalTo: center.trailingAnchor)])
    }

    /// The top of `shown`: under the toolbar, never behind it; in either full screen, the window's top.
    func pin(_ shown: NSView) -> NSLayoutConstraint {
        shown.topAnchor.constraint(equalTo: full || pageFull ? center.topAnchor : center.safeAreaLayoutGuide.topAnchor)
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

    /// Brings the window to the front, made again if it was closed; while the welcome is open, the welcome.
    func front() {
        (welcoming ?? window).makeKeyAndOrderFront(nil)
        NSApp.activate()
        visible(true)
    }
}

/// The split view of the window: ⌃⌘S and the toolbar's toggle ask `over` first, which lays the sidebar over the space
/// in full screen instead of showing its column.
final class Split: NSSplitViewController {
    var over: () -> Bool = { false }
    /// Whether the sidebar is laid over the space, nil where it is not laid over but shown as a column.
    var laid: () -> Bool? = { nil }
    override func toggleSidebar(_ sender: Any?) {
        if !over() { super.toggleSidebar(sender) }
    }
    /// ⌃⌘S says what it does: "Hide Sidebar" while the sidebar shows, as a column or laid over, else "Show Sidebar".
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard item.action == #selector(toggleSidebar(_:)) else { return super.validateUserInterfaceItem(item) }
        let laid = laid(), shown = laid ?? !(splitViewItems.first?.isCollapsed ?? true)
        (item as? NSMenuItem)?.title = shown ? "Hide Sidebar" : "Show Sidebar"
        return laid != nil || super.validateUserInterfaceItem(item)
    }
}

/// The main window. NSWindow answers toggleSidebar: itself, without the split view's override, whenever nothing in the
/// split view has the focus: ⌃⌘S would then never lay the sidebar over the space.
/// The menu validates ⌃⌘S against this window then too: NSWindow's own validation reaches the split view today, but
/// privately, so the window asks it itself.
final class MainWindow: NSWindow {
    @objc func toggleSidebar(_ sender: Any?) { (contentViewController as? Split)?.toggleSidebar(sender) }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard item.action == #selector(Split.toggleSidebar(_:)), let split = contentViewController as? Split else {
            return super.validateUserInterfaceItem(item)
        }
        return split.validateUserInterfaceItem(item)
    }
    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        item.action == #selector(Split.toggleSidebar(_:)) ? validateUserInterfaceItem(item) : super.validateMenuItem(item)
    }
}

/// The toolbar's name: drawn here, since a text field in a toolbar is greyed while its window is not the key one. It
/// gives way first when the window narrows, cut with an ellipsis, so that the tools never leave the toolbar. Over a
/// space it is a button, plain words as the mockup's, its chip drawn only under the pointer or while Info is open: a
/// click, or VoiceOver's press, opens Info or closes it, as ⌘I does.
final class TitleLine: NSView {
    /// 18 points from the sidebar's edge, as the mockup's toolbar starts; the toolbar gives the other 8. The chip starts
    /// 8 points before the words.
    static let indent: CGFloat = 10
    /// The chip's height, and how far it reaches after the words.
    static let chip: CGFloat = 26, trail: CGFloat = 8
    var line = NSAttributedString() {
        didSet {
            setAccessibilityLabel(line.string)
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    /// Whether it names an open space, and so opens Info.
    var space = false {
        didSet {
            setAccessibilityRole(space ? .button : .staticText)
            setAccessibilityHelp(space ? Keys.tooltip("insp") : nil)
            toolTip = space ? Keys.tooltip("insp") : nil
            window?.invalidateCursorRects(for: self)
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    /// Whether the pointer is over the chip, and whether Info is open: either draws it.
    private var lit = false {
        didSet { needsDisplay = true }
    }
    var held = false {
        didSet { needsDisplay = true }
    }

    /// What the tools need on its right, with the gap before them: the toolbar would rather move them to its overflow
    /// menu than narrow a view that asks for more.
    var reserve: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: NSSize {
        let whole = ceil(line.size().width) + TitleLine.indent + (space ? TitleLine.trail : 0)
        let room = window.map { $0.frame.width - convert(NSPoint.zero, to: nil).x - reserve } ?? whole
        return NSSize(width: max(TitleLine.indent, min(whole, room)), height: max(ceil(line.size().height), space ? TitleLine.chip : 0))
    }
    override func draw(_ dirtyRect: NSRect) {
        let cut = NSMutableAttributedString(attributedString: line), style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        cut.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: cut.length))
        let height = ceil(line.size().height), words = bounds.width - TitleLine.indent - (space ? TitleLine.trail : 0)
        if space, lit || held {
            (held ? Look.Token.sel : .hover).color.setFill()
            let chip = NSRect(x: TitleLine.indent - 8, y: (bounds.height - TitleLine.chip) / 2, width: bounds.width - TitleLine.indent + 8, height: TitleLine.chip)
            NSBezierPath(roundedRect: chip, xRadius: Look.control, yRadius: Look.control).fill()
        }
        cut.draw(in: NSRect(x: TitleLine.indent, y: (bounds.height - height) / 2, width: words, height: height))
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { lit = space }
    override func mouseExited(with event: NSEvent) { lit = false }
    override func resetCursorRects() {
        if space { addCursorRect(bounds, cursor: .pointingHand) }
    }
    // Over a space a press is the button's, not the window's to drag.
    override var mouseDownCanMoveWindow: Bool { !space }
    override func mouseDown(with event: NSEvent) {
        if !space { super.mouseDown(with: event) }
    }
    override func mouseUp(with event: NSEvent) {
        guard space, bounds.contains(convert(event.locationInWindow, from: nil)) else { return super.mouseUp(with: event) }
        opened()
    }
    /// Opens Info, or closes it, as ⌘I does: the Shell's.
    var opened: () -> Void = {}
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityPerformPress() -> Bool {
        guard space else { return false }
        opened()
        return true
    }
}

/// The center when a space cannot be shown, in the card a stopped space shows (Stopped.box, CardFace): the sign,
/// its title in Fraunces, what keeps it from being displayed in plain words, the assistant asked to fix it, and the
/// codes in small mono at the foot; something's own words only.
struct Unshown: View {
    let problems: [String], fault: AssistantModel.Fault
    let assistant: AssistantModel

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: Sign.image(.limit, side: 60)).padding(.bottom, 6).accessibilityHidden(true)
            Text("“\(fault.title)” can’t be shown").font(Look.titleM.font.ui).kerning(-0.55).foregroundStyle(Look.Token.ink.ui)
            ForEach(problems, id: \.self) { Text($0).font(Look.body.font.ui).lineSpacing(3).foregroundStyle(Look.Token.ink2.ui).textSelection(.enabled) }
            Text("It reloads by itself when its files change.").font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui)
            if assistant.kind != nil {
                Button("Ask \(assistant.name) to Fix It") { assistant.fix(fault) }
                    .buttonStyle(Primary()).font(Look.font(.ui, size: 12.5, weight: .semibold).ui).padding(.top, 6)
            }
            Text(([fault.name] + fault.codes).joined(separator: " · ")).font(Look.font(.code, size: 11).ui).foregroundStyle(Look.Token.ink3.ui).padding(.top, 4)
        }
        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        .padding(EdgeInsets(top: Stopped.box.insets.top, leading: Stopped.box.insets.left, bottom: Stopped.box.insets.bottom,
                            trailing: Stopped.box.insets.right)).frame(width: Stopped.box.width)
        .background { CardFace() }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Look.Token.bg.ui)
    }
}

/// Unshown's card from Look.float's shades, as Stopped draws its own: each shade cast by the card inset by its
/// spread, then the face and its ring outside it.
private struct CardFace: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Look.card, style: .continuous)
        let shades = Look.float(NSAppearance(named: scheme == .dark ? .darkAqua : .aqua) ?? NSApp.effectiveAppearance)
        ZStack {
            ForEach(shades.indices, id: \.self) { index in
                shape.fill(Look.Token.bg2.ui).padding(-shades[index].spread)
                    .shadow(color: Color(nsColor: shades[index].color), radius: shades[index].blur / 2, y: shades[index].y)
            }
            shape.fill(Look.Token.bg2.ui)
            shape.inset(by: -0.5).stroke(Look.floatRing.token.ui, lineWidth: Look.floatRing.width)
        }
    }
}

/// A toolbar button that shows itself pressed, as the mockup's .ib[aria-pressed]: the selection's fill under an ink icon.
/// Point is a `chip`: pressed, it is filled in the action's colours, as the mockup's pressed chip, its words too.
final class ToolButton: NSButton {
    var chip = false
    var pressed = false {
        didSet {
            contentTintColor = (pressed ? chip ? Look.Token.actfg : .ink : .ink2).color
            if chip {
                attributedTitle = NSAttributedString(string: title, attributes: [.font: font ?? Look.font(.ui, size: 12, weight: .medium),
                                                                                 .foregroundColor: contentTintColor ?? Look.Token.ink2.color])
                setAccessibilityValue(pressed ? "on" : "off")
            }
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if pressed {
            (chip ? Look.Token.act : .sel).color.setFill()
            // The mockup's chip is 26 high in the 28-point button.
            let radius = chip ? Look.control + 1 : Look.control
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: chip ? (bounds.height - 26) / 2 : 0), xRadius: radius, yRadius: radius).fill()
        }
        super.draw(dirtyRect)
    }
}
