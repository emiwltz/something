// The request panel: a window of the Mac of its own, beside the main window, that no space can draw, imitate or answer.
// It shows the queue's request on screen (Requests.swift), with "‹ 1 of 3 ›" while more wait: who asks, the effect in
// words first, where it runs, the exact text, for a plain command of an agent a space started the checkbox "Always for
// this space" (kept as a lasting rule once Allow Once answers: Rules.swift), then Deny and Allow Once. It never takes
// the keys when it arrives: a key typed in a page must never answer it. Allow Once arms 0.5 s after a request appears,
// and then answers a click, or VoiceOver's press once the person made the panel key themselves (a click on it, or Show
// Request); no key, Return and Space included, ever presses it. Show Request (⌥⌘P) gives it the keys, ringed, with one
// pulse; when it goes away they go back to the window that had them. Closing it denies, and so does Escape while it has
// the keys. The exact command is folded to four lines; ↕ or the grip at its bottom-right corner make the panel larger,
// its footer always in sight.
// A question shows in the same panel: its numbered options, a field for one's own answer, and Don't Answer. An option
// that answers a lone question by one click is armed like Allow Once: a click meant for the space may land on it.
import AppKit
import SomethingAgents
import SomethingCore
import SwiftUI

/// Who asks, in the panel's words: the program, its space, whether it is that space's assistant, the agent's own name,
/// its folder with ~, and whether it is a Quick Change's temporary session. What is not known is left out.
struct Asker: Equatable {
    var program: String, space: String? = nil, assistant = false, name: String? = nil, folder: String? = nil
    var quick = false
}

