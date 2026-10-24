// The sign of something: four soft corner brackets and two tall low eyes, the eyes saying an assistant's state. One
// drawing serves the sticker, the panel, the sidebar, menus, point frames and the arrival: a view that breathes and
// blinks under Calm motion, a still image, the mini eyes (a 16x10 template for menus and the rail) and the hard
// "portée" shadow of what a person grabs. It is all drawn in draw(_:), so cacheDisplay pictures it as the screen does.
import AppKit

enum Sign {
    /// An assistant's state, as its eyes say it. What no source gives is `unknown`, drawn hollow, never as `listen`.
    enum State: String, CaseIterable {
        case listen, think, wait, done, sleep, limit, unknown

        /// The word VoiceOver reads and a tooltip shows.
        var word: String {
            switch self {
            case .listen: "Ready"
            case .think: "Working"
            case .wait: "Waiting for you"
            case .done: "Done"
            case .sleep: "Asleep"
            case .limit: "Stopped"
            case .unknown: "Unknown"
            }
        }

        /// Whether it moves under Calm motion: limit and unknown stay still, as the mockup's do.
        var moves: Bool { self != .limit && self != .unknown }
    }

    /// What VoiceOver reads of a sign in `state`, smiling with `joy`: the smile is an expression, not a state, so the
    /// state is still said as it is ("Ready, smiling"), never as Done.
    static func words(_ state: State, joy: Bool) -> String { joy ? "\(state.word), smiling" : state.word }

    /// The proportions, as fractions of the sign's side: the corner's arm, the stroke (in a 100-unit corner, as the
    /// mockup's SVG has it), the eye unit, and the frame's inset. Emi's defaults: arm .31, stroke 35, eye .125. The
    /// joy eye's width and stroke are in eye units; the welcome's big sticker draws them 1.5 and .34.
    struct Geometry: Equatable {
        var arm: CGFloat = 0.31, stroke: CGFloat = 35, eye: CGFloat = 0.125, inset: CGFloat = 0.06
        var joy: CGFloat = 1.3, joyStroke: CGFloat = 0.46

