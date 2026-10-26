// Acceptance scenarios of the window around the spaces: the frame, the sidebar and its groups, Info, full screen, the rail and the
// rows' eyes (b1, b3–b8; b2, La page, waits for Emi). It also draws the frame of b1 alone, with and without a toast,
// and a long title in a narrow window.
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
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

    /// Gives the rows of `shell` the eyes of `states`, as the sessions would; a space it does not name is asleep.
    static func eyes(_ shell: Shell, _ states: [String: Sign.State]) throws {
        let host = try #require(shell.split.splitViewItems[0].viewController as? NSHostingController<SidebarView>)
        host.rootView = SidebarView(library: host.rootView.library, assistant: host.rootView.assistant, eyes: { states[$0] ?? .sleep })
    }

    /// The window of every day (W1–W3): the groups open, each row with its assistant's eyes at the mockup's moment,
    /// Daily brief open, the chip counting the one request. A folded group shows its most urgent eyes; Go lists the
    /// spaces with the same eyes and words; the Settings switch hides the rows' eyes, their words staying for VoiceOver.
    @Test("b1: the window") func b1() async throws {
        let stage = try Stage("shell-b1")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        library.preferences.groups = Stage.groups.map { Preferences.Group(name: $0.0, spaces: $0.1) }
        library.relist()
        try Self.eyes(shell, Stage.moment)
        shell.waiting(1, mine: 0)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        let chip = try #require(shell.window.toolbar?.items.first { $0.itemIdentifier == Shell.chip })
        #expect(!chip.isHidden && shell.chip.accessibilityLabel() == "1 waits for you" && shell.chip.action == #selector(App.chipClicked(_:)))
        #expect(library.sections().allSatisfy { $0.group.map(library.folded) == false })
        let labels = library.order().map { Library.label($0, Stage.moment[$0.id] ?? .unknown) }
        #expect(labels == ["Daily brief, Working", "My agents, Waiting for you", "Project watch, Ready", "Logbook, Asleep", "Oracle, Ready",
                           "Pebble, Done", "Stack, Asleep"], "\(labels)")
        let drawn = try stage.drawn(shell)
        for line in ["Agents", "Notes", "Breaks", "Daily brief", "Pebble", "Stack", "Templates"] {
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
        // Folded, Agents shows its most urgent eyes, waiting before working, and says so.
        library.preferences.fold("Agents", true)
        let urgent = Library.urgent(library.sections()[0].entries.map { Stage.moment[$0.id] ?? .unknown })
        #expect(urgent == .wait && library.label(group: "Agents", count: 3, urgent: urgent) == "Agents, 3 spaces, folded, waiting for you")
        #expect(!(try stage.drawn(shell)).contains { $0.contains("My agents") })
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
    /// Info docked at full height beside My agents (W4), whose assistant waits for the request the chip counts: the
    /// panel is 320 points wide and the page narrows beside it, nothing under it; ✕, ⌘I and Esc close it at once.
    @Test("b4: Info docked full height") func b4() async throws {
        let stage = try Stage("shell-b4")
        defer { stage.remove() }
        try AcceptanceAssistant.fake(in: stage)
        let (shell, library, info) = stage.window()
        library.preferences.groups = Stage.groups.map { Preferences.Group(name: $0.0, spaces: $0.1) }
        library.relist()
        try stage.moment(shell)
        let model = shell.assistant, engine = model.engine
        engine.changed = { model.refresh() }
        engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        let agents = try await stage.open("agents", in: shell, library)
        defer { agents.close() }
        info.current = { agents }
        info.show(agents.space)
        model.send("Check that the counters match what the terminal says.")
        #expect(await wait(until: { model.presence.state == .wait }), "said: \(model.presence.word)")
        // The count comes from the real queue, as the chip's does: the request belongs to My agents.
        let source = FakePrompts()
        AcceptanceTrust.request("r", [0], in: source)
        let panels = AcceptanceTrust.panels(source, shell, open: "agents", assistant: "claude")
        panels.clock = { 100 }
        info.asks = { panels.queue.waiting.first { panels.queue.space($0) == "agents" }?.tool }
        panels.refresh()
        let center = shell.center.frame.width
        #expect(center == 1200 - 236 && agents.web.frame.width == center)
        shell.showInfo(true)
        shell.window.layoutIfNeeded()
        #expect(shell.infoShown && info.content == .info && (shell.controls[Shell.info] as? ToolButton)?.pressed == true)
        // Full height under the toolbar, which stays one band across the window, as the mockup draws it.
        let under = shell.window.contentLayoutRect.height, docked = shell.inspector.viewController.view.frame
        #expect(docked.width == 320 && docked.height == under && under > 700, "full height under the toolbar: \(docked.height) of \(under)")
        #expect(agents.web.frame.width == center - 320, "the page narrows beside Info: \(agents.web.frame.width)")
        #expect(info.space?.name == "agents" && info.waiting == 1 && model.place.space == "agents")
        #expect(model.messageCount == 2 && model.resumes && !model.canSleep)
        #expect(info.rights.map(\.right) == ["state", "send"] && info.rights.allSatisfy { $0.standing == .allowed } && info.answered != nil)
        #expect(library.preferences.group(of: "agents") == "Agents" && info.size?.files == 1 && info.made != nil && info.changed != nil)
        // As the panel is read: its assistant waiting, what its request asks, Show Request and never Allow (rule 2);
        // what it may do, allowed; its group.
        let panel = shell.inspector.viewController.view
        let read = await AcceptanceBuild.read(panel) { $0.contains { $0.hasPrefix("Show Request") } && $0.contains { $0.contains("Group: Agents") } }
        #expect(read.contains { $0.hasPrefix("Show Request") } && !read.contains { $0.range(of: #"\bAllow\b"#, options: .regularExpression) != nil }, "\(read)")
        let waits = "Waiting for you. It wants to run a command. Its request waits in a window of its own, outside the space."
        #expect(read.contains(waits), "\(read)")
        for words in ["See your agents", "Write to your agents", "Allowed", "Group: Agents", "Export…"] {
            #expect(read.contains { $0.contains(words) }, "the panel reads \(words): \(read)")
        }
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: agents.web, "b4" + suffix, root: stage.home.root)
        }
        // Answered: Show Request goes, and Put to Sleep follows only what the assistant can do.
        source.prompts = []
        panels.refresh()
        #expect(info.waiting == 0 && shell.chip.count == 0)
        let after = await AcceptanceBuild.read(panel) { !$0.contains { $0.hasPrefix("Show Request") } && $0.contains("Put to Sleep") }
        #expect(!after.contains { $0.hasPrefix("Show Request") } && after.contains("Put to Sleep"), "\(after)")
        // Esc with the focus in the panel goes up the responder chain to it: it closes, the page takes its width back.
        #expect(shell.window.makeFirstResponder(panel.subviews.first ?? panel))
        shell.window.firstResponder?.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        shell.window.layoutIfNeeded()
        #expect(!shell.infoShown && agents.web.frame.width == center && (shell.controls[Shell.info] as? ToolButton)?.pressed == false)
        // ⌘I opens it again, as the menu's command does, and closes it; ✕ closes it too.
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
        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })
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
        #expect(shell.controls[Shell.full]?.image?.accessibilityDescription == "Exit Full Screen")
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
    /// saying "Title, state", folded groups too, a line between groups; the toolbar's toggle goes, the title drops its
    /// file, the chip its words. ⌃⌘S lays the whole sidebar over the space under the toolbar. Below 860 points the
    /// window takes the rail and keeps it until 880; the sidebar then comes back as it was.
    @Test("b7: the rail") func b7() async throws {
        let stage = try Stage("shell-b7")
        defer { stage.remove() }
        let (shell, library, _) = stage.window(NSSize(width: 760, height: 680))
        library.preferences.groups = Stage.groups.map { Preferences.Group(name: $0.0, spaces: $0.1) }
        library.preferences.fold("Breaks", true)
        library.relist()
        try Self.eyes(shell, Stage.moment)
        shell.waiting(1, mine: 0)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        let side = shell.split.splitViewItems[0], host = side.viewController.view
        shell.window.layoutIfNeeded()
        #expect(shell.rail && library.sidebar.rail && !side.isCollapsed && host.frame.width == Rail.width, "\(host.frame)")
        #expect(shell.window.toolbar?.items.map(\.itemIdentifier) == [Shell.title, .flexibleSpace, Shell.chip, Shell.tools],
                "the rail has its own toggle")
        #expect(shell.titleLine.bare && shell.titleLine.shown.string == "Daily brief" && shell.window.subtitle == "brief.html")
        #expect(shell.chip.compact && shell.chip.accessibilityLabel() == "1 waits for you" && shell.chip.intrinsicContentSize.width < 50)
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
        #expect(!shell.rail && !library.sidebar.rail && host.frame.width == 236 && !shell.titleLine.bare && !shell.chip.compact, "\(host.frame)")
        #expect(shell.window.toolbar?.items.map(\.itemIdentifier) == Shell.head + [Shell.title, .flexibleSpace, Shell.chip, Shell.tools])
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

    /// Several assistants at work, Logbook open (W3): Project watch starts working, Daily brief finishes, Oracle asks;
    /// the rows' eyes follow, the chip and the panel count both requests, the whole Mac's, and Logbook's sticker shows no
    /// badge, since none is its own. The chip's menu lists the assistants by state; nothing in it answers.
    @Test("b8: rows with their eyes") func b8() async throws {
        let stage = try Stage("shell-b8")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        shell.window.setFrameOrigin(AcceptanceTrust.large)
        library.preferences.groups = Stage.groups.map { Preferences.Group(name: $0.0, spaces: $0.1) }
        library.relist()
        try Self.eyes(shell, Stage.moment)
        let logbook = try await stage.open("logbook", in: shell, library)
        defer { logbook.close() }
        let now = Stage.moment.merging(["project": .think, "brief": .done, "oracle": .wait]) { $1 }
        try Self.eyes(shell, now)
        let source = FakePrompts()
        AcceptanceTrust.request("r", [0, 0], in: source)
        let panels = AcceptanceTrust.panels(source, shell, open: "logbook")
        panels.queue.space = { ["a1": "agents", "a2": "oracle"][$0.agent] }
        panels.clock = { 100 }
        panels.refresh()
        shell.glass.motion = { .reduced }
        #expect(await wait(5) { shell.glass.grown == false && shell.glass.stickerShown })
        let panel = try #require(panels.panel)
        panel.place(beside: shell.window, screen: AcceptanceTrust.desk)
        #expect(shell.chip.count == 2 && shell.chip.accessibilityLabel() == "2 wait for you" && panel.position == "1 of 2")
        #expect(shell.glass.mine == 0 && shell.glass.sticker.badge.isHidden, "no request is Logbook's")
        let rows = library.order().filter(\.isSpace).map { ($0.id, $0.title, now[$0.id] ?? .unknown) }
        // The app's own mapping: every request the chip counts, a space no longer listed made nil.
        let spaces = panels.requestSpaces { library.entry($0) != nil }
        #expect(spaces.count == shell.chip.count && spaces == ["agents", "oracle"])
        #expect(panels.requestSpaces { _ in false } == [nil, nil])
        // The menu opens under the chip in a window, at the pointer when the toolbar's overflow sent the click.
        let placed = WaitingChip(), holder = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40), styleMask: [], backing: .buffered, defer: true)
        holder.isReleasedWhenClosed = false
        holder.contentView?.addSubview(placed)
        #expect(placed.menuPlace.1 === placed && WaitingChip().menuPlace.1 == nil)
        guard case .menu(let menu) = WaitingChip.goes(spaces, open: "logbook", assistants: rows) else {
            Issue.record("two requests open the menu")
            return
        }
        #expect(menu.items.map(\.title) == ["Assistants", "My agents", "Oracle", "Project watch", "Daily brief", "Pebble"])
        #expect(!menu.items.contains { $0.title.contains("Allow") || $0.title.contains("Deny") }, "the chip never answers")
        if let gallery {
            let lines = menu.items.map { $0.isSectionHeader ? "# " + $0.title : "[eyes] " + ($0.attributedTitle?.string.replacingOccurrences(of: "\t", with: "  ") ?? "") }
            try FileManager.default.createDirectory(at: gallery, withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n").write(to: gallery.appendingPathComponent("b8-chip-menu.txt"), atomically: true, encoding: .utf8)
        }
        // Drawn armed, as the mockup shows it: half a second after the request appeared.
        panel.clock = { 100 + RequestPanel.arming }
        panel.tick()
        #expect(panel.armed && panel.allowButton.isEnabled)
        try await stage.appearances { suffix in
            try await Picture.panel(panel, over: shell, library: library, web: logbook.web, "b8" + suffix, root: stage.home.root)
        }
        panel.orderOut(nil)
    }
}
