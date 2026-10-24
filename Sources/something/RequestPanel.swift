// The request panel: a window of the Mac of its own, beside the main window, that no space can draw, imitate or answer.
// It shows the queue's request on screen (Requests.swift), with "‹ 1 of 3 ›" while more wait: who asks, the effect in
// words first, where it acts, the exact text, then Deny and Allow Once. It never takes the keys when it arrives: a key
// typed in a page must never answer it. Allow Once arms 0.5 s after a request appears, and then answers a click, or
// VoiceOver's press once the person made the panel key themselves (a click on it, or Show Request); no key, Return and
// Space included, ever presses it. Closing it denies, and so does Escape while it has the keys. The exact command is
// folded to four lines; ↕ or the grip at its bottom-right corner make the panel larger, its footer always in sight.
import AppKit
import SomethingAgents
import SomethingCore

/// Who asks, in the panel's words: the program, the space the request belongs to, whether it is that space's
/// assistant, the agent's own name, and its folder with ~. What is not known is left out.
struct Asker: Equatable {
    var program: String, space: String? = nil, assistant = false, name: String? = nil, folder: String? = nil
}

class RequestPanel: NSPanel {
    static let width: CGFloat = 392, wide: CGFloat = 560, widths: ClosedRange<CGFloat> = 360...720, arming: TimeInterval = 0.5
    let decide: (Answer) -> Void
    /// Moves the queue's request on screen by one, back or on.
    var step: (Int) -> Void = { _ in }
    /// The clock Allow Once's arming reads, in seconds: a test's seam.
    var clock: () -> TimeInterval = { CACurrentMediaTime() }
    /// Where Copy Command writes: a test's seam.
    var pasteboard = NSPasteboard.general
    private(set) var request: Request?, who: Asker?
    /// The exact command's box, when the request has one.
    private(set) var code: CommandBox?
    /// Whether the person sized the panel, by ↕ or the grip: it keeps that size from one request to the next, until ↕
    /// folds it again.
    private(set) var sized = false
    /// Set once it was put away; `told` once it says that the answer did not reach the agent.
    private(set) var dismissed = false, told = false
    /// Whether the person made it key themselves, by a click on it or Show Request. Lost with the keys.
    private(set) var held = false
    private var shownAt: TimeInterval = 0, ticker: Timer?
    let header = PanelHeader(), allowButton = ArmedButton("Allow Once", primary: true)
    private(set) var denyButton = PanelButton("Deny", hint: "esc")
    /// For a question: the boxes of each question's options, and the field where an answer can be typed.
    private(set) var boxes: [[NSButton]] = [], typed: [NSTextField] = []
    private let body = NSStackView(), foot = NSStackView(), grip = Grip()
    private var widthRule = NSLayoutConstraint()
    /// The window and screen it was last placed beside, to place it again once it changed size.
    private weak var beside: NSWindow?
    /// The open "Why am I asked?" sentence, and Copy Command's presses: only the last one's reset puts its title back.
    private weak var whyBox: Box?
    private var copies = 0
    private var desk: NSRect?

