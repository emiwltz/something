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
    @Test("f1: pointing", .disabled("not built yet: T14")) func f1() async throws {}
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
