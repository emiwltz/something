// What a Quick Change that changed nothing says: its assistant's answer as a note beside the part it was about. With
// room (440 points of page left), the note opens a margin of something's own paper at the right of the space, the page
// narrowed by 284 points as a narrower window would be, and a leader line ties the note to the part; without it, the
// note sits under the part, over the page. The part keeps the sign's corners. The note says whose assistant answered,
// "Answered · nothing changed", the answer in the agent's voice (Young Serif), the part, and Dismiss; Esc does the
// same, wherever the focus is (Shell.escape): the note never takes the keys, so that typing to the main assistant
// goes on while a Quick Change ends. A note never holds a button that allows anything: a permission is decided in
// something's own panel. A note and Info exclude each other: the right edge holds one thing at a time (Shell). At rest
// it asks the page nothing: it follows its part when the page scrolls or reflows (SpaceView). Drawn in draw(_:), so a
// picture of the window shows it as the screen does.
import AppKit

final class MarginNote: NSView {
    /// Where the note goes: in the margin, or under the part.
    enum Side: Equatable { case margin, under }

    /// The note's place, its leader line and the frame around its part, in the note view's points (the page's own,
    /// the margin to their right).
    struct Layout: Equatable {
        let side: Side, note: CGRect, about: CGRect
        /// From the part's edge to the note, level with the part; nil under the part.
        let lead: [CGPoint]?
    }

    /// The margin's width, the page width it leaves at the least, and a note's width under its part.
    static let margin: CGFloat = 284, least: CGFloat = 440, narrow: CGFloat = 268

    /// The side for a page `width` points wide before any margin.
    static func side(for width: CGFloat) -> Side { width - margin >= least ? .margin : .under }

    /// Where a note `height` high goes for the part at `part` (in the page's viewport) on `side`, in a note view of
    /// `size`, the margin included: in the margin, level with the part, 14 points off the page's top and bottom; under
    /// the part with its right edge, or over it when the page has no room below, 12 points off the page's sides.
    static func layout(part: CGRect, side: Side, size: CGSize, height: CGFloat) -> Layout {
        let pad = PointOverlay.pad, about = part.insetBy(dx: -pad, dy: -pad)
        switch side {
        case .margin:
            let page = size.width - margin, y = max(30, min(size.height - 40, part.minY + min(part.height / 2, 22)))
            let top = max(14, min(size.height - height - 14, y - 20))
            let note = CGRect(x: page + 16, y: top, width: margin - 32, height: height)
            return Layout(side: side, note: note, about: about, lead: [CGPoint(x: min(part.maxX + pad, page - 6), y: y), CGPoint(x: note.minX, y: y)])
        case .under:
            var top = part.maxY + pad + 12
            if top + height > size.height - 12 { top = part.minY - pad - 12 - height }
            let left = min(size.width - narrow - 12, part.maxX - narrow)
            return Layout(side: side, note: CGRect(x: max(12, left), y: max(12, top), width: narrow, height: height), about: about, lead: nil)
        }
    }

    let words: String, title: String
    /// Margin or under, again each time the window changes width.
    private(set) var side: Side
    private(set) var part: Pointing.Part
    private weak var space: SpaceView?
    let card: Card
    /// Called once the note leaves, by Dismiss, Esc or the window.
    var dismissed: () -> Void = {}
    private var asking = false, askAgain = false

    private init(_ words: String, about part: Pointing.Part, title: String, side: Side, over space: SpaceView) {
        (self.words, self.part, self.title, self.side, self.space) = (words, part, title, side, space)
        card = Card(words: words, title: title, part: part.kind, width: side == .margin ? Self.margin - 32 : Self.narrow)
        super.init(frame: .zero)
        addSubview(card)
        card.dismiss.target = self
        card.dismiss.action = #selector(dismiss)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("\(title)’s assistant, no change")
        setAccessibilityValue(words)
    }
    required init?(coder: NSCoder) { nil }

