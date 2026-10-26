// The layer above the whole window's split view, for what covers the window rather than one column: the toast, and
// the cards on a scrim, the shortcut sheet (KeysSheet.swift) and the palette (Palette.swift); later the sidebar shown
// over the space. It takes the mouse only on what it holds, so the columns, their dividers and the toolbar's separators
// under it behave as if it were not there, and it is hidden while it holds nothing. The glass over the center, which
// holds the assistant, is one too (Glass.swift).
import AppKit

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

    /// Lays the card over all of `layer`, any other card closed first, and gives the focus to `focus` (else to the
    /// scrim). The layer lays the card out first: a SwiftUI card makes its AppKit views on its first layout.
    func present(in layer: WindowLayer, focus: () -> NSView? = { nil }) {
        layer.subviews.compactMap { $0 as? ScrimCard }.forEach { $0.close() }
        frame = layer.bounds
        autoresizingMask = [.width, .height]
        layer.hold(self)
        before = layer.window?.firstResponder
        layer.layoutSubtreeIfNeeded()
        layer.window?.makeFirstResponder(focus() ?? self)
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
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
