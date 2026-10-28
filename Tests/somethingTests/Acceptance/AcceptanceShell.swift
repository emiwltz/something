// Acceptance scenarios of the window around the spaces: the frame, the sidebar and its groups, full screen and the rail
// (b1, b3, b5–b7; b2, La page, waits for Emi; b8, the rows' eyes, left with v6.2), the word "space" explained (x1-2),
// Info in three parts (x5-1 to x5-3, which retired b4), and round 2's calm window: the toolbar and Needs You (x9-1),
// the list of names and the rail's letter tiles (x9-2), finding a space in the rail (j4-1). It also draws the frame of
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
        #expect(shell.split.splitViewItems.count == 3 && shell.inspector.isCollapsed)
        #expect(shell.window.toolbar?.items.map(\.itemIdentifier) == [.flexibleSpace, Shell.sidebar, .sidebarTrackingSeparator, Shell.title,
                                                                       .flexibleSpace, Shell.tools])
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
        let host = try #require(shell.split.splitViewItems[0].viewController as? NSHostingController<SidebarView>)
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
        #expect(labels == ["Daily brief, Working", "My agents, Waiting for you", "Project watch, Ready", "Logbook, Asleep", "Oracle, Ready",
                           "Pebble, Done", "Stack, Asleep"], "\(labels)")
        let drawn = try stage.drawn(shell)
        // Vision may read the f of "brief" as a t beside "pages of your own": the title's start is enough.
        for line in ["Needs You", "Agents", "Notes", "Breaks", "Daily bri", "Pebble", "Stack", "Templates"] {
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
        // Folded, Agents hides its rows, My agents too, which Needs You still lists.
        library.preferences.fold("Agents", true)
        #expect(library.label(group: "Agents", count: 3) == "Agents, 3 spaces, folded")
        let folded = try stage.drawn(shell)
        #expect(folded.filter { $0.contains("My agents") }.count == 1 && !folded.contains { $0.contains("Project watch") }, "\(folded)")
        library.preferences.fold("Agents", false)
    }
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
        shell.waiting(["agents"], mine: 0)
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
        let menu = SidebarMenu.text(library.menu(for: row))
        #expect(menu == ["Open", "Show Info  ⌘I", "Rename…", "Show in Group  ▸", "  Agents  ✓  (dimmed)", "  Notes", "  Breaks", "  —",
                         "  New Group…", "  (Groups are only in the sidebar. The file does not move.)", "—", "Show in Finder", "Export", "—",
                         "Move to Trash…  (red)"])
        if let gallery {
            try FileManager.default.createDirectory(at: gallery, withIntermediateDirectories: true)
            try (menu.joined(separator: "\n") + "\n").write(to: gallery.appendingPathComponent("b3-menu.txt"), atomically: true, encoding: .utf8)
        }
        let drawn = try stage.drawn(shell)
        for line in ["Agents", "Notes", "Breaks", "Daily bri", "Project watch", "Oracle"] {
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
    /// Full screen (W5): the system hides the toolbar with the menu bar; the sidebar steps aside and the space starts
    /// at the window's top; ⌃⌘S lays the sidebar over the space, and Esc, a click outside or a space picked takes it
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
        let side = shell.split.splitViewItems[0], height = Stage.Size.main.height
        func top() -> CGFloat? { shell.shown.map { $0.convert($0.bounds, to: nil).maxY } }
        shell.window.layoutIfNeeded()
        #expect(top() == shell.window.contentLayoutRect.maxY && shell.window.contentLayoutRect.maxY < height, "under the toolbar")
        shell.fullScreen(true)
        shell.window.layoutIfNeeded()
        #expect(shell.full && side.isCollapsed && shell.space === brief)
        #expect(top() == height && brief.web.frame.width == Stage.Size.main.width, "the space alone, from the window's top")
        #expect(shell.controls[Shell.full]?.image?.accessibilityDescription == "Exit Full Screen", "until the page's own mode (S6)")
        // ⌃⌘S lays the sidebar over the space, its column still away; it takes the keys, and gives them back.
        func over() -> SidebarOver? { SidebarOver.shown(in: shell.layer) }
        shell.window.makeFirstResponder(brief.web)
        shell.split.toggleSidebar(nil)
        let laid = try #require(over())
        // It arrives from the window's edge.
        _ = await wait(until: { laid.alphaValue == 1 })
        laid.layoutSubtreeIfNeeded()
        #expect(side.isCollapsed && laid.card.frame == NSRect(x: 0, y: 0, width: SidebarOver.width, height: height), "\(laid.card.frame)")
        #expect(laid.accessibilityLabel() == "Sidebar" && shell.window.firstResponder === laid.card)
        #expect(shell.layer.hitTest(NSPoint(x: 600, y: 300)) === laid, "a click outside lands on the layer, which closes it")
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: shell.window.windowNumber,
                                                   context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        #expect(shell.escape(escape) && over() == nil && shell.window.firstResponder === brief.web, "Esc")
        shell.split.toggleSidebar(nil)
        shell.split.toggleSidebar(nil)
        #expect(over() == nil, "⌃⌘S again")
        shell.split.toggleSidebar(nil)
        let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 600, y: 300), modifierFlags: [], timestamp: 0,
                                                    windowNumber: shell.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        try #require(over()).mouseDown(with: click)
        #expect(over() == nil, "a click outside")
        shell.split.toggleSidebar(nil)
        shell.show(brief)
        #expect(over() == nil, "a space picked")
        shell.window.toolbar?.isVisible = false
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { shell.window.standardWindowButton($0)?.isHidden = true }
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "b5" + suffix, root: stage.home.root, keyed: false)
            shell.split.toggleSidebar(nil)
            try await Picture.window(shell, library: library, web: brief.web, "b5-sidebar" + suffix, root: stage.home.root, keyed: false)
            #expect(SidebarOver.close(in: shell.layer))
        }
        shell.window.toolbar?.isVisible = true
        // Out of full screen, the sidebar comes back as it was, the space under the toolbar, and ⌃⌘S hides the column.
        shell.fullScreen(false)
        shell.window.layoutIfNeeded()
        #expect(!shell.full && !side.isCollapsed && top() == shell.window.contentLayoutRect.maxY)
        shell.split.toggleSidebar(nil)
        #expect(over() == nil)
        #expect(await wait(until: { side.isCollapsed }), "the column hides")
        shell.fullScreen(true)
        shell.fullScreen(false)
        #expect(side.isCollapsed, "a sidebar hidden before stays hidden after")
    }
    /// No space yet (W2, the center AB12's): the sidebar says only where the spaces will be, New Space selected.
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
        let drawn = try stage.drawn(shell)
        #expect(drawn.contains { $0.contains("Your spaces appear here") }, "the drawn sidebar says where the spaces will be: \(drawn)")
        #expect(!drawn.contains { ["Agents", "Notes", "Breaks"].contains(where: $0.contains) }, "no group header is drawn: \(drawn)")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "b6" + suffix, root: stage.home.root)
        }
    }

    /// The narrow window (W6), 760 by 680: the sidebar is a 64-point rail, one button per space in the sidebar's order
    /// saying "Title, state", folded groups too, a line between groups; the toolbar's toggle goes. ⌃⌘S lays the whole
    /// sidebar over the space under the toolbar. Below 860 points the window takes the rail and keeps it until 880; the
    /// sidebar then comes back as it was. Its letter tiles are x9-2's.
    @Test("b7: the rail") func b7() async throws {
        let stage = try Stage("shell-b7")
        defer { stage.remove() }
        let (shell, library, _) = stage.window(NSSize(width: 760, height: 680))
        library.preferences.groups = Stage.groups.map { Preferences.Group(name: $0.0, spaces: $0.1) }
        library.preferences.fold("Breaks", true)
        library.relist()
        try Self.eyes(shell, Stage.moment)
        shell.waiting(["agents"], mine: 0)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        let side = shell.split.splitViewItems[0], host = side.viewController.view
        shell.window.layoutIfNeeded()
        #expect(shell.rail && library.sidebar.rail && !side.isCollapsed && host.frame.width == Rail.width, "\(host.frame)")
        #expect(shell.window.toolbar?.items.map(\.itemIdentifier) == [Shell.title, .flexibleSpace, Shell.tools], "the rail has its own toggle")
        #expect(shell.titleLine.line.string == "Daily brief")
        // One button per space, in the sidebar's order, Breaks' rows too though it is folded; each says its title and
        // state, and under the pointer its name and state.
        let order = library.order()
        let spaces = order.map { Library.label($0, Stage.moment[$0.id] ?? .sleep) }
        let fixed = ["Show Sidebar", "New Space", "Go to…", "New Group", "Templates", "Settings"]
        let said = await AcceptanceBuild.read(host) { words in (spaces + fixed).allSatisfy(words.contains) }
        #expect(said.filter((spaces + fixed).contains) == Array(fixed.prefix(4)) + spaces + fixed.suffix(2), "\(said)")
        // ↑ and ↓ go through New Space and every space, no header.
        #expect(library.step(1) == .space("agents") && library.step(-1) == .space("brief") && library.sidebar.cursor == nil)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "b7" + suffix, root: stage.home.root)
        }
        // ⌃⌘S, and the rail's toggle, lay the whole sidebar over the space, under the toolbar; Esc takes it away. The
        // menu item stays on beside the rail, whose column cannot collapse, and goes the person's way: the responder
        // chain from the window, to its delegate.
        let action = try #require(Keys.command("sidebar")?.action)
        let item = NSMenuItem(title: "Hide Sidebar", action: action, keyEquivalent: "s")
        // Nothing in the split view has the focus: the menu picks the first in the window's responder chain that
        // answers (the test's window is never key, so NSApp's own search would find nothing), the window itself.
        shell.window.makeFirstResponder(nil)
        var target = shell.window.firstResponder
        while let responder = target, !responder.responds(to: action) { target = responder.nextResponder }
        #expect(target === shell.window)
        let validated = { (target as? NSMenuItemValidation)?.validateMenuItem(item) == true }
        #expect(validated() && item.title == "Show Sidebar")
        #expect(NSApp.sendAction(action, to: target, from: item))
        let laid = try #require(SidebarOver.shown(in: shell.layer))
        #expect(validated() && item.title == "Hide Sidebar")
        _ = await wait(until: { laid.alphaValue == 1 })
        laid.layoutSubtreeIfNeeded()
        let band = shell.window.frame.height - shell.window.contentLayoutRect.maxY
        #expect(laid.card.frame == NSRect(x: 0, y: 0, width: SidebarOver.width, height: 680 - band), "\(laid.card.frame)")
        #expect(shell.rail && !side.isCollapsed && shell.window.firstResponder === laid.card)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "b7-sidebar" + suffix, root: stage.home.root)
        }
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: shell.window.windowNumber,
                                                   context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        #expect(shell.escape(escape) && SidebarOver.shown(in: shell.layer) == nil)
        // The line, both ways: 20 points of hysteresis.
        shell.window.setContentSize(NSSize(width: 870, height: 680))
        #expect(shell.rail, "still the rail at 870")
        shell.window.setContentSize(NSSize(width: 880, height: 680))
        shell.window.layoutIfNeeded()
        #expect(!shell.rail && !library.sidebar.rail && host.frame.width == 236, "\(host.frame)")
        #expect(shell.window.toolbar?.items.map(\.itemIdentifier) == Shell.head + [Shell.title, .flexibleSpace, Shell.tools])
        shell.window.setContentSize(NSSize(width: 870, height: 680))
        #expect(!shell.rail, "still the sidebar at 870")
        // A sidebar hidden before the window narrows is the rail all the same, and hidden again once it widens.
        side.isCollapsed = true
        shell.window.setContentSize(NSSize(width: 800, height: 680))
        #expect(shell.rail && !side.isCollapsed)
        shell.window.setContentSize(Stage.Size.main)
        #expect(!shell.rail && side.isCollapsed)
        // Full screen never has the rail.
        side.isCollapsed = false
        shell.window.setContentSize(NSSize(width: 800, height: 680))
        shell.fullScreen(true)
        #expect(!shell.rail && side.isCollapsed)
        shell.fullScreen(false)
        #expect(shell.rail && !side.isCollapsed)
    }

    /// The mockup's window for round 2 (X9.1, X9.2, J4.1): its groups (Work, Notes, Breaks), Daily brief open, My
    /// agents waiting for the answer to its request, the rows' states at the mockup's moment.
    static func calm(_ stage: Stage, _ size: NSSize = Stage.Size.main) async throws -> (Shell, Library, SpaceView) {
        let (shell, library, _) = stage.window(size)
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
        #expect(shell.window.toolbar?.items.map(\.itemIdentifier) == Shell.head + [Shell.title, .flexibleSpace, Shell.tools])
        #expect(shell.toolbarItems.suffix(3).map(\.itemIdentifier) == [Shell.point, Shell.info, Shell.full])
        #expect(shell.toolbarItems.allSatisfy { !["reload", "chip"].contains($0.itemIdentifier.rawValue) })
        let title = shell.titleLine
        #expect(title.line.string == "Daily brief" && shell.window.subtitle == "" && title.accessibilityLabel() == "Daily brief")
        #expect(title.accessibilityRole() == .button && title.toolTip == "Show Info (⌘I)")
        let labels = [Shell.point, Shell.info, Shell.full].map { shell.controls[$0]?.image?.accessibilityDescription }
        #expect(labels == ["Point", "Info", "Page Full Screen"], "\(labels)")
        // The name opens Info, as ⌘I: the button pressed, View's item says Hide Info; again, it closes.
        #expect(shell.infoWords == "Show Info" && title.accessibilityPerformPress())
        #expect(shell.infoShown && (shell.controls[Shell.info] as? ToolButton)?.pressed == true && shell.infoWords == "Hide Info")
        #expect(title.accessibilityPerformPress() && !shell.infoShown && (shell.controls[Shell.info] as? ToolButton)?.pressed == false)
        // Needs You, then the groups; My agents in both, so ⌘1–9 keep the groups' order.
        #expect(library.needing().map(\.title) == ["My agents"] && library.sections().map(\.group) == ["Work", "Notes", "Breaks"])
        #expect(library.order().map(\.title) == ["Daily brief", "My agents", "Project watch", "Logbook", "Oracle", "Pebble", "Stack"])
        let host = shell.split.splitViewItems[0].viewController.view
        let read = await AcceptanceBuild.read(host) { $0.contains("Needs You, 1 space") && $0.contains("Stack, Asleep") }
        let rows = read.filter { $0.contains(", ") && !$0.lowercased().contains("space") }
        #expect(rows == ["My agents, Waiting for you", "Daily brief, Working", "My agents, Waiting for you", "Project watch, Ready",
                         "Logbook, Asleep", "Oracle, Ready", "Pebble, Done", "Stack, Asleep"], "\(read)")
        #expect(read.contains("Needs You, 1 space") && read.contains("Work, 3 spaces, open") && read.contains("Settings"), "\(read)")
        let drawn = try stage.drawn(shell)
        for line in ["Needs You", "Work", "Daily brief", "Project watch", "Templates", "something"] {
            #expect(drawn.contains { $0.contains(line) }, "the drawn sidebar shows \(line): \(drawn)")
        }
        #expect(drawn.filter { $0.contains("My agents") }.count == 2, "\(drawn)")
        // The View menu, Daily brief open, the sidebar shown: each item says what it does; Reload is here only.
        let bar = MenuBar(builders: nil)
        let view = try #require(bar.submenu("View")), space = try #require(bar.submenu("Space"))
        let sidebar = try #require(view.items.first { $0.identifier?.rawValue == "sidebar" })
        shell.window.makeFirstResponder(nil)
        #expect(shell.window.validateMenuItem(sidebar) && sidebar.title == "Hide Sidebar")
        // The Info items, in View and Space, are named as the app's validation names them: Show, then Hide while Info shows.
        let infos = [view, space].compactMap { menu in menu.items.first { $0.identifier?.rawValue == "insp" } }
        #expect(infos.count == 2)
        shell.showInfo(true)
        infos.forEach(shell.retitle)
        #expect(infos.allSatisfy { $0.title == "Hide Info" }, "\(infos.map(\.title))")
        shell.showInfo(false)
        infos.forEach(shell.retitle)
        let lines = Mockup.lines(view)
        #expect(lines == ["Hide Sidebar  ⌃⌘S", "Show Info  ⌘I", "---", "Show History…", "Show Keyboard Shortcuts  ⌘/", "---", "Reload Space  ⌘R", "---",
                          "Enter Full Screen  ⌃⌘F"], "\(lines)")
        #expect(!space.items.contains { $0.identifier?.rawValue == "reload" }, "Reload lives in View only")
        if let gallery {
            try FileManager.default.createDirectory(at: gallery, withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n").write(to: gallery.appendingPathComponent("x9-1-view.txt"), atomically: true, encoding: .utf8)
        }
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "x9-1" + suffix, root: stage.home.root)
        }
        // Hidden, the sidebar's item says Show Sidebar; the request answered, Needs You goes.
        shell.split.splitViewItems[0].isCollapsed = true
        #expect(shell.window.validateMenuItem(sidebar) && sidebar.title == "Show Sidebar")
        shell.split.splitViewItems[0].isCollapsed = false
        shell.waiting([], mine: 0)
        #expect(library.needing().isEmpty)
        let after = await AcceptanceBuild.read(host) { !$0.contains("Needs You, 1 space") && $0.contains("Stack, Asleep") }
        #expect(!after.contains("Needs You, 1 space"), "\(after)")
    }

    /// The list of names in the narrow window (S5, X9.2), 760 by 680: the rail's tiles, a letter on the colour of
    /// each space's name, in the sidebar's order, Daily brief's ringed; no eyes. Each tile says "Title, state" to
    /// VoiceOver and "Title · state" under the pointer; the toolbar is the calm one.
    @Test("x9-2: the list of names") func x9_2() async throws {
        let stage = try Stage("shell-x9-2")
        defer { stage.remove() }
        let (shell, library, brief) = try await Self.calm(stage, NSSize(width: 760, height: 680))
        defer { brief.close() }
        let host = shell.split.splitViewItems[0].viewController.view
        shell.window.layoutIfNeeded()
        #expect(shell.rail && host.frame.width == Rail.width)
        #expect(shell.window.toolbar?.items.map(\.itemIdentifier) == [Shell.title, .flexibleSpace, Shell.tools])
        let order = library.order()
        #expect(order.map { Rail.letter($0.title) } == ["D", "M", "P", "L", "O", "P", "S"])
        #expect(order.map { Rail.tip($0, Stage.moment[$0.id] ?? .sleep) }.first == "Daily brief · Working")
        // Neighbours of a group never share a colour here.
        for section in library.sections() {
            let tones = section.entries.map { Look.tile($0.id) }
            #expect(zip(tones, tones.dropFirst()).allSatisfy { $0 != $1 }, "\(section.group ?? "")")
        }
        let spaces = order.map { Library.label($0, Stage.moment[$0.id] ?? .sleep) }
        let said = await AcceptanceBuild.read(host) { words in spaces.allSatisfy(words.contains) }
        #expect(said.filter(spaces.contains) == spaces && !said.contains("Needs You"), "\(said)")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "x9-2" + suffix, root: stage.home.root)
        }
    }

    /// Finding a space in the narrow window (S5, J4.1): the pointer over My agents' tile, whose assistant waits: the
    /// tile lit, its tooltip its name and state (a tooltip cannot be drawn offscreen: its words are checked). The
    /// sidebar laid over by ⌃⌘S shows Needs You first.
    @Test("j4-1: find your spaces") func j4_1() async throws {
        let stage = try Stage("shell-j4-1")
        defer { stage.remove() }
        let (shell, library, brief) = try await Self.calm(stage, NSSize(width: 760, height: 680))
        defer { brief.close() }
        let agents = try #require(library.entry("agents"))
        #expect(Rail.tip(agents, .wait) == "My agents · Waiting for you" && Library.label(agents, .wait) == "My agents, Waiting for you")
        library.sidebar.hovered = .space("agents")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "j4-1" + suffix, root: stage.home.root)
        }
        library.sidebar.hovered = nil
        shell.split.toggleSidebar(nil)
        let laid = try #require(SidebarOver.shown(in: shell.layer))
        _ = await wait(until: { laid.alphaValue == 1 })
        let said = await AcceptanceBuild.read(laid) { $0.contains("Needs You, 1 space") }
        let first = said.firstIndex(of: "Needs You, 1 space"), work = said.firstIndex(of: "Work, 3 spaces, open")
        #expect(first != nil && work != nil && (first ?? 0) < (work ?? 0), "Needs You over the groups: \(said)")
        #expect(SidebarOver.close(in: shell.layer))
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
        let drawn = try stage.drawn(shell)
        #expect(drawn.contains { $0.contains("pages of your own") }, "the drawn sidebar explains the word: \(drawn)")
        let side = try #require(shell.split.splitViewItems[0].viewController as? NSHostingController<SidebarView>)
        let said = await AcceptanceBuild.read(side.view) { $0.contains("Spaces, pages of your own") }
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
          body { margin: 0; min-height: 100vh; box-sizing: border-box; padding: 56px 60px; color: #fff; font: 15px -apple-system, sans-serif;
                 background: linear-gradient(180deg, #2b3363 0%, #5f4a86 40%, #c27587 68%, #f2a676 100%); }
          small { letter-spacing: .18em; font-size: 11.5px; font-weight: 600; opacity: .85; }
          .count { font: 300 92px Georgia, serif; margin: 10px 0 0; letter-spacing: -.02em; }
          h2 { font: 600 24px Georgia, serif; margin: 26px 0 30px; }
          .cards { display: flex; gap: 18px; flex-wrap: wrap; }
          .card { width: 230px; padding: 20px; border-radius: 14px; background: rgba(255, 255, 255, .92); color: #3a2b45; }
          .card.dark { background: rgba(60, 40, 80, .5); color: #fff; }
          .card p { margin: 10px 0 0; line-height: 1.45; }
        </style></head><body>
        <small>UNTIL THE WEEKEND</small><div class="count">1 05 40</div><h2>Saturday 24 October.</h2>
        <div class="cards"><div class="card"><small>SATURDAY PLANS</small><p>Market at nine. Call the bike shop.</p></div>
        <div class="card dark"><small>BEFORE SATURDAY</small><p id="list">No agent shown.</p></div></div>
        <script>
          const list = document.getElementById("list");
          const render = (state) => { const shown = (state.agents || []).filter((a) => a.kind !== "other");
            list.textContent = shown.length ? shown.map((a) => `${a.name}: ${a.state}`).join(" · ") : "No agent shown."; };
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
        // Its page's own card hears them before any picture is drawn.
        for _ in 0..<100 {
            if (try? await run(view, "return document.getElementById('list').textContent") as? String)?.contains("atelier") == true { break }
            await wait(0.05)
        }
        shell.layer.announce = { _ in }
        (info.current, info.clock) = ({ view }, { Stage.local })
        info.show(view.space)
        shell.showInfo(true)
        shell.window.layoutIfNeeded()
        return (shell, library, info, view)
    }

    /// The lines of text Info shows, read off its picture by Vision, as tall as the window's center.
    static func drawnInfo(_ shell: Shell) throws -> [String] {
        let controller = try #require(shell.inspector.viewController as? InfoController)
        let offscreen = Offscreen(NSHostingView(rootView: controller.rootView))
        offscreen.window.setContentSize(NSSize(width: 320, height: shell.window.contentLayoutRect.height))
        offscreen.view.layoutSubtreeIfNeeded()
        let rep = try #require(offscreen.view.bitmapImageRepForCachingDisplay(in: offscreen.view.bounds))
        offscreen.view.cacheDisplay(in: offscreen.view.bounds, to: rep)
        return try Picture.text(rep)
    }

    /// One panel, three parts (X5.1): Space (its file, Show in Finder, its weight and last change, Export, History),
    /// Your agents (the level, its sentence, the agents its page shows now, what still waits for you) and Assistant
    /// (its eyes, the agent and model, its last reply, Open Conversation); Move to Trash… quiet at the foot. No switch,
    /// no About, no Activity. ⌘I and ✕ close it, and Esc in it; Open Conversation opens the card on its conversation.
    @Test("x5-1: Info in one place") func x5_1() async throws {
        let stage = try Stage("shell-x5-1")
        defer { stage.remove() }
        let (shell, library, info, view) = try await AcceptanceShell.weekend(stage)
        defer { view.close() }
        let center = shell.center.frame.width + 320, docked = shell.inspector.viewController.view.frame
        #expect(shell.infoShown && info.content == .info && (shell.controls[Shell.info] as? ToolButton)?.pressed == true)
        #expect(docked.width == 320 && view.web.frame.width == center - 320)
        #expect(info.level == .watch && info.folder == nil && info.about == "A countdown to Saturday, your plans, and what your agents still have to finish.")
        #expect(Info.weight(try #require(info.size), form: .file, changed: info.changed, now: Stage.local).hasSuffix("one file · changed today, 18:04"))
        // The agents its page sees: X5's, all of them, as its page receives them, each with what it did last.
        #expect(Set(info.shown.map(\.id)) == Set(Self.weekendWorld(stage.home.places.home).agents.map(\.id)), "\(info.shown.map(\.id))")
        #expect(Set(info.shown.map(info.doing)) == ["working: Write the login form", "waits for you: Run the tests?", "idle since 16:10"],
                "\(info.shown.map(info.doing))")
        var unknown = Agent(id: "other-1", kind: "other", origin: "elsewhere")
        unknown.state = "unknown"
        #expect(Info.doing(unknown) == "state unknown", "the unknown is said")
        // As VoiceOver reads the panel: every button named, the three parts, the level as one choice of four.
        let panel = shell.inspector.viewController.view
        let tree = await AccessibilityTests.walk(panel), read = tree.words
        #expect(tree.unnamed.isEmpty, "\(tree.unnamed)")
        for words in ["Week-end", "Close Info", "Space", "Show in Finder", "Export", "History", "Your agents", "With your agents: Watch",
                      "The agents it shows now", "Assistant", "Its assistant: Asleep", "Open Conversation", "Move to Trash…"] {
            #expect(read.contains(words), "the panel reads \(words): \(read)")
        }
        #expect(read.filter { ["Space", "Your agents", "Assistant"].contains($0) }.count == 3, "three parts: \(read)")
        for gone in ["What it may do", "Versions", "About", "Activity", "Group", "Put to Sleep", "New Conversation", "Ask Again", "Export…", "Show Request"] {
            #expect(!read.contains { $0.hasPrefix(gone) }, "Info no longer holds \(gone)")
        }
        // Its sentences, as the panel draws them (offscreen, SwiftUI gives a text no element of its own).
        let drawn = try AcceptanceShell.drawnInfo(shell).joined(separator: " ")
        // Vision reads a middle dot as a bullet: the words around it are enough.
        for words in ["A countdown to Saturday", "~/something/spaces/week-end.html", "one file", "changed today, 18:04", "It sees your agents",
                      "Amp waits for you", "Claude Code working", "Codex idle since 16:10", "~/code/shop", "Whatever an agent asks still waits for you", "Claude Code",
                      "Week-end is ready. It counts down to"] {
            #expect(drawn.contains(words), "the panel shows \(words): \(drawn)")
        }
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: view.web, "x5-1" + suffix, root: stage.home.root)
        }
        // Esc with the focus in the panel closes it; ⌘I opens it again and closes it; ✕ too.
        #expect(shell.window.makeFirstResponder(panel.subviews.first ?? panel))
        shell.window.firstResponder?.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        shell.window.layoutIfNeeded()
        #expect(!shell.infoShown && view.web.frame.width == center && (shell.controls[Shell.info] as? ToolButton)?.pressed == false)
        let command = try #require(Keys.command("insp"))
        #expect(command.action == #selector(App.toggleInfo(_:)) && command.key == "i")
        shell.toggleInfo(spaceOpen: false)
        #expect(!shell.infoShown, "⌘I opens nothing while no space is open")
        shell.toggleInfo(spaceOpen: true)
        #expect(shell.infoShown && info.content == .info)
        shell.toggleInfo(spaceOpen: true)
        #expect(!shell.infoShown)
        shell.toggleInfo(spaceOpen: true)
        info.close()
        #expect(!shell.infoShown, "✕")
        // Open Conversation: the panel goes, the card opens on its conversation.
        shell.showInfo(true)
        info.converse()
        #expect(!shell.infoShown && shell.assistant.open && shell.assistant.threadShown)
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
        let panel = shell.inspector.viewController.view
        let none = await AcceptanceBuild.read(panel) { !$0.contains("The agents it shows now") && $0.contains("Watch") }
        #expect(!none.contains("The agents it shows now"), "\(none)")
        #expect(try AcceptanceShell.drawnInfo(shell).joined(separator: " ").contains("It shows no agent."))

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
        let running = await AcceptanceBuild.read(panel) { $0.contains("The agents it shows now") }
        #expect(running.contains("The agents it shows now"), "\(running)")
        let drawn = try AcceptanceShell.drawnInfo(shell).joined(separator: " ")
        for words in ["It sees them, writes to them", "Starts them in", "~/code/shop"] {
            #expect(drawn.contains(words), "the panel shows \(words): \(drawn)")
        }
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: view.web, "x5-2" + suffix, root: stage.home.root)
        }
        // Back to Watch: the folder goes with Run, and Run asks again only when nothing tells it where.
        info.choose(.watch)
        #expect(info.level == .watch && info.folder == nil && picks == 1)
    }

    /// Export in one click (X5.3): one .something file in Downloads, without its memory until the person can choose to
    /// include it, no sheet; the toast says where with Show. History beside it opens the versions in Info's place.
    @Test("x5-3: Export in one click") func x5_3() async throws {
        let stage = try Stage("shell-x5-3")
        defer { stage.remove() }
        let (shell, library, info, view) = try await AcceptanceShell.weekend(stage)
        defer { view.close() }
        try Memory(folder: stage.home.places.data, space: "week-end").set("plans", "Market at nine.")
        var revealed: [URL] = []
        library.reveal = { revealed.append($0) }
        let command = try #require(Keys.command("export"))
        #expect(command.title == "Export Space" && command.key == "e" && command.action == #selector(App.exportSpace(_:)))
        // The toast in place at once, so that the pictures show it whole.
        library.preferences.motion = .reduced
        library.export("week-end")
        let file = stage.home.places.downloads.appendingPathComponent("week-end.something")
        let exported = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(exported["name"] as? String == "week-end" && exported["data"] is NSNull, "its memory stays on the Mac")
        let ask = try #require(view.ask as? FakeAsk)
        #expect(ask.told.isEmpty && ask.folderMessages.isEmpty, "no sheet, no panel: \(ask.told)")
        let toast = try #require(shell.layer.subviews.compactMap { $0 as? Toast }.last)
        #expect(toast.words == "week-end.something is in Downloads · its memory stays on this Mac")
        func buttons(_ view: NSView) -> [NSButton] { [view as? NSButton].compactMap { $0 } + view.subviews.flatMap(buttons) }
        let show = try #require(buttons(toast).first { $0.title == "Show" })
        show.performClick(nil)
        #expect(revealed == [file])
        // The pictures take longer than the toast stays: the same words held for them, as b1-frame-toast does.
        try await stage.appearances { suffix in
            let held = shell.toast(toast.words, action: Toast.Action(label: "Show") {}, seconds: 60)
            try await Picture.window(shell, library: library, web: view.web, "x5-3" + suffix, root: stage.home.root)
            #expect(held.shown && held.superview != nil, "the toast is in the picture")
            held.leave(now: true)
        }
        // History, beside Export: the versions in Info's place.
        info.showHistory()
        #expect(shell.infoShown && info.content == .history)
    }
}
