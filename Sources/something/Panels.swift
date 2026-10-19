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
    /// Who asks: the agent's program ("Claude Code"), and a line with its name, the space that started it when one
    /// did, and its folder.
    var who: (Request) -> Asker = { _ in Asker(program: "An agent", line: "") }
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
    /// they answered. The requests behind it wait until then, as behind any panel: one thing at a time. A panel that
    /// says so only goes away.
    private func decide(_ request: String, _ answer: Answer) {
        defer { refresh() }
        answered.insert(request)
        waiting.removeAll { $0 == request }
        if panel?.told == false {
            do { try source.answer(request, answer) } catch {
                panel?.tell((error as? CodedError)?.message ?? error.localizedDescription)
                return
            }
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

/// Who asks in a panel: the program, which titles it, and a line that says which of its agents.
struct Asker: Equatable {
    var program: String, line: String
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
    /// The lines above the request, which stay when the panel says its answer was lost: the title, and who asks.
    private var heading = 1

    /// The panel's width: who asks, with its folder, would otherwise widen it past the screen.
    static let width: CGFloat = 480

    init(_ prompt: Prompt, who: Asker, decide: @escaping (Answer) -> Void) {
        request = prompt.request
        self.decide = decide
        super.init(contentRect: NSRect(x: 0, y: 0, width: PromptPanel.width, height: 200), styleMask: [.titled, .utilityWindow],
                   backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        // Over a space in full screen too, and on the Space the person is on.
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        // Answerable while a sheet of the main window waits for the person: an agent's request does not wait for it.
        worksWhenModal = true
        let lines = NSStackView()
        lines.orientation = .vertical
        lines.alignment = .leading
        lines.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        lines.widthAnchor.constraint(equalToConstant: PromptPanel.width).isActive = true
        let question = prompt.request.kind == "question"
        let headline = PromptPanel.line(question ? "\(who.program) asks you" : "\(who.program) wants to \(PromptPanel.action(prompt.request.tool))")
        headline.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        lines.addArrangedSubview(headline)
        if !who.line.isEmpty {
            let line = PromptPanel.line(who.line)
            line.textColor = .secondaryLabelColor
            lines.addArrangedSubview(line)
            heading = 2
        }
        let buttons: [NSButton]
        if question {
            for question in prompt.questions { add(question, to: lines) }
            buttons = [NSButton(title: "Don't Answer", target: self, action: #selector(deny)),
                       NSButton(title: "Answer", target: self, action: #selector(reply))]
        } else {
            if let what = prompt.input ?? prompt.request.about { lines.addArrangedSubview(PromptPanel.box(what)) }
            // No key for "Allow Once": a permission takes a click on the button that says what it does.
            buttons = [NSButton(title: "Deny", target: self, action: #selector(deny)),
                       NSButton(title: "Allow Once", target: self, action: #selector(allow))]
        }
        buttons[0].keyEquivalent = "\u{1b}"
        let row = PromptPanel.trailing(buttons)
        lines.setCustomSpacing(14, after: lines.arrangedSubviews.last!)
        lines.addArrangedSubview(row)
        contentView = lines
        setContentSize(lines.fittingSize)
        center()
    }

    /// `buttons` at the trailing edge, as in every Mac dialog, the last one rightmost.
    static func trailing(_ buttons: [NSButton]) -> NSStackView {
        let row = NSStackView()
        row.setViews(buttons, in: .trailing)
        row.widthAnchor.constraint(equalToConstant: width - 32).isActive = true
        return row
    }

    /// What a tool does, as the panel's title says it: "run a command", "change a file", or "use <tool>".
    static func action(_ tool: String?) -> String {
        guard let tool else { return "do something that needs your permission" }
        // Claude Code's tool names, Codex's request kinds, and the kinds of the Agent Client Protocol (OpenCode).
        if ["Bash", "commandExecution", "execute"].contains(tool) { return "run a command" }
        if ["Edit", "Write", "MultiEdit", "NotebookEdit", "fileChange", "edit", "delete", "move"].contains(tool) { return "change a file" }
        return tool == "permissions" ? "change its permissions" : "use \(tool)"
    }

    /// The command or path, monospaced and selectable, on a tinted ground of its own.
    static func box(_ text: String) -> NSView {
        let label = line(text)
        label.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        label.isSelectable = true
        label.preferredMaxLayoutWidth = width - 52
        let box = Tinted(views: [label])
        box.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        box.widthAnchor.constraint(equalToConstant: width - 32).isActive = true
        box.wantsLayer = true
        box.layer?.cornerRadius = 6
        return box
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

    /// Says `sentence` in place of the request, under who asked, with OK, which puts the panel away, as Escape does.
    /// The panel shrinks from the bottom: its top stays where the person was looking.
    func tell(_ sentence: String) {
        told = true
        guard let lines = contentView as? NSStackView else { return }
        lines.arrangedSubviews.dropFirst(heading).forEach { $0.removeFromSuperview() }
        let ok = NSButton(title: "OK", target: self, action: #selector(deny))
        ok.keyEquivalent = "\r"
        [PromptPanel.line(sentence), PromptPanel.trailing([ok])].forEach(lines.addArrangedSubview)
        var shrunk = frameRect(forContentRect: NSRect(origin: .zero, size: lines.fittingSize))
        shrunk.origin = NSPoint(x: frame.minX, y: frame.maxY - shrunk.height)
        setFrame(shrunk, display: true)
    }

    /// A label that wraps inside the panel's insets.
    static func line(_ text: String) -> NSTextField { Style.line(text, width: width - 32) }

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

/// A stack on a tinted ground, drawn again in each appearance: it follows the Mac from light to dark.
final class Tinted: NSStackView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}
