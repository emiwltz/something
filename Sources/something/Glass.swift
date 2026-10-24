// The glass: a pass-through layer over the center that holds the open space's assistant, either the 44-point sticker
// in the bottom right corner or the card grown from it. The sticker is the sign on a surface with the hard offset
// shadow (it is grabbed): its eyes say the assistant's state, a badge counts only this space's requests (the Dock and
// the toolbar's chip count every one), and a label beside it says in words what it does, on hover or focus. A click,
// Return or ⌘K grows the card from the sticker's corner; ⌘\, Esc or Reduce shrinks it back, and the focus returns to
// the page. The sticker is only over a space: on the blank page and the templates the card stands alone, as the window
// shows it, and over the tour there is neither.
import AppKit
import Observation

final class Glass: WindowLayer {
    /// The sticker's side and its distance from the center's edges.
    static let side: CGFloat = 44, margin: CGFloat = 16
    let model: AssistantModel
    let sticker = Sticker(), label = Tag()
    let card: CardHost
    /// How many of the open space's own requests wait: the sticker's badge.
    var mine = 0 {
        didSet { if mine != oldValue { sticker.mine = mine; say() } }
    }
    /// The person's Motion: Reduced, the card is in place at once.
    var motion: () -> Look.Motion = { .calm }
    /// Where the focus goes when the card shrinks with it inside: the page.
    var page: () -> NSView? = { nil }
    /// Whether the card is grown, as last placed; nil before the first time.
    private(set) var grown: Bool?
    /// Whether the card is on its way between the sticker and its place: its frame is the animation's meanwhile.
    private(set) var morphing = false
    /// The count of moves begun: a move cut short by the next one ends, and only the last one's end counts.
    private var moves = 0

    init(over center: NSView, model: AssistantModel) {
        self.model = model
        card = CardHost(model: model)
        super.init(over: center)
        // The card above the sticker it grows from: closed, it lets the clicks through to the sticker.
        [sticker, label, card].forEach(hold)
        (card.isHidden, label.isHidden) = (true, true)
        sticker.opened = { [weak self] in self?.model.focus() }
        sticker.hovered = { [weak self] _ in self?.say() }
        (sticker.badge.target, sticker.badge.action) = (self, #selector(showRequest))
        card.resized = { [weak self] in self?.place() }
        watch()
    }

    required init?(coder: NSCoder) { nil }

    /// The sticker's surface: `side` square, `margin` from the right and bottom edges.
    var corner: NSRect {
        NSRect(x: bounds.width - Glass.margin - Glass.side, y: Glass.margin, width: Glass.side, height: Glass.side)
    }

    /// Whether the sticker is shown: over a space, the card closed.
    var stickerShown: Bool { !sticker.isHidden && sticker.alphaValue > 0 }

    @objc private func showRequest() { model.showRequest() }

    /// Follows the model: each change it reads calls `update` again, on the next turn of the main loop.
    private func watch() {
        withObservationTracking { update() } onChange: { [weak self] in
            DispatchQueue.main.async { self?.watch() }
        }
    }

    /// The sticker's eyes and words from the assistant's presence, and the card grown or shrunk as the model says.
    private func update() {
        let presence = model.presence, onSpace = { if case .space = model.place { true } else { false } }()
        sticker.show(presence, title: model.title)
        sticker.isHidden = !onSpace
        let open = model.cardShown
        if open != grown { grow(open, animated: onSpace && grown != nil) }
        say()
    }

    /// The label beside the sticker, shown while the pointer is over it or it has the focus, the card closed.
    private func say() {
        let on = sticker.hovering && stickerShown && grown != true && !morphing
        label.isHidden = !on
        guard on, let presence = sticker.presence else { return }
        label.say(title: sticker.title, words: Glass.words(presence, mine: mine))
        place()
    }

    /// What the label says after the title: the requests of this space waiting, else the assistant's present tense.
    static func words(_ presence: Presence, mine: Int) -> String {
        mine == 0 ? presence.word : "\(mine == 1 ? "A request" : "\(mine) requests") waiting for your answer"
    }

    /// Grows the card from the sticker's corner (`open`), or shrinks it into the sticker, by explicit frames, the
    /// card's bottom right corner held where the sticker's is; at once when not `animated` or under Reduced motion.
    private func grow(_ open: Bool, animated: Bool) {
        grown = open
        if !open, let responder = window?.firstResponder as? NSView, responder.isDescendant(of: card) {
            window?.makeFirstResponder(page())
        }
        let duration = animated ? Look.duration(0.5, Look.motion(motion())) : 0
        guard duration > 0 else {
            (moves, morphing) = (moves + 1, false)
            (card.isHidden, card.alphaValue, sticker.alphaValue, model.folding) = (!open, 1, open ? 0 : 1, false)
            return place()
        }
        model.folding = !open
        if open {
            (card.frame, card.alphaValue, card.isHidden) = (shrunk, 0, false)
            card.layoutSubtreeIfNeeded()
        }
        morphing = true
        moves += 1
        let move = moves
        say()
        NSAnimationContext.runAnimationGroup({ context in
            (context.duration, context.timingFunction, context.allowsImplicitAnimation) = (duration, Look.douce.timing, true)
            card.animator().frame = open ? grownFrame : shrunk
            card.animator().alphaValue = open ? 1 : 0
            sticker.animator().alphaValue = open ? 0 : 1
        }, completionHandler: { [weak self] in
            guard let self, move == moves else { return }
            morphing = false
            if grown == false { (card.isHidden, model.folding) = (true, false) }
            place()
            say()
        })
    }

    /// The card's frame around the sticker: its 16-point margin, where the shadow falls, around the sticker's corner.
    private var shrunk: NSRect { corner.insetBy(dx: -AssistantCard.margin, dy: -AssistantCard.margin) }

    /// The card's frame grown: as wide as it is drawn (narrower in a narrow center), as high as it asks under the
    /// toolbar, its bottom right corner the sticker's (with its margin).
    private var grownFrame: NSRect {
        let size = card.intrinsicContentSize, top = superview?.safeAreaInsets.top ?? 0
        let width = min(AssistantCard.width + 2 * AssistantCard.margin, bounds.width)
        let height = max(0, min(size.height, bounds.height - top))
        return NSRect(x: corner.maxX + AssistantCard.margin - width, y: corner.minY - AssistantCard.margin, width: width, height: height)
    }

    /// Places the sticker, its label and the card, except while the card moves between them.
    func place() {
        let surface = corner, room = Sticker.room
        if sticker.frame != surface.insetBy(dx: -room, dy: -room) { sticker.frame = surface.insetBy(dx: -room, dy: -room) }
        if !label.isHidden {
            let size = label.fittingSize, width = min(size.width, max(0, surface.minX - 10 - 8))
            label.frame = NSRect(x: surface.minX - 10 - width, y: surface.midY - size.height / 2, width: width, height: size.height)
        }
        guard !morphing else { return }
        let frame = grown == true ? grownFrame : shrunk
        if card.frame != frame { card.frame = frame }
        let floating = grown == true ? frame.height : 0
        if model.floating != floating { model.floating = floating }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        place()
    }
}

/// The sticker: the sign on a 44-point surface with the hard offset shadow, lifted under the pointer, and the badge of
/// its space's requests at its top right corner. A click, Return or Space opens the card; the badge shows the request.
/// It is drawn `room` points inside its frame, which holds the shadow and the badge.
final class Sticker: NSView {
    static let room: CGFloat = 12, radius: CGFloat = Look.card + 4
    let sign = SignView(.unknown, side: 30), badge = Badge()
    /// Called to open the card, and when the pointer or the focus comes or goes.
    var opened: () -> Void = {}
    var hovered: (Bool) -> Void = { _ in }
    /// How many of its space's requests wait; the badge hides at 0.
    var mine = 0 {
        didSet { badge.count = mine; badge.isHidden = mine == 0; place() }
    }
    private(set) var pointed = false, focused = false
    /// What it shows: its assistant's presence and its space's title.
    private(set) var presence: Presence?, title = ""
    private var label = ""
    /// Whether its label is shown: the pointer is over it, or it has the focus.
    var hovering: Bool { pointed || focused }

