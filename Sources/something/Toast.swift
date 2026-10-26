// The toast: a short sentence that something did what was asked, at the bottom of the center, in the window layer.
// One at a time (a new one replaces the one shown), an optional action (Undo, Show), a quiet variant for what is only
// information, and it leaves by itself. It never takes the focus, so typing goes on where it was, and VoiceOver reads
// it out, since the person may not be looking at the bottom of the window.
import AppKit

final class Toast: NSView {
    struct Action {
        let label: String, act: () -> Void
    }

    let words: String
    private static let pad: CGFloat = 9
    private var action: Action?
    private var timer: Timer?
    /// Its distance from the center's bottom edge, -22 once in place.
    private(set) var bottom: NSLayoutConstraint?
    private var motion = Look.Motion.calm
    private let button: NSButton?
    /// Whether it is in place or arriving, false once it starts to leave.
    private(set) var shown = false

    /// Shows `words` in `layer`, centred at the bottom of `center`, in place of any toast there, and returns it. It
    /// leaves after `seconds`, or when its action is clicked, which acts once; it slides only under Calm `motion`.
    @discardableResult
    static func show(_ words: String, action: Action? = nil, quiet: Bool = false, seconds: TimeInterval = 3.2,
                     motion: Look.Motion = .calm, in layer: WindowLayer, under center: NSView) -> Toast {
        layer.subviews.compactMap { $0 as? Toast }.forEach { $0.leave(now: true) }
        let toast = Toast(words, action: action, quiet: quiet)
        layer.hold(toast)
        // It starts below the center's edge (170% of its height, as the mockup's) and rises 22 points above it.
        let bottom = toast.bottomAnchor.constraint(equalTo: center.bottomAnchor, constant: 68 - 22)
        NSLayoutConstraint.activate([bottom, toast.centerXAnchor.constraint(equalTo: center.centerXAnchor),
                                     toast.widthAnchor.constraint(lessThanOrEqualTo: center.widthAnchor, constant: -32)])
        (toast.bottom, toast.motion) = (bottom, motion)
        layer.layoutSubtreeIfNeeded()
        toast.move(to: -22)
        toast.shown = true
        toast.timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak toast] _ in toast?.leave() }
        layer.announce(words)
        return toast
    }

    private init(_ words: String, action: Action?, quiet: Bool) {
        (self.words, self.action) = (words, action)
        button = action.map { NSButton(title: $0.label, target: nil, action: nil) }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView.symbol(quiet ? "info.circle" : "checkmark", 12, .semibold, tint: .bg)
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 14), icon.heightAnchor.constraint(equalToConstant: 14)])
        let text = NSTextField(labelWithString: words)
        (text.font, text.textColor, text.lineBreakMode) = (Look.font(.ui, size: 12.5, weight: .medium), Look.Token.bg.color, .byTruncatingMiddle)
        // A long path or title is cut in its middle rather than widening the toast past the center.
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [icon, text] + [button].compactMap { $0 })
        row.spacing = 10
        // The action's veil reaches `pad` beyond its words on each side, as the mockup's padding does.
        row.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: button == nil ? 16 : 8 + Toast.pad)
        row.setCustomSpacing(10 + Toast.pad, after: text)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: 40), row.leadingAnchor.constraint(equalTo: leadingAnchor),
                                     row.trailingAnchor.constraint(equalTo: trailingAnchor), row.centerYAnchor.constraint(equalTo: centerYAnchor)])
        if let button {
            button.isBordered = false
            // A click acts; no key reaches it, and it never draws the focus away from where the person types.
            button.refusesFirstResponder = true
            (button.font, button.contentTintColor) = (Look.font(.ui, size: 12.5, weight: .medium), Look.Token.bg.color)
            (button.target, button.action) = (self, #selector(act))
            button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        }
    }

    required init?(coder: NSCoder) { nil }

    /// Ink, with the action on a veil of white by day and of black by night. Drawn here rather than by layers, whose
    /// colours would not follow a change between day and night.
    override func draw(_ dirtyRect: NSRect) {
        Look.Token.ink.color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        guard let button else { return }
        (Look.isDark(effectiveAppearance) ? Look.srgb(0, 0.08) : Look.srgb(0xFFFFFF, 0.12)).setFill()
        let veil = convert(button.bounds, from: button).insetBy(dx: -Toast.pad, dy: 0)
        NSBezierPath(roundedRect: veil, xRadius: Look.control + 1, yRadius: Look.control + 1).fill()
    }

    /// Clicked: the action acts once, and the toast leaves.
    @objc func act() {
        let action = action
        self.action = nil
        leave()
        action?.act()
    }

    /// Leaves by sliding down, or at once (`now`) when another takes its place.
    func leave(now: Bool = false) {
        timer?.invalidate()
        shown = false
        if now { return removeFromSuperview() }
        move(to: 68 - 22) { [weak self] in self?.removeFromSuperview() }
    }

    private func move(to constant: CGFloat, then done: (() -> Void)? = nil) {
        // Reduced, it is in place at once: an animation of no duration would still land on a later turn.
        let duration = Look.duration(0.45, Look.motion(motion))
        guard duration > 0 else {
            bottom?.constant = constant
            done?()
            return
        }
        let bottom = bottom
        Look.animate(duration, Look.out, { bottom?.moving.constant = constant }, done: done)
    }
}