        /// A corner bracket in a 100-unit square, the mockup's path: up the left side, round the top-left, along.
        static let corner: CGPath = {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 13, y: 92))
            path.addLine(to: CGPoint(x: 13, y: 61))
            path.addQuadCurve(to: CGPoint(x: 61, y: 13), control: CGPoint(x: 13, y: 13))
            path.addLine(to: CGPoint(x: 92, y: 13))
            return path
        }()

        /// The rectangle of corner `index` (0 top-left, then clockwise) in a sign of side `side`, top-left origin.
        func cornerRect(_ index: Int, side: CGFloat) -> CGRect {
            let box = CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: inset * side, dy: inset * side), a = arm * side
            let x = index == 1 || index == 2 ? box.maxX - a : box.minX, y = index >= 2 ? box.maxY - a : box.minY
            return CGRect(x: x, y: y, width: a, height: a)
        }

        /// The two eyes' rectangles of `state` at rest in a sign of side `side`, top-left origin.
        func eyes(_ state: State, side: CGFloat) -> [CGRect] {
            let e = eye * side, (w, h) = state == .done ? (joy, joy) : Sign.eyeSize(state), gap = 1.4 * e
            let face = Sign.faceShift(state)
            let cx = side / 2 + face.x * e, cy = side / 2 + face.y * e + 0.45 * e
            return [-1, 1].map { (side: CGFloat) in
                CGRect(x: cx + side * (gap + w * e) / 2 - w * e / 2, y: cy - h * e / 2, width: w * e, height: h * e)
            }
        }
    }

    /// An eye's width and height in eye units (the joy eye's are Geometry.joy): tall ovals, dashes when working, bars
    /// asleep.
    static func eyeSize(_ state: State) -> (CGFloat, CGFloat) {
        switch state {
        case .think: (1.35, 0.34)
        case .sleep: (1.2, 0.22)
        case .unknown: (1.05, 1.3)
        default: (0.88, 1.56)
        }
    }

    /// Where the face looks, in eye units: up and right while it waits for the person, down when stopped.
    static func faceShift(_ state: State) -> CGPoint {
        state == .wait ? CGPoint(x: 0.55, y: -0.3) : state == .limit ? CGPoint(x: 0, y: 0.5) : .zero
    }

    /// A moment of the sign's motion: the frame's scale and lift (a fraction of the side), the eyes' openness and
    /// sideways look (in eye units), the sleeping z's progress, and the seconds since the sign arrived.
    struct Pose: Equatable {
        var scale: CGFloat = 1, lift: CGFloat = 0, open: CGFloat = 1, look: CGFloat = 0, z: CGFloat = 1
        /// How far the eyes lean, in points, toward where a dragged sticker moves.
        var lean = CGSize.zero
        var arrived: TimeInterval = .infinity
        static let rest = Pose()
    }

    /// The pose of `state` `t` seconds after it began (`arrived` seconds after the sign arrived, if it did): the
    /// mockup's keyframes. Reduced motion gives the pose at rest, whatever the time.
    static func pose(_ state: State, at t: TimeInterval, arrived: TimeInterval? = nil, motion: Look.Motion) -> Pose {
        guard motion == .calm else { return .rest }
        func wave(_ period: Double) -> CGFloat { CGFloat(1 - cos(2 * Double.pi * t / period)) / 2 }
        var pose = Pose(arrived: arrived ?? .infinity)
        switch state {
        case .listen, .wait: pose.scale = 1 + 0.025 * wave(6)
        case .think: pose.scale = 1 + 0.045 * wave(1.4); pose.look = -0.25 + 0.5 * wave(1.6)
        case .done where t < 0.7:
            let hop = CGFloat(t < 0.28 ? t / 0.28 : (0.7 - t) / 0.42)
            pose.scale = 1 + 0.03 * hop; pose.lift = -0.06 * hop
        case .sleep: pose.z = CGFloat(t.truncatingRemainder(dividingBy: 2.8) / 2.8)
        default: break
        }
        if state == .listen || state == .wait || state == .done {
            let p = t.truncatingRemainder(dividingBy: 7) / 7
            pose.open = p < 0.95 ? 1 : CGFloat(p < 0.965 ? 1 - 0.9 * (p - 0.95) / 0.015 : 0.1 + 0.9 * (p - 0.965) / 0.035)
        }
        return pose
    }

    /// Draws the sign of `state` in `rect` (square, centered when it is not), in the current graphics context,
    /// whose y grows downward when `flipped`; with `joy`, its eyes smile (the mockup's x-joy) whatever the state.
    /// Colours resolve in the current drawing appearance.
    static func draw(_ state: State, joy: Bool = false, pose: Pose = .rest, geometry g: Geometry = Geometry(), in rect: CGRect, flipped: Bool) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        let s = min(rect.width, rect.height), e = g.eye * s
        func out(_ p: Double) -> CGFloat { let q = 1 - min(max(p, 0), 1); return CGFloat(1 - q * q * q) }
        c.saveGState()
        c.translateBy(x: rect.midX - s / 2, y: flipped ? rect.midY - s / 2 : rect.midY + s / 2)
        if !flipped { c.scaleBy(x: 1, y: -1) }
        // The frame: four corners, scaled and lifted with the breath or the hop, each arriving on its own.
        c.saveGState()
        c.translateBy(x: s / 2, y: s / 2 + pose.lift * s)
        c.scaleBy(x: pose.scale, y: pose.scale)
        c.translateBy(x: -s / 2, y: -s / 2)
        c.setStrokeColor(color(.ink))
        c.setLineWidth(g.stroke)
        c.setLineCap(.round)
        c.setLineJoin(.round)
        for index in 0..<4 {
            let r = g.cornerRect(index, side: s), arrival = out((pose.arrived - 0.1 * Double(index)) / 0.7)
            var angle = CGFloat(index) * 90, shift = CGPoint.zero, alpha: CGFloat = state == .unknown ? 0.38 : 1
            if state == .wait, index == 1 { angle = 78; shift = CGPoint(x: -0.08, y: -0.18) }
            if state == .sleep, index < 2 { angle = index == 0 ? 8 : 82; shift = CGPoint(x: 0, y: 0.1) }
            if state == .limit, index == 2 { alpha = 0.12 }
            c.saveGState()
            c.setAlpha(alpha * arrival)
            c.translateBy(x: r.midX + shift.x * r.width, y: r.midY + shift.y * r.width)
            c.rotate(by: angle * CGFloat.pi / 180)
            c.scaleBy(x: (1.6 - 0.6 * arrival) * r.width / 100, y: (1.6 - 0.6 * arrival) * r.width / 100)
            c.translateBy(x: -50, y: -50)
            c.addPath(Geometry.corner)
            c.strokePath()
            c.restoreGState()
        }
        c.restoreGState()
        // The face: two eyes, popping in after the corners when the sign arrives.
        let face = joy ? State.done : state, pop = out((pose.arrived - 0.55) / 0.5), eyes = g.eyes(face, side: s)
        c.setAlpha(pop)
        c.translateBy(x: s / 2 + pose.lean.width, y: eyes[0].midY + pose.lean.height)
        c.scaleBy(x: 0.3 + 0.7 * pop, y: (0.3 + 0.7 * pop) * pose.open)
        c.translateBy(x: -s / 2 + pose.look * e, y: -eyes[0].midY)
        for eye in eyes { drawEye(face, eye, e: e, stroke: g.joyStroke, in: c) }
        if state == .sleep, pose.z < 1 {
            // The z drifts up and right from the face's corner, appearing then fading, as the mockup's does.
            let size = 1.5 * e, p = pose.z, faceTop = eyes[0].midY - 0.45 * e - eyes[0].height / 2
            let fade = p < 0.3 ? 0.85 * p / 0.3 : 0.85 * (1 - (p - 0.3) / 0.7)
            let origin = CGPoint(x: eyes[1].maxX + 0.6 * size * p, y: faceTop - 0.7 * eyes[0].height + size * (0.3 - 1.2 * p))
            c.setAlpha(fade * pop)
            drawZ(CGRect(origin: origin, size: CGSize(width: size * 0.6, height: size * 0.6)), color(.ink2), in: c)
        }
        c.restoreGState()
    }

    /// One eye of `state` in `r`: filled, hollow when unknown, an arc when done (the smile), red when stopped.
    static func drawEye(_ state: State, _ r: CGRect, e: CGFloat, stroke: CGFloat, in c: CGContext) {
        switch state {
        case .done:
            // The joy eye, as the mockup's .x-joy: a round eye's top and right borders, turned 45°, which is a soft arc
            // over the eye, the box moved down 30% of its height; the border at least 2 points, so it reads at the
            // sticker's size. In this context y grows downward, so the arc from π to 2π is the upper half.
            let side = r.width, thick = min(max(2, stroke * e), side / 2)
            c.saveGState()
            c.setStrokeColor(color(.eyes))
            c.setLineWidth(thick)
            c.setLineCap(.butt)
            c.addArc(center: CGPoint(x: r.midX, y: r.midY + 0.3 * side), radius: (side - thick) / 2, startAngle: CGFloat.pi, endAngle: 2 * CGFloat.pi, clockwise: false)
            c.strokePath()
            c.restoreGState()
        case .unknown:
            let line = min(1.5, r.width * 0.3)
            c.setStrokeColor(color(.eyes))
            c.setLineWidth(line)
            c.strokeEllipse(in: r.insetBy(dx: line / 2, dy: line / 2))
        case .think, .sleep:
            c.setFillColor(color(.eyes).copy(alpha: state == .sleep ? 0.75 : 1) ?? color(.eyes))
            c.addPath(CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil))
            c.fillPath()
        default:
            c.setFillColor(color(state == .limit ? .bad : .eyes))
            c.fillEllipse(in: r)
        }
    }

    /// A sleeping z in `r`, stroked rather than set in type, so it stays crisp at the size of an eye.
    static func drawZ(_ r: CGRect, _ ink: CGColor, in c: CGContext) {
        c.setStrokeColor(ink)
        c.setLineWidth(max(0.8, r.width * 0.2))
        c.setLineCap(.round)
        c.setLineJoin(.round)
        c.addLines(between: [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                             CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)])
        c.strokePath()
    }

    /// `token` as the current drawing appearance resolves it.
    static func color(_ token: Look.Token) -> CGColor {
        (token.color.usingColorSpace(.sRGB) ?? token.color).cgColor
    }

    /// The still sign of `state`, `side` points square, resolving its colours wherever it is drawn; VoiceOver reads
    /// the state's word.
    static func image(_ state: State, side: CGFloat, geometry: Geometry = Geometry()) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            draw(state, geometry: geometry, in: rect, flipped: true)
            return true
        }
        image.accessibilityDescription = state.word
        return image
    }

    /// The mini eyes of `state`, 16x10 points, for menus and the rail: still (menus cannot animate), a template image
    /// by default so the menu colours it; with `template` false, in the identity's colours (red when stopped); with
    /// `joy`, the arcs of a smile, VoiceOver still saying the state.
    static func miniEyes(_ state: State, template: Bool = true, joy: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 10), flipped: true) { _ in
            let state = joy ? State.done : state
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            let ink = template ? CGColor(gray: 0, alpha: 1) : color(state == .limit ? .bad : .eyes)
            var eyes = [CGRect(x: 3, y: 1.9, width: 3.5, height: 6.2), CGRect(x: 9.5, y: 1.9, width: 3.5, height: 6.2)]
            switch state {
            case .think: eyes = [CGRect(x: 1.5, y: 2.8, width: 5, height: 2), CGRect(x: 9.5, y: 5.2, width: 5, height: 2)]
            case .wait: eyes = eyes.map { $0.offsetBy(dx: -1.5, dy: -1.6) }
            case .done: eyes = [CGRect(x: 0.5, y: 3.5, width: 6, height: 4.2), CGRect(x: 9.5, y: 3.5, width: 6, height: 4.2)]
            case .sleep: eyes = [CGRect(x: 1.9, y: 5.9, width: 4.6, height: 1.4), CGRect(x: 9.5, y: 5.9, width: 4.6, height: 1.4)]
            case .limit: eyes[1] = eyes[1].offsetBy(dx: 0, dy: 1.4)
            default: break
            }
            c.setFillColor(ink)
            c.setStrokeColor(ink)
            for r in eyes {
                switch state {
                case .done:
                    // An arch: the top of the eye's box drawn with its sides, open at the bottom.
                    c.setLineWidth(1.6)
                    c.move(to: CGPoint(x: r.minX + 0.8, y: r.maxY))
                    c.addArc(tangent1End: CGPoint(x: r.minX + 0.8, y: r.minY + 0.8), tangent2End: CGPoint(x: r.midX, y: r.minY + 0.8), radius: 2.2)
                    c.addArc(tangent1End: CGPoint(x: r.maxX - 0.8, y: r.minY + 0.8), tangent2End: CGPoint(x: r.maxX - 0.8, y: r.maxY), radius: 2.2)
                    c.addLine(to: CGPoint(x: r.maxX - 0.8, y: r.maxY))
                    c.strokePath()
                case .unknown:
                    c.setAlpha(0.75)
                    c.setLineWidth(1.3)
                    c.strokeEllipse(in: r.insetBy(dx: 0.65, dy: 0.65))
                case .think, .sleep:
                    c.setAlpha(state == .sleep ? 0.38 : 1)
                    c.addPath(CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil))
                    c.fillPath()
                default: c.fillEllipse(in: r)
                }
            }
            c.setAlpha(1)
            if state == .wait {
                // The dot of a waiting request, cut out of the eye it touches so it reads at this size.
                let dot = CGRect(x: 12.25, y: 0, width: 3.75, height: 3.75)
                c.setBlendMode(.clear)
                c.fillEllipse(in: dot.insetBy(dx: -1.1, dy: -1.1))
                c.setBlendMode(.normal)
                c.setFillColor(template ? ink : color(.ink))
                c.fillEllipse(in: dot)
            }
            if state == .sleep { drawZ(CGRect(x: 12.6, y: 0.4, width: 2.8, height: 2.8), template ? ink : color(.ink3), in: c) }
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = words(state, joy: joy)
        return image
    }

    // MARK: The hard shadow of what a person grabs

    /// How far the hard shadow falls: small, at rest, and held or under the pointer.
    enum Lift: CGFloat { case small = 2, rest = 3, held = 5 }

    /// Draws a grabbed thing's surface in `rect`, rounded by `radius`, with the hard offset shadow ("portée"): a
    /// 1.5 pt ring of ink and its solid copy `lift` points down and right. Only for what a person grabs (the sticker,
    /// a template card on hover), never for inputs, composers or primary buttons: Emi dislikes it there.
    static func grab(_ rect: CGRect, radius: CGFloat, lift: Lift = .rest, surface: Look.Token = .bg2) {
        let flipped = NSGraphicsContext.current?.isFlipped ?? false
        let ring = rect.insetBy(dx: -1.5, dy: -1.5), drop = ring.offsetBy(dx: lift.rawValue, dy: flipped ? lift.rawValue : -lift.rawValue)
        let night = Look.isDark(NSAppearance.currentDrawing())
        let ink = (Look.Token.ink.color.usingColorSpace(.sRGB) ?? .black).withAlphaComponent(night ? (lift == .held ? 0.92 : 0.88) : 1)
        ink.setFill()
        NSBezierPath(roundedRect: drop, xRadius: radius + 1.5, yRadius: radius + 1.5).fill()
        NSBezierPath(roundedRect: ring, xRadius: radius + 1.5, yRadius: radius + 1.5).fill()
        (surface.color.usingColorSpace(.sRGB) ?? .white).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
}