    init(decide: @escaping (Answer) -> Void) {
        self.decide = decide
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 300),
                   styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: true)
        (isReleasedWhenClosed, hidesOnDeactivate, level) = (false, false, .floating)
        // Over a space in full screen too, and on the Space the person is on.
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        // Answerable while a sheet of the main window waits: an agent's request does not wait for it.
        worksWhenModal = true
        // Moved by its header only, which says so by being the one place that drags.
        isMovable = false
        (titleVisibility, titlebarAppearsTransparent, backgroundColor) = (.hidden, true, Look.Token.bg2.color)
        if let close = standardWindowButton(.closeButton) {
            (close.target, close.action) = (self, #selector(deny))
            close.setAccessibilityLabel("Close: deny")
        }
        header.step = { [weak self] in self?.step($0) }
        (allowButton.target, allowButton.action) = (self, #selector(allow))
        allowButton.voice = { [weak self] in self?.voicePress() ?? false }
        (body.orientation, body.alignment, body.spacing) = (.vertical, .leading, 11)
        body.edgeInsets = NSEdgeInsets(top: 15, left: 16, bottom: 4, right: 16)
        (foot.spacing, foot.edgeInsets) = (8, NSEdgeInsets(top: 12, left: 16, bottom: 14, right: 16))
        let root = NSStackView(views: [header, body, foot])
        (root.orientation, root.spacing) = (.vertical, 0)
        widthRule = root.widthAnchor.constraint(equalToConstant: Self.width)
        widthRule.isActive = true
        [header, body, foot].forEach { $0.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        let content = Box(root, fill: .bg2)
        grip.drag = { [weak self] in self?.resize(to: $0) }
        grip.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(grip)
        NSLayoutConstraint.activate([grip.widthAnchor.constraint(equalToConstant: 14), grip.heightAnchor.constraint(equalToConstant: 14),
                                     grip.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -2),
                                     grip.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -2)])
        contentView = content
    }

    /// Where the panel goes: across the top-right corner of `window`, half outside it so that no page could have drawn
    /// it, its top 8 points below the toolbar (`toolbar` high), kept 16 points inside `screen`; at the screen's top
    /// right when the window is in full screen. Returns the panel's origin.
    static func place(_ size: NSSize, window: NSRect, toolbar: CGFloat, screen: NSRect, fullScreen: Bool) -> NSPoint {
        let right = screen.maxX - size.width - 16
        let x = fullScreen ? right : min(right, window.maxX - (size.width / 2).rounded())
        let top = min(fullScreen ? screen.maxY : window.maxY, screen.maxY) - toolbar - 8
        return NSPoint(x: max(screen.minX + 16, x), y: max(screen.minY, top - size.height))
    }

    /// Brings the panel in beside `window`, in front but without the keys: a key typed in a page or in another app must
    /// never reach it.
    func arrive(beside window: NSWindow?) {
        if let window { place(beside: window) }
        orderFrontRegardless()
    }

    /// Puts the panel in its place beside `window`, on `screen` (the window's own by default).
    func place(beside window: NSWindow, screen: NSRect? = nil) {
        let full = window.styleMask.contains(.fullScreen)
        guard let screen = screen ?? (full ? window.screen?.frame : window.screen?.visibleFrame) else { return center() }
        (beside, desk) = (window, screen)
        setFrameOrigin(Self.place(frame.size, window: window.frame, toolbar: window.frame.height - window.contentLayoutRect.maxY,
                                  screen: screen, fullScreen: full))
    }

    /// The queue's position ("2 of 3"), shown in the header with its steps; nil for a lone request.
    var position: String? {
        get { header.position }
        set { header.position = newValue }
    }

    /// Shows `prompt`, asked by `who` `age` ago, in place of what the panel showed, and arms Allow Once again.
    func show(_ prompt: Prompt, who: Asker, age: String?) {
        (request, self.who, code) = (prompt.request, who, nil)
        // Its labels are made for the first width; size(width:) widens them to the kept one.
        let kept = widthRule.constant
        widthRule.constant = Self.width
        let question = prompt.request.kind == "question"
        title = question ? "\(who.program) asks you a question" : "\(who.program) wants to \(Words.wants(prompt.request.tool))"
        header.kind = question ? "Question" : "Permission"
        (boxes, typed) = ([], [])
        var views = [whoRow(title, Words.who(space: who.space, assistant: who.assistant, name: who.name, age: age), who.program)]
        if question {
            prompt.questions.forEach { views += ask($0) }
            denyButton = PanelButton("Don't Answer", hint: "esc")
            foot.setViews([denyButton, PanelButton("Answer", primary: true, target: self, action: #selector(reply))], in: .trailing)
        } else {
            views.append(Self.text(Words.effect(prompt.request.tool, space: who.space), Look.body))
            let rows = [("Space", who.space), ("Folder", who.folder)].compactMap { key, value in value.map { (key, $0) } }
            if !rows.isEmpty { views.append(Self.table(rows)) }
            if let exact = prompt.input ?? prompt.request.about {
                let code = CommandBox(exact, target: self, action: #selector(expand))
                views += [code, links()]
                self.code = code
            }
            denyButton = PanelButton("Deny", hint: "esc")
            foot.setViews([denyButton, allowButton], in: .trailing)
        }
        (denyButton.target, denyButton.action, denyButton.keyEquivalent) = (self, #selector(deny), "\u{1b}")
        body.setViews(views, in: .top)
        stretch(views)
        size(width: kept, height: sized ? frame.height : nil)
        shownAt = clock()
        tick()
        ticker?.invalidate()
        guard !question else { return }
        let ticker = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            // tick() stops it once armed, after enabling the button.
            guard let self else { return timer.invalidate() }
            tick()
        }
        // In every mode: it arms while a sheet waits in a modal loop, or a menu is open.
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    /// Whether Allow Once answers: 0.5 s after the request appeared, so that no click meant for something else lands on
    /// it.
    var armed: Bool { clock() - shownAt >= Self.arming }

    /// Draws how far Allow Once has armed; once it has, it takes a click.
    func tick() {
        allowButton.progress = min(1, max(0, (clock() - shownAt) / Self.arming))
        allowButton.isEnabled = armed
        if armed { ticker?.invalidate() }
    }

    /// Sizes the panel `width` wide, kept within 360–720 points: the command folded to four lines, or the whole panel
    /// `height` high, the command taking what is left; never taller than the screen below it, so the footer stays in
    /// sight.
    func size(width: CGFloat, height: CGFloat? = nil) {
        let width = min(Self.widths.upperBound, max(Self.widths.lowerBound, width.rounded()))
        let delta = width - widthRule.constant
        widthRule.constant = width
        Self.fields(in: body).forEach { $0.preferredMaxLayoutWidth += delta }
        if let code, let content = contentView {
            code.fold(0)
            content.layoutSubtreeIfNeeded()
            let rest = frameRect(forContentRect: NSRect(origin: .zero, size: content.fittingSize)).height - code.shown
            let room = desk.map { frame.maxY - $0.minY - 16 } ?? .greatestFiniteMagnitude
            code.fold(height.map { min($0, room) - rest } ?? min(code.full, CommandBox.folded))
            code.expand.setAccessibilityLabel(sized ? "Fold the command" : "Expand the command")
        }
        fit()
    }

    /// ↕: the panel 560 points wide and as tall as the whole command needs, or back to its first size; in its place
    /// across the window's corner again.
    @objc func expand() {
        guard let code else { return }
        sized.toggle()
        size(width: sized ? Self.wide : Self.width)
        if sized { size(width: Self.wide, height: frame.height - code.shown + code.full) }
        if let beside { place(beside: beside, screen: desk) }
    }

    /// The grip's drag: the panel at `size`, within its bounds, its top-left corner staying put.
    func resize(to size: NSSize) {
        sized = true
        self.size(width: size.width, height: max(300, size.height))
    }

    /// Copy Command: the exact text the agent sent, as it sent it.
    @objc func copyCommand(_ sender: NSButton) {
        guard let code else { return }
        pasteboard.clearContents()
        pasteboard.setString(code.exact, forType: .string)
        sender.title = "Copied"
        copies += 1
        let press = copies
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in if self?.copies == press { sender.title = "Copy Command" } }
    }

    /// Why am I asked?: says, under the links, why this request waits here; a second press takes it away.
    @objc func why(_ sender: NSButton) {
        if let shown = whyBox {
            shown.removeFromSuperview()
            whyBox = nil
        } else if let who {
            let words = who.assistant ? "\(who.program) is this space's assistant: it may change your spaces and run something's own commands "
                + "without asking; everything else it does asks you, as its own settings decide, and"
                : "\(who.program) asks you when its own settings decide; its request"
            let field = Self.text(words + " waits here, in a window of the Mac that no page can draw or click. Allow Once covers this one "
                                  + "request, this one time.", Look.small, .ink2)
            field.preferredMaxLayoutWidth = widthRule.constant - 52
            let box = Box(field, fill: .hover, radius: 8, insets: NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10))
            body.addArrangedSubview(box)
            stretch([box])
            whyBox = box
        }
        sender.setAccessibilityExpanded(whyBox != nil)
        size(width: widthRule.constant, height: sized ? frame.height : nil)
    }

    /// The boxes among `views` take the body's width, less its insets.
    private func stretch(_ views: [NSView]) {
        for case let box as Box in views { box.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -32).isActive = true }
    }

    private static func fields(in view: NSView) -> [NSTextField] {
        ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(fields)
    }

    /// Sizes the panel to what it shows, keeping its top where the person looks.
    private func fit() {
        guard let content = contentView else { return }
        content.layoutSubtreeIfNeeded()
        let top = frame.maxY
        var fitted = frameRect(forContentRect: NSRect(origin: .zero, size: content.fittingSize))
        fitted.origin = NSPoint(x: frame.minX, y: top - fitted.height)
        setFrame(fitted, display: isVisible)
    }

    /// Says `sentence` in place of the request, under who asked, with OK, which puts the panel away as Escape does.
    func tell(_ sentence: String) {
        (told, code) = (true, nil)
        ticker?.invalidate()
        body.setViews(Array(body.arrangedSubviews.prefix(1)) + [Self.text(sentence, Look.body)], in: .top)
        let ok = PanelButton("OK", primary: true, target: self, action: #selector(deny))
        ok.keyEquivalent = "\r"
        foot.setViews([ok], in: .trailing)
        fit()
    }

    /// Show Request: the person asked for the panel, so it takes the keys.
    func present() {
        orderFrontRegardless()
        makeKey()
        held = true
    }

    func dismiss() {
        ticker?.invalidate()
        orderOut(nil)
        dismissed = true
    }

    override var canBecomeKey: Bool { true }

    /// A click on the panel is the person's own: it makes the panel key, and VoiceOver's press may then answer.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { held = true }
        super.sendEvent(event)
    }

    override func resignKey() {
        held = false
        super.resignKey()
    }

    /// ← and → walk the queue while the panel has the keys.
    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .leftArrow?: step(-1)
        case .rightArrow?: step(1)
        default: super.keyDown(with: event)
        }
    }

    /// Escape denies.
    override func cancelOperation(_ sender: Any?) { deny() }

    /// VoiceOver's press on Allow Once, the one way to it that is not a click: only once armed, and only while the
    /// panel is key because the person made it so.
    func voicePress() -> Bool {
        guard armed, held, isKeyWindow else { return false }
        decide(.once)
        return true
    }

    /// Allow Once's click; nothing before it is armed.
    @objc func allow() { if armed { decide(.once) } }
    @objc func deny() { decide(.deny) }
    @objc func reply() { decide(.choice(choice)) }
    /// Does nothing: AppKit groups radio buttons by a shared action, and only that grouping is needed.
    @objc func chose() {}

    /// Each question's chosen labels, with the typed text when there is one.
    var choice: [[String]] {
        zip(boxes, typed).map { options, field in
            options.filter { $0.state == .on }.map(\.title) + (field.stringValue.isEmpty ? [] : [field.stringValue])
        }
    }

    // MARK: The parts

    /// The sign, the title in Fraunces, and under it the waiting eyes with the space, who asks and when.
    private func whoRow(_ headline: String, _ line: String, _ program: String) -> NSView {
        let sign = SignView(.listen, side: 36)
        sign.name = "\(program) is waiting"
        let eyes = NSImageView(image: Sign.miniEyes(.wait, template: false))
        let sub = NSStackView(views: [eyes, Self.text(line, Look.small, .ink3)])
        sub.spacing = 6
        let lines = NSStackView(views: [Self.text(headline, Look.titleS), sub])
        (lines.orientation, lines.alignment, lines.spacing) = (.vertical, .leading, 4)
        let row = NSStackView(views: [sign, lines])
        row.spacing = 12
        NSLayoutConstraint.activate([sign.widthAnchor.constraint(equalToConstant: 36), sign.heightAnchor.constraint(equalToConstant: 36)])
        return row
    }

    /// Space, Folder: a key in ink3, its value in ink, in a ringed box.
    private static func table(_ rows: [(String, String)]) -> NSView {
        let grid = NSGridView(views: rows.map { key, value in
            [text(key, Look.Style(face: .ui, size: 12, weight: .regular, leading: 1.45), .ink3),
             text(value, Look.Style(face: .ui, size: 12, weight: .medium, leading: 1.45))]
        })
        (grid.columnSpacing, grid.rowSpacing) = (14, 4)
        return Box(grid, ring: .line, radius: 9, insets: NSEdgeInsets(top: 9, left: 11, bottom: 9, right: 11), loose: true)
    }

    /// Copy Command and Why am I asked?, quiet links under the command.
    private func links() -> NSView {
        let row = NSStackView(views: [LinkButton("Copy Command", "doc.on.doc", target: self, action: #selector(copyCommand)),
                                      LinkButton("Why am I asked?", "questionmark.circle", target: self, action: #selector(why))])
        row.spacing = 14
        return row
    }

    private func ask(_ question: Question) -> [NSView] {
        let options = question.options.map {
            question.multiple ? NSButton(checkboxWithTitle: $0, target: nil, action: nil)
                : NSButton(radioButtonWithTitle: $0, target: self, action: #selector(chose))
        }
        // Radio buttons with the same action in the same stack form one group: one choice.
        let group = NSStackView(views: options)
        (group.orientation, group.alignment) = (.vertical, .leading)
        let field = NSTextField(string: "")
        field.placeholderString = question.options.isEmpty ? "Your answer" : "Or type your answer"
        boxes.append(options)
        typed.append(field)
        return [question.header.map { Self.text($0, Look.small, .ink3) }, Self.text(question.text, Look.body), group, field].compactMap { $0 }
    }

    /// A label in the panel's type, wrapping inside its insets.
    static func text(_ string: String, _ style: Look.Style, _ color: Look.Token = .ink) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: string)
        field.font = style.font
        field.textColor = color.color
        field.preferredMaxLayoutWidth = width - 32
        return field
    }
}

/// The panel's title bar: the system's buttons at its left, the app and the kind of request, and the steps of the
/// queue at its right while more than one waits. Dragging it moves the panel.
final class PanelHeader: NSView {
    var step: (Int) -> Void = { _ in }
    var kind = "Permission" { didSet { kindLabel.stringValue = "·  " + kind } }
    var position: String? {
        didSet {
            of.stringValue = position ?? ""
            nav.isHidden = position == nil
            centered.isActive = position == nil
            leading.isActive = position != nil
        }
    }
    let of = RequestPanel.text("", Look.Style(face: .ui, size: 11, weight: .semibold, leading: 1))
    private let kindLabel = RequestPanel.text("·  Permission", Look.Style(face: .ui, size: 11.5, weight: .medium, leading: 1), .ink3)
    private let nav: Box, title: NSStackView
    private var centered = NSLayoutConstraint(), leading = NSLayoutConstraint()
    private var grabbed: (mouse: NSPoint, origin: NSPoint)?

    init() {
        // The app's badge stays light by night too, as the app's icon does.
        let badge = Box(NSImageView(image: Sign.image(.listen, side: 13)), fill: .bg, ring: .line2, radius: 4.5,
                        insets: NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2))
        badge.appearance = NSAppearance(named: .aqua)
        title = NSStackView(views: [badge, RequestPanel.text("something", Look.Style(face: .ui, size: 11.5, weight: .semibold, leading: 1)), kindLabel])
        title.spacing = 6
        let back = Self.arrow("chevron.left", "Previous request", -1), on = Self.arrow("chevron.right", "Next request", 1)
        // Its digits keep their width as the count changes.
        of.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let steps = NSStackView(views: [back, of, on])
        steps.spacing = 1
        nav = Box(steps, fill: .hover, radius: 7, insets: NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2))
        super.init(frame: .zero)
        [back, on].forEach { ($0.target, $0.action) = (self, #selector(walk(_:))) }
        for view in [title, nav] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        centered = title.centerXAnchor.constraint(equalTo: centerXAnchor)
        leading = title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 76)
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: 32), centered, title.centerYAnchor.constraint(equalTo: centerYAnchor),
                                     nav.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), nav.centerYAnchor.constraint(equalTo: centerYAnchor)])
        nav.isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    private static func arrow(_ symbol: String, _ label: String, _ by: Int) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(), target: nil, action: nil)
        (button.isBordered, button.tag, button.contentTintColor) = (false, by, Look.Token.ink2.color)
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: 20), button.heightAnchor.constraint(equalToConstant: 20)])
        return button
    }

    @objc private func walk(_ sender: NSButton) { step(sender.tag) }

    override func draw(_ dirtyRect: NSRect) {
        Look.Token.side.color.setFill()
        bounds.fill()
        Look.Token.line.color.setFill()
        NSRect(x: 0, y: isFlipped ? bounds.maxY - 1 : 0, width: bounds.width, height: 1).fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        grabbed = (window.convertPoint(toScreen: event.locationInWindow), window.frame.origin)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let grabbed else { return }
        let now = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(NSPoint(x: grabbed.origin.x + now.x - grabbed.mouse.x, y: grabbed.origin.y + now.y - grabbed.mouse.y))
    }

    override func mouseUp(with event: NSEvent) { grabbed = nil }
}

