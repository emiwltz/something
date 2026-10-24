// What an assistant's presence says, in words only: from what its conversation knows, the agent as the state shows it,
// its last turn and the time now, the state its eyes draw, the card's header word, the present-tense line while it
// works ("Editing brief.html…", then "Still working · Stop" after 10 s), "Changed brief.html" for 3.6 s after a turn,
// the sticker's VoiceOver label and why it is stuck. It reads no clock and no file: the card and the sticker ask again
// at each change of the state and each tick of their own clock, so a test gives any moment.
import Foundation
import SomethingCore

struct Presence: Equatable {
    /// What the conversation knows that the state does not: the agent's name, whether its program is on this Mac (nil
    /// while not known), whether it is being started, why its last launch or message failed, and whether something
    /// stopped it (for idleness, or Stop on an agent that cannot pause).
    struct Facts: Equatable {
        var name: String
        var installed: Bool? = nil
        var waking = false
        var failure: String? = nil
        var stopped = false
    }

    /// Why it cannot go on: its program is gone, its model does not answer, it quit, or no source says what it does.
    enum Stuck: Equatable { case missing, cannotReachModel, crashed, unknown }

    /// The line above the composer: the present-tense step and whether 10 s went by (Stop is offered), the start of a
    /// sleeping agent, or the file the turn just changed.
    enum Now: Equatable { case working(String, late: Bool), waking, changed(String) }

    /// What a tool item did, by its tool's name or something's own command: the thread's rows and the line share it.
    enum Step {
        case read, edit, command, check, guide, other

        static func of(_ item: Item) -> Step {
            let name = item.tool?.name.lowercased() ?? ""
            if item.text.hasPrefix("something guide") || name.hasSuffix("something_guide") { return .guide }
            if item.text.hasPrefix("something check") || name.hasSuffix("something_check") { return .check }
            if name.hasPrefix("something_") || ["bash", "commandexecution", "execute", "shell_command", "code_exec"].contains(name) { return .command }
            if ["edit", "write", "multiedit", "notebookedit", "filechange", "apply_patch"].contains(name) { return .edit }
            return name == "read" ? .read : .other
        }
    }

    struct Notice: Equatable { let title: String, text: String }

    /// Stop is offered beside the line after `late`; a finished turn says what it changed for `changedFor`.
    static let late: TimeInterval = 10, changedFor: TimeInterval = 3.6

    let state: Sign.State, stuck: Stuck?, now: Now?
    /// The sentence the sidebar and the label say; the card's header says `header`.
    let word: String
    /// The notice above the composer while it is stuck: its bold title and its sentence.
    let notice: Notice?
    /// What Stop's tooltip says: it pauses the turn, or ends an agent that cannot pause mid-task.
    let stopHelp: String

    init(_ facts: Facts, agent: Agent?, turn: Turn?, now date: Date) {
        let name = facts.name, edited = turn.map(Presence.edited) ?? [], step = Presence.step(turn)
        var ended: TimeInterval?
        if turn?.state == "done", let at = turn?.ended.flatMap(iso8601.date) { ended = date.timeIntervalSince(at) }
        (state, stuck) = Presence.state(facts, agent, justDone: ended.map { $0 >= 0 && $0 < Presence.changedFor } == true)
        now = switch state {
        case _ where stuck != nil: nil
        case .sleep where facts.waking: .waking
        case .think:
            .working(step, late: turn?.started.flatMap(iso8601.date).map { date.timeIntervalSince($0) >= Presence.late } == true)
        case .done: edited.last.map(Now.changed)
        default: nil
        }
        word = switch (stuck, state) {
        case (.missing?, _): "\(name) isn't on this Mac"
        case (.crashed?, _): "Stopped unexpectedly"
        case (nil, .sleep) where facts.waking: "Waking up…"
        case (nil, .think): step
        case (nil, .done) where !edited.isEmpty: "Just finished · changed \(edited[edited.count - 1])"
        default: Presence.sentence(state)
        }
        let seen = agent?.updated.flatMap(iso8601.date)
        notice = switch stuck {
        case .missing?:
            Notice(title: "\(name) isn't on this Mac",
                   text: "something launches the agent you already use. Install \(name), or choose another one for this space.")
        case .crashed?:
            Notice(title: "The assistant stopped", text: facts.failure
                ?? "\(name) quit unexpectedly\(seen.map { " at " + Presence.clock.string(from: $0) } ?? ""). "
                + (agent?.can.resume == true ? "Your conversation is kept; starting again picks it up." : "Starting again begins a new conversation."))
        case .cannotReachModel?:
            Notice(title: "Stopped · can't reach its model",
                   text: "\(agent?.model ?? name) did not answer\(agent?.state == "working" ? "; \(name) keeps trying" : ""). "
                       + (edited.isEmpty ? "Your last message is kept and nothing in the space changed." : "Your last message is kept."))
        case .unknown?:
            Notice(title: "State unknown · something cannot read it",
                   text: "\(name) gave no sign\(seen.map { Presence.minutes(date.timeIntervalSince($0)) } ?? ""). It may still be working; something will not guess.")
        case nil: nil
        }
        stopHelp = agent?.can.interrupt == false && !facts.waking
            ? "Stop ends \(name), which can't pause mid-task; your next message starts it again." : Keys.tooltip("stop")
    }

