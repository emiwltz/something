// Acceptance scenarios of show and change: pointing, picked frames, the margin note, the toast, History, the glimpse and
// the comments (f1–f11).
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
    /// the mode and Esc. Point is greyed only when there is nothing to point at; a reload keeps the mode.
    @Test("f1: pointing") func f1() async throws {
        let stage = try Stage("show")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        try stage.moment(shell)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        shell.waiting(["agents"], mine: 0)
        let point = try #require(shell.controls[Shell.point] as? ToolButton)
        #expect(point.isEnabled && !point.pressed && brief.pointable)
        #expect(Keys.enabled("pointpart", Keys.Situation(space: true)) && !Keys.enabled("pointpart", Keys.Situation(space: true, pointable: false)))
        #expect(Keys.command("pointpart")?.shown == "⌥⌘S" && point.toolTip == "Point (⌥⌘S)")

        shell.point()
        let overlay = try #require(brief.pointer)
        #expect(point.pressed && !shell.assistant.open && overlay.frame == brief.web.frame)
        #expect(overlay.accessibilityLabel() == "Point at a part of the space" && overlay.accessibilityHelp() == "Esc to stop. Tab frames the next part, Return picks it")
        // The pointer over the waiting box: its frame and kind.
        let frame = try #require(brief.frame)
        let box = try #require(try await brief.web.callAsyncJavaScript(
            "const b = document.querySelector('.box').getBoundingClientRect(); return [b.right - 5, b.y + b.height / 2]",
            in: frame, contentWorld: .defaultClient) as? [Double])
        overlay.look(at: CGPoint(x: box[0], y: box[1]))
        #expect(await wait(until: { overlay.hovered != nil }))
        #expect(overlay.hovered?.kind == "this block" && overlay.accessibilityValue() as? String == "this block")
        #expect(overlay.hovered?.tag == "div" && overlay.hovered?.path.contains("box") == false, "\(String(describing: overlay.hovered))")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "f1" + suffix, root: stage.home.root)
        }

        // Esc stops it, the page's keys back; ⌥⌘S again starts it, and a stopped page cannot be pointed at.
        #expect(overlay.escape() == true)
        #expect(brief.pointer == nil && !point.pressed)
        shell.point()
        #expect(brief.pointer != nil)
        // A reload (⌘R, a change of the assistant, an undo) keeps the mode: the window shows the space again, as the
        // app does at each load, and Point stays pressed and enabled while the page loads.
        brief.load()
        shell.show(brief)
        #expect(brief.frame == nil && brief.pointer != nil && point.pressed && point.isEnabled && brief.pointable)
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
        shell.waiting(["agents"], mine: 0)
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
        shell.waiting(["agents"], mine: 0)
        shell.layer.announce = { _ in }
        model.choose(model: "opus")
        // Long enough to draw Done and the end in both appearances, on a loaded Mac too.
        model.lingers = (20, 60)
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
        let point = try #require(shell.controls[Shell.point] as? ToolButton)
        #expect(brief.pointer == nil && !point.pressed)
        let quick = try #require(model.quicks["brief"])
        let drawn = try #require(brief.area.subviews.compactMap { $0 as? QuickFrame }.first)
        #expect(drawn.quick === quick && quick.parts == [part] && drawn.hitTest(NSPoint(x: 50, y: 50)) == nil && drawn.frame == brief.web.frame)
        #expect(drawn.chip == "Quick session · Claude Code · Opus 5.5" && drawn.badge == "Working")
        #expect(drawn.accessibilityLabel() == "Quick session · Claude Code · Opus 5.5" && drawn.accessibilityValue() as? String == "Working")
        #expect(await wait(until: { !users().isEmpty }), "the quick session did not start")
        #expect(users().count == 1 && users()[0].contains("Pointing at \(part.kind): \(part.path)") && users()[0].contains("Make the weather corner smaller"))
        #expect(model.session.id == nil && model.session.rows.isEmpty, "the main conversation is untouched")
        #expect(await wait { shell.glass.grown == false && !shell.glass.morphing })
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "f3-working" + suffix, root: stage.home.root)
        }

        // The quick session changes the page and ends its turn: Done, the change kept with its named undo. Done
        // lasts its set time, then the chip says the session ended: the drawing turn is taken first, since waiting
        // for it while another suite draws could outlast both moments.
        try await Stage.alone {
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
            #expect(await wait(30) { quick.phase == .ended })
            #expect(drawn.badge == nil && drawn.chip == "Quick session ended" && drawn.superview != nil)
            // The mockup's f9 (Quick Change) is this same moment, its shot the same: drawn here, its keys proven in f9.
            try await stage.appearances { suffix in
                try await Picture.window(shell, library: library, web: brief.web, "f3" + suffix, root: stage.home.root)
                try await Picture.window(shell, library: library, web: brief.web, "f9" + suffix, root: stage.home.root)
            }
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
        shell.waiting(["agents"], mine: 0)
        shell.layer.announce = { _ in }
        model.choose(model: "opus")
        let changes = Changes(places: stage.home.places, undo: shell.undo)
        changes.follow(model, in: shell, library: library)
        let was = try String(contentsOf: brief.space.location, encoding: .utf8)
        shell.window.layoutIfNeeded()
        let width = brief.area.bounds.width
        shell.inspector.isCollapsed = false
        shell.window.layoutIfNeeded()

        shell.point()
        let overlay = try #require(brief.pointer), frame = try #require(brief.frame)
        // Info narrowed the page: the point is measured once the page has reflowed into its new width.
        var reflowed = false
        for _ in 0..<250 where !reflowed {
            let inner = try? await brief.web.callAsyncJavaScript("return window.innerWidth", in: frame, contentWorld: .defaultClient) as? Double
            reflowed = inner.map { abs($0 - brief.web.frame.width) < 1 && brief.web.frame.width < width } ?? false
            if !reflowed { await wait(0.02) }
        }
        #expect(reflowed, "the page did not reflow beside Info")
        await Picture.settle(brief)
        let at = try #require(try await brief.web.callAsyncJavaScript(
            "const b = document.querySelector('#weather-line').getBoundingClientRect(); return [b.x + b.width / 2, b.y + b.height / 2]",
            in: frame, contentWorld: .defaultClient) as? [Double])
        await overlay.click(at: CGPoint(x: at[0], y: at[1]), adding: false)
        let composer = try #require(overlay.composer), part = try #require(overlay.picks.first)
        // The weather line itself is smaller than a part: its dateline is what is picked, named by its tag alone.
        let holds = try await brief.web.callAsyncJavaScript("return document.querySelector(path).contains(document.querySelector('#weather-line'))",
                                                            arguments: ["path": part.path], in: frame, contentWorld: .defaultClient) as? Bool
        #expect(holds == true && part.tag == "div" && part.kind == "this block", "\(part.path)")
        composer.field.insertText("Why does the weather say Evening?", replacementRange: composer.field.selectedRange())
        composer.sendQuick()
        // The person goes on elsewhere while the quick session works: the note does not take that focus.
        let typing = shell.window.firstResponder

        // The answer, nothing changed: Info closed, the margin opened, the note in it.
        #expect(await wait(until: { brief.note != nil }), "no note")
        let note = try #require(brief.note)
        #expect(shell.inspector.isCollapsed && note.side == .margin && brief.web.frame.width == width - MarginNote.margin)
        #expect(note.words == "No change made. The weather shows the time of day, because nothing leaves your Mac." && note.title == "Daily brief")
        #expect(note.accessibilityLabel() == "Daily brief’s assistant, no change" && note.accessibilityValue() as? String == note.words)
        #expect(note.part.path == part.path && shell.window.firstResponder === typing && !note.acceptsFirstResponder)
        #expect(note.card.voice == Look.font(.voice, size: 13.5), "the answer in the agent's voice")
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
        #expect(await wait { shell.glass.grown == false && !shell.glass.morphing })
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
        shell.window.setContentSize(NSSize(width: 720, height: 680))
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
        // The window widens: the margin comes back, the page beside it.
        shell.window.setContentSize(NSSize(width: 1200, height: 760))
        shell.window.layoutIfNeeded()
        #expect(narrow.side == .margin && brief.web.frame.width == brief.area.bounds.width - MarginNote.margin && narrow.card.frame.width == 252)
        shell.window.setContentSize(NSSize(width: 720, height: 680))
        shell.window.layoutIfNeeded()
        #expect(narrow.side == .under && brief.web.frame.width == brief.area.bounds.width && narrow.card.frame.width == 268)
        // Esc through the window's key handling, wherever the focus is.
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: shell.window.windowNumber,
                                                   context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        #expect(shell.escape(escape) && brief.note == nil && !shell.escape(escape))
        // An answer for a space not shown waits for it, and shows when it is shown again; a trashed space's is forgotten.
        let quick = AssistantModel.Quick(space: "brief", sentence: "Why?", session: model.session, chip: "", parts: [moved])
        shell.show(nil)
        shell.note(note.words, about: quick)
        #expect(brief.note == nil)
        shell.show(brief)
        #expect(brief.note?.words == note.words)
        brief.note?.dismiss()
        shell.show(nil)
        shell.note(note.words, about: quick)
        shell.forget("brief")
        shell.show(brief)
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
        shell.waiting(["agents"], mine: 0)
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
        /// Waits for the page to load again after a change of its file, and for the last toast to have risen in place.
        func reloaded(after loads: Int) async {
            #expect(await wait(until: { brief.loads > loads && !brief.web.isLoading && brief.frame != nil }), "the page did not reload")
            await Picture.settle(brief)
            #expect(await wait { shell.layer.subviews.compactMap { $0 as? Toast }.last { $0.shown }?.bottom?.constant == -22 },
                    "the toast rose")
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
    /// The mockup's twelve versions of Daily brief, oldest first: the sentence (nil for the state kept before the first
    /// change, and for an edit no turn claims), the day of October and the time, local.
    static let briefVersions: [(String?, Int, Int, Int)] = [
        (nil, 12, 9, 0), ("Make me a morning paper of my agents", 12, 9, 4), ("Put the date under the title", 13, 10, 15),
        ("Add a quote of the day", 14, 17, 40), ("Split the news into three columns", 15, 11, 30), ("Use a serif for the headlines", 17, 16, 5),
        ("Use a newspaper look, like a morning paper", 19, 9, 20), ("Add the day’s numbers under At work", 20, 11, 2),
        ("Make the headlines shorter", 21, 14, 30), ("Put the agents that wait for me first", 21, 21, 5), (nil, 22, 16, 40),
        ("Add a weather corner, top right", 22, 18, 12),
    ]

    /// Daily brief open, its twelve versions kept: Info's History, beside Export, puts History in Info's place, 320 points, the page narrowed beside it. History opens on the
    /// version before the newest, the edit outside something with its pencil, six rows, then the fold to the six
    /// older back to 12 October; Hold Space to compare beside Restore This Version. The newest's picture is taken once
    /// its page settled. ↓ moves the choice; a restore waits while the assistant works, then is a version; Esc closes.
    @Test("f6: History") func f6() async throws {
        let stage = try Stage("show")
        defer { stage.remove() }
        let (shell, library, info) = stage.window()
        try stage.moment(shell)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        shell.waiting(["agents"], mine: 0)
        shell.layer.announce = { _ in }
        info.clock = { Stage.local }
        info.current = { brief }
        let changes = Changes(places: stage.home.places, undo: shell.undo)
        changes.follow(shell.assistant, in: shell, library: library)
        var said: [String] = []
        changes.toast = { words, _, _, _ in said.append(words) }
        let page = brief.space.location, was = try String(contentsOf: page, encoding: .utf8), store = info.history.store
        let all = try await Self.keepVersions(of: brief, info)

        // Info: its Space part, History a tab beside it. The page's width before the panel opens, at Default's size.
        let wide = await Stage.alone { shell.window.layoutIfNeeded(); return brief.web.frame.width }
        shell.showInfo(true, on: .info)
        shell.window.layoutIfNeeded()
        let panel = shell.inspector.viewController.view
        let infoRead = await AcceptanceBuild.read(panel)
        #expect(infoRead.contains("Space") && infoRead.contains("Show History") && infoRead.contains("Export…"), "\(infoRead)")
        #expect(info.history.bytes == store.weight("brief") && History.when(all[0].when, now: info.clock()) == "Today 18:12")
        // History: a tab of the panel, at its width, its button still pressed. The 320 points are Default's: read
        // in the drawing turn, which no other suite holds at Large meanwhile.
        info.select(.history)
        #expect(shell.infoShown && info.content == .history && (shell.controls[Shell.info] as? ToolButton)?.pressed == true)
        await Stage.alone {
            let width = { shell.inspector.viewController.view.frame.width }
            #expect(await wait(10) { shell.window.layoutIfNeeded(); return width() == 320 && brief.web.frame.width == wide - 320 },
                    "\(width()) \(brief.web.frame.width) \(wide)")
        }
        let history = info.history
        #expect(history.chosen == all[1].id && history.restorable && history.rows.count == 6)
        #expect(history.older == "6 older versions, back to 12 October")
        let read = await AcceptanceBuild.read(panel)
        for words in ["History", "“Add a weather corner, top right”, Today 18:12 · Claude Code, now",
                      "Edited outside something, Today 16:40 · Changed on disk, not by its assistant",
                      "“Use a newspaper look, like a morning paper”, Monday 09:20 · Claude Code", "6 older versions, back to 12 October",
                      "Hold Space to compare", "Restore This Version", "Close the panel"] {
            #expect(read.contains(words), "History reads \(words): \(read)")
        }
        #expect(!read.contains { $0.contains("Before its first change") }, "the oldest is folded")
        #expect(!read.contains { $0.range(of: #"\bAllow\b"#, options: .regularExpression) != nil })
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "f6" + suffix, root: stage.home.root)
        }

        // ↓ and ↑ as keys with the focus in the panel; ⌘I goes back to Info, History again opens on the
        // version before the newest.
        #expect(shell.window.makeFirstResponder(panel.subviews.first ?? panel))
        let arrow = { (code: UInt16) in
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: shell.window.windowNumber,
                             context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)
        }
        for code: UInt16 in [125, 125, 126] { shell.window.sendEvent(try #require(arrow(code))) }
        #expect(history.chosen == all[2].id)
        shell.toggleInfo(spaceOpen: true)
        #expect(!shell.infoShown, "⌘I closes the panel on any tab")
        #expect(Keys.command("history")?.action == #selector(App.showHistory(_:)) && Keys.enabled("history", Keys.Situation(space: true)))
        shell.showHistory()
        #expect(info.content == .history && history.chosen == all[1].id)
        history.chosen = all[2].id

        // Restore This Version waits while the assistant works on Daily brief, then is a version, the newest chosen.
        changes.working = { _ in true }
        history.restore()
        #expect(said.last == "Daily brief’s assistant is working · restore once it’s done" && history.versions.count == 12)
        changes.working = { _ in false }
        history.restore()
        #expect(try String(contentsOf: page, encoding: .utf8) == was + "<!-- 9 -->\n")
        #expect(history.versions.count == 13 && history.versions[0].kind == .restore && history.chosen == history.versions[0].id)
        #expect(said.last == "Restored the version of Yesterday 21:05" && history.title(history.versions[0]) == said.last)

        // Esc with the focus in it closes it; the page takes its width back.
        #expect(shell.escape(try #require(arrow(53))))
        #expect(!shell.infoShown)
        await Stage.alone {
            #expect(await wait(10) { shell.window.layoutIfNeeded(); return shell.inspector.isCollapsed && brief.web.frame.width == wide },
                    "\(wide) \(brief.web.frame.width)")
        }
        // Opened again after the restore: on the version before the newest, not on Now. Restoring the version the
        // space already is says so.
        shell.showHistory()
        #expect(history.chosen == history.versions[1].id && history.restorable)
        history.chosen = all[2].id
        history.restore()
        #expect(said.last == "Daily brief is already the version of Yesterday 21:05" && history.versions.count == 13)
        #expect(history.versions.last?.first == true && history.title(history.versions.last!) == "As something first kept it")
        shell.showInfo(false)
    }
    /// Keeps Daily brief's twelve versions, each a little other file, the newest the page as it loaded, and their
    /// pictures: the newest's once its page settled, the older ones, never shown, given the same. `older` changes the
    /// page of the versions before the last three. Returns them, newest first.
    static func keepVersions(of brief: SpaceView, _ info: Info, older: (String) -> String = { $0 }) async throws -> [Versions.Version] {
        let page = brief.space.location, was = try String(contentsOf: page, encoding: .utf8), store = info.history.store
        for (index, version) in briefVersions.enumerated() {
            let last = index == briefVersions.count - 1, then = index < briefVersions.count - 3 ? older(was) : was
            try (last ? was : then + "<!-- \(index) -->\n").write(to: page, atomically: true, encoding: .utf8)
            let at = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: version.1, hour: version.2, minute: version.3)))
            try store.capture(brief.space, kind: version.0 == nil ? .outside : .turn, sentence: version.0, who: version.0 == nil ? nil : "Claude Code", at: at)
        }
        // Loaded here, at its last file: the folder's watch, which looks each second, has nothing left to reload.
        brief.load()
        #expect(await wait(until: { !brief.web.isLoading && brief.frame != nil }))
        await Picture.settle(brief)
        info.show(brief.space)
        let all = info.history.versions
        #expect(all.count == 12 && all[1].kind == .outside && all.last?.kind == .outside)
        // Taken in the day appearance the pictures are compared in, whatever this Mac's own.
        await Stage.alone {
            NSApp.appearance = NSAppearance(named: .aqua)
            #expect(await info.history.picture(of: brief), "the picture of the newest version")
        }
        let picture = try Data(contentsOf: store.picture("brief", all[0].id))
        #expect(store.list("brief").first?.thumb != nil && NSImage(data: picture)?.isValid == true)
        for version in all.dropFirst() { try store.keep(picture: picture, of: version.id, in: "brief") }
        info.show(brief.space)
        return all
    }

    /// History open on “Make the headlines shorter”: held, that version fades in over the page in a second locked web
    /// view, the row ringed, the label at the top of the space saying which version, when, and Release to see now. Its
    /// writes are refused, Daily brief's journal unchanged, the library lists no new space. Let go, the page is now
    /// again; Space held with the focus in History does the same. Closing History removes the copy.
    @Test("f7: the glimpse") func f7() async throws {
        let stage = try Stage("show")
        defer { stage.remove() }
        let (shell, library, info) = stage.window()
        try stage.moment(shell)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        shell.waiting(["agents"], mine: 0)
        info.clock = { Stage.local }
        info.current = { brief }
        let all = try await Self.keepVersions(of: brief, info) { $0.replacingOccurrences(of: "<h1>The Daily Brief</h1>", with: "<h1>Daily Brief</h1>") }
        let spaces = library.entries.count, journal = try Journal(folder: stage.home.places.journals).last(50, space: "brief")
        shell.showHistory()
        shell.window.layoutIfNeeded()
        let history = info.history
        history.chosen = all[3].id
        history.press(all[3].id)
        #expect(!history.comparing, "a press shows nothing before it is held")
        #expect(await wait(until: { history.glimpse?.shown == true }), "the held version did not show")
        let glimpse = try #require(history.glimpse), held = try #require(glimpse.view)
        #expect(history.comparing && history.chosen == all[3].id && glimpse.cover.frame == brief.web.frame)
        #expect(await wait(until: { glimpse.cover.alphaValue == 1 }))
        #expect(try await run(held, "return document.querySelector('.mast h1').textContent") as? String == "Daily Brief")
        #expect(try await run(brief, "return document.querySelector('.mast h1').textContent") as? String == "The Daily Brief")
        let label = await AcceptanceBuild.read(glimpse.cover)
        #expect(label == ["“Make the headlines shorter”", "Yesterday 14:30", "Release to see now"], "\(label)")
        for call in ["something.send('a1', 'invented')", "something.store.set('seen', 1)"] {
            #expect(try await run(held, "try { await \(call); return 'answered' } catch (e) { return e.code }") as? String == "NOT_SUPPORTED", "\(call)")
        }
        #expect(try Journal(folder: stage.home.places.journals).last(50, space: "brief") == journal)
        library.relist()
        #expect(library.entries.count == spaces && !held.space.location.path.hasPrefix(stage.home.places.spaces.path))
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "f7" + suffix, root: stage.home.root)
        }

        // Let go: now again, its web view released.
        history.lift()
        #expect(!history.comparing && glimpse.view == nil)
        #expect(await wait(until: { glimpse.cover.superview == nil }))
        // Space, held with the focus in History.
        let panel = shell.inspector.viewController.view
        #expect(shell.window.makeFirstResponder(panel.subviews.first ?? panel))
        let space = { (type: NSEvent.EventType) in
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: shell.window.windowNumber,
                             context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)
        }
        shell.window.sendEvent(try #require(space(.keyDown)))
        #expect(history.comparing && history.glimpse != nil)
        shell.window.sendEvent(try #require(space(.keyUp)))
        #expect(!history.comparing && history.glimpse == nil)
        // Closing History removes the copy.
        let copy = Glimpse.folder(history.store, "brief")
        #expect(FileManager.default.fileExists(atPath: copy.path))
        shell.showInfo(false)
        #expect(!FileManager.default.fileExists(atPath: copy.path))
    }
    /// Daily brief open with its twelve versions, nothing running on it: its page changes on disk, a line added by
    /// hand. The folder's watch sees it, the page reloads with it, and it is kept as an edit outside something; a quiet
    /// toast says "Daily brief changed outside something" with Show What Changed (f8-toast). Nothing is undone: the
    /// file keeps the line. Show What Changed opens History on the version before, ready to compare or restore; the
    /// newest row, with its pencil, says what changed in its files and that something kept the version before it; it
    /// is added on top of the six rows f6 shows, the fold still "6 older versions".
    @Test("f8: changed outside something") func f8() async throws {
        let stage = try Stage("show")
        defer { stage.remove() }
        let (shell, library, info) = stage.window()
        try stage.moment(shell)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        shell.waiting(["agents"], mine: 0)
        var announced: [String] = []
        shell.layer.announce = { announced.append($0) }
        info.clock = { Stage.local }
        info.current = { brief }
        let changes = Changes(places: stage.home.places, undo: shell.undo)
        changes.follow(shell.assistant, in: shell, library: library)
        changes.clock = { Stage.local.addingTimeInterval(60) }
        // It stays until Show What Changed: a turn to read it or draw it can take minutes on a loaded Mac.
        changes.toast = { words, action, quiet, _ in _ = shell.toast(words, action: action, quiet: quiet, seconds: 3600) }
        let all = try await Self.keepVersions(of: brief, info)
        // As the app wires each open space's watch (App.open).
        brief.changed = { changes.seen("brief") }
        let loads = brief.loads, page = brief.space.location, was = try String(contentsOf: page, encoding: .utf8)
        let mark = #"<div id="paper" class="cols"></div>"#
        #expect(was.contains(mark))
        let edited = was.replacingOccurrences(of: mark, with: #"<div class="ears caps"><span>Late edition, set by hand</span></div>"# + "\n  " + mark)
        try edited.write(to: page, atomically: true, encoding: .utf8)

        // The watch, which looks each second, keeps it and reloads the page.
        #expect(await wait(until: { info.history.versions.count == 13 && brief.loads > loads }), "the watch did not keep the edit")
        #expect(await wait(until: { !brief.web.isLoading && brief.frame != nil }))
        let newest = try #require(info.history.versions.first)
        #expect(newest.kind == .outside && newest.who == nil && newest.summary == "brief.html · one line added" && newest.first == nil)
        #expect(try String(contentsOf: page, encoding: .utf8) == edited, "nothing is undone by itself")
        let toast = try #require(shell.layer.subviews.compactMap { $0 as? Toast }.last { $0.shown })
        #expect(toast.words == "Daily brief changed outside something" && announced.last == toast.words)
        let toastRead = await AcceptanceBuild.read(toast) { $0.contains("Show What Changed") }
        // Read again without the awaited words, which end the first read before the rest may be there.
        let whole = await AcceptanceBuild.read(toast)
        #expect(toastRead.contains("Show What Changed") && !whole.contains { $0.range(of: #"\bAllow\b"#, options: .regularExpression) != nil }, "\(whole)")
        await Picture.settle(brief)
        await Stage.alone {
            NSApp.appearance = NSAppearance(named: .aqua)
            #expect(await info.history.picture(of: brief), "the picture of the edit")
        }
        info.show(brief.space)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "f8-toast" + suffix, root: stage.home.root)
        }

        // Show What Changed: History, on the version before the edit.
        toast.act()
        shell.window.layoutIfNeeded()
        let history = info.history
        #expect(shell.infoShown && info.content == .history && history.chosen == all[0].id && history.restorable)
        #expect(history.versions.count == 13 && history.versions[1].id == all[0].id && history.rows.count == 7)
        #expect(history.older == "6 older versions, back to 12 October")
        let read = await AcceptanceBuild.read(shell.inspector.viewController.view)
        for words in ["History", "Edited outside something, Today 18:21 · Changed on disk, not by its assistant, brief.html · one line added. something kept the version before it., now",
                      "“Add a weather corner, top right”, Today 18:12 · Claude Code",
                      "Edited outside something, Today 16:40 · Changed on disk, not by its assistant",
                      "“Use a newspaper look, like a morning paper”, Monday 09:20 · Claude Code", "6 older versions, back to 12 October",
                      "Hold Space to compare", "Restore This Version"] {
            #expect(read.contains(words), "History reads \(words): \(read)")
        }
        #expect(await wait(until: { toast.superview == nil }), "the toast left")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "f8" + suffix, root: stage.home.root)
        }
        shell.showInfo(false)
    }
    /// The mockup's comments: a selector of Daily brief's page, where in it to click, and the words.
    static let comments: [(String, Double, String)] = [
        (".dateline", 0.5, "Make it smaller, one line"), (".mast h1", 0.5, "Add the week number after the date"),
        ("#paper > :first-child", 0.3, "Keep this to two short paragraphs"),
    ]

    /// ⌘↵, as the keyboard sends it to `window`.
    static func commandReturn(_ window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
                                      context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
    }

    /// Picks the part of `space` under the element `selector`, `across` its width at its middle, writes `words` in the
    /// composer and adds them with ⌘↵. Returns the part.
    @discardableResult
    static func comment(_ selector: String, across: Double, _ words: String, over space: SpaceView) async throws -> Pointing.Part {
        let overlay = try #require(space.pointer), frame = try #require(space.frame)
        let at = try #require(try await space.web.callAsyncJavaScript(
            "const b = document.querySelector(s).getBoundingClientRect(); return [b.x + b.width * a, b.y + b.height / 2]",
            arguments: ["s": selector, "a": across], in: frame, contentWorld: .defaultClient) as? [Double])
        await overlay.click(at: CGPoint(x: at[0], y: at[1]), adding: false)
        let composer = try #require(overlay.composer), part = try #require(overlay.picks.first)
        composer.field.insertText(words, replacementRange: composer.field.selectedRange())
        #expect(composer.field.performKeyEquivalent(with: try commandReturn(try #require(space.web.window))))
        return part
    }

    /// The composer's two gestures side by side, by their keys (the mockup's f9 is Quick Change's last moment, the same
    /// screen as f3's, which f3 draws as f9): ↵ makes a Quick Change of the words about the parts; ⌘↵ adds them as a
    /// comment, and point mode stays on to pick another part. ⌘↵ in the window sends the comments, never while the
    /// composer is open; an assistant that cannot start refuses them, said in a toast, and they stay to send again.
    @Test("f9: Quick Change beside Add Comment") func f9() async throws {
        let stage = try Stage("show")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        try stage.moment(shell)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        shell.layer.announce = { _ in }
        shell.point()
        let overlay = try #require(brief.pointer), frame = try #require(brief.frame)
        var quick: (String, [Pointing.Part])?
        overlay.quickChange = { quick = ($0, $1) }
        let at = try #require(try await brief.web.callAsyncJavaScript(
            "const b = document.querySelector('.mast h1').getBoundingClientRect(); return [b.x + b.width / 2, b.y + b.height / 2]",
            in: frame, contentWorld: .defaultClient) as? [Double])
        await overlay.click(at: CGPoint(x: at[0], y: at[1]), adding: false)
        let composer = try #require(overlay.composer)
        composer.field.insertText("Make the masthead smaller", replacementRange: composer.field.selectedRange())
        composer.field.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(quick?.0 == "Make the masthead smaller" && quick?.1 == overlay.picks && Comments.of(brief) == nil)
        // ⌘↵ in the composer: a comment, the mode on, no part picked; ⌘↵ in the window is the composer's while it is open.
        #expect(!shell.sendComments(try AcceptanceShow.commandReturn(shell.window)))
        #expect(composer.field.performKeyEquivalent(with: try AcceptanceShow.commandReturn(shell.window)))
        let comments = try #require(Comments.of(brief))
        #expect(comments.list.map(\.words) == ["Make the masthead smaller"] && brief.pointer === overlay && overlay.picks.isEmpty && overlay.composer == nil)
        // Sent with no assistant to start: refused, said, kept.
        #expect(shell.sendComments(try AcceptanceShow.commandReturn(shell.window)))
        #expect(comments.phase == .writing && comments.list.count == 1 && brief.pointer != nil)
        let toast = try #require(shell.layer.subviews.compactMap { $0 as? Toast }.last)
        #expect(toast.words == "Daily brief’s assistant can’t start · open its card to see why")
        shell.layer.subviews.compactMap { $0 as? Toast }.forEach { $0.leave(now: true) }
    }

    /// Daily brief in point mode; the weather corner, the masthead and the lead story picked one after the other, each
    /// given words and Add Comment (⌘↵): a numbered pin at each part, point mode still on to pick the next, its banner
    /// gone, and the tray at the bottom of the space, 640 wide: each comment's number, part and words, then "3
    /// comments", the way on (Point at another part · Esc Stop Pointing), Clear and Send to Assistant ⌘↵ (f10). Nothing
    /// is sent before Send, and nothing allows anything. A comment taken out renumbers the others; Esc stops pointing
    /// and the tray stays; Clear takes them all, and the banner comes back.
    @Test("f10: the comments tray") func f10() async throws {
        let stage = try Stage("show")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        try stage.moment(shell)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        shell.waiting(["agents"], mine: 0)
        shell.point()
        let overlay = try #require(brief.pointer)
        var parts: [Pointing.Part] = []
        for (selector, across, words) in AcceptanceShow.comments { parts.append(try await AcceptanceShow.comment(selector, across: across, words, over: brief)) }
        let comments = try #require(Comments.of(brief)), tray = comments.tray
        #expect(brief.pointer === overlay && overlay.picks.isEmpty && overlay.composer == nil && overlay.commented())
        #expect(comments.list.map(\.words) == AcceptanceShow.comments.map(\.2) && comments.list.map(\.part.path) == parts.map(\.path))
        #expect(comments.pins == parts.indices.map { "Comment \($0 + 1) on \(parts[$0].kind)" } && comments.phase == .writing)
        #expect(tray.footer == ["3 comments", "Point at another part", "Esc", "Stop Pointing"] && tray.accessibilityLabel() == "Comments")
        #expect(tray.fields.map(\.stringValue) == AcceptanceShow.comments.map(\.2) && tray.fields.allSatisfy(\.isEditable))
        #expect(tray.frame.width == 640 && abs(tray.frame.midX - comments.bounds.width / 2) <= 0.5 && tray.frame.maxY == comments.bounds.height - 16)
        #expect(tray.frame.height == 6 + 3 * 31 + 2 + 46 && comments.frame == brief.web.frame)
        #expect(tray.sendButton.title == "Send to Assistant" && tray.sendButton.hint == "⌘↵" && tray.sendButton.primary && tray.clear.title == "Clear")
        func buttons(_ view: NSView) -> [NSButton] { [view as? NSButton].compactMap { $0 } + view.subviews.flatMap(buttons) }
        #expect(!buttons(tray).contains { $0.title.contains("Allow") }, "a comment never allows anything")
        #expect(!FileManager.default.fileExists(atPath: stage.home.root.appendingPathComponent("out/input").path), "nothing sent")
        // A click on the tray is the tray's, never a pick of the page under it.
        let inTray = comments.convert(CGPoint(x: tray.frame.midX, y: tray.frame.maxY - 20), to: comments.superview)
        #expect(comments.superview?.hitTest(inTray).map { $0 === tray || $0.isDescendant(of: tray) } == true)
        #expect(comments.hitTest(comments.convert(CGPoint(x: 30, y: 30), to: comments.superview)) == nil)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "f10" + suffix, root: stage.home.root)
        }

        tray.removes[1].performClick(nil)
        #expect(comments.pins == ["Comment 1 on \(parts[0].kind)", "Comment 2 on \(parts[2].kind)"] && tray.footer[0] == "2 comments")
        #expect(overlay.escape() && brief.pointer == nil && tray.footer == ["2 comments"] && Comments.of(brief) === comments)
        tray.clear.performClick(nil)
        #expect(Comments.of(brief) == nil)
        shell.point()
        #expect(brief.pointer?.commented() == false)
    }

    /// The three comments of f10, Send to Assistant (⌘↵): point mode closes, the card opens on the conversation, and
    /// the comments go in one message to Daily brief's main assistant, which the card shows as the numbered list; the
    /// tray moves to the left of the card and says it works through them, the pins kept (f11, the mockup's moment). Its
    /// turn changes the page and ends: every pin and row a check, the words struck through, "All done", and the change
    /// kept as one version named "3 comments", undone by that name, its toast clear of the card (f11-done).
    @Test("f11: comments sent together") func f11() async throws {
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
        shell.waiting(["agents"], mine: 0)
        shell.layer.announce = { _ in }
        model.choose(model: "opus")
        library.preferences.motion = .reduced
        let changes = Changes(places: stage.home.places, undo: shell.undo)
        changes.follow(model, in: shell, library: library)
        changes.toast = { words, action, quiet, _ in _ = shell.toast(words, action: action, quiet: quiet, seconds: 60) }
        let page = brief.space.location, was = try String(contentsOf: page, encoding: .utf8), style = try #require(was.range(of: "</style>"))
        let users = { ((try? String(contentsOf: stage.home.root.appendingPathComponent("out/input"), encoding: .utf8)) ?? "")
            .split(separator: "\n").filter { $0.contains(#""type":"user""#) } }

        shell.point()
        var parts: [Pointing.Part] = []
        for (selector, across, words) in AcceptanceShow.comments { parts.append(try await AcceptanceShow.comment(selector, across: across, words, over: brief)) }
        let comments = try #require(Comments.of(brief)), tray = comments.tray
        comments.linger = 60
        #expect(shell.sendComments(try AcceptanceShow.commandReturn(shell.window)))

        // Sent: the mode closed, the card open on the conversation, the tray beside it, at work.
        let point = try #require(shell.controls[Shell.point] as? ToolButton)
        #expect(brief.pointer == nil && !point.pressed && model.open && model.threadShown && comments.phase == .sending)
        #expect(tray.footer == ["3 comments", "Working through them"] && tray.frame.minX == 16 && tray.frame.width == 460 && tray.removes.allSatisfy(\.isHidden))
        #expect(!tray.fields.contains(where: \.isEditable) && tray.sendButton.isHidden && tray.clear.isHidden)
        let list = parts.indices.map { "\($0 + 1). \(parts[$0].kind.prefix(1).uppercased() + parts[$0].kind.dropFirst()): \(AcceptanceShow.comments[$0].2)" }
        let shown = (["3 comments on this page:"] + list).joined(separator: "\n")
        #expect(await wait(until: { model.rows.contains(.mine(caption: "about Daily brief", text: shown)) }), "\(model.rows)")
        #expect(await wait(until: { !users().isEmpty }), "the fake read nothing")
        #expect(users().count == 1 && users()[0].contains(parts.indices.map { "[something] Comment \($0 + 1) is on \(parts[$0].kind): \(parts[$0].path)" }.joined(separator: "\\n")), "\(users())")
        #expect(model.session === model.session(for: AssistantModel.place(brief)) && model.quicks.isEmpty, "the main assistant's")
        #expect(await wait { shell.glass.grown == true && !shell.glass.morphing })
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "f11" + suffix, root: stage.home.root)
        }

        // The turn changes the page and ends: all done, one version named by the count.
        let loads = brief.loads
        try was.replacingCharacters(in: style, with: "  .dateline b { font-size: 80%; }\n</style>").write(to: page, atomically: true, encoding: .utf8)
        try Data().write(to: stage.home.root.appendingPathComponent("out/finish"))
        #expect(await wait(until: { comments.phase == .done }), "\(comments.phase)")
        #expect(tray.footer == ["3 comments", "All done"] && comments.pins.allSatisfy { $0.hasSuffix(", done") })
        #expect(tray.fields.allSatisfy { ($0.attributedStringValue.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int) == 1 })
        let made = changes.versions.list("brief")
        #expect(made.map(\.kind) == [.turn, .outside] && made.first?.sentence == "3 comments" && shell.undo.undoMenuItemTitle == "Undo “3 comments”")
        #expect(await wait(until: { brief.loads > loads && !brief.web.isLoading && brief.frame != nil }), "the page did not reload")
        await Picture.settle(brief)
        // The toast stands where every toast does, at the bottom centre of the center, whatever the card or the tray.
        let toast = try #require(shell.layer.subviews.compactMap { $0 as? Toast }.first)
        shell.layer.layoutSubtreeIfNeeded()
        let center = shell.center.convert(shell.center.bounds, to: nil), placed = toast.convert(toast.bounds, to: nil)
        #expect(abs(placed.midX - center.midX) < 1 && toast.bottom?.secondItem === shell.center, "\(placed) \(center)")
        #expect(await wait { toast.bottom?.constant == -22 })
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "f11-done" + suffix, root: stage.home.root)
        }
        shell.layer.subviews.compactMap { $0 as? Toast }.forEach { $0.leave(now: true) }
        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })
    }

    /// The keys' path through show and change, with no pointer: ⌥⌘S, then Tab and ⇧Tab frame the parts in the page's
    /// order (VoiceOver hears each kind), Return picks the one framed and the composer takes the keys; Tab there frames
    /// another part and ⌥Return adds it; ⌘↵ adds the comment. Tab past the last part goes into the tray (each row's words,
    /// its ✕, which shows while it has the keys, Clear, Send) and back to pointing; once Esc stops pointing, the tray
    /// comes after the page. Show History… gives the panel the keys at once: ↓ chooses an older version, Esc closes it,
    /// even with a margin note shown, and the page has the keys again.
    @Test("Keys only: point, comment, History") func keysOnly() async throws {
        let stage = try Stage("show")
        defer { stage.remove() }
        let (shell, library, info) = stage.window()
        try stage.moment(shell)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        shell.layer.announce = { _ in }
        let window = shell.window
        func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = []) throws {
            window.sendEvent(try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                                                           context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)))
        }
        func tab(back: Bool = false) throws { try key(48, back ? "\u{19}" : "\t", back ? .shift : []) }
        /// Whether `view` has the keys: itself, or the field editor at work in it.
        func has(_ view: NSView) -> Bool {
            window.firstResponder === view || (window.firstResponder as? NSTextView).map { $0.isFieldEditor && $0.delegate === view as AnyObject } == true
        }

        shell.point()
        let overlay = try #require(brief.pointer)
        #expect(window.firstResponder === overlay && overlay.accessibilityHelp() == "Esc to stop. Tab frames the next part, Return picks it")
        try tab()
        #expect(await wait(until: { overlay.hovered != nil }))
        let first = try #require(overlay.hovered)
        #expect(overlay.accessibilityValue() as? String == first.kind)
        try tab()
        #expect(await wait(until: { overlay.hovered.map { $0.path != first.path } == true }))
        let second = try #require(overlay.hovered)
        #expect(second.path.hasPrefix(first.path), "the next part in the page's order lies in the first: \(first.path) \(second.path)")
        try tab(back: true)
        #expect(await wait(until: { overlay.hovered?.path == first.path }), "⇧Tab goes back")
        // Two quick Tabs move two parts, one each, in order.
        try tab()
        try tab()
        #expect(await wait(until: { overlay.hovered.map { $0.path != first.path && $0.path != second.path } == true }))
        let third = try #require(overlay.hovered)
        try tab(back: true)
        #expect(await wait(until: { overlay.hovered?.path == second.path }), "\(String(describing: overlay.hovered?.path)) after \(third.path)")
        try key(36, "\r")
        let composer = try #require(overlay.composer)
        #expect(overlay.picks.map(\.path) == [second.path] && window.firstResponder === composer.field)
        composer.field.insertText("Say it in one line", replacementRange: composer.field.selectedRange())
        // Tab in the composer frames another part; ⌥Return adds it, and the words wait.
        try tab()
        #expect(await wait(until: { overlay.hovered?.path == third.path }), "Tab from the composer frames the next part")
        #expect(window.firstResponder === overlay && overlay.accessibilityHelp()?.hasSuffix(". Tab frames another part, ⌥Return adds it") == true)
        try key(36, "\r", .option)
        #expect(overlay.picks.map(\.path) == [second.path, third.path] && window.firstResponder === composer.field && composer.field.string == "Say it in one line")
        #expect(composer.field.performKeyEquivalent(with: try AcceptanceShow.commandReturn(window)))
        let comments = try #require(Comments.of(brief)), tray = comments.tray
        #expect(comments.list.map(\.words) == ["Say it in one line", "Say it in one line"] && overlay.picks.isEmpty && brief.pointer === overlay)
        #expect(tray.fields.first?.accessibilityLabel() == "Comment 1 on \(second.kind)" && tray.removes.first?.alphaValue == 0)
        #expect(window.firstResponder === overlay)

        // Tab past the page's last part goes into the tray, then through it and back to pointing.
        var tabs = 0
        while !has(tray.fields[0]), tabs < 200 {
            let before = overlay.hovered?.path
            try tab()
            tabs += 1
            _ = await wait(until: { overlay.hovered?.path != before || has(tray.fields[0]) })
        }
        #expect(has(tray.fields[0]) && overlay.hovered == nil, "Tab past the last part reaches the first comment, after \(tabs) tabs")
        try tab()
        #expect(window.firstResponder === tray.removes[0] && tray.removes[0].alphaValue == 1, "the ✕ that has the keys shows")
        try tab()
        #expect(has(tray.fields[1]) && tray.removes[0].alphaValue == 0)
        try tab()
        try tab()
        #expect(window.firstResponder === tray.clear)
        try tab()
        #expect(window.firstResponder === tray.sendButton)
        try tab()
        #expect(window.firstResponder === overlay, "Send's Tab goes back to pointing")
        try tab()
        #expect(await wait(until: { overlay.hovered?.path == first.path }), "and on to the first part")
        try tab(back: true)
        #expect(await wait(until: { window.firstResponder === tray.sendButton }), "⇧Tab before the first part goes to Send")
        for _ in 1...5 { try tab(back: true) }
        #expect(has(tray.fields[0]), "⇧Tab goes back through the tray")
        try tab(back: true)
        #expect(window.firstResponder === overlay, "⇧Tab from the first comment goes back to pointing")
        window.makeFirstResponder(tray.removes[1])
        try key(49, " ")
        #expect(comments.list.count == 1, "Space on a ✕ takes its comment out")

        // Esc stops pointing: the page has the keys, and the tray comes after it.
        window.makeFirstResponder(overlay)
        #expect(shell.escape(try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))))
        #expect(brief.pointer == nil && window.firstResponder === brief.web)
        // Tab past the page's last element: WebKit asks the window for the view after the page, as here.
        #expect(brief.web.nextKeyView === tray.fields[0] && tray.sendButton.nextKeyView === brief.web)
        window.selectKeyView(following: brief.web)
        #expect(has(tray.fields[0]), "the tray comes after the page")
        try tab(back: true)
        #expect(window.firstResponder === brief.web, "and ⇧Tab goes back to it")
        tray.clear.performClick(nil)
        #expect(brief.web.nextKeyView == nil, "the tray gone, the page's keys go where they went before")

        // History, by its keys alone.
        info.clock = { Stage.local }
        info.current = { brief }
        let all = try await Self.keepVersions(of: brief, info)
        shell.showHistory()
        let panel = shell.inspector.viewController.view
        #expect((window.firstResponder as? NSView)?.isDescendant(of: panel) == true, "the panel has the keys: \(String(describing: window.firstResponder))")
        #expect(info.history.chosen == all[1].id)
        try key(125, "\u{f701}")
        #expect(info.history.chosen == all[2].id)
        try key(53, "\u{1b}")
        #expect(!shell.infoShown && window.firstResponder === brief.web, "Esc closes History and the page has the keys again")
        // With a margin note shown, the app's key monitor asks Shell.escape first: the panel with the keys still closes.
        shell.showHistory()
        let note = MarginNote.show("A note", about: second, title: "Daily brief", over: brief)
        defer { note.dismiss() }
        #expect(shell.escape(try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))))
        #expect(!shell.infoShown && brief.note != nil && window.firstResponder === brief.web, "Esc closed the panel, not the note")
    }
}