/// A button of the panel, drawn in the identity: secondary (a ring on bg2) or primary (act), with a key hint ("esc")
/// after its title. A primary button arming fills from the left on a pale ground.
class PanelButton: NSButton {
    let primary: Bool, hint: String?
    /// How much of the fill has swept across, 0 to 1.
    var progress: CGFloat = 1 { didSet { needsDisplay = true } }

    init(_ title: String, primary: Bool = false, hint: String? = nil, target: AnyObject? = nil, action: Selector? = nil) {
        (self.primary, self.hint) = (primary, hint)
        super.init(frame: .zero)
        (self.title, self.target, self.action, isBordered) = (title, target, action, false)
        setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { nil }

    private var label: NSAttributedString {
        let ink = (primary ? Look.Token.actfg : .ink).color
        let words = NSMutableAttributedString(string: title, attributes: [.font: Look.font(.ui, size: 12.5, weight: .semibold), .foregroundColor: ink])
        if let hint {
            words.append(NSAttributedString(string: "  " + hint, attributes: [.font: Look.font(.ui, size: 10, weight: .medium),
                                                                             .foregroundColor: ink.withAlphaComponent(0.6)]))
        }
        return words
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(primary ? 112 : 96, (label.size().width + 26).rounded(.up)), height: 30)
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: Look.control + 1, yRadius: Look.control + 1)
        Look.Token.bg2.color.setFill()
        shape.fill()
        if primary {
            let act = Look.Token.act.color.usingColorSpace(.sRGB) ?? .black
            act.withAlphaComponent(progress < 1 ? 0.42 : 1).setFill()
            shape.fill()
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            act.setFill()
            NSRect(x: 0, y: 0, width: bounds.width * progress, height: bounds.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            Look.Token.line2.color.setStroke()
            shape.stroke()
        }
        let label = label, size = label.size()
        label.draw(at: NSPoint(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded()))
    }
}

