// The composer point mode attaches to the parts a person picked: it names them, asks "What should change here?", says
// whose assistant hears it (the space's name with its assistant's eyes), and offers the two ways on: Quick Change
// (Return), a change made now, and Add Comment (⌘↵), kept for later with others. Shift-Return breaks the line. It
// sits under the last part picked, or over it when the window has no room below, on the side of the window the part
// is on (place(_:by:in:)). The overlay draws its float shadow; it draws its own ground.
import AppKit

final class PointComposer: NSView, NSTextViewDelegate {
    /// The mockup's .sw-comp: 368 wide; 10 above, the header, 6, the two-line field, 6, the buttons, 8 below.
    static let size = CGSize(width: 368, height: 118)

    let field = ComposerText(frame: NSRect(x: 0, y: 0, width: 348, height: 44))
    let quickButton = PanelButton("Quick Change", primary: true, hint: "↵", symbol: "bolt")
    let commentButton = PanelButton("Add Comment", hint: "⌘↵", symbol: "text.bubble")
    /// The parts' names ("this table and this row"), the space's title, and its assistant's eyes.
    var names: String { didSet { changed() } }
    var eyes: Sign.State { didSet { needsDisplay = true } }
    let title: String
    /// What Return and ⌘↵ do with the words, trimmed and never empty; Esc, the overlay's.
    var quick: (String) -> Void = { _ in }, comment: (String) -> Void = { _ in }, escape: () -> Void = {}

    init(names: String, title: String, eyes: Sign.State) {
        (self.names, self.title, self.eyes) = (names, title, eyes)
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        field.delegate = self
        field.composer = self
        // Two lines high, as the mockup's textarea; longer words scroll in it.
        let scroll = NSScrollView(frame: NSRect(x: 10, y: 32, width: 348, height: 44))
        (scroll.drawsBackground, scroll.hasVerticalScroller, scroll.documentView) = (false, false, field)
        addSubview(scroll)
        for button in [commentButton, quickButton] {
            (button.height, button.size, button.hintSize, button.pad, button.least) = (28, 12, 11, 10, 0)
            (button.target, button.action) = (self, button === quickButton ? #selector(sendQuick) : #selector(sendComment))
            addSubview(button)
        }
        var right = Self.size.width - 10
        for button in [quickButton, commentButton] {
            let width = button.intrinsicContentSize.width
            button.frame = NSRect(x: right - width, y: 82, width: width, height: 28)
            right -= width + 6
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        changed()
        textDidChange(Notification(name: NSText.didChangeNotification))
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    /// The words, trimmed: nil while there are none.
    var words: String? {
        let words = field.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? nil : words
    }

    /// "To Daily brief’s assistant": whom the words go to.
    var to: String { "To " + title + (title.lowercased().hasSuffix("s") ? "’" : "’s") + " assistant" }

    /// Where a composer of `size` goes by `part` (the last picked, in the overlay's flipped points) in an overlay of
    /// `bounds`: 12 points under the part's frame, or over it when it would pass 12 points from the bottom; aligned
    /// with the frame's right edge when the part's centre is in the right half, else its left; 12 points off every edge.
    static func place(_ size: CGSize, by part: CGRect, in bounds: CGSize) -> CGRect {
        let pad = PointOverlay.pad, right = part.midX > bounds.width / 2
        let x = right ? part.maxX + pad - size.width : part.minX - pad
        var y = part.maxY + pad + 12
        if y + size.height > bounds.height - 12 { y = part.minY - pad - 12 - size.height }
        return CGRect(x: max(12, min(bounds.width - size.width - 12, x)), y: max(12, y), width: size.width, height: size.height)
    }

    /// Joins names as a sentence does: "a", "a and b", "a, b and c".
    static func sentence(_ names: [String]) -> String {
        names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "") : names.first ?? ""
    }

    func textDidChange(_ notification: Notification) {
        // Greyed at the mockup's .35 while there is nothing to send.
        for button in [quickButton, commentButton] { (button.isEnabled, button.alphaValue) = (words != nil, words != nil ? 1 : 0.35) }
        field.needsDisplay = true
    }

    /// Return makes a Quick Change; Shift-Return (and ⌥-Return) breaks the line; Esc is the overlay's.
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { return false }
            sendQuick()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            escape()
            return true
        default:
            return false
        }
    }

