// The permission and question panels: a native panel for each request of an agent something
// launched, one at a time, in the order they came. A permission is allowed once or denied, and Escape denies; a
// question is answered or left unanswered. The panels are not modal, so a request the agent withdraws closes its
// panel while the person still looks at it. A space sees the request in its state and can never answer it.
import AppKit
import SomethingAgents
import SomethingCore

/// Where the panels find the open requests and send the answers: the Engine, or a test's fake.
protocol PromptSource: AnyObject {
    /// The requests waiting for the person, oldest first.
    var requests: [Request] { get }
    /// The details of an open request, or nil once it closed.
    func prompt(_ request: String) -> Prompt?
    /// Throws, in words for the person, when the answer did not reach the agent.
    func answer(_ request: String, _ answer: Answer) throws
}

extension Engine: PromptSource {
    var requests: [Request] { state.requests }
}

final class Panels {
    let source: PromptSource
    /// Whether panels are put on the screen; a test reads them without showing them.
    let shows: Bool
    /// Who asks, in words: the agent, its folder, and the space that launched it when one did.
    var who: (Request) -> String = { _ in "An agent" }
    /// The requests waiting for a panel, the shown one first.
    private(set) var waiting: [String] = []
    private(set) var panel: PromptPanel?
    /// Answered requests stay in the state until the agent takes the answer: they are not shown again.
    private var answered: Set<String> = []

    init(source: PromptSource, shows: Bool = true) {
        self.source = source
        self.shows = shows
    }

    /// Follows the source: a new request joins the queue, a request that left it is dropped, and its panel closes.
    /// Called at each change of the state.
    func refresh() {
        let open = source.requests.map(\.id)
        answered.formIntersection(open)
        waiting.removeAll { !open.contains($0) }
        waiting += open.filter { !waiting.contains($0) && !answered.contains($0) }
        if let panel, !panel.told, !waiting.contains(panel.request.id) { dismiss() }
        while panel == nil, let first = waiting.first {
            guard let prompt = source.prompt(first) else {
                waiting.removeFirst()
                continue
            }
            let shown = PromptPanel(prompt, who: who(prompt.request)) { [weak self] answer in self?.decide(first, answer) }
            panel = shown
            if shows {
                shown.orderFrontRegardless()
                // Key, so that Escape reaches it while the person is in something. It takes no keys from another app:
                // a key typed there for that app must never answer a permission.
                shown.makeKey()
            }
        }
    }

    /// Sends the answer. A lost one is said in the panel, which stays until the person puts it away: they believe
    /// they answered. A panel that says so only goes away.
    private func decide(_ request: String, _ answer: Answer) {
        defer { refresh() }
        answered.insert(request)
        waiting.removeAll { $0 == request }
        if panel?.told == false {
            do { try source.answer(request, answer) } catch { return panel?.tell((error as? CodedError)?.message ?? error.localizedDescription) ?? () }
        }
        dismiss()
    }

    /// Puts the panel away. It is released only after the current event: a button of the panel may be the one
    /// running, and a window released inside its own control's action can crash AppKit.
    private func dismiss() {
        let old = panel
        panel = nil
        old?.dismiss()
        DispatchQueue.main.async { withExtendedLifetime(old) {} }
    }
}

/// One request's panel. Its buttons and boxes are kept so that a test can press them as the person would.
final class PromptPanel: NSPanel {
    let request: Request
    let decide: (Answer) -> Void
    /// Set once the panel was put away, answered or withdrawn.
    private(set) var dismissed = false
    /// Set once the panel says that the answer did not reach the agent.
    private(set) var told = false
    /// For a question: the boxes of each question's options, and the field where an answer can be typed.
    private(set) var boxes: [[NSButton]] = [], typed: [NSTextField] = []

    /// The panel's width: who asks, with its folder, would otherwise widen it past the screen.
    static let width: CGFloat = 480

