// The one window: a split view with the sidebar, the center and Info (the inspector, hidden at first), a toolbar with
// the sidebar toggle, the open space's title and file, Reload and Info; and the menus. The center holds the open
// space's web view edge to edge under the toolbar, what keeps a space from being shown, the blank page, the templates
// or the tour, with the assistant floating over it at the bottom (not over the tour).
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
    static let reload = NSToolbarItem.Identifier("reload")
    /// Called when the person closes the window: the app closes the open space, whose page stops.
    var closed: () -> Void = {}
    /// The tour while it is shown: the blank page stays behind it until it ends.
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
        (inspector.minimumThickness, inspector.maximumThickness) = (270, 360)
        [sidebar, NSSplitViewItem(viewController: content), inspector].forEach(split.addSplitViewItem)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1240, height: 800))
        // The columns' first widths; collapsed, Info keeps its width for when it is shown.
        window.layoutIfNeeded()
        split.splitView.setPosition(232, ofDividerAt: 0)
        split.splitView.setPosition(1240 - 300, ofDividerAt: 1)
        inspector.isCollapsed = true
        window.contentMinSize = NSSize(width: 820, height: 560)
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
        show(nil)
    }

    /// Puts the assistant at the bottom of `center`, at most 640 points wide, its conversation at most 45% of the
    /// center's height (plus the capsule's): it takes its own size, its shadows inside its margin.
    static func float(_ host: Floater, in center: NSView) {
        host.sizingOptions = [.intrinsicContentSize]
        host.translatesAutoresizingMaskIntoConstraints = false
        center.addSubview(host)
        let margin = AssistantView.margin, wide = host.widthAnchor.constraint(equalToConstant: 640 + 2 * margin)
        wide.priority = .defaultHigh
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

    func windowWillClose(_ notification: Notification) { closed() }

    /// Out of full screen, an assistant ⌘J hid comes back: a window offers no other way to find it.
    func windowDidExitFullScreen(_ notification: Notification) { assistant.hidden = false }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, Shell.reload, .toggleInspector]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard id == Shell.reload else { return NSToolbarItem(itemIdentifier: id) }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = "Reload"
        item.toolTip = "Reload Space (⌘R)"
        item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")
        item.action = #selector(App.reloadSpace(_:))
        return item
    }

    /// Shows `space` in the center, or the blank page for nil (the templates for `gallery`), with its title and file
    /// in the toolbar. While the tour is shown, nil keeps it unless `endingTour`, and a space ends it.
    func show(_ space: SpaceView?, endingTour: Bool = false, gallery: Bool = false) {
        if let touring, space == nil, !endingTour { return show(touring) }
        touring = nil
        guard let space else {
            put(gallery ? Shell.hosted(GalleryView(library: library)) : Shell.hosted(BlankView(model: assistant, library: library)))
            return gallery ? bare("Templates", "Start from one, then make it yours") : bare("New Space", "")
        }
        if space.blocked.isEmpty {
            put(space.web)
        } else {
            let fault = AssistantModel.Fault(title: space.title, name: space.space.name, codes: space.blocked.map(\.code))
            put(Shell.hosted(Unshown(problems: space.blocked.map { "\($0.message) \($0.fix) (\($0.code))" }, fault: fault, assistant: assistant)))
        }
        (window.title, window.subtitle) = (space.title, space.space.location.lastPathComponent)
        window.toolbar?.items.filter { [Shell.reload, .toggleInspector].contains($0.itemIdentifier) }.forEach { $0.isHidden = false }
    }

    /// Shows the tour in the center, alone: the sidebar folded, Info and the assistant hidden.
    func show(_ tour: Tour) {
        touring = tour
        put(Shell.hosted(TourView(tour: tour, assistant: assistant, templates: library.templates)))
        floating?.isHidden = true
        split.splitViewItems[0].isCollapsed = true
        bare("something", "")
    }

    /// The toolbar's title and subtitle when no space is shown, without Reload and Info, which Info follows.
    private func bare(_ title: String, _ subtitle: String) {
        (window.title, window.subtitle) = (title, subtitle)
        window.toolbar?.items.filter { [Shell.reload, .toggleInspector].contains($0.itemIdentifier) }.forEach { $0.isHidden = true }
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
    }

    /// The app's menus, every item acting through the responder chain: the window, its split view, or the App.
    static func menu() -> NSMenu {
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            holder.submenu = NSMenu(title: title)
            items.forEach { holder.submenu?.addItem($0) }
            return holder
        }
        func item(_ title: String, _ action: String?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let made = NSMenuItem(title: title, action: action.map { Selector($0) }, keyEquivalent: key)
            made.keyEquivalentModifierMask = modifiers
            return made
        }
        let main = NSMenu()
        main.addItem(submenu("something", [
            item("About something", "orderFrontStandardAboutPanel:"), .separator(),
            item("Hide something", "hide:", "h"), item("Hide Others", "hideOtherApplications:", "h", [.command, .option]),
            item("Show All", "unhideAllApplications:"), .separator(), item("Quit something", "terminate:", "q"),
        ]))
        main.addItem(submenu("File", [
            item("New Space", "newSpace:", "n"), item("Templates", "showTemplates:", "t", [.command, .shift]), .separator(),
            item("Import Space…", "importSpace:", "i", [.command, .shift]), item("Export Space…", "exportSpace:", "e", [.command, .shift]),
            item("Show in Finder", "showInFinder:", "r", [.command, .option]), item("Move to Trash…", "moveToTrash:"), .separator(),
            item("Close Window", "performClose:", "w"),
        ]))
        main.addItem(submenu("Edit", [
            item("Undo", "undo:", "z"), item("Redo", "redo:", "z", [.command, .shift]), .separator(),
            item("Cut", "cut:", "x"), item("Copy", "copy:", "c"), item("Paste", "paste:", "v"), item("Select All", "selectAll:", "a"),
        ]))
        main.addItem(submenu("View", [
            item("Show Sidebar", "toggleSidebar:", "s", [.command, .control]), item("Show Info", "toggleInspector:", "i", [.command, .option]),
            item("Show Conversation", "toggleConversation:", "j"), item("Reload Space", "reloadSpace:", "r"), .separator(),
            item("Enter Full Screen", "toggleFullScreen:", "f", [.command, .control]),
        ]))
        let builders = submenu("Build With", [])
        builders.submenu?.delegate = NSApp.delegate as? NSMenuDelegate
        main.addItem(submenu("Assistant", [
            item("Ask…", "askAssistant:", "k"), item("Stop", "stopAssistant:", "."),
            item("New Conversation", "newConversation:", "k", [.command, .shift]), .separator(), builders,
        ]))
        let windows = submenu("Window", [item("Minimize", "performMiniaturize:", "m"), item("Zoom", "performZoom:"), .separator(),
                                         item("Bring All to Front", "arrangeInFront:")])
        main.addItem(windows)
        NSApp.windowsMenu = windows.submenu
        let help = submenu("Help", [item("Welcome Tour", "showTour:"), item("What something Does and Doesn't", "showPromise:"), .separator(),
                                    item("something Help", "openHelp:"), item("Guide for Coding Agents", "showGuide:")])
        main.addItem(help)
        NSApp.helpMenu = help.submenu
        return main
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
