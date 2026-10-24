// The requests of the agents something launched, in front of the person: one panel (RequestPanel.swift) that shows the
// queue's request on screen and steps through the others, in the order they came. A permission is allowed once or
// denied; a question is answered or left unanswered. The panel is not modal, so a request the agent withdraws leaves
// it while the person still looks at it. A space sees the request in its state and can never answer it.
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
    private(set) var panel: RequestPanel?

    init(source: PromptSource, shows: Bool = true) {
        self.source = source
        self.shows = shows
    }

    /// Follows the source: a new request joins the queue, a request that left it is dropped, and the panel shows the
    /// one on screen, or goes away when none waits. Called at each change of the state. A panel that says an answer
    /// was lost stays until the person puts it away.
    func refresh() {
        queue.follow(source.requests)
        guard panel?.told != true else { return }
        // Its details are gone: it closed, and cannot be shown.
        while let shown = queue.shown, source.prompt(shown.id) == nil { queue.drop(shown.id) }
        guard let shown = queue.shown, let prompt = source.prompt(shown.id) else { return dismiss() }
        let panel = panel ?? open()
        panel.position = queue.position
        if panel.request?.id != shown.id { panel.show(prompt, who: who(shown), age: Words.age(shown.at, now: now())) }
        guard shows, !panel.isVisible else { return }
        if let window = beside() { panel.place(beside: window) }
        // In front, without the keys: a key typed in a page or in another app must never reach it.
        panel.orderFrontRegardless()
    }

    /// Show Request: the panel in front, with the keys.
    func present() { panel?.present() }

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
