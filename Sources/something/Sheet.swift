// The one layout of every sheet of something, as the mockup's dialog: an icon in a tile at the left, a title in
// Fraunces, its sentence (some words bold), rows, a block of its own (a link's address), a fine print, and the actions
// at the bottom right, the safe one first. The alert variant (Quit) centres it all under the sign, its actions sharing
// the width. It hangs from the toolbar over the space, beside the sidebar. A space cannot draw it, so a space cannot
// answer it. Escape presses the cancel action, or the safe one when there is none; the safe action holds the focus at
// first, and Return presses the focused action unless it is destructive: a key meant for something else never confirms
// what cannot be undone.
import AppKit

final class Sheet: NSPanel {
    enum Role { case cancel, secondary, primary, destructive }
    /// An action; `hint` is the key that presses it, shown after its title.
    struct Action { var title: String, role: Role, hint: String? = nil }
    enum Icon { case symbol(String), sign }
    /// A sentence in parts, each bold or not: the words a space chose are never read as markup.
    typealias Words = [(text: String, bold: Bool)]
    /// A row of what a sheet is about: a symbol or an agent's eyes, a label on one line, and a detail at the right, in
    /// code, or `plain` in the text's face; `bad` when it says what the person loses.
    struct Row {
        enum Mark { case symbol(String), eyes(Sign.State) }
        var mark: Mark, label: Words, meta: String?, plain = false, bad = false
    }
    static let width: CGFloat = 380, corner: CGFloat = 14

    let isAlert: Bool
    private(set) var buttons: [SheetButton] = []
    /// The role of the action pressed; nil until one is.
    private(set) var chosen: Role?
    /// Called once an action was pressed: the window it hangs from takes it away.
    var ended: () -> Void = {}