/// A quiet link of the panel: a symbol, 5 points, then its words in ink2, drawn here because NSButton measures itself
/// by the system's font and clips Onest.
final class LinkButton: NSButton {
    private let symbol: NSImage?

    init(_ title: String, _ symbol: String, target: AnyObject, action: Selector) {
        self.symbol = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))
        super.init(frame: .zero)
        (self.title, self.target, self.action, isBordered) = (title, target, action, false)
    }

    required init?(coder: NSCoder) { nil }

    override var title: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }

    private var words: NSAttributedString {
        NSAttributedString(string: title, attributes: [.font: Look.font(.ui, size: 11.5, weight: .medium), .foregroundColor: Look.Token.ink2.color])
    }

    override var intrinsicContentSize: NSSize { NSSize(width: (17 + words.size().width).rounded(.up), height: 18) }

    override func draw(_ dirtyRect: NSRect) {
        if let symbol {
            let tinted = NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect)
                Look.Token.ink2.color.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: 0, y: ((bounds.height - symbol.size.height) / 2).rounded(), width: symbol.size.width, height: symbol.size.height))
        }
        words.draw(at: NSPoint(x: 17, y: ((bounds.height - words.size().height) / 2).rounded()))
    }
}

/// Allow Once: a click, once armed, is the only key to it. It never becomes the focus, takes no key equivalent and
/// ignores every key; VoiceOver's press goes to the panel, which decides.
final class ArmedButton: PanelButton {
    var voice: () -> Bool = { false }
    override var acceptsFirstResponder: Bool { false }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { false }
    override func keyDown(with event: NSEvent) {}
    override func accessibilityPerformPress() -> Bool { voice() }
}

