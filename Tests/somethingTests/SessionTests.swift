// Sleep and wake of each space's assistant (AB10), with the fake `claude` of AssistantTests and a moved clock: an idle
// one sleeps after the Preferences' delay and wakes on the same thread, model and effort; a kind that cannot resume is
// never put to sleep by itself and, put to sleep by the person, wakes on a new conversation that says so; leaving a
// space sets its sleep, and a wake after Ask Before Every Change changed starts anew and says why; the cap of
// awake assistants never takes a working or waiting one; what a space keeps on disk round-trips, its last 60 items;
// and a space trashed, recreated or gone starts empty.
import Foundation
import SomethingCore
import Testing
@testable import SomethingAgents
@testable import something

@MainActor @Suite(.serialized, .leavesNothing("something-session-")) struct SessionTests {
    let helper = AssistantTests()

    func place(_ home: Home, _ title: String, _ name: String) -> AssistantModel.Place {
        .space(title: title, name: name, page: home.places.spaces.appendingPathComponent("\(name).html").path)
    }

    /// The arguments the fake was last launched with, a line each.
    func arguments(_ home: Home) -> [Substring] {
        ((try? String(contentsOf: home.root.appendingPathComponent("out/arguments"), encoding: .utf8)) ?? "").split(separator: "\n")
    }

    func keep(_ kept: Session.Saved, _ name: String, in home: Home) throws {
        try FileManager.default.createDirectory(at: home.places.assistants, withIntermediateDirectories: true)
        try JSONEncoder().encode(kept).write(to: Session.file(name, in: home.places.assistants))
    }

    func kept(_ name: String, in home: Home) throws -> Session.Saved {
        try JSONDecoder().decode(Session.Saved.self, from: Data(contentsOf: Session.file(name, in: home.places.assistants)))
    }

    /// Logbook kept Claude Code with Haiku at low effort. Its first message launches it so; ten idle minutes later, by
    /// the moved clock, it sleeps, its turns kept on disk; the next message says "Waking up…" and resumes the same
    /// thread with the same model and effort, the conversation shown whole.
    @Test func anIdleClaudeSleepsThenResumesItsThread() async throws {
        let (home, model) = try helper.assistant(prefix: "something-session-")
        defer { home.remove() }
        var now = Date()
        model.clock = { now }
        try keep(Session.Saved(kind: "claude", model: "haiku", effort: "low", thread: nil, asking: false, turns: []), "logbook", in: home)
        await helper.look(model)
        let logbook = model.session(for: place(home, "Logbook", "logbook"))
        #expect(logbook.model == "haiku" && logbook.effort == "low" && logbook.rows.isEmpty)
        model.deliver("Group the entries by day.", to: logbook)
        #expect(await wait(until: { logbook.agent?.state == "idle" && logbook.rows.contains(.reply("Invented reply.")) }), "\(logbook.rows)")
        let first = try #require(logbook.id), thread = try #require(logbook.thread)
        #expect(arguments(home).contains("--model=haiku") && arguments(home).contains("--effort=low"))
        now += 10 * 60 - 1
        model.tick()
        #expect(!logbook.asleep && model.awake(logbook))
        now += 1
        model.tick()
        #expect(logbook.asleep && !model.awake(logbook) && model.eyes(of: "logbook") == .sleep)
        #expect(await wait(until: { model.engine.state.agents.first { $0.id == first }?.alive == false }))
        let rows = logbook.rows, file = try kept("logbook", in: home)
        #expect(file.thread == thread && file.kind == "claude" && file.model == "haiku" && file.effort == "low")
        #expect(AssistantModel.rows(file.turns) == rows && !rows.isEmpty)
        // The next message wakes it on the same thread, model and effort.
        model.deliver("Newest first.", to: logbook)
        #expect(model.presence(of: logbook).now == .waking || logbook.id != nil)
        #expect(await wait(until: { logbook.id != nil && logbook.id != first && !logbook.launching && arguments(home).contains("--resume") }),
                "\(arguments(home))")
        let resumed = arguments(home)
        #expect(resumed.firstIndex(of: "--resume").map { resumed[$0 + 1] == thread } == true, "\(resumed)")
        #expect(resumed.contains("--model=haiku") && resumed.contains("--effort=low") && !logbook.asleep)
        #expect(await wait(until: { logbook.rows.count > rows.count }))
        #expect(Array(logbook.rows.prefix(rows.count)) == rows && logbook.renewed == nil, "the conversation goes on, shown whole")
        await helper.finish(home, model)
    }

    /// A kind that cannot resume (faked) is never put to sleep by itself, however long it idles. Put to sleep by the
    /// person, its next message starts a new conversation, and the card says so.
    @Test func aKindThatCannotResumeWakesOnANewConversation() async throws {
        let (home, model) = try helper.assistant(prefix: "something-session-")
        defer { home.remove() }
        var now = Date()
        model.clock = { now }
        model.resumable = { _ in false }
        await helper.look(model)
        model.place = place(home, "Stack", "stack")
        model.send("Hello.")
        #expect(await wait(until: { model.agent?.state == "idle" && model.messageCount == 2 }))
        let first = try #require(model.id)
        model.place = .blank
        now += 2 * 60 * 60
        model.tick()
        let stack = model.session(for: place(home, "Stack", "stack"))
        #expect(!stack.asleep && model.awake(stack), "never put to sleep by itself")
        model.place = place(home, "Stack", "stack")
        #expect(model.canSleep)
        model.putToSleep()
        #expect(model.asleep && model.presence.word == "Asleep · wakes on your next message" && !model.canSleep)
        model.send("Again.")
        // The fake writes its arguments once running, which a loaded Mac may not have reached when the agent shows alive.
        #expect(await wait(until: { model.id != nil && model.id != first && !model.launching && model.agent?.alive == true
            && arguments(home).contains("--session-id") }), "\(arguments(home))")
        #expect(!arguments(home).contains("--resume"))
        #expect(model.firstLines.contains("Claude Code cannot resume a conversation. Started a new conversation."), "\(model.firstLines)")
        #expect(await wait(until: { model.messageCount == 2 }))
        #expect(!model.rows.contains(.mine(caption: "about Stack", text: "Hello.")), "the old conversation is gone")
        await helper.finish(home, model)
    }

    /// Leaving a space sets the timer for its assistant's sleep by itself: nothing else changes once its turn is long
    /// over. Asleep while Ask Before Every Change was turned on, it wakes on a new conversation that says why.
    @Test func leavingASpaceSetsItsSleepAndAModeChangeRenewsIt() async throws {
        let (home, model) = try helper.assistant(prefix: "something-session-")
        defer { home.remove() }
        var now = Date()
        model.clock = { now }
        await helper.look(model)
        model.place = place(home, "Stack", "stack")
        model.send("Hello.")
        #expect(await wait(until: { model.agent?.state == "idle" && model.messageCount == 2 }))
        let stack = model.session, first = try #require(model.id)
        now += 60
        model.place = .blank
        #expect(model.beatAt == stack.active + 10 * 60, "\(String(describing: model.beatAt)) \(stack.active)")
        now += 10 * 60
        model.tick()
        #expect(stack.asleep)
        model.toggleAsking()
        model.place = place(home, "Stack", "stack")
        model.send("Again.")
        #expect(await wait(until: { model.id != nil && model.id != first && !model.launching && model.agent?.alive == true
            && arguments(home).contains("--session-id") }), "\(arguments(home))")
        #expect(!arguments(home).contains("--resume"))
        #expect(model.firstLines.contains("Started a new conversation: Ask Before Every Change changed."), "\(model.firstLines)")
        await helper.finish(home, model)
    }

    /// With at most one assistant awake, the cap puts the idle ones to sleep, the longest idle first, and never one
    /// that works or waits for an answer. Put Idle Assistants to Sleep then finds none.
    @Test func theCapNeverTakesAWorkingOrWaitingAssistant() async throws {
        let (home, model) = try helper.assistant(prefix: "something-session-")
        defer { home.remove() }
        var now = Date()
        model.clock = { now }
        Preferences.at(home.places).awakeAtMost = 1
        await helper.look(model)
        let idle = model.session(for: place(home, "Logbook", "logbook")), later = model.session(for: place(home, "Pebble", "pet"))
        let working = model.session(for: place(home, "Daily brief", "brief")), waiting = model.session(for: place(home, "My agents", "agents"))
        model.deliver("Hello.", to: idle)
        #expect(await wait(until: { idle.agent?.state == "idle" }))
        now += 60
        model.deliver("Hello too.", to: later)
        #expect(await wait(until: { idle.asleep }), "the longest idle sleeps once another wakes")
        #expect(await wait(until: { later.agent?.state == "idle" }))
        now += 60
        model.deliver("go-slow, brief.", to: working)
        model.deliver("ask-first, agents.", to: waiting)
        #expect(await wait(until: { working.agent?.state == "working" && waiting.agent?.state == "waiting" }))
        model.refresh()
        #expect(later.asleep && model.awake(working) && model.awake(waiting) && !working.asleep && !waiting.asleep)
        now += 60 * 60
        model.tick()
        #expect(model.awake(working) && model.awake(waiting), "nor after the delay")
        #expect(model.putIdleToSleep() == 0)
        await helper.finish(home, model)
    }

    /// What a space keeps on disk: its kind, model, effort, thread and how it asked, and its last 60 items, the oldest
    /// turn cut; New Space's conversation keeps nothing.
    @Test func theTailRoundTrips() throws {
        let home = Home(prefix: "something-session-")
        defer { home.remove() }
        let folder = home.places.assistants
        let items = { (turn: Int, count: Int) in
            (0..<count).map { Item(id: "i\(turn)-\($0)", kind: "message", author: $0 % 2 == 0 ? "person" : "agent", text: "Invented \($0).",
                                   at: "2026-10-19T09:0\(turn):00Z") }
        }
        let session = Session(kind: "claude", model: "opus", effort: "high", space: "logbook")
        session.kept = [Turn(id: "t1", state: "done", started: "2026-10-19T09:01:00Z", ended: nil, items: items(1, 40)),
                        Turn(id: "t2", state: "done", started: "2026-10-19T09:02:00Z", ended: nil, items: items(2, 30))]
        var agent = Agent(id: "a1", kind: "claude", origin: "something")
        agent.thread = "thread-1"
        session.id = "a1"
        session.asking = true
        session.read(State(at: "2026-10-19T09:03:00Z", kinds: [:], agents: [agent]))
        session.save(in: folder)
        let back = try #require(Session.restored("logbook", in: folder))
        #expect(back.kind == "claude" && back.model == "opus" && back.effort == "high" && back.thread == "thread-1" && back.asking && back.asleep)
        #expect(back.threadKind == "claude")
        #expect(back.kept.map(\.id) == ["t1", "t2"] && back.kept.map(\.items.count) == [30, 30])
        #expect(back.kept.flatMap(\.items).first?.id == "i1-10" && back.kept.flatMap(\.items).last?.id == "i2-29")
        #expect(back.rows == AssistantModel.rows(back.kept) && back.id == nil && back.space == "logbook")
        Session(kind: "claude").save(in: folder)
        #expect((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) == ["logbook.json"], "New Space keeps nothing")
    }

    /// A space reopened at start, before the agents are looked for, keeps its builder: once they are found, its next
    /// message resumes the thread saved. A thread another kind reported is never resumed: that one wakes on a new
    /// conversation.
    @Test func aSavedConversationKeepsItsBuilderAndOnlyItsOwnThread() async throws {
        let (home, model) = try helper.assistant(prefix: "something-session-")
        defer { home.remove() }
        let turn = Turn(id: "t1", state: "done", started: "2026-10-19T09:00:00Z", ended: nil,
                        items: [Item(id: "i1", kind: "message", author: "agent", text: "Invented.", at: "2026-10-19T09:00:00Z")])
        try keep(Session.Saved(kind: "claude", model: nil, effort: nil, thread: "thread-kept", threadKind: "claude", asking: false, turns: [turn]),
                 "logbook", in: home)
        try keep(Session.Saved(kind: "claude", model: nil, effort: nil, thread: "thread-other", threadKind: "codex", asking: false, turns: [turn]),
                 "pet", in: home)
        let logbook = model.session(for: place(home, "Logbook", "logbook")), pet = model.session(for: place(home, "Pebble", "pet"))
        model.refresh()
        #expect(logbook.kind == "claude" && pet.kind == "claude", "not looked for yet: the builder stays")
        await helper.look(model)
        #expect(logbook.kind == "claude" && pet.kind == "claude")
        model.deliver("Newest first.", to: logbook)
        #expect(await wait(until: { logbook.id != nil && !logbook.launching && arguments(home).contains("--resume") }), "\(arguments(home))")
        let resumed = arguments(home)
        #expect(resumed.firstIndex(of: "--resume").map { resumed[$0 + 1] == "thread-kept" } == true, "\(resumed)")
        #expect(await wait(until: { logbook.agent?.state == "idle" }))
        model.deliver("Hello.", to: pet)
        #expect(await wait(until: { pet.id != nil && !pet.launching && arguments(home).contains("--session-id") }), "\(arguments(home))")
        #expect(!arguments(home).contains("--resume") && pet.renewed?.hasSuffix("Started a new conversation.") == true)
        await helper.finish(home, model)
    }

    /// A space moved to the Trash takes its conversation with it; one made again under a name (something new, Use
    /// Template, Import) starts empty; one gone from the folder at the start loses its file.
    @Test func aTrashedOrRecreatedSpaceStartsEmpty() async throws {
        let (home, model) = try helper.assistant(prefix: "something-session-")
        defer { home.remove() }
        let turn = Turn(id: "t1", state: "done", started: "2026-10-19T09:00:00Z", ended: nil,
                        items: [Item(id: "i1", kind: "message", author: "agent", text: "Invented.", at: "2026-10-19T09:00:00Z")])
        let kept = Session.Saved(kind: "claude", model: nil, effort: nil, thread: "t", asking: false, turns: [turn])
        for name in ["logbook", "pet", "gone"] { try keep(kept, name, in: home) }
        for name in ["logbook", "pet"] { _ = try home.space(name, page(#"{"contract": 1, "title": "Invented"}"#, "")) }
        #expect(model.messages(of: "logbook") == 1 && model.session(for: place(home, "Logbook", "logbook")).rows.count == 2)
        model.forget("logbook")
        #expect(model.session(for: place(home, "Logbook", "logbook")).rows.isEmpty && model.messages(of: "logbook") == 0)
        try Library.forget("pet", in: home.places, recycle: { _ in Issue.record("no versions to trash") })
        #expect(model.session(for: place(home, "Pebble", "pet")).rows.isEmpty)
        try keep(kept, "pet", in: home)
        try Library.forgetGone(home.places, recycle: { _ in Issue.record("no versions to trash") })
        #expect(Session.restored("gone", in: home.places.assistants) == nil && Session.restored("pet", in: home.places.assistants) != nil)
        await helper.finish(home, model)
    }
}
