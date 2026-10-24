// One conversation with a builder: its kind, the model and effort it is launched with, its agent and thread as the
// engine's state shows them, what went wrong, what the person is writing to it, the messages waiting for its launch or
// for its turn to end, and the space it is about; the turns of its earlier agent that a resumed one continues, and
// whether it began because the last one could not be picked up. A class, so a launch that ends after a new
// conversation began can tell it was for another one.
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
    /// Its agent and the messages and tools of its thread, as the state shows them.
    private(set) var agent: Agent?
    private(set) var rows: [AssistantModel.Row] = []
    private(set) var turn: Turn?
    /// Whether its agent asks before every change: how it was launched, whatever the menu says now.
    var asking = false
    var launching = false
    /// Why the last launch or message failed, in the engine's words.
    var failure: String?
    /// Whether something stopped its agent, and whether for idleness.
    var stopped = false
    var idled = false
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
    /// the conversation shows both. And whether it is the new conversation Start Again began, which its first lines say.
    var kept: [Turn] = []
    var renewed = false

    init(kind: String?, model: String? = nil, effort: String? = nil, space: String? = nil) {
        (self.kind, self.model, self.effort, self.space) = (kind, model, effort, space)
    }

    /// Takes from `state` this conversation's agent and its thread, never another's. Only what changed is written,
    /// so the window draws the assistant again only then.
    func read(_ state: State) {
        let agent = state.agents.first { $0.id == id }, thread = state.threads.first { $0.agent == id }
        if self.agent != agent { self.agent = agent }
        if let reported = agent?.thread, reported != self.thread { self.thread = reported }
        let rows = AssistantModel.rows(kept + (thread?.turns ?? []))
        if self.rows != rows { self.rows = rows }
        // Its last step is the sticker's words, even while the card that draws the rows is closed.
        let turn = thread?.turns.last
        if self.turn != turn { self.turn = turn }
    }
}
