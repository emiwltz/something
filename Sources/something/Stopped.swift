// What covers a space whose page stopped (its web content process ended: a crash, or macOS took its memory back): the
// page dimmed under a veil, and a calm card in the middle with the sign's stopped face, "This space stopped", Reload,
// Ask Its Assistant to Fix It and when it stopped. After two stops it says that something waits for the person
// before it reloads again (SpaceView pauses its watch). The card and the veil are drawn in draw(_:), so a picture made
// with cacheDisplay shows them as the screen does.
import AppKit
import SomethingCore

final class Stopped: NSView {
    // Weak: the space holds its cover, and a closed space must go with its web view.
    weak var space: SpaceView?
    let assistant: AssistantModel
    let reload: PanelButton, fix: PanelButton
    private let card = NSStackView()

    /// The cover of `space`, which stopped; its Fix button asks `assistant`, and it fades in under Calm `motion`.
    init(_ space: SpaceView, assistant: AssistantModel, motion: Look.Motion = .calm) {
        (self.space, self.assistant) = (space, assistant)
        reload = PanelButton("Reload", symbol: "arrow.clockwise")
        fix = PanelButton("Ask Its Assistant to Fix It", primary: true)
        super.init(frame: .zero)
        (reload.target, reload.action, fix.target, fix.action) = (self, #selector(reloadNow), self, #selector(fixNow))
        (reload.least, fix.least) = (0, 0)
        fix.enable(!assistant.noAgent)
        let file = space.space.location.lastPathComponent
        let (said, when) = Stopped.words(space.stops, file: file, calendar: space.calendar, hours: space.hours)
        let sign = NSImageView(image: Sign.image(.limit, side: 60))
        sign.setAccessibilityLabel("Stopped")
        let title = Stopped.label("This space stopped", Look.titleM.font, .ink, leading: 1.15, kern: -0.55)
        let body = Stopped.label(said, Look.font(.ui, size: 13), .ink2, leading: 1.5, balanced: true)
        let line = Stopped.label(when, Look.font(.code, size: 11), .ink3, leading: 1)
        let buttons = NSStackView(views: [reload, fix])
        buttons.spacing = 8
        [sign, title, body, buttons, line].forEach(card.addArrangedSubview)
        (card.orientation, card.alignment, card.spacing) = (.vertical, .centerX, 10)
        card.setCustomSpacing(16, after: sign)
        card.setCustomSpacing(16, after: body)
        card.setCustomSpacing(14, after: buttons)
        card.edgeInsets = NSEdgeInsets(top: 28, left: 30, bottom: 22, right: 30)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.setAccessibilityElement(true)
        card.setAccessibilityRole(.group)
        card.setAccessibilityLabel("This space stopped")
        addSubview(card)
        NSLayoutConstraint.activate([card.widthAnchor.constraint(equalToConstant: 420), card.centerXAnchor.constraint(equalTo: centerXAnchor),
                                     card.centerYAnchor.constraint(equalTo: centerYAnchor)])
        // The page under it, as the mockup dims it: grey, a little blurred (on the screen only), behind the veil.
        wantsLayer = true
        layerUsesCoreImageFilters = true
        layer?.backgroundFilters = [CIFilter(name: "CIColorControls", parameters: [kCIInputSaturationKey: 0]),
                                    CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: 2])].compactMap { $0 }
        let calm = Look.duration(0.45, Look.motion(motion))
        guard calm > 0 else { return }
        alphaValue = 0
        Look.animate(calm, Look.out, { [weak self] in self?.animator().alphaValue = 1 })
    }

    required init?(coder: NSCoder) { nil }

    /// What the card says after `stops` (oldest first) of the page in `file`: why nothing is lost, or, after two, that
    /// something waits; and the file with the times of the last two stops, in `hours`' 12 or 24 hours.
    static func words(_ stops: [Date], file: String, calendar: Calendar, hours: Locale) -> (said: String, when: String) {
        let times = stops.suffix(2).map { Words.time(iso8601.string(from: $0), now: stops.last ?? $0, calendar: calendar, locale: Words.english, clock: hours) }
        let said = stops.count < 2 ? "Its page stopped responding. Nothing is lost: the page, its memory and its assistant are as they were."
            : "It stopped \(stops.count == 2 ? "twice" : "\(stops.count) times"). something won't reload it again until you ask."
        return (said, times.isEmpty ? file : "\(file) · stopped at " + times.joined(separator: " and "))
    }

    /// What Ask Its Assistant to Fix It sends: the space's title and its file, and something's own sentence.
    static func fault(_ space: SpaceView) -> AssistantModel.Fault {
        AssistantModel.Fault(title: space.title, name: space.space.location.lastPathComponent, codes: [AssistantModel.Fault.stopped])
    }

    private static func label(_ string: String, _ font: NSFont, _ color: Look.Token, leading: CGFloat, kern: CGFloat = 0, balanced: Bool = false) -> NSTextField {
        let style = NSMutableParagraphStyle()
        // The mockup's line height, in points: a multiple of Onest's own tall line would be taller.
        (style.alignment, style.minimumLineHeight, style.maximumLineHeight) = (.center, font.pointSize * leading, font.pointSize * leading)
        let field = NSTextField(wrappingLabelWithString: "")
        field.attributedStringValue = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color.color, .paragraphStyle: style, .kern: kern])
        field.preferredMaxLayoutWidth = balanced ? Sheet.balanced(field, width: 360) : 360
        return field
    }

    @objc func reloadNow() { space?.load() }

    @objc func fixNow() {
        guard let space else { return }
        assistant.fix(Stopped.fault(space))
        space.asked()
        fix.enable(false)
    }

    // A screen reader hears that the open space stopped, as the mockup's role="alert" card says it.
    override func viewDidMoveToWindow() {
        guard window != nil else { return }
        NSAccessibility.post(element: card, notification: .announcementRequested,
                             userInfo: [.announcement: "This space stopped", .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    override func draw(_ dirtyRect: NSRect) {
        // The mockup's page at .25 opacity, blurred: without the blur (cacheDisplay, or a reduced-transparency Mac)
        // the page would read too clearly, so the veil leaves less of it.
        Look.Token.bg.color.withAlphaComponent(0.88).setFill()
        bounds.fill()
        let shape = NSBezierPath(roundedRect: card.frame, xRadius: Look.card, yRadius: Look.card)
        Look.drawFloat(card.frame, radius: Look.card, fill: .bg2, ring: false, appearance: effectiveAppearance)
        Look.Token.bg2.color.setFill()
        shape.fill()
        Look.floatRing.token.color.setStroke()
        NSBezierPath(roundedRect: card.frame.insetBy(dx: -0.5, dy: -0.5), xRadius: Look.card + 0.5, yRadius: Look.card + 0.5).stroke()
    }
}