    /// Puts the note of `words`, `title`'s assistant's answer about `part`, over `space`, in place of one there: in a
    /// margin the page gives it when the page is wide enough, else under the part. Returns the note.
    @discardableResult
    static func show(_ words: String, about part: Pointing.Part, title: String, over space: SpaceView) -> MarginNote {
        space.note?.dismiss()
        space.area.superview?.layoutSubtreeIfNeeded()
        let note = MarginNote(words, about: part, title: title, side: side(for: space.area.bounds.width), over: space)
        note.autoresizingMask = [.width, .height]
        space.area.addSubview(note)
        // One page resize, no animation: the page reflows once into its narrower width, and the note asks where its
        // part went (SpaceView.place).
        space.margin = note.side == .margin ? margin : 0
        note.place()
        return note
    }

    override var isFlipped: Bool { true }
    /// Only the card takes clicks: the page around it is the person's.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return card.frame.contains(local) ? card.hitTest(local) ?? card : nil
    }
    /// The window changed width: a margin that would leave the page under 440 points becomes a note under the part,
    /// and the margin comes back once there is room; the page reflows, so the note asks where its part went.
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        let fits = Self.side(for: bounds.width)
        if fits != side {
            side = fits
            card.width = fits == .margin ? Self.margin - 32 : Self.narrow
            space?.resized(margin: fits == .margin ? Self.margin : 0)
        }
        place()
        follow()
    }

    /// Dismiss and Esc: the note leaves, and the page takes its width back.
    @objc func dismiss() {
        guard superview != nil else { return }
        removeFromSuperview()
        space?.margin = 0
        dismissed()
    }

    /// Where everything goes now.
    var layout: Layout { Self.layout(part: part.rect, side: side, size: bounds.size, height: card.height) }

    private func place() {
        card.frame = layout.note
        needsDisplay = true
    }

    /// Asks the page where the part is now, one question at a time, once more if asked meanwhile: the page reflows
    /// into its new width, and scrolls.
    func follow() {
        guard !asking else { return askAgain = true }
        guard superview != nil, let space, let frame = space.frame else { return }
        asking = true
        Task { @MainActor in
            repeat {
                askAgain = false
                let found = await Pointing.rects([part.path], in: space.web, frame: frame)
                if superview != nil, let rect = found.first ?? nil, rect != part.rect {
                    part.rect = rect
                    place()
                }
            } while askAgain && superview != nil
            asking = false
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let layout = layout
        if side == .margin {
            let page = bounds.width - Self.margin
            Look.Token.bg.color.setFill()
            CGRect(x: page, y: 0, width: Self.margin, height: bounds.height).fill()
            Look.Token.line.color.setFill()
            CGRect(x: page, y: 0, width: 1, height: bounds.height).fill(using: .sourceOver)
        }
        PointOverlay.corners(layout.about, ink: .ink)
        if let lead = layout.lead, let from = lead.first, let to = lead.last, to.x > from.x {
            let line = NSBezierPath()
            line.move(to: from)
            line.line(to: to)
            line.lineWidth = 1.5
            Look.Token.ink.color.withAlphaComponent(0.7).setStroke()
            line.stroke()
            // The dot at the part's end, ringed in the background.
            Look.Token.bg.color.setFill()
            NSBezierPath(ovalIn: CGRect(x: from.x - 5.5, y: from.y - 5.5, width: 11, height: 11)).fill()
            Look.Token.ink.color.setFill()
            NSBezierPath(ovalIn: CGRect(x: from.x - 3.5, y: from.y - 3.5, width: 7, height: 7)).fill()
        }
        Look.drawFloat(layout.note, radius: Look.card, fill: .bg2, ring: false, appearance: effectiveAppearance)
        Look.Token.line.color.setStroke()
        let ring = NSBezierPath(roundedRect: layout.note.insetBy(dx: -0.5, dy: -0.5), xRadius: Look.card + 0.5, yRadius: Look.card + 0.5)
        ring.stroke()
    }

    /// The note itself: the sign and whose assistant answered over a hairline, the answer, then the part and Dismiss.
    final class Card: NSView {
        let dismiss = NSButton(title: "Dismiss", target: nil, action: nil)
        private let words: NSAttributedString, name: NSAttributedString, said: NSAttributedString, part: NSAttributedString
        /// The card's width, which the answer is measured at: the margin's, or the narrower note's under the part.
        /// The mockup's .sw-note: 12 above, 14 each side, 9 below; header, answer and footer 9 apart.
        var width: CGFloat

        init(words: String, title: String, part: String, width: CGFloat) {
            self.width = width
            let leading = NSMutableParagraphStyle()
            (leading.minimumLineHeight, leading.maximumLineHeight) = (13.5 * 1.5, 13.5 * 1.5)
            self.words = NSAttributedString(string: words, attributes: [.font: Look.font(.voice, size: 13.5), .foregroundColor: Look.Token.ink.color,
                                                                        .paragraphStyle: leading])
            name = NSAttributedString(string: "\(title)’s assistant", attributes: [.font: Look.font(.ui, size: 13, weight: .semibold),
                                                                                    .foregroundColor: Look.Token.ink.color])
            said = NSAttributedString(string: "Answered · nothing changed", attributes: [.font: Look.font(.ui, size: 11), .foregroundColor: Look.Token.ink3.color])
            self.part = NSAttributedString(string: part, attributes: [.font: Look.font(.ui, size: 11), .foregroundColor: Look.Token.ink3.color])
            super.init(frame: NSRect(x: 0, y: 0, width: width, height: 100))
            dismiss.isBordered = false
            dismiss.attributedTitle = NSAttributedString(string: "Dismiss", attributes: [.font: Look.font(.ui, size: 12, weight: .medium),
                                                                                         .foregroundColor: Look.Token.ink2.color])
            dismiss.toolTip = "Dismiss (Esc)"
            addSubview(dismiss)
        }
        required init?(coder: NSCoder) { nil }

        /// The answer's font: the agent's voice.
        var voice: NSFont? { words.length == 0 ? nil : words.attribute(.font, at: 0, effectiveRange: nil) as? NSFont }

        override var isFlipped: Bool { true }

        private var textHeight: CGFloat {
            ceil(words.boundingRect(with: NSSize(width: width - 28, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin]).height)
        }
        /// The header's height: the sign, 24, beside two lines.
        private static let header: CGFloat = 32
        var height: CGFloat { 12 + Self.header + 9 + 1 + 9 + textHeight + 9 + 26 + 9 }

        override func layout() {
            super.layout()
            let width = ceil(dismiss.attributedTitle.size().width) + 20
            dismiss.frame = NSRect(x: bounds.width - 14 + 4 - width, y: bounds.height - 9 - 26, width: width, height: 26)
        }

        override func draw(_ dirtyRect: NSRect) {
            // The paper again over the note's float, whose shadow would otherwise show through inside the card.
            Look.Token.bg2.color.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: Look.card, yRadius: Look.card).fill()
            let top: CGFloat = 12, mid = top + Self.header / 2
            Sign.image(.listen, side: 24).draw(in: CGRect(x: 14, y: mid - 12, width: 24, height: 24), from: .zero, operation: .sourceOver,
                                               fraction: 1, respectFlipped: true, hints: nil)
            let lines = name.size().height + 1 + said.size().height
            name.draw(at: CGPoint(x: 14 + 24 + 9, y: mid - lines / 2))
            said.draw(at: CGPoint(x: 14 + 24 + 9, y: mid - lines / 2 + name.size().height + 1))
            Look.Token.line.color.setFill()
            CGRect(x: 14, y: top + Self.header + 9, width: bounds.width - 28, height: 1).fill(using: .sourceOver)
            let text = top + Self.header + 9 + 1 + 9
            words.draw(with: CGRect(x: 14, y: text, width: bounds.width - 28, height: textHeight), options: [.usesLineFragmentOrigin])
            let foot = bounds.height - 9 - 13
            NSImage.symbol("scope", 10, .medium).draw(Look.Token.ink3.color, flippedIn: CGRect(x: 14, y: foot - 5.5, width: 11, height: 11))
            part.draw(at: CGPoint(x: 14 + 11 + 5, y: foot - part.size().height / 2))
        }
    }
}

extension SpaceView {
    /// The note over this space's page, while one shows.
    var note: MarginNote? { area.subviews.lazy.compactMap { $0 as? MarginNote }.first }
}
