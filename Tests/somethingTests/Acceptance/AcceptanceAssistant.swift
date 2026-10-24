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
        shell.reduceAssistant(nil)
        #expect(await wait(5) { glass.grown == false && glass.card.isHidden })
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
    /// me first." with Opus 5.5 at high effort, then started the weather corner, an edit that never ends; the clock
    /// stays at the moment the line is drawn, so it never says "Still working". The caller closes the space.
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
    @Test("c4: still working, Stop", .disabled("not built yet: AB07")) func c4() async throws {}
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
        shell.reduceAssistant(nil)
        #expect(await wait(5) { glass.grown == false && glass.card.isHidden })
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
    @Test("c9: the sticker dragged", .disabled("not built yet: AB06")) func c9() async throws {}
    @Test("c10: a message held by the app", .disabled("not built yet: AB07")) func c10() async throws {}
}