/// A view around `content`, on a rounded `fill`, ringed in `ring`, drawn again in each appearance; `loose`, the content
/// keeps its own width inside, at the leading edge.
class Box: NSView {
    let fill: Look.Token?, ring: Look.Token?, radius: CGFloat

    init(_ content: NSView, fill: Look.Token? = nil, ring: Look.Token? = nil, radius: CGFloat = 0, insets: NSEdgeInsets = NSEdgeInsets(),
         loose: Bool = false) {
        (self.fill, self.ring, self.radius) = (fill, ring, radius)
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([content.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
                                     content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
                                     content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
                                     loose ? content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -insets.right)
                                         : content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right)])
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        if let fill {
            fill.color.setFill()
            shape.fill()
        }
        if let ring {
            ring.color.setStroke()
            shape.stroke()
        }
    }
}

/// The exact command on a sunk ground: its caption with the count of its lines and ↕, then the text as the agent sent
/// it, monospaced and selectable, a line breaking only at a space, never inside `--strict` or a path. Folded, it shows
/// four whole lines, the last one fading while more is hidden below.
final class CommandBox: Box, NSLayoutManagerDelegate {
    static let line: CGFloat = 18, inset: CGFloat = 6, folded = 2 * inset + 4 * line
    let exact: String, text = NSTextView(usingTextLayoutManager: false), expand: NSButton
    private let scroll = NSScrollView(), fade = Fade()
    private var height = NSLayoutConstraint()

