// Acceptance scenarios of each space's assistant: the sticker on the glass, the card, its states and notices (c1–c10).
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import Foundation
import SomethingCore
import Testing
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-assistant-"))
struct AcceptanceAssistant {
    /// Daily brief open, its assistant at work on the weather corner, reduced to the sticker; the pointer over it shows
    /// the label. Nothing of Daily brief waits, and the sticker has no badge, while My agents' request is in Needs You.
    @Test("c1: the sticker on the glass") func c1() async throws {
        let stage = try Stage("assistant")
        defer { stage.remove() }
        let (shell, library, brief) = try await AcceptanceAssistant.atWork(stage)
        defer { brief.close() }
        let model = shell.assistant, glass = shell.glass, sticker = glass.sticker
        glass.motion = { .reduced }
        // A space opens with its assistant as the sticker, which follows its presence on the next turn of the main loop.
        #expect(await wait { glass.grown == false && glass.card.isHidden && glass.stickerShown && sticker.presence == model.presence })
        shell.waiting(["agents"], mine: 0)
        sticker.mouseEntered(with: try #require(NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
                                                                    windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)))
        #expect(glass.stickerShown && sticker.sign.state == .think && sticker.subviews == [sticker.sign] && library.sidebar.needs == ["agents"])
        #expect(glass.corner == NSRect(x: shell.center.bounds.width - 60, y: 16, width: 44, height: 44))
        #expect(!glass.label.isHidden && glass.label.title == "Daily brief" && glass.label.words == "Editing brief.html…")
        #expect(sticker.accessibilityLabel() == "Assistant of Daily brief, Editing brief.html…. Open with ⌘K")
        #expect(sticker.accessibilityRole() == .button && sticker.sign.accessibilityLabel() == "Working")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "c1" + suffix, root: stage.home.root)
        }
        var stopped = false
        model.engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })
    }
    /// Daily brief open with its assistant at work: the fake claude edited brief.html with Opus 5.5 at high effort and
    /// answered, then started a weather corner and never ends that turn. The card, open, says it in the present tense;
    /// the conversation (three messages) stays folded, then opens for c2-thread.
    @Test("c2: the card") func c2() async throws {
        let stage = try Stage("assistant")
        defer { stage.remove() }
        let (shell, library, brief) = try await AcceptanceAssistant.atWork(stage)
        defer { brief.close() }
        let model = shell.assistant, engine = model.engine
        // The space opened with the sticker; ⌘K opens the card.
        model.focus()
        #expect(model.cardShown && !model.threadShown && model.title == "Daily brief" && model.presence.header == "Working")
        #expect(model.presence.state == .think && model.notice == nil)
        #expect(model.name == "Claude Code" && model.modelWords.model == "Opus 5.5" && model.modelWords.effort == "High")
        #expect(AssistantModel.messages(model.rows) == 3 && model.placeholder == "Write your next request · it waits for this one")
        #expect(model.stops && !model.canSend, "Send is Stop while it works and nothing is written")
        let host = shell.glass.card
        #expect(await wait { shell.glass.grown == true && !shell.glass.morphing }, "the card grew from the sticker")
        shell.window.layoutIfNeeded()
        let card = host.frame.insetBy(dx: AssistantCard.margin, dy: AssistantCard.margin)
        #expect(card.width == AssistantCard.width && card.maxX == shell.center.bounds.width - 16 && card.minY == 16)
        #expect(card.height > 150 && card.height < 180, "header, the present-tense line and the composer: \(card.height)")
        // The field the card draws: SwiftUI builds the rest of its accessibility only for a real assistive client, which
        // a test cannot be, so the other words are read from what the card shows (the model) and seen in the pictures.
        let field = try #require(AcceptanceTrust.fields(host).first)
        #expect(field.placeholderString == model.placeholder || field.placeholderAttributedString?.string == model.placeholder)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "c2" + suffix, root: stage.home.root)
        }
        // ⌘J opens the conversation above the composer: the days, the bubbles, the tool line.
        shell.toggleConversation(nil)
        #expect(model.threadShown && model.rows.first.map { if case .day = $0 { true } else { false } } == true)
        #expect(model.rows.contains(.tool(failed: false, words: "Edited brief.html", command: nil)))
        #expect(model.rows.contains(.reply("Done. The two agents that wait for you now open the page, oldest first, with what each one asks.")))
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "c2-thread" + suffix, root: stage.home.root)
        }
        // ⌘\ reduces it; ⌘K opens it again, and the field, drawn anew, takes the keys, even when SwiftUI draws it (here
        // forced) before the glass shows the card: a hidden field refuses the focus, and the request comes after.
        shell.reduceAssistant(nil)
        #expect(!model.cardShown)
        #expect(await wait { shell.glass.grown == false && !shell.glass.morphing && shell.glass.stickerShown })
        let keys = FieldKeys(shell.window) { host }
        model.focus()
        #expect(model.cardShown && host.isHidden)
        host.layoutSubtreeIfNeeded()
        #expect(await wait { shell.glass.grown == true && !shell.glass.morphing })
        #expect(await wait { keys.taken && !model.wantsFocus }, "the card's field took the keys")
        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })
    }
    /// Daily brief open in a window of `stage`, its assistant the fake claude: it answered "Put the agents that wait for
    /// me first." with Opus 5.5 at high effort, then started the weather corner, an edit that ends only once
    /// $HOME/out/finish appears; the clock stays at the moment the line is drawn, so it never says "Still working". The
    /// caller closes the space.
    static func atWork(_ stage: Stage) async throws -> (Shell, Library, SpaceView) {
        try AcceptanceAssistant.fake(in: stage)
        let (shell, library, _) = stage.window()
        let model = shell.assistant, engine = model.engine
        engine.changed = { model.refresh() }
        engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        let brief = try await stage.open("brief", in: shell, library)
        model.draft = "Put the agents that wait for me first."
        model.send()
        #expect(await wait(until: { AssistantModel.messages(model.rows) == 2 && !model.working && model.agent?.state == "idle" }), "rows: \(model.rows)")
        model.draft = "Add a small weather corner, top right."
        model.send()
        #expect(await wait(until: { model.presence.now == .working("Editing brief.html…", late: false) }), "said: \(model.presence.word)")
        let at = Date()
        model.clock = { at }
        // My agents' request waits in the toolbar's chip, as in the mockup's pictures.
        shell.waiting(["agents"], mine: 0)
        return (shell, library, brief)
    }

    /// Logbook open with its card and conversation (⌘J): its assistant asleep, its thread kept on disk from Monday as a
    /// restart leaves it (assistants/logbook.json, written by the app's own Session.save): the person's message, the
    /// edit, the reply. Nothing runs; the field says the next message wakes it, and the first lines, said when the
    /// conversation began, are not repeated.
    @Test("c3: a thread kept after sleep") func c3() async throws {
        let stage = try Stage("assistant")
        defer { stage.remove() }
        try AcceptanceAssistant.fake(in: stage)
        // What Logbook's assistant kept when it fell asleep on Monday.
        let monday = { (minute: Int) in iso8601.string(from: Date(timeIntervalSince1970: 1_792_404_000 + Double(minute * 60))) }
        let kept = Session(kind: "claude", model: "haiku", effort: "low", space: "logbook")
        kept.kept = [Turn(id: "t1", state: "done", started: monday(0), ended: monday(2), items: [
            Item(id: "i1", kind: "message", author: "person", text: "[something] Open space: “Logbook” (logbook, ~/something/spaces/logbook.html).\nGroup the entries by day.", at: monday(0)),
            Item(id: "i2", kind: "tool", author: "agent", text: "/Users/example/something/spaces/logbook.html", at: monday(1), tool: Tool(name: "Edit", status: "done")),
            Item(id: "i3", kind: "message", author: "agent", text: "Grouped. Each day now starts with a small heading, newest first.", at: monday(2)),
        ])]
        var agent = Agent(id: "a0", kind: "claude", origin: "launched")
        (agent.thread, agent.alive, kept.id) = ("00000000-0000-4000-8000-000000000001", false, "a0")
        kept.read(State(at: monday(2), kinds: [:], agents: [agent]))
        kept.save(in: stage.home.places.assistants)
        let (shell, library, _) = stage.window()
        let model = shell.assistant, engine = model.engine
        model.clock = { Stage.now }
        engine.changed = { model.refresh() }
        engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        let logbook = try await stage.open("logbook", in: shell, library)
        defer { logbook.close() }
        model.focus()
        shell.toggleConversation(nil)
        shell.waiting(["agents"], mine: 0)
        #expect(model.threadShown && model.asleep && model.id == nil && engine.state.agents.isEmpty, "nothing runs while it sleeps")
        #expect(model.title == "Logbook" && model.presence.state == .sleep && model.presence.word == "Asleep · wakes on your next message")
        #expect(model.rows == [.day(Date(timeIntervalSince1970: 1_792_404_000)), .mine(caption: "about Logbook", text: "Group the entries by day."),
                               .tool(failed: false, words: "Edited logbook.html", command: nil),
                               .reply("Grouped. Each day now starts with a small heading, newest first.")])
        #expect(AssistantCard.day(Date(timeIntervalSince1970: 1_792_404_000), now: Stage.now) == "Monday")
        #expect(model.firstLines.isEmpty && AssistantModel.messages(model.rows) == 2 && model.placeholder == "Ask for a change · it wakes up")
        #expect(model.name == "Claude Code" && model.modelWords.effort == "Low" && model.resumes)
        #expect(await wait { shell.glass.grown == true && !shell.glass.morphing })
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: logbook.web, "c3" + suffix, root: stage.home.root)
        }
    }
    /// Daily brief open with its card and conversation: "Make the masthead smaller and calmer." was written while the
    /// weather corner ran, held by the app, and left when that turn ended; the fake claude read and edited brief.html
    /// and now checks the page, a turn that never ends. 11 s into it the line says "Still working" and offers Stop ⌘.;
    /// the empty field's Send is Stop.
    @Test("c4: still working, Stop") func c4() async throws {
        let stage = try Stage("assistant")
        defer { stage.remove() }
        let (shell, library, brief) = try await AcceptanceAssistant.atWork(stage)
        defer { brief.close() }
        let model = shell.assistant, engine = model.engine
        model.focus()
        shell.toggleConversation(nil)
        model.draft = "Make the masthead smaller and calmer."
        model.send()
        #expect(model.held == ["Make the masthead smaller and calmer."])
        try Data().write(to: stage.home.root.appendingPathComponent("out/finish"))
        #expect(await wait(until: { model.presence.now == .working("Checking the page…", late: false) }), "said: \(model.presence.word)")
        #expect(model.held.isEmpty && model.rows.contains(.mine(caption: "about Daily brief", text: "Make the masthead smaller and calmer.")))
        #expect(model.rows.suffix(2) == [.tool(failed: false, words: "Read brief.html", command: nil), .tool(failed: false, words: "Edited brief.html", command: nil)])
        // 11 s later, by the card's clock: the time alone changes the line.
        let later = Date().addingTimeInterval(11)
        model.clock = { later }
        model.tick()
        #expect(model.presence.now == .working("Checking the page…", late: true) && model.presence.header == "Working")
        #expect(AssistantModel.messages(model.rows) == 4 && model.placeholder == "Write your next request · it waits for this one")
        #expect(model.stops && !model.canSend && model.presence.stopHelp == Keys.tooltip("stop"))
        #expect(await wait { shell.glass.grown == true && !shell.glass.morphing })
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "c4" + suffix, root: stage.home.root)
        }
        // Stop pauses the turn; the agent stays for the next message.
        model.stop()
        #expect(await wait(until: { model.agent?.state == "interrupted" && !model.working && model.agent?.alive == true }))
        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })
    }
    /// Project watch open with its card: its assistant answered a first message and listens. The model chip's menu
    /// offers the models and efforts Claude Code listed; Sonnet 5.5 at Medium is chosen for this space alone, which the
    /// chip then says. An open menu is drawn by the window server, which no picture here reaches (cannot_native): its
    /// structure is checked by value, and written beside the picture as c5-menu.txt.
    @Test("c5: model and effort") func c5() async throws {
        let stage = try Stage("assistant")
        defer { stage.remove() }
        try AcceptanceAssistant.fake(in: stage)
        let (shell, library, _) = stage.window()
        let model = shell.assistant, engine = model.engine
        engine.changed = { model.refresh() }
        engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        let project = try await stage.open("project", in: shell, library)
        defer { project.close() }
        #expect(model.modelWords == ("Default model", nil), "before Claude Code ever ran")
        model.draft = "Mark the evaluation page done."
        model.send()
        #expect(await wait(until: { model.light == .ready && model.agent?.state == "idle" && AssistantModel.messages(model.rows) == 2 }), "rows: \(model.rows)")
        // A minute later, by the card's clock: no longer "Just finished".
        let later = Date().addingTimeInterval(60)
        model.clock = { later }
        model.tick()
        model.focus()
        model.choose(model: "sonnet")
        model.choose(effort: "medium")
        #expect(await wait(until: { model.agent?.effort == "medium" && model.modelMenu.last?.choices.count == 4 }))
        typealias Choice = AssistantModel.ModelPart.Choice
        #expect(model.modelMenu == [
            .init(header: "Model · this space", choices: [Choice(title: "Opus 5.5", value: "opus", effort: false, checked: false),
                                                         Choice(title: "Sonnet 5.5", value: "sonnet", effort: false, checked: true),
                                                         Choice(title: "Haiku 5.5", value: "haiku", effort: false, checked: false)]),
            .init(header: "Effort", choices: [Choice(title: "Low", value: "low", effort: true, checked: false),
                                              Choice(title: "Medium", value: "medium", effort: true, checked: true),
                                              Choice(title: "High", value: "high", effort: true, checked: false),
                                              Choice(title: "Max", value: "max", effort: true, checked: false)]),
        ])
        #expect(model.modelWords == ("Sonnet 5.5", "Medium") && model.name == "Claude Code")
        #expect(model.title == "Project watch" && model.presence.header == "Listening" && !model.threadShown)
        #expect(model.placeholder == "Ask for a change · / for Claude Code's commands")
        // This space's alone: the defaults for new spaces are unchanged.
        #expect(Preferences(stage.home.places).model == nil && Preferences(stage.home.places).effort == nil)
        shell.waiting(["agents"], mine: 0)
        #expect(await wait { shell.glass.grown == true && !shell.glass.morphing })
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: project.web, "c5" + suffix, root: stage.home.root)
        }
        if let gallery {
            let lines = model.modelMenu.flatMap { part in [part.header.uppercased()] + part.choices.map { "  \($0.title)\($0.checked ? "  ✓" : "")" } }
            try (lines.joined(separator: "\n") + "\n").write(to: gallery.appendingPathComponent("c5-menu.txt"), atomically: true, encoding: .utf8)
        }
        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })
    }

    /// Puts the fake claude of AssistantTests in the PATH of `stage`'s home; returns its file.
    @discardableResult static func fake(in stage: Stage) throws -> URL {
        let bin = stage.home.root.appendingPathComponent("bin"), claude = bin.appendingPathComponent("claude")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try AssistantTests.fake.write(to: claude, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
        return claude
    }
    /// Each space has its own assistant and conversation. Daily brief's works on the weather corner, its card open
    /// with the conversation; Logbook's sleeps, never written to; My agents' answered, then waits for a permission. The
    /// card stays open and in place from one to the other, fading to each one's own rows; the sidebar shows each one's
    /// eyes, and the sticker's badge only My agents' request.
    @Test("c6: one assistant per space") func c6() async throws {
        let stage = try Stage("assistant")
        defer { stage.remove() }
        let (shell, library, brief) = try await AcceptanceAssistant.atWork(stage)
        defer { brief.close() }
        let model = shell.assistant, engine = model.engine, glass = shell.glass
        let briefs = model.session
        // The card open with its conversation, whatever an earlier ⌘J left: the card keeps it from space to space. Its
        // field is not typed in, as the mockup's.
        model.open = true
        model.threadShown = true
        #expect(await wait { glass.grown == true && !glass.morphing })
        let fades = glass.fades
        // Logbook: its own conversation, empty and asleep; the card stayed open, its content faded.
        let logbook = try await stage.open("logbook", in: shell, library)
        defer { logbook.close() }
        #expect(await wait { glass.fades == fades + 1 })
        #expect(model.cardShown && glass.grown == true && model.session !== briefs && model.rows.isEmpty && model.title == "Logbook")
        #expect(model.presence.state == .sleep && model.placeholder == "Ask for a change · it wakes up")
        // My agents: written to, it answers, then asks; the card leads to the request, never shows Allow.
        let agents = try await stage.open("agents", in: shell, library)
        defer { agents.close() }
        model.send("Check that the counters match what the terminal says.")
        #expect(await wait(until: { model.presence.state == .wait }), "said: \(model.presence.word)")
        #expect(model.cardShown && model.title == "My agents" && AssistantModel.messages(model.rows) == 2 && model.engine.assistants.count == 2)
        #expect(model.rows.contains(.reply("I can compare them, but I need to run the check script once. I asked you below.")))
        #expect(!model.rows.contains { "\($0)".contains("weather corner") }, "only My agents' rows")
        let notice = try #require(model.notice)
        #expect(notice.title == "Claude Code is waiting for your answer" && !notice.actions.contains { $0.title.contains("Allow") })
        #expect(model.eyes(of: "brief") == .think && model.eyes(of: "logbook") == .sleep && model.eyes(of: "agents") == .wait)
        #expect(briefs.agent?.state == "working" && briefs.rows.contains(.mine(caption: "about Daily brief", text: "Add a small weather corner, top right.")))
        // The counts the app makes of its queue (App.counted): My agents' request is this space's own, no other's.
        let queue = RequestQueue()
        queue.space = { request in
            RequestQueue.space(of: request.agent, assistant: engine.assistants.contains(request.agent),
                               working: model.space(of: request.agent), launches: [:])
        }
        queue.follow(engine.requests)
        #expect(queue.waiting.count == 1 && queue.count(in: "agents") == 1 && queue.count(in: "brief") == 0)
        shell.waiting(queue.waiting.compactMap(queue.space), mine: queue.count(in: "agents"))
        #expect(model.threadShown && model.rows.first.map { if case .day = $0 { true } else { false } } == true)
        #expect(glass.mine == 1 && library.sidebar.needs == ["agents"], "the label counts this space's own request; Needs You lists it")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: agents.web, "c6" + suffix, root: stage.home.root)
        }
        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })
    }
    /// Project watch open, its assistant reduced to the sticker with the label shown, in each of the seven states its
    /// presence can take: the eyes and the words of each, from invented agents at the Stage's moment. c7.png is asleep,
    /// as the mockup's shot; c7-<state>.png each state.
    @Test("c7: the sign's seven states") func c7() async throws {
        let stage = try Stage("assistant")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        let project = try await stage.open("project", in: shell, library)
        defer { project.close() }
        let glass = shell.glass, sticker = glass.sticker
        glass.motion = { .reduced }
        // A space opens with its assistant as the sticker.
        #expect(await wait { glass.grown == false && glass.card.isHidden && glass.stickerShown })
        shell.waiting(["agents"], mine: 0)
        sticker.mouseEntered(with: try #require(NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
                                                                    windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)))
        let now = Stage.now, at = { (seconds: TimeInterval) in iso8601.string(from: now.addingTimeInterval(-seconds)) }
        func agent(_ state: String) -> Agent {
            var agent = Agent(id: "a1", kind: "claude", origin: "launched")
            (agent.state, agent.alive, agent.model, agent.updated) = (state, true, "Opus 5.5", at(20))
            return agent
        }
        let edit = Item(id: "i1", kind: "tool", author: "agent", text: "/Users/example/something/spaces/project.html", at: at(1),
                        tool: Tool(name: "Edit", status: "running"))
        var done = edit
        done.tool?.status = "done"
        let facts = Presence.Facts(name: "Claude Code", installed: true)
        let states: [(Sign.State, Presence, String)] = [
            (.listen, Presence(facts, agent: agent("idle"), turn: nil, now: now), "Listening"),
            (.think, Presence(facts, agent: agent("working"), turn: Turn(id: "t1", state: "working", started: at(2), ended: nil, items: [edit]), now: now),
             "Editing project.html…"),
            (.wait, Presence(facts, agent: agent("waiting"), turn: nil, now: now), "Waiting for you"),
            (.done, Presence(facts, agent: agent("idle"), turn: Turn(id: "t1", state: "done", started: at(9), ended: at(1), items: [done]), now: now),
             "Just finished · changed project.html"),
            (.sleep, Presence(facts, agent: nil, turn: nil, now: now), "Asleep · wakes on your next message"),
            (.limit, Presence(facts, agent: agent("error"), turn: nil, now: now), "Stopped · can't reach its model"),
            (.unknown, Presence(facts, agent: agent("unknown"), turn: nil, now: now), "State unknown · something cannot read it"),
        ]
        for (state, presence, words) in states {
            sticker.show(presence, title: "Project watch")
            #expect(presence.state == state && sticker.sign.state == state)
            #expect(!glass.label.isHidden && glass.label.title == "Project watch" && glass.label.words == words, "\(state)")
            #expect(sticker.accessibilityLabel() == "Assistant of Project watch, \(words). Open with ⌘K")
            #expect(sticker.sign.accessibilityLabel() == state.word)
            try await stage.appearances { suffix in
                try await Picture.window(shell, library: library, web: project.web, "c7-\(state.rawValue)" + suffix, root: stage.home.root)
                if state == .sleep { try await Picture.window(shell, library: library, web: project.web, "c7" + suffix, root: stage.home.root) }
            }
        }
    }
    /// One notice above the composer when the assistant cannot go on, never an Allow button. In the mockup's order of
    /// spaces: Logbook, where the fake claude quits mid-answer (c8 and c8-crashed: Start Again, the field greyed); the
    /// same conversation, picked up again, then said unknown by an invented state (c8-unknown: no action, something will
    /// not guess); Project watch, its model retried (c8-model: Try Again, the conversation open); Daily brief, waiting
    /// for an answer (c8-waiting: Show Request), then its program gone from the Mac (c8-missing: How to Get One).
    @Test("c8: the notice slot") func c8() async throws {
        let stage = try Stage("assistant")
        defer { stage.remove() }
        let claude = try AcceptanceAssistant.fake(in: stage)
        let (shell, library, _) = stage.window()
        let model = shell.assistant, engine = model.engine, glass = shell.glass
        glass.motion = { .reduced }
        shell.waiting(["agents"], mine: 0)
        var asked = 0
        model.showRequest = { asked += 1 }
        engine.changed = { model.refresh() }
        engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        /// Opens the card over `view` and draws it as `ids`, after `check` holds.
        func draw(_ view: SpaceView, _ ids: [String]) async throws {
            model.focus()
            #expect(await wait { glass.grown == true && !glass.morphing })
            try await stage.appearances { suffix in
                for id in ids { try await Picture.window(shell, library: library, web: view.web, id + suffix, root: stage.home.root) }
            }
        }

        // Logbook: Claude Code quits while it answers.
        let logbook = try await stage.open("logbook", in: shell, library)
        model.draft = "One line per hour."
        model.send()
        #expect(await wait(until: { model.presence.stuck == .crashed }), "said: \(model.presence.word)")
        #expect(model.presence.header == "Stopped unexpectedly" && model.presence.state == .limit)
        let crashed = try #require(model.notice)
        #expect(crashed.title == "The assistant stopped" && crashed.bad && crashed.actions.map(\.title) == ["Start Again"])
        #expect(crashed.text.hasPrefix("Claude Code quit unexpectedly at ") && crashed.text.hasSuffix("Your conversation is kept; starting again picks it up."))
        #expect(model.blocked && !model.canSend && model.placeholder == "Start Again to send a message" && AssistantModel.messages(model.rows) == 2)
        try await draw(logbook, ["c8", "c8-crashed"])

        // Start Again picks it up; then a state no source gives is said unknown, with nothing to click.
        crashed.actions[0].run()
        #expect(await wait(until: { model.agent?.alive == true && model.agent?.state == "idle" && !model.launching }))
        #expect(model.notice == nil && AssistantModel.messages(model.rows) == 2)
        engine.changed = {}
        var state = engine.state
        let index = try #require(state.agents.firstIndex { $0.id == model.id })
        let at = Date()
        model.clock = { at }
        (state.agents[index].state, state.agents[index].updated) = ("unknown", iso8601.string(from: at.addingTimeInterval(-4 * 60 - 5)))
        model.session.read(state)
        let unknown = try #require(model.notice)
        #expect(model.presence.state == .unknown && model.presence.header == "State unknown · something cannot read it")
        #expect(unknown.title == "State unknown · something cannot read it" && !unknown.bad && unknown.actions.isEmpty)
        #expect(unknown.text == "Claude Code gave no sign for 4 minutes. It may still be working; something will not guess.")
        #expect(!model.blocked && model.placeholder == "Ask for a change · / for Claude Code's commands")
        try await draw(logbook, ["c8-unknown"])
        (engine.changed, model.clock) = ({ model.refresh() }, Date.init)
        model.refresh()
        logbook.close()

        // Project watch: its model does not answer, and Claude Code retries.
        model.newConversation()
        let project = try await stage.open("project", in: shell, library)
        defer { project.close() }
        model.draft = "Show the slides milestone in red."
        model.send()
        #expect(await wait(until: { model.presence.stuck == .cannotReachModel }), "said: \(model.presence.word)")
        let limit = try #require(model.notice)
        #expect(limit.title == "Stopped · can't reach its model" && limit.bad && limit.actions.map(\.title) == ["Try Again"])
        #expect(limit.text == "Its model did not answer; Claude Code keeps trying. Your last message is kept and nothing in the space changed.")
        #expect(!model.blocked && model.presence.header == "Stopped · can't reach its model")
        #expect(!model.stops && model.placeholder == "Write your next request · it waits until the model answers", "the send arrow, not Stop")
        shell.toggleConversation(nil)
        try await draw(project, ["c8-model"])
        shell.toggleConversation(nil)

        // Daily brief: a request waits in its own window; the notice leads there.
        model.newConversation()
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        model.draft = "ask-first"
        model.send()
        #expect(await wait(until: { model.presence.state == .wait }))
        let waiting = try #require(model.notice)
        #expect(waiting.title == "Claude Code is waiting for your answer" && !waiting.bad)
        #expect(waiting.text == "The request is in its own window, outside the space. Only you can answer it there.")
        #expect(waiting.actions.map(\.title) == ["Show Request \(Keys.shown("showreq"))"] && !waiting.actions.contains { $0.title.contains("Allow") })
        waiting.actions[0].run()
        #expect(asked == 1 && !model.blocked)
        try await draw(brief, ["c8-waiting"])

        // Then Claude Code leaves the Mac: the conversation keeps its builder and says it is missing.
        model.newConversation()
        model.draft = "Hello."
        model.send()
        #expect(await wait(until: { model.light == .ready }))
        try FileManager.default.removeItem(at: claude)
        engine.lookAgain()
        #expect(await wait(until: { model.presence.stuck == .missing }))
        let missing = try #require(model.notice)
        #expect(missing.title == "Claude Code isn't on this Mac" && missing.bad && missing.actions.map(\.title) == ["How to Get One"])
        #expect(missing.text == "something launches the agent you already use. Install Claude Code, or choose another one for this space.")
        #expect(model.blocked && model.placeholder == "Choose an agent to continue" && model.presence.header == "Claude Code isn't on this Mac")
        try await draw(brief, ["c8-missing"])
        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })
    }
    /// Daily brief open, the sticker in its first corner: a drag takes it across the space, its eyes leaning with the
    /// motion, and lets it go left of the middle; it goes to the leading side at the height it was let go. Logbook
    /// then opens with the sticker in the same place, the label on its right, while My agents' request is in Needs You.
    @Test("c9: the sticker dragged") func c9() async throws {
        let stage = try Stage("assistant")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        let glass = shell.glass, sticker = glass.sticker, window = shell.window
        glass.motion = { .reduced }
        #expect(await wait { glass.grown == false && glass.stickerShown && glass.corner.maxX == glass.bounds.width - 16 })
        // The mockup's glide: through 70% across and 55% down the space, then 42% and 34%, let go at 20% and 42%.
        let room = NSSize(width: glass.bounds.width, height: glass.bounds.height - shell.center.safeAreaInsets.top)
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            glass.convert(NSPoint(x: x * room.width, y: room.height - y * room.height), to: nil)
        }
        func mouse(_ type: NSEvent.EventType, _ at: NSPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        let press = glass.convert(NSPoint(x: glass.corner.midX, y: glass.corner.midY), to: nil)
        sticker.mouseDown(with: try mouse(.leftMouseDown, press))
        for (x, y) in [(0.7, 0.55), (0.42, 0.34), (0.2, 0.42)] {
            sticker.mouseDragged(with: try mouse(.leftMouseDragged, point(x, y)))
            #expect(sticker.dragging && glass.label.isHidden && abs(sticker.sign.lean.width) <= 3 && abs(sticker.sign.lean.height) <= 3)
        }
        #expect(sticker.sign.lean == CGSize(width: -3, height: 3), "it moved left and down, the sign drawn flipped")
        sticker.mouseUp(with: try mouse(.leftMouseUp, point(0.2, 0.42)))
        let spot = try #require(library.preferences.sticker)
        #expect(!spot.trailing && !spot.bottom && glass.spot == spot && !shell.assistant.open)
        #expect(glass.corner.minX == 16 && abs(glass.corner.midY - (room.height - 0.42 * room.height)) < 1, "\(glass.corner)")
        // Another space: the same place, its label on the side toward the middle.
        let logbook = try await stage.open("logbook", in: shell, library)
        defer { logbook.close() }
        #expect(await wait { glass.stickerShown && sticker.title == "Logbook" })
        #expect(glass.spot == spot && glass.corner.minX == 16)
        shell.waiting(["agents"], mine: 0)
        sticker.mouseEntered(with: try mouse(.mouseMoved, press))
        #expect(!glass.label.isHidden && glass.label.title == "Logbook" && glass.label.frame.minX == glass.corner.maxX + 10)
        #expect(glass.label.words == Glass.words(shell.assistant.presence, mine: 0) && library.sidebar.needs == ["agents"])
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: logbook.web, "c9" + suffix, root: stage.home.root)
        }
    }
    /// Daily brief open with its card and conversation while the weather corner runs: "Also make the date bigger." is
    /// held by the app, outlined after the conversation with "Sends when it finishes · Take Back"; folded, the
    /// conversation leaves a strip above the field (c10-folded). Take Back gives the text back to the field.
    @Test("c10: a message held by the app") func c10() async throws {
        let stage = try Stage("assistant")
        defer { stage.remove() }
        let (shell, library, brief) = try await AcceptanceAssistant.atWork(stage)
        defer { brief.close() }
        let model = shell.assistant, engine = model.engine
        model.focus()
        shell.toggleConversation(nil)
        model.draft = "Also make the date bigger."
        model.send()
        #expect(model.held == ["Also make the date bigger."] && model.draft.isEmpty)
        #expect(model.placeholder == "Write another request…" && AssistantModel.messages(model.rows) == 3)
        #expect(model.stops && model.presence.now == .working("Editing brief.html…", late: false))
        // Above the held message, the turn's tool lines so far, as the reference draws them.
        let turn = Array(model.rows.suffix(2))
        if case .mine(_, let text)? = turn.first { #expect(text == "Add a small weather corner, top right.") } else { Issue.record("rows: \(model.rows)") }
        #expect(turn.last == .tool(failed: false, words: "Read brief.html", command: nil), "rows: \(model.rows)")
        // 11 s into the turn, as the reference draws it: "Still working" and Stop beside the line.
        let later = Date().addingTimeInterval(11)
        model.clock = { later }
        model.tick()
        #expect(model.presence.now == .working("Editing brief.html…", late: true))
        #expect(await wait { shell.glass.grown == true && !shell.glass.morphing })
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "c10" + suffix, root: stage.home.root)
        }
        shell.toggleConversation(nil)
        #expect(!model.threadShown && model.held.count == 1)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "c10-folded" + suffix, root: stage.home.root)
        }
        // Nothing of it reached the agent; Take Back puts it back in the field.
        let input = (try? String(contentsOf: stage.home.root.appendingPathComponent("out/input"), encoding: .utf8)) ?? ""
        #expect(!input.contains("Also make the date bigger."))
        model.takeBack()
        #expect(model.held.isEmpty && model.draft == "Also make the date bigger.")
        #expect(model.placeholder == "Write your next request · it waits for this one")
        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })
    }

    /// Daily brief open with its card, as X6 starts: its assistant answered a first message, then the person asked
    /// for the time in the weather corner; the fake claude read and edited brief.html with Sonnet 5.5 and answered. The
    /// card is minimal: one chip for the agent and its model (the effort in its menu), no Point, mode or count chip, and
    /// a field that says "/" opens Claude Code's own commands, which its initialize listed.
    static func x6(_ stage: Stage) async throws -> (Shell, Library, SpaceView) {
        try AcceptanceAssistant.fake(in: stage)
        let (shell, library, _) = stage.window()
        let model = shell.assistant
        model.engine.changed = { model.refresh() }
        model.engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        let brief = try await stage.open("brief", in: shell, library)
        #expect(model.commands.isEmpty && model.placeholder == "Ask for a change · it wakes up", "no command is known before Claude Code first runs")
        for (sent, count) in [("Put the agents that wait for me first.", 2), ("Show the time in the weather corner, 24-hour like the masthead.", 4)] {
            model.draft = sent
            model.send()
            #expect(await wait(until: { AssistantModel.messages(model.rows) == count && !model.working && model.agent?.state == "idle" }), "rows: \(model.rows)")
        }
        model.focus()
        shell.waiting(["agents"], mine: 0)
        #expect(await wait { shell.glass.grown == true && !shell.glass.morphing })
        return (shell, library, brief)
    }

    /// X6.1: the card has asked for a change and just answered it: the conversation above, the line of what changed,
    /// the chip and the field.
    @Test("x6-1: ask for a change") func x6_1() async throws {
        let stage = try Stage("assistant")
        defer { stage.remove() }
        let (shell, library, brief) = try await AcceptanceAssistant.x6(stage)
        defer { brief.close() }
        let model = shell.assistant
        // The card's clock held as the turn ends: "Just now" lasts a few seconds, less than the pictures take.
        let held = Date()
        model.clock = { held }
        model.tick()
        shell.toggleConversation(nil)
        #expect(model.cardShown && model.threadShown && model.title == "Daily brief" && model.notice == nil)
        #expect(model.presence.now == .changed("brief.html"), "said: \(String(describing: model.presence.now))")
        #expect(model.name == "Claude Code" && model.modelWords == ("Sonnet 5.5", "Medium"))
        #expect(AgentModelChip.label(model) == "Claude Code, Sonnet 5.5, effort Medium. Change agent, model or effort")
        #expect(Monogram.letters(model.name) == "CC" && model.commands.map(\.value) == ["compact", "explain", "init", "review", "tidy"])
        #expect(model.placeholder == "Ask for a change · / for Claude Code's commands" && model.slashed == nil)
        let field = try #require(AcceptanceTrust.fields(shell.glass.card).first)
        #expect(field.placeholderString == model.placeholder || field.placeholderAttributedString?.string == model.placeholder)
        #expect(AcceptanceTrust.fields(shell.glass.card).count == 1, "one field, and no other control drawn as one")
        // Kept for the next launch: "/" offers them before Claude Code runs again.
        #expect(Preferences(stage.home.places).commands["claude"]?.count == 5)
        try await AcceptanceAssistant.fit(shell)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "x6-1" + suffix, root: stage.home.root)
        }
        try await AcceptanceAssistant.stop(model)
    }

    /// X6.2: the reply, the conversation unfolded above the field (⌘J); the fold arrow in the header folds it again.
    @Test("x6-2: its reply") func x6_2() async throws {
        let stage = try Stage("assistant")
        defer { stage.remove() }
        let (shell, library, brief) = try await AcceptanceAssistant.x6(stage)
        defer { brief.close() }
        let model = shell.assistant
        // A minute later: no longer "Just finished".
        let later = Date().addingTimeInterval(60)
        model.clock = { later }
        model.tick()
        shell.toggleConversation(nil)
        #expect(model.threadShown && model.presence.header == "Listening" && model.presence.now == nil)
        #expect(model.rows.contains(.mine(caption: "about Daily brief", text: "Show the time in the weather corner, 24-hour like the masthead.")))
        #expect(model.rows.suffix(3) == [.tool(failed: false, words: "Read brief.html", command: nil), .tool(failed: false, words: "Edited brief.html", command: nil),
                                         .reply("Done. The weather corner now shows the time, 18:20, in 24-hour format like the masthead. It reads nothing from the Internet.")])
        try await AcceptanceAssistant.fit(shell)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "x6-2" + suffix, root: stage.home.root)
        }
        try await AcceptanceAssistant.stop(model)
    }

    /// X6.3: "/" in the field opens Claude Code's own commands, as it listed them; ↓ three times reaches /review, and
    /// Return sends it as is, without the line that says which space is open, so Claude Code reads it as a command.
    /// Esc closes the list and leaves the card open; a word after the name closes it too. The keys are real events.
    @Test("x6-3: a \"/\" command") func x6_3() async throws {
        let stage = try Stage("assistant")
        defer { stage.remove() }
        let (shell, library, brief) = try await AcceptanceAssistant.x6(stage)
        defer { brief.close() }
        let model = shell.assistant, window = shell.window
        shell.toggleConversation(nil)
        #expect(await wait { window.firstResponder is NSTextView && !model.wantsFocus }, "the card's field has the keys")
        model.draft = "/"
        #expect(model.slashed?.map(\.value) == ["compact", "explain", "init", "review", "tidy"] && model.commandPick == 0)
        #expect(model.slashed?.first?.label == "Summarize the conversation to make room")
        for _ in 0..<3 { window.sendEvent(try AcceptanceTrust.key("\u{F701}", 125)) }
        #expect(await wait { model.commandPick == 3 }, "↓ moves the choice: \(model.commandPick)")
        try await AcceptanceAssistant.fit(shell)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "x6-3-list" + suffix, root: stage.home.root)
        }
        // Typing filters; nothing matches, and the list says so.
        model.draft = "/zz"
        #expect(model.slashed == [] && model.noCommands == "No command of Claude Code starts with that.")
        model.draft = "/re"
        #expect(model.slashed?.map(\.value) == ["review"])
        window.sendEvent(try AcceptanceTrust.key("\u{1B}", 53))
        #expect(await wait { model.slashed == nil && model.cardShown }, "Esc closes the list, not the card")
        model.draft = "/r"
        #expect(model.slashed?.map(\.value) == ["review"] && Field.slash(.upArrow, model) == .handled && model.commandPick == 0)
        model.draft = "/review now"
        #expect(model.slashed == nil && Field.slash(.return, model) == .ignored)
        model.draft = "/rev"
        window.sendEvent(try AcceptanceTrust.key("\t", 48))
        #expect(await wait { model.draft == "/review " }, "Tab leaves it for its text: \(model.draft)")
        #expect(window.firstResponder is NSTextView, "Tab kept the field")
        model.draft = "/"
        for _ in 0..<3 { window.sendEvent(try AcceptanceTrust.key("\u{F701}", 125)) }
        #expect(await wait { model.commandPick == 3 })
        window.sendEvent(try AcceptanceTrust.key("\r", 36))
        #expect(await wait { model.draft.isEmpty })
        #expect(await wait(until: { AssistantModel.messages(model.rows) == 6 && !model.working && model.agent?.state == "idle" }), "rows: \(model.rows)")
        #expect(model.rows.contains(.mine(caption: nil, text: "/review")))
        #expect(model.rows.last == .reply("Two notes: the weather corner has no label for VoiceOver, and its time is in 12-hour format while the masthead uses 24. Shall I fix both?"))
        let input = try String(contentsOf: stage.home.root.appendingPathComponent("out/input"), encoding: .utf8)
        #expect(input.contains(#""content":"/review""#), "sent as is")
        try await AcceptanceAssistant.fit(shell)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "x6-3" + suffix, root: stage.home.root)
        }
        try await AcceptanceAssistant.stop(model)
    }

    /// Lets the card take the size of what it now shows before a picture: SwiftUI asks for it a turn later.
    static func fit(_ shell: Shell) async throws {
        try await Task.sleep(for: .milliseconds(400))
        shell.glass.place()
        shell.window.layoutIfNeeded()
    }

    /// Stops every agent of `model`'s engine, waiting at most 6 s.
    static func stop(_ model: AssistantModel) async throws {
        var stopped = false
        model.engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })
    }

    /// The sticker and the card by keys alone: the sticker with the keys shows its label as under the pointer, Return
    /// opens the card and its field takes the keys once drawn; Esc in the field reduces the card to the sticker and the
    /// page has the keys again; Space opens it too, and ⌘K (the menu's, here its action) from the page. VoiceOver's
    /// press on the sticker opens it.
    @Test("Keys only: the sticker and the card") func keysOnly() async throws {
        let stage = try Stage("assistant")
        defer { stage.remove() }
        let (shell, _, brief) = try await AcceptanceAssistant.atWork(stage)
        defer { brief.close() }
        let model = shell.assistant, glass = shell.glass, sticker = glass.sticker, window = shell.window
        glass.motion = { .reduced }
        #expect(await wait { glass.grown == false && glass.stickerShown })
        func key(_ code: UInt16, _ characters: String) throws {
            window.sendEvent(try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                           context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)))
        }
        func opened() async -> Bool {
            await wait { glass.grown == true && !glass.morphing && window.firstResponder is NSTextView && !model.wantsFocus }
        }
        func reduced() async throws -> Bool {
            try key(53, "\u{1b}")
            return await wait { !model.cardShown && glass.grown == false && glass.stickerShown && window.firstResponder === brief.web }
        }
        #expect(window.makeFirstResponder(sticker) && sticker.hovering && !glass.label.isHidden, "the sticker with the keys shows its label")
        try key(36, "\r")
        #expect(model.cardShown && sticker.accessibilityRole() == .button)
        #expect(await opened(), "the card's field has the keys: \(String(describing: window.firstResponder))")
        #expect(try await reduced(), "Esc reduces the card, the page has the keys")
        #expect(window.makeFirstResponder(sticker))
        try key(49, " ")
        #expect(await opened())
        #expect(try await reduced())
        model.focus()
        #expect(await opened(), "⌘K from the page")
        #expect(try await reduced())
        #expect(sticker.accessibilityPerformPress() && model.cardShown)
        var stopped = false
        model.engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })
    }
}