    init() {
        super.init(frame: .zero)
        sign.name = ""
        addSubview(sign)
        addSubview(badge)
        badge.isHidden = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    /// The surface, lifted up and left by a point under the pointer, as the mockup's hover.
    var surface: NSRect {
        let rest = bounds.insetBy(dx: Sticker.room, dy: Sticker.room)
        return pointed ? rest.offsetBy(dx: -1, dy: -1) : rest
    }

    /// Shows `presence`'s state in the eyes, and says it to VoiceOver with the space's `title`; the label, when shown,
    /// says it again.
    func show(_ presence: Presence, title: String) {
        if sign.state != presence.state { sign.state = presence.state }
        (self.presence, self.title, label) = (presence, title, presence.label(title))
        if hovering { hovered(true) }
    }

    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        place()
    }

    /// The sign 7 points inside the surface; the badge over its top right corner, 8 points out.
    private func place() {
        let surface = surface
        sign.frame = surface.insetBy(dx: 7, dy: 7)
        let size = badge.intrinsicContentSize
        badge.frame = NSRect(x: surface.maxX + 8 - size.width, y: surface.minY - 8, width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        Sign.grab(surface, radius: Sticker.radius, lift: pointed ? .held : .rest)
    }

    /// The badge answers for itself, the surface for the sticker; the shadow and the room around let the page have it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let inside = convert(point, from: superview)
        if !badge.isHidden, badge.frame.contains(inside) { return badge }
        return surface.contains(inside) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds.insetBy(dx: Sticker.room, dy: Sticker.room),
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { point(true) }
    override func mouseExited(with event: NSEvent) { point(false) }

    private func point(_ on: Bool) {
        pointed = on
        place()
        needsDisplay = true
        hovered(hovering)
    }

    // AB06 tells a drag from a click; until then a press that ends on the sticker opens the card.
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if surface.contains(convert(event.locationInWindow, from: nil)) { opened() }
    }

