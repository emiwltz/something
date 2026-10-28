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
    /// go, and a hint at the top says how to leave.
    func pageFullScreen(_ on: Bool) {
        pageAfterFull = false
        guard on != pageFull else { return }
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
        // Never drawn pressed, as the mockup's: its tooltip and label say how to leave.
        button?.toolTip = on ? "Exit Page Full Screen (esc)" : Keys.tooltip("pagefull", "Page Full Screen")
        button?.setAccessibilityLabel(on ? "Exit Page Full Screen" : "Page Full Screen")
        layer.subviews.filter { $0 is NSHostingView<PageFullHint> }.forEach { $0.removeFromSuperview() }
        if on { hint() } else { fit() }
        reveals()
    }

    /// The hint of its first moments, at the page's top centre, 14 points down, gone after 2.6 s; VoiceOver reads it.
    private func hint() {
        let ask = Keys.shown("ask"), hint = NSHostingView(rootView: PageFullHint(ask: ask))
        hint.translatesAutoresizingMaskIntoConstraints = false
        layer.hold(hint)
        NSLayoutConstraint.activate([hint.topAnchor.constraint(equalTo: center.topAnchor, constant: 14), hint.centerXAnchor.constraint(equalTo: center.centerXAnchor)])
        layer.announce("Page Full Screen · esc to leave · \(ask) assistant")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak hint, motion = library.preferences.motion] in
            guard let hint else { return }
            Look.animate(Look.duration(0.5, Look.motion(motion)), Look.douce, { hint.moving.alphaValue = 0 }, done: { hint.removeFromSuperview() })
        }
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
        guard floats, SidebarOver.shown(in: layer) == nil else { return }
        layOver(under: pageFull ? 0 : window.frame.height - window.contentLayoutRect.maxY, floating: true)
    }

    /// Lays the window's sidebar list over the page `under` points from the top, or takes it away; `floating`, it is
    /// the floating sidebar, inset with its pin. The column's own eyes, so that both lists always say the same.
    func layOver(under: CGFloat, floating: Bool) {
        guard let column = (split.splitViewItems[0].viewController as? NSHostingController<SidebarView>)?.rootView else { return }
        _ = SidebarOver.toggle(in: layer, motion: library.preferences.motion) {
            let list = SidebarView(library: library, assistant: assistant, eyes: column.eyes, column: false)
            return floating ? SidebarOver(list, under: under, inset: 8, pin: { [weak self] in self?.keepSidebar() }) : SidebarOver(list, under: under)
        }
    }

    /// The pin: the floating sidebar becomes a column again, Page Full Screen ending for it.
    func keepSidebar() {
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
/// band behind the toolbar brought back over the page, the window's background, its lower edge and a soft shadow.
final class Reveal: NSView {
    let delay: TimeInterval, leave: TimeInterval
    var came: () -> Void = {}, went: () -> Void = {}
    var height: NSLayoutConstraint?
    /// Whether a click on the empty strip is its own: the left edge's; the top edge lets every click through.
    let clicks: Bool
    var filled = false {
        didSet {
            needsDisplay = true
            // The band brought back lies over the page with a soft shadow under it (the mockup's 0 12 30 -16).
            wantsLayer = true
            layer?.masksToBounds = false
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowRadius = 15
            layer?.shadowOffset = CGSize(width: 0, height: -12)
            layer?.shadowPath = CGPath(rect: bounds.insetBy(dx: 16, dy: 16), transform: nil)
            layer?.shadowOpacity = filled ? 0.35 : 0
        }
    }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(rect: bounds.insetBy(dx: 16, dy: 16), transform: nil)
    }
    private var timer: Timer?

    init(delay: TimeInterval, leave: TimeInterval = 0, clicks: Bool) {
        (self.delay, self.leave, self.clicks) = (delay, leave, clicks)
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
    override func hitTest(_ point: NSPoint) -> NSView? { filled || !clicks ? nil : super.hitTest(point) }
}

/// Page Full Screen's hint, as the mockup's: a dark pill, its keys in caps.
struct PageFullHint: View {
    let ask: String

    var body: some View {
        let dot = Circle().frame(width: 3, height: 3).opacity(0.45)
        HStack(spacing: 7) {
            Text("Page Full Screen").font(Look.font(.ui, size: 12, weight: .semibold).ui)
            dot
            key("esc")
            Text("to leave").opacity(0.72)
            dot
            key(ask)
            Text("assistant").opacity(0.72)
        }
        .font(Look.font(.ui, size: 12, weight: .medium).ui).foregroundStyle(Look.Token.bg.ui)
        .padding(.horizontal, 13).frame(height: 32)
        .background(Capsule().fill(Look.Token.ink.ui.opacity(0.84)))
        .fixedSize()
        .accessibilityHidden(true)
    }

    private func key(_ word: String) -> some View {
        Text(word).font(Look.font(.ui, size: 11, weight: .medium).ui).padding(.horizontal, 6).padding(.vertical, 3)
            .background(Look.Token.bg.ui.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
    }
}
