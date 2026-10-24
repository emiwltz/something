// Acceptance scenarios of the window around the spaces: the frame, the sidebar and its groups, Info, full screen, the rail and the
// rows' eyes (b1, b3–b8; b2, La page, waits for Emi). It also draws today's window as b1-baseline, the picture the
// interface work starts from.
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import Testing
import WebKit
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-shell-"))
struct AcceptanceShell {
    /// Today's window, before any interface slice: Daily brief open at the main size, Info hidden. The picture is the
    /// starting point every comparison with the mockup is read against.
    @Test func baseline() async throws {
        let stage = try Stage("shell")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        #expect(shell.window.contentView?.frame.size == Stage.Size.main)
        #expect(shell.split.splitViewItems.count == 3 && shell.inspector.isCollapsed)
        #expect(shell.window.toolbar?.items.map(\.itemIdentifier) ==
                [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, Shell.reload, .toggleInspector])
        let titles = Stage.templates.map(\.1) + ["Oracle"]
        #expect(Set(library.entries.map(\.title)) == Set(titles), "\(library.entries.map(\.title))")
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        #expect(shell.window.title == "Daily brief" && library.selection == "brief")
        #expect(shell.window.toolbar?.items.first { $0.itemIdentifier == Shell.reload }?.isHidden == false)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "b1-baseline" + suffix, root: stage.home.root)
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