    /// A sheet of the parts given, in this order, `width` points wide; `alert` centres them. Text the page gave is
    /// shown as is.
    init(icon: Icon?, title: String, body: Words = [], rows: [Row] = [], block: NSView? = nil, fine: String? = nil,
         actions: [Action], alert: Bool = false, width: CGFloat = Sheet.width) {
        isAlert = alert
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: 100), styleMask: .borderless, backing: .buffered, defer: true)
        (isOpaque, backgroundColor, hasShadow, self.title) = (false, .clear, true, title)
        let tiled = icon.map { Self.tile($0, alert: alert) }
        let text = Self.column(alert: alert, tiled: tiled != nil, width: width)
        let heading = Self.label([(title, false)], Look.titleS, width: text, kern: -0.3, centred: alert)
        heading.preferredMaxLayoutWidth = Self.balanced(heading, width: text)
        var parts: [NSView] = [heading]
        if !body.isEmpty { parts.append(Self.label(body, Look.body, color: .ink2, width: text, centred: alert)) }
        if !rows.isEmpty { parts.append(Self.list(rows, width: text)) }
        // A block of its own is as wide as the text, so that what it holds can wrap there.
        block?.widthAnchor.constraint(equalToConstant: text).isActive = true
        if let block { parts.append(block) }
        if let fine { parts.append(Self.label([(fine, false)], Look.small, color: .ink3, width: text, centred: alert)) }
        let column = NSStackView(views: parts)
        (column.orientation, column.alignment, column.spacing) = (.vertical, alert ? .centerX : .leading, 8)
        // The title sits 5 points lower than the tile's top, as the mockup sets it beside the tile.
        column.edgeInsets.top = alert ? 0 : 5
        column.widthAnchor.constraint(equalToConstant: text).isActive = true
        let head = NSStackView(views: [tiled, column].compactMap { $0 })
        (head.orientation, head.alignment, head.spacing) = alert ? (.vertical, .centerX, 14) : (.horizontal, .top, 14)
        buttons = actions.map { SheetButton($0, target: self, action: #selector(press(_:))) }
        // Side by side, the actions are as wide as the widest.
        let widest = buttons.map(\.intrinsicContentSize.width).max() ?? 0
        buttons.forEach { $0.least = widest }
        let row = NSStackView(views: buttons)
        row.spacing = 8
        if alert {
            row.distribution = .fillEqually
            buttons.forEach { $0.setContentHuggingPriority(.defaultLow, for: .horizontal) }
            row.widthAnchor.constraint(equalToConstant: width - 40).isActive = true
        }
        let root = NSStackView(views: [head, row])
        (root.orientation, root.alignment, root.spacing) = (.vertical, alert ? .centerX : .trailing, 18)
        let back = SheetBack(root, insets: NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20))
        back.widthAnchor.constraint(equalToConstant: width).isActive = true
        contentView = back
        setContentSize(back.fittingSize)
        // The safe action: Cancel in a sheet; in an alert, its primary one, which the alert makes the safe one, or its
        // Cancel when it has none (a destructive question).
        initialFirstResponder = (alert ? buttons.first { $0.role == .primary } : nil) ?? buttons.first { $0.role == .cancel }
        makeFirstResponder(initialFirstResponder)
        (buttons.first { $0.role == .cancel } ?? initialFirstResponder as? SheetButton)?.keyEquivalent = "\u{1b}"
        setAccessibilitySubrole(.dialog)
    }

    override var canBecomeKey: Bool { true }

    /// Takes the height its content now needs, its top where it was: a sheet hangs from its top edge.
    func refit() {
        guard let content = contentView else { return }
        content.layoutSubtreeIfNeeded()
        var frame = self.frame
        (frame.origin.y, frame.size.height) = (frame.maxY - content.fittingSize.height, content.fittingSize.height)
        setFrame(frame, display: true)
    }

    /// Hangs the sheet from `window`; once an action was pressed it is taken away, and `then` gets that action's role,
    /// or nil when the sheet was ended otherwise (Quit ends an open question as its Cancel would).
    func hang(on window: NSWindow, then: @escaping (Role?) -> Void) {
        ended = { [weak window, unowned self] in window?.endSheet(self) }
        // The handler holds the sheet until it ran: nothing else may keep it once it is off the window.
        window.beginSheet(self) { _ in then(self.chosen) }
    }

    @objc private func press(_ sender: SheetButton) {
        guard chosen == nil else { return }
        chosen = sender.role
        ended()
    }

    override func keyDown(with event: NSEvent) {
        if ["\r", "\u{3}"].contains(event.charactersIgnoringModifiers), let button = firstResponder as? SheetButton, button.role != .destructive {
            button.performClick(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { buttons.first { $0.keyEquivalent == "\u{1b}" }?.performClick(nil) }

    /// How wide a sheet `width` points wide sets its text: its insets, and the tile beside the text unless `alert`
    /// centres it.
    static func column(alert: Bool = false, tiled: Bool = true, width: CGFloat = Sheet.width) -> CGFloat {
        width - 40 - (alert || !tiled ? 0 : 46)
    }

    /// The narrowest width up to `width` that keeps `text` on as many lines as `width` does: the mockup balances the
    /// lines of a title (text-wrap: balance) rather than leave one word alone on the last.
    /// The field's own cell measures, so the width chosen wraps as the field draws.
    static func balanced(_ field: NSTextField, width: CGFloat) -> CGFloat {
        func height(_ wide: CGFloat) -> CGFloat {
            field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: wide, height: 10_000)).height.rounded(.up) ?? 0
        }
        let lines = height(width)
        var (low, high) = (width / 2, width)
        while high - low > 1 {
            let middle = (low + high) / 2
            if height(middle) > lines { low = middle } else { high = middle }
        }
        return high.rounded(.up)
    }

    /// Where a sheet hangs in `window`, in its coordinates: under its toolbar, centred over the space beside a sidebar
    /// `sidebar` points wide (the system centres a sheet on the rectangle's width).
    static func place(in window: NSWindow, sidebar: CGFloat) -> NSRect {
        NSRect(x: sidebar, y: window.contentLayoutRect.maxY, width: window.frame.width - sidebar, height: 0)
    }

    private static func tile(_ icon: Icon, alert: Bool) -> NSView {
        switch icon {
        case .symbol(let name):
            let image = NSImageView.symbol(name, 14, .regular, tint: .ink2)
            let tile = Box(image, fill: .sunk, ring: .line, radius: Look.control, insets: NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8))
            NSLayoutConstraint.activate([image.widthAnchor.constraint(equalToConstant: 16), image.heightAnchor.constraint(equalToConstant: 16)])
            return tile
        case .sign:
            // The mockup's 30-point sign draws its corners about 22 points wide, which a 25-point image of ours does, in
            // the same 44-point tile.
            return Sign.tile(side: 25, radius: 11, inset: 9.5)
        }
    }

    /// `words` in `style`, the bold ones in ink, wrapping at `width`.
    static func label(_ words: Words, _ style: Look.Style, color: Look.Token = .ink, width: CGFloat, kern: CGFloat = 0,
                      centred: Bool = false) -> NSTextField {
        let paragraph = NSMutableParagraphStyle()
        (paragraph.minimumLineHeight, paragraph.alignment) = ((style.size * style.leading).rounded(), centred ? .center : .natural)
        let string = NSMutableAttributedString()
        for (text, bold) in words {
            string.append(NSAttributedString(string: text, attributes: [
                .font: bold ? Look.font(style.face, size: style.size, weight: .semibold) : style.font,
                .foregroundColor: (bold ? Look.Token.ink : color).color, .paragraphStyle: paragraph, .kern: kern]))
        }
        let field = NSTextField(labelWithAttributedString: string)
        (field.lineBreakMode, field.maximumNumberOfLines, field.preferredMaxLayoutWidth) = (.byWordWrapping, 0, width)
        return field
    }

    /// The rows of what a sheet is about, a mark, a label and a quiet detail each, in a ringed list.
    private static func list(_ rows: [Row], width: CGFloat) -> NSView {
        ringed(rows.map { row in
            let image: NSImageView
            switch row.mark {
            case .symbol(let name):
                image = NSImageView.symbol(name, 11, .regular, tint: .ink3)
                image.widthAnchor.constraint(equalToConstant: 14).isActive = true
            case .eyes(let state):
                image = NSImageView(image: Sign.miniEyes(state))
                (image.contentTintColor, image.imageScaling) = (Look.Token.eyes.color, .scaleNone)
                image.setAccessibilityLabel(state.word)
                image.widthAnchor.constraint(equalToConstant: 16).isActive = true
            }
            // One line at its own height, centred with its mark and its detail; a long one ends in "…".
            let label = label(row.label, Look.Style(face: Look.medium.face, size: Look.medium.size, weight: Look.medium.weight, leading: 1),
                              width: width - 80)
            (label.maximumNumberOfLines, label.lineBreakMode) = (1, .byTruncatingTail)
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let style = row.plain ? Look.small : Look.Style(face: .code, size: 11, weight: .regular, leading: 1)
            let meta = row.meta.map { RequestPanel.text($0, style, row.bad ? .bad : .ink3) }
            // The label takes the room left, so that each detail stands at the right edge.
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            meta?.setContentHuggingPriority(.required, for: .horizontal)
            meta?.setContentCompressionResistancePriority(.required, for: .horizontal)
            let line = NSStackView(views: [image, label, meta].compactMap { $0 })
            (line.spacing, line.distribution, line.alignment) = (9, .fill, .centerY)
            line.heightAnchor.constraint(greaterThanOrEqualToConstant: Look.row + 3).isActive = true
            return line
        }, width: width, inset: 12)
    }

    /// `rows` in a ringed list `width` wide, a rule between each two; `inset` points each side keep the rows and the
    /// rules off the ring.
    static func ringed(_ rows: [NSView], width: CGFloat, inset: CGFloat = 0) -> NSView {
        let lines = NSStackView()
        (lines.orientation, lines.spacing) = (.vertical, 0)
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let rule = Box(NSView(), fill: .line)
                rule.heightAnchor.constraint(equalToConstant: 1).isActive = true
                lines.addArrangedSubview(rule)
            }
            lines.addArrangedSubview(row)
        }
        lines.arrangedSubviews.forEach { $0.widthAnchor.constraint(equalToConstant: width - 2 * inset).isActive = true }
        return Box(lines, fill: .bg, ring: .line, radius: Look.card, insets: NSEdgeInsets(top: 0, left: inset, bottom: 0, right: inset))
    }
}