    init(_ prompt: Prompt, who: String, decide: @escaping (Answer) -> Void) {
        request = prompt.request
        self.decide = decide
        super.init(contentRect: NSRect(x: 0, y: 0, width: PromptPanel.width, height: 200), styleMask: [.titled, .utilityWindow],
                   backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        let lines = NSStackView()
        lines.orientation = .vertical
        lines.alignment = .leading
        lines.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        lines.widthAnchor.constraint(equalToConstant: PromptPanel.width).isActive = true
        let buttons: [NSButton]
        if prompt.request.kind == "question" {
            title = "A question from an agent"
            lines.addArrangedSubview(PromptPanel.line("\(who) asks you:"))
            for question in prompt.questions { add(question, to: lines) }
            buttons = [NSButton(title: "Don't answer", target: self, action: #selector(deny)),
                       NSButton(title: "Answer", target: self, action: #selector(reply))]
        } else {
            title = "Permission"
            let tool = prompt.request.tool.map { "to use \($0)" } ?? "for permission"
            lines.addArrangedSubview(PromptPanel.line("\(who) asks \(tool)."))
            if let what = prompt.input ?? prompt.request.about {
                let text = PromptPanel.line(what)
                text.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
                text.isSelectable = true
                lines.addArrangedSubview(text)
            }
            // No key for "Allow once": a permission takes a click on the button that says what it does.
            buttons = [NSButton(title: "Deny", target: self, action: #selector(deny)),
                       NSButton(title: "Allow once", target: self, action: #selector(allow))]
        }
        buttons[0].keyEquivalent = "\u{1b}"
        lines.addArrangedSubview(NSStackView(views: buttons))
        contentView = lines
        setContentSize(lines.fittingSize)
        center()
    }

    private func add(_ question: Question, to lines: NSStackView) {
        if let header = question.header { lines.addArrangedSubview(NSTextField(labelWithString: header)) }
        lines.addArrangedSubview(PromptPanel.line(question.text))
        // Radio buttons with the same action in the same stack form one group: one choice.
        let group = NSStackView()
        group.orientation = .vertical
        group.alignment = .leading
        let options = question.options.map {
            question.multiple ? NSButton(checkboxWithTitle: $0, target: nil, action: nil)
                : NSButton(radioButtonWithTitle: $0, target: self, action: #selector(chose))
        }
        options.forEach(group.addArrangedSubview)
        lines.addArrangedSubview(group)
        let field = NSTextField(string: "")
        field.placeholderString = question.options.isEmpty ? "Your answer" : "Or type your answer"
        lines.addArrangedSubview(field)
        boxes.append(options)
        typed.append(field)
    }

    /// Says `sentence` in place of the request, with OK, which puts the panel away, as Escape does.
    func tell(_ sentence: String) {
        told = true
        guard let lines = contentView as? NSStackView else { return }
        lines.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let ok = NSButton(title: "OK", target: self, action: #selector(deny))
        ok.keyEquivalent = "\r"
        [PromptPanel.line(sentence), ok].forEach(lines.addArrangedSubview)
        setContentSize(lines.fittingSize)
    }

    /// A label that wraps inside the panel's insets.
    static func line(_ text: String) -> NSTextField { Card.line(text, width: width - 32) }

    /// Each question's chosen labels, with the typed text when there is one.
    var choice: [[String]] {
        zip(boxes, typed).map { options, field in
            options.filter { $0.state == .on }.map(\.title) + (field.stringValue.isEmpty ? [] : [field.stringValue])
        }
    }

    override var canBecomeKey: Bool { true }

    /// Escape denies.
    override func cancelOperation(_ sender: Any?) { deny() }

    func dismiss() {
        orderOut(nil)
        dismissed = true
    }

    @objc func allow() { decide(.once) }
    @objc func deny() { decide(.deny) }
    @objc func reply() { decide(.choice(choice)) }
    /// Does nothing: AppKit groups radio buttons by a shared action, and only that grouping is needed.
    @objc func chose() {}
}
