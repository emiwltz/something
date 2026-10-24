// The requests of the agents something launched, in front of the person: one panel (RequestPanel.swift) that shows the
// queue's request on screen and steps through the others, in the order they came. A permission is allowed once or
// denied; a question is answered or left unanswered. The panel is not modal, so a request the agent withdraws leaves
// it while the person still looks at it. A space sees the request in its state and can never answer it. One question
// is left out of the panel: the one New Space's build asks while that page is shown, which the page answers (`inline`);
// the Dock and the toolbar's chip still count it. Its permissions, and every other conversation's questions, come here.
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
    /// Whether the panel is put on the screen; a test reads it without showing it.
    let shows: Bool
    /// Who asks a request.
    var who: (Request) -> Asker = { _ in Asker(program: "An agent") }
    /// The main window the panel arrives beside.
    var beside: () -> NSWindow? = { nil }
    /// The clocks a request's age and Allow Once's arming read: tests' seams.
    var now: () -> Date = Date.init, clock: () -> TimeInterval = { CACurrentMediaTime() }
    /// The requests waiting; the panel shows the one on screen.
    let queue = RequestQueue()
    /// The Dock and the notifications, which follow the queue; the app's.
    var attention: Attention?
    /// Told how many requests wait at each change: the toolbar's chip.
    var counted: (Int) -> Void = { _ in }
    /// Whether a request is answered elsewhere, by something's own page: never queued or shown here, only counted.
    var inline: (Request) -> Bool = { _ in false }
    /// The requests answered elsewhere, waiting: the Dock and the chip count them with the queue's.
    private(set) var elsewhere: [Request] = []
    private(set) var panel: RequestPanel?

    init(source: PromptSource, shows: Bool = true) {
        self.source = source
        self.shows = shows
    }

    /// Follows the source: a new request joins the queue, a request that left it is dropped, and the panel shows the
    /// one on screen, or goes away when none waits. Called at each change of the state. A panel that says an answer
    /// was lost stays until the person puts it away.
    func refresh() {
        let requests = source.requests
        elsewhere = requests.filter(inline)
        queue.follow(requests.filter { !inline($0) })
        // A build that asks while the person is in another app is blocked until they come back: the Dock says so.
        attention?.follow(queue.waiting + elsewhere, who: who)
        counted(queue.waiting.count + elsewhere.count)
        guard panel?.told != true else { return }
        // Its details are gone: it closed, and cannot be shown.
        while let shown = queue.shown, source.prompt(shown.id) == nil { queue.drop(shown.id) }
        guard let shown = queue.shown, let prompt = source.prompt(shown.id) else { return dismiss() }
        let panel = panel ?? open()
        panel.position = queue.position
        // The age it says is the one it had when it came on screen.
        if panel.request?.id != shown.id { panel.show(prompt, who: who(shown), age: Words.age(shown.at, now: now())) }
        if shows, !panel.isVisible { panel.arrive(beside: beside()) }
    }

    /// Show Request: the request of the space open (`space`, by name) in front, else the oldest, the panel key and
    /// pulsing once. Returns false when no request waits.
    @discardableResult func present(in space: String?) -> Bool {
        guard let oldest = queue.waiting.first else { return false }
        if panel?.told != true, queue.shown.map({ queue.space($0) != space || space == nil }) ?? true {
            queue.select(queue.waiting.first { space != nil && queue.space($0) == space }?.id ?? oldest.id)
            refresh()
        }
        guard let panel else { return false }
        panel.present(onScreen: shows)
        return true
    }

    private func open() -> RequestPanel {
        let made = RequestPanel { [weak self] answer in
            guard let self, let id = panel?.request?.id else { return }
            decide(id, answer)
        }
        made.clock = clock
        made.step = { [weak self] by in
            self?.queue.step(by)
            self?.refresh()
        }
        panel = made
        return made
    }

    /// Sends the answer. A lost one is said in the panel, which stays until the person puts it away: they believe
    /// they answered. The requests behind it wait until then. A panel that says so only goes away.
    private func decide(_ request: String, _ answer: Answer) {
        defer { refresh() }
        queue.answer(request)
        if panel?.told == false {
            do { try source.answer(request, answer) } catch {
                panel?.tell((error as? CodedError)?.message ?? error.localizedDescription)
                return
            }
            // The next request takes its place in the same panel.
            if queue.shown != nil { return }
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
