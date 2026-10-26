// The one window: a split view with the sidebar, the center and Info (the inspector, hidden at first), the window layer
// over all three, a toolbar with the sidebar toggle at the sidebar's edge, the title and file, a slot for the chip of
// waiting requests, Point (pressed while the person points at the space's parts: PointOverlay.swift; a Quick Change
// leaves its frames at work, QuickFrame.swift, and an answer without a change in a note, MarginNote.swift), Reload,
// Info and Full Screen. Its backgrounds are the identity's, opaque: no vibrancy lets the desktop through. The center
// holds the open space's web view edge to edge under the toolbar, what keeps a space from being shown, New Space or
// the templates; over a space, the glass, which holds the assistant (Glass.swift). Off the spaces the assistant is
// away: New Space has its own field. While the welcome is open over it, the window steps back under a veil that takes
// every click.
// In full screen the space is alone: the system hides the toolbar and the menu bar until the pointer reaches the top,
// the sidebar steps aside and the space starts at the screen's top; ⌃⌘S lays the sidebar over it (SidebarOver).
// A window narrower than 860 points has the rail in place of its sidebar (Rail.swift), until it is 880 wide again, so
// that a window resized about the line does not flicker between the two: ⌃⌘S lays the whole sidebar over the space
// there too, the toolbar's own toggle goes (the rail has one), the title drops the file and the chip its words.
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
    /// The welcome window while it is open over this one, and the veil between them.
    private(set) var welcoming: NSWindow?
    private(set) var veil: NSWindow?
    /// The first-launch film while it plays over this window (Film.swift).
    var film: Film?
    /// The window's undo manager: typing, and the changes of the spaces (Changes.swift).
    let undo = WindowUndo()
    /// Whether the window is in full screen, or entering it; the sidebar's own state before, given back after.
    private(set) var full = false
    private var sideHidden = false
    /// What holds the top of what the center shows: the toolbar's lower edge, or in full screen the window's top.
    private var top: NSLayoutConstraint?
    /// The toolbar's lower edge, over the center only.
    private let edge = NSBox()
    /// Whether the sidebar column is the rail; the column's own state before, given back after.
    private(set) var rail = false
    private var sideBefore: (hidden: Bool, width: CGFloat) = (false, 236)
    /// Whether the columns' widths are kept in the defaults (`init`'s `autosave`), given back to the split view when
    /// the rail goes.
    private let autosave: Bool
    /// Below `narrow` points the window takes the rail; it gives it up at `narrow + hysteresis`.
    static let narrow: CGFloat = 860, hysteresis: CGFloat = 20

    /// `autosave` keeps the window's frame and the columns' widths in the app's defaults: never in a test, whose
    /// program has no bundle and would write them into the person's own preferences.
    init(library: Library, info: Info, assistant: AssistantModel, autosave: Bool) {
        (self.assistant, self.library, self.info, self.autosave) = (assistant, library, info, autosave)
        let list = SidebarView(library: library, assistant: assistant, eyes: { [unowned assistant] in assistant.eyes(of: $0) })
        let sidebar = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: list))
        (sidebar.minimumThickness, sidebar.maximumThickness) = (190, 320)
        let content = NSViewController()
        content.view = center
        inspector = NSSplitViewItem(inspectorWithViewController: InfoController(rootView: InspectorView(info: info, library: library, assistant: assistant)))
        (inspector.minimumThickness, inspector.maximumThickness) = (320, 320)
        // The toolbar stays one band across the window: the panel begins under it, as the mockup draws it.
        inspector.allowsFullHeightLayout = false
        [sidebar, NSSplitViewItem(viewController: content), inspector].forEach(split.addSplitViewItem)
        window = MainWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        layer = WindowLayer(over: split.view)
        glass = Glass(over: center, model: assistant)
        super.init()
        split.over = { [unowned self] in sidebarOver() }
        split.laid = { [unowned self] in full || rail ? SidebarOver.shown(in: layer) != nil : nil }
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
        // Its own identifier: toolbars of one identifier share their items, and the rail takes some away from this one.
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
        // A frame kept narrow from the last time starts with the rail.
        fit()
        assistant.answered = { [weak self] quick, words in self?.note(words, about: quick) }
        info.close = { [weak self] in self?.showInfo(false) }
        info.showHistory = { [weak self] in self?.showHistory() }
        library.renamed = { [weak self] name in if let space = self?.space, space.space.name == name { self?.heading(space) } }
        library.told = { [weak self] words in self?.toast(words, quiet: true) }
        glass.motion = { [weak library] in library?.preferences.motion ?? .calm }
        glass.page = { [weak self] in self?.page }
        // One place for the sticker over every space, kept for the next start unless the person asked otherwise.
        let preferences = library.preferences
        glass.spot = preferences.rememberSticker ? preferences.sticker : nil
        glass.moved = { [weak preferences] spot in if preferences?.rememberSticker == true { preferences?.sticker = spot } }
        // The toolbar's lower edge, over the center only: the sidebar runs up to the window's top.
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

    /// The columns moved: the title measures the room it has again; Info shown, a note leaves the right edge to it.
    @objc private func columnsMoved() {
        titleLine.invalidateIntrinsicContentSize()
        if !inspector.isCollapsed { space?.note?.dismiss() }
    }

    /// The window changed size, which does not always move the columns: the title measures its room again.
    func windowDidResize(_ notification: Notification) {
        fit()
        titleLine.invalidateIntrinsicContentSize()
        veil?.setFrame(window.frame, display: true)
        film?.cover.setFrame(window.frame, display: true)
        welcoming?.setFrame(Welcome.place(over: window.frame), display: true)
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

    /// Lays the window out for full screen (`on`) or back: the sidebar steps aside and comes back as it was, the space
    /// starts at the window's top, which the hidden toolbar no longer holds, and the Full Screen button turns to leave
    /// it. Pinned to the top rather than to the safe area, the page does not move when the toolbar comes down over it.
    func fullScreen(_ on: Bool) {
        guard on != full else { return }
        if on { railed(false) }
        full = on
        _ = SidebarOver.close(in: layer)
        let side = split.splitViewItems[0]
        if on { sideHidden = side.isCollapsed }
        side.isCollapsed = on || sideHidden
        top?.isActive = false
        top = shown.map(pin)
        top?.isActive = true
        edge.isHidden = on
        controls[Shell.full]?.image = NSImage(systemSymbolName: on ? "arrow.down.right.and.arrow.up.left" : "viewfinder",
                                              accessibilityDescription: on ? "Exit Full Screen" : "Full Screen")
        if !on { fit() }
    }

    /// Whether a window `width` points wide has the rail, `now` being whether it has it: below 860 it takes it, and
    /// keeps it until 880.
    static func rail(_ width: CGFloat, now: Bool) -> Bool { width < narrow + (now ? hysteresis : 0) }

    /// Takes the rail or gives it up for the window's width; never in full screen, where the sidebar steps aside.
    func fit() {
        railed(!full && Shell.rail(window.frame.width, now: rail))
    }

    /// Turns the sidebar column into the rail (`on`), shown whatever the column was, or back into the sidebar as it
    /// was before; the toolbar follows. The split view stops keeping its widths meanwhile: the rail's 64 points must
    /// never become the person's saved width, nor its shown column a sidebar they had hidden.
    private func railed(_ on: Bool) {
        guard on != rail else { return }
        rail = on
        _ = SidebarOver.close(in: layer)
        let side = split.splitViewItems[0]
        library.sidebar.cursor = nil
        library.sidebar.rail = on
        if on {
            // At launch the column may not be laid out yet: a width under the sidebar's least is not the person's.
            let width = side.viewController.view.frame.width
            sideBefore = (side.isCollapsed, side.isCollapsed || width < 190 ? sideBefore.width : width)
            split.splitView.autosaveName = nil
            (side.minimumThickness, side.maximumThickness, side.canCollapse) = (Rail.width, Rail.width, false)
            side.isCollapsed = false
            split.splitView.setPosition(Rail.width, ofDividerAt: 0)
        } else {
            (side.minimumThickness, side.maximumThickness, side.canCollapse) = (190, 320, true)
            split.splitView.setPosition(sideBefore.width, ofDividerAt: 0)
            side.isCollapsed = sideBefore.hidden
            split.splitView.autosaveName = autosave ? "main" : nil
        }
        // The toggle goes with the separator that follows the sidebar's edge, removed: even hidden, the separator would
        // keep the title well past the lights.
        if let toolbar = window.toolbar {
            if on {
                for id in Shell.head { if let at = toolbar.items.firstIndex(where: { $0.itemIdentifier == id }) { toolbar.removeItem(at: at) } }
            } else { Shell.head.reversed().forEach { toolbar.insertItem(withItemIdentifier: $0, at: 0) } }
        }
        (titleLine.bare, chip.compact) = (on, on)
    }

    /// ⌃⌘S in full screen or beside the rail: lays the sidebar over the space, or takes it away; beside the rail, under
    /// the toolbar, which would draw the title over it. Returns false elsewhere, where the sidebar column shows or
    /// hides as usual.
    private func sidebarOver() -> Bool {
        guard full || rail else { return false }
        let under = full ? 0 : window.frame.height - window.contentLayoutRect.maxY
        // The column's own eyes, so that both lists always say the same.
        guard let column = (split.splitViewItems[0].viewController as? NSHostingController<SidebarView>)?.rootView else { return true }
        _ = SidebarOver.toggle(in: layer, motion: library.preferences.motion) {
            SidebarOver(SidebarView(library: library, assistant: assistant, eyes: column.eyes, column: false), under: under)
        }
        return true
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { undo }

    func windowDidChangeOcclusionState(_ notification: Notification) { visible(window.occlusionState.contains(.visible)) }

    /// The toolbar's items over the sidebar column, which the rail has not.
    static let head: [NSToolbarItem.Identifier] = [.flexibleSpace, Shell.sidebar, .sidebarTrackingSeparator]

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Shell.head + [Shell.title, .flexibleSpace, Shell.chip, Shell.tools]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    /// The mockup's toolbar items: plain icons in `ink2`, with the words of its tooltips and the keys of the command
    /// table; the chip's slot stays hidden while empty.
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        func item(_ id: NSToolbarItem.Identifier, _ label: String, _ symbol: String, _ tip: String, _ action: Selector?, words: String? = nil) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: id)
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage()
            let button = ToolButton(image: image, target: nil, action: action)
            (button.chip, button.isBordered, button.contentTintColor, button.toolTip) = (id == Shell.point, false, Look.Token.ink2.color, tip)
            // The mockup's icons are thin strokes, Point's target a size below the others'.
            button.symbolConfiguration = .init(pointSize: id == Shell.point ? 12 : 13, weight: .regular)
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
            // The mockup draws Reload's arrow smaller and Full Screen's corners heavier than the other icons.
            buttons[1].symbolConfiguration = .init(pointSize: 11.5, weight: .semibold)
            buttons[3].symbolConfiguration = .init(pointSize: 13, weight: .bold)
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
        titleLine.titleLength = line.length
        if !file.isEmpty {
            line.append(NSAttributedString(string: "  " + file, attributes: [.font: Look.font(.ui, size: 11.5),
                                                                              .foregroundColor: Look.Token.ink3.color]))
        }
        titleLine.line = line
        titleLine.setAccessibilityLabel(file.isEmpty ? title : "\(title), \(file)")
        // Point is greyed while the page is stopped or cannot be shown: nothing to point at.
        assistant.pointable = space && point
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
        (glass.mine, info.waiting) = (mine, mine)
        guard chip.count != count else { return }
        chip.count = count
        window.toolbar?.items.first { $0.itemIdentifier == Shell.chip }?.isHidden = count == 0
        titleLine.invalidateIntrinsicContentSize()
    }

    /// Shows `words` at the bottom of the center for a moment; see Toast.
    @discardableResult
    func toast(_ words: String, action: Toast.Action? = nil, quiet: Bool = false, seconds: TimeInterval = 3.2) -> Toast {
        Toast.show(words, action: action, quiet: quiet, seconds: seconds, motion: library.preferences.motion, in: layer, under: center,
                   clearOf: glass.grown == true && !glass.isHidden ? glass.card : nil)
    }

    /// Shows `space` in the center, or the blank page for nil (the templates with `templates`), with its title and file
    /// in the toolbar.
    func show(_ space: SpaceView?, templates: Bool = false) {
        library.previewing = false
        self.space = space
        // A space picked in the sidebar laid over the page takes its place.
        _ = SidebarOver.close(in: layer)
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
        } else {
            let fault = AssistantModel.Fault(title: space.title, name: space.space.name, codes: space.blocked.map(\.code))
            put(Shell.hosted(Unshown(problems: space.blocked.map { "\($0.message) \($0.fix) (\($0.code))" }, fault: fault, assistant: assistant)))
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
        guard let note = space.note else { return false }
        note.dismiss()
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
        assistant.pointing = on
        space.flatMap(Comments.of)?.changed()
    }

    /// Heads the toolbar with `space`: the name the person gave it in the sidebar, else its declared title.
    private func heading(_ space: SpaceView) {
        heading(library.entry(space.space.name)?.title ?? space.title, space.space.location.lastPathComponent, space: true, point: space.pointable)
    }

    /// Opens `tour`'s welcome over this window, where Welcome.place puts it, and steps this window back as the mockup
    /// dims it: the center blurred and faded, the sidebar faded, and over it all, toolbar included, a veil of the
    /// background that takes every click. The welcome takes the keys; the menus grey this window's commands (App).
    /// `onScreen` false leaves both windows off the screen, as a test's are. Returns the welcome's window.
    @discardableResult
    func welcome(_ tour: Tour, onScreen: Bool = true) -> NSWindow {
        welcomed()
        let welcome = Welcome.window(tour, assistant: assistant, motion: library.preferences.motion)
        welcome.setFrame(Welcome.place(over: window.frame), display: false)
        let veil = Cover(over: window.frame)
        veil.contentView = Veil()
        (welcoming, self.veil) = (welcome, veil)
        stepBack(true)
        guard onScreen else { return welcome }
        window.addChildWindow(veil, ordered: .above)
        veil.addChildWindow(welcome, ordered: .above)
        welcome.makeKeyAndOrderFront(nil)
        return welcome
    }

    /// Closes the welcome and its veil, and brings this window forward again, its keys back.
    func welcomed() {
        guard let welcome = welcoming else { return }
        welcoming = nil
        veil?.removeChildWindow(welcome)
        welcome.close()
        stepBack(false)
        if window.isVisible { window.makeKey() }
    }

    /// The welcome ended: Make Your First Space opens New Space; skipped, the window stays where it was and says so.
    /// Either way, on New Space its field takes the keys, as the mockup's skip focuses it. Returns the toast, if any.
    @discardableResult
    func welcomed(skipped: Bool) -> Toast? {
        welcomed()
        if !skipped { library.select(.newSpace) }
        if library.selection == .newSpace { assistant.focus() }
        return skipped ? toast("Skipped · everything is in Settings when you want it", quiet: true) : nil
    }

    /// Steps the window back (`back`) or forward, in half a second, at once under Reduced motion. Only the page is
    /// blurred and faded, as the mockup filters its view: the glass, the sticker and its badge stay sharp under the veil.
    private func stepBack(_ back: Bool) {
        let page = shown, sidebar = split.splitViewItems[0].viewController.view, veil = veil
        if back {
            Self.blur(page, true)
            veil?.alphaValue = 0
        }
        Look.animate(Look.duration(0.5, Look.motion(library.preferences.motion)), Look.douce, {
            page?.moving.alphaValue = back ? 0.35 : 1
            sidebar.moving.alphaValue = back ? 0.7 : 1
            veil?.moving.alphaValue = back ? 1 : 0
        }, done: back ? nil : { [weak self] in
            // The blur goes once the page is back in full, so that it never snaps off a page still faded.
            if self?.welcoming == nil { Self.blur(page, false) }
            guard let veil else { return }
            self?.window.removeChildWindow(veil)
            veil.orderOut(nil)
            if self?.veil === veil { self?.veil = nil }
        })
    }

    /// Blurs and desaturates `view` as the welcome steps the window back (`on`), or takes both off, and with them the
    /// Core Image layer that a web view would otherwise keep for the rest of the session.
    private static func blur(_ view: NSView?, _ on: Bool) {
        guard let view else { return }
        view.wantsLayer = true
        view.layerUsesCoreImageFilters = on
        view.contentFilters = on ? [CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: 7]),
                                    CIFilter(name: "CIColorControls", parameters: [kCIInputSaturationKey: 0.6])].compactMap { $0 } : []
    }

    /// The toolbar's title and subtitle when no space is shown, its space's items greyed, and Info closed.
    private func bare(_ title: String, _ subtitle: String) {
        heading(title, subtitle, space: false)
        showInfo(false)
    }

    /// Puts `shown` in the center in place of what was there, under the assistant.
    private func put(_ shown: NSView) {
        self.shown?.removeFromSuperview()
        // While the welcome is open, the page put in its place steps back too, and the one taken away comes back whole.
        if welcoming != nil {
            Self.blur(self.shown, false)
            self.shown?.alphaValue = 1
            Self.blur(shown, true)
            shown.alphaValue = 0.35
        }
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

    /// The top of `shown`: under the toolbar, never behind it; in full screen, the window's top.
    private func pin(_ shown: NSView) -> NSLayoutConstraint {
        shown.topAnchor.constraint(equalTo: full ? center.topAnchor : center.safeAreaLayoutGuide.topAnchor)
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

/// The split view of the window: ⌃⌘S and the toolbar's toggle ask `over` first, which lays the sidebar over the space
/// in full screen or beside the rail instead of showing its column.
final class Split: NSSplitViewController {
    var over: () -> Bool = { false }
    /// Whether the sidebar is laid over the space, nil where it is not laid over but shown as a column.
    var laid: () -> Bool? = { nil }
    override func toggleSidebar(_ sender: Any?) {
        if !over() { super.toggleSidebar(sender) }
    }
    /// ⌃⌘S stays on beside the rail, whose column cannot collapse, and says what it does to the sidebar laid over.
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard item.action == #selector(toggleSidebar(_:)), let laid = laid() else { return super.validateUserInterfaceItem(item) }
        (item as? NSMenuItem)?.title = laid ? "Hide Sidebar" : "Show Sidebar"
        return true
    }
}

/// The main window. NSWindow answers toggleSidebar: itself, without the split view's override, whenever nothing in the
/// split view has the focus: ⌃⌘S and the rail's toggle would then never lay the sidebar over the space.
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

/// A borderless, clear window laid over the whole of the main window, toolbar and lights included: the welcome's veil,
/// which never takes the keys, and the first-launch film's (Film.swift), which takes them while it plays.
final class Cover: NSWindow {
    private var keys = false
    convenience init(over frame: NSRect, keys: Bool = false) {
        self.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: true)
        (self.keys, isOpaque, backgroundColor, hasShadow, isReleasedWhenClosed) = (keys, false, .clear, false, false)
    }
    override var canBecomeKey: Bool { keys }
}

