// The arrival: a space just made comes out of what made it. On the glass, over a still of the page left, four corners
// and the eyes stand on New Space's sign (or a frame on the template card Use pressed), then grow to the center's
// edges, 14 points in, in 820 ms on the douce curve, their stroke thinning and the eyes going to the corner as they
// fade; then it all fades and the space is there, its row ringed a moment in the sidebar, and only then its rights
// sheet. Reduced motion skips the growth: the still fades. A new opening ends an arrival still playing. It is drawn in
// draw(_:), so cacheDisplay pictures it. The first-launch film (Film.swift) grows the same frame to the window's edges.
import AppKit
import SwiftUI

final class Arrival: NSView {
    /// How far in from the center's edges the frame grows, how long it grows, and how long it then fades.
    static let inset: CGFloat = 14, grows: TimeInterval = 0.82, fades: TimeInterval = 0.45
    /// The stroke grown, in a 100-unit corner, and the eyes' place then, from the frame's top left; the eyes fade in
    /// this many seconds.
    static let thin: CGFloat = 16, corner = CGPoint(x: 46, y: 40), blinks: TimeInterval = 0.35

    /// Where the frame is at a moment: its rectangle, its corners' arm and stroke, the eyes' center and opacity.
    struct Shape: Equatable {
        var rect: CGRect, arm: CGFloat, stroke: CGFloat, face: CGPoint, eyes: CGFloat
    }

    /// Where it starts: a rectangle in the center, its corners' arm and stroke, and whether the eyes come (the sign's
    /// do, a card has none).
    struct Start: Equatable {
        var rect: CGRect, arm: CGFloat, stroke: CGFloat, face: Bool
    }

    let start: Start
    /// The page left, and where it was: drawn under the frame until it fades.
    private let still: NSBitmapImageRep?, stillRect: CGRect
    /// How far it grew, from 0 to 1, in time: the curve is applied in `shape`.
    var progress: CGFloat = 0 { didSet { needsDisplay = true } }
    private(set) var playing = false
    /// Whether the frame stays drawn once grown, until it fades: the film's frame holds at the window's edges.
    var holds = false { didSet { needsDisplay = true } }
    private var timer: Timer?
    /// How long it grows: `grows`, or the film's at its pace.
    var span = Arrival.grows
    /// The clock in seconds; a seam for tests.
    var clock: () -> TimeInterval = { CACurrentMediaTime() }

