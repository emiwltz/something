// Add Comment: what a person says about parts of the open space, kept to send together. Each comment is a numbered pin
// at its part's top-left corner and a row of the tray at the bottom of the space: its number, its part's name and the
// words, which stay editable, and a cross that takes it out (the others renumber). While comments wait, point mode's
// banner leaves and the tray says the way on: point at another part, Esc, Clear, Send to Assistant ⌘↵. Send passes
// them all in one message to the space's main assistant (AssistantModel.comment); the tray moves aside for the card
// and says the assistant works through them; when that turn ends every pin becomes a check, the tray says All done,
// then both leave. A turn that failed gives the comments back, to send again. Nothing here allows anything: a
// permission is always the native panel's. Pins and tray are drawn in draw(_:), so a picture of the window shows them.
import AppKit

final class Comments: NSView, NSTextFieldDelegate {
    struct Comment: Equatable {
        var part: Pointing.Part
        var words: String
    }
    /// Written and waiting, sent and worked on, or done.
    enum Phase { case writing, sending, done }

    private(set) var list: [Comment] = []
    private(set) var phase = Phase.writing
    /// Where each comment's part is now, in the page's viewport; a part the page lost keeps its last place.
    private(set) var rects: [CGRect] = []
    private weak var space: SpaceView?
    /// Sends the comments: true once they left (or wait for the turn under way); a refusal is the window's to say.
    var send: ([Comment]) -> Bool = { _ in false }
    /// Whether the space's assistant works now, whether its last turn failed, and whether point mode is on.
    var working: () -> Bool = { false }, failed: () -> Bool = { false }, pointing: () -> Bool = { false }
    /// How long the checks stay once all is done, as the mockup's; a test lengthens it.
    var linger: TimeInterval = 2.6
    let tray = CommentTray()
    private var timer: Timer?, asking = false

    /// The comments over `space`'s page, if any wait or are at work.
    static func of(_ space: SpaceView) -> Comments? { space.area.subviews.lazy.compactMap { $0 as? Comments }.first }

