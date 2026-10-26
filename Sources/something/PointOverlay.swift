// Point mode's layer over the open space's page: it takes every click (none reaches the page) and hands the wheel on
// as a scroll from something's world (Pointing.swift). It dims the space a little, with a hole around the part under
// the pointer, draws the sign's four corners around that part with its kind in a pill ("this table"), and says the
// mode and its way out in a banner at the top. A click picks a part; once a frame is drawn, ⌥-click adds one, and the
// composer (PointComposer.swift) attaches to the last one picked. Esc lets go of the picked parts, then stops the
// mode. The frames follow the page when it scrolls or reloads. It is all drawn in draw(_:), so a picture of the
// window shows it as the screen does.
import AppKit
import WebKit

final class PointOverlay: NSView {
    /// The space it points into; weak, as an answer of the page may come after the space closed.
    private(set) weak var space: SpaceView?
    var motion: Look.Motion
    /// Called when Esc stops the mode: the window takes the overlay away.
    var stopped: () -> Void = {}
    /// What the composer's Quick Change (Return) and Add Comment (⌘↵) do with the words and the parts picked.
    var quickChange: (String, [Pointing.Part]) -> Void = { _, _ in }
    var addComment: (String, [Pointing.Part]) -> Void = { _, _ in }
    /// The eyes of the space's assistant, which the composer shows beside the space's name.
    var eyes: () -> Sign.State = { .unknown }
    /// The composer, while parts are picked.
    private(set) var composer: PointComposer?
    /// The part under the pointer, and the parts picked, in the page's viewport (the overlay's own points).
    private(set) var hovered: Pointing.Part?
    private(set) var picks: [Pointing.Part] = []
    /// What the banner says, in its order: the mode, then the way on or out.
    var banner: [String] {
        picks.isEmpty ? ["Point at a part of the space", "Esc", "to stop"]
            : ["Say what should change", "Hold ⌥ and click to add a part", "Esc", "Back"]
    }

