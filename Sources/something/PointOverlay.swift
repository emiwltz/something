// Point mode's layer over the open space's page: it takes every click (none reaches the page) and hands the wheel on
// as a scroll from something's world (Pointing.swift). It dims the space a little, with a hole around the part under
// the pointer, draws the sign's four corners around that part with its kind in a pill ("this table"), and says the
// mode and its way out in a banner at the top. A click picks a part; once a frame is drawn, ⌥-click adds one. Esc
// lets go of the picked parts, then stops the mode. The frames follow the page when it scrolls or reloads. It is all
// drawn in draw(_:), so a picture of the window shows it as the screen does.
import AppKit
import WebKit

final class PointOverlay: NSView {
    /// The space it points into; weak, as an answer of the page may come after the space closed.
    private(set) weak var space: SpaceView?
    var motion: Look.Motion
    /// Called when Esc stops the mode: the window takes the overlay away.
    var stopped: () -> Void = {}
    /// The part under the pointer, and the parts picked, in the page's viewport (the overlay's own points).
    private(set) var hovered: Pointing.Part?
    private(set) var picks: [Pointing.Part] = []
    /// What the banner says, in its order: the mode, then the way on or out.
    var banner: [String] {
        picks.isEmpty ? ["Point at a part of the space", "Esc", "to stop"]
            : ["Say what should change", "Hold ⌥ and click to add a part", "Esc", "Back"]
    }

    private var asking = false, pending: CGPoint?, pointer: CGPoint?
    /// The hole's rectangle as drawn, moving towards its part; when it started and from where, while it moves.
    private var hole: CGRect?, from: CGRect?, began: TimeInterval = 0
    private var arrived: TimeInterval = 0
    private var timer: Timer?

    /// Frames stand 7 points off their part; the hole is rounded 9; the corners have 17-point arms.
    static let pad: CGFloat = 7, holeRadius: CGFloat = 9, arm: CGFloat = 17, stroke: CGFloat = 17 * 15 / 100

    init(_ space: SpaceView, motion: Look.Motion) {
        (self.space, self.motion) = (space, motion)
        super.init(frame: space.web.frame)
        arrived = CACurrentMediaTime()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        changed()
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Every click in its bounds is its own: the page under it hears none.
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) { look(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) {
        pointer = nil
        hover(nil)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let at = convert(event.locationInWindow, from: nil), adding = event.modifierFlags.contains(.option)
        Task { @MainActor in await click(at: at, adding: adding) }
    }

    /// The wheel scrolls the page under the overlay, then the frames and the part under the pointer follow it.
    override func scrollWheel(with event: NSEvent) {
        let line: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        let delta = CGSize(width: -event.scrollingDeltaX * line, height: -event.scrollingDeltaY * line)
        guard let space, let frame = space.frame, delta != .zero else { return }
        let web = space.web, at = convert(event.locationInWindow, from: nil)
        Task { @MainActor in
            await Pointing.scroll(by: delta, at: at, in: web, frame: frame)
            await follow()
        }
    }

    /// Esc reaches escape() through the app's key monitor wherever the focus is in the window; this is the way of a
    /// window without that monitor (a test's), the overlay being the first responder.
    override func cancelOperation(_ sender: Any?) { _ = escape() }

    /// Esc: lets go of the picked parts, or stops the mode. Returns true: the key is the overlay's.
    func escape() -> Bool {
        if picks.isEmpty { stopped() } else { unpick() }
        return true
    }

    /// Asks which part is at `point`, one question at a time: a pointer moving faster than the page answers is asked
    /// about where it is last.
    func look(at point: CGPoint) {
        pointer = point
        guard !asking else { return pending = point }
        guard let space, let frame = space.frame else { return hover(nil) }
        asking = true
        let web = space.web
        Task { @MainActor in
            let part = await Pointing.part(at: point, in: web, frame: frame)
            asking = false
            if pointer != nil { hover(part) }
            if let next = pending {
                pending = nil
                look(at: next)
            }
        }
    }

    /// A click at `point`: picks the part there, adds it with ⌥ once a frame is drawn, or lets the picks go when it
    /// falls on nothing.
    func click(at point: CGPoint, adding: Bool) async {
        guard let space, let frame = space.frame else { return }
        guard let part = await Pointing.part(at: point, in: space.web, frame: frame) else {
            if !adding { unpick() }
            return
        }
        if adding, !picks.isEmpty {
            if !picks.contains(where: { $0.path == part.path }) { picks.append(part) }
        } else {
            picks = [part]
        }
        hover(nil)
        changed()
    }

    func unpick() {
        picks = []
        changed()
    }

    private func hover(_ part: Pointing.Part?) {
        // A picked part keeps its frame: the pointer over it draws no second one.
        let part = part.flatMap { part in picks.contains { $0.path == part.path } ? nil : part }
        guard part != hovered else { return }
        hovered = part
        changed()
    }

    /// Asks where the parts are now, after a scroll, a reload or a resize; a part the page lost is let go.
    func follow() async {
        guard let space, let frame = space.frame else { return }
        let paths = picks.map(\.path) + [hovered?.path].compactMap { $0 }
        let rects = await Pointing.rects(paths, in: space.web, frame: frame)
        guard rects.count == paths.count else { return }
        picks = zip(picks, rects).compactMap { part, rect in rect.map { Pointing.Part(path: part.path, tag: part.tag, rect: $0) } }
        if let part = hovered { hovered = rects.last.flatMap { $0 }.map { Pointing.Part(path: part.path, tag: part.tag, rect: $0) } }
        changed()
        if let pointer { look(at: pointer) }
    }

    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        Task { @MainActor in await follow() }
    }

