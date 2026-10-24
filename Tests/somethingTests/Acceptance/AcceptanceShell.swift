// Acceptance scenarios of the window around the spaces: the frame, the sidebar and its groups, Info, full screen, the rail and the
// rows' eyes (b1, b3–b8; b2, La page, waits for Emi). It also draws the frame of b1 alone, with and without a toast,
// while b1 waits for W3.
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import Testing
import WebKit
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-shell-"))
struct AcceptanceShell {
    /// The frame of b1 (W1), until W2 and W3 build the rest: the mockup's sizes, the toolbar's items in order, those of
    /// a space enabled once Daily brief is open, and a toast in the window layer. b1-frame is compared with b1 for the
    /// frame and toolbar only; b1-frame-toast shows the toast, b1-frame-narrow a long title in a narrow window.
    @Test func frame() async throws {
        let stage = try Stage("shell")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        #expect(shell.window.contentView?.frame.size == Stage.Size.main)
        #expect(shell.split.splitViewItems.count == 3 && shell.inspector.isCollapsed)
        #expect(shell.window.toolbar?.items.map(\.itemIdentifier) == [.flexibleSpace, Shell.sidebar, .sidebarTrackingSeparator, Shell.title,
                                                                       .flexibleSpace, Shell.chip, Shell.tools])
        let items = shell.toolbarItems
        #expect(items.suffix(4).map(\.itemIdentifier) == [Shell.point, Shell.reload, Shell.info, Shell.full])
        let titles = Stage.templates.map(\.1) + ["Oracle"]
        #expect(Set(library.entries.map(\.title)) == Set(titles), "\(library.entries.map(\.title))")
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        #expect(shell.window.title == "Daily brief" && shell.window.subtitle == "brief.html" && library.selection == .space("brief"))
        #expect(items.filter { [Shell.reload, Shell.info].contains($0.itemIdentifier) }.allSatisfy { $0.isEnabled && !$0.isHidden })
        #expect(items.first { $0.itemIdentifier == Shell.point }?.isEnabled == false, "Point waits for T14")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "b1-frame" + suffix, root: stage.home.root)
            shell.layer.announce = { _ in }
            // The old composer goes until the sticker's slice: the mockup's toast sits over the page alone.
            shell.glass.isHidden = true
            defer { shell.glass.isHidden = false }
            let toast = shell.toast("Daily brief exported to Downloads, with its memory", action: Toast.Action(label: "Show") {}, seconds: 60)
            #expect(toast.shown && shell.window.firstResponder !== toast)
            try await Picture.window(shell, library: library, web: brief.web, "b1-frame-toast" + suffix, root: stage.home.root)
            toast.leave(now: true)
            #expect(shell.layer.isHidden)
        }
        // In a narrow window a long title gives way to the tools, cut with an ellipsis.
        shell.window.setContentSize(shell.window.contentMinSize)
        shell.heading("A morning brief with every feed I read before work", "a-morning-brief-with-every-feed.html", space: true)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "b1-frame-narrow" + suffix, root: stage.home.root)
            #expect(shell.window.contentView?.frame.width == 640)
            let full = try #require(shell.controls[Shell.full])
            #expect(full.window === shell.window && full.convert(full.bounds, to: nil).maxX <= 640 - 10 + 2)
            #expect(shell.titleLine.intrinsicContentSize.width < ceil(shell.titleLine.line.size().width) + TitleLine.indent, "cut")
        }
    }

    @Test("b1: the window", .disabled("not built yet: W3")) func b1() async throws {}
    @Test("b3: sidebar groups", .disabled("not built yet: W2")) func b3() async throws {}
    @Test("b4: Info docked full height", .disabled("not built yet: W4")) func b4() async throws {}
    @Test("b5: full screen", .disabled("not built yet: W5")) func b5() async throws {}
    @Test("b6: no space yet", .disabled("not built yet: W2")) func b6() async throws {}
    @Test("b7: the rail", .disabled("not built yet: W6")) func b7() async throws {}
    @Test("b8: rows with their eyes", .disabled("not built yet: W3")) func b8() async throws {}
}