    /// An empty layer of comments, which follows its parts and its turn a few times a second while it is in a view.
    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(tray)
        tray.owner = self
        timer = .scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            // It leaves with its space, or once its comments are done; the timer with it.
            guard let self else { return timer.invalidate() }
            if superview != nil { tick() }
        }
    }
    required init?(coder: NSCoder) { nil }

    /// Puts an empty layer of comments over `space`'s page, above all that covers it, so the tray takes its clicks.
    static func show(over space: SpaceView) -> Comments {
        let made = Comments(frame: space.web.frame)
        made.space = space
        made.autoresizingMask = [.width, .height]
        space.area.addSubview(made)
        return made
    }

    override var isFlipped: Bool { true }
    /// Only the tray takes clicks: a pin's part is the page's, or point mode's to pick again.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let at = convert(point, from: superview)
        guard tray.frame.contains(at) else { return nil }
        return tray.hitTest(at) ?? tray
    }

    /// Adds `words` about each of `parts`, numbered after the others. After comments sent, it starts a new list.
    func add(_ words: String, _ parts: [Pointing.Part]) {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, !parts.isEmpty else { return }
        if phase != .writing { (list, rects, phase) = ([], [], .writing) }
        list += parts.map { Comment(part: $0, words: words) }
        rects += parts.map(\.rect)
        changed()
    }

    /// Takes the comment at `index` out; the others renumber. The last one gone, the layer leaves.
    func remove(_ index: Int) {
        guard phase == .writing, list.indices.contains(index) else { return }
        list.remove(at: index)
        rects.remove(at: index)
        list.isEmpty ? clear() : changed()
    }

    /// Clear: every comment goes, and point mode's banner comes back.
    func clear() {
        (list, rects) = ([], [])
        timer?.invalidate()
        let pointer = space?.pointer
        removeFromSuperview()
        pointer?.needsDisplay = true
    }

    /// Send to Assistant (and ⌘↵): the comments with words leave together.
    @objc func sendAll() {
        let kept = list.indices.filter { !list[$0].words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard phase == .writing, !kept.isEmpty else { return }
        (list, rects) = (kept.map { list[$0] }, kept.map { rects[$0] })
        window?.makeFirstResponder(nil)
        if send(list) {
            phase = .sending
            changed()
        }
    }

    /// What VoiceOver says of each pin, in order.
    var pins: [String] { list.indices.map { "Comment \($0 + 1) on \(list[$0].part.kind)" + (phase == .done ? ", done" : "") } }

    /// Draws again and lays the tray out after any change, point mode's start and stop included.
    func changed() {
        tray.lay(list, phase: phase, pointing: pointing())
        let width = bounds.width, height = tray.height
        tray.frame = phase == .writing
            ? CGRect(x: ((width - min(640, width - 40)) / 2).rounded(), y: bounds.height - 16 - height, width: min(640, width - 40), height: height)
            : CGRect(x: 16, y: bounds.height - 16 - height, width: min(460, max(260, width - 440)), height: height)
        tray.setAccessibilityValue(pins.joined(separator: ", "))
        needsDisplay = true
        space?.pointer?.needsDisplay = true
    }

    override func resizeSubviews(withOldSize size: NSSize) {
        super.resizeSubviews(withOldSize: size)
        changed()
    }

    /// The words of a row changed: kept as typed.
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let index = tray.fields.firstIndex(of: field), list.indices.contains(index) else { return }
        list[index].words = field.stringValue
    }

    /// Follows the parts, and the turn the comments went with: once it is over, done, or back to send again.
    private func tick() {
        if window != nil { follow() }
        guard phase == .sending, !working() else { return }
        guard !failed() else {
            phase = .writing
            return changed()
        }
        phase = .done
        changed()
        DispatchQueue.main.asyncAfter(deadline: .now() + linger) { [weak self] in
            guard let self, phase == .done else { return }
            Look.animate(0.35, Look.douce, settle: [self], { self.animator().alphaValue = 0 }, done: { [weak self] in
                if self?.phase == .done { self?.clear() }
            })
        }
    }

    /// Asks the page where the parts are now, one question at a time.
    private func follow() {
        guard !asking, let space, let frame = space.frame, !list.isEmpty else { return }
        asking = true
        let paths = list.map(\.part.path)
        Task { @MainActor in
            let found = await Pointing.rects(paths, in: space.web, frame: frame)
            asking = false
            guard found.count == rects.count, paths == list.map(\.part.path) else { return }
            let moved = zip(rects, found).map { $1 ?? $0 }
            if moved != rects {
                rects = moved
                needsDisplay = true
            }
        }
    }

    override func removeFromSuperview() {
        timer?.invalidate()
        timer = nil
        super.removeFromSuperview()
    }

    // MARK: Drawing

    /// A pin: 22 points round, 11 off its part's frame corner, never cut by the page's top or left.
    func pin(_ index: Int) -> CGRect {
        let r = rects[index], off = PointOverlay.pad + 11
        return CGRect(x: max(2, r.minX - off), y: max(2, r.minY - off), width: 22, height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        for index in list.indices {
            let box = pin(index)
            (phase == .done ? Look.Token.ok : .act).color.setFill()
            NSBezierPath(ovalIn: box).fill()
            if phase == .done {
                NSImage.symbol("checkmark", 10, .bold).draw(.white, flippedIn: box.insetBy(dx: 5.5, dy: 5.5))
            } else {
                let number = NSAttributedString(string: "\(index + 1)", attributes: [.font: Look.font(.ui, size: 11.5, weight: .bold),
                                                                                    .foregroundColor: Look.Token.actfg.color])
                let size = number.size()
                number.draw(at: CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))
            }
        }
        // The tray's ground: the float shadow, with a hairline ring.
        Look.drawFloat(tray.frame, radius: Look.card, fill: .bg2, ring: false, appearance: effectiveAppearance)
        Look.Token.bg2.color.setFill()
        NSBezierPath(roundedRect: tray.frame, xRadius: Look.card, yRadius: Look.card).fill()
        Look.Token.line.color.setStroke()
        NSBezierPath(roundedRect: tray.frame.insetBy(dx: -0.5, dy: -0.5), xRadius: Look.card + 0.5, yRadius: Look.card + 0.5).stroke()
    }
}

