// The layer above the whole window's split view, for what covers the window rather than one column: the toast, and
// the cards on a scrim, the shortcut sheet (KeysSheet.swift) and the palette (Palette.swift); and the sidebar laid
// over the space in full screen or floating (SidebarOver). It takes the mouse only on what it holds,
// so the columns, their dividers and the toolbar's separators under it behave as if it were not there, and it is
// hidden while it holds nothing. The glass over the center, which holds the assistant, is one too (Glass.swift).
import AppKit
import SwiftUI

class WindowLayer: NSView {
    /// Says `words` to VoiceOver at once, for what appears here without taking the focus. Tests replace it.
    var announce: (String) -> Void = { words in
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: words, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// Lays the layer over all of `view`, above its other subviews, following its size.
    init(over view: NSView) {
        super.init(frame: view.bounds)
        autoresizingMask = [.width, .height]
        isHidden = true
        view.addSubview(self, positioned: .above, relativeTo: nil)
    }

    required init?(coder: NSCoder) { nil }

    /// What it holds answers for itself; the layer's own empty space answers nil, so the event goes on to what is under it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    /// Shows `view` in the layer, the layer brought back above the columns, which the split view may have added after
    /// it. The layer shows first: a view added under a hidden one would stay hidden to the mouse.
    func hold(_ view: NSView) {
        isHidden = false
        if superview?.subviews.last !== self { superview?.addSubview(self, positioned: .above, relativeTo: nil) }
        addSubview(view)
    }

    override func willRemoveSubview(_ subview: NSView) { isHidden = subviews.allSatisfy { $0 === subview } }
}

/// A card on a scrim over all of the window layer, one at a time: the shortcut sheet and the palette. It takes the
/// focus while it is up, so no key reaches the page under it, and gives it back to where it was. Esc, a click on the
/// scrim or its own key again closes it. The toolbar draws above the window layer, so a click on one of its controls
/// closes the card instead of acting, as a click on the scrim does.
class ScrimCard: NSView {
    /// The card, the scrim's first subview; placed by the subclass.
    let card: NSView
    private let radius: CGFloat
    /// What had the focus before the card took it.
    private weak var before: NSResponder?
    /// The watch on the window's clicks while the card is in one, for the toolbar it cannot cover.
    private var clicks: Any?
    /// Where the card's shadow and ring were last drawn.
    private(set) var drawn = NSRect.zero
    /// How the card arrives under Calm motion, set by the subclass: `place`, the constraint that places it, starts
    /// `by` points off and comes back while the card fades in for `seconds`.
    var arrival: (place: NSLayoutConstraint, by: CGFloat, seconds: TimeInterval)?
    /// What takes the focus while the card is up; nil: the scrim.
    var focus: NSView? { nil }

    init(card: NSView, radius: CGFloat, label: String) {
        (self.card, self.radius) = (card, radius)
        super.init(frame: .zero)
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityRoleDescription("dialog")
        setAccessibilityLabel(label)
    }

    required init?(coder: NSCoder) { nil }

    /// The card of this kind `layer` holds, nil while none is up.
    static func shown(in layer: WindowLayer) -> Self? { layer.subviews.lazy.compactMap { $0 as? Self }.first }

    /// Closes the card of this kind `layer` holds (`ScrimCard` closes any); false when none is up, so Esc goes on to
    /// what else it closes.
    static func close(in layer: WindowLayer) -> Bool {
        guard let card = shown(in: layer) else { return false }
        card.close()
        return true
    }

    /// Shows the card `make` makes over all of `layer`, or closes the one of this kind when it is up, as its key does;
    /// returns the card when it shows. Any other card closes first; the card takes the focus and arrives under Calm
    /// `motion`. The layer lays the card out first: a SwiftUI card makes its AppKit views on its first layout.
    static func toggle<Card: ScrimCard>(in layer: WindowLayer, motion: Look.Motion, _ make: () -> Card) -> Card? {
        if Card.close(in: layer) { return nil }
        let card = make()
        layer.subviews.compactMap { $0 as? ScrimCard }.forEach { $0.close() }
        (card.frame, card.autoresizingMask) = (layer.bounds, [.width, .height])
        layer.hold(card)
        card.before = layer.window?.firstResponder
        layer.layoutSubtreeIfNeeded()
        layer.window?.makeFirstResponder(card.focus ?? card)
        let calm = Look.duration(card.arrival?.seconds ?? 0, Look.motion(motion))
        guard calm > 0, let (place, by, _) = card.arrival else { return card }
        let rest = place.constant
        (card.alphaValue, place.constant) = (0, rest + by)
        layer.layoutSubtreeIfNeeded()
        Look.animate(calm, Look.out) {
            card.moving.alphaValue = 1
            place.moving.constant = rest
        }
        return card
    }