    init(_ exact: String, target: AnyObject, action: Selector) {
        self.exact = exact
        // A trailing newline ends the last line; it does not start another.
        let lines = exact.split(separator: "\n", omittingEmptySubsequences: false).reversed().drop(while: \.isEmpty).count
        let caption = RequestPanel.text("The exact command" + (lines > 1 ? " · \(lines) lines" : ""),
                                        Look.Style(face: .ui, size: 10.5, weight: .medium, leading: 1), .ink3)
        expand = NSButton(image: NSImage(systemSymbolName: "arrow.up.and.down", accessibilityDescription: "Expand the command") ?? NSImage(),
                          target: target, action: action)
        (expand.isBordered, expand.contentTintColor) = (false, Look.Token.ink2.color)
        expand.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        let head = NSStackView()
        head.setViews([caption], in: .leading)
        head.setViews([expand], in: .trailing)
        head.edgeInsets = NSEdgeInsets(top: 0, left: 11, bottom: 0, right: 0)
        let style = NSMutableParagraphStyle()
        (style.minimumLineHeight, style.maximumLineHeight) = (Self.line, Self.line)
        let font = Look.font(.code, size: 11.5, weight: .regular)
        text.textStorage?.setAttributedString(NSAttributedString(string: exact, attributes: [
            .font: font, .foregroundColor: Look.Token.ink.color, .paragraphStyle: style,
            // Centred in its 18 points, as the mockup's lines are: the extra height would all go above the glyphs.
            .baselineOffset: ((Self.line - font.ascender + font.descender) / 2).rounded()]))
        (text.isEditable, text.isSelectable, text.drawsBackground) = (false, true, false)
        text.textContainerInset = NSSize(width: 11, height: Self.inset)
        text.textContainer?.lineFragmentPadding = 0
        (text.isVerticallyResizable, text.autoresizingMask) = (true, [.width])
        text.setAccessibilityLabel("The exact command")
        (scroll.documentView, scroll.drawsBackground, scroll.hasVerticalScroller, scroll.autohidesScrollers) = (text, false, true, true)
        let stack = NSStackView(views: [head, scroll])
        (stack.orientation, stack.spacing) = (.vertical, 0)
        super.init(stack, fill: .sunk, ring: .line, radius: 9, insets: NSEdgeInsets(top: 5, left: 0, bottom: 2, right: 5))
        text.layoutManager?.delegate = self
        fade.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fade)
        height = scroll.heightAnchor.constraint(equalToConstant: Self.folded)
        NSLayoutConstraint.activate([height, head.widthAnchor.constraint(equalTo: stack.widthAnchor),
                                     scroll.widthAnchor.constraint(equalTo: widthAnchor, constant: -1),
                                     expand.widthAnchor.constraint(equalToConstant: 22), expand.heightAnchor.constraint(equalToConstant: 22),
                                     fade.leadingAnchor.constraint(equalTo: scroll.leadingAnchor), fade.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
                                     fade.bottomAnchor.constraint(equalTo: scroll.bottomAnchor), fade.heightAnchor.constraint(equalToConstant: 16)])
    }

    required init?(coder: NSCoder) { nil }

    /// How high the text shows now.
    var shown: CGFloat { height.constant }

    /// How high the whole command stands at the box's present width.
    var full: CGFloat {
        guard let manager = text.layoutManager, let container = text.textContainer else { return 0 }
        manager.ensureLayout(for: container)
        return manager.usedRect(for: container).height + 2 * Self.inset
    }

    /// Shows `visible` points of the text, at least a line; the last line fades while more is hidden.
    func fold(_ visible: CGFloat) {
        height.constant = max(Self.line + 2 * Self.inset, visible.rounded())
        fade.isHidden = visible <= 0 || full <= height.constant + 1
    }

    /// A line breaks only after a space, so that a flag, a path or a word is never cut in two.
    func layoutManager(_ layoutManager: NSLayoutManager, shouldBreakLineByWordBeforeCharacterAt index: Int) -> Bool {
        guard index > 0, let text = layoutManager.textStorage?.string as NSString?, let before = Unicode.Scalar(text.character(at: index - 1))
        else { return true }
        return CharacterSet.whitespacesAndNewlines.contains(before)
    }
}

