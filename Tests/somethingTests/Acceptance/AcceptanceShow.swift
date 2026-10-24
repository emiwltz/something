// Acceptance scenarios of show and change: pointing, picked frames, the margin note, the toast, History, the glimpse and
// the comments (f1–f11; f9–f11 wait for their shots).
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import Testing
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-show-"))
struct AcceptanceShow {
    /// Daily brief open, its card folded to the sticker; ⌥⌘S starts point mode: Point pressed in the toolbar, the space
    /// dimmed but for the part under the pointer, the sign's corners around it with its kind, and the banner saying
    /// the mode and Esc. The card's Point is greyed only when there is nothing to point at.
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
        shell.point()
        #expect(brief.pointer == nil)
    }
    @Test("f2: picked frames and the composer", .disabled("not built yet: T15")) func f2() async throws {}
    @Test("f3: a frame at work", .disabled("not built yet: T16")) func f3() async throws {}
    @Test("f4: the margin note", .disabled("not built yet: T17")) func f4() async throws {}
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