/// The veil over the main window while the welcome is open: the background at 42%, at the window's corners, taking
/// every click so that nothing behind the welcome can be used.
final class Veil: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Look.Token.bg.color.withAlphaComponent(0.42).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: Look.window, yRadius: Look.window).fill()
    }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The toolbar's title: drawn here, since a text field in a toolbar is greyed while its window is not the key one. It
/// gives way first when the window narrows, the file cut with an ellipsis, so that the tools never leave the toolbar.
final class TitleLine: NSView {
    /// 18 points from the sidebar's edge, as the mockup's toolbar starts; the toolbar gives the other 8.
    static let indent: CGFloat = 10
    var line = NSAttributedString() {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// How much of `line` is the title: beside the rail, `bare`, only the title is drawn.
    var titleLength = 0
    var bare = false {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// What is drawn: the line, or its title alone.
    var shown: NSAttributedString { bare && titleLength < line.length ? line.attributedSubstring(from: NSRange(location: 0, length: titleLength)) : line }

    /// What the tools need on its right, with the gap before them: the toolbar would rather move them to its overflow
    /// menu than narrow a view that asks for more.
    var reserve: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: NSSize {
        let whole = ceil(shown.size().width) + TitleLine.indent
        let room = window.map { $0.frame.width - convert(NSPoint.zero, to: nil).x - reserve } ?? whole
        return NSSize(width: max(TitleLine.indent, min(whole, room)), height: ceil(shown.size().height))
    }
    override func draw(_ dirtyRect: NSRect) {
        let cut = NSMutableAttributedString(attributedString: shown), style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        cut.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: cut.length))
        cut.draw(in: NSRect(x: TitleLine.indent, y: 0, width: bounds.width - TitleLine.indent, height: bounds.height))
    }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
}