/// The sign as a view: it breathes, blinks, scans or sleeps by its state under Calm motion, at up to 30 frames a
/// second while it is in a window, and holds still at rest under Reduced motion or the system's Reduce Motion.
final class SignView: NSView {
    /// The state its eyes say; setting it restarts that state's motion.
    var state: Sign.State { didSet { began = clock(); refresh() } }
    /// Whether its eyes smile (the mockup's x-joy): an expression over the state, which it does not change.
    var joy = false { didSet { if joy != oldValue { began = clock(); refresh() } } }
    var geometry = Sign.Geometry() { didSet { needsDisplay = true } }
    /// How far the eyes lean, in points, while a drag moves the sticker.
    var lean = CGSize.zero { didSet { if lean != oldValue { needsDisplay = true } } }
    /// The person's Motion choice; the system's Reduce Motion is folded in by `systemReduces`.
    var motion: Look.Motion = .calm { didSet { refresh() } }
    /// What VoiceOver calls it before its state's word ("something, Ready"); empty makes it decoration.
    var name: String? { didSet { setAccessibilityElement(name != "") } }
    /// Seams for tests: the clock in seconds and the system's Reduce Motion.
    var clock: () -> TimeInterval = { CACurrentMediaTime() }
    var systemReduces: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var began: TimeInterval = 0, arrival: TimeInterval?
    private var link: CADisplayLink?