    // MARK: Drawing

    /// The part the hole opens on: the first picked, else the one under the pointer.
    private var lead: CGRect? { (picks.first ?? hovered).map { $0.rect.insetBy(dx: -Self.pad, dy: -Self.pad) } }

    private func changed() {
        let target = lead
        if target != hole {
            // A hole opening for the first time takes its place at once; then it moves, calmly.
            from = hole == nil || Look.motion(motion) == .reduced ? nil : hole
            hole = target
            began = CACurrentMediaTime()
        }
        setAccessibilityLabel(banner[0])
        setAccessibilityHelp(banner.dropFirst().joined(separator: " "))
        setAccessibilityValue((picks.isEmpty ? [hovered?.kind].compactMap { $0 } : picks.map(\.kind)).joined(separator: ", "))
        tick()
        needsDisplay = true
    }

    /// Draws again while the hole moves or the banner arrives, at up to 60 frames a second.
    private func tick() {
        guard timer == nil, moving else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            needsDisplay = true
            guard !moving else { return }
            timer.invalidate()
            self.timer = nil
        }
    }

    private var moving: Bool {
        let now = CACurrentMediaTime()
        return Look.motion(motion) == .calm && (now - arrived < 0.45 || (from != nil && now - began < 0.3))
    }

    /// How far a change that lasts `seconds` has gone, on `curve`, from `start`.
    private func progress(_ seconds: TimeInterval, since start: TimeInterval, _ curve: Look.Curve) -> CGFloat {
        guard Look.motion(motion) == .calm, seconds > 0 else { return 1 }
        return CGFloat(curve.value(at: (CACurrentMediaTime() - start) / seconds))
    }

    /// The hole where it is drawn now.
    private var drawnHole: CGRect? {
        guard let hole else { return nil }
        guard let from else { return hole }
        let p = progress(0.3, since: began, Look.douce)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
        return CGRect(x: mix(from.minX, hole.minX), y: mix(from.minY, hole.minY), width: mix(from.width, hole.width), height: mix(from.height, hole.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        let night = Look.isDark(effectiveAppearance), dim = NSBezierPath(rect: bounds)
        // The dim: the scrim at .8 by day, .5 at night, cut around the lead part.
        if let hole = drawnHole {
            dim.append(NSBezierPath(roundedRect: hole, xRadius: Self.holeRadius, yRadius: Self.holeRadius))
            dim.windingRule = .evenOdd
        }
        Look.Token.scrim.color.withAlphaComponent((Look.Token.scrim.color.usingColorSpace(.sRGB)?.alphaComponent ?? 0.18) * (night ? 0.5 : 0.8)).setFill()
        dim.fill()
        let lifted = drawnHole.map { $0 != hole } ?? false
        for part in picks { frame(part, words: part.kind, ink: .ink, at: lifted && part == picks.first ? drawnHole : nil) }
        if let hovered {
            frame(hovered, words: (picks.isEmpty ? "" : "+ ") + hovered.kind, ink: picks.isEmpty ? .ink : .ink2,
                  at: lifted && picks.isEmpty ? drawnHole : nil)
        }
        drawBanner()
    }

    /// The sign's four corners around `part` (or in `box` while its hole moves), haloed in the background so they read
    /// on any page, and its pill above it, or below it when the part starts within 36 points of the top.
    private func frame(_ part: Pointing.Part, words: String, ink: Look.Token, at box: CGRect?) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        let r = box ?? part.rect.insetBy(dx: -Self.pad, dy: -Self.pad), a = Self.arm
        c.saveGState()
        c.setShadow(offset: .zero, blur: 2.5, color: Look.Token.bg.color.cgColor)
        c.setStrokeColor(ink.color.cgColor)
        c.setLineWidth(Self.stroke * 100 / a)
        c.setLineCap(.round)
        c.setLineJoin(.round)
        let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX - a, y: r.minY), CGPoint(x: r.maxX - a, y: r.maxY - a), CGPoint(x: r.minX, y: r.maxY - a)]
        for (index, at) in corners.enumerated() {
            c.saveGState()
            c.translateBy(x: at.x + a / 2, y: at.y + a / 2)
            c.rotate(by: CGFloat(index) * CGFloat.pi / 2)
            c.scaleBy(x: a / 100, y: a / 100)
            c.translateBy(x: -50, y: -50)
            c.addPath(Sign.Geometry.corner)
            c.strokePath()
            c.restoreGState()
        }
        c.restoreGState()
        // The pill: 21 high, 8 points each side, rounded 6, in the action's colours.
        let text = NSAttributedString(string: words, attributes: [.font: Look.font(.ui, size: 11, weight: .semibold), .foregroundColor: Look.Token.actfg.color])
        let size = text.size(), pill = CGRect(x: r.minX, y: part.rect.minY < 36 ? r.maxY + 6 : r.minY - 6 - 21, width: ceil(size.width) + 16, height: 21)
        Look.Token.act.color.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
        text.draw(at: CGPoint(x: pill.minX + 8, y: pill.midY - size.height / 2))
    }

    /// The banner: 34 high, centred 14 points under the top, on the glass with the float shadow; it slides down as
    /// the mode starts.
    private func drawBanner() {
        let words = banner, font = Look.font(.ui, size: 12.5, weight: .medium)
        let first = NSAttributedString(string: words[0], attributes: [.font: font, .foregroundColor: Look.Token.ink.color])
        let quiet: [NSAttributedString.Key: Any] = [.font: Look.font(.ui, size: 12.5), .foregroundColor: Look.Token.ink2.color]
        let hint = words.count == 4 ? NSAttributedString(string: words[1], attributes: quiet) : nil
        let key = NSAttributedString(string: words[words.count - 2], attributes: [.font: Look.font(.ui, size: 10.5, weight: .medium),
                                                                               .foregroundColor: Look.Token.ink.color])
        let after = NSAttributedString(string: words[words.count - 1], attributes: quiet)
        let icon = NSImage(systemSymbolName: "scope", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium)) ?? NSImage()
        let keyBox = CGSize(width: ceil(key.size().width) + 10, height: ceil(key.size().height) + 6)
        var widths: [CGFloat] = [13, ceil(first.size().width)]
        if let hint { widths += [3, ceil(hint.size().width)] }
        widths += [3, keyBox.width + 2 + ceil(after.size().width)]
        let width = 12 + widths.reduce(0, +) + 9 * CGFloat(widths.count - 1) + 14
        let p = progress(0.45, since: arrived, Look.out)
        let box = CGRect(x: (bounds.width - width) / 2, y: 14 - 56 * (1 - p), width: width, height: 34)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(min(1, p * 1.5))
        let shape = NSBezierPath(roundedRect: box, xRadius: 17, yRadius: 17)
        for shade in Look.float(effectiveAppearance) {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            (shadow.shadowColor, shadow.shadowBlurRadius, shadow.shadowOffset) = (shade.color, shade.blur / 2, NSSize(width: 0, height: -shade.y))
            shadow.set()
            Look.Token.glass.color.setFill()
            NSBezierPath(roundedRect: box.insetBy(dx: -shade.spread, dy: -shade.spread), xRadius: 17, yRadius: 17).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        Look.Token.glass.color.setFill()
        shape.fill()
        var x = box.minX + 12
        let mid = box.midY
        Self.tinted(icon, Look.Token.ink.color).draw(in: CGRect(x: x, y: mid - 6.5, width: 13, height: 13), from: .zero,
                                                     operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        x += 13 + 9
        func put(_ text: NSAttributedString) {
            let size = text.size()
            text.draw(at: CGPoint(x: x, y: mid - size.height / 2))
            x += ceil(size.width) + 9
        }
        func dot() {
            Look.Token.ink3.color.setFill()
            NSBezierPath(ovalIn: CGRect(x: x, y: mid - 1.5, width: 3, height: 3)).fill()
            x += 3 + 9
        }
        put(first)
        if let hint {
            dot()
            put(hint)
        }
        dot()
        let keyRect = CGRect(x: x, y: mid - keyBox.height / 2, width: keyBox.width, height: keyBox.height)
        Look.Token.sel.color.setFill()
        NSBezierPath(roundedRect: keyRect, xRadius: 5, yRadius: 5).fill()
        key.draw(at: CGPoint(x: keyRect.minX + 5, y: keyRect.minY + 3))
        x += keyBox.width + 2 + 3
        put(after)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// `image` drawn in `color`: a symbol's template image takes no tint when drawn by hand.
    static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    override func removeFromSuperview() {
        timer?.invalidate()
        timer = nil
        super.removeFromSuperview()
    }
}