    @objc func sendQuick() {
        if let words { quick(words) }
    }

    @objc func sendComment() {
        if let words { comment(words) }
    }

    private func changed() {
        setAccessibilityLabel("What should change here?")
        setAccessibilityHelp(names + ". " + to)
        field.setAccessibilityLabel("What should change here?")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds, xRadius: Look.card, yRadius: Look.card)
        Look.Token.bg2.color.setFill()
        shape.fill()
        // The header, 16 high: the target, the parts' names, and to the right the eyes and the space.
        let mid: CGFloat = 18, small = Look.font(.ui, size: 11.5)
        let icon = NSImage(systemSymbolName: "scope", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium)) ?? NSImage()
        PointOverlay.tinted(icon, Look.Token.ink2.color).draw(in: CGRect(x: 12, y: mid - 6.5, width: 13, height: 13), from: .zero,
                                                             operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let space = NSAttributedString(string: title, attributes: [.font: small, .foregroundColor: Look.Token.ink3.color])
        let spaceSize = space.size(), spaceX = bounds.width - 12 - ceil(spaceSize.width)
        space.draw(at: CGPoint(x: spaceX, y: mid - spaceSize.height / 2))
        PointOverlay.tinted(Sign.miniEyes(eyes), Look.Token.eyes.color).draw(in: CGRect(x: spaceX - 6 - 13, y: mid - 4, width: 13, height: 8),
                                                                             from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let name = NSAttributedString(string: names, attributes: [.font: Look.font(.ui, size: 11.5, weight: .semibold),
                                                                  .foregroundColor: Look.Token.ink.color, .paragraphStyle: style])
        let nameHeight = name.size().height
        name.draw(with: CGRect(x: 12 + 13 + 6, y: mid - nameHeight / 2, width: spaceX - 19 - 12 - 31, height: nameHeight),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

/// The composer's field: Onest 14 on 1.4 lines, its placeholder in ink3, and ⌘↵ taken before any menu sees it.
final class ComposerText: NSTextView {
    weak var composer: PointComposer?
    static let placeholder = "What should change here?"

    override init(frame: NSRect) {
        super.init(frame: frame)
        textContainer?.lineFragmentPadding = 2
        (drawsBackground, isRichText, allowsUndo, textContainerInset) = (false, false, true, NSSize(width: 0, height: 2))
        let style = NSMutableParagraphStyle()
        (style.minimumLineHeight, style.maximumLineHeight) = (19.6, 19.6)
        (font, textColor, defaultParagraphStyle) = (Look.font(.ui, size: 14), Look.Token.ink.color, style)
        typingAttributes = [.font: Look.font(.ui, size: 14), .foregroundColor: Look.Token.ink.color, .paragraphStyle: style]
        (isAutomaticQuoteSubstitutionEnabled, isAutomaticDashSubstitutionEnabled) = (false, false)
        insertionPointColor = Look.Token.ink.color
        (isVerticallyResizable, isHorizontallyResizable, autoresizingMask) = (true, false, .width)
        (minSize, maxSize) = (NSSize(width: 0, height: frame.height), NSSize(width: frame.width, height: .greatestFiniteMagnitude))
    }

    override init(frame: NSRect, textContainer: NSTextContainer?) { super.init(frame: frame, textContainer: textContainer) }
    required init?(coder: NSCoder) { nil }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard window?.firstResponder === self, flags == .command, event.keyCode == 36 || event.keyCode == 76 else {
            return super.performKeyEquivalent(with: event)
        }
        composer?.sendComment()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        var attributes = typingAttributes
        attributes[.foregroundColor] = Look.Token.ink3.color
        NSAttributedString(string: Self.placeholder, attributes: attributes).draw(at: NSPoint(x: 2, y: textContainerInset.height))
    }
}