    /// Takes the card away at once, the focus back where it was when that is still in the window.
    func close() {
        let window = window
        // A field's keys go to the window's field editor, which is the field's only while it edits.
        let focused = (window?.firstResponder as? NSTextView).flatMap { $0.isFieldEditor ? $0.delegate as? NSView : nil } ?? window?.firstResponder
        removeFromSuperview()
        guard let window, focused === self || (focused as? NSView)?.isDescendant(of: self) == true else { return }
        // A view that left the window since cannot take it back: the window's content does.
        let back = (before as? NSView)?.window === window || before is NSWindow ? before : nil
        window.makeFirstResponder(back ?? window.contentView)
    }

    /// A click in the card's window that lands outside it (the toolbar draws above the layer) closes it. Returns nil,
    /// the click used up, when it would have worked a toolbar control; else `event`, so the lights and the window's
    /// drag still answer it.
    func covers(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window, let frame = window.contentView?.superview,
              let hit = frame.hitTest(event.locationInWindow), !hit.isDescendant(of: self) else { return event }
        close()
        let lights = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap(window.standardWindowButton)
        let control = sequence(first: hit, next: \.superview).contains { view in view is NSControl && !lights.contains { $0 === view } }
        return control ? nil : event
    }

    /// The toolbar's controls, faded while the card is up: the toolbar draws above the window layer, so the scrim dims
    /// only the band behind them, and the faded controls let the whole toolbar dim evenly with the window.
    private var faded: [NSView] = []
    /// Whether the card dims the window under it; the sidebar laid over does not.
    var dims: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        faded.forEach { $0.alphaValue = 1 }
        faded = dims ? ((window?.delegate as? Shell)?.toolbarItems ?? []).compactMap(\.view) : []
        faded.forEach { $0.alphaValue = 0.45 }
        if let clicks { NSEvent.removeMonitor(clicks) }
        clicks = window == nil ? nil : NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.covers(event) ?? event
        }
    }

    /// The card moves by constraint while it arrives, which does not redraw the scrim: its float shadow and ring follow.
    override func layout() {
        super.layout()
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
    override func keyDown(with event: NSEvent) { event.keyCode == 53 ? close() : super.keyDown(with: event) }
    /// A click on the scrim closes it; a click on the card is the card's.
    override func mouseDown(with event: NSEvent) { close() }
    /// The scrim takes the wheel too: the page under it stays where it is.
    override func scrollWheel(with event: NSEvent) {}

    /// The scrim, then the card's float shadow and ring; drawn here so a picture made with cacheDisplay shows them.
    override func draw(_ dirtyRect: NSRect) {
        Look.Token.scrim.color.setFill()
        bounds.fill()
        drawn = card.frame
        Look.drawFloat(card.frame, radius: radius, fill: .bg2, ring: true, appearance: effectiveAppearance)
    }
}

/// The sidebar laid over the space at the window's left edge, full height, where full screen leaves no column for it:
/// the mockup's .wn-sideov, its float shadow and ring, no scrim. It arrives from the edge, takes the focus for ↑ and ↓,
/// and goes with Esc, ⌃⌘S again, a click outside it, or the space picked in it. Floating (PageFull.swift), it is
/// frosted glass with the page seen through, 8 points inside the window's edges with rounded corners and a pin at its
/// top, and leaves soon after the pointer does, unless a field in it is being edited.
final class SidebarOver: ScrimCard {
    /// The mockup's 236 points, grown with the interface size as the pinned sidebar is.
    static var width: CGFloat { 236 * Look.scale.size.factor }
    private let host: NSView
    /// Whether it leaves with the pointer: the floating sidebar's.
    let floats: Bool
    private var leaving: Timer?
    /// Whether one of the app's menus is open (a row's), and what tells it.
    private var menuOpen = false, menus: [NSObjectProtocol] = []

