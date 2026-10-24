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
        #expect(items.first { $0.itemIdentifier == Shell.point }?.isEnabled == true)
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
    /// The sidebar and its groups (W2): Agents, Notes and Breaks, Breaks folded with its count, Daily brief open, the
    /// pointer over Project watch, whose "…" shows. An open menu cannot be drawn offscreen: its structure is checked by
    /// value and written beside the picture as b3-menu.txt.
    @Test("b3: sidebar groups") func b3() async throws {
        let stage = try Stage("shell-b3")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        library.preferences.groups = Stage.groups.map { Preferences.Group(name: $0.0, spaces: $0.1) }
        library.preferences.fold("Breaks", true)
        library.relist()
        try stage.moment(shell)
        shell.waiting(1, mine: 0)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        let sections = library.sections()
        #expect(sections.map(\.group) == ["Agents", "Notes", "Breaks"])
        #expect(sections.map { $0.entries.map(\.title) } == [["Daily brief", "My agents", "Project watch"], ["Logbook", "Oracle"], ["Pebble", "Stack"]])
        #expect(library.folded("Breaks") && library.label(group: "Breaks", count: 2) == "Breaks, 2 spaces, folded")
        #expect(library.label(group: "Agents", count: 3) == "Agents, 3 spaces, open")
        #expect(library.stops().contains(.space("pet")) == false, "a folded group's rows are not stops")
        let row = try #require(library.entry("project"))
        #expect(Library.label(row, Stage.moment["project"] ?? .unknown) == "Project watch, \(Sign.State.listen.word)")
        #expect(Template.symbol(of: "brief") != Template.symbol(of: "oracle") && Template.symbol(of: "oracle") == "doc")
        let menu = SidebarMenu.text(library.menu(for: row))
        #expect(menu == ["Open", "Show Info  ⌘I", "Rename…", "Show in Group  ▸", "  Agents  ✓  (dimmed)", "  Notes", "  Breaks", "  —",
                         "  New Group…", "  (Groups are only in the sidebar. The file does not move.)", "—", "Show in Finder", "Export…", "—",
                         "Move to Trash…  (red)"])
        if let gallery {
            try FileManager.default.createDirectory(at: gallery, withIntermediateDirectories: true)
            try (menu.joined(separator: "\n") + "\n").write(to: gallery.appendingPathComponent("b3-menu.txt"), atomically: true, encoding: .utf8)
        }
        // Vision may read a row's symbol as a letter before its title ("• Oracle"): a line contains the title.
        let drawn = try stage.drawn(shell)
        for line in ["Agents", "Notes", "Breaks", "Daily brief", "Project watch", "Oracle"] {
            #expect(drawn.contains { $0.contains(line) }, "the drawn sidebar shows \(line): \(drawn)")
        }
        #expect(!drawn.contains { $0.contains("Pebble") || $0.contains("Stack") }, "a folded group's rows are not drawn: \(drawn)")
        library.sidebar.hovered = .space("project")
        library.sidebar.menuOpened()
        #expect(library.sidebar.menued == .space("project"), "the row its menu opened on stays lit and ringed")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "b3" + suffix, root: stage.home.root)
        }
        // Show in Group ▸ Notes writes only the preferences; the file stays in the flat spaces folder.
        if case let .submenu(_, _, picks) = library.menu(for: row)[3], case let .item(_, _, _, _, _, _, run) = picks[1] { run() }
        #expect(library.preferences.group(of: "project") == "Notes")
        #expect(FileManager.default.fileExists(atPath: stage.home.places.spaces.appendingPathComponent("project.html").path))
        // Rename… of the open space: the toolbar and the window's title follow the name shown in the sidebar.
        library.rename("brief", to: "Morning paper")
        #expect(shell.window.title == "Morning paper" && shell.titleLine.line.string.hasPrefix("Morning paper"))
        library.rename("oracle", to: "Seer")
        #expect(shell.window.title == "Morning paper", "another space's name leaves the toolbar alone")
    }
    @Test("b4: Info docked full height", .disabled("not built yet: W4")) func b4() async throws {}
    @Test("b5: full screen", .disabled("not built yet: W5")) func b5() async throws {}
    /// No space yet (W2, the center AB12's): the sidebar says only where the spaces will be, New Space selected.
    @Test("b6: no space yet") func b6() async throws {
        let stage = try Stage("shell-b6")
        defer { stage.remove() }
        for file in try FileManager.default.contentsOfDirectory(at: stage.home.places.spaces, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: file)
        }
        let (shell, library, _) = stage.window()
        library.preferences.groups = Stage.groups.map { Preferences.Group(name: $0.0, spaces: []) }
        #expect(library.entries.isEmpty && library.selection == .newSpace)
        #expect(library.stops() == [.newSpace], "no header shows while no space is listed")
        #expect(library.sections().allSatisfy { $0.entries.isEmpty } && !shell.assistant.building, "the list says \(SidebarView.empty)")
        let drawn = try stage.drawn(shell)
        #expect(drawn.contains { $0.contains("Your spaces appear here") }, "the drawn sidebar says where the spaces will be: \(drawn)")
        #expect(!drawn.contains { ["Agents", "Notes", "Breaks"].contains(where: $0.contains) }, "no group header is drawn: \(drawn)")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "b6" + suffix, root: stage.home.root)
        }
    }

    @Test("b7: the rail", .disabled("not built yet: W6")) func b7() async throws {}
    @Test("b8: rows with their eyes", .disabled("not built yet: W3")) func b8() async throws {}
}
