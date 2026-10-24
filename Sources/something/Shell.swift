// The one window: a split view with the sidebar, the center and Info (the inspector, hidden at first), the window layer
// over all three, a toolbar with the sidebar toggle at the sidebar's edge, the title and file, a slot for the chip of
// waiting requests, Point, Reload, Info and Full Screen. Its backgrounds are the identity's, opaque: no vibrancy lets
// the desktop through. The center holds the open space's web view edge to edge under the toolbar, what keeps a space
// from being shown, the blank page, the templates or the tour, with the assistant floating over it at the bottom (not
// over the tour).
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
    /// What the center shows, and the assistant over it.
    private var shown: NSView?
    private(set) var floating: NSView?
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
        let floating = Floater(rootView: AssistantView(model: assistant))
        Shell.float(floating, in: center)
        self.floating = floating
        // The toolbar's lower edge, over the center only: the sidebar runs up to the window's top.
        let edge = NSBox()
        (edge.boxType, edge.borderWidth, edge.fillColor, edge.translatesAutoresizingMaskIntoConstraints) = (.custom, 0, Look.Token.line.color, false)
        center.addSubview(edge)
        NSLayoutConstraint.activate([edge.heightAnchor.constraint(equalToConstant: 1), edge.leadingAnchor.constraint(equalTo: center.leadingAnchor),
                                     edge.trailingAnchor.constraint(equalTo: center.trailingAnchor),
                                     edge.bottomAnchor.constraint(equalTo: center.safeAreaLayoutGuide.topAnchor)])
        show(nil)
    }

    /// Puts the assistant at the bottom of `center`, at most 640 points wide, its conversation at most 45% of the
    /// center's height (plus the capsule's): it takes its own size, its shadows inside its margin.
    static func float(_ host: Floater, in center: NSView) {
        host.sizingOptions = [.intrinsicContentSize]
        host.translatesAutoresizingMaskIntoConstraints = false
        center.addSubview(host)
        let margin = AssistantView.margin, wide = host.widthAnchor.constraint(equalToConstant: 640 + 2 * margin)
        // Below the window's wish to keep its size (500): the assistant narrows, the window keeps its 640-point minimum.
        wide.priority = .defaultLow
        host.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        NSLayoutConstraint.activate([wide, host.widthAnchor.constraint(lessThanOrEqualTo: center.widthAnchor, constant: 2 * margin - AssistantView.sides),
                                     host.centerXAnchor.constraint(equalTo: center.centerXAnchor),
                                     host.bottomAnchor.constraint(equalTo: center.bottomAnchor),
                                     host.heightAnchor.constraint(lessThanOrEqualTo: center.heightAnchor, multiplier: 0.45, constant: 90 + 2 * margin)])
    }

    /// ⌘J: shows or hides the conversation. In full screen it also hides the whole assistant, for a space alone.
    @objc func toggleConversation(_ sender: Any?) {
        if window.styleMask.contains(.fullScreen), assistant.drawer || assistant.hidden {
            assistant.drawer = false
            assistant.hidden.toggle()
        } else {
            assistant.drawer.toggle()
            assistant.hidden = false
        }
    }

    func windowWillClose(_ notification: Notification) {
        visible(false)
        closed()
    }

    /// The sidebar changed width: the title measures the room it has again.
    @objc private func columnsMoved() { titleLine.invalidateIntrinsicContentSize() }

    /// The window changed size, which does not always move the columns: the title measures its room again.
    func windowDidResize(_ notification: Notification) { titleLine.invalidateIntrinsicContentSize() }

    func windowDidChangeOcclusionState(_ notification: Notification) { visible(window.occlusionState.contains(.visible)) }

    /// Out of full screen, an assistant ⌘J hid comes back: a window offers no other way to find it.
    func windowDidExitFullScreen(_ notification: Notification) { assistant.hidden = false }

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
            (item.view, item.isBordered, item.isHidden) = (NSView(), false, true)
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
    /// space when none is open.
    func heading(_ title: String, _ file: String, space: Bool) {
        (window.title, window.subtitle) = (title, file)
        let line = NSMutableAttributedString(string: title, attributes: [.font: Look.font(.ui, size: 13.5, weight: .semibold),
                                                                         .foregroundColor: Look.Token.ink.color, .kern: -0.135])
        if !file.isEmpty {
            line.append(NSAttributedString(string: "  " + file, attributes: [.font: Look.font(.ui, size: 11.5),
                                                                              .foregroundColor: Look.Token.ink3.color]))
        }
        titleLine.line = line
        titleLine.setAccessibilityLabel(file.isEmpty ? title : "\(title), \(file)")
        // Point stays greyed until its slice gives it an action.
        toolbarItems.filter { Shell.onSpace.contains($0.itemIdentifier) }.forEach {
            let control = controls[$0.itemIdentifier]
            $0.isEnabled = space && control?.action != nil
            control?.isEnabled = $0.isEnabled
        }
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
            put(templates ? Shell.hosted(GalleryView(library: library)) : Shell.hosted(BlankView(model: assistant, library: library)))
            return templates ? bare("Templates", "Start from one, then make it yours") : bare("New Space", "")
        }
        if space.blocked.isEmpty {
            put(space.web)
        } else {
            let fault = AssistantModel.Fault(title: space.title, name: space.space.name, codes: space.blocked.map(\.code))
            put(Shell.hosted(Unshown(problems: space.blocked.map { "\($0.message) \($0.fix) (\($0.code))" }, fault: fault, assistant: assistant)))
        }
        heading(space.title, space.space.location.lastPathComponent, space: true)
    }

    /// Shows the tour in the center, alone: the sidebar folded, Info and the assistant hidden.
    func show(_ tour: Tour) {
        touring = tour
        put(Shell.hosted(TourView(tour: tour, assistant: assistant, templates: library.templates)))
        floating?.isHidden = true
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
        floating?.isHidden = false
        shown.translatesAutoresizingMaskIntoConstraints = false
        center.addSubview(shown, positioned: .below, relativeTo: floating)
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

/// The assistant's hosting view. It takes only the clicks on what it draws: those beside its pieces, between them and
/// in its margin, where the shadows fall, reach the space under it.
final class Floater: NSHostingView<AssistantView> {
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let superview else { return }
        superview.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(resized), name: NSView.frameDidChangeNotification, object: superview)
        resized()
    }

    /// The center changed: the assistant is told the width it now has.
    @objc private func resized() {
        let room = min(640, max(0, (superview?.bounds.width ?? 0) - AssistantView.sides))
        if rootView.model.room != room { rootView.model.room = room }
    }

    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        if rootView.model.floating != size.height { rootView.model.floating = size.height }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let inside = convert(point, from: superview)
        // SwiftUI's frames start at the top-left corner, like this view's own when it is flipped.
        let flipped = isFlipped ? inside : NSPoint(x: inside.x, y: bounds.height - inside.y)
        return rootView.model.drawn.contains { $0.contains(flipped) } ? super.hitTest(point) : nil
    }
}