    override var acceptsFirstResponder: Bool { !isHidden && alphaValue > 0 }
    override func becomeFirstResponder() -> Bool {
        focused = true
        hovered(hovering)
        return true
    }
    override func resignFirstResponder() -> Bool {
        focused = false
        hovered(hovering)
        return true
    }

    /// Return, Enter and Space open the card.
    override func keyDown(with event: NSEvent) {
        if ["\r", "\u{3}", " "].contains(event.charactersIgnoringModifiers ?? "") { opened() } else { super.keyDown(with: event) }
    }

    override var focusRingMaskBounds: NSRect { surface.insetBy(dx: -3, dy: -3) }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: surface.insetBy(dx: -3, dy: -3), xRadius: Sticker.radius + 3, yRadius: Sticker.radius + 3).fill()
    }

    override func accessibilityLabel() -> String? { label }
    override func accessibilityPerformPress() -> Bool {
        opened()
        return true
    }
}

/// The sticker's badge: how many of its space's requests wait, white on ink in a pill ringed with the surface's colour.
/// A click shows the request.
final class Badge: NSButton {
    var count = 0 {
        didSet {
            setAccessibilityLabel("\(count) \(count == 1 ? "request" : "requests") from this space waiting for your answer")
            toolTip = "\(accessibilityLabel() ?? "") · \(Keys.tooltip("showreq", "Show Request"))"
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    private var number: NSAttributedString {
        NSAttributedString(string: "\(count)", attributes: [.font: Look.font(.ui, size: 11, weight: .bold), .foregroundColor: Look.Token.bg.color])
    }

    init() {
        super.init(frame: .zero)
        (isBordered, title, refusesFirstResponder) = (false, "", true)
    }

    required init?(coder: NSCoder) { nil }

    // The mockup's .abadge: 19 high, at least 19 wide, 5 on each side of the number, a 2-point ring of bg2.
    override var intrinsicContentSize: NSSize { NSSize(width: max(19, ceil(number.size().width) + 10), height: 19) }

    override func draw(_ dirtyRect: NSRect) {
        Look.Token.bg2.color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let pill = bounds.insetBy(dx: 2, dy: 2)
        Look.Token.ink.color.setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        let size = number.size()
        number.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }
}

/// The label beside the sticker: the space's title, what its assistant does, and ⌘K, in a pill with the soft shadow.
/// It never takes the mouse; VoiceOver reads the same words on the sticker.
final class Tag: NSView {
    private(set) var title = "", words = ""
    private var parts: (title: NSAttributedString, words: NSAttributedString, key: NSAttributedString) {
        (NSAttributedString(string: title, attributes: [.font: Look.font(.ui, size: 12, weight: .semibold), .foregroundColor: Look.Token.ink.color]),
         NSAttributedString(string: words, attributes: [.font: Look.font(.ui, size: 12), .foregroundColor: Look.Token.ink2.color]),
         NSAttributedString(string: Keys.shown("ask"), attributes: [.font: Look.font(.ui, size: 10.5, weight: .medium),
                                                                   .foregroundColor: Look.Token.ink3.color, .kern: 0.2]))
    }

    init() {
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    func say(title: String, words: String) {
        guard (title, words) != (self.title, self.words) else { return }
        (self.title, self.words) = (title, words)
        needsDisplay = true
    }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // The mockup's .atag: 30 high (with a point of room around), 11 before the title, 8 between the pieces, 6 after the key's 5-point padding.
    override var fittingSize: NSSize {
        let p = parts
        return NSSize(width: 11 + ceil(p.title.size().width) + 8 + ceil(p.words.size().width) + 8 + ceil(p.key.size().width) + 10 + 6 + 2, height: 32)
    }

    override func draw(_ dirtyRect: NSRect) {
        // A point of room around it for the shadow.
        let pill = bounds.insetBy(dx: 1, dy: 1), shape = NSBezierPath(roundedRect: pill, xRadius: 15, yRadius: 15)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        (shadow.shadowColor, shadow.shadowBlurRadius, shadow.shadowOffset) = (Look.float(effectiveAppearance)[0].color, 1, NSSize(width: 0, height: -1))
        shadow.set()
        Look.Token.bg2.color.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        Look.Token.line2.color.setStroke()
        NSBezierPath(roundedRect: pill.insetBy(dx: 0.5, dy: 0.5), xRadius: 14.5, yRadius: 14.5).stroke()
        let p = parts, key = ceil(p.key.size().width) + 10
        var x = pill.minX + 11
        let room = pill.maxX - 6 - key - 8
        for (piece, last) in [(p.title, false), (p.words, true)] {
            let size = piece.size(), width = last ? max(0, room - x) : ceil(size.width)
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            let cut = NSMutableAttributedString(attributedString: piece)
            cut.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: cut.length))
            cut.draw(in: NSRect(x: x, y: pill.midY - size.height / 2, width: width, height: size.height))
            x += width + 8
        }
        let box = NSRect(x: pill.maxX - 6 - key, y: pill.midY - 8.5, width: key, height: 17)
        Look.Token.hover.color.setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        let size = p.key.size()
        p.key.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))
    }
}