    init(_ state: Sign.State = .listen, side: CGFloat = 44) {
        self.state = state
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        began = clock()
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    /// The motion it plays: the person's choice, Reduced whenever the system reduces motion.
    var playing: Look.Motion { Look.motion(motion, systemReduces: systemReduces()) }

    /// The pose it draws now.
    var pose: Sign.Pose {
        let now = clock()
        var pose = Sign.pose(joy ? .done : state, at: now - began, arrived: arrival.map { now - $0 }, motion: playing)
        pose.lean = lean
        return pose
    }

    /// Whether it is moving: in a window, under Calm motion, with a state that moves or an arrival not yet over.
    var animating: Bool {
        window != nil && playing == .calm && (state.moves || arrival.map { clock() - $0 < 1.05 } == true)
    }

    /// Plays the arrival: the corners land one after the other, then the face pops in. Under Reduced motion it is
    /// simply there.
    func arrive() {
        arrival = playing == .calm ? clock() : nil
        refresh()
    }

    override func draw(_ dirtyRect: NSRect) {
        Sign.draw(state, joy: joy, pose: pose, geometry: geometry, in: bounds, flipped: true)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refresh()
    }

    override func accessibilityLabel() -> String? {
        let word = Sign.words(state, joy: joy)
        return name.map { $0.isEmpty ? word : "\($0), \(word)" } ?? word
    }

    private func refresh() {
        needsDisplay = true
        if animating, link == nil {
            let link = displayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 30)
            link.add(to: .main, forMode: .common)
            self.link = link
        } else if !animating {
            link?.invalidate()
            link = nil
        }
    }

    @objc private func tick() {
        if animating { needsDisplay = true } else { refresh() }
    }
}