    /// The card's header: the short state word while the line below already says what it does, else `word`.
    var header: String {
        switch now { case .working?, .changed?: state.word; default: word }
    }

    /// What VoiceOver reads on the sticker of the space titled `title`.
    func label(_ title: String) -> String { "Assistant of \(title), \(word). Open with \(Keys.shown("ask"))" }

    /// The state from the facts first (a missing program, a failed launch, a start under way, a stop), then from the
    /// agent. What no source gives is `unknown`, never `listen`: an agent whose life nothing proves is never idle.
    private static func state(_ facts: Facts, _ agent: Agent?, justDone: Bool) -> (Sign.State, Stuck?) {
        if facts.installed == false { return (.limit, .missing) }
        if facts.failure != nil { return (.limit, .crashed) }
        guard !facts.waking, !facts.stopped, let agent else { return (.sleep, nil) }
        if agent.alive == false { return agent.error != nil || agent.state == "interrupted" ? (.limit, .crashed) : (.sleep, nil) }
        switch agent.state {
        case "working": return agent.detail["apiRetry"] == nil ? (.think, nil) : (.limit, .cannotReachModel)
        case "waiting": return (.wait, nil)
        case "error": return (.limit, .cannotReachModel)
        case "idle" where agent.alive == true, "interrupted" where agent.alive == true: return (justDone ? .done : .listen, nil)
        case "done": return (.sleep, nil)
        default: return (.unknown, .unknown)
        }
    }

    /// The present-tense words of the turn's running tool, in the person's words; "Working…" when none says more.
    private static func step(_ turn: Turn?) -> String {
        guard let item = turn?.items.last(where: { $0.tool?.status == "running" }) else { return "Working…" }
        let file = (item.text as NSString).lastPathComponent, one = !file.isEmpty && !item.text.contains(where: \.isNewline) && !item.truncated
        switch Step.of(item) {
        case .read where one: return "Reading \(file)…"
        case .edit where one: return "Editing \(file)…"
        case .edit: return "Changing files…"
        case .check: return "Checking the page…"
        case .guide: return "Reading the guide…"
        case .command: return "Running a command…"
        default: return "Working…"
        }
    }

    /// The files the turn changed, by name, in order, each once.
    private static func edited(_ turn: Turn) -> [String] {
        turn.items.filter { Step.of($0) == .edit && $0.tool?.status != "failed" && !$0.text.contains(where: \.isNewline) }
            .map { ($0.text as NSString).lastPathComponent }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    /// The long words of each state, the mockup's.
    private static func sentence(_ state: Sign.State) -> String {
        switch state {
        case .listen: "Listening"
        case .think: "Working"
        case .wait: "Waiting for you"
        case .done: "Just finished"
        case .sleep: "Asleep · wakes on your next message"
        case .limit: "Stopped · can't reach its model"
        case .unknown: "State unknown · something cannot read it"
        }
    }

    /// " for 4 minutes", or nothing under a minute.
    private static func minutes(_ seconds: TimeInterval) -> String {
        let n = Int(seconds / 60)
        return n < 1 ? "" : " for \(n) minute\(n == 1 ? "" : "s")"
    }

    /// The time of day a crash is said at, "18:12", in the Mac's time zone.
    static let clock: DateFormatter = {
        let format = DateFormatter()
        (format.locale, format.dateFormat) = (Locale(identifier: "en_US_POSIX"), "HH:mm")
        return format
    }()
}
