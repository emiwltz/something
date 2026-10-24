// One conversation with a builder: its kind, the model and effort it is launched with, its agent and thread as the
// engine's state shows them, what went wrong, what the person is writing to it, the messages waiting for its launch or
// for its turn to end, and the space it is about; the turns of its earlier agent that a resumed one continues, and
// whether it began because the last one could not be picked up; and what a space's conversation keeps across sleep and
// restarts, in assistants/<name>.json: its kind, model, effort, thread, the kind that reported it, and last 60 items.
// A class, so a launch that ends after a new conversation began can tell it was for another one.
import Foundation
import Observation
import SomethingCore

@Observable final class Session {
    /// The builder; nil while none is found.
    var kind: String?
    /// What the agent is launched with; nil leaves its own default.
    let model: String?, effort: String?
    /// The space this conversation is about; nil for New Space's, which the blank page and the templates share. A build
    /// from New Space becomes the new space's own conversation (AssistantModel.appeared).
    var space: String?
    /// Its agent, once launched, and the thread that agent last reported: what a later launch may resume.
    var id: String?
    private(set) var thread: String?
    /// The kind of the agent that reported `thread`: only a launch of that kind may resume it.
    private(set) var threadKind: String?
    /// Its agent and the messages and tools of its thread, as the state shows them.
    private(set) var agent: Agent?
    private(set) var rows: [AssistantModel.Row] = []
    /// The turns shown: those carried over (`kept`), then its agent's, as `read` last took them.
    @ObservationIgnored private(set) var shown: [Turn] = []
    private(set) var turn: Turn?
    /// Whether its agent asks before every change: how it was launched, whatever the menu says now.
    var asking = false
    var launching = false
    /// Why the last launch or message failed, in the engine's words.
    var failure: String?
    /// Whether something stopped its agent, and whether it put it to sleep (idle, the cap, or the person): its next
    /// message wakes it.
    var stopped = false
    var asleep = false
    /// The last message delivered, its context line included: Try Again sends it again.
    var last: String?
    /// The messages written while the agent starts, sent once it runs; and the number of the launch that may still
    /// start it: Stop, New Conversation and a switch end a pending launch by moving this number on.
    @ObservationIgnored var queued: [String] = []
    @ObservationIgnored var launch = 0
    /// When its agent last worked or was written to, by the assistant's clock: the idle stop counts from it.
    @ObservationIgnored var active = Date()
    /// The messages written while its turn runs, context line included: the app holds them, not the agent, so Take
    /// Back and Stop can give them back; one leaves each time a turn ends. And the turn after which one last left, so
    /// a state read again before the next turn starts sends no second one.
    var held: [String] = []
    /// What the person is writing to it, not sent yet.
    var draft = ""
    @ObservationIgnored var releasedAfter: String??
    /// The turns its agent had when Start Again resumed its thread in a new one, which reports only the turns it runs:
    /// the conversation shows both. And, for the new conversation Start Again or a wake began, the line that says so.
    var kept: [Turn] = []
    var renewed: String?

    init(kind: String?, model: String? = nil, effort: String? = nil, space: String? = nil) {
        (self.kind, self.model, self.effort, self.space) = (kind, model, effort, space)
    }

    /// Takes from `state` this conversation's agent and its thread, never another's. Only what changed is written,
    /// so the window draws the assistant again only then. Returns whether its thread changed or its last turn ended:
    /// when it is saved, rather than at every row a streaming turn adds, up to four times a second.
    @discardableResult func read(_ state: State) -> Bool {
        let agent = state.agents.first { $0.id == id }, thread = state.threads.first { $0.agent == id }
        var changed = false
        if self.agent != agent { self.agent = agent }
        if let agent, let reported = agent.thread, reported != self.thread { (self.thread, threadKind, changed) = (reported, agent.kind, true) }
        shown = kept + (thread?.turns ?? [])
        let rows = AssistantModel.rows(shown)
        if self.rows != rows { self.rows = rows }
        // Its last step is the sticker's words, even while the card that draws the rows is closed.
        let turn = thread?.turns.last
        if self.turn != turn {
            if let turn, turn.state != "working", self.turn?.id != turn.id || self.turn?.state != turn.state { changed = true }
            self.turn = turn
        }
        return changed
    }

    /// Whether it has a past a builder took part in: a message sent, a thread reported, or turns carried over. Such a
    /// conversation keeps its builder rather than pass to another unasked.
    var hasHistory: Bool { last != nil || thread != nil || !kept.isEmpty }

    /// Keeps the turns of its agent's thread in `state` and lets that agent go: a later launch continues it, and the
    /// dead agent's thread, still in the state, never shows them twice.
    func fold(_ state: State) {
        kept += state.threads.first { $0.agent == id }?.turns ?? []
        id = nil
        read(state)
    }

    /// Forgets the thread and its turns: the next launch begins a new conversation, whose first lines say `why`.
    func renew(_ why: String) {
        (kept, thread, threadKind, renewed, shown) = ([], nil, nil, why, [])
        rows = []
    }

    // MARK: Saved

    /// The items kept, the newest.
    static let tail = 60

    /// The file of the space `name`'s conversation in `folder` (Places.assistants).
    static func file(_ name: String, in folder: URL) -> URL { folder.appendingPathComponent("\(name).json") }

    /// Writes its kind, model, effort, thread, the kind that reported it, and last `tail` items into `folder`, for a
    /// space's conversation only. A file that cannot be written loses only what this change kept: the conversation goes
    /// on. A renewed conversation is written too, empty: it keeps the space's agent, model and effort.
    func save(in folder: URL) {
        guard let space else { return }
        var left = Session.tail, turns: [Turn] = []
        for turn in shown.reversed() where left > 0 {
            let items = Array(turn.items.suffix(left))
            left -= items.count
            turns.insert(Turn(id: turn.id, state: turn.state, started: turn.started, ended: turn.ended, items: items), at: 0)
        }
        let saved = Saved(kind: kind, model: model, effort: effort, thread: thread, threadKind: threadKind, asking: asking, turns: turns)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(saved).write(to: Session.file(space, in: folder), options: .atomic)
    }

    /// The conversation of the space `name` saved in `folder`, asleep: its next message wakes it. Nil when none was
    /// saved or its file does not read.
    static func restored(_ name: String, in folder: URL) -> Session? {
        guard let data = try? Data(contentsOf: file(name, in: folder)), let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return nil }
        let session = Session(kind: saved.kind, model: saved.model, effort: saved.effort, space: name)
        (session.thread, session.threadKind, session.asking, session.kept, session.asleep) = (saved.thread, saved.threadKind, saved.asking, saved.turns, true)
        session.rows = AssistantModel.rows(saved.turns)
        session.shown = saved.turns
        return session
    }
}

extension Session {
    /// What a space's conversation keeps on disk. `threadKind` missing reads as nil: its thread is never resumed.
    struct Saved: Codable {
        var kind: String?, model: String?, effort: String?, thread: String?, threadKind: String?
        var asking: Bool
        var turns: [Turn]
    }
}
