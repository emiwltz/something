// Acceptance scenarios of show and change: pointing, picked frames, the margin note, the toast, History, the glimpse and
// the comments (f1–f11; f9–f11 wait for their shots).
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import SomethingCore
import Testing
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-show-"))
struct AcceptanceShow {
    /// Daily brief open, its card folded to the sticker; ⌥⌘S starts point mode: Point pressed in the toolbar, the space
    /// dimmed but for the part under the pointer, the sign's corners around it with its kind, and the banner saying
    /// the mode and Esc. The card's Point is greyed only when there is nothing to point at; a reload keeps the mode.
    @Test("f1: pointing") func f1() async throws {
        let stage = try Stage("show")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        try stage.moment(shell)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        shell.waiting(1, mine: 0)
        let point = try #require(shell.controls[Shell.point] as? PressButton)
        #expect(point.isEnabled && !point.pressed && shell.assistant.pointable && !shell.assistant.pointing)
        #expect(Keys.enabled("pointpart", Keys.Situation(space: true)) && !Keys.enabled("pointpart", Keys.Situation(space: true, pointable: false)))
        #expect(Keys.command("pointpart")?.shown == "⌥⌘S" && point.toolTip == "Point (⌥⌘S)")

        shell.point()
        let overlay = try #require(brief.pointer)
        #expect(point.pressed && shell.assistant.pointing && !shell.assistant.open && overlay.frame == brief.web.frame)
        #expect(overlay.accessibilityLabel() == "Point at a part of the space" && overlay.accessibilityHelp() == "Esc to stop")
        // The pointer over the waiting box: its frame and kind.
        let frame = try #require(brief.frame)
        let box = try #require(try await brief.web.callAsyncJavaScript(
            "const b = document.querySelector('.box').getBoundingClientRect(); return [b.right - 5, b.y + b.height / 2]",
            in: frame, contentWorld: .defaultClient) as? [Double])
        overlay.look(at: CGPoint(x: box[0], y: box[1]))
        #expect(await wait(10, until: { overlay.hovered != nil }))
        #expect(overlay.hovered?.kind == "this block" && overlay.accessibilityValue() as? String == "this block")
        #expect(overlay.hovered?.tag == "div" && overlay.hovered?.path.contains("box") == false, "\(String(describing: overlay.hovered))")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "f1" + suffix, root: stage.home.root)
        }

        // Esc stops it, the page's keys back; ⌥⌘S again starts it, and a stopped page cannot be pointed at.
        #expect(overlay.escape() == true)
        #expect(brief.pointer == nil && !point.pressed && !shell.assistant.pointing)
        shell.point()
        #expect(brief.pointer != nil)
        // A reload (⌘R, a change of the assistant, an undo) keeps the mode: the window shows the space again, as the
        // app does at each load, and Point stays pressed and enabled while the page loads.
        brief.load()
        shell.show(brief)
        #expect(brief.frame == nil && brief.pointer != nil && point.pressed && point.isEnabled && shell.assistant.pointable)
        #expect(await wait(until: { !brief.web.isLoading && brief.frame != nil }))
        shell.point()
        #expect(brief.pointer == nil)
    }
    /// Daily brief in point mode; a click picks the paragraph of the last column: its frame stays, the banner says
    /// to say what should change and that ⌥ adds a part, and the composer attaches under it, on its side: the part's
    /// name, the words being typed, to Daily brief's assistant with its eyes, Add Comment ⌘↵ and Quick Change ↵.
    @Test("f2: picked frames and the composer") func f2() async throws {
        let stage = try Stage("show")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        try stage.moment(shell)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        shell.waiting(1, mine: 0)
        shell.point()
        let overlay = try #require(brief.pointer)
        let frame = try #require(brief.frame)
        let at = try #require(try await brief.web.callAsyncJavaScript(
            "const b = document.querySelector('#paper > :last-child p').getBoundingClientRect(); return [b.x + b.width / 2, b.y + b.height / 2]",
            in: frame, contentWorld: .defaultClient) as? [Double])
        // ⌥ alone picks nothing; a click does.
        await overlay.click(at: CGPoint(x: at[0], y: at[1]), adding: true)
        #expect(overlay.picks.isEmpty && overlay.composer == nil)
        await overlay.click(at: CGPoint(x: at[0], y: at[1]), adding: false)
        let composer = try #require(overlay.composer)
        let part = try #require(overlay.picks.first)
        #expect(overlay.picks.count == 1 && part.kind == "this paragraph" && composer.names == "this paragraph")
        #expect(overlay.banner == ["Say what should change", "Hold ⌥ and click to add a part", "Esc", "Back"])
        #expect(overlay.accessibilityLabel() == "Say what should change" && overlay.accessibilityValue() as? String == "this paragraph")
        #expect(composer.accessibilityLabel() == "What should change here?" && composer.accessibilityHelp() == "this paragraph. To Daily brief’s assistant")
        #expect(composer.title == "Daily brief" && composer.eyes == shell.assistant.eyes(of: "brief"))
        #expect(composer.quickButton.title == "Quick Change" && composer.quickButton.hint == "↵" && composer.quickButton.primary)
        #expect(composer.commentButton.title == "Add Comment" && composer.commentButton.hint == "⌘↵" && !composer.commentButton.primary)
        #expect(!composer.quickButton.isEnabled && !composer.commentButton.isEnabled)
        // Under the part and on its side (the right half), its right edge with the frame's.
        #expect(part.rect.midX > overlay.bounds.width / 2 && composer.frame.maxX == part.rect.maxX + PointOverlay.pad)
        #expect(composer.frame.minY == part.rect.maxY + PointOverlay.pad + 12)
        #expect(shell.window.firstResponder === composer.field)
        composer.field.insertText("Make this shorter", replacementRange: composer.field.selectedRange())
        #expect(composer.quickButton.isEnabled && composer.commentButton.isEnabled)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "f2" + suffix, root: stage.home.root)
        }
        // Esc lets the part go with the composer; a second Esc leaves the mode.
        #expect(overlay.escape() && overlay.composer == nil && brief.pointer != nil)
        #expect(overlay.escape() && brief.pointer == nil)
    }
    /// Daily brief in point mode, the dateline picked and "Make the weather corner smaller" written: Quick Change (↵)
    /// closes the mode, and the part keeps its frame, its top-right corner become the assistant's eyes at work, and
    /// under it the chip "Quick session · Claude Code · Opus 5.5" (f3-working): a temporary session of the space's
    /// assistant, the fake claude, with the same model. It changes the page; its frame says Done and the toast offers
    /// to undo it by the sentence (f3-done); then the chip says the session ended (f3, the mockup's last moment).
    @Test("f3: a frame at work") func f3() async throws {
        let stage = try Stage("show")
        defer { stage.remove() }
        try AcceptanceAssistant.fake(in: stage)
        Preferences.at(stage.home.places).listed["claude"] = {
            var options = Options()
            options.model = [Option(value: "opus", label: "Opus 5.5")]
            return options
        }()
        let (shell, library, _) = stage.window()
        let model = shell.assistant, engine = model.engine
        engine.changed = { model.refresh() }
        engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        try stage.moment(shell)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        shell.waiting(1, mine: 0)
        shell.layer.announce = { _ in }
        model.choose(model: "opus")
        // Long enough to draw Done and the end in both appearances.
        model.lingers = (12, 60)
        // A never-shown window's animations run only while this Mac's display is awake: under reduced motion the toast
        // is drawn where it lands, whatever the display does during the run.
        library.preferences.motion = .reduced
        let changes = Changes(places: stage.home.places, undo: shell.undo)
        changes.follow(model, in: shell, library: library)
        changes.toast = { words, action, quiet, _ in _ = shell.toast(words, action: action, quiet: quiet, seconds: 60) }
        let page = brief.space.location, was = try String(contentsOf: page, encoding: .utf8), style = try #require(was.range(of: "</style>"))
        let users = { ((try? String(contentsOf: stage.home.root.appendingPathComponent("out/input"), encoding: .utf8)) ?? "")
            .split(separator: "\n").filter { $0.contains(#""type":"user""#) } }

        shell.point()
        let overlay = try #require(brief.pointer), frame = try #require(brief.frame)
        let at = try #require(try await brief.web.callAsyncJavaScript(
            "const b = document.querySelector('#weather-line').getBoundingClientRect(); return [b.x + b.width / 2, b.y + b.height / 2]",
            in: frame, contentWorld: .defaultClient) as? [Double])
        await overlay.click(at: CGPoint(x: at[0], y: at[1]), adding: false)
        let composer = try #require(overlay.composer), part = try #require(overlay.picks.first)
        composer.field.insertText("Make the weather corner smaller", replacementRange: composer.field.selectedRange())
        composer.sendQuick()

        // The mode closed; the frame stays, at work, and takes no click.
        let point = try #require(shell.controls[Shell.point] as? PressButton)
        #expect(brief.pointer == nil && !point.pressed && !model.pointing)
        let quick = try #require(model.quicks["brief"])
        let drawn = try #require(brief.area.subviews.compactMap { $0 as? QuickFrame }.first)
        #expect(drawn.quick === quick && quick.parts == [part] && drawn.hitTest(NSPoint(x: 50, y: 50)) == nil && drawn.frame == brief.web.frame)
        #expect(drawn.chip == "Quick session · Claude Code · Opus 5.5" && drawn.badge == "Working")
        #expect(drawn.accessibilityLabel() == "Quick session · Claude Code · Opus 5.5" && drawn.accessibilityValue() as? String == "Working")
        #expect(await wait(until: { !users().isEmpty }), "the quick session did not start")
        #expect(users().count == 1 && users()[0].contains("Pointing at \(part.kind): \(part.path)") && users()[0].contains("Make the weather corner smaller"))
        #expect(model.session.id == nil && model.session.rows.isEmpty, "the main conversation is untouched")
        #expect(await wait(5) { shell.glass.grown == false && !shell.glass.morphing })
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "f3-working" + suffix, root: stage.home.root)
        }

        // The quick session changes the page and ends its turn: Done, the change kept with its named undo.
        let loads = brief.loads
        try was.replacingCharacters(in: style, with: "  .dateline b { font-size: 80%; }\n</style>").write(to: page, atomically: true, encoding: .utf8)
        try Data().write(to: stage.home.root.appendingPathComponent("out/finish"))
        #expect(await wait(until: { quick.phase == .done }), "\(quick.phase)")
        #expect(drawn.badge == "Done" && drawn.chip == "Quick session · Claude Code · Opus 5.5")
        let toast = try #require(shell.layer.subviews.compactMap { $0 as? Toast }.last { $0.shown })
        #expect(toast.words == "Changed Daily brief" && toast.bottom?.constant == -22)
        #expect(changes.versions.list("brief").first?.kind == .quick && shell.undo.undoMenuItemTitle == "Undo “Make the weather corner smaller”")
        #expect(await wait(until: { brief.loads > loads && !brief.web.isLoading && brief.frame != nil }), "the page did not reload")
        await Picture.settle(brief)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "f3-done" + suffix, root: stage.home.root)
        }

        // Then only the chip, which says the session ended.
        #expect(await wait(15) { quick.phase == .ended })
        #expect(drawn.badge == nil && drawn.chip == "Quick session ended" && drawn.superview != nil)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "f3" + suffix, root: stage.home.root)
        }
        shell.layer.subviews.compactMap { $0 as? Toast }.forEach { $0.leave(now: true) }
        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })
    }
    /// Daily brief open with Info shown; the weather corner picked and "Why does the weather say Evening?" asked as a
    /// Quick Change. Its temporary session answers without changing the page: Info closes, the page narrows by 284
    /// points and the margin holds the note, tied to the part by a leader line: the assistant, "Answered · nothing
    /// changed", the answer in the agent's voice, the part and Dismiss, never a button that allows anything (f4). In a
    /// window too narrow for a margin, the note sits under its part and the page keeps its width (f4-narrow). Dismiss
    /// and Esc each give the page its width back.
    @Test("f4: the margin note") func f4() async throws {
        let stage = try Stage("show")
        defer { stage.remove() }
        try AcceptanceAssistant.fake(in: stage)
        Preferences.at(stage.home.places).listed["claude"] = {
            var options = Options()
            options.model = [Option(value: "opus", label: "Opus 5.5")]
            return options
        }()
        let (shell, library, _) = stage.window()
        let model = shell.assistant, engine = model.engine
        engine.changed = { model.refresh() }
        engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        try stage.moment(shell)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        shell.waiting(1, mine: 0)
        shell.layer.announce = { _ in }
        model.choose(model: "opus")
        let changes = Changes(places: stage.home.places, undo: shell.undo)
        changes.follow(model, in: shell, library: library)
        let was = try String(contentsOf: brief.space.location, encoding: .utf8)
        shell.inspector.isCollapsed = false
        let width = brief.area.bounds.width

        shell.point()
        let overlay = try #require(brief.pointer), frame = try #require(brief.frame)
        let at = try #require(try await brief.web.callAsyncJavaScript(
            "const b = document.querySelector('#weather-line').getBoundingClientRect(); return [b.x + b.width / 2, b.y + b.height / 2]",
            in: frame, contentWorld: .defaultClient) as? [Double])
        await overlay.click(at: CGPoint(x: at[0], y: at[1]), adding: false)
        let composer = try #require(overlay.composer), part = try #require(overlay.picks.first)
        composer.field.insertText("Why does the weather say Evening?", replacementRange: composer.field.selectedRange())
        composer.sendQuick()

        // The answer, nothing changed: Info closed, the margin opened, the note in it.
        #expect(await wait(until: { brief.note != nil }), "no note")
        let note = try #require(brief.note)
        #expect(shell.inspector.isCollapsed && note.side == .margin && brief.web.frame.width == width - MarginNote.margin)
        #expect(note.words == "No change made. The weather shows the time of day, because nothing leaves your Mac." && note.title == "Daily brief")
        #expect(note.accessibilityLabel() == "Daily brief’s assistant, no change" && note.accessibilityValue() as? String == note.words)
        #expect(note.part.path == part.path && shell.window.firstResponder === note)
        func buttons(_ view: NSView) -> [NSButton] { [view as? NSButton].compactMap { $0 } + view.subviews.flatMap(buttons) }
        #expect(buttons(note).map(\.title) == ["Dismiss"], "a note never allows anything")
        #expect(try String(contentsOf: brief.space.location, encoding: .utf8) == was && changes.versions.list("brief").allSatisfy { $0.kind != .quick })
        #expect(model.session.id == nil && model.session.rows.isEmpty, "the main conversation is untouched")
        // The page reflowed into its width: the part found again, the note level with it in the margin.
        #expect(await wait(until: { note.part.rect != part.rect && note.part.rect.maxX <= brief.web.frame.width }), "\(note.part.rect)")
        let layout = note.layout
        #expect(note.card.frame == layout.note && layout.note.minX == brief.web.frame.width + 16 && layout.note.width == 252)
        #expect(layout.lead?.first?.x == min(note.part.rect.maxX + PointOverlay.pad, brief.web.frame.width - 6))
        // The quick session's chip has left: only the note stays.
        #expect(await wait(until: { model.quicks["brief"] == nil }))
        #expect(await wait(5) { shell.glass.grown == false && !shell.glass.morphing })
        await Picture.settle(brief)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "f4" + suffix, root: stage.home.root)
        }

        // Dismiss: the page takes its width back. Info shown later closes a note too.
        note.card.dismiss.performClick(nil)
        #expect(brief.note == nil && brief.web.frame.width == width)
        let again = MarginNote.show(note.words, about: note.part, title: "Daily brief", over: brief)
        #expect(brief.web.frame.width == width - MarginNote.margin)
        shell.inspector.isCollapsed = false
        #expect(await wait(until: { brief.note == nil }) && brief.web.frame.width == brief.area.bounds.width && again.superview == nil)
        shell.inspector.isCollapsed = true

        // A narrow window: under the part, the page whole; Esc dismisses it.
        shell.window.setContentSize(NSSize(width: 760, height: 680))
        shell.window.layoutIfNeeded()
        await Picture.settle(brief)
        let found = await Pointing.rects([part.path], in: brief.web, frame: try #require(brief.frame))
        var moved = part
        moved.rect = try #require(found.first ?? nil)
        let narrow = MarginNote.show(note.words, about: moved, title: "Daily brief", over: brief)
        #expect(narrow.side == .under && brief.web.frame.width == brief.area.bounds.width && narrow.card.frame.width == 268)
        #expect(narrow.card.frame.minY > moved.rect.maxY || narrow.card.frame.maxY < moved.rect.minY, "never over its part")
        await Picture.settle(brief)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "f4-narrow" + suffix, root: stage.home.root)
        }
        narrow.cancelOperation(nil)
        #expect(brief.note == nil)
        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })
    }
    /// Daily brief open; its assistant's turn, asked "Make the weather corner smaller", ends having changed the page:
    /// the toast names the change and offers to undo it by that sentence (f5-changed). ⌘Z, through the window's undo
    /// manager, brings the page back, and the toast says Undone with Redo ⇧⌘Z (f5, the mockup's last moment).
    @Test("f5: the undo toast") func f5() async throws {
        let stage = try Stage("show")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        try stage.moment(shell)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        shell.waiting(1, mine: 0)
        shell.layer.announce = { _ in }
        let changes = Changes(places: stage.home.places, undo: shell.undo)
        changes.follow(shell.assistant, in: shell, library: library)
        // The toasts stay while both appearances are drawn.
        changes.toast = { words, action, quiet, _ in _ = shell.toast(words, action: action, quiet: quiet, seconds: 60) }
        let sentence = "Make the weather corner smaller", page = brief.space.location
        let was = try String(contentsOf: page, encoding: .utf8), style = try #require(was.range(of: "</style>"))
        /// The toast in the window layer: its words and its action's.
        func toast() throws -> (words: String, action: String?) {
            let toast = try #require(shell.layer.subviews.compactMap { $0 as? Toast }.last { $0.shown })
            func buttons(_ view: NSView) -> [NSButton] { [view as? NSButton].compactMap { $0 } + view.subviews.flatMap(buttons) }
            return (toast.words, buttons(toast).first?.title)
        }
        /// Waits for the page to load again after a change of its file.
        func reloaded(after loads: Int) async {
            #expect(await wait(until: { brief.loads > loads && !brief.web.isLoading && brief.frame != nil }), "the page did not reload")
            await Picture.settle(brief)
        }

        // The turn, as the assistant says it begins and ends: Daily brief kept as it was, then as the turn left it.
        shell.assistant.turnStarts("brief")
        try was.replacingCharacters(in: style, with: "  .dateline b { font-size: 80%; }\n</style>").write(to: page, atomically: true, encoding: .utf8)
        var loads = brief.loads
        shell.assistant.turnEnded("brief", sentence, "Claude Code")
        let made = changes.versions.list("brief")
        #expect(made.map(\.kind) == [.turn, .outside] && made.first?.sentence == sentence && made.first?.who == "Claude Code")
        #expect(try toast() == ("Changed Daily brief", "Undo “Make the weather corner smaller” ⌘Z"))
        #expect(shell.undo.undoMenuItemTitle == "Undo “Make the weather corner smaller”" && !shell.undo.canRedo)
        await reloaded(after: loads)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "f5-changed" + suffix, root: stage.home.root)
        }

        // ⌘Z: the page as it was, and Redo by the same sentence.
        loads = brief.loads
        shell.undo.undo()
        #expect(try String(contentsOf: page, encoding: .utf8) == was)
        #expect(try toast() == ("Undone “Make the weather corner smaller”", "Redo ⇧⌘Z"))
        #expect(shell.undo.redoMenuItemTitle == "Redo “Make the weather corner smaller”" && !shell.undo.canUndo)
        #expect(changes.versions.list("brief").map(\.kind) == [.restore, .turn, .outside])
        await reloaded(after: loads)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "f5" + suffix, root: stage.home.root)
        }
        shell.layer.subviews.compactMap { $0 as? Toast }.forEach { $0.leave(now: true) }
    }
    @Test("f6: History", .disabled("not built yet: T19")) func f6() async throws {}
    @Test("f7: the glimpse", .disabled("not built yet: T20")) func f7() async throws {}
    @Test("f8: changed outside something", .disabled("not built yet: T21")) func f8() async throws {}
    @Test("f9: comment pins", .disabled("not built yet: T18")) func f9() async throws {}
    @Test("f10: the comments tray", .disabled("not built yet: T18")) func f10() async throws {}
    @Test("f11: comments sent together", .disabled("not built yet: T18")) func f11() async throws {}
}
