// The sidebar, one host at every size: a card of glass over the columns, in the Shell's `chrome` layer, 250 points wide
// and 10 from the window's edges. In a space the page takes the whole window, and the sidebar comes over it: the pointer
// resting on the left edge (PageFull.swift's strip), a click there, or ⌃⌘S. It leaves 0.32 s after the pointer, with Esc,
// with ⌃⌘S again or with a click on the page, never during a menu, a rename, a sheet or an Undo toast. On New Space and
// Templates it stays open beside the page until a build starts, and the pin keeps it there everywhere: the center then
// starts to its right, so what follows the center's width (the toast, the sticker, the sheets) needs nothing else. Docked or floating it is the same view. Where there is no room, either full screen or a window under
// 860 points, it floats and the pin hides. The page behind is blurred by the window server, then tinted; at night the
// tint lies over 50 % black, which darkens a light page first. No picture can show that blur (cacheDisplay never draws
// a visual effect), so it is checked by hand.
import AppKit
import SwiftUI

/// Where the sidebar is, as a pure value: the mockup's YW, one bit each. A pinned and a floating sidebar differ by one.
struct DrawerState: Equatable {
    /// The pin, the preference.
    var pinned = false
    /// Pinned, but ⌃⌘S hid it for a while.
    var away = false
    /// ⌃⌘S hid it on New Space or Templates.
    var off = false
    /// It lies over the page: the edge, ⌃⌘S or the toolbar's button.
    var peek = false
    /// Whether the window has room beside the page: neither full screen, nor narrow.
    var room = true
    /// Whether a space is shown, and whether New Space shows a build, which it leaves the whole window.
    var page = false, building = false

    var held: Bool { !page && !off && !building }
    /// Whether it lies beside the page, the center moved aside for it.
    var dock: Bool { room && (pinned && !away || held) }
    var shown: Bool { dock || peek }
    /// What the pin shows as pressed.
    var kept: Bool { pinned && !away }

    /// ⌃⌘S and the toolbar's button: shown, it hides; hidden, it comes back as it was, pinned or floating.
    mutating func toggle() {
        if dock {
            if pinned { away = true }
            if !page { off = true }
            peek = false
        } else if room, pinned || (!page && !building) {
            (away, off, peek) = (false, false, false)
        } else {
            peek.toggle()
        }
    }

    /// The pin: once off, the sidebar floats and leaves with a pointer that is `inside` it.
    mutating func pin(inside: Bool) {
        let on = !kept
        (pinned, away) = (on, false)
        if on, room { peek = false } else if !on { peek = inside && !held }
    }

    /// Settings' Sidebar row, the same bit.
    mutating func set(pinned on: Bool) { (pinned, away, peek) = (on, false, false) }

    /// New Space's build began or ended: pressing Build sends the sidebar away.
    mutating func build(_ on: Bool) {
        if on, !building { peek = false }
        building = on
    }

    /// The window moved to a space (`now`) or off the spaces. The sidebar that was held stays under the pointer and
    /// leaves with it; one over a page leaves unless the pointer is on it; a space being built takes the whole window.
    mutating func viewed(page now: Bool, inside: Bool, writing: Bool) {
        let held = !page
        (page, off) = (now, false)
        if !now || writing { peek = false } else if held, inside, !dock { peek = true } else if !inside { peek = false }
    }
}

/// The card, the view that casts its shadow, as wide as the window and letting through every click off the card. A
/// local watch sends a floating sidebar away at a click elsewhere in the window, which still reaches what was clicked.
final class Drawer: NSView {
    static var width: CGFloat { 250 * Look.scale.size.factor }
    static let margin: CGFloat = 10, radius = Look.card + 4
    /// The room it takes docked: the card and a margin on each side.
    static var column: CGFloat { width + 2 * margin }

    private(set) var state = DrawerState()
    /// The list.
    let host: NSHostingView<SidebarView>
    let blur = NSVisualEffectView()
    private var place: NSLayoutConstraint!, wide: NSLayoutConstraint!
    /// The card's top under the toolbar, or in either full screen 10 points from the window's top.
    private var tops: (under: NSLayoutConstraint, top: NSLayoutConstraint)!
    /// Whether the pointer is on it or within 10 points of it.
    private(set) var inside = false
    private var leaving: Timer?
    private var menuOpen = false
    private var clicks: Any?
    /// What had the keys when it took them.
    private weak var before: NSResponder?
    /// What keeps it from leaving now, a sheet or an Undo toast; the Shell's.
    var busy: () -> Bool = { false }
    /// Called after each change of `state`.
    var moved: () -> Void = {}
    /// The app's motion setting, and the sidebar button of the toolbar, whose click is its own.
    var motion: () -> Look.Motion = { .calm }, button: () -> NSView? = { nil }

