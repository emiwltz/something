// More room for the page, inside the window. Page Full Screen (⇧⌘F, the toolbar's last button): the sidebar and Info
// step aside, the toolbar and the lights go, and the page fills the window from its top; the pointer at the top edge
// brings the toolbar back over the page until it leaves it, and Esc or ⇧⌘F again ends it. It is not the Mac's full
// screen (⌃⌘F), which stays: asking for one leaves the other. The floating sidebar: a sidebar column the person hid
// still floats at the window's left edge, where the pointer resting 200 ms, or a click, lays it over the page
// (SidebarOver) until the pointer leaves it; its pin keeps it, as ⌃⌘S does, a column again. In Page Full Screen the
// sidebar floats the same way. In both full screens the sticker is discreet (Glass).
import AppKit
import SwiftUI

extension Shell {
    /// Whether the sidebar floats: its column hidden in the window (not the rail's, not in the Mac's full screen), or
    /// the page in Page Full Screen.
    var floats: Bool { pageFull || (!full && !rail && split.splitViewItems[0].isCollapsed) }

    /// Puts the page in Page Full Screen (`on`) or back, only while a space is open; from the Mac's full screen, once
    /// the window has left it. Info closes, the sidebar steps aside and comes back as it was, the toolbar and the lights
    /// go, and a toast says how to leave.
    func pageFullScreen(_ on: Bool) {
        guard on != pageFull else { return }
        pageAfterFull = false
        guard !on || space != nil else { return }
        if on, full {
            pageAfterFull = true
            return window.toggleFullScreen(nil)
        }
        let side = split.splitViewItems[0]
        if on {
            railed(false)
            sideHidden = side.isCollapsed
            showInfo(false)
            bar = max(window.frame.height - window.contentLayoutRect.maxY, 28)
        }
        pageFull = on
        _ = SidebarOver.close(in: layer)
        side.isCollapsed = on || sideHidden
        top?.isActive = false
        top = shown.map(pin)
        top?.isActive = true
        edge.isHidden = on
        glass.discreet = on
        toolbar(!on)
        let button = controls[Shell.full] as? ToolButton
        button?.pressed = on
        button?.toolTip = on ? "Exit Page Full Screen (esc)" : Keys.tooltip("pagefull", "Page Full Screen")
        button?.setAccessibilityLabel(on ? "Exit Page Full Screen" : "Page Full Screen")
        if on {
            toast("Page Full Screen · esc to leave · \(Keys.shown("ask")) for your assistant", quiet: true)
        } else { fit() }
        reveals()
    }

    /// Shows the toolbar and the lights (`shown`) or hides them; in Page Full Screen the top edge then holds the
    /// toolbar's band over the page, for as long as the pointer stays in it.
    func toolbar(_ shown: Bool) {
        window.toolbar?.isVisible = shown
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { window.standardWindowButton($0)?.isHidden = !shown }
        topEdge.filled = pageFull && shown
        topEdge.height?.constant = topEdge.filled ? bar : 6
    }

    /// Lays the floating sidebar over the page from the left edge, its pin at the top; under the toolbar, or from the
    /// window's top in Page Full Screen.
    func float() {
        guard floats, SidebarOver.shown(in: layer) == nil,
              let column = (split.splitViewItems[0].viewController as? NSHostingController<SidebarView>)?.rootView else { return }
        let under = pageFull ? 0 : window.frame.height - window.contentLayoutRect.maxY
        _ = SidebarOver.toggle(in: layer, motion: library.preferences.motion) {
            SidebarOver(SidebarView(library: library, assistant: assistant, eyes: column.eyes, column: false), under: under,
                        inset: 8, pin: { [weak self] in self?.pin() })
        }
    }

    /// The pin: the floating sidebar becomes a column again, Page Full Screen ending for it.
    func pin() {
        _ = SidebarOver.close(in: layer)
        sideHidden = false
        if pageFull { return pageFullScreen(false) }
        split.splitViewItems[0].isCollapsed = false
    }

    /// The two edges, made once: each a strip over the page that the pointer brings something back from.
    func edges() {
        for strip in [topEdge, leftEdge] {
            strip.translatesAutoresizingMaskIntoConstraints = false
            center.addSubview(strip)
        }
        let height = topEdge.heightAnchor.constraint(equalToConstant: 6)
        topEdge.height = height
        leftTop = (leftEdge.topAnchor.constraint(equalTo: center.safeAreaLayoutGuide.topAnchor), leftEdge.topAnchor.constraint(equalTo: center.topAnchor))
        NSLayoutConstraint.activate([height, topEdge.topAnchor.constraint(equalTo: center.topAnchor),
                                     topEdge.leadingAnchor.constraint(equalTo: center.leadingAnchor),
                                     topEdge.trailingAnchor.constraint(equalTo: center.trailingAnchor),
                                     leftEdge.leadingAnchor.constraint(equalTo: center.leadingAnchor),
                                     leftEdge.bottomAnchor.constraint(equalTo: center.bottomAnchor), leftEdge.widthAnchor.constraint(equalToConstant: 8)])
        topEdge.came = { [weak self] in self?.toolbar(true) }
        topEdge.went = { [weak self] in if self?.pageFull == true { self?.toolbar(false) } }
        leftEdge.came = { [weak self] in self?.float() }
        collapse = split.splitViewItems[0].observe(\.isCollapsed) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.reveals() }
        }
        reveals()
    }

    /// Each edge only where it brings something back, above what the center shows.
    func reveals() {
        topEdge.isHidden = !pageFull
        leftEdge.isHidden = !floats
        leftTop?.under.isActive = !pageFull
        leftTop?.top.isActive = pageFull
        for strip in [topEdge, leftEdge] where center.subviews.last !== strip && !strip.isHidden {
            center.addSubview(strip, positioned: .above, relativeTo: nil)
        }
    }
}

/// A strip at an edge of the page that brings something back: the pointer resting on it for `delay`, or a click, calls
/// `came`; leaving it for `leave` calls `went`. Empty, it lets every click but its own through; `filled`, it is the
/// band behind the toolbar brought back over the page, the window's background and its lower edge.
final class Reveal: NSView {
    let delay: TimeInterval, leave: TimeInterval
    var came: () -> Void = {}, went: () -> Void = {}
    var height: NSLayoutConstraint?
    var filled = false { didSet { needsDisplay = true } }
    private var timer: Timer?

    init(delay: TimeInterval, leave: TimeInterval = 0) {
        (self.delay, self.leave) = (delay, leave)
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { after(delay, came) }
    override func mouseExited(with event: NSEvent) { after(leave, went) }
    override func mouseDown(with event: NSEvent) {
        timer?.invalidate()
        came()
    }

    /// Calls `act` after `seconds`, in place of what waited; at once for none.
    private func after(_ seconds: TimeInterval, _ act: @escaping () -> Void) {
        timer?.invalidate()
        guard seconds > 0 else { return act() }
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in act() }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard filled else { return }
        Look.Token.bg.color.setFill()
        bounds.fill()
        Look.Token.line.color.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    /// The band takes nothing: the toolbar over it has the clicks. The strip at the left edge takes its click.
    override func hitTest(_ point: NSPoint) -> NSView? { filled || height != nil ? nil : super.hitTest(point) }
}