/// The last line of a folded command, fading into the box's ground.
final class Fade: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let ground = Look.Token.sunk.color
        NSGradient(starting: ground.withAlphaComponent(0), ending: ground)?.draw(in: bounds, angle: -90)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The panel's resize grip, at its bottom-right corner: dragging it sizes the panel, whose top-left corner stays put.
final class Grip: NSView {
    var drag: (NSSize) -> Void = { _ in }
    private var start: (mouse: NSPoint, size: NSSize)?

    override func draw(_ dirtyRect: NSRect) {
        // The mockup's two strokes, on a 10-unit square measured from its top-left corner.
        let path = NSBezierPath(), unit = bounds.width / 10
        for (from, to) in [((9.0, 3.0), (3.0, 9.0)), ((9.0, 6.5), (6.5, 9.0))] {
            path.move(to: NSPoint(x: from.0 * unit, y: (10 - from.1) * unit))
            path.line(to: NSPoint(x: to.0 * unit, y: (10 - to.1) * unit))
        }
        (path.lineWidth, path.lineCapStyle) = (1.2 * unit, .round)
        Look.Token.ink3.color.withAlphaComponent(0.7).setStroke()
        path.stroke()
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all)) }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        start = (window.convertPoint(toScreen: event.locationInWindow), window.frame.size)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let start else { return }
        let now = window.convertPoint(toScreen: event.locationInWindow)
        drag(NSSize(width: start.size.width + now.x - start.mouse.x, height: start.size.height - now.y + start.mouse.y))
    }
}