class RequestPanel: NSPanel, NSTextFieldDelegate {
    static let width: CGFloat = 392, wide: CGFloat = 560, widths: ClosedRange<CGFloat> = 360...720, arming: TimeInterval = 0.5
    let decide: (Answer) -> Void
    /// Moves the queue's request on screen by one, back or on.
    var step: (Int) -> Void = { _ in }
    /// The clock Allow Once's arming reads, in seconds: a test's seam.
    var clock: () -> TimeInterval = { CACurrentMediaTime() }
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
    let header = PanelHeader(), allowButton = ArmedButton("Allow Once", primary: true), ring = KeyRing()
    /// The window that had the keys before Show Request took them: it gets them back when the panel goes away.
    private weak var previous: NSWindow?
    private(set) var denyButton: NSButton = PanelButton("Deny", hint: "esc")
    /// For a question: each question's options, and the field where an answer can be typed.
    private(set) var boxes: [[OptionButton]] = [], typed: [NSTextField] = []
    private let body = NSStackView(), foot = NSStackView(), grip = Grip()
    private var widthRule = NSLayoutConstraint()
    /// The window and screen it was last placed beside, to place it again once it changed size.
    private weak var beside: NSWindow?
    /// "Always for this space", when the request offers it.
    private(set) var always: NSButton?
    private var desk: NSRect?
    /// While more requests wait, the edges of the next ones under the panel's bottom, 6 and 11 points, as a small
    /// stack: windows of their own, since a window draws nothing outside its frame. The nearer one is first.
    let edges = [(10, 6, 1), (20, 11, 0.8)].map { inset, below, alpha in
        let edge = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        (edge.isOpaque, edge.backgroundColor, edge.ignoresMouseEvents, edge.hasShadow) = (false, .clear, true, false)
        (edge.alphaValue, edge.isReleasedWhenClosed) = (alpha, false)
        edge.contentView = Box(NSView(), fill: .bg2, ring: .line2, radius: Look.window)
        return (window: edge, inset: CGFloat(inset), below: CGFloat(below))
    }

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
        ring.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(ring)
        NSLayoutConstraint.activate([ring.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                                     ring.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                                     ring.topAnchor.constraint(equalTo: content.topAnchor), ring.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
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
        stack()
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
        set {
            header.position = newValue
            stack()
        }
    }

    /// Puts the edges under the panel while more requests wait and it is on the screen; takes them away otherwise.
    private func stack() {
        // The farther edge goes first, so that the nearer one, ordered just below the panel, lies over it.
        for edge in edges.reversed() {
            edge.window.setFrame(NSRect(x: frame.minX + edge.inset, y: frame.minY - edge.below, width: frame.width - 2 * edge.inset, height: 24),
                                 display: false)
            if position != nil && isVisible {
                if edge.window.parent == nil { addChildWindow(edge.window, ordered: .below) }
            } else if edge.window.parent != nil {
                removeChildWindow(edge.window)
                edge.window.orderOut(nil)
            }
        }
    }

    /// Shows `prompt`, asked by `who` `age` ago, in place of what the panel showed, with "Always for this space" when
    /// `always`, unticked, and arms Allow Once again.
    func show(_ prompt: Prompt, who: Asker, age: String?, always: Bool = false) {
        (request, self.who, code, self.always) = (prompt.request, who, nil, nil)
        // Its labels are made for the first width; size(width:) widens them to the kept one.
        let kept = widthRule.constant
        widthRule.constant = Self.width
        let question = prompt.request.kind == "question"
        title = question ? "\(who.program) asks you a question" : "\(who.program) wants to \(Words.wants(prompt.request.tool))"
        header.kind = question ? "Question" : "Permission"
        (boxes, typed) = ([], [])
        var views = [whoRow(title, Words.who(space: who.space, assistant: who.assistant, name: who.name, age: age, quick: who.quick), who.program, assistant: who.assistant)]
        if question {
            denyButton = LinkButton("Don't Answer", size: 12, weight: .semibold, target: self, action: #selector(deny))
            views += ask(prompt.questions)
        } else {
            // An agent a space started works in its own folder, which Runs in says: the space is no place for it.
            views.append(Self.text(Words.effect(prompt.request.tool, space: who.assistant ? who.space : nil), Look.body))
            if let folder = who.folder { views.append(Self.runsIn(folder)) }
            if let exact = prompt.input ?? prompt.request.about {
                let code = CommandBox(exact, target: self, action: #selector(expand))
                views.append(code)
                self.code = code
            }
            if always, let folder = who.folder { views.append(keeper(who.program, folder)) }
            views.append(Self.lock("No space can see or click this window."))
            denyButton = PanelButton("Deny", hint: "esc")
            foot.setViews([denyButton, allowButton], in: .trailing)
        }
        // A question has no Escape key equivalent: it would deny before Escape empties a typed answer.
        (denyButton.target, denyButton.action, denyButton.keyEquivalent, foot.isHidden) = (self, #selector(deny), question ? "" : "\u{1b}", question)
        body.setViews(views, in: .top)
        stretch(views)
        size(width: kept, height: sized ? frame.height : nil)
        shownAt = clock()
        tick()
        ticker?.invalidate()
        guard !question else { return }
        // In every mode: it arms while a sheet waits in a modal loop, or a menu is open. tick() stops it once armed.
        ticker = .frames(1.0 / 30) { [weak self] in
            self?.tick()
            return self != nil
        }
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
        stack()
    }

    /// Says `sentence` in place of the request, under who asked, with OK, which puts the panel away as Escape does.
    func tell(_ sentence: String) {
        (told, code) = (true, nil)
        ticker?.invalidate()
        body.setViews(Array(body.arrangedSubviews.prefix(1)) + [Self.text(sentence, Look.body)], in: .top)
        let ok = PanelButton("OK", primary: true, target: self, action: #selector(deny))
        (ok.keyEquivalent, foot.isHidden) = ("\r", false)
        foot.setViews([ok], in: .trailing)
        fit()
    }

    /// Show Request: the person asked for the panel, so it takes the keys, ringed, and pulses once to say where they
    /// went. `onScreen` false leaves it off the screen, as a test's panel is.
    func present(onScreen: Bool = true) {
        if !isKeyWindow { previous = NSApp.keyWindow ?? NSApp.mainWindow }
        (held, ring.lit) = (true, true)
        ring.pulseOnce(Look.motion(Look.chosen))
        guard onScreen else { return }
        orderFrontRegardless()
        makeKey()
    }

    func dismiss() {
        let keyed = isKeyWindow
        ticker?.invalidate()
        orderOut(nil)
        dismissed = true
        // AppKit would hand the keys to the frontmost window; they go back where they were, a window like the welcome's.
        if keyed, let previous, previous.isVisible { previous.makeKey() }
        previous = nil
    }

    override var canBecomeKey: Bool { true }

    override func becomeKey() {
        super.becomeKey()
        ring.lit = true
    }

    /// A click on the panel is the person's own: it makes the panel key, and VoiceOver's press may then answer.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { held = true }
        super.sendEvent(event)
    }

    override func resignKey() {
        (held, ring.lit) = (false, false)
        super.resignKey()
    }

    /// ← and → walk the queue while the panel has the keys.
    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .leftArrow?: step(-1)
        case .rightArrow?: step(1)
        default: event.keyCode == 53 ? cancelOperation(nil) : super.keyDown(with: event) // Escape, held by no button's key
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
    /// Answer, or Return in a field: the choices and typed answers, once there is one.
    @objc func reply() { if choice.contains(where: { !$0.isEmpty }) { decide(.choice(choice)) } }

    /// An option's click answers a lone question of one choice, its state put back, since a click sets even a momentary
    /// button's; elsewhere AppKit toggles it, turning off the others of a one-choice question, radio buttons alike.
    @objc func chose(_ sender: OptionButton) {
        guard sender.toggles == nil else { return }
        sender.state = .off
        if armed { decide(.choice([[sender.title]])) }
    }

    /// Each question's chosen labels, with the typed text when there is one.
    var choice: [[String]] {
        zip(boxes, typed).map { options, field in
            let own = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return options.filter { $0.state == .on }.map(\.title) + (own.isEmpty ? [] : [own])
        }
    }

    /// Rings the field that has the keys, since its system ring is off.
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        defer { typed.forEach { ($0.superview as? Box)?.focused = $0.currentEditor() != nil } }
        return super.makeFirstResponder(responder)
    }

    /// Escape in a typed answer first empties it and leaves the field; only the next one answers nothing.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        guard command == #selector(cancelOperation(_:)) else { return false }
        control.stringValue = ""
        _ = makeFirstResponder(nil)
        return true
    }

    // MARK: The parts

    /// The asker's tile (the sign for the assistant, else the agent's monogram), the title in Fraunces, and under it
    /// the waiting eyes with the space, who asks and when.
    private func whoRow(_ headline: String, _ line: String, _ program: String, assistant: Bool) -> NSView {
        let sign: NSView
        if assistant {
            let mark = SignView(.listen, side: 36)
            mark.name = "\(program) is waiting"
            sign = mark
        } else {
            sign = NSHostingView(rootView: Monogram(name: program, side: 36))
            sign.setAccessibilityElement(true)
            sign.setAccessibilityRole(.image)
            sign.setAccessibilityLabel("\(program) is waiting")
        }
        let eyes = NSImageView(image: Sign.miniEyes(.wait, template: false))
        let sub = NSStackView(views: [eyes, Self.text(line, Look.small, .ink3)])
        sub.spacing = 6
        // The mockup's titles are drawn 0.02 em tighter.
        let title = Self.text(headline, Look.titleS)
        title.attributedStringValue = NSAttributedString(string: headline, attributes: [.font: Look.titleS.font, .foregroundColor: Look.Token.ink.color,
                                                                                       .kern: -0.02 * Look.titleS.size])
        let lines = NSStackView(views: [title, sub])
        (lines.orientation, lines.alignment, lines.spacing) = (.vertical, .leading, 4)
        let row = NSStackView(views: [sign, lines])
        row.spacing = 12
        NSLayoutConstraint.activate([sign.widthAnchor.constraint(equalToConstant: 36), sign.heightAnchor.constraint(equalToConstant: 36)])
        return row
    }

    /// Where it runs: a folder, "Runs in" in ink3, the folder in code, in a ringed box.
    private static func runsIn(_ folder: String) -> NSView {
        let row = NSStackView(views: [NSImageView.symbol("folder", 10, .regular, tint: .ink3),
                                      text("Runs in", Look.Style(face: .ui, size: 12, weight: .regular, leading: 1.45), .ink3),
                                      text(folder, Look.Style(face: .code, size: 11.5, weight: .regular, leading: 1.45))])
        (row.spacing, row.alignment) = (8, .firstBaseline)
        row.setCustomSpacing(12, after: row.views[1])
        return Box(row, ring: .line, radius: 9, insets: NSEdgeInsets(top: 8, left: 11, bottom: 8, right: 11), loose: true)
    }

    /// "Always for this space", unticked, and what it keeps: exactly this command, for `program`, in `folder`.
    private func keeper(_ program: String, _ folder: String) -> NSView {
        let box = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        box.attributedTitle = NSAttributedString(string: "Always for this space", attributes: [.font: Look.font(.ui, size: 12.5, weight: .semibold),
                                                                                             .foregroundColor: Look.Token.ink.color])
        let what = Self.text("Keeps exactly this command, for \(program), in \(folder). You can revoke it in the space’s Info.", Look.small, .ink3)
        // Under the box's title, as the mockup sets it: the panel's insets, the box's, and the checkbox's width.
        what.preferredMaxLayoutWidth = widthRule.constant - 32 - 22 - 20
        let column = NSStackView(views: [box, Box(what, insets: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0))])
        (column.orientation, column.alignment, column.spacing) = (.vertical, .leading, 2)
        always = box
        return Box(column, fill: .sunk, radius: 9, insets: NSEdgeInsets(top: 9, left: 11, bottom: 10, right: 11))
    }

    /// Whether "Always for this space" is ticked.
    var keeps: Bool { always?.state == .on }

    /// A lock, then `words` in ink3: what no page can do to this window.
    private static func lock(_ words: String) -> NSView {
        let row = NSStackView(views: [NSImageView.symbol("lock", 9, .medium, tint: .ink3),
                                      text(words, Look.Style(face: .ui, size: 11, weight: .regular, leading: 1.3), .ink3)])
        row.spacing = 5
        return row
    }

    /// Each question in the agent's voice, its numbered options, and a field for one's own answer, Answer beside the
    /// last; then Don't Answer, and why typing here is safe. Only a lone question of one choice is answered by a click.
    private func ask(_ questions: [Question]) -> [NSView] {
        let lone = questions.count == 1 && !questions[0].multiple
        var views: [NSView] = []
        for (index, question) in questions.enumerated() {
            let options = question.options.enumerated().map {
                OptionButton($0.offset + 1, $0.element, toggles: lone ? nil : question.multiple, target: self, action: #selector(chose))
            }
            let list = NSStackView(views: options)
            (list.orientation, list.alignment, list.spacing) = (.vertical, .width, 6)
            let field = NSTextField(string: "")
            (field.isBordered, field.drawsBackground, field.focusRingType, field.font) = (false, false, .none, Look.font(.ui, size: 13))
            (field.target, field.action, field.delegate) = (self, #selector(reply), self)
            field.cell?.sendsActionOnEndEditing = false // only Return answers, never leaving the field by Tab, click or Escape
            field.placeholderString = question.options.isEmpty ? "Your answer" : "Or type your answer"
            let own = NSStackView(views: [Box(field, fill: .sunk, ring: .line, radius: 8, insets: NSEdgeInsets(top: 9, left: 10, bottom: 8, right: 10))])
            own.spacing = 6
            if index == questions.count - 1 {
                let answer = PanelButton("Answer", primary: true, target: self, action: #selector(reply))
                answer.height = 32
                own.addArrangedSubview(answer)
            }
            (boxes, typed) = (boxes + [options], typed + [field])
            views += [question.header.map { Self.text($0, Look.small, .ink3) },
                      Self.text(question.text, Look.Style(face: .voice, size: 15, weight: .regular, leading: 1.42)),
                      options.isEmpty ? nil : Box(list), Box(own)].compactMap { $0 }
        }
        let last = NSStackView(views: [denyButton, Self.lock("The space can't see this window.")])
        last.distribution = .equalSpacing
        // The mockup's spacing around the row, measured on its picture.
        return views + [Box(last, insets: NSEdgeInsets(top: 13, left: 0, bottom: 16, right: 0))]
    }

    /// A label in the panel's type, wrapping inside its insets.
    static func text(_ string: String, _ style: Look.Style, _ color: Look.Token = .ink) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: string)
        (field.font, field.textColor, field.preferredMaxLayoutWidth) = (style.font, color.color, width - 32)
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
        let badge = Sign.tile(side: 13, radius: 4.5, inset: 2)
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

/// A button that Tab reaches, once `keyable`, even without the system's full keyboard access, where it is the only way
/// to its action by keys.
class KeyableButton: NSButton {
    var keyable = false
    override var acceptsFirstResponder: Bool { keyable || super.acceptsFirstResponder }
    override var canBecomeKeyView: Bool { keyable && !isHidden || super.canBecomeKeyView }
}

/// A button of the panel, drawn in the identity: secondary (a ring on bg2) or primary (act), with a key hint ("esc")
/// after its title. A primary button arming fills from the left on a pale ground.
class PanelButton: KeyableButton {
    let primary: Bool, hint: String?, symbol: NSImage?
    var height: CGFloat = 30
    /// Its title's size, its key hint's, and the room each side of its words: the point composer's are 12, 11 and 10.
    var size: CGFloat = 12.5, hintSize: CGFloat = 10, pad: CGFloat = 13
    /// Its narrowest width, one for both kinds so that Deny and Allow Once side by side are as wide; and the colour a
    /// primary one is filled with.
    var least: CGFloat = 112
    var fill = Look.Token.act
    /// How much of the fill has swept across, 0 to 1.
    var progress: CGFloat = 1 { didSet { needsDisplay = true } }

    /// `symbol`, a system symbol's name, goes 7 points before the title.
    init(_ title: String, primary: Bool = false, hint: String? = nil, symbol: String? = nil, target: AnyObject? = nil, action: Selector? = nil) {
        (self.primary, self.hint) = (primary, hint)
        self.symbol = symbol.map { NSImage.symbol($0, 10.5, .semibold) }
        super.init(frame: .zero)
        (self.title, self.target, self.action, isBordered) = (title, target, action, false)
        setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { nil }

    /// Enables it, or greys it: a button that draws itself does not grey on its own.
    func enable(_ on: Bool) { (isEnabled, alphaValue) = (on, on ? 1 : 0.45) }

    private var label: NSAttributedString {
        let ink = (primary ? Look.Token.actfg : .ink).color
        let words = NSMutableAttributedString(string: title, attributes: [.font: Look.font(.ui, size: size, weight: .semibold), .foregroundColor: ink])
        if let hint {
            words.append(NSAttributedString(string: "  " + hint, attributes: [.font: Look.font(.ui, size: hintSize, weight: .medium),
                                                                             .foregroundColor: ink.withAlphaComponent(0.6)]))
        }
        return words
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(least, (label.size().width + 2 * pad + lead).rounded(.up)), height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Look.control, yRadius: Look.control)
        Look.Token.bg2.color.setFill()
        shape.fill()
        if primary {
            let act = fill.color.usingColorSpace(.sRGB) ?? .black
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
        let label = label, size = label.size(), x = ((bounds.width - size.width - lead) / 2).rounded()
        if let symbol {
            symbol.tinted((primary ? Look.Token.actfg : .ink).color)
                .draw(in: NSRect(origin: NSPoint(x: x, y: ((bounds.height - symbol.size.height) / 2).rounded()), size: symbol.size))
        }
        label.draw(at: NSPoint(x: x + lead, y: ((bounds.height - size.height) / 2).rounded()))
    }

    private var lead: CGFloat { symbol.map { $0.size.width + 7 } ?? 0 }
}

/// A quiet link of the panel: its words in ink2, drawn here because NSButton measures itself by the system's font and
/// clips Onest.
final class LinkButton: KeyableButton {
    private let face: NSFont

    init(_ title: String, size: CGFloat = 11.5, weight: NSFont.Weight = .medium, target: AnyObject, action: Selector) {
        face = Look.font(.ui, size: size, weight: weight)
        super.init(frame: .zero)
        (self.title, self.target, self.action, isBordered) = (title, target, action, false)
    }

    required init?(coder: NSCoder) { nil }

    override var title: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }

    private var words: NSAttributedString {
        NSAttributedString(string: title, attributes: [.font: face, .foregroundColor: Look.Token.ink2.color])
    }

    override var intrinsicContentSize: NSSize { NSSize(width: words.size().width.rounded(.up), height: 18) }

    override func draw(_ dirtyRect: NSRect) { words.draw(at: NSPoint(x: 0, y: ((bounds.height - words.size().height) / 2).rounded())) }
}

/// One option of a question: its number in a small tile, its label, in a ringed row. `toggles` nil, a click answers;
/// true, it turns on and off; false, it is one choice among its question's options. Its label wraps, since the agent
/// writes it: the person reads the whole answer before a click sends it.
final class OptionButton: NSButton {
    let number: Int, toggles: Bool?
    private var hovered = false { didSet { needsDisplay = true } }

    init(_ number: Int, _ title: String, toggles: Bool?, target: AnyObject, action: Selector) {
        (self.number, self.toggles) = (number, toggles)
        super.init(frame: .zero)
        (self.title, self.target, self.action, isBordered) = (title, target, action, false)
        if let toggles { setButtonType(toggles ? .pushOnPushOff : .radio) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { nil }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    private var words: NSAttributedString {
        NSAttributedString(string: title, attributes: [.font: Look.font(.ui, size: 12.8, weight: .medium), .foregroundColor: Look.Token.ink.color])
    }

    /// The label's height at a row's width: 38 points before it, 10 after.
    func labelHeight(_ width: CGFloat) -> CGFloat {
        words.boundingRect(with: NSSize(width: max(1, width - 48), height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin).height.rounded(.up)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: bounds.width > 48 ? max(34, labelHeight(bounds.width) + 16) : 34)
    }

    override func setFrameSize(_ size: NSSize) {
        let wider = size.width != frame.width
        super.setFrameSize(size)
        if wider { invalidateIntrinsicContentSize() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let on = state == .on, shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        (on ? Look.Token.sel : hovered ? .hover : .bg2).color.setFill()
        (on || hovered ? Look.Token.ink2 : .line2).color.setStroke()
        shape.fill()
        shape.stroke()
        let tile = NSRect(x: 10, y: ((bounds.height - 18) / 2).rounded(), width: 18, height: 18)
        (on ? Look.Token.act : .hover).color.setFill()
        NSBezierPath(roundedRect: tile, xRadius: 5, yRadius: 5).fill()
        let digit = NSAttributedString(string: "\(number)", attributes: [.font: Look.font(.ui, size: 10.5, weight: .semibold),
                                                                         .foregroundColor: (on ? Look.Token.actfg : .ink2).color])
        digit.draw(at: NSPoint(x: tile.midX - digit.size().width / 2, y: tile.midY - digit.size().height / 2))
        let height = labelHeight(bounds.width)
        words.draw(with: NSRect(x: 38, y: ((bounds.height - height) / 2).rounded(), width: bounds.width - 48, height: height),
                   options: .usesLineFragmentOrigin)
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

/// The panel's ring while it has the keys, 1.5 points of ink2 inside its edge as the mockup rings a window in front;
/// and once, on Show Request, a pulse that spreads 10 points inward and fades, since a window draws nothing outside its
/// frame where the mockup's spreads. It takes no click.
final class KeyRing: NSView {
    var lit = false { didSet { needsDisplay = true } }
    /// How far the pulse has gone, 0 to 1; nil when none plays.
    private(set) var pulse: Double?
    private var timer: Timer?

    /// Plays the pulse once, over 1.1 s; not at all under Reduced `motion`.
    func pulseOnce(_ motion: Look.Motion) {
        timer?.invalidate()
        let length = Look.duration(1.1, motion), start = CACurrentMediaTime()
        guard length > 0 else { return }
        pulse = 0
        timer = .frames(1.0 / 30) { [weak self] in
            guard let self else { return false }
            let done = (CACurrentMediaTime() - start) / length
            pulse = done < 1 ? done : nil
            needsDisplay = true
            return pulse != nil
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        func stroke(_ color: NSColor, _ width: CGFloat) {
            let inset = width / 2, shape = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), xRadius: Look.window - inset,
                                                        yRadius: Look.window - inset)
            color.setStroke()
            shape.lineWidth = width
            shape.stroke()
        }
        // As the mockup's: spread and faded by 60 % of its length, calm at the end.
        if let pulse {
            let spread = 1 - pow(1 - min(1, pulse / 0.6), 2)
            stroke(Look.Token.ink.color.withAlphaComponent(0.24 * (1 - spread)), 1.5 + 10 * spread)
        }
        // A hairline while it holds the keys: the pulse says where they went, the lights say they stay.
        if lit { stroke(Look.Token.ink2.color, 1) }
    }
}

/// A view around `content`, on a rounded `fill`, ringed in `ring`, drawn again in each appearance; `loose`, the content
/// keeps its own width inside, at the leading edge.
class Box: NSView {
    let fill: Look.Token?, ring: Look.Token?, radius: CGFloat
    /// Rings it in ink2 at 1.5 points, as the mockup shows a field with the keys.
    var focused = false { didSet { needsDisplay = true } }

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
        // Inset half a point for the ring's stroke only: a rule one point tall is a fill alone.
        let edge: CGFloat = ring == nil ? 0 : 0.5
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: edge, dy: edge), xRadius: radius, yRadius: radius)
        if let fill {
            fill.color.setFill()
            shape.fill()
        }
        if let ring {
            (focused ? Look.Token.ink2 : ring).color.setStroke()
            shape.lineWidth = focused ? 1.5 : 1
            shape.stroke()
        }
    }
}

/// The exact command on a sunk ground: its caption with the count of its lines and ↕, then the text as the agent sent
/// it, monospaced and selectable, a line breaking only at a space, never inside `--strict` or a path, each line as full
/// as it can be. Folded, it shows four whole lines, the last one fading while more is hidden below.
final class CommandBox: Box, NSLayoutManagerDelegate {
    static let line: CGFloat = 18, inset: CGFloat = 6, folded = 2 * inset + 4 * line
    let exact: String, text = CommandText(usingTextLayoutManager: false), expand: NSButton
    private let scroll = NSScrollView(), fade = Fade()
    private var height = NSLayoutConstraint()

    init(_ exact: String, target: AnyObject, action: Selector) {
        self.exact = exact
        // A trailing newline ends the last line; it does not start another.
        let lines = exact.split(separator: "\n", omittingEmptySubsequences: false).reversed().drop(while: \.isEmpty).count
        let caption = RequestPanel.text("The exact command · \(lines) line\(lines == 1 ? "" : "s")",
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
        // Unicode never breaks a line before `/`, `.` or `)` even after a space, which would leave `--strict` alone on
        // its line before `--report /tmp/…`: a zero-width space after such a space allows it. Copying takes it out.
        let shown = exact.replacingOccurrences(of: #"(?<= )(?=[/.,:;!?)\]}])"#, with: CommandText.joint, options: .regularExpression)
        text.textStorage?.setAttributedString(NSAttributedString(string: shown, attributes: [
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
                                     // Over the last line's 16 points and the inset under it, as the mockup fades it.
                                     fade.bottomAnchor.constraint(equalTo: scroll.bottomAnchor), fade.heightAnchor.constraint(equalToConstant: 16 + Self.inset)])
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
        // From its first line: the text view keeps its end in sight as the box shrinks.
        text.scroll(.zero)
    }

    /// A line breaks only after a space, so that a flag, a path or a word is never cut in two.
    func layoutManager(_ layoutManager: NSLayoutManager, shouldBreakLineByWordBeforeCharacterAt index: Int) -> Bool {
        guard index > 0, let text = layoutManager.textStorage?.string as NSString?, let before = Unicode.Scalar(text.character(at: index - 1))
        else { return true }
        return CharacterSet.whitespacesAndNewlines.contains(before) || String(before) == CommandText.joint
    }
}

/// The command's text, which copies and drags the words without the zero-width spaces put in for its line breaks.
final class CommandText: NSTextView {
    static let joint = "\u{200B}"

    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let words = selectedRanges.map { (string as NSString).substring(with: $0.rangeValue) }.joined()
        pboard.declareTypes([.string], owner: nil)
        return pboard.setString(words.replacingOccurrences(of: Self.joint, with: ""), forType: .string)
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