    /// The frame's shape `progress` of the way (in time) from `start` to `room` inset by `inset`.
    static func shape(_ start: Start, to room: CGRect, inset: CGFloat = Arrival.inset, progress: CGFloat) -> Shape {
        let p = min(max(progress, 0), 1), e = CGFloat(Look.douce.value(at: Double(p)))
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * e }
        let end = room.insetBy(dx: inset, dy: inset), from = start.rect
        let rect = CGRect(x: mix(from.minX, end.minX), y: mix(from.minY, end.minY),
                          width: mix(from.width, end.width), height: mix(from.height, end.height))
        let face = CGPoint(x: rect.minX + mix(from.width / 2, corner.x), y: rect.minY + mix(from.height / 2, corner.y))
        let eyes = start.face ? max(0, 1 - p * CGFloat(grows / blinks)) : 0
        return Shape(rect: rect, arm: start.arm, stroke: mix(start.stroke, thin), face: face, eyes: eyes)
    }

    /// The arrival of the space `name` that `shell` is about to open, laid on its glass over a still of the page shown:
    /// from New Space's sign when that page is the one the space was built from, or from the card Use pressed on the
    /// templates; nil for any other opening.
    static func made(_ name: String, in shell: Shell) -> Arrival? {
        let glass = shell.glass
        guard let host = shell.center.subviews.first(where: { $0 is NSHostingView<BlankView> || $0 is NSHostingView<GalleryView> }) else { return nil }
        let blank = (host as? NSHostingView<BlankView>)?.rootView
        let gallery = blank?.gallery ?? (host as? NSHostingView<GalleryView>)?.rootView.model
        var start: Start, sign: NSView?
        if let used = gallery?.used, name == used || name.hasPrefix("\(used)-"), let card = gallery?.drawn[used] {
            // The card's frame, in the page's coordinates as SwiftUI gave them, without a face.
            let rect = glass.convert(host.convert(card, to: nil), from: nil)
            (start, sign) = (Start(rect: rect, arm: min(rect.width, rect.height) * 0.3, stroke: 22, face: false), nil)
        } else if let blank, let built = shell.assistant.sessions[.space(name)], ObjectIdentifier(built) == blank.opened,
                  let hero = Arrival.sign(in: host) {
            let g = hero.geometry, side = hero.bounds.width
            start = Start(rect: glass.convert(hero.bounds.insetBy(dx: g.inset * side, dy: g.inset * side), from: hero),
                          arm: g.arm * side, stroke: g.stroke, face: true)
            sign = hero
        } else {
            return nil
        }
        // The page's still without the sign, which the frame takes from there.
        sign?.isHidden = true
        let still = host.bitmapImageRepForCachingDisplay(in: host.bounds)
        still.map { host.cacheDisplay(in: host.bounds, to: $0) }
        sign?.isHidden = false
        // The glass is not flipped and the arrival is: its rectangles are turned over once, here.
        let height = glass.bounds.height
        func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: height - r.maxY, width: r.width, height: r.height) }
        start.rect = flip(start.rect)
        let arrival = Arrival(start: start, still: still, stillRect: flip(host.convert(host.bounds, to: glass)))
        glass.hold(arrival)
        arrival.frame = glass.bounds
        return arrival
    }

    /// Opens `view` after `arrival` played, and then only if `isCurrent` still says it is the space shown, so the
    /// level sheet comes once the space is there; without an arrival, at once.
    static func open(_ view: SpaceView, after arrival: Arrival?, library: Library, motion: Look.Motion,
                     isCurrent: @escaping () -> Bool) {
        guard let arrival else { return view.open() }
        arrival.play(view.space.name, library: library, motion: motion) { [weak view] in
            if let view, isCurrent() { view.open() }
        }
    }

    /// Ends any arrival on `shell`'s glass: the person went elsewhere while it played.
    static func end(in shell: Shell) {
        shell.glass.subviews.filter { $0 is Arrival }.forEach { $0.removeFromSuperview() }
    }

    /// The sign of the page in `view`: New Space's, the only one that lands there.
    static func sign(in view: NSView) -> SignView? {
        for sub in view.subviews {
            if let sign = sub as? SignView, sign.name == "something" { return sign }
            if let sign = Arrival.sign(in: sub) { return sign }
        }
        return nil
    }

    init(start: Start, still: NSBitmapImageRep?, stillRect: CGRect) {
        (self.start, self.still, self.stillRect) = (start, still, stillRect)
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    /// It never takes a click: what is under it answers, as on the rest of the glass.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Where the frame grows to, and how far in: the center under the toolbar, or `reach` when it is set (the film's
    /// whole window).
    var reach: (room: CGRect, inset: CGFloat)?
    var room: CGRect {
        if let reach { return reach.room }
        let top = superview?.superview?.safeAreaInsets.top ?? 0
        return CGRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
    }

    var shape: Shape { Arrival.shape(start, to: room, inset: reach?.inset ?? Arrival.inset, progress: progress) }

    override func draw(_ dirtyRect: NSRect) {
        still?.draw(in: stillRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        guard progress < 1 || playing || holds, let c = NSGraphicsContext.current?.cgContext else { return }
        let shape = shape
        PointOverlay.corners(shape.rect, ink: .ink, arm: shape.arm, width: shape.stroke, halo: false)
        guard shape.eyes > 0 else { return }
        // The sign's eyes at rest, Ready, as the mockup's frame carries them, around the face's center.
        let g = Sign.Geometry(), side = start.rect.width / (1 - 2 * g.inset), eyes = g.eyes(.listen, side: side)
        let shift = CGPoint(x: shape.face.x - side / 2, y: shape.face.y - eyes[0].midY)
        c.setAlpha(shape.eyes)
        for eye in eyes { Sign.drawEye(.listen, eye.offsetBy(dx: shift.x, dy: shift.y), e: g.eye * side, stroke: g.joyStroke, in: c) }
    }

    /// Grows the frame, then fades it and the still, and calls `arrived` once it is gone; under Reduced `motion`, only
    /// the still fades. The row of `name` in `library` is ringed meanwhile, and let go 1.6 s after the arrival is gone
    /// (the ring's own time), so the next arrival of the same name rings it again: counted from the start, a busy Mac
    /// playing slowly let it go before the space was there.
    func play(_ name: String, library: Library, motion: Look.Motion, arrived: @escaping () -> Void) {
        library.fresh = name
        ringed = (name, library)
        guard Look.motion(motion) == .calm, start.rect.width > 0 else {
            progress = 1
            return fade(0.25, arrived)
        }
        grow { [weak self] in self?.fade(Arrival.fades, arrived) }
    }

    /// Grows the frame in `span` seconds, and calls `grown` once it is at its end.
    func grow(_ grown: @escaping () -> Void) {
        playing = true
        let began = clock()
        timer = .frames(1.0 / 60) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return false }
                self.progress = min(1, CGFloat((self.clock() - began) / self.span))
                guard self.progress >= 1 else { return true }
                self.playing = false
                grown()
                return false
            }
        }
    }

    /// Fades it out in `duration`, then takes it off its layer and calls `arrived`.
    func fade(_ duration: TimeInterval, _ arrived: @escaping () -> Void) {
        Look.animate(duration, Look.douce, { [weak self] in self?.moving.alphaValue = 0 }, done: { [weak self] in
            self?.removeFromSuperview()
            arrived()
        })
    }

    /// The row ringed while it plays.
    private var ringed: (name: String, library: Library)?

    override func removeFromSuperview() {
        timer?.invalidate()
        if let (name, library) = ringed {
            ringed = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak library] in
                if library?.fresh == name { library?.fresh = nil }
            }
        }
        super.removeFromSuperview()
    }
}