/// The tray: one row per comment, then its footer. The words are fields; the rest is drawn.
final class CommentTray: NSView {
    weak var owner: Comments?
    private(set) var fields: [NSTextField] = [], removes: [NSButton] = []
    private(set) lazy var clear = LinkButton("Clear", nil, size: 12, target: self, action: #selector(clearAll))
    let sendButton = PanelButton("Send to Assistant", primary: true, hint: "⌘↵", symbol: "arrow.up")
    private var list: [Comments.Comment] = [], phase = Comments.Phase.writing, pointing = false
    private var hovered: Int? { didSet { removes.enumerated().forEach { $1.alphaValue = $0 == hovered ? 1 : 0 } } }

    /// Rows 31 high under 6 points, 2 under them, then the footer, 46.
    static let row: CGFloat = 31, top: CGFloat = 6, footer: CGFloat = 46
    var height: CGFloat { Self.top + CGFloat(list.count) * Self.row + 2 + Self.footer }
    private var footerTop: CGFloat { height - Self.footer }

    init() {
        super.init(frame: .zero)
        (sendButton.height, sendButton.size, sendButton.hintSize, sendButton.pad, sendButton.least) = (28, 12, 11, 11, 0)
        (sendButton.target, sendButton.action) = (self, #selector(send))
        addSubview(clear)
        addSubview(sendButton)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Comments")
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    @objc private func send() { owner?.sendAll() }
    @objc private func clearAll() { owner?.clear() }
    @objc private func remove(_ sender: NSButton) { removes.firstIndex(of: sender).map { owner?.remove($0) } }

    /// The footer's words, as drawn: the count, then the way on while writing, or how the work goes.
    var footer: [String] {
        let count = "\(list.count) comment\(list.count == 1 ? "" : "s")"
        switch phase {
        case .writing: return pointing ? [count, "Point at another part", "Esc", "Stop Pointing"] : [count]
        case .sending: return [count, "Working through them"]
        case .done: return [count, "All done"]
        }
    }

    /// Lays out `list` in `phase`: its fields made again only when the count changed, so typing keeps its place.
    func lay(_ list: [Comments.Comment], phase: Comments.Phase, pointing: Bool) {
        (self.list, self.phase, self.pointing) = (list, phase, pointing)
        if fields.count != list.count {
            (fields + removes).forEach { $0.removeFromSuperview() }
            fields = list.indices.map { _ in
                let field = NSTextField(string: "")
                (field.isBordered, field.drawsBackground, field.focusRingType, field.font) = (false, false, .none, Look.font(.ui, size: 13))
                field.cell?.lineBreakMode = .byTruncatingTail
                field.delegate = owner
                addSubview(field)
                return field
            }
            removes = list.indices.map { _ in
                let button = NSButton(image: NSImage.symbol("xmark", 10, .medium).tinted(Look.Token.ink3.color), target: self, action: #selector(remove(_:)))
                (button.isBordered, button.alphaValue) = (false, 0)
                addSubview(button)
                return button
            }
        }
        let writing = phase == .writing, face = NSAttributedString.Key.self
        for (index, comment) in list.enumerated() {
            let field = fields[index], y = Self.top + CGFloat(index) * Self.row
            if field.currentEditor() == nil {
                field.attributedStringValue = NSAttributedString(string: comment.words, attributes: [
                    face.font: Look.font(.ui, size: 13), face.foregroundColor: (phase == .done ? Look.Token.ink3 : .ink).color,
                    face.strikethroughStyle: phase == .done ? NSUnderlineStyle.single.rawValue : 0, face.strikethroughColor: Look.Token.line2.color])
            }
            (field.isEditable, field.isSelectable) = (writing, writing)
            field.setAccessibilityLabel("Comment \(index + 1)")
            let x = 42 + ceil(name(comment).size().width) + 9 + 6
            field.frame = CGRect(x: x, y: y + (Self.row - 18) / 2, width: max(40, bounds.width - x - 10 - (writing ? 30 : 0)), height: 18)
            removes[index].frame = CGRect(x: bounds.width - 10 - 26, y: y + (Self.row - 24) / 2, width: 24, height: 24)
            removes[index].isHidden = !writing
            removes[index].setAccessibilityLabel("Remove comment \(index + 1)")
        }
        let send = sendButton.intrinsicContentSize.width, clearSize = clear.intrinsicContentSize
        sendButton.frame = CGRect(x: bounds.width - 10 - send, y: footerTop + 8, width: send, height: 28)
        clear.frame = CGRect(x: sendButton.frame.minX - 8 - 11 - clearSize.width, y: footerTop + 13, width: clearSize.width + 11, height: 18)
        (sendButton.isHidden, clear.isHidden) = (!writing, !writing)
        needsDisplay = true
    }

    override func setFrameSize(_ size: NSSize) {
        let changed = size != frame.size
        super.setFrameSize(size)
        if changed { lay(list, phase: phase, pointing: pointing) }
    }

    override func mouseMoved(with event: NSEvent) {
        let y = convert(event.locationInWindow, from: nil).y - Self.top
        hovered = y >= 0 && y < CGFloat(list.count) * Self.row ? Int(y / Self.row) : nil
    }
    override func mouseExited(with event: NSEvent) { hovered = nil }

    private func name(_ comment: Comments.Comment) -> NSAttributedString {
        NSAttributedString(string: comment.part.kind, attributes: [.font: Look.font(.ui, size: 12, weight: .semibold), .foregroundColor: Look.Token.ink2.color])
    }

    override func draw(_ dirtyRect: NSRect) {
        let done = phase == .done
        for (index, comment) in list.enumerated() {
            let mid = Self.top + CGFloat(index) * Self.row + Self.row / 2, circle = CGRect(x: 14, y: mid - 10, width: 20, height: 20)
            (done ? Look.Token.ok : .act).color.setFill()
            NSBezierPath(ovalIn: circle).fill()
            if done {
                NSImage.symbol("checkmark", 9, .bold).draw(.white, flippedIn: circle.insetBy(dx: 5, dy: 5))
            } else {
                let number = NSAttributedString(string: "\(index + 1)", attributes: [.font: Look.font(.ui, size: 10.5, weight: .bold),
                                                                                    .foregroundColor: Look.Token.actfg.color])
                number.draw(at: CGPoint(x: circle.midX - number.size().width / 2, y: circle.midY - number.size().height / 2))
            }
            let label = name(comment)
            label.draw(at: CGPoint(x: 42, y: mid - label.size().height / 2))
        }
        Look.Token.line.color.setFill()
        CGRect(x: 0, y: footerTop, width: bounds.width, height: 1).fill()
        // The footer: the count in ink, then the way on in ink3 (its Esc a key cap), or the eyes and how the work goes.
        let mid = footerTop + 8 + 14, words = footer
        let count = NSAttributedString(string: words[0], attributes: [.font: Look.font(.ui, size: 12.5, weight: .semibold), .foregroundColor: Look.Token.ink.color])
        count.draw(at: CGPoint(x: 14, y: mid - count.size().height / 2))
        var x = 14 + ceil(count.size().width) + 8
        if phase != .writing {
            x += 6
            Sign.miniEyes(done ? .done : .think).draw(Look.Token.eyes.color, flippedIn: CGRect(x: x, y: mid - 5, width: 16, height: 10))
            let said = NSAttributedString(string: words[1], attributes: [.font: Look.font(.ui, size: 12.5), .foregroundColor: Look.Token.ink2.color])
            said.draw(at: CGPoint(x: x + 16 + 7, y: mid - said.size().height / 2))
        } else if words.count == 4 {
            x += 10
            let quiet: [NSAttributedString.Key: Any] = [.font: Look.font(.ui, size: 11.5), .foregroundColor: Look.Token.ink3.color]
            NSImage.symbol("scope", 10, .medium).draw(Look.Token.ink3.color, flippedIn: CGRect(x: x, y: mid - 6, width: 12, height: 12))
            x += 12 + 6
            let point = NSAttributedString(string: words[1], attributes: quiet)
            point.draw(at: CGPoint(x: x, y: mid - point.size().height / 2))
            x += ceil(point.size().width) + 6
            Look.Token.ink3.color.setFill()
            NSBezierPath(ovalIn: CGRect(x: x, y: mid - 1.5, width: 3, height: 3)).fill()
            x += 3 + 6
            let key = NSAttributedString(string: words[2], attributes: [.font: Look.font(.ui, size: 10.5, weight: .medium), .foregroundColor: Look.Token.ink.color])
            let cap = CGRect(x: x, y: mid - 9, width: ceil(key.size().width) + 10, height: 18)
            Look.Token.sel.color.setFill()
            NSBezierPath(roundedRect: cap, xRadius: 5, yRadius: 5).fill()
            key.draw(at: CGPoint(x: cap.minX + 5, y: cap.midY - key.size().height / 2))
            let stop = NSAttributedString(string: words[3], attributes: quiet)
            stop.draw(at: CGPoint(x: cap.maxX + 6, y: mid - stop.size().height / 2))
        }
    }
}