    init(_ list: SidebarView) {
        host = NSHostingView(rootView: list)
        super.init(frame: .zero)
        (host.safeAreaRegions, host.sizingOptions) = ([], [])
        (blur.material, blur.blendingMode, blur.state) = (.underWindowBackground, .withinWindow, .active)
        for card in [blur, host] {
            card.translatesAutoresizingMaskIntoConstraints = false
            card.wantsLayer = true
            card.layer?.cornerRadius = Drawer.radius
            card.layer?.masksToBounds = true
            addSubview(card)
        }
        place = host.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Drawer.margin)
        wide = host.widthAnchor.constraint(equalToConstant: Drawer.width)
        tops = (host.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: Drawer.margin),
                host.topAnchor.constraint(equalTo: topAnchor, constant: Drawer.margin))
        NSLayoutConstraint.activate([place, wide, tops.under, host.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Drawer.margin),
                                     blur.leadingAnchor.constraint(equalTo: host.leadingAnchor), blur.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                                     blur.topAnchor.constraint(equalTo: host.topAnchor), blur.bottomAnchor.constraint(equalTo: host.bottomAnchor)])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Sidebar")
        NotificationCenter.default.addObserver(self, selector: #selector(menuBegan), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuEnded), name: NSMenu.didEndTrackingNotification, object: nil)
    }

    required init?(coder: NSCoder) { nil }

    /// The card, in this view.
    var card: NSRect { host.frame }

    /// Changes `state`, the card sliding in or out when that changes, the keys given back when it leaves.
    func change(_ body: (inout DrawerState) -> Void) {
        let was = state
        body(&state)
        guard state != was else { return }
        if !state.peek { leaving?.invalidate() }
        if was.shown != state.shown {
            if !state.shown { focusBack() }
            slide(state.shown)
        }
        moved()
    }

    /// The sidebar comes over the page; `keys`, it takes them, for ↑ and ↓.
    func open(keys: Bool = false) {
        guard !state.dock else { return }
        leaving?.invalidate()
        if !state.peek { before = window?.firstResponder }
        inside = pointerOver
        change { $0.peek = true }
        if keys { window?.makeFirstResponder(host) }
    }

    func close() { change { $0.peek = false } }

    /// ⌃⌘S and the toolbar's button.
    func toggle() {
        let peeked = state.peek
        if !peeked { before = window?.firstResponder }
        change { $0.toggle() }
        if state.peek, !peeked { window?.makeFirstResponder(host) }
    }

    /// Follows the window: where its top is free the card starts 10 points from it.
    func follow(topFree: Bool) {
        tops.under.isActive = !topFree
        tops.top.isActive = topFree
        wide.constant = Drawer.width
    }

    private func slide(_ on: Bool) {
        let rest = on ? Drawer.margin : -Drawer.width - 24, calm = window == nil ? 0 : Look.duration(on ? 0.36 : 0.24, Look.motion(motion()))
        if on { [blur, host].forEach { $0.isHidden = false } }
        let settled = { [weak self] in
            guard let self, !state.shown else { return }
            [blur, host].forEach { $0.isHidden = true }
        }
        guard calm > 0 else {
            place.constant = rest
            return settled()
        }
        Look.animate(calm, on ? Look.out : Look.douce, { [place] in place?.moving.constant = rest }, done: settled)
    }

    private func focusBack() {
        guard let window else { return }
        let focused = (window.firstResponder as? NSTextView).flatMap { $0.isFieldEditor ? $0.delegate as? NSView : nil } ?? window.firstResponder
        guard (focused as? NSView)?.isDescendant(of: self) == true else { return }
        window.makeFirstResponder((before as? NSView)?.window === window || before is NSWindow ? before : window.contentView)
    }

    // MARK: The pointer

    /// The card and the 10 points around it: the pointer on the edge is not gone.
    private var room: NSRect { NSRect(x: 0, y: card.minY - Drawer.margin, width: Drawer.width + 2 * Drawer.margin, height: card.height + 2 * Drawer.margin) }
    /// Where the pointer is now, only in the key window, which alone tracks it.
    private var pointerOver: Bool {
        guard let window, window.isKeyWindow else { return false }
        return room.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: room, options: pointerOver ? [.mouseEnteredAndExited, .activeInKeyWindow, .assumeInside] : [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }

    override func layout() {
        super.layout()
        needsDisplay = true
        updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        inside = true
        leaving?.invalidate()
    }

    override func mouseExited(with event: NSEvent) {
        inside = false
        if state.peek { leave() }
    }

    /// Leaves after `seconds`, looking again while something holds it; the timer also runs while a menu tracks. A menu
    /// that ended sees for itself whether the pointer came back (`menu`): it sends no entry.
    func leave(after seconds: TimeInterval = 0.32, menu: Bool = false) {
        leaving?.invalidate()
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self, state.peek, !inside else { return }
            if menuOpen || isRenaming || busy() { return leave(menu: menuOpen || menu) }
            if menu, pointerOver { return }
            close()
        }
        RunLoop.main.add(timer, forMode: .common)
        leaving = timer
    }

    private var isRenaming: Bool { host.rootView.library.sidebar.renaming != nil }
    @objc private func menuBegan() { menuOpen = true }
    @objc private func menuEnded() { menuOpen = false }

    // MARK: The window's clicks

    /// A click in the window off the sidebar and off its own toolbar button sends a floating sidebar away.
    func clicked(_ event: NSEvent) {
        guard state.peek, let window, event.window === window, let frame = window.contentView?.superview,
              let hit = frame.hitTest(event.locationInWindow), !hit.isDescendant(of: self), button().map({ !hit.isDescendant(of: $0) }) ?? true else { return }
        inside = false
        close()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let clicks { NSEvent.removeMonitor(clicks) }
        clicks = window == nil ? nil : NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.clicked(event)
            return event
        }
    }

    /// Only the card takes the mouse; the rest of the view is air.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self || !state.shown ? nil : hit
    }

    /// The float shadow and ring; the glass inside them is the window server's, the tint the list's.
    override func draw(_ dirtyRect: NSRect) {
        guard state.shown else { return }
        Look.drawFloat(card, radius: Drawer.radius, fill: .side, ring: false, appearance: effectiveAppearance, hollow: true)
        Look.Token.line2.color.setStroke()
        let ring = NSBezierPath(roundedRect: card.insetBy(dx: -0.25, dy: -0.25), xRadius: Drawer.radius, yRadius: Drawer.radius)
        ring.lineWidth = 0.5
        ring.stroke()
    }
}

