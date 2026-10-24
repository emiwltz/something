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
    @Test("c1: the sticker on the glass", .disabled("not built yet: AB05")) func c1() async throws {}
    /// Daily brief open with its assistant at work: the fake claude edited brief.html with Opus 5.5 at high effort and
    /// answered, then started a weather corner and never ends that turn. The card, open, says it in the present tense;
    /// the conversation (three messages) stays folded, then opens for c2-thread.
    @Test("c2: the card") func c2() async throws {
        let stage = try Stage("assistant")
        defer { stage.remove() }
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
        defer { brief.close() }
        model.draft = "Put the agents that wait for me first."
        model.send()
        #expect(await wait(until: { model.messageCount == 2 && !model.working && model.agent?.state == "idle" }), "rows: \(model.rows)")
        model.draft = "Add a small weather corner, top right."
        model.send()
        #expect(await wait(until: { model.presence.now == .working("Editing brief.html…", late: false) }), "said: \(model.presence.word)")
        // The moment the line is drawn: never "Still working", however slow the run.
        let at = Date()
        model.clock = { at }

        #expect(model.cardShown && !model.threadShown && model.title == "Daily brief" && model.presence.header == "Working")
        #expect(model.presence.state == .think && model.dot == .ok && model.notice == nil)
        #expect(model.name == "Claude Code" && model.modelWords.model == "Opus 5.5" && model.modelWords.effort == "High")
        #expect(model.messageCount == 3 && model.placeholder == "Write your next request · it waits for this one")
        #expect(model.stops && !model.canSend, "Send is Stop while it works and nothing is written")
        let host = try #require(shell.floating as? CardHost)
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
        model.focus()
        shell.window.layoutIfNeeded()
        #expect(model.cardShown && !model.wantsFocus, "the field took the request")
        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })
    }
    /// The text fields drawn under `view`, depth first.
    static func fields(in view: NSView) -> [NSTextField] {
        view.subviews.flatMap { ($0 as? NSTextField).map { [$0] } ?? fields(in: $0) }
    }
    @Test("c3: a thread kept after sleep", .disabled("not built yet: AB10")) func c3() async throws {}
    @Test("c4: still working, Stop", .disabled("not built yet: AB07")) func c4() async throws {}
    @Test("c5: model and effort", .disabled("not built yet: AB11")) func c5() async throws {}
    @Test("c6: one assistant per space", .disabled("not built yet: AB09b")) func c6() async throws {}
    @Test("c7: the sign's seven states", .disabled("not built yet: AB05")) func c7() async throws {}
    @Test("c8: the notice slot", .disabled("not built yet: AB08")) func c8() async throws {}
    @Test("c9: the sticker dragged", .disabled("not built yet: AB06")) func c9() async throws {}
    @Test("c10: a message held by the app", .disabled("not built yet: AB07")) func c10() async throws {}
}
