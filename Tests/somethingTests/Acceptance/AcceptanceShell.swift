// Acceptance scenarios of the window around the spaces: the frame, the sidebar and its groups, full screen (b1, b3, b5,
// b6; b8, the rows' eyes, left with v6.2), the word "space" explained (x1-2), Info in three parts (x5-1 to x5-3, which
// retired b4), round 2's calm window: the toolbar and Needs You (x9-1), Page Full Screen (2-6) and ⌘K in it (2-8), and
// round 4's sidebar: by the edge or ⌃⌘S (r4-2), the pin (r4-3), night (r4-4). It also draws the frame of
// b1 alone, with and without a toast, and a long name in a narrow window.
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
@testable import SomethingAgents
import SomethingCore
import SwiftUI
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
        #expect(shell.split.splitViewItems.count == 2 && shell.inspector.isCollapsed)
        #expect(shell.window.toolbar?.items.map(\.itemIdentifier) == [Shell.sidebar, Shell.title, .flexibleSpace, Shell.tools])
        let items = shell.toolbarItems
        #expect(items.suffix(3).map(\.itemIdentifier) == [Shell.point, Shell.info, Shell.full])
        let titles = Stage.templates.map(\.1) + ["Oracle"]
        #expect(Set(library.entries.map(\.title)) == Set(titles), "\(library.entries.map(\.title))")
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        #expect(shell.window.title == "Daily brief" && shell.window.subtitle == "" && library.selection == .space("brief"))
        #expect(items.first { $0.itemIdentifier == Shell.info }?.isEnabled == true && shell.controls[Shell.info]?.isHidden == false)
        #expect(items.first { $0.itemIdentifier == Shell.point }?.isEnabled == true)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "b1-frame" + suffix, root: stage.home.root)
            shell.layer.announce = { _ in }
            // The old composer goes until the sticker's slice: the mockup's toast sits over the page alone.
            shell.glass.isHidden = true
            defer { shell.glass.isHidden = false }
            let toast = shell.toast("brief.something is in Downloads", action: Toast.Action(label: "Show") {}, seconds: 60)
            #expect(toast.shown && shell.window.firstResponder !== toast)
            try await Picture.window(shell, library: library, web: brief.web, "b1-frame-toast" + suffix, root: stage.home.root)
            toast.leave(now: true)
            #expect(shell.layer.isHidden)
        }
        // In a narrow window a long name gives way to the tools, cut with an ellipsis.
        shell.window.setContentSize(shell.window.contentMinSize)
        shell.heading("A morning brief with every feed, newsletter and calendar I read before work starts", "", space: true)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "b1-frame-narrow" + suffix, root: stage.home.root)
            #expect(shell.window.contentView?.frame.width == 640)
            let full = try #require(shell.controls[Shell.full])
            #expect(full.window === shell.window && full.convert(full.bounds, to: nil).maxX <= 640 - 10 + 2)
            #expect(shell.titleLine.intrinsicContentSize.width < ceil(shell.titleLine.line.size().width) + TitleLine.indent, "cut")
        }
    }

    /// Gives the rows of `shell` the eyes of `states`, as the sessions would; a space it does not name is asleep.
    static func eyes(_ shell: Shell, _ states: [String: Sign.State]) throws {
        let host = shell.drawer.host
        host.rootView = SidebarView(library: host.rootView.library, assistant: host.rootView.assistant, eyes: { states[$0] ?? .sleep })
    }

    /// The window of every day (W1–W3), as v6.2 left it (S5): the groups open, each row a name whose VoiceOver label
    /// says its assistant's state at the mockup's moment, Daily brief open, My agents' request in Needs You. Go lists
    /// the spaces with their eyes and words; a folded group shows no eyes.
    @Test("b1: the window") func b1() async throws {
        let stage = try Stage("shell-b1")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        library.preferences.groups = Stage.groups.map { Preferences.Group(name: $0.0, spaces: $0.1) }
        library.relist()
        try Self.eyes(shell, Stage.moment)
        shell.waiting(["agents"], mine: 0)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        #expect(library.needing().map(\.title) == ["My agents"])
        #expect(library.sections().allSatisfy { $0.group.map(library.folded) == false })
        let labels = library.order().map { Library.label($0, Stage.moment[$0.id] ?? .unknown) }
        #expect(labels == ["Daily brief, Working", "My agents, Waiting for You", "Project watch, Idle", "Logbook, Asleep", "Oracle, Idle",
                           "Pebble, Idle", "Stack, Asleep"], "\(labels)")
        let drawn = try await stage.drawn(shell)
        // Vision may read the f of "brief" as a t beside "pages of your own": the title's start is enough.
        for line in ["Needs You", "Work", "Notes", "Breaks", "Daily bri", "Pebble", "Stack", "Templates"] {
            #expect(drawn.contains { $0.contains(line) }, "the drawn sidebar shows \(line): \(drawn)")
        }
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "b1" + suffix, root: stage.home.root)
        }
        // Go, with the same eyes and words: still images, as a menu cannot animate.
        let bar = MenuBar(builders: nil)
        bar.spaces = { library.order().filter(\.isSpace).map { ($0.id, $0.title) } }
        bar.open = { ("brief", "Daily brief") }
        bar.eyes = { Stage.moment[$0] ?? .unknown }
        bar.refresh()
        let go = try #require(bar.submenu("Go")).items.filter { $0.identifier?.rawValue.hasPrefix("space:") == true }
        #expect(go.map { $0.attributedTitle?.string ?? "" } == labels.map { $0.replacingOccurrences(of: ", ", with: "\t") })
        #expect(go.allSatisfy { $0.image?.isTemplate == true } && go.filter { $0.state == .on }.map(\.title) == ["Daily brief"])
        if let gallery {
            let lines = go.map { "\($0.state == .on ? "✓ " : "")[eyes] \($0.attributedTitle?.string.replacingOccurrences(of: "\t", with: "  ") ?? "")  ⌘\($0.keyEquivalent)" }
            try (lines.joined(separator: "\n") + "\n").write(to: gallery.appendingPathComponent("g9-go.txt"), atomically: true, encoding: .utf8)
        }
        // Folded, Work hides its rows, My agents too, which Needs You still lists.
        library.preferences.fold("Work", true)
        #expect(library.label(group: "Work", count: 3) == "Work, 3 spaces, folded")
        let folded = try await stage.drawn(shell)
        #expect(folded.filter { $0.contains("My agents") }.count == 1 && !folded.contains { $0.contains("Project watch") }, "\(folded)")
        library.preferences.fold("Work", false)
    }
    /// The sidebar and its groups (W2): Work, Notes and Breaks, Breaks folded with its count, Daily brief open, the
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
        shell.waiting(["agents"], mine: 0)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        let sections = library.sections()
        #expect(sections.map(\.group) == ["Work", "Notes", "Breaks"])
        #expect(sections.map { $0.entries.map(\.title) } == [["Daily brief", "My agents", "Project watch"], ["Logbook", "Oracle"], ["Pebble", "Stack"]])
        #expect(library.folded("Breaks") && library.label(group: "Breaks", count: 2) == "Breaks, 2 spaces, folded")
        #expect(library.label(group: "Work", count: 3) == "Work, 3 spaces, open")
        #expect(library.stops().contains(.space("pet")) == false, "a folded group's rows are not stops")
        let row = try #require(library.entry("project"))
        #expect(Library.label(row, Stage.moment["project"] ?? .unknown) == "Project watch, \(Sign.State.listen.word)")
        let menu = SidebarMenu.text(library.menu(for: row))
        #expect(menu == ["Open", "Show Agents  ⌘I", "Rename…", "Show in Group  ▸", "  Work  ✓  (dimmed)", "  Notes", "  Breaks", "  —",
                         "  New Group…", "  (Groups are only in the sidebar. The file does not move.)", "—", "Show in Finder", "Export…", "—",
                         "Move to Trash…  (red)"])
        if let gallery {
            try FileManager.default.createDirectory(at: gallery, withIntermediateDirectories: true)
            try (menu.joined(separator: "\n") + "\n").write(to: gallery.appendingPathComponent("b3-menu.txt"), atomically: true, encoding: .utf8)
        }
        let drawn = try await stage.drawn(shell)
        for line in ["Work", "Notes", "Breaks", "Daily bri", "Project watch", "Oracle"] {
            #expect(drawn.contains { $0.contains(line) }, "the drawn sidebar shows \(line): \(drawn)")
        }
        #expect(!drawn.contains { $0.contains("Pebble") || $0.contains("Stack") }, "a folded group's rows are not drawn: \(drawn)")
        let seen = try await Picture.lines(try stage.sidebar(shell))
        let breaks = try #require(seen.first { $0.words == "Breaks" }?.box, "\(seen.map(\.words))")
        #expect(seen.contains { $0.words == "2" && abs($0.box.midY - breaks.midY) < 4 }, "a folded group keeps its count at rest")
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
    /// Full screen (W5): the system hides the toolbar with the menu bar; the sidebar has no room there and the space
    /// starts at the window's top; ⌃⌘S lays the sidebar over the space, and Esc, ⌃⌘S again or a space picked takes it
    /// away. A window never shown cannot enter a real full screen: the layout comes from its flag, and the pictures
    /// leave out the toolbar and the lights the system hides (the hand trial checks a real one). b5-sidebar is the
    /// sidebar laid over, which the mockup's screen shows only once ⌃⌘S is pressed.
    @Test("b5: full screen") func b5() async throws {
        let stage = try Stage("shell-b5")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        let options = shell.window(shell.window, willUseFullScreenPresentationOptions: [])
        #expect(options.isSuperset(of: [.fullScreen, .autoHideToolbar, .autoHideMenuBar]) && shell.window.collectionBehavior.contains(.fullScreenPrimary))
        let command = try #require(Keys.command("full"))
        #expect(command.action == #selector(NSWindow.toggleFullScreen(_:)) && command.key == "f" && command.modifiers == [.command, .control])
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        let drawer = shell.drawer, height = Stage.Size.main.height
        func top() -> CGFloat? { shell.shown.map { $0.convert($0.bounds, to: nil).maxY } }
        shell.window.layoutIfNeeded()
        #expect(top() == shell.window.contentLayoutRect.maxY && shell.window.contentLayoutRect.maxY < height, "under the toolbar")
        shell.keepSidebar()
        shell.fullScreen(true)
        shell.window.layoutIfNeeded()
        #expect(shell.full && !drawer.state.dock && !drawer.state.shown && shell.column.constant == 0 && shell.space === brief, "no room: the pin waits")
        #expect(top() == height && brief.web.frame.width == Stage.Size.main.width, "the space alone, from the window's top")
        // The toolbar's last button stays Page Full Screen, the sticker discreet.
        #expect(shell.controls[Shell.full]?.image?.accessibilityDescription == "Page Full Screen" && shell.glass.discreet)
        // ⌃⌘S lays the sidebar over the space, 10 points from the window's top; it takes the keys, and gives them back.
        shell.window.makeFirstResponder(brief.web)
        drawer.toggle()
        drawer.layoutSubtreeIfNeeded()
        #expect(await wait(until: { drawer.card.minX == Drawer.margin }), "\(drawer.card)")
        #expect(drawer.state.peek && shell.column.constant == 0 && drawer.card == NSRect(x: 10, y: 10, width: 250, height: height - 20), "\(drawer.card)")
        #expect(drawer.accessibilityLabel() == "Sidebar" && shell.window.firstResponder === drawer.host)
        #expect(shell.chrome.hitTest(NSPoint(x: 600, y: 300)) == nil, "the page keeps its clicks")
        let escape = try Self.escape(shell)
        #expect(shell.escape(escape) && !drawer.state.peek && shell.window.firstResponder === brief.web, "Esc")
        drawer.toggle()
        drawer.toggle()
        #expect(!drawer.state.peek, "⌃⌘S again")
        drawer.toggle()
        shell.show(brief)
        #expect(!drawer.state.peek, "a space picked")
        shell.window.toolbar?.isVisible = false
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { shell.window.standardWindowButton($0)?.isHidden = true }
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "b5" + suffix, root: stage.home.root, keyed: false)
            drawer.toggle()
            #expect(await wait(until: { drawer.card.minX == Drawer.margin }))
            try await Picture.window(shell, library: library, web: brief.web, "b5-sidebar" + suffix, root: stage.home.root, keyed: false)
            drawer.close()
        }
        shell.window.toolbar?.isVisible = true
        // Out of full screen, a pinned sidebar docks again, the space under the toolbar.
        shell.fullScreen(false)
        shell.window.layoutIfNeeded()
        #expect(!shell.full && drawer.state.dock && shell.column.constant == 270 && top() == shell.window.contentLayoutRect.maxY && !shell.glass.discreet)
        shell.keepSidebar()
        shell.fullScreen(true)
        shell.fullScreen(false)
        #expect(!drawer.state.shown, "a floating sidebar stays away")
    }
    /// No space yet (W2, the center AB12's): the sidebar stays open beside New Space, 10 points from the window's edges,
    /// and says only where the spaces will be.
    @Test("b6: no space yet") func b6() async throws {
        let stage = try Stage("shell-b6")
        defer { stage.remove() }
        for file in try FileManager.default.contentsOfDirectory(at: stage.home.places.spaces, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: file)
        }
        // The mockup's newcomer has an agent to build with: the suggestions are live, in their normal ink.
        let bin = stage.home.root.appendingPathComponent("bin"), claude = bin.appendingPathComponent("claude")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try AssistantTests.fake.write(to: claude, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
        let (shell, library, _) = stage.window()
        let model = shell.assistant
        model.engine.changed = { model.refresh() }
        model.engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        library.preferences.groups = Stage.groups.map { Preferences.Group(name: $0.0, spaces: []) }
        #expect(library.entries.isEmpty && library.selection == .newSpace)
        #expect(library.stops() == [.newSpace], "no header shows while no space is listed")
        #expect(library.sections().allSatisfy { $0.entries.isEmpty } && !shell.assistant.building, "the list says \(SidebarView.empty)")
        let drawn = try await stage.drawn(shell)
        let said = await AcceptanceBuild.read(shell.drawer.host, whole: true) { $0.contains("Your spaces appear here") }
        #expect(said.contains("Your spaces appear here"), "the sidebar says where the spaces will be: \(said)")
        #expect(!drawn.contains { ["Work", "Notes", "Breaks"].contains(where: $0.contains) }, "no group header is drawn: \(drawn)")
        #expect(shell.drawer.state.dock && shell.column.constant == Drawer.column, "held open, the page beside it")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "b6" + suffix, root: stage.home.root)
        }
    }

    /// The mockup's window for round 2 (X9.1): its groups (Work, Notes, Breaks), Daily brief open, My
    /// agents waiting for the answer to its request, the rows' states at the mockup's moment.
    static func calm(_ stage: Stage) async throws -> (Shell, Library, SpaceView) {
        let (shell, library, _) = stage.window()
        Stage.work(library)
        try Self.eyes(shell, Stage.moment)
        shell.waiting(["agents"], mine: 0)
        let brief = try await stage.open("brief", in: shell, library)
        return (shell, library, brief)
    }

    /// The calm toolbar (S5, X9.1): the name alone, then Point, Info and Page Full Screen; no Reload, no waiting chip.
    /// A click on the name opens Info, its button pressed, and closes it. What waits is in the sidebar's Needs You,
    /// above the groups, My agents still in Work; the View menu says what its items will do and holds Reload. The open
    /// View menu cannot be drawn offscreen: its lines are written beside the picture as x9-1-view.txt.
    @Test("x9-1: the calm toolbar") func x9_1() async throws {
        let stage = try Stage("shell-x9-1")
        defer { stage.remove() }
        let (shell, library, brief) = try await Self.calm(stage)
        defer { brief.close() }
        #expect(shell.window.toolbar?.items.map(\.itemIdentifier) == [Shell.sidebar, Shell.title, .flexibleSpace, Shell.tools])
        #expect(shell.toolbarItems.suffix(3).map(\.itemIdentifier) == [Shell.point, Shell.info, Shell.full])
        #expect(shell.toolbarItems.allSatisfy { !["reload", "chip"].contains($0.itemIdentifier.rawValue) })
        let title = shell.titleLine
        #expect(title.line.string == "Daily brief" && shell.window.subtitle == "" && title.accessibilityLabel() == "Daily brief")
        #expect(title.accessibilityRole() == .button && title.toolTip == "Show Info")
        let labels = [Shell.point, Shell.info, Shell.full].map { shell.controls[$0]?.image?.accessibilityDescription }
        #expect(labels == ["Point", "Info", "Page Full Screen"], "\(labels)")
        // The name opens Info, as ⌘I: the button pressed, View's item says Hide Info; again, it closes.
        #expect(shell.infoWords == "Show Agents" && title.accessibilityPerformPress())
        #expect(shell.infoShown && (shell.controls[Shell.info] as? ToolButton)?.pressed == true && shell.infoWords == "Hide Agents")
        #expect(title.accessibilityPerformPress() && !shell.infoShown && (shell.controls[Shell.info] as? ToolButton)?.pressed == false)
        // Needs You, then the groups; My agents in both, so ⌘1–9 keep the groups' order.
        #expect(library.needing().map(\.title) == ["My agents"] && library.sections().map(\.group) == ["Work", "Notes", "Breaks"])
        #expect(library.order().map(\.title) == ["Daily brief", "My agents", "Project watch", "Logbook", "Oracle", "Pebble", "Stack"])
        shell.drawer.open()
        let host = shell.drawer.host
        let read = await AcceptanceBuild.read(host) { $0.contains("Needs You, 1 space") && $0.contains("Stack, Asleep") }
        let rows = read.filter { $0.contains(", ") && !$0.lowercased().contains("space") }
        #expect(rows == ["My agents, Waiting for You", "Daily brief, Working", "My agents, Waiting for You", "Project watch, Idle",
                         "Logbook, Asleep", "Oracle, Idle", "Pebble, Idle", "Stack, Asleep"], "\(read)")
        #expect(read.contains("Needs You, 1 space") && read.contains("Work, 3 spaces, open") && read.contains("Settings"), "\(read)")
        let drawn = try await stage.drawn(shell)
        for line in ["Needs You", "Work", "Daily brief", "Project watch", "Templates", "something"] {
            #expect(drawn.contains { $0.contains(line) }, "the drawn sidebar shows \(line): \(drawn)")
        }
        #expect(drawn.filter { $0.contains("My agents") }.count == 2, "\(drawn)")
        // The View menu, Daily brief open, the sidebar shown: each item says what it does; Reload is here only.
        let bar = MenuBar(builders: nil)
        let view = try #require(bar.submenu("View")), space = try #require(bar.submenu("Space"))
        let sidebar = try #require(view.items.first { $0.identifier?.rawValue == "sidebar" })
        shell.retitle(sidebar)
        #expect(sidebar.title == "Hide Sidebar")
        // The Info items, in View and Space, are named as the app's validation names them: Show, then Hide while Info shows.
        let infos = [view, space].compactMap { menu in menu.items.first { $0.identifier?.rawValue == "insp" } }
        #expect(infos.count == 2)
        shell.showInfo(true)
        infos.forEach(shell.retitle)
        #expect(infos.allSatisfy { $0.title == "Hide Agents" }, "\(infos.map(\.title))")
        shell.showInfo(false)
        infos.forEach(shell.retitle)
        let lines = Mockup.lines(view)
        #expect(lines == ["Hide Sidebar  ⌃⌘S", "Keep Sidebar Open", "Show Agents  ⌘I", "---", "Show History…", "Show Keyboard Shortcuts  ⌘/", "---", "Reload Space  ⌘R", "---",
                          "# Interface Size · Default", "Make Interface Bigger  ⌘+", "Make Interface Smaller  ⌘−", "Default Size  ⌘0", "---",
                          "Enter Page Full Screen  ⇧⌘F", "Enter Full Screen  ⌃⌘F"], "\(lines)")
        #expect(!space.items.contains { $0.identifier?.rawValue == "reload" }, "Reload lives in View only")
        if let gallery {
            try FileManager.default.createDirectory(at: gallery, withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n").write(to: gallery.appendingPathComponent("x9-1-view.txt"), atomically: true, encoding: .utf8)
        }
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "x9-1" + suffix, root: stage.home.root)
        }
        // Hidden, the sidebar's item says Show Sidebar; the request answered, Needs You goes.
        shell.drawer.close()
        shell.retitle(sidebar)
        #expect(sidebar.title == "Show Sidebar")
        shell.drawer.open()
        shell.waiting([], mine: 0)
        #expect(library.needing().isEmpty)
        let after = await AcceptanceBuild.read(host) { !$0.contains("Needs You, 1 space") && $0.contains("Stack, Asleep") }
        #expect(!after.contains("Needs You, 1 space"), "\(after)")
    }

    /// Talking to an agent in full from a page (S8, J4.2; the page's look S14a): My agents, its Claude Code in pacman
    /// launched by the space, listing its own commands, three sub-agents, its model, effort and mode. Write to It opens
    /// its conversation in place: the chips say Sonnet 5.5 · Medium and Ask; "/" (typed, or its button) opens its
    /// commands as it lists them, ↓ chooses, ↩ puts "/plan " in the box and says what the command does over it; the
    /// helpers line says which sub-agents work; Send Now and After This Turn, since it works. The picture shows "/goal"
    /// and its argument typed, as the mockup does. something only passes "/plan …" on as the agent's own command.
    @Test("j4-2: talk to an agent, in full") func j4_2() async throws {
        let stage = try Stage("shell-j4-2")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        Stage.work(library)
        try Self.eyes(shell, Stage.moment)
        let board = try await stage.open("agents", in: shell, library)
        defer { board.close() }
        #expect(board.granted.rights.contains("send"), "\(board.granted.rights)")
        board.engine.update(outside: Self.inFull)
        board.push()   // the app's timer pushes four times a second; no timer runs here
        let card = #"document.querySelector('.agent[data-id="claude-pacman"]')"#
        func run(_ script: String) async throws -> [String: Any] {
            try #require(try await board.web.callAsyncJavaScript("const card = \(card), box = card && card.querySelector('textarea'); \(script)",
                                                                  in: try #require(board.frame), contentWorld: .defaultClient) as? [String: Any])
        }
        var ready = false
        for _ in 0..<100 where !ready {
            ready = (try? await run("return { ok: !!card && !card.querySelector('.acts').hidden };"))?["ok"] as? Bool == true
            if !ready { _ = await wait(0.05) }
        }
        #expect(ready, "pacman's Write to It shows once the space may write to it")
        // The board as the mockup counts it, and the cards the space may not write to say why, with no button.
        let counted = try await run("""
            card.querySelector('.write').click();
            return { counts: [...document.querySelectorAll('.count')].map((c) => [...c.children].map((n) => n.textContent).join(' ')),
                     first: document.querySelector('#board').firstElementChild.dataset.id, open: card.classList.contains('open'),
                     chips: [...card.querySelectorAll('.chips select')].map((s) => s.selectedOptions[0].textContent),
                     labels: [...card.querySelectorAll('.chips select')].map((s) => s.getAttribute('aria-label')),
                     waits: document.querySelector('.agent[data-id="claude-shop"] .pill').textContent,
                     waitsWrite: document.querySelector('.agent[data-id="claude-shop"] .acts').hidden,
                     thread: [...card.querySelectorAll('.thread li')].map((li) => li.className),
                     buttons: [...card.querySelectorAll('form button')].filter((b) => !b.hidden).map((b) => b.getAttribute('aria-label') || b.textContent) };
            """)
        #expect(counted["counts"] as? [String] == ["1 waiting for you", "2 working", "1 idle", "1 unknown"], "\(counted)")
        #expect(counted["first"] as? String == "claude-pacman" && counted["open"] as? Bool == true, "\(counted)")
        #expect(counted["chips"] as? [String] == ["Sonnet 5.5", "Medium", "Ask"] && counted["labels"] as? [String] == ["Model", "Effort", "Mode"], "\(counted)")
        #expect(counted["waits"] as? String == "waits 34 min" && counted["waitsWrite"] as? Bool == true, "\(counted)")
        #expect(counted["thread"] as? [String] == ["you", "it", "you", "step"], "\(counted)")
        #expect(counted["buttons"] as? [String] == ["Its commands", "Send Now", "After This Turn"], "\(counted)")
        let read = """
            const menu = card.querySelector(".cmds"), hint = card.querySelector(".hint");
            return { hidden: menu.hidden, label: menu.getAttribute("aria-label"), role: menu.getAttribute("role"), box: box.value,
                     names: [...menu.querySelectorAll("li b")].map((b) => b.textContent), roles: [...menu.children].map((li) => li.getAttribute("role")),
                     chosen: [...menu.children].findIndex((li) => li.getAttribute("aria-selected") === "true"), place: box.placeholder,
                     helpers: card.querySelector(".helpers summary").textContent, expanded: box.getAttribute("aria-expanded"),
                     active: box.getAttribute("aria-activedescendant"), chosenID: menu.querySelector("[aria-selected=true]")?.id ?? null,
                     controls: box.getAttribute("aria-controls") === menu.id, hint: hint.hidden ? null : hint.textContent };
            """
        func key(_ name: String) -> String { #"box.dispatchEvent(new KeyboardEvent("keydown", { key: "\#(name)", bubbles: true, cancelable: true }));"# }
        let type = #"box.focus(); box.value = "/"; box.dispatchEvent(new Event("input"));"#
        var seen = try await run(#"card.querySelector(".slash").click();"# + read)
        #expect(seen["hidden"] as? Bool == false && seen["label"] as? String == "Claude Code's commands" && seen["role"] as? String == "listbox", "\(seen)")
        #expect(seen["names"] as? [String] == ["/goal", "/plan", "/review", "/agents", "/compact"] && seen["chosen"] as? Int == 0, "\(seen)")
        #expect((seen["roles"] as? [String])?.allSatisfy { $0 == "option" } == true)
        #expect(seen["place"] as? String == "Write to Claude Code…")
        #expect(seen["helpers"] as? String == "Its helpers2 sub-agents at work · 1 finished", "\(seen)")
        seen = try await run(#"box.value = "/re"; box.dispatchEvent(new Event("input"));"# + read)
        #expect(seen["names"] as? [String] == ["/review"])
        seen = try await run(type + key("ArrowDown") + read)
        #expect(seen["chosen"] as? Int == 1 && seen["expanded"] as? String == "true" && seen["controls"] as? Bool == true, "\(seen)")
        #expect(seen["active"] as? String != nil && seen["active"] as? String == seen["chosenID"] as? String, "\(seen)")
        seen = try await run(key("Enter") + read)
        #expect(seen["box"] as? String == "/plan " && seen["hidden"] as? Bool == true && seen["expanded"] as? String == "false", "\(seen)")
        #expect(seen["hint"] as? String == "/planIt proposes before it touches a file", "\(seen)")
        // Esc closes the menu, and a text that is no command's name shows none.
        seen = try await run(type + key("Escape") + read)
        #expect(seen["hidden"] as? Bool == true)
        seen = try await run(#"box.value = "/deploy"; box.dispatchEvent(new Event("input"));"# + read)
        #expect(seen["hidden"] as? Bool == true && seen["hint"] is NSNull)
        // As the mockup draws it: a command chosen, its argument typed, the helpers at work in view.
        seen = try await run(#"box.value = "/goal Each ghost chases its own way, and the tests pass"; box.dispatchEvent(new Event("input"));"# + read)
        #expect(seen["hidden"] as? Bool == true && seen["hint"] as? String == "/goalA goal it keeps working toward, checking as it goes", "\(seen)")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: board.web, "j4-2" + suffix, root: stage.home.root)
        }
        // And "/" alone, its commands open as the agent lists them: the step's point.
        seen = try await run(type + read)
        #expect(seen["hidden"] as? Bool == false)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: board.web, "j4-2-list" + suffix, root: stage.home.root)
        }
    }

    /// The mockup's agents, Claude Code in pacman launched by My agents, with its own commands, its sub-agents, and
    /// its model, effort and mode as its driver offers them.
    static var inFull: (agents: [Agent], threads: [AgentThread]) {
        var world = Stage.world(of: "agents")
        guard let index = world.agents.firstIndex(where: { $0.id == "claude-pacman" }) else { return world }
        world.agents[index].origin = "launched"
        (world.agents[index].can.send, world.agents[index].can.steer, world.agents[index].can.queue, world.agents[index].can.interrupt) = (true, true, true, true)
        (world.agents[index].can.model, world.agents[index].can.mode, world.agents[index].can.effort) = (true, true, true)
        world.agents[index].because = [:]
        (world.agents[index].model, world.agents[index].effort, world.agents[index].mode) = ("sonnet", "medium", "default")
        world.agents[index].options.model = [Option(value: "sonnet", label: "Sonnet 5.5"), Option(value: "opus", label: "Opus 5.5")]
        world.agents[index].options.effort = [Option(value: "medium", label: "Medium"), Option(value: "high", label: "High")]
        world.agents[index].options.mode = [Option(value: "default", label: "Ask"), Option(value: "plan", label: "Plan"),
                                            Option(value: "acceptEdits", label: "Accept Edits")]
        world.agents[index].commands = [("goal", "A goal it keeps working toward, checking as it goes"), ("plan", "It proposes before it touches a file"),
                                        ("review", "Reads the recent changes and comments on them"), ("agents", "See its helpers, or ask it to start one"),
                                        ("compact", "Shortens the conversation, keeps the gist")].map { Option(value: $0, label: $1) }
        world.agents[index].subagents = [Tool(name: "Explore: read the ghost files", status: "done"), Tool(name: "Writer: chase for Blinky", status: "running"),
                                         Tool(name: "Writer: chase for Pinky", status: "running")]
        // Claude Code in portfolio, launched by the space too: Write to It, as the mockup draws it at Run.
        if let other = world.agents.firstIndex(where: { $0.id == "claude-portfolio" }) {
            (world.agents[other].origin, world.agents[other].can.send, world.agents[other].because) = ("launched", true, [:])
        }
        return world
    }

    /// X1.2, the words: "Space" stays, explained once where every space is listed, "pages of your own" beside SPACES;
    /// New Space says where a space is built, and its level row starts at None, pre-set from the words.
    @Test("x1-2: a space, a page of your own") func x1_2() async throws {
        let stage = try Stage("shell-x1-2")
        defer { stage.remove() }
        let (shell, library, host) = try await AcceptanceBuild.newSpace(stage, builder: true)
        Stage.work(library)
        let model = shell.assistant
        #expect(String(BlankView.where(model.folder).characters) == "Describe it in your words. Your assistant builds it in \u{2009}~/something/spaces\u{2009}.")
        #expect(model.level == .none && model.chosenLevel == nil)
        let drawn = try await stage.drawn(shell)
        #expect(drawn.contains { $0.contains("pages of your own") }, "the drawn sidebar explains the word: \(drawn)")
        let said = await AcceptanceBuild.read(shell.drawer.host) { $0.contains("Spaces, pages of your own") }
        #expect(said.contains("Spaces, pages of your own"), "\(said)")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "x1-2" + suffix, root: stage.home.root)
            let words = await AcceptanceBuild.read(host) { $0 == AcceptanceBuild.newSpaceWords() }
            #expect(words == AcceptanceBuild.newSpaceWords(), "\(words)")
        }
    }

    // MARK: Info (X5)

    /// Week-end, an invented page (X5's): a countdown, its plans, and the agents it sees; a page that watches.
    static let weekendPage = """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><title>Week-end</title>
        <script type="application/json" id="something">{"contract": 1, "title": "Week-end", "agents": {"see": "all"}, "rights": ["state", "store"],
          "description": "A countdown to Saturday, your plans, and what your agents still have to finish."}</script>
        <style>
          body { margin: 0; min-height: 100vh; box-sizing: border-box; padding: 56px 64px; color: #fff; font: 14px -apple-system, sans-serif;
                 background: radial-gradient(circle at 50% 108%, #ffe0a3 0, #f6b27c 22%, transparent 48%),
                             linear-gradient(180deg, #2b3363 0%, #5f4a86 38%, #c27587 66%, #f2a676 100%); }
          small { display: block; letter-spacing: .18em; font-size: 11px; font-weight: 600; opacity: .85; }
          .count { display: flex; gap: 22px; margin: 18px 0 0; }
          .count b { display: block; font: 400 88px/1 Georgia, serif; letter-spacing: -.03em; font-variant-numeric: lining-nums; }
          .count span { font-size: 13px; opacity: .85; }
          h2 { font: 600 22px Georgia, serif; margin: 30px 0 34px; }
          .cards { display: flex; gap: 18px; align-items: flex-start; }
          .card { box-sizing: border-box; flex: 1 1 0; max-width: 270px; padding: 20px; border-radius: 14px; background: rgba(255, 255, 255, .92); color: #3a2b45; }
          .card.dark { max-width: 230px; background: rgba(60, 40, 80, .5); color: #fff; }
          .card p { margin: 12px 0 0; line-height: 1.45; }
          .plans p { font: 600 18px/1.35 Georgia, serif; padding-bottom: 14px; border-bottom: 1px dashed rgba(58, 43, 69, .3); }
          .plans i { display: block; margin-top: 12px; font-style: normal; opacity: .5; }
        </style></head><body>
        <small>UNTIL THE WEEKEND</small>
        <div class="count"><div><b>1</b><span>day</span></div><div><b>05</b><span>hours</span></div><div><b>40</b><span>minutes</span></div></div>
        <h2>Saturday 24 October.</h2>
        <div class="cards"><div class="card plans"><small>SATURDAY PLANS</small><p>Market at nine. Call Léa about the bikes.</p><i>Write your plans…</i></div>
        <div class="card dark"><small>BEFORE SATURDAY · ~/CODE/SHOP</small><div id="list">No agent shown.</div></div></div>
        <script>
          const list = document.getElementById("list"), NAMES = { claude: "Claude Code", amp: "Amp", codex: "Codex" };
          // What the agents in ~/code/shop still do: who waits for the person, who works, in their own last words.
          const line = (state, a) => { const thread = (state.threads || []).find((t) => t.agent === a.id), turn = thread && thread.turns.at(-1);
            const said = ((turn && turn.items.at(-1) || {}).text || "").replace(/^./, (c) => c.toLowerCase());
            const p = document.createElement("p"), who = document.createElement("b");
            who.textContent = NAMES[a.kind] || a.kind;
            p.append(who, a.state === "waiting" ? ` waits for you: ${said}` : ` is at work: ${said}.`);
            return p; };
          const render = (state) => { const shown = (state.agents || []).filter((a) => (a.folder || "").endsWith("/code/shop")
              && ["waiting", "working"].includes(a.state)).sort((a, b) => (a.state === "waiting" ? -1 : 0) - (b.state === "waiting" ? -1 : 0));
            if (shown.length) list.replaceChildren(...shown.map((a) => line(state, a))); else list.textContent = "No agent shown."; };
          const again = () => something.state().then(render).catch(() => render({}));
          again(); something.on("change", render); something.on("granted", again);
        </script></body></html>
        """

    /// X5's agents (the mockup's XC_NOW), their words invented, in folders of the stage's home so that Info says them
    /// from ~: Claude Code at work and Amp waiting in shop, Codex idle in atelier since 16:10.
    static func weekendWorld(_ home: URL) -> (agents: [Agent], threads: [AgentThread]) {
        let at = { (minutes: Double) in iso8601.string(from: Stage.local.addingTimeInterval(-60 * minutes)) }
        let rows = [("cc", "claude", "shop", "working", 3.0, "Write the login form"), ("amp", "amp", "shop", "waiting", 6, "Run the tests?"),
                    ("cx", "codex", "atelier", "idle", 130, "The page builds again.")]
        var agents: [Agent] = [], threads: [AgentThread] = []
        for (key, kind, folder, state, minutes, words) in rows {
            var agent = Agent(id: "\(kind)-\(key)", kind: kind, origin: "elsewhere")
            (agent.folder, agent.state, agent.alive, agent.evidence, agent.thread) = (home.appendingPathComponent("code/\(folder)").path, state, true, "log", key)
            agent.name = folder
            (agent.started, agent.updated, agent.waiting) = (at(minutes + 20), at(minutes), state == "waiting" ? "permission" : "none")
            agents.append(agent)
            threads.append(AgentThread(id: key, agent: agent.id, title: nil, started: at(minutes + 20), turns: [
                Turn(id: "\(key)-0", state: state == "idle" ? "done" : "working", started: at(minutes + 20), ended: nil, items: [
                    Item(id: "\(key)-0-0", kind: "message", author: "agent", text: words, at: at(minutes)),
                ]),
            ]))
        }
        return (agents, threads)
    }

    /// The X5 window: Week-end open, watching your agents (the level its page needs, answered at its opening), its
    /// assistant asleep on the reply that built it, Info shown. The sidebar as the mockup groups it.
    static func weekend(_ stage: Stage) async throws -> (shell: Shell, library: Library, info: Info, view: SpaceView) {
        try AcceptanceAssistant.fake(in: stage)
        let page = try stage.home.space("week-end", weekendPage)
        try FileManager.default.setAttributes([.modificationDate: Stage.local.addingTimeInterval(-16 * 60)], ofItemAtPath: page.location.path)
        let at = { (minutes: Double) in iso8601.string(from: Stage.local.addingTimeInterval(-60 * minutes)) }
        let kept = Session(kind: "claude", model: "sonnet", space: "week-end")
        kept.kept = [Turn(id: "t1", state: "done", started: at(20), ended: at(17), items: [
            Item(id: "i1", kind: "message", author: "person", text: "[something] No space is open: the person is on the blank page.\n"
                 + "A countdown to Saturday, with what my agents still have to finish before the weekend.", at: at(20)),
            Item(id: "i2", kind: "message", author: "agent", text: "Week-end is ready. It counts down to Saturday. Try: write your plans, then reopen it.", at: at(17)),
        ])]
        var agent = Agent(id: "a0", kind: "claude", origin: "launched")
        (agent.thread, agent.alive, kept.id) = ("00000000-0000-4000-8000-000000000005", false, "a0")
        kept.read(State(at: at(17), kinds: [:], agents: [agent]))
        kept.save(in: stage.home.places.assistants)
        let (shell, library, info) = stage.window()
        library.preferences.groups = [("Work", ["week-end", "brief", "agents", "project"]), ("Notes", ["logbook", "oracle"]), ("Breaks", ["pet", "stack"])]
            .map { Preferences.Group(name: $0.0, spaces: $0.1) }
        library.relist()
        let model = shell.assistant, engine = model.engine
        model.clock = { Stage.local }
        engine.changed = { model.refresh() }
        engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        let view = try await stage.open("week-end", in: shell, library)
        view.engine.update(outside: weekendWorld(stage.home.places.home))
        view.push()   // the app's timer pushes four times a second; no timer runs here
        // Its page's own card hears them before any picture is drawn.
        var list = ""
        for _ in 0..<200 where !list.contains("run the tests?") {
            list = (try? await run(view, "return document.getElementById('list').textContent") as? String) ?? ""
            await wait(0.05)
        }
        #expect(list.contains("run the tests?"), "the page lists what Info lists: \(list)")
        shell.layer.announce = { _ in }
        (info.current, info.clock) = ({ view }, { Stage.local })
        info.show(view.space)
        shell.showInfo(true)
        shell.window.layoutIfNeeded()
        return (shell, library, info, view)
    }

    /// The panel's Info tab: Space (its file, Show in Finder, its weight and last change, Export), Memory, Versions and
    /// Assistant; Move to Trash… quiet at the foot. No agents, no level. ⌘I, ✕ and Esc close the panel.
    @Test("x5-1: Info in one place") func x5_1() async throws {
        let stage = try Stage("shell-x5-1")
        defer { stage.remove() }
        let (shell, library, info, view) = try await AcceptanceShell.weekend(stage)
        defer { view.close() }
        shell.showInfo(true, on: .info)
        #expect(shell.infoShown && info.content == .info && (shell.controls[Shell.info] as? ToolButton)?.pressed == true)
        // Info's 320 points are Default's: read in the drawing turn, which no other suite holds at Large meanwhile.
        let open = await Stage.alone {
            let docked = { shell.inspector.viewController.view.frame.width }
            #expect(await wait(10) { shell.window.layoutIfNeeded(); return docked() == 320 && view.web.frame.width == shell.center.frame.width },
                    "\(docked()) \(view.web.frame.width) \(shell.center.frame.width)")
            return view.web.frame.width
        }
        #expect(info.level == .watch && info.folder == nil && info.about == "A countdown to Saturday, your plans, and what your agents still have to finish.")
        #expect(Info.weight(try #require(info.size), form: .file, changed: info.changed, now: Stage.local).hasSuffix("one file · changed today, 18:04"))
        // As VoiceOver reads the tab: every button named, its parts.
        let panel = shell.inspector.viewController.view
        let heard = ["This space: Info", "Close the panel", "Week-end", "Space", "Show in Finder", "Export…", "Memory", "Versions", "Show History", "Assistant", "Move to Trash…"]
        // SwiftUI makes the panel's elements part by part, as late as a loaded Mac lets it: read until all are there.
        let tree = await AccessibilityTests.walk(panel) { words in heard.allSatisfy(words.contains) }, read = tree.words
        #expect(tree.unnamed.isEmpty, "\(tree.unnamed)")
        for words in heard {
            #expect(read.contains(words), "the panel reads \(words): \(read)")
        }
        for gone in ["Your agents", "With your agents", "Open Conversation", "Group", "Put to Sleep", "New Conversation", "Ask Again", "Show Request"] {
            #expect(!read.contains { $0.hasPrefix(gone) }, "Info no longer holds \(gone)")
        }
        #expect(info.memory == "It keeps no memory." && info.history.versions.isEmpty)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: view.web, "x5-1" + suffix, root: stage.home.root)
        }
        // Esc with the focus in the panel closes it; ⌘I opens it again and closes it; ✕ too.
        #expect(shell.window.makeFirstResponder(panel.subviews.first ?? panel))
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: shell.window.windowNumber,
                                                   context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        #expect(shell.escape(escape))
        #expect(!shell.infoShown && (shell.controls[Shell.info] as? ToolButton)?.pressed == false)
        // The page takes back the 320 points Info held, at Default's size like the width read open.
        await Stage.alone {
            #expect(await wait(10) { shell.window.layoutIfNeeded(); return shell.inspector.isCollapsed && view.web.frame.width == open + 320 },
                    "\(open) \(view.web.frame.width)")
        }
        let command = try #require(Keys.command("insp"))
        #expect(command.action == #selector(App.toggleInfo(_:)) && command.key == "i")
        shell.toggleInfo(spaceOpen: false)
        #expect(!shell.infoShown, "⌘I opens nothing while no space is open")
        shell.toggleInfo(spaceOpen: true)
        #expect(shell.infoShown)
        shell.toggleInfo(spaceOpen: true)
        #expect(!shell.infoShown)
        shell.toggleInfo(spaceOpen: true)
        info.close()
        #expect(!shell.infoShown, "✕")
    }

    /// Info's model also holds what an agent a space started offers: its model, effort, mode and commands, from what it lists;
    /// and once it has a conversation, Continue in Terminal, which stops it and hands Terminal a command file.
    @Test("Info: an agent's settings and Continue in Terminal") func agentSettings() async throws {
        let stage = try Stage("shell-settings")
        defer { stage.remove() }
        let (shell, library, info, view) = try await AcceptanceShell.weekend(stage)
        defer { view.close() }
        let home = stage.home.root, id = try view.launch("claude", folder: stage.home.places.spaces.path, model: nil, mode: nil, effort: nil)
        let reading: () -> AgentReading? = { info.refresh(); return info.shown.first { $0.id == id } }
        let agent: () -> Agent? = { reading()?.agent }
        #expect(await wait(until: { agent()?.options.model?.isEmpty == false && agent()?.commands?.isEmpty == false }))
        #expect(try #require(agent()).can.model && info.terminalWords(try #require(reading())) == nil, "no conversation yet")
        _ = try view.deliver("Make the tiles wider.", to: try #require(agent()), when: "next")
        #expect(await wait(until: { info.terminalWords(reading()!) != nil && agent()?.state == "idle" }))
        let lines = { (try? String(contentsOf: home.appendingPathComponent("out/input"), encoding: .utf8)) ?? "" }
        info.set(try #require(agent()), model: "sonnet")
        #expect(await wait(until: { lines().contains(#""set_model""#) }), "the model goes to the agent")
        info.set(try #require(agent()), mode: "plan")
        #expect(await wait(until: { lines().contains(#""set_permission_mode""#) }), "a mode that asks as much needs no click")
        info.command(try #require(agent()?.commands?.first?.value), to: try #require(agent()))
        #expect(await wait(until: { lines().contains(#""/"#) }), "its own command, as it lists it")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: view.web, "info-settings" + suffix, root: stage.home.root)
        }
        // Continue in Terminal: one click or two, one Terminal, and the launched row leaves at once, never reading Ended.
        var opened: [URL] = []
        info.terminal = { opened.append($0) }
        let moving = try #require(reading()), thread = try #require(moving.agent.thread)
        info.continueInTerminal(moving)
        info.continueInTerminal(moving)
        #expect(info.moving == [id], "the button waits")
        #expect(await wait(until: { !opened.isEmpty }), "Terminal gets its file once the agent stopped")
        let file = try #require(opened.first)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(reading() == nil && !view.engine.state.agents.contains { $0.id == id }, "no agent ended here: its conversation moved")
        info.continueInTerminal(moving)
        await wait(0.2)
        #expect(opened.count == 1, "a second click opens no second Terminal")
        // The reader then sees it, as an agent elsewhere; this space keeps it in sight, by the same key, with no Ended.
        var seen = Agent(id: Engine.seenID("claude", thread: thread), kind: "claude", origin: "elsewhere")
        (seen.alive, seen.thread, seen.state, seen.pid) = (true, thread, "idle", 4_200)
        #expect(view.launched.contains(seen.id) && !view.launched.contains(id) && Rights.key(seen) == moving.key)
        let after = AgentReading(seen, thread: nil, known: moving.title, runs: RunsIn { _ in ["/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"] })
        #expect((after.title, after.word, after.tag, after.phase) == (moving.title, "Idle", "In Terminal", .away))
        #expect(try String(contentsOf: file, encoding: .utf8) == "#!/bin/sh\nrm -- \"$0\"\ncd '\(stage.home.places.spaces.path)' && exec 'claude' '--resume' '\(thread)'\n")
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o700)
        #expect(Info.script(["x"], in: "/a'b") == "#!/bin/sh\nrm -- \"$0\"\ncd '/a'\\''b' && exec 'x'\n", "a quote stays in its word")
        #expect(Registry.app.agent("pi")?.terminal == nil, "only proven ways")
    }

    /// The level in one click (X5.2): None and the page shows no agent at once, nothing asked; Run takes a folder
    /// (asked when none is known) and says where it starts them.
    @Test("x5-2: the level in one click") func x5_2() async throws {
        let stage = try Stage("shell-x5-2")
        defer { stage.remove() }
        let (shell, library, info, view) = try await AcceptanceShell.weekend(stage)
        defer { view.close() }
        let asked = (view.ask as? FakeAsk)?.questions.count
        info.choose(.none)
        // What the page's own card lists, read until it says `words` (or, with `not`, anything else).
        func lists(_ words: String, not: Bool = false) async -> Bool {
            for _ in 0..<200 {
                let said = try? await run(view, "return document.getElementById('list').textContent") as? String
                if (said == words) != not { return true }
                await wait(0.05)
            }
            return false
        }
        #expect(await lists("No agent shown."), "the page shows no agent at once")
        #expect(info.level == Grant.Level.none && info.shown.isEmpty && view.granted.rights == ["store"])
        let shop = stage.home.places.home.appendingPathComponent("code/shop")
        try FileManager.default.createDirectory(at: shop, withIntermediateDirectories: true)
        var picks = 0
        info.pick = { answer in
            picks += 1
            answer(shop.path)
        }
        info.choose(.run)
        #expect(picks == 1 && info.level == .run && info.folder == shop.path && view.granted.folder == shop.path)
        let grant = try #require(try AppFile.read(stage.home.places.grants).spaces["week-end"])
        #expect(grant.level == .run && grant.granted == ["state", "send", "launch"] && grant.folder == shop.path)
        #expect((view.ask as? FakeAsk)?.questions.count == asked, "a level chosen in Info asks nothing more")
        #expect(await lists("No agent shown.", not: true), "it sees them again")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: view.web, "x5-2" + suffix, root: stage.home.root)
        }
        // Back to Watch: the folder goes with Run, and Run asks again only when nothing tells it where.
        info.choose(.watch)
        #expect(info.level == .watch && info.folder == nil && picks == 1)
    }

    /// Move to Trash with Undo (F3.2): the next space opens, the toast offers Undo; Undo brings back the file, the memory,
    /// the answers, the versions, the conversation and its place; the toast's end forgets them. An agent the space
    /// started keeps running, and the toast says so.
    @Test("f3-2: Trash with Undo, the next space opens") func f3_2() async throws {
        let stage = try Stage("shell-f3-2")
        defer { stage.remove() }
        try AcceptanceAssistant.fake(in: stage)
        let (shell, library, _) = stage.window()
        let model = shell.assistant, engine = model.engine, places = stage.home.places
        engine.changed = { model.refresh() }
        engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        let page = try await stage.open("logbook", in: shell, library)
        defer { page.close() }
        let trash = stage.home.root.appendingPathComponent("Trash")
        library.discard = { url in
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
            return trash.appendingPathComponent(url.lastPathComponent)
        }
        library.preferences.motion = .reduced
        func toast() -> Toast? { shell.layer.subviews.compactMap { $0 as? Toast }.last }
        func undo() throws {
            func buttons(_ view: NSView) -> [NSButton] { [view as? NSButton].compactMap { $0 } + view.subviews.flatMap(buttons) }
            try #require(toast().flatMap { buttons($0).first { $0.title == "Undo" } }).performClick(nil)
        }
        func trashed() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: trash.path).sorted() }
        func grants() throws -> [String: Grant] { try AppFile.read(places.grants).spaces }
        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
        func group(_ name: String) -> String? { library.sections().first { $0.entries.contains { $0.id == name } }?.group }
        let conversation = Session.file("logbook", in: places.assistants), versions = Versions(root: places.versions, keep: 50, limit: 0)
        let bin = TrashUndo(shell: shell), entry = try #require(library.entry("logbook"))
        let order = library.order().map(\.id), next = order[try #require(order.firstIndex(of: "logbook")) + 1], home = group("logbook")
        try versions.capture(entry.space, kind: .turn, sentence: "Make it")
        Session(kind: "claude", space: "logbook").save(in: places.assistants)
        library.preferences.includeMemory(true, of: "logbook")
        let running = try engine.launch("claude", folder: stage.home.root.path, model: nil, mode: nil, effort: nil)
        defer { engine.stopAll(within: 1, only: running) {} }
        #expect(await wait(until: { engine.state.agents.contains { $0.id == running && $0.alive == true } }))
        model.launches.ids["logbook"] = [running]
        let word = try #require(bin.running("logbook").first)
        #expect(try grants()["logbook"] != nil && exists(conversation))

        // Gone at once, the next space open; all it left waits for the toast, and the agent it started keeps running.
        bin.move(entry)
        #expect(library.selection == .space(next) && library.entry("logbook") == nil, "the next space opens, not New Space")
        #expect(toast()?.words == "Logbook is in the Trash · \(word) keeps running", "\(toast()?.words ?? "")")
        #expect(try trashed() == ["logbook.html", "logbook.json"] && grants()["logbook"] != nil && versions.list("logbook").count == 1)
        #expect(exists(conversation), "its conversation is kept")
        #expect(engine.state.agents.contains { $0.id == running && $0.alive == true })

        // Undo: everything back, in its place, the space open, its row ringed.
        try undo()
        #expect(toast()?.words == "Logbook is back")
        #expect(library.selection == .space("logbook") && library.entry("logbook") != nil && library.fresh == "logbook" && group("logbook") == home)
        #expect(try Memory(folder: places.data, space: "logbook").get("notes") != nil && grants()["logbook"] != nil && versions.list("logbook").count == 1)
        #expect(exists(conversation) && library.preferences.memoryExport["logbook"] == true && model.launches.ids["logbook"] == [running])
        try await stage.appearances { suffix in
            let held = shell.toast("Logbook is back", seconds: 60)
            try await Picture.window(shell, library: library, web: page.web, "f3-2" + suffix, root: stage.home.root)
            held.leave(now: true)
        }

        // The toast's end: it goes for good. Its agent is no longer the space's, and goes on.
        bin.move(entry)
        #expect(library.selection == .space(next))
        toast()?.leave(now: true)
        #expect(try !exists(conversation) && grants()["logbook"] == nil && trashed().contains("logbook"), "its versions went to the Trash")
        #expect(library.preferences.memoryExport["logbook"] == nil && model.launches.ids["logbook"] == nil && group("logbook") == nil)
        #expect(engine.state.agents.contains { $0.id == running && $0.alive == true })

        // Undo that can't: a new space took the name, and what the new one has stays.
        let pet = try #require(library.entry("pet")), title = pet.title
        var file = try AppFile.read(places.grants)
        file.spaces["pet"] = Grant(declared: Asked(Declaration(name: "pet")), at: "2026-10-17T09:00:00Z")
        try file.write(places.grants)
        bin.move(pet)
        _ = try stage.home.space("pet", "<!doctype html><p>A new one.</p>")
        library.relist()
        try undo()
        #expect(toast()?.words == "\(title) stays in the Trash: a new space took its name")
        #expect(try library.entry("pet") != nil && grants()["pet"] == nil, "a page under that name inherits no answer")
        // Put back in Finder during the toast: the same space, which keeps what it left.
        let oracleGrant = try #require(library.entry("oracle"))
        var answers = try AppFile.read(places.grants)
        answers.spaces["oracle"] = Grant(declared: Asked(Declaration(name: "oracle")), at: "2026-10-17T09:00:00Z")
        try answers.write(places.grants)
        bin.move(oracleGrant)
        try FileManager.default.moveItem(at: trash.appendingPathComponent("oracle.html"), to: oracleGrant.space.location)
        library.relist()
        toast()?.leave(now: true)
        #expect(try grants()["oracle"] != nil)
        // A Trash that fails leaves the toast on screen and its Undo whole.
        let tiny = try #require(library.entry("project")), held = library.discard
        var answer = try AppFile.read(places.grants)
        answer.spaces["project"] = Grant(declared: Asked(Declaration(name: "project")), at: "2026-10-17T09:00:00Z")
        try answer.write(places.grants)
        bin.move(tiny)
        library.discard = { _ in throw SpaceError("Invented.") }
        bin.move(try #require(library.entry("agents")))
        library.discard = held
        #expect(try grants()["project"] != nil && library.entry("agents") != nil)
        try undo()
        #expect(toast()?.words == "\(tiny.title) is back" && library.entry("project") != nil)
        // The Trash emptied meanwhile: said too.
        let stack = try #require(library.entry("stack"))
        bin.move(stack)
        try FileManager.default.removeItem(at: trash.appendingPathComponent("stack.html"))
        try undo()
        #expect(toast()?.words == "\(stack.title) is no longer in the Trash")
        // A second Trash ends the first's Undo at once.
        let brief = try #require(library.entry("brief")), second = try #require(library.entry("project"))
        Session(kind: "claude", space: "brief").save(in: places.assistants)
        bin.move(brief)
        bin.move(second)
        #expect(!exists(Session.file("brief", in: places.assistants)))
        bin.finish()
    }

    /// Export as one HTML file (F6.1): a space with a memory asks, Include Its Memory unticked; the file is in Downloads
    /// without it, one space's answer kept; the toast says so with Show. History beside it opens the versions in Info's place.
    @Test("f6-1: Export as one HTML file, then a browser") func f6_1() async throws {
        let stage = try Stage("shell-f6-1")
        defer { stage.remove() }
        let (shell, library, info, view) = try await AcceptanceShell.weekend(stage)
        defer { view.close() }
        try Memory(folder: stage.home.places.data, space: "week-end").set("plans", "Market at nine.")
        var revealed: [URL] = []
        library.reveal = { revealed.append($0) }
        let command = try #require(Keys.command("export"))
        #expect(command.title == "Export Space…" && command.key == "e" && command.action == #selector(App.exportSpace(_:)))
        // The sheet, as Export shows it: unticked; its words; Export is the way on, ↵ beside it.
        let entries = try #require(library.remembers("week-end"))
        let entry = try #require(library.entry("week-end"))
        let asked = Ask.export(entry, entries: 12, included: false)
        #expect(entries == 1 && asked.included() == false)
        #expect(PanelsTests.texts(asked.sheet.contentView).contains("week-end.html · one HTML file, in Downloads"), "\(PanelsTests.texts(asked.sheet.contentView))")
        #expect(PanelsTests.texts(asked.sheet.contentView).contains("12 entries. Anyone who gets the file can read them."))
        #expect(asked.sheet.title == "Export \(entry.title)" && asked.sheet.buttons.map(\.title) == ["Cancel", "Export"] && asked.sheet.buttons.map(\.role) == [.cancel, .primary])
        func ticks(_ view: NSView) -> [NSButton] { [view as? NSButton].compactMap { $0 }.filter { $0.title == "Include Its Memory" } + view.subviews.flatMap(ticks) }
        let tick = try #require(asked.sheet.contentView.flatMap { ticks($0).first })
        #expect(tick.state == .off, "unticked")
        tick.performClick(nil)
        #expect(asked.included() == true)
        tick.performClick(nil)
        #expect(Ask.export(entry, entries: 1, included: true).included() && PanelsTests.texts(Ask.export(entry, entries: 1, included: true).sheet.contentView).contains("1 entry. Anyone who gets the file can read them."))
        try await stage.appearances { suffix in
            try await Picture.sheet(asked.sheet, over: shell, library: library, web: view.web, "f6-1-sheet" + suffix, root: stage.home.root)
        }
        // The toast in place at once, so that the pictures show it whole.
        library.preferences.motion = .reduced
        library.export("week-end")
        let ask = try #require(library.ask as? FakeAsk)
        #expect(ask.exportsAsked.count == 1 && ask.exportsAsked[0].included == false && ask.told.isEmpty, "\(ask.told)")
        let file = stage.home.places.downloads.appendingPathComponent("week-end.html")
        let exported = try Export.read(try #require(Export.unwrap(try Data(contentsOf: file))))
        #expect(exported.name == "week-end" && exported.data == nil, "its memory stays on the Mac")
        #expect(library.preferences.memoryExport["week-end"] == false, "kept for this space")
        let toast = try #require(shell.layer.subviews.compactMap { $0 as? Toast }.last)
        #expect(toast.words == "week-end.html is in Downloads · one HTML file")
        func buttons(_ view: NSView) -> [NSButton] { [view as? NSButton].compactMap { $0 } + view.subviews.flatMap(buttons) }
        let show = try #require(buttons(toast).first { $0.title == "Show" })
        show.performClick(nil)
        #expect(revealed == [file])
        // The other word of the toast: with its memory.
        ask.exports = { _ in true }
        library.export("week-end")
        let second = try #require(shell.layer.subviews.compactMap { $0 as? Toast }.last)
        #expect(second.words == "week-end 2.html is in Downloads · one HTML file, its memory inside")
        // The pictures take longer than the toast stays: the same words held for them, as b1-frame-toast does.
        try await stage.appearances { suffix in
            let held = shell.toast(toast.words, action: Toast.Action(label: "Show") {}, seconds: 60)
            try await Picture.window(shell, library: library, web: view.web, "f6-1" + suffix, root: stage.home.root)
            #expect(held.shown && held.superview != nil, "the toast is in the picture")
            held.leave(now: true)
        }
        // History, a tab of the panel.
        info.select(.history)
        #expect(shell.infoShown && info.content == .history)
    }
    // MARK: Round 2, S6: Page Full Screen and the floating sidebar

    /// How far apart the lightest and the darkest pixel of `box` in `picture` are, in brightness from 0 to 1: how
    /// strongly the text there stands out from its background.
    static func spread(_ picture: NSBitmapImageRep, _ box: CGRect) -> CGFloat {
        var (low, high) = (CGFloat(1), CGFloat(0))
        for x in Int(box.minX)..<min(Int(box.maxX), picture.pixelsWide) {
            for y in Int(box.minY)..<min(Int(box.maxY), picture.pixelsHigh) {
                let bright = picture.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 0
                (low, high) = (min(low, bright), max(high, bright))
            }
        }
        return max(0, high - low)
    }

    /// The pointer's way in or out of `view`, as its tracking area would send it.
    static func pointer(_ entered: Bool, _ view: NSView) throws -> NSEvent {
        try #require(NSEvent.enterExitEvent(with: entered ? .mouseEntered : .mouseExited, location: .zero, modifierFlags: [], timestamp: 0,
                                            windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
    }

    static func escape(_ shell: Shell) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: shell.window.windowNumber,
                                      context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
    }

    /// A rectangle in the window's points, the origin at its top left as the mockup measures.
    static func inWindow(_ view: NSView, _ rect: NSRect) -> NSRect {
        let at = view.convert(rect, to: nil), height = view.window?.frame.height ?? 0
        return NSRect(x: at.minX, y: height - at.maxY, width: at.width, height: at.height)
    }

    /// Page Full Screen (2.6), ⇧⌘F or the toolbar's last button: the sidebar and Info step aside, the toolbar and the
    /// lights go, the page fills the window from its top, the sticker discreet; a hint says how to leave. The pointer
    /// at the top edge brings the toolbar back over the page (the picture), until it leaves it; ⌃⌘S floats the sidebar
    /// from the window's top; Esc leaves, everything back as it was. 2-6-alone is the page alone.
    @Test("2-6: Page Full Screen") func v2_6() async throws {
        let stage = try Stage("shell-2-6")
        defer { stage.remove() }
        let (shell, library, _, view) = try await AcceptanceShell.weekend(stage)
        defer { view.close() }
        let command = try #require(Keys.command("pagefull"))
        #expect(command.title == "Enter Page Full Screen" && command.key == "f" && command.modifiers == [.command, .shift] && command.mine && command.needsSpace)
        let typed = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0, windowNumber: 0,
                                                  context: nil, characters: "F", charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3))
        #expect(Keys.claim(typed) == .command("pagefull"), "the page never sees ⇧⌘F")
        let button = try #require(shell.controls[Shell.full] as? ToolButton)
        #expect(button.action == command.action && button.toolTip == "Page Full Screen (⇧⌘F)" && !button.pressed)
        let height = shell.window.frame.height
        func top() -> CGFloat? { shell.shown.map { $0.convert($0.bounds, to: nil).maxY } }
        func lights() -> [Bool] { [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { shell.window.standardWindowButton($0)?.isHidden } }
        #expect(shell.infoShown)
        var said: [String] = []
        shell.layer.announce = { said.append($0) }
        shell.pageFullScreen(true)
        shell.window.layoutIfNeeded()
        #expect(shell.pageFull && shell.column.constant == 0 && !shell.infoShown && shell.window.toolbar?.isVisible == false && lights() == [true, true, true])
        #expect(top() == height && view.web.frame.width == shell.window.frame.width, "the page fills the window")
        #expect(!button.pressed && button.toolTip == "Exit Page Full Screen (esc)" && button.accessibilityLabel() == "Exit Page Full Screen")
        #expect(said == ["Page Full Screen · esc to leave · ⌘K assistant"] && shell.layer.subviews.contains { $0 is NSHostingView<PageFullHint> }, "\(said)")
        // The sticker, discreet: smaller, toward the window's corner, faded until the pointer comes.
        let glass = shell.glass, sticker = glass.sticker
        #expect(glass.discreet && glass.corner.width == 32 && glass.corner.maxX == glass.bounds.width - Glass.margin && sticker.sign.alphaValue == 0.4)
        sticker.mouseEntered(with: try Self.pointer(true, sticker))
        #expect(sticker.sign.alphaValue == 1)
        sticker.mouseExited(with: try Self.pointer(false, sticker))
        #expect(sticker.sign.alphaValue == 0.4)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: view.web, "2-6-alone" + suffix, root: stage.home.root, keyed: false)
        }
        // The top edge brings the toolbar back over the page, its band behind it; leaving it, the toolbar goes again.
        #expect(!shell.topEdge.isHidden && Self.inWindow(shell.topEdge, shell.topEdge.bounds).height == 6)
        shell.topEdge.mouseEntered(with: try Self.pointer(true, shell.topEdge))
        shell.window.layoutIfNeeded()
        #expect(shell.window.toolbar?.isVisible == true && lights() == [false, false, false] && shell.topEdge.filled)
        #expect(Self.inWindow(shell.topEdge, shell.topEdge.bounds).height == shell.bar && top() == height, "over the page, which does not move")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: view.web, "2-6" + suffix, root: stage.home.root)
        }
        shell.topEdge.mouseExited(with: try Self.pointer(false, shell.topEdge))
        #expect(shell.window.toolbar?.isVisible == true, "not at once")
        #expect(await wait(until: { shell.window.toolbar?.isVisible == false }) && lights() == [true, true, true] && !shell.topEdge.filled)
        // ⌃⌘S floats the sidebar from the window's top; the pin is away: no room.
        shell.drawer.toggle()
        shell.drawer.layoutSubtreeIfNeeded()
        #expect(shell.drawer.state.peek && !library.sidebar.room)
        #expect(await wait(until: { shell.drawer.card.minX == Drawer.margin }) && Self.inWindow(shell.drawer, shell.drawer.card).minY == 10)
        shell.drawer.toggle()
        #expect(!shell.drawer.state.peek)
        // An input method's Esc ends its composition, not Page Full Screen.
        let typing = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        shell.center.addSubview(typing)
        shell.window.makeFirstResponder(typing)
        typing.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let composing = try Self.escape(shell)
        #expect(typing.hasMarkedText() && !shell.escape(composing) && shell.pageFull, "composing")
        typing.unmarkText()
        typing.removeFromSuperview()
        // Esc leaves: the sidebar and the toolbar back, the page under the toolbar, the sticker as it was.
        #expect(shell.escape(try Self.escape(shell)))
        shell.window.layoutIfNeeded()
        #expect(!shell.pageFull && library.sidebar.room && shell.window.toolbar?.isVisible == true && lights() == [false, false, false])
        #expect(top() == shell.window.contentLayoutRect.maxY && !glass.discreet && glass.corner.width == Glass.side && sticker.sign.alphaValue == 1)
        let esc = try Self.escape(shell)
        #expect(!button.pressed && shell.topEdge.isHidden && !shell.escape(esc), "Esc is the page's again")
        // The Mac's full screen ends it; off the spaces it ends, and it never starts there.
        shell.pageFullScreen(true)
        shell.fullScreen(true)
        #expect(!shell.pageFull && shell.full && glass.discreet && shell.window.toolbar?.isVisible == true)
        shell.fullScreen(false)
        shell.pageFullScreen(true)
        shell.show(nil)
        #expect(!shell.pageFull && shell.drawer.state.dock && shell.window.toolbar?.isVisible == true, "New Space holds it open")
        shell.pageFullScreen(true)
        #expect(!shell.pageFull && shell.controls[Shell.full]?.isEnabled == false)
    }

    /// ⌘K in Page Full Screen (2.8): the card opens from the discreet sticker over the page alone, as anywhere; Esc
    /// folds it first, then leaves Page Full Screen.
    @Test("2-8: ⌘K in Page Full Screen") func v2_8() async throws {
        let stage = try Stage("shell-2-8")
        defer { stage.remove() }
        let (shell, library, _, view) = try await AcceptanceShell.weekend(stage)
        defer { view.close() }
        let model = shell.assistant
        shell.pageFullScreen(true)
        model.focus()
        #expect(model.cardShown && shell.pageFull)
        #expect(await wait { shell.glass.grown == true && !shell.glass.morphing }, "the card grew from the sticker")
        let card = Self.inWindow(shell.glass, shell.glass.card.frame)
        #expect(card.maxY <= shell.window.frame.height && card.maxX <= shell.window.frame.width, "\(card)")
        #expect(shell.glass.sticker.isHidden && shell.window.toolbar?.isVisible == false)
        // The hint of the first moments goes after 2.6 s: both pictures are drawn without it (2-6-alone has it).
        #expect(await wait { !shell.layer.subviews.contains { $0 is NSHostingView<PageFullHint> } }, "the hint is gone")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: view.web, "2-8" + suffix, root: stage.home.root, keyed: false)
        }
        shell.window.makeFirstResponder(view.web)
        #expect(shell.escape(try Self.escape(shell)) && !model.cardShown && shell.pageFull, "Esc folds the card first")
        #expect(await wait { shell.glass.grown == false && !shell.glass.morphing && shell.glass.stickerShown })
        #expect(shell.escape(try Self.escape(shell)) && !shell.pageFull, "then leaves")
    }

    // MARK: The words and the window's finish (X1.1, X1.3, 2.9, 2.10)

    /// The window and its menus in the words Emi kept (X1.1, axis 1 B): "Space" stays, said at once as "pages of your
    /// own" beside the sidebar's SPACES; the groups are Work, Notes and Breaks ("agents" means one thing only); the
    /// menu bar says File, Edit, View, Go, Space, Assistant, Window, Help, and the Assistant menu names the open space's
    /// assistant first. The open menu cannot be drawn offscreen: its lines are written beside the picture as
    /// x1-1-assistant.txt. Build With ▸ is filled by the app when it opens, which this menu bar has no part of: the
    /// builder it checks is AssistantTests.buildWithChoosesNewSpacesBuilder's.
    @Test("x1-1: the window and its menus") func x1_1() async throws {
        let stage = try Stage("shell-x1-1")
        defer { stage.remove() }
        let (shell, library, brief) = try await Self.calm(stage)
        defer { brief.close() }
        shell.drawer.open()
        let said = await AcceptanceBuild.read(shell.drawer.host) { $0.contains("Spaces, pages of your own") && $0.contains("Stack, Asleep") }
        #expect(said.contains("Spaces, pages of your own") && said.contains("New Space") && said.contains("Templates"), "\(said)")
        #expect(library.sections().map(\.group) == ["Work", "Notes", "Breaks"])
        #expect(!said.contains { $0.hasPrefix("Agents,") }, "no group is called Agents: \(said)")
        let drawn = try await stage.drawn(shell)
        #expect(drawn.contains { $0.contains("pages of your own") }, "the drawn sidebar explains the word: \(drawn)")
        let bar = MenuBar(builders: nil)
        bar.open = { ("brief", "Daily brief") }
        bar.refresh()
        #expect(bar.menu.items.dropFirst().map(\.title) == ["File", "Edit", "View", "Go", "Space", "Assistant", "Window", "Help"])
        let assistant = try #require(bar.submenu("Assistant")), lines = Mockup.lines(assistant)
        #expect(lines.first == "# Daily brief’s assistant", "\(lines)")
        for line in ["Ask…  ⌘K", "Show Conversation  ⌘J", "Stop  ⌘.", "Point at a Part  ⌥⌘S", "Put Idle Assistants to Sleep"] {
            #expect(lines.contains(line), "the Assistant menu holds \(line): \(lines)")
        }
        #expect(Mockup.lines(try #require(bar.submenu("Space"))).first == "# Daily brief")
        if let gallery {
            try FileManager.default.createDirectory(at: gallery, withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n").write(to: gallery.appendingPathComponent("x1-1-assistant.txt"), atomically: true, encoding: .utf8)
        }
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "x1-1" + suffix, root: stage.home.root)
        }
    }

    /// Talking to the one who builds (X1.3, axis 1 B): Logbook open, ⌘K opens its card, named for the role and the
    /// space, whatever agent is behind it: the sticker and the menu say "assistant", the chip says the agent. Asleep,
    /// it wakes on the next message.
    @Test("x1-3: talk to the one who builds") func x1_3() async throws {
        let stage = try Stage("shell-x1-3")
        defer { stage.remove() }
        try AcceptanceAssistant.fake(in: stage)
        let (shell, library, _) = stage.window()
        Stage.work(library)
        try Self.eyes(shell, Stage.moment)
        shell.waiting(["agents"], mine: 0)
        let model = shell.assistant
        model.engine.changed = { model.refresh() }
        model.engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        let logbook = try await stage.open("logbook", in: shell, library)
        defer { logbook.close() }
        #expect(Keys.command("ask")?.key == "k" && Keys.command("ask")?.title == "Ask…")
        model.focus()
        #expect(model.cardShown && model.title == "Logbook" && model.place.space == "logbook")
        #expect(await wait { shell.glass.grown == true && !shell.glass.morphing }, "the card grew from the sticker")
        #expect(model.name == "Claude Code" && AgentChips.labels(model)[0] == "Program: Claude Code. Change", "\(AgentChips.labels(model))")
        #expect(model.presence.header == "Asleep · wakes on your next message" && model.placeholder == "Ask for a change · / for Claude Code’s commands", "\(model.presence.header) \(model.placeholder)")
        let bar = MenuBar(builders: nil)
        bar.open = { ("logbook", "Logbook") }
        bar.refresh()
        #expect(Mockup.lines(try #require(bar.submenu("Assistant"))).first == "# Logbook’s assistant")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: logbook.web, "x1-3" + suffix, root: stage.home.root)
        }
        var stopped = false
        model.engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })
    }

    /// The sidebar's finish (2.9, in v6.2's window): bottom left the word "something" alone and a real gear for
    /// Settings; a list longer than the column fades out above Templates instead of cutting a row in half. Ten more
    /// spaces in Notes, in a window 1000 by 660.
    @Test("2-9: something, and a real gear") func v2_9() async throws {
        let stage = try Stage("shell-2-9")
        defer { stage.remove() }
        let more = [("garden", "Garden notes"), ("review", "Morning review"), ("reading", "Reading list"), ("recipes", "Recipes"),
                    ("wins", "Tiny wins"), ("trips", "Trips"), ("birds", "Bird log"), ("films", "Films"), ("plants", "Plants"), ("walks", "Walks")]
        for (name, title) in more {
            try stage.home.space(name, page(#"{"contract": 1, "title": "\#(title)"}"#, "<p>Invented.</p>"))
        }
        let (shell, library, _) = stage.window(NSSize(width: 1000, height: 660))
        library.preferences.groups = Stage.groups.map { Preferences.Group(name: $0.0, spaces: $0.0 == "Notes" ? $0.1 + more.map(\.0) : $0.1) }
        library.relist()
        try Self.eyes(shell, Stage.moment)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        #expect(library.sections().map(\.entries.count) == [3, 12, 2])
        shell.drawer.open()
        let host = shell.drawer.host
        let said = await AcceptanceBuild.read(host) { $0.contains("Settings") && $0.contains("Templates") }
        #expect(said.contains("Settings") && said.contains("Templates"), "\(said)")
        #expect(Keys.tooltip("settings", "Settings") == "Settings (⌘,)")
        // The word alone, no sign: the sign with eyes is the assistant's.
        let whole = try stage.sidebar(shell, taller: 200), lines = try await Picture.lines(whole), drawn = lines.map(\.words)
        #expect(drawn.contains("something"), "the foot says something alone: \(drawn)")
        func foot() async throws -> CGFloat {
            let rep = try stage.sidebar(shell), lines = try await Picture.lines(rep), scale = CGFloat(rep.pixelsHigh) / rep.size.height
            let templates = try #require(lines.first { $0.words.hasSuffix("Templates") }), word = try #require(lines.first { $0.words == "something" })
            #expect(word.box.minY > templates.box.maxY, "something stands under Templates")
            return (word.box.midY - templates.box.midY) / scale
        }
        #expect(drawn.contains { $0.hasSuffix("Templates") } && drawn.contains { $0.contains("Daily brief") }, "\(drawn)")
        // The list is longer than its column, and it ends on a whole row that fades out above Templates. Drawn as the
        // window shows the column, below the title bar: the last row read above Templates spans what it spans at the
        // sidebar's full height (not cut through), stands out less than there (faded), and nothing of a next row is
        // drawn between it and Templates.
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        let list = try #require(all(host).compactMap { $0 as? NSScrollView }.first)
        #expect((list.documentView?.frame.height ?? 0) > list.contentView.bounds.height, "the list overflows its column")
        let shown = try stage.sidebar(shell), seen = try await Picture.lines(shown)
        let templates = try #require(seen.first { $0.words.hasSuffix("Templates") }?.box, "\(seen.map(\.words))")
        let last = try #require(seen.filter { $0.box.maxY < templates.minY }.max { $0.box.minY < $1.box.minY })
        let full = try #require(lines.first { $0.words == last.words }?.box, "\(last.words) is a row of the whole list")
        #expect(last.box.minY < full.minY + 4 && last.box.maxY > full.maxY - 4, "\(last.words) is drawn whole: \(last.box) \(full)")
        let (faded, clear) = (Self.spread(shown, last.box), Self.spread(whole, full))
        #expect(clear > 0.4 && faded < clear * 0.85, "\(last.words) fades: \(faded) \(clear)")
        let gap = CGRect(x: full.minX, y: last.box.maxY + 4, width: full.width, height: max(1, templates.minY - last.box.maxY - 8))
        #expect(Self.spread(shown, gap) < 0.05, "no row is cut through between \(last.words) and Templates")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "2-9" + suffix, root: stage.home.root)
        }
        // The chrome grows with the words at Larger (6.3): the first group's header, as drawn, 25 × 1.24, and Templates.
        #expect(await wait { abs((library.sidebar.ends.min() ?? 0) - 25) < 0.5 }, "\(library.sidebar.ends)")
        let normal = try await foot()
        try await Stage.alone {
            Look.scale.size = .larger
            _ = try stage.sidebar(shell)
            #expect(await wait { abs((library.sidebar.ends.min() ?? 0) - 25 * 1.24) < 0.5 }, "\(library.sidebar.ends)")
            let larger = try await foot()
            #expect(larger > normal, "Templates' row and the foot grow with the words: \(larger) from \(normal)")
        }
    }

    /// Forty spaces in three groups, which no frozen step shows: the sidebar scrolls to the last space, at the main
    /// size and in the smallest window, and Go to… finds it. Drawn as forty-sidebar.
    @Test("Forty spaces") func fortySpaces() async throws {
        let stage = try Stage("shell-forty")
        defer { stage.remove() }
        let names = (1...40).map { String(format: "s%02d", $0) }
        for (index, name) in names.enumerated() {
            try stage.home.space(name, page(#"{"contract": 1, "title": "Invented \#(index + 1)"}"#, "<p>Invented.</p>"))
        }
        let (shell, library, _) = stage.window()
        library.preferences.groups = [("Home", 0..<14), ("Studio", 14..<27), ("Later", 27..<40)].map { Preferences.Group(name: $0.0, spaces: Array(names[$0.1])) }
        library.relist()
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        let last = try #require(library.order().last { names.contains($0.id) })
        #expect(library.order().filter { names.contains($0.id) }.count == 40)
        // The last row can be scrolled into view: scrolled to its end, the column shows its last row whole, the
        // sidebar's above its fade (its bottom in the list, `ends`).
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func scrolls(_ host: NSView) throws -> Bool {
            let list = try #require(all(host).compactMap { $0 as? NSScrollView }.first), clip = list.contentView
            guard let document = list.documentView, document.frame.height > clip.bounds.height else { return false }
            clip.scroll(to: NSPoint(x: 0, y: document.isFlipped ? document.frame.height - clip.bounds.height : 0))
            list.reflectScrolledClipView(clip)
            host.layoutSubtreeIfNeeded()
            // The visible part, measured from the list's top as `ends` are.
            let visible = clip.documentVisibleRect, top = document.isFlipped ? visible.minY : document.frame.height - visible.maxY
            let bottom = try #require(library.sidebar.ends.max())
            return top <= bottom - 30 && top + visible.height - SidebarView.fade >= bottom - 1
        }
        shell.drawer.open()
        let host = shell.drawer.host
        shell.window.layoutIfNeeded()
        #expect((library.sidebar.ends.max() ?? 0) > host.frame.height, "the list is longer than the column")
        #expect(try scrolls(host), "the sidebar scrolls to \(last.title)")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "forty-sidebar" + suffix, root: stage.home.root)
        }
        shell.window.setContentSize(NSSize(width: 640, height: 480))
        shell.window.layoutIfNeeded()
        #expect(try scrolls(host), "the sidebar of the smallest window scrolls to \(last.title)")
        // Go to… finds it by its title.
        let palette = PaletteModel(library: library, eyes: { _ in .sleep }, enabled: { _ in true })
        palette.query = last.title
        #expect(palette.rows.first { $0.section == .spaces }?.id == "space:" + last.id, "\(palette.rows.map(\.id))")
    }

    /// A calm toolbar where no space is open (2.10): on New Space and Templates, Point, Info and Page Full Screen are
    /// gone rather than greyed, and the name opens nothing; they come back with a space. Drawn on Templates. Page Full
    /// Screen goes too, though 2.10's note keeps it there: X9.1 A and slice S5 ("nothing space-only") came after, and a
    /// page's full screen has no page to show.
    @Test("2-10: a calm toolbar without a space") func v2_10() async throws {
        let stage = try Stage("shell-2-10")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        Stage.work(library)
        try Self.eyes(shell, Stage.moment)
        let tools = [Shell.point, Shell.info, Shell.full]
        @MainActor func shown() -> [Bool] { tools.map { shell.controls[$0]?.isHidden == false } }
        #expect(library.selection == .newSpace && shown() == [false, false, false] && shell.window.title == "New Space")
        #expect(shell.titleLine.accessibilityRole() == .staticText && shell.titleLine.toolTip == nil)
        library.select(.templates)
        shell.show(nil, templates: true)
        #expect(shell.window.title == "Templates" && shown() == [false, false, false] && shell.titleLine.accessibilityRole() == .staticText)
        #expect(shell.window.toolbar?.items.map(\.itemIdentifier) == [Shell.sidebar, Shell.title, .flexibleSpace, Shell.tools])
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "2-10" + suffix, root: stage.home.root)
        }
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        #expect(shown() == [true, true, true] && shell.titleLine.accessibilityRole() == .button)
    }

    // MARK: Round 4, the final mockup

    @Test("r4-1: At rest: the glass header, no rail", .disabled("not built yet: S3")) func r4_1() async throws {}

    /// The sidebar by the edge or ⌃⌘S (R4.2): at rest the page has the window; a strip at the left edge under the
    /// toolbar, no control for VoiceOver; the pointer resting there shows a mark, and 200 ms later, or at a click, the
    /// sidebar comes over the page, 250 wide, 10 from the edges, in glass. It leaves 0.32 s after the pointer, never
    /// during a menu, a rename, a sheet's wait or an Undo toast; a click on the page sends it away and still reaches the
    /// page. The blur behind it is the window server's: the picture shows the tint alone.
    @Test("r4-2: The drawer by the edge or ⌃⌘S") func r4_2() async throws {
        let stage = try Stage("shell-r4-2")
        defer { stage.remove() }
        let (shell, library, _, view) = try await Self.weekend(stage)
        defer { view.close() }
        shell.showInfo(false)
        shell.waiting(["agents"], mine: 0)
        try stage.moment(shell)
        let drawer = shell.drawer, edge = shell.leftEdge
        shell.window.layoutIfNeeded()
        #expect(!drawer.state.shown && !edge.isHidden && !edge.isAccessibilityElement() && shell.column.constant == 0)
        #expect(view.web.frame.width == Stage.Size.main.width, "in a space the page takes the whole window")
        let strip = Self.inWindow(edge, edge.bounds), under = shell.window.frame.height - shell.window.contentLayoutRect.maxY
        #expect(strip.minX == 0 && strip.width == 8 && strip.minY == under && strip.maxY == shell.window.frame.height, "\(strip)")
        #expect(drawer.hitTest(NSPoint(x: 100, y: 300)) == nil, "away, it takes no click")
        // The pointer rests on the edge: its mark at once, the sidebar after 200 ms.
        let rested = Date()
        edge.mouseEntered(with: try Self.pointer(true, edge))
        #expect(!drawer.state.shown && edge.subviews.count == 1 && edge.subviews[0].frame.width == 7, "not at once")
        #expect(!drawer.isAccessibilityElement(), "closed, VoiceOver finds no empty group")
        #expect(await wait(until: { drawer.state.peek }) && Date().timeIntervalSince(rested) >= 0.2)
        #expect(await wait(until: { drawer.card.minX == Drawer.margin }))
        shell.window.layoutIfNeeded()
        let card = Self.inWindow(drawer, drawer.card)
        #expect(card.minX == 10 && card.width == 250 && card.minY == under + 10 && card.maxY == shell.window.frame.height - 10, "\(card)")
        #expect(edge.isHidden && drawer.accessibilityLabel() == "Sidebar" && shell.column.constant == 0, "over the page, which does not move")
        #expect(edge.subviews[0].alphaValue == 0 && drawer.isAccessibilityElement(), "the mark went with its coming")
        let order = shell.split.view.accessibilityChildrenInNavigationOrder() as? [NSView]
        #expect(order?.first === shell.chrome, "VoiceOver reads the sidebar before the page")
        #expect(view.web.frame.width == Stage.Size.main.width)
        let sidebar = try #require(MenuBar(builders: nil).submenu("View")?.items.first { $0.identifier?.rawValue == "sidebar" })
        shell.retitle(sidebar)
        #expect(sidebar.title == "Hide Sidebar")
        #expect((shell.toolbarItems.first { $0.itemIdentifier == Shell.sidebar }?.view as? ToolButton)?.pressed == true)
        library.sidebar.hovered = .space("logbook")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: view.web, "r4-2" + suffix, root: stage.home.root)
        }
        library.sidebar.hovered = nil
        // The pointer leaves it: it goes a moment later.
        let left = Date()
        drawer.mouseEntered(with: try Self.pointer(true, drawer))
        drawer.mouseExited(with: try Self.pointer(false, drawer))
        #expect(drawer.state.peek, "not at once")
        #expect(await wait(until: { !drawer.state.peek }) && Date().timeIntervalSince(left) >= 0.3, "it leaves with the pointer")
        #expect(await wait(until: { drawer.host.isHidden && !edge.isHidden }), "the edge is back")
        // A click on the edge: at once. A row's menu, a rename, an Undo toast, a sheet's wait each keep it.
        edge.mouseDown(with: try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 3, y: 300), modifierFlags: [], timestamp: 0,
                                                             windowNumber: shell.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)))
        #expect(drawer.state.peek, "at once")
        drawer.mouseExited(with: try Self.pointer(false, drawer))
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
        await wait(0.6)
        #expect(drawer.state.peek, "a menu is open")
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: NSMenu())
        func click(_ x: CGFloat, _ y: CGFloat) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: 0,
                                            windowNumber: shell.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        let page = try click(700, 300)
        library.beginRename(.group("Work"))
        await wait(0.6)
        drawer.clicked(page)
        #expect(drawer.state.peek, "a name is being edited, a click keeps it")
        library.cancelRename()
        shell.layer.announce = { _ in }
        let undo = shell.toast("Trashed", action: Toast.Action(label: "Undo") {}, seconds: 60)
        await wait(0.6)
        drawer.clicked(page)
        #expect(drawer.state.peek && shell.holdsDrawer, "an Undo toast is up, a click keeps it")
        undo.leave(now: true)
        let sheet = Sheet(icon: nil, title: "A sheet", actions: [])
        shell.window.beginSheet(sheet) { _ in }
        await wait(0.6)
        drawer.clicked(page)
        #expect(drawer.state.peek, "a sheet is up")
        Shell.endSheets(of: shell.window)
        #expect(await wait(until: { !drawer.state.peek }), "then it leaves")
        // A rename in Page Full Screen: Esc is the field's, and the mode stays.
        shell.pageFullScreen(true)
        drawer.open()
        library.beginRename(.group("Work"))
        #expect(!shell.escape(try Self.escape(shell)) && shell.pageFull && drawer.state.peek)
        library.cancelRename()
        drawer.close()
        shell.pageFullScreen(false)
        // ⌃⌘S brings it with the keys; Esc takes it away, the keys back on the page; a click on the page too.
        shell.window.makeFirstResponder(view.web)
        drawer.toggle()
        #expect(drawer.state.peek && shell.window.firstResponder === drawer.host)
        #expect(shell.escape(try Self.escape(shell)) && !drawer.state.peek && shell.window.firstResponder === view.web, "Esc")
        drawer.toggle()
        drawer.clicked(try click(100, 300))
        #expect(drawer.state.peek, "a click on the card is the card's")
        let button = try #require(drawer.button()), middle = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        drawer.clicked(try click(middle.x, middle.y))
        #expect(drawer.state.peek, "the toolbar's button toggles it itself")
        drawer.clicked(page)
        #expect(!drawer.state.peek, "a click on the page")
        // ⌃⌘S goes to the app, and waits under what covers the window.
        #expect(Keys.command("sidebar")?.action == #selector(App.showSidebar(_:)) && Keys.command("keepSidebar")?.action == #selector(App.keepSidebarOpen(_:)))
        #expect(Keys.enabled("sidebar", Keys.Situation()) && !Keys.enabled("sidebar", Keys.Situation(covered: true)) && !Keys.enabled("keepSidebar", Keys.Situation(covered: true)))
        // The drawn head: the word, no New Space or Go to… row.
        let drawn = try await stage.drawn(shell)
        for line in ["Spaces", "pages of your own", "Needs You", "Templates", "something"] { #expect(drawn.contains { $0.contains(line) }, "\(line): \(drawn)") }
        #expect(!drawn.contains { $0.contains("Go to") || $0.contains("New Space") }, "\(drawn)")
    }

    /// The pin (R4.3): the pin keeps the sidebar, the same card, and the page narrows beside it, the toolbar where it
    /// was; again, it floats and leaves with the pointer. ⌃⌘S hides a pinned sidebar for a while and brings it back
    /// pinned. View › Keep Sidebar Open is the same bit, checked, and so is Settings' row, kept in the preferences. A
    /// window under 860 points has no room: the pin hides and the sidebar floats. On New Space and Templates it stays
    /// open beside the page, ⌃⌘S hiding it there too, and pressing Build sends it away. Sheets hang over the page.
    @Test("r4-3: The pin") func r4_3() async throws {
        let stage = try Stage("shell-r4-3")
        defer { stage.remove() }
        let (shell, library, _, view) = try await Self.weekend(stage)
        defer { view.close() }
        shell.showInfo(false)
        shell.waiting(["agents"], mine: 0)
        try stage.moment(shell)
        let drawer = shell.drawer
        func start() -> CGFloat { shell.center.convert(shell.center.bounds, to: nil).minX }
        #expect(!library.preferences.pinned && !Preferences(stage.home.places).pinned, "Floating at first")
        let title = shell.titleLine.convert(shell.titleLine.bounds, to: nil).minX
        drawer.open()
        #expect(await wait(until: { drawer.card.minX == Drawer.margin }))
        shell.keepSidebar()
        shell.window.layoutIfNeeded()
        #expect(drawer.state.dock && drawer.state.kept && !drawer.state.peek && library.sidebar.kept && shell.column.constant == 270)
        #expect(start() == 270 && view.web.frame.width == Stage.Size.main.width - 270, "the page beside it: \(start())")
        #expect(shell.titleLine.convert(shell.titleLine.bounds, to: nil).minX == title, "the toolbar does not move")
        #expect(drawer.card.minX == 10 && drawer.card.width == 250, "the same card")
        #expect(Preferences(stage.home.places).pinned, "kept for the next start")
        #expect(shell.leftEdge.isHidden, "docked, no edge")
        // Hiding it gives the keys to the page, even when the sidebar held them.
        shell.window.makeFirstResponder(drawer.host)
        drawer.toggle()
        #expect(shell.window.firstResponder === view.web, "the page takes the keys")
        drawer.toggle()
        shell.window.makeFirstResponder(drawer.host)
        shell.pageFullScreen(true)
        #expect(shell.window.firstResponder === view.web, "in Page Full Screen too")
        shell.pageFullScreen(false)
        // Info opening keeps the sidebar's layer over the columns, the window layer over it.
        shell.showInfo(true)
        #expect(Array(shell.split.view.subviews.suffix(2)) == [shell.chrome, shell.layer])
        shell.showInfo(false)
        let bar = MenuBar(builders: nil), menu = try #require(bar.submenu("View"))
        let keep = try #require(menu.items.first { $0.identifier?.rawValue == "keepSidebar" })
        shell.retitle(keep)
        #expect(keep.title == "Keep Sidebar Open" && keep.state == .on && keep.keyEquivalent.isEmpty)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: view.web, "r4-3" + suffix, root: stage.home.root)
        }
        // ⌃⌘S: away for a while, and back pinned.
        drawer.toggle()
        shell.window.layoutIfNeeded()
        #expect(drawer.state.away && !drawer.state.shown && shell.column.constant == 0 && start() == 0)
        shell.retitle(keep)
        #expect(keep.state == .off, "the pin is up while it is away")
        drawer.open()
        #expect(drawer.state.peek, "the edge still brings it")
        drawer.toggle()
        shell.window.layoutIfNeeded()
        #expect(drawer.state.dock && drawer.state.pinned && !drawer.state.away && start() == 270)
        // Sheets hang over the page beside it; toasts and the sticker follow the center.
        let sheet = Sheet(icon: nil, title: "A sheet", actions: [])
        #expect(shell.window(shell.window, willPositionSheet: sheet, using: .zero).minX == 270)
        // A narrow window: no room, the pin hides, the sidebar floats; wide again it docks.
        shell.window.setContentSize(NSSize(width: 859, height: 760))
        shell.window.layoutIfNeeded()
        #expect(!drawer.state.dock && !library.sidebar.room && shell.column.constant == 0 && start() == 0 && drawer.state.pinned)
        drawer.toggle()
        #expect(drawer.state.peek, "⌃⌘S floats it")
        drawer.close()
        shell.window.setContentSize(NSSize(width: 860, height: 760))
        shell.window.layoutIfNeeded()
        #expect(drawer.state.dock && library.sidebar.room && start() == 270)
        // The line grows with the interface size.
        try await Stage.alone {
            shell.window.setContentSize(NSSize(width: 900, height: 760))
            Look.scale.size = .larger
            #expect(await wait(until: { !library.sidebar.room }), "Larger at 900 wide")
            Look.scale.size = .standard
            #expect(await wait(until: { library.sidebar.room }))
        }
        shell.window.setContentSize(Stage.Size.main)
        // Settings' row is the same bit; a second click on the pin floats it.
        library.preferences.pinned = false
        #expect(await wait(until: { !drawer.state.dock }) && !drawer.state.peek)
        library.preferences.pinned = true
        #expect(await wait(until: { drawer.state.dock }))
        shell.keepSidebar()
        #expect(!drawer.state.pinned && !library.preferences.pinned && !drawer.state.shown, "the pointer elsewhere: it leaves")
        drawer.mouseEntered(with: try Self.pointer(true, drawer))
        shell.keepSidebar()
        shell.keepSidebar()
        #expect(drawer.state.peek && !drawer.state.pinned, "the pointer on it: it stays until the pointer leaves")
        drawer.mouseExited(with: try Self.pointer(false, drawer))
        #expect(await wait(until: { !drawer.state.peek }))
        // New Space and Templates hold it open; ⌃⌘S hides it there, the next view holds it again.
        library.select(.newSpace)
        shell.show(nil)
        shell.window.layoutIfNeeded()
        #expect(drawer.state.dock && drawer.state.held && start() == 270 && library.sidebar.kept == false)
        drawer.toggle()
        shell.window.layoutIfNeeded()
        #expect(drawer.state.off && !drawer.state.shown && start() == 0)
        shell.show(nil, templates: true)
        #expect(drawer.state.dock, "Templates holds it")
        drawer.toggle()
        drawer.toggle()
        #expect(drawer.state.dock)
        // Back on a space it leaves, except from under the pointer, which it leaves with.
        drawer.mouseEntered(with: try Self.pointer(true, drawer))
        shell.show(view)
        #expect(drawer.state.peek && !drawer.state.dock, "it stays under the pointer")
        drawer.mouseExited(with: try Self.pointer(false, drawer))
        #expect(await wait(until: { !drawer.state.peek }))
        // Either full screen: the pin hides.
        shell.pageFullScreen(true)
        #expect(!library.sidebar.room)
        shell.pageFullScreen(false)
    }

    /// The states of the pure value, the mockup's YW, row by row: what the window cannot reach in one scenario.
    @Test func theSidebarsStateIsTheMockups() {
        var state = DrawerState()
        #expect(state.held && state.dock && state.shown, "New Space at first")
        state.build(true)
        #expect(!state.held && !state.dock, "pressing Build sends it away")
        state.toggle()
        #expect(state.peek && !state.dock, "⌃⌘S over a build")
        state.build(false)
        state.viewed(page: true, inside: false, writing: false)
        #expect(!state.peek && !state.shown)
        state.peek = true
        state.viewed(page: true, inside: true, writing: true)
        #expect(!state.peek, "a space being built takes the whole window, even under the pointer")
        state.room = false
        state.pin(inside: false)
        #expect(state.pinned && !state.dock, "no room: the pin waits")
        state.room = true
        #expect(state.dock)
        state.set(pinned: false)
        #expect(!state.pinned && !state.shown)
    }

    /// Night, over a light page (R4.4): Daily brief keeps its light colours under the dark app. The names stay readable
    /// on the tint alone, the worst case a picture can draw: over the page, unblurred. The tint is 74 % over 50 % black.
    @Test("r4-4: Night, over a light page") func r4_4() async throws {
        let stage = try Stage("shell-r4-4")
        defer { stage.remove() }
        let (shell, library, brief) = try await Self.calm(stage)
        defer { brief.close() }
        shell.drawer.open()
        #expect(await wait(until: { shell.drawer.card.minX == Drawer.margin }))
        library.sidebar.hovered = .space("logbook")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "r4-4" + suffix, root: stage.home.root, page: NSAppearance(named: .aqua))
        }
        try await Stage.alone {
            NSApp.appearance = NSAppearance(named: .darkAqua)
            #expect(await wait(until: { shell.window.effectiveAppearance.name == .darkAqua }))
            let words = try await Picture.lines(try stage.sidebar(shell)).map(\.words)
            for line in ["Spaces", "Needs You", "Logbook", "Oracle", "Templates"] { #expect(words.contains { $0.contains(line) }, "\(line): \(words)") }
        }
    }
    @Test("f3-1: What waits, the drawer closed: dot, count, ⌘P", .disabled("not built yet: AG8")) func f3_1() async throws {}
    @Test("r5-1: Delete Group…, Undo", .disabled("not built yet: S4")) func r5_1() async throws {}
    @Test("r5-2: The root on top, Move to ▸ No Group", .disabled("not built yet: S4")) func r5_2() async throws {}
    /// R5.3, No Folder: the folder menu's row, said in the sentence, on the line sent to the assistant, and made once the
    /// build's space appears: the grant holds its blank folder, the agent chosen, and `launch` narrowed to it.
    @Test("r5-3: No Folder") func r5_3() async throws {
        let stage = try Stage("build")
        defer { stage.remove() }
        let (shell, library, _) = try await AcceptanceBuild.newSpace(stage, builder: true)
        Stage.work(library)
        shell.waiting([], mine: 0)
        let model = shell.assistant
        model.engine.update(outside: Stage.world)
        model.draft = BlankView.chips[0].1
        model.chosenLevel = .run
        (model.runFolder, model.chosenStart) = (.path(stage.home.root.appendingPathComponent("code/shop").path), Grant.Start(kind: "claude"))
        let row = try #require(AcceptanceBuild.sentence(model).folderMenu.rows.first { $0.title == "No Folder" })
        #expect(row.note == "It starts in a blank folder of its own.\n~/something/agents" && row.on == false && row.apart)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "r5-3" + suffix, root: stage.home.root)
        }
        if let gallery { try AcceptanceBuild.text(AcceptanceBuild.sentence(model).folderMenu).write(to: gallery.appendingPathComponent("r5-3-menu.txt"), atomically: true, encoding: .utf8) }
        row.pick()
        #expect(model.runFolder == .blank)
        #expect(model.choice.line(home: "/Users/example") == "[something] With your agents: Run, starts Claude Code, in a blank folder of its own.")
        model.send("A page for my mornings.")
        #expect(model.before?.choice.folder == .blank && model.chosenLevel == nil && model.chosenStart == nil)
        #expect(await wait(until: { !model.building }))
        await AcceptanceBuild.finish(model)
    }
    @Test("f3-3: Halo, rise, fade", .disabled("not built yet: S10")) func f3_3() async throws {}
    @Test("f6-2: Import, checked first", .disabled("not built yet: C9")) func f6_2() async throws {}
    @Test("f6-2b: A file dropped on the window", .disabled("not built yet: C9")) func f6_2b() async throws {}
    @Test("f6-3: The white tile", .disabled("not built yet: FIN3")) func f6_3() async throws {}
}