extension Shell {
    /// Lets the window's state reach the sidebar: whether there is room, the pin of Settings, and a build on New Space.
    func arrange() {
        let room = !full && !pageFull && window.frame.width >= Shell.narrow, pinned = library.preferences.pinned, building = assistant.building
        drawer.change {
            if $0.pinned != pinned { $0.set(pinned: pinned) }
            $0.room = room
            $0.build(building)
        }
        drawer.follow(topFree: full || pageFull)
    }

    /// The sidebar changed: the center makes its room or takes it back, and the edge, the pin and the toolbar's button
    /// say so.
    func drawerMoved() {
        let state = drawer.state
        column.constant = state.dock ? Drawer.column : 0
        (library.sidebar.kept, library.sidebar.room) = (state.kept, state.room)
        reveals()
        let button = toolbarItems.first { $0.itemIdentifier == Shell.sidebar }?.view as? ToolButton, words = state.shown ? "Hide Sidebar" : "Show Sidebar"
        button?.pressed = state.shown
        button?.toolTip = Keys.tooltip("sidebar", words)
        button?.setAccessibilityLabel(words)
    }

    /// The pin and View › Keep Sidebar Open.
    func keepSidebar() {
        let inside = drawer.inside
        drawer.change { $0.pin(inside: inside) }
        library.preferences.pinned = drawer.state.pinned
    }

    /// What holds a floating sidebar besides its own menus and rename: a sheet, or a toast that offers Undo.
    var holdsDrawer: Bool {
        window.attachedSheet != nil || layer.subviews.contains { ($0 as? Toast)?.offersUndo == true }
    }
}

extension App {
    /// ⌃⌘S. NSWindow answers toggleSidebar: itself, ahead of the app: this one has a selector of its own.
    @objc func showSidebar(_ sender: Any?) { shell.drawer.toggle() }
    /// View › Keep Sidebar Open.
    @objc func keepSidebarOpen(_ sender: Any?) { shell.keepSidebar() }
}