/// The toolbar's chip: the eyes of a request, how many wait and "wait for you", in a pill with a hairline and no
/// shadow, hidden at 0. One meaning only, the count of every request, as the Dock's; a click goes to the request, or,
/// with several, opens the menu of the assistants by state (`goes`).
final class WaitingChip: NSButton {
    /// Where a click goes: a space to open, the request panel, or the assistants' menu.
    enum Go { case space(String), request, menu(NSMenu) }

    /// The states the menu lists, in its order: who waits, who works, who is done, stopped or unknown. Ready and
    /// asleep are left out: nothing to look at.
    static let listed: [Sign.State] = [.wait, .think, .done, .limit, .unknown]

    /// Where a click goes, `spaces` being each waiting request's space (nil for none or one no longer listed): one
    /// request opens its space, or shows the panel when it is `open` or has none; several open the menu of
    /// `assistants` (id, title, state) in `listed`, by state then in the sidebar's order, or the panel when none is.
    static func goes(_ spaces: [String?], open: String?, assistants: [(String, String, Sign.State)]) -> Go {
        if spaces.count == 1 { return spaces[0].map { $0 == open ? .request : .space($0) } ?? .request }
        let rows = listed.flatMap { state in assistants.filter { $0.2 == state } }
        guard !rows.isEmpty else { return .request }
        let menu = NSMenu(title: "Assistants"), tab = NSMenuItem.tab(rows.map { ($0.1, $0.2) })
        menu.addItem(.sectionHeader(title: "Assistants"))
        rows.forEach { menu.addItem(.space($0.0, $0.1, $0.2, tab: tab)) }
        return .menu(menu)
    }