    private var asking = false, pending: CGPoint?, pointer: CGPoint?, holding = false
    private var following = false, followAgain = false
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
    /// Every click in its bounds is its own, but for the composer's: the page under it hears none.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        let local = convert(point, from: superview)
        if let composer, composer.frame.contains(local) { return composer.hitTest(local) ?? self }
        return self
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let at = convert(event.locationInWindow, from: nil)
        holding = event.modifierFlags.contains(.option)
        // Over the composer, no part is under the pointer.
        if let composer, composer.frame.contains(at) {
            pointer = nil
            return hover(nil)
        }
        look(at: at)
    }

    override func flagsChanged(with event: NSEvent) {
        holding = event.modifierFlags.contains(.option)
        if let pointer { look(at: pointer) } else { hover(nil) }
    }
    override func mouseExited(with event: NSEvent) {
        pointer = nil
        hover(nil)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let at = convert(event.locationInWindow, from: nil), adding = event.modifierFlags.contains(.option)
        Task { @MainActor in await click(at: at, adding: adding) }
    }

    /// The wheel scrolls the page under the overlay. That a real wheel reaches here with these deltas is a hand trial:
    /// a native wheel event cannot be proven offscreen, nor while the display sleeps (spike SP9).
    override func scrollWheel(with event: NSEvent) {
        let line: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        let delta = CGSize(width: -event.scrollingDeltaX * line, height: -event.scrollingDeltaY * line)
        let at = convert(event.locationInWindow, from: nil)
        Task { @MainActor in await scroll(by: delta, at: at) }
    }

    /// Scrolls the box at `point` that scrolls, else the page, by `delta` from something's world, then the frames and
    /// the part under the pointer follow it. Returns once the page scrolled.
    func scroll(by delta: CGSize, at point: CGPoint) async {
        guard let space, let frame = space.frame, delta != .zero else { return }
        await Pointing.scroll(by: delta, at: point, in: space.web, frame: frame)
        followSoon()
    }

    /// Esc reaches escape() through the app's key monitor wherever the focus is in the window; this is the way of a
    /// window without that monitor (a test's), the overlay being the first responder.
    override func cancelOperation(_ sender: Any?) { _ = escape() }

    /// Esc: lets go of the picked parts, or stops the mode. Returns true: the key is the overlay's.
    func escape() -> Bool {
        if picks.isEmpty { stopped() } else {
            unpick()
            window?.makeFirstResponder(self)
        }
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

    /// A click at `point`: picks the part there, adds it with ⌥ once a frame is drawn (⌥ alone does nothing), or lets
    /// the picks go when it falls on nothing. The composer takes the keys.
    func click(at point: CGPoint, adding: Bool) async {
        guard let space, let frame = space.frame, !adding || !picks.isEmpty else { return }
        guard let part = await Pointing.part(at: point, in: space.web, frame: frame) else {
            if !adding { unpick() }
            return
        }
        if adding, !picks.isEmpty {
            if !picks.contains(where: { $0.path == part.path }) { picks.append(part) }
        } else {
            // Words written about other parts do not go with this one: only an ⌥-add keeps them.
            if picks.map(\.path) != [part.path] { composer?.clear() }
            picks = [part]
        }
        hover(nil)
        changed()
        if let composer { window?.makeFirstResponder(composer.field) }
    }

    func unpick() {
        picks = []
        changed()
    }

    private func hover(_ part: Pointing.Part?) {
        // A picked part keeps its frame: the pointer over it draws no second one; once one is picked, the pointer
        // frames another only while ⌥ is held, to add it.
        let part = part.flatMap { part in picks.contains { $0.path == part.path } || (!picks.isEmpty && !holding) ? nil : part }
        guard part != hovered else { return }
        hovered = part
        changed()
    }

    /// Asks where the parts are now, after a scroll, a reload or a resize; a part the page lost is let go. The
    /// answers are applied by path: a click or a pointer move during the question keeps what it changed.
    func follow() async {
        guard let space, let frame = space.frame else { return }
        let paths = picks.map(\.path) + [hovered?.path].compactMap { $0 }
        let rects = await Pointing.rects(paths, in: space.web, frame: frame)
        guard rects.count == paths.count else { return }
        let found = Dictionary(zip(paths, rects), uniquingKeysWith: { first, _ in first })
        let moved = { (part: Pointing.Part) -> Pointing.Part? in
            guard let rect = found[part.path] else { return part }
            return rect.map { Pointing.Part(path: part.path, tag: part.tag, rect: $0) }
        }
        picks = picks.compactMap(moved)
        if let part = hovered, found[part.path] != nil { hovered = moved(part) }
        changed()
        if let pointer { look(at: pointer) }
    }

    /// A follow without waiting for it, one at a time: the wheel, the page's scroll and a live resize ask many times
    /// a second, and the running one asks once more at its end for all that came meanwhile.
    func followSoon() {
        guard !following else { return followAgain = true }
        following = true
        Task { @MainActor in
            repeat {
                followAgain = false
                await follow()
            } while followAgain
            following = false
        }
    }

    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        followSoon()
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
        compose()
        setAccessibilityLabel(banner[0])
        setAccessibilityHelp(banner.dropFirst().joined(separator: " "))
        setAccessibilityValue((picks.isEmpty ? [hovered?.kind].compactMap { $0 } : picks.map(\.kind)).joined(separator: ", "))
        tick()
        needsDisplay = true
    }

    /// Puts the composer by the last part picked, or takes it away when none is; its words stay while parts are added.
    private func compose() {
        guard let last = picks.last, let space else {
            composer?.removeFromSuperview()
            composer = nil
            return
        }
        let names = PointComposer.sentence(picks.map(\.kind))
        if let composer {
            composer.names = names
        } else {
            let made = PointComposer(names: names, title: space.title, eyes: eyes())
            made.quick = { [weak self] words in
                guard let self else { return }
                quickChange(words, picks)
            }
            made.comment = { [weak self] words in
                guard let self else { return }
                addComment(words, picks)
                // The comment is kept; the mode stays, to point at another part.
                _ = escape()
            }
            made.escape = { [weak self] in _ = self?.escape() }
            addSubview(made)
            composer = made
            watchEyes(made)
        }
        composer?.frame = PointComposer.place(PointComposer.size, by: last.rect, in: bounds.size)
    }

    /// Keeps `composer`'s eyes on its assistant's real state while it is open: each change eyes() reads (an
    /// observable model in the app) draws them again, on the next turn of the main loop.
    private func watchEyes(_ composer: PointComposer) {
        guard self.composer === composer else { return }
        composer.eyes = withObservationTracking { eyes() } onChange: { [weak self, weak composer] in
            DispatchQueue.main.async { if let composer { self?.watchEyes(composer) } }
        }
    }

    /// Draws again while the hole moves or the banner arrives, at up to 60 frames a second.
    private func tick() {
        guard timer == nil, moving else { return }
        timer = .frames(1.0 / 60, common: false) { [weak self] in
            guard let self else { return false }
            needsDisplay = true
            if !moving { timer = nil }
            return moving
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
        // A picked part's name is the composer's to say: its frame has no pill.
        for part in picks { frame(part, words: nil, ink: .ink, at: lifted && part == picks.first ? drawnHole : nil) }
        if let hovered {
            frame(hovered, words: (picks.isEmpty ? "" : "+ ") + hovered.kind, ink: picks.isEmpty ? .ink : .ink2,
                  at: lifted && picks.isEmpty ? drawnHole : nil)
        }
        drawBanner()
        if let composer { Look.drawFloat(composer.frame, radius: Look.card, fill: .bg2, ring: true, appearance: effectiveAppearance) }
    }

    /// The sign's four corners around `part` (or in `box` while its hole moves), haloed in the background so they read
    /// on any page, and the pill of `words` above it, or below it when the part starts within 36 points of the top.
    private func frame(_ part: Pointing.Part, words: String?, ink: Look.Token, at box: CGRect?) {
        let r = box ?? part.rect.insetBy(dx: -Self.pad, dy: -Self.pad)
        Self.corners(r, ink: ink)
        // The pill: 21 high, 8 points each side, rounded 6, in the action's colours, under the frame's bottom left
        // corner as the mockup puts it; above it only where the page has no room below.
        guard let words else { return }
        let text = NSAttributedString(string: words, attributes: [.font: Look.font(.ui, size: 11, weight: .semibold), .foregroundColor: Look.Token.actfg.color])
        let size = text.size(), pill = CGRect(x: r.minX, y: r.maxY + 6 + 21 <= bounds.height ? r.maxY + 6 : r.minY - 6 - 21, width: ceil(size.width) + 16, height: 21)
        Look.Token.act.color.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
        text.draw(at: CGPoint(x: pill.minX + 8, y: pill.midY - size.height / 2))
    }

    /// The sign's four corners in `r`, in `ink`: arms of `a` points, stroked `width` wide in the sign's 100-unit
    /// corner, haloed in the background when `halo`; the corner `skipping` (0 top left, then clockwise) is left out,
    /// for the eyes of a frame at work to take its place. The arrival's growing frame draws them too.
    static func corners(_ r: CGRect, ink: Look.Token, arm a: CGFloat = PointOverlay.arm, width: CGFloat = PointOverlay.stroke * 100 / PointOverlay.arm,
                        halo: Bool = true, skipping: Int? = nil) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        c.saveGState()
        if halo { c.setShadow(offset: .zero, blur: 2.5, color: Look.Token.bg.color.cgColor) }
        c.setStrokeColor(Sign.color(ink))
        c.setLineWidth(width)
        c.setLineCap(.round)
        c.setLineJoin(.round)
        let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX - a, y: r.minY), CGPoint(x: r.maxX - a, y: r.maxY - a), CGPoint(x: r.minX, y: r.maxY - a)]
        for (index, at) in corners.enumerated() where index != skipping {
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
    }

    /// The banner: 34 high, centred 14 points under the top, on the glass with the float shadow; it slides down as
    /// the mode starts.
    private func drawBanner() {
        let words = banner
        let quiet: [NSAttributedString.Key: Any] = [.font: Look.font(.ui, size: 12.5), .foregroundColor: Look.Token.ink2.color]
        let keyFace: [NSAttributedString.Key: Any] = [.font: Look.font(.ui, size: 10.5, weight: .medium), .foregroundColor: Look.Token.ink.color]
        /// A piece of the banner: words, a key in its cap, or the dot between two.
        enum Piece { case words(NSAttributedString), key(NSAttributedString), dot }
        // The mode in ink; a hint whose ⌥ is a key; the way out, its key first.
        var pieces: [Piece] = [.words(NSAttributedString(string: words[0], attributes: [.font: Look.font(.ui, size: 12.5, weight: .medium),
                                                                                        .foregroundColor: Look.Token.ink.color]))]
        if words.count == 4 {
            pieces.append(.dot)
            let parts = words[1].components(separatedBy: "⌥")
            for (index, part) in parts.enumerated() {
                if index > 0 { pieces.append(.key(NSAttributedString(string: "⌥", attributes: keyFace))) }
                pieces.append(.words(NSAttributedString(string: part.trimmingCharacters(in: .whitespaces), attributes: quiet)))
            }
        }
        pieces += [.dot, .key(NSAttributedString(string: words[words.count - 2], attributes: keyFace)),
                   .words(NSAttributedString(string: words[words.count - 1], attributes: quiet))]
        // A key and the words around it in one span sit a space apart (4 points); spans and dots sit 9 apart.
        func width(_ piece: Piece) -> CGFloat {
            switch piece {
            case .words(let text): ceil(text.size().width)
            case .key(let text): ceil(text.size().width) + 10
            case .dot: 3
            }
        }
        let gaps = pieces.indices.map { index -> CGFloat in
            guard index + 1 < pieces.count else { return 0 }
            switch (pieces[index], pieces[index + 1]) {
            case (.key, .words), (.words, .key): return 4
            default: return 9
            }
        }
        let boxWidth = 12 + 13 + 9 + zip(pieces, gaps).reduce(0) { $0 + width($1.0) + $1.1 } + 14
        let p = progress(0.45, since: arrived, Look.out)
        let box = CGRect(x: (bounds.width - boxWidth) / 2, y: 14 - 56 * (1 - p), width: boxWidth, height: 34)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(min(1, p * 1.5))
        Look.drawFloat(box, radius: 17, fill: .glass, ring: false, appearance: effectiveAppearance)
        Look.Token.glass.color.setFill()
        NSBezierPath(roundedRect: box, xRadius: 17, yRadius: 17).fill()
        var x = box.minX + 12
        let mid = box.midY
        NSImage.symbol("scope", 12, .medium).draw(Look.Token.ink.color, flippedIn: CGRect(x: x, y: mid - 6.5, width: 13, height: 13))
        x += 13 + 9
        for (index, piece) in pieces.enumerated() {
            switch piece {
            case .words(let text):
                text.draw(at: CGPoint(x: x, y: mid - text.size().height / 2))
            case .key(let text):
                let size = text.size(), cap = CGRect(x: x, y: mid - (ceil(size.height) + 6) / 2, width: width(piece), height: ceil(size.height) + 6)
                Look.Token.sel.color.setFill()
                NSBezierPath(roundedRect: cap, xRadius: 5, yRadius: 5).fill()
                text.draw(at: CGPoint(x: cap.minX + (cap.width - size.width) / 2, y: cap.minY + 3))
            case .dot:
                Look.Token.ink3.color.setFill()
                NSBezierPath(ovalIn: CGRect(x: x, y: mid - 1.5, width: 3, height: 3)).fill()
            }
            x += width(piece) + gaps[index]
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func removeFromSuperview() {
        timer?.invalidate()
        timer = nil
        super.removeFromSuperview()
    }
}
