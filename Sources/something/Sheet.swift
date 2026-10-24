// The one layout of every sheet of something, as the mockup's dialog: an icon in a tile at the left, a title in
// Fraunces, its sentence (some words bold), rows, a block of its own (a link's address), a fine print, and the actions
// at the bottom right, the safe one first. The alert variant (Quit) centres it all under the sign, its actions sharing
// the width. It hangs from the toolbar over the space, beside the sidebar. A space cannot draw it, so a space cannot
// answer it. Escape presses the cancel action, or the safe one when there is none; the safe action holds the focus at first, and Return presses the
// focused action unless it is destructive: a key meant for something else never confirms what cannot be undone.
import AppKit

final class Sheet: NSPanel {
    enum Role { case cancel, secondary, primary, destructive }
    struct Action { var title: String, role: Role }
    enum Icon { case symbol(String), sign }
    /// A sentence in parts, each bold or not: the words a space chose are never read as markup.
    typealias Words = [(text: String, bold: Bool)]
    static let width: CGFloat = 380, corner: CGFloat = 14

    let isAlert: Bool
    private(set) var buttons: [SheetButton] = []
    /// The role of the action pressed; nil until one is.
    private(set) var chosen: Role?
    /// Called once an action was pressed: the window it hangs from takes it away.
    var ended: () -> Void = {}

    /// A sheet `width` wide of the parts given, in this order; `alert` centres them. Text the page gave is shown as is.
    init(icon: Icon?, title: String, body: Words = [], rows: [(symbol: String, label: String, meta: String?)] = [],
         block: NSView? = nil, fine: String? = nil, actions: [Action], alert: Bool = false, width: CGFloat = Sheet.width) {
        isAlert = alert
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: 100), styleMask: .borderless, backing: .buffered, defer: true)
        (isOpaque, backgroundColor, hasShadow, self.title) = (false, .clear, true, title)
        let tiled = icon.map { Self.tile($0, alert: alert) }
        let text = Self.column(width: width, alert: alert, tiled: tiled != nil)
        let heading = Self.label([(title, false)], Look.titleS, width: text, kern: -0.3, centred: alert)
        heading.preferredMaxLayoutWidth = Self.balanced(heading.attributedStringValue, width: text)
        var parts: [NSView] = [heading]
        if !body.isEmpty { parts.append(Self.label(body, Look.body, color: .ink2, width: text, centred: alert)) }
        if !rows.isEmpty { parts.append(Self.list(rows, width: text)) }
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
        // The safe action: Cancel in a sheet; in an alert, its primary one, which the alert makes the safe one.
        initialFirstResponder = alert ? buttons.first { $0.role == .primary } : buttons.first { $0.role == .cancel }
        makeFirstResponder(initialFirstResponder)
        (buttons.first { $0.role == .cancel } ?? initialFirstResponder as? SheetButton)?.keyEquivalent = "\u{1b}"
        setAccessibilitySubrole(.dialog)
    }

    override var canBecomeKey: Bool { true }

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

    /// How wide a sheet `width` wide sets its text: its insets, and the tile beside the text unless `alert` centres it.
    static func column(width: CGFloat = Sheet.width, alert: Bool = false, tiled: Bool = true) -> CGFloat {
        width - 40 - (alert || !tiled ? 0 : 46)
    }

    /// The narrowest width up to `width` that keeps `text` on as many lines as `width` does: the mockup balances the
    /// lines of a title (text-wrap: balance) rather than leave one word alone on the last.
    static func balanced(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        func height(_ wide: CGFloat) -> CGFloat {
            text.boundingRect(with: NSSize(width: wide, height: 10_000), options: .usesLineFragmentOrigin).height.rounded(.up)
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
            let image = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage())
            (image.symbolConfiguration, image.contentTintColor) = (NSImage.SymbolConfiguration(pointSize: 14, weight: .regular), Look.Token.ink2.color)
            let tile = Box(image, fill: .sunk, ring: .line, radius: Look.control, insets: NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8))
            NSLayoutConstraint.activate([image.widthAnchor.constraint(equalToConstant: 16), image.heightAnchor.constraint(equalToConstant: 16)])
            return tile
        case .sign:
            // The app's own tile stays light by night, as its icon does.
            let tile = Box(NSImageView(image: Sign.image(.listen, side: 30)), fill: .bg, ring: .line2, radius: 11,
                           insets: NSEdgeInsets(top: 7, left: 7, bottom: 7, right: 7))
            tile.appearance = NSAppearance(named: .aqua)
            return tile
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

    /// The rows of what a sheet is about, a symbol, a label and a quiet detail each, in a ringed list.
    private static func list(_ rows: [(symbol: String, label: String, meta: String?)], width: CGFloat) -> NSView {
        let lines = NSStackView()
        (lines.orientation, lines.spacing) = (.vertical, 0)
        for (index, row) in rows.enumerated() {
            if index > 0 { lines.addArrangedSubview(Box(NSView(), fill: .line)) }
            let image = NSImageView(image: NSImage(systemSymbolName: row.symbol, accessibilityDescription: nil) ?? NSImage())
            (image.symbolConfiguration, image.contentTintColor) = (NSImage.SymbolConfiguration(pointSize: 11, weight: .regular), Look.Token.ink3.color)
            // One line at its own height, centred with its symbol and its detail.
            let label = label([(row.label, false)], Look.Style(face: Look.medium.face, size: Look.medium.size, weight: Look.medium.weight, leading: 1),
                              width: width - 80)
            let meta = row.meta.map { RequestPanel.text($0, Look.Style(face: .code, size: 11, weight: .regular, leading: 1), .ink3) }
            // The label takes the room left, so that each detail stands at the right edge.
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            image.widthAnchor.constraint(equalToConstant: 14).isActive = true
            meta?.setContentHuggingPriority(.required, for: .horizontal)
            let line = NSStackView(views: [image, label, meta].compactMap { $0 })
            (line.spacing, line.distribution, line.alignment) = (9, .fill, .centerY)
            line.heightAnchor.constraint(greaterThanOrEqualToConstant: Look.row + 3).isActive = true
            lines.addArrangedSubview(line)
        }
        lines.arrangedSubviews.forEach { $0.widthAnchor.constraint(equalToConstant: width - 24).isActive = true }
        lines.arrangedSubviews.filter { $0 is Box }.forEach { $0.heightAnchor.constraint(equalToConstant: 1).isActive = true }
        return Box(lines, fill: .bg, ring: .line, radius: Look.card, insets: NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12))
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
/// While it holds the focus it is ringed in ink 2 points outside its edge, as the mockup marks the safe action. It
/// takes the focus with or without the system's full keyboard access: a sheet is answered from the keyboard too.
final class SheetButton: PanelButton {
    let role: Sheet.Role

    init(_ action: Sheet.Action, target: AnyObject, action selector: Selector) {
        role = action.role
        super.init(action.title, primary: [.primary, .destructive].contains(role), target: target, action: selector)
        least = 0
        if role == .destructive { fill = .bad }
        focusRingType = .none
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func becomeFirstResponder() -> Bool {
        defer { superview?.setNeedsDisplay(frame.insetBy(dx: -4, dy: -4)) }
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        defer { superview?.setNeedsDisplay(frame.insetBy(dx: -4, dy: -4)) }
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard window?.firstResponder === self else { return }
        let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: -3, dy: -3), xRadius: Look.control + 3, yRadius: Look.control + 3)
        ring.lineWidth = 2
        Look.Token.ink.color.setStroke()
        ring.stroke()
    }
}