    /// Where the assistants' menu opens: just under the chip in its window, or at the pointer when the chip is in no
    /// window (the toolbar sent it to its overflow menu).
    var menuPlace: (NSPoint, NSView?) {
        window == nil ? (NSEvent.mouseLocation, nil) : (NSPoint(x: 0, y: isFlipped ? bounds.height + 4 : -4), self)
    }

    var count = 0 {
        didSet {
            setAccessibilityLabel("\(count) \(said)")
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    /// Beside the rail, the eyes and the count alone; the label still says the words.
    var compact = false {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    private var said: String { count == 1 ? "waits for you" : "wait for you" }
    /// The count, then the words unless `compact`, as drawn.
    private var parts: [NSAttributedString] {
        ([("\(count)", NSFont.Weight.semibold)] + (compact ? [] : [(said, .medium)])).map { words, weight in
            NSAttributedString(string: words, attributes: [.font: Look.font(.ui, size: 12, weight: weight), .foregroundColor: Look.Token.ink.color])
        }
    }

    init() {
        super.init(frame: .zero)
        (isBordered, title, target, action) = (false, "", nil, #selector(App.chipClicked(_:)))
        toolTip = Keys.tooltip("showreq", "Show Request")
    }
    required init?(coder: NSCoder) { nil }

    // The mockup's .wn-chip: 26 high, 8 before the eyes, 6 between the pieces, 10 after the words; compact, 7 and 9.
    override var intrinsicContentSize: NSSize {
        NSSize(width: lead + 16 + parts.reduce(0) { $0 + 6 + ceil($1.size().width) } + (compact ? 9 : 10), height: 26)
    }
    private var lead: CGFloat { compact ? 7 : 8 }

    override func draw(_ dirtyRect: NSRect) {
        let pill = bounds.insetBy(dx: 0.5, dy: (bounds.height - 26) / 2 + 0.5), path = NSBezierPath(roundedRect: pill, xRadius: 12.5, yRadius: 12.5)
        Look.Token.bg2.color.setFill()
        path.fill()
        Look.Token.line2.color.setStroke()
        path.lineWidth = 1
        path.stroke()
        Sign.miniEyes(.wait, template: false).draw(in: NSRect(x: lead, y: bounds.midY - 5, width: 16, height: 10))
        var x: CGFloat = lead + 16
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
