// The strip across the top of a space whose page left an error uncaught: "Script error" in something's words, then
// the page's first error line drawn as a quote (monospaced, between quote marks, on its own inset), so that a page
// cannot make its words look like something speaking or asking; Ask to Fix and a close button. It pushes the page
// down rather than covering it, and the page keeps running. Ask to Fix sends the assistant the codes only, never the
// page's words. Its fills are drawn in draw(_:), so a picture made with cacheDisplay shows them as the screen does.
import AppKit

final class ScriptError: NSView {
    weak var space: SpaceView?
    let assistant: AssistantModel
    let quote: NSTextField
    let fix: PanelButton, close: NSButton
    static let height: CGFloat = 40

    /// The strip of `space`, nil when it has no error to show or the person closed it; Ask to Fix asks `assistant`.
    init?(_ space: SpaceView, assistant: AssistantModel) {
        guard let line = space.firstError, !space.dismissed, !space.stopped else { return nil }
        (self.space, self.assistant) = (space, assistant)
        quote = NSTextField(labelWithString: "“\(line)”")
        fix = PanelButton("Ask to Fix")
        close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close") ?? NSImage(), target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: ScriptError.height))
        let icon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil) ?? NSImage())
        (icon.symbolConfiguration, icon.contentTintColor) = (.init(pointSize: 12.5, weight: .semibold), Look.Token.bad.color)
        let title = NSTextField(labelWithString: "Script error")
        (title.font, title.textColor) = (Look.font(.ui, size: 12.5, weight: .semibold), Look.Token.ink.color)
        (quote.font, quote.textColor, quote.lineBreakMode) = (Look.font(.code, size: 11.5), Look.Token.ink2.color, .byTruncatingTail)
        quote.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        quote.toolTip = line
        quote.setAccessibilityLabel("The page's message: \(line)")
        let inset = Box(quote, fill: .hover, radius: 5, insets: NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6))
        inset.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        (fix.height, fix.least, fix.target, fix.action) = (26, 0, self, #selector(fixNow))
        fix.isEnabled = !assistant.noAgent
        fix.alphaValue = fix.isEnabled ? 1 : 0.45
        close.isBordered = false
        (close.contentTintColor, close.target, close.action, close.toolTip) = (Look.Token.ink2.color, self, #selector(closeNow), "Close")
        close.symbolConfiguration = .init(pointSize: 10.5, weight: .semibold)
        let room = NSView()
        room.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [icon, title, inset, room, fix, close])
        (row.spacing, row.edgeInsets) = (10, NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 8))
        row.setCustomSpacing(9, after: title)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     row.centerYAnchor.constraint(equalTo: centerYAnchor), close.widthAnchor.constraint(equalToConstant: 26),
                                     close.heightAnchor.constraint(equalToConstant: 26), icon.widthAnchor.constraint(equalToConstant: 15)])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Script error")
    }

    required init?(coder: NSCoder) { nil }

    /// The page's error as the strip shows it, in one line of at most 200 characters: the first line of its `message`,
    /// then its `file` and `line` when both are known ("TypeError: … · brief.html, line 142"). nil when the message is
    /// empty.
    static func line(_ message: String, file: String? = nil, line: String? = nil) -> String? {
        func first(_ text: String?) -> String { text?.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "" }
        guard !first(message).isEmpty else { return nil }
        let place = first(file).isEmpty || first(line).isEmpty ? "" : " · \(first(file)), line \(first(line))"
        let whole = first(message) + place
        return whole.count > 200 ? whole.prefix(199) + "…" : whole
    }

    /// Ask to Fix: the space's title and name and the codes of its errors, in something's words.
    @objc func fixNow() {
        guard let space else { return }
        assistant.fix(AssistantModel.Fault(title: space.title, name: space.space.name, codes: space.faults))
        closeNow()
    }

    @objc func closeNow() {
        space?.dismissed = true
        space?.show(strip: nil)
    }

    // A screen reader hears it, as the mockup's role="status" strip says it.
    override func viewDidMoveToWindow() {
        guard window != nil else { return }
        NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [.announcement: "Script error"])
    }

    override func draw(_ dirtyRect: NSRect) {
        Look.Token.bg.color.setFill()
        bounds.fill()
        Look.Token.line.color.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        Look.Token.bad.color.setFill()
        NSRect(x: 0, y: 0, width: 2, height: bounds.height).fill()
    }
}
