// The window's header, glass as far as a page in a locked frame allows: the band behind the toolbar, and two of the
// toolbar's items, "Jump to a space or an action" and the panel's button. No page runs under the band, whose scroller
// lives inside its frame: the band wears a picture of the page's top rows, stretched, saturated and tinted. At rest it
// looks as the glass would; while the page scrolls it stays as it was, and takes the new colours when the page stops.
import AppKit
import CoreImage
import WebKit

/// The band behind the toolbar, across the window, with its lower edge. It takes no click: the toolbar has them. The
/// strip is nil off a space: the tint then lies on the window's background.
final class HeaderBand: NSView {
    /// How much of the page's top the picture holds, and how wide it is taken: the stretch is the blur.
    static let rows: CGFloat = 12, wide: CGFloat = 64
    private static let saturate = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])

    /// The page's top rows, saturated.
    private(set) var strip: NSImage?
    /// Whether it lies over the page, as Page Full Screen brings it back: it then casts the mockup's soft shadow.
    var over = false {
        didSet { layer?.shadowOpacity = over ? 0.35 : 0 }
    }
    /// Called when the appearance changed: a page's colours may follow it.
    var changed: () -> Void = {}
    private var waiting: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowRadius = 15
        layer?.shadowOffset = CGSize(width: 0, height: -12)
    }

    required init?(coder: NSCoder) { nil }

    /// Wears `image`, the page's top rows as they are; nil takes the picture off.
    func wear(_ image: NSImage?) {
        strip = image.flatMap(HeaderBand.saturated)
        needsDisplay = true
    }

    /// Calls `read` in a moment, in place of what waited: WebKit paints a new width a little after the view has it, and
    /// the part it has not painted yet would come out empty.
    func soon(_ read: @escaping () -> Void) {
        waiting?.invalidate()
        waiting = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in read() }
    }

    /// `image` at the mockup's saturation, nil when it cannot be made: the band then lies on the background.
    private static func saturated(_ image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let filter = CIFilter(name: "CIColorControls", parameters: [kCIInputImageKey: CIImage(cgImage: cg), kCIInputSaturationKey: 1.9]),
              let out = filter.outputImage, let made = saturate.createCGImage(out, from: out.extent) else { return nil }
        return NSImage(cgImage: made, size: NSSize(width: made.width, height: made.height))
    }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(rect: bounds.insetBy(dx: 16, dy: 16), transform: nil)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        changed()
    }

    /// Night darkens what is behind first, then tints; `cacheDisplay` draws all of it, so the pictures prove it.
    override func draw(_ dirtyRect: NSRect) {
        let night = Look.isDark(effectiveAppearance)
        Look.Token.bg.color.setFill()
        bounds.fill()
        if let strip {
            NSGraphicsContext.current?.imageInterpolation = .high
            strip.draw(in: bounds)
            if night {
                NSColor.black.withAlphaComponent(0.5).setFill()
                bounds.fill(using: .sourceOver)
            }
        }
        Look.Token.side.color.withAlphaComponent(night ? 0.74 : 0.72).setFill()
        bounds.fill(using: .sourceOver)
        Look.Token.ink.color.withAlphaComponent(0.16).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill(using: .sourceOver)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The header's middle: a button that opens ⌘P, drawn like a field. What waits while the sidebar is closed comes as a
/// yellow dot and a count, a small pop when it grows. ⌘P's Needs You is the palette's.
final class JumpPill: NSControl {
    static let words = "Jump to a space or an action"
    /// Its width, in a window with room and in a narrow one.
    static func width(narrow: Bool) -> CGFloat { (narrow ? 176 : 296) * Look.scale.size.factor }

    private let count = WaitMark()
    private var lit = false {
        didSet { needsDisplay = true }
    }
    private lazy var wide = widthAnchor.constraint(equalToConstant: JumpPill.width(narrow: false))
    private lazy var high = heightAnchor.constraint(equalToConstant: 28 * Look.scale.size.factor)
    /// The app's motion setting.
    var motion: () -> Look.Motion = { .calm }
    /// What waits, 0 for nothing or while the sidebar shows.
    private(set) var waiting = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        (count.isHidden, action) = (true, #selector(App.showPalette(_:)))
        addSubview(count)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([wide, high])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(JumpPill.words)
    }

    required init?(coder: NSCoder) { nil }

    /// Takes the width for a window that is `narrow` or not, at the interface size.
    func fit(narrow: Bool) {
        (wide.constant, high.constant) = (JumpPill.width(narrow: narrow), 28 * Look.scale.size.factor)
        needsLayout = true
        needsDisplay = true
    }

    func show(waiting now: Int) {
        guard now != waiting else { return }
        let grew = now > waiting
        waiting = now
        count.number = now
        count.isHidden = now == 0
        let say = "\(now) \(now == 1 ? "needs" : "need") you"
        toolTip = now > 0 ? Keys.tooltip("palette", say) : nil
        setAccessibilityLabel(now > 0 ? "\(JumpPill.words). \(say)" : JumpPill.words)
        needsLayout = true
        needsDisplay = true
        layoutSubtreeIfNeeded()
        if grew { count.pop(Look.duration(0.42, Look.motion(motion()))) }
    }

    private var key: NSAttributedString {
        NSAttributedString(string: Keys.shown("palette"), attributes: [.font: Look.font(.ui, size: 10.5, weight: .medium), .foregroundColor: tone])
    }
    /// The grey of the field's words, ink at less strength, as everything on the glass; under the pointer, one deeper.
    private var tone: NSColor { Look.Token.ink.color.withAlphaComponent(lit ? 0.76 : 0.62) }

    override func layout() {
        super.layout()
        let size = count.fittingSize, room = key.size().width
        count.frame = NSRect(x: bounds.width - 10 * Look.scale.size.factor - room - 7 - size.width, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let k = Look.scale.size.factor, shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        Look.Token.ink.color.withAlphaComponent(0.06).setFill()
        shape.fill()
        (lit ? tone : Look.Token.ink.color.withAlphaComponent(0.16)).setStroke()
        shape.stroke()
        let glass = NSImage.symbol("magnifyingglass", 11 * k, .medium).tinted(tone)
        glass.draw(in: NSRect(x: 10 * k, y: (bounds.height - glass.size.height) / 2, width: glass.size.width, height: glass.size.height))
        let shortcut = key, width = shortcut.size().width, right = bounds.width - 10 * k - width
        shortcut.draw(at: NSPoint(x: right, y: (bounds.height - shortcut.size().height) / 2))
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let words = NSAttributedString(string: JumpPill.words, attributes: [.font: Look.font(.ui, size: 12.5), .foregroundColor: tone, .paragraphStyle: style])
        let start = (10 + 7) * k + glass.size.width, end = (waiting > 0 ? count.frame.minX : right) - 7, height = ceil(words.size().height)
        words.draw(in: NSRect(x: start, y: (bounds.height - height) / 2, width: max(end - start, 0), height: height))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { lit = true }
    override func mouseExited(with event: NSEvent) { lit = false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { sendAction(action, to: target) }
    }
    override func accessibilityPerformPress() -> Bool { sendAction(action, to: target) }
}

/// The yellow dot, its soft ring, and the count.
private final class WaitMark: NSView {
    var number = 0 {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    private static let dot: CGFloat = 7, ring: CGFloat = 2.5, gap: CGFloat = 7
    private var words: NSAttributedString {
        NSAttributedString(string: "\(number)", attributes: [.font: Look.font(.ui, size: 12, weight: .semibold), .foregroundColor: Look.Token.ink.color])
    }
    override var fittingSize: NSSize {
        NSSize(width: ceil(WaitMark.ring * 2 + WaitMark.dot + WaitMark.gap + words.size().width), height: ceil(max(words.size().height, 12)))
    }
    override func draw(_ dirtyRect: NSRect) {
        let dot = NSRect(x: WaitMark.ring, y: (bounds.height - WaitMark.dot) / 2, width: WaitMark.dot, height: WaitMark.dot)
        Look.Token.needSoft.color.setFill()
        NSBezierPath(ovalIn: dot.insetBy(dx: -WaitMark.ring, dy: -WaitMark.ring)).fill()
        Look.Token.need.color.setFill()
        NSBezierPath(ovalIn: dot).fill()
        words.draw(at: NSPoint(x: dot.maxX + WaitMark.gap, y: (bounds.height - words.size().height) / 2))
    }
    /// A small pop from a smaller, clear mark, around its centre; nothing under Reduced.
    func pop(_ seconds: TimeInterval) {
        guard seconds > 0 else { return }
        wantsLayer = true
        guard let layer else { return }
        let middle = (bounds.width / 2, bounds.height / 2), small = CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(-middle.0, -middle.1, 0), CATransform3DMakeScale(0.7, 0.7, 1)), CATransform3DMakeTranslation(middle.0, middle.1, 0))
        let scale = CABasicAnimation(keyPath: "transform"), fade = CABasicAnimation(keyPath: "opacity")
        (scale.fromValue, fade.fromValue) = (small, 0)
        let group = CAAnimationGroup()
        (group.animations, group.duration, group.timingFunction) = ([scale, fade], seconds, Look.out.timing)
        layer.add(group, forKey: "pop")
    }
}

/// The panel's button: the mini eyes, still (a live sign in a toolbar is a display link per window, for a small mark),
/// and the count when there is one. `show` is what `Shell.agents(count:eyes:)` calls.
final class AgentsButton: ToolButton {
    private var count = 0

    /// Says how many agents the open space sees, and in what eyes.
    func show(count: Int, eyes: Sign.State) {
        self.count = count
        let size = Look.scale.size.factor, picture = Sign.miniEyes(eyes)
        picture.size = NSSize(width: 16 * size, height: 10 * size)
        picture.accessibilityDescription = image?.accessibilityDescription
        image = picture
        write()
    }

    override var pressed: Bool {
        didSet { write() }
    }

    /// The count in the button's tone, and the width the mockup's padding leaves it: 34 points at least.
    private func write() {
        let k = Look.scale.size.factor, font = Look.font(.ui, size: 12, weight: .semibold)
        (imagePosition, imageHugsTitle) = (count > 0 ? .imageLeading : .imageOnly, true)
        attributedTitle = NSAttributedString(string: count > 0 ? " \(count)" : "", attributes: [.font: font, .foregroundColor: contentTintColor ?? Look.Token.ink2.color])
        let number = count > 0 ? 6 * k + ceil("\(count)".size(withAttributes: [.font: font]).width) : 0
        constraints.first { $0.firstAttribute == .width }?.constant = max(34 * k, 8 * k + 16 * k + number + 8 * k)
    }
}

extension Shell {
    /// The band takes the page's top rows, nil off a page. Later pictures win; one that comes after the space changed
    /// is dropped.
    func readPage() {
        guard let web = page as? WKWebView, web.url != nil, !web.bounds.isEmpty else { return band.wear(nil) }
        let config = WKSnapshotConfiguration(), shown = space
        config.rect = NSRect(x: 0, y: 0, width: web.bounds.width, height: HeaderBand.rows)
        config.snapshotWidth = NSNumber(value: Double(HeaderBand.wide))
        web.takeSnapshot(with: config) { [weak self] image, _ in
            guard let self, space === shown else { return }
            band.wear(image)
        }
    }

    /// The page's width changed.
    func readPageSoon() { band.soon { [weak self] in self?.readPage() } }

    /// The band shows with the toolbar, in the window: the Mac's full screen has the toolbar in a window of its own, and
    /// the band does not follow it there.
    func placeBand() {
        band.isHidden = full || pageFull && window.toolbar?.isVisible == false
        band.over = pageFull
    }

    /// The pill's width, and what a long title leaves on its right: the tools, and the pill, which sits in the middle.
    func fitHeader() {
        let narrow = window.frame.width < Shell.narrow * Look.scale.size.factor
        jump.fit(narrow: narrow)
        titleLine.reserve = max(toolsWidth, (window.frame.width + JumpPill.width(narrow: narrow)) / 2 + 12)
    }

    /// What the pill says waits: nothing while the sidebar shows, whose Needs You says it.
    func sayWaiting() { jump.show(waiting: drawer.state.shown ? 0 : library.sidebar.needs.count) }
}