/// The sheet's ground: bg2, ringed, its bottom corners round and its top straight under the toolbar it hangs from.
final class SheetBack: Box {
    init(_ content: NSView, insets: NSEdgeInsets) { super.init(content, insets: insets) }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        // A rounded shape taller than the view: its top corners are out of sight.
        let shape = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: bounds.width - 1, height: bounds.height + Sheet.corner),
                                 xRadius: Sheet.corner, yRadius: Sheet.corner)
        Look.Token.bg2.color.setFill()
        shape.fill()
        Look.Token.line2.color.setStroke()
        shape.stroke()
    }
}

/// An action of a sheet, drawn by its role: Cancel and secondary ringed, primary filled in act, destructive in bad.
/// While it holds the focus a light ring, ink3 and thinner than the primary's weight, sits 2 points outside it. It
/// takes the focus with or without the system's full keyboard access: a sheet is answered from the keyboard too.
final class SheetButton: PanelButton {
    let role: Sheet.Role

    init(_ action: Sheet.Action, target: AnyObject, action selector: Selector) {
        role = action.role
        super.init(action.title, primary: [.primary, .destructive].contains(role), hint: action.hint, target: target, action: selector)
        least = 0
        if role == .destructive { fill = .bad }
        focusRingType = .none
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func becomeFirstResponder() -> Bool { redrawRing(super.becomeFirstResponder()) }
    override func resignFirstResponder() -> Bool { redrawRing(super.resignFirstResponder()) }

    /// The ring is drawn outside the button: its superview redraws around it. Returns `done`.
    private func redrawRing(_ done: Bool) -> Bool {
        superview?.setNeedsDisplay(frame.insetBy(dx: -4, dy: -4))
        return done
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard window?.firstResponder === self else { return }
        let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: -2.5, dy: -2.5), xRadius: Look.control + 2.5, yRadius: Look.control + 2.5)
        ring.lineWidth = 1.5
        Look.Token.ink3.color.setStroke()
        ring.stroke()
    }
}

