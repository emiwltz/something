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
    /// the label. Nothing of Daily brief waits, so no badge, while My agents' request is in the toolbar's chip.
    @Test("c1: the sticker on the glass") func c1() async throws {
        let stage = try Stage("assistant")
        defer { stage.remove() }
        let (shell, library, brief) = try await AcceptanceAssistant.atWork(stage)
        defer { brief.close() }
        let model = shell.assistant, glass = shell.glass, sticker = glass.sticker
        glass.motion = { .reduced }
        // A space opens with its assistant as the sticker, which follows its presence on the next turn of the main loop.
        #expect(await wait(5) { glass.grown == false && glass.card.isHidden && glass.stickerShown && sticker.presence == model.presence })
        shell.waiting(1, mine: 0)
        sticker.mouseEntered(with: try #require(NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
                                                                    windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)))
        #expect(glass.stickerShown && sticker.sign.state == .think && sticker.badge.isHidden && shell.chip.count == 1)
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
        #expect(model.presence.state == .think && model.dot == .ok && model.notice == nil)
        #expect(model.name == "Claude Code" && model.modelWords.model == "Opus 5.5" && model.modelWords.effort == "High")
        #expect(model.messageCount == 3 && model.placeholder == "Write your next request · it waits for this one")
        #expect(model.stops && !model.canSend, "Send is Stop while it works and nothing is written")
        let host = shell.glass.card
        #expect(await wait(5) { shell.glass.grown == true && !shell.glass.morphing }, "the card grew from the sticker")
        shell.window.layoutIfNeeded()
        let card = host.frame.insetBy(dx: AssistantCard.margin, dy: AssistantCard.margin)
        #expect(card.width == AssistantCard.width && card.maxX == shell.center.bounds.width - 16 && card.minY == 16)
        #expect(card.height > 150 && card.height < 180, "header, the present-tense line and the composer: \(card.height)")
        // The field the card draws: SwiftUI builds the rest of its accessibility only for a real assistive client, which
        // a test cannot be, so the other words are read from what the card shows (the model) and seen in the pictures.
        let field = try #require(AcceptanceAssistant.fields(in: host).first)
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
        // ⌘\ reduces it; ⌘K opens it again, and the field, drawn anew, takes the request for the focus (whether the
        // window gives it the focus is for a trial by hand: this window is never shown).
        shell.reduceAssistant(nil)
        #expect(!model.cardShown)
        #expect(await wait(5) { shell.glass.grown == false && !shell.glass.morphing && shell.glass.stickerShown })
        model.focus()
        #expect(await wait(5) { shell.glass.grown == true && !shell.glass.morphing })
        shell.window.layoutIfNeeded()
        #expect(model.cardShown && !model.wantsFocus, "the field took the request")
        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })
    }
    /// Daily brief open in a window of `stage`, its assistant the fake claude: it answered "Put the agents that wait for
    /// me first." with Opus 5.5 at high effort, then started the weather corner, an edit that ends only once
    /// $HOME/out/finish appears; the clock stays at the moment the line is drawn, so it never says "Still working". The
    /// caller closes the space.
    static func atWork(_ stage: Stage) async throws -> (Shell, Library, SpaceView) {
        let bin = stage.home.root.appendingPathComponent("bin"), claude = bin.appendingPathComponent("claude")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try AssistantTests.fake.write(to: claude, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
        let (shell, library, _) = stage.window()
        let model = shell.assistant, engine = model.engine
        engine.changed = { model.refresh() }
        engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        let brief = try await stage.open("brief", in: shell, library)
        model.draft = "Put the agents that wait for me first."
        model.send()
        #expect(await wait(until: { model.messageCount == 2 && !model.working && model.agent?.state == "idle" }), "rows: \(model.rows)")
        model.draft = "Add a small weather corner, top right."
        model.send()
        #expect(await wait(until: { model.presence.now == .working("Editing brief.html…", late: false) }), "said: \(model.presence.word)")
        let at = Date()
        model.clock = { at }
        return (shell, library, brief)
    }

    /// The text fields drawn under `view`, depth first.
    static func fields(in view: NSView) -> [NSTextField] {
        view.subviews.flatMap { ($0 as? NSTextField).map { [$0] } ?? fields(in: $0) }
    }
    @Test("c3: a thread kept after sleep", .disabled("not built yet: AB10")) func c3() async throws {}
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
        #expect(model.messageCount == 4 && model.placeholder == "Write your next request · it waits for this one")
        #expect(model.stops && !model.canSend && model.presence.stopHelp == Keys.tooltip("stop"))
        #expect(await wait(5) { shell.glass.grown == true && !shell.glass.morphing })
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
    @Test("c5: model and effort", .disabled("not built yet: AB11")) func c5() async throws {}
    @Test("c6: one assistant per space", .disabled("not built yet: AB09b")) func c6() async throws {}
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
        #expect(await wait(5) { glass.grown == false && glass.card.isHidden && glass.stickerShown })
        shell.waiting(1, mine: 0)
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
    @Test("c8: the notice slot", .disabled("not built yet: AB08")) func c8() async throws {}
    /// Daily brief open, the sticker in its first corner: a drag takes it across the space, its eyes leaning with the
    /// motion, and lets it go left of the middle; it goes to the leading side at the height it was let go. Logbook
    /// then opens with the sticker in the same place, the label on its right, while My agents' request is in the chip.
    @Test("c9: the sticker dragged") func c9() async throws {
        let stage = try Stage("assistant")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        let glass = shell.glass, sticker = glass.sticker, window = shell.window
        glass.motion = { .reduced }
        #expect(await wait(5) { glass.grown == false && glass.stickerShown && glass.corner.maxX == glass.bounds.width - 16 })
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
        #expect(await wait(5) { glass.stickerShown && sticker.title == "Logbook" })
        #expect(glass.spot == spot && glass.corner.minX == 16)
        shell.waiting(1, mine: 0)
        sticker.mouseEntered(with: try mouse(.mouseMoved, press))
        #expect(!glass.label.isHidden && glass.label.title == "Logbook" && glass.label.frame.minX == glass.corner.maxX + 10)
        #expect(glass.label.words == Glass.words(shell.assistant.presence, mine: 0) && sticker.badge.isHidden && shell.chip.count == 1)
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
        #expect(model.placeholder == "Write another request…" && model.messageCount == 3)
        #expect(model.stops && model.presence.now == .working("Editing brief.html…", late: false))
        // 11 s into the turn, as the reference draws it: "Still working" and Stop beside the line.
        let later = Date().addingTimeInterval(11)
        model.clock = { later }
        model.tick()
        #expect(model.presence.now == .working("Editing brief.html…", late: true))
        #expect(await wait(5) { shell.glass.grown == true && !shell.glass.morphing })
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
}
