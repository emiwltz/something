// The one window: a split view with the sidebar, the center and Info (the inspector, hidden at first), the window layer
// over all three, a toolbar with the sidebar toggle at the sidebar's edge, the title and file, a slot for the chip of
// waiting requests, Point (pressed while the person points at the space's parts: PointOverlay.swift; a Quick Change
// leaves its frames at work, QuickFrame.swift, and an answer without a change in a note, MarginNote.swift), Reload,
// Info and Full Screen. Its backgrounds are the identity's, opaque: no vibrancy lets the desktop through. The center
// holds the open space's web view edge to edge under the toolbar, what keeps a space from being shown, New Space or
// the templates; over a space, the glass, which holds the assistant (Glass.swift). Off the spaces the assistant is
// away: New Space has its own field. While the welcome is open over it, the window steps back under a veil that takes
// every click.
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
    private(set) var shown: NSView?
    private weak var page: NSView?
    /// The space shown in the center, when one is.
    private(set) weak var space: SpaceView?
    /// Quick Change answers without a change, by space name, waiting for their space to be shown (showNote).
    private var unread: [String: (words: String, part: Pointing.Part)] = [:]
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
    /// The welcome window while it is open over this one, and the veil between them.
    private(set) var welcoming: NSWindow?
    private(set) var veil: NSWindow?
    /// The first-launch film while it plays over this window (Film.swift).
    var film: Film?
    /// The window's undo manager: typing, and the changes of the spaces (Changes.swift).
    let undo = WindowUndo()

    /// `autosave` keeps the window's frame and the columns' widths in the app's defaults: never in a test, whose
    /// program has no bundle and would write them into the person's own preferences.
    init(library: Library, info: Info, assistant: AssistantModel, autosave: Bool) {
        (self.assistant, self.library) = (assistant, library)
        let list = SidebarView(library: library, assistant: assistant, eyes: { [unowned assistant] in assistant.eyes(of: $0) })
        let sidebar = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: list))
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
        assistant.answered = { [weak self] quick, words in self?.note(words, about: quick) }
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

    /// The columns moved: the title measures the room it has again; Info shown, a note leaves the right edge to it.
    @objc private func columnsMoved() {
        titleLine.invalidateIntrinsicContentSize()
        if !inspector.isCollapsed { space?.note?.dismiss() }
    }

    /// The window changed size, which does not always move the columns: the title measures its room again.
    func windowDidResize(_ notification: Notification) {
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

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { undo }

    func windowDidChangeOcclusionState(_ notification: Notification) { visible(window.occlusionState.contains(.visible)) }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Shell.sidebar, .sidebarTrackingSeparator, Shell.title, .flexibleSpace,
         Shell.chip, Shell.tools]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    /// The mockup's toolbar items: plain icons in `ink2`, with the words of its tooltips and the keys of the command
    /// table; the chip's slot stays hidden while empty.
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        func item(_ id: NSToolbarItem.Identifier, _ label: String, _ symbol: String, _ tip: String, _ action: Selector?, words: String? = nil) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: id)
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage()
            let button = id == Shell.point ? PressButton(image: image, target: nil, action: action) : NSButton(image: image, target: nil, action: action)
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
    /// in the toolbar.
    func show(_ space: SpaceView?, templates: Bool = false) {
        library.previewing = false
        self.space = space
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
        heading(space.title, space.space.location.lastPathComponent, space: true, point: space.pointable)
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
        inspector.isCollapsed = true
        MarginNote.show(waiting.words, about: waiting.part, title: space.title, over: space)
    }

    /// Esc typed in this window, wherever the focus is: a margin note leaves, the top thing over the page. Returns
    /// whether it did, the key then used up.
    func escape(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53, event.windowNumber == window.windowNumber, window.attachedSheet == nil, let note = space?.note else { return false }
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
        (controls[Shell.point] as? PressButton)?.pressed = on
        assistant.pointing = on
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
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Look.duration(0.5, Look.motion(library.preferences.motion))
            context.timingFunction = Look.douce.timing
            page?.animator().alphaValue = back ? 0.35 : 1
            sidebar.animator().alphaValue = back ? 0.7 : 1
            veil?.animator().alphaValue = back ? 1 : 0
        }, completionHandler: back ? nil : { [weak self] in
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
        inspector.isCollapsed = true
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

/// Point in the toolbar: pressed, it is filled in the action's colours, as the mockup's pressed chip.
final class PressButton: NSButton {
    var pressed = false {
        didSet {
            contentTintColor = pressed ? Look.Token.actfg.color : Look.Token.ink2.color
            attributedTitle = NSAttributedString(string: title, attributes: [.font: font ?? Look.font(.ui, size: 12, weight: .medium),
                                                                             .foregroundColor: contentTintColor ?? Look.Token.ink2.color])
            setAccessibilityValue(pressed ? "on" : "off")
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if pressed {
            Look.Token.act.color.setFill()
            // The mockup's chip is 26 high in the 28-point button.
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: (bounds.height - 26) / 2), xRadius: Look.control + 1, yRadius: Look.control + 1).fill()
        }
        super.draw(dirtyRect)
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