    /// Lays out `list`, the window's own sidebar list: its first row 49 points down, under the 50-point band of the
    /// mockup's sidebar head, whatever safe area the full screen gives; `under` points from the top (the toolbar), its
    /// first row just under them. `pin`, when given, makes it the floating sidebar, its head 40 points
    /// high holding the pin.
    init(_ list: SidebarView, under: CGFloat = 0, pin: (() -> Void)? = nil) {
        var list = list
        list.glass = pin != nil
        // The mockup's floating panel: 8 points in, 8 wider, 14-point corners.
        let inset: CGFloat = list.glass ? 8 : 0, radius = list.glass ? Look.card + 4 : 0
        let host = NSHostingView(rootView: list.padding(.top, list.glass ? 40 : max(52 - under, 8)).background(Look.Token.side.ui.opacity(list.glass ? 0.76 : 1)))
        (host.safeAreaRegions, host.sizingOptions) = ([], [])
        (self.host, floats) = (host, list.glass)
        super.init(card: host, radius: radius, label: "Sidebar")
        let place = host.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset)
        NSLayoutConstraint.activate([place, host.topAnchor.constraint(equalTo: topAnchor, constant: under + inset),
                                     host.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
                                     host.widthAnchor.constraint(equalToConstant: SidebarOver.width + inset)])
        arrival = (place, -SidebarOver.width - 2 * inset, 0.5)
        guard let pin else { return }
        host.wantsLayer = true
        host.layer?.cornerRadius = radius
        host.layer?.masksToBounds = true
        // The mockup's frosted glass: the page blurred behind the panel, the sidebar's colour at 76 % over it.
        let blur = NSVisualEffectView()
        (blur.material, blur.blendingMode, blur.state) = (.underWindowBackground, .withinWindow, .active)
        (blur.wantsLayer, blur.translatesAutoresizingMaskIntoConstraints) = (true, false)
        blur.layer?.cornerRadius = radius
        blur.layer?.masksToBounds = true
        addSubview(blur, positioned: .below, relativeTo: host)
        NSLayoutConstraint.activate([blur.leadingAnchor.constraint(equalTo: host.leadingAnchor), blur.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                                     blur.topAnchor.constraint(equalTo: host.topAnchor), blur.bottomAnchor.constraint(equalTo: host.bottomAnchor)])
        for (name, open) in [(NSMenu.didBeginTrackingNotification, true), (NSMenu.didEndTrackingNotification, false)] {
            menus.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.menuOpen = open }
            })
        }
        let image = NSImage(systemSymbolName: "pin", accessibilityDescription: "Keep Sidebar") ?? NSImage()
        let button = Pin(image: image, target: nil, action: nil)
        (button.isBordered, button.contentTintColor, button.toolTip) = (false, Look.Token.ink2.color, Keys.tooltip("sidebar", "Keep Sidebar"))
        button.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        button.setAccessibilityLabel("Keep Sidebar")
        button.kept = pin
        (button.target, button.action) = (button, #selector(Pin.keep))
        button.translatesAutoresizingMaskIntoConstraints = false
        // Beside the card rather than in it: the hosting view lays out its own subviews.
        addSubview(button)
        NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: 26), button.heightAnchor.constraint(equalToConstant: 26),
                                     button.topAnchor.constraint(equalTo: host.topAnchor, constant: 7),
                                     button.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -10)])
    }

    required init?(coder: NSCoder) { nil }

    override var focus: NSView? { host }
    override var dims: Bool { false }

    /// The pin, with what it does.
    final class Pin: NSButton {
        var kept: () -> Void = {}
        @objc func keep() { kept() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        if floats { addTrackingArea(NSTrackingArea(rect: room, options: [.mouseEnteredAndExited, .activeInKeyWindow, .assumeInside], owner: self)) }
    }

    /// From the window's edge, where the pointer brought it, to its right side: it leaves once the pointer leaves that.
    private var room: NSRect { NSRect(x: 0, y: card.frame.minY, width: card.frame.maxX, height: card.frame.height) }

    override func layout() {
        super.layout()
        updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { leaving?.invalidate() }
    /// The floating sidebar leaves a third of a second after the pointer, unless a name in it is being edited.
    override func mouseExited(with event: NSEvent) { leave(menu: false) }

    /// Closes after a third of a second; while a menu is open (a row's) it waits for the menu, then stays if the
    /// pointer is back over it (`menu`). The timer also runs in the menu's tracking mode, to see it.
    private func leave(menu: Bool) {
        leaving?.invalidate()
        let timer = Timer(timeInterval: 0.32, repeats: false) { [weak self] _ in
            guard let self, superview != nil, let window else { return }
            if let editing = window.firstResponder as? NSView, editing is NSText, editing.isDescendant(of: self) { return }
            if menuOpen { return leave(menu: true) }
            if menu, room.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) { return }
            close()
        }
        RunLoop.main.add(timer, forMode: .common)
        leaving = timer
    }

    override func removeFromSuperview() {
        menus.forEach(NotificationCenter.default.removeObserver)
        menus = []
        leaving?.invalidate()
        super.removeFromSuperview()
    }

    /// No scrim: the space stays as it is beside the sidebar, which casts the float shadow.
    override func draw(_ dirtyRect: NSRect) {
        Look.drawFloat(card.frame, radius: floats ? Look.card + 4 : 0, fill: .side, ring: true, appearance: effectiveAppearance, hollow: floats)
    }
}
