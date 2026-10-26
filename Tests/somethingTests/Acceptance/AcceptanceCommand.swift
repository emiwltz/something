// Acceptance scenarios of the palette, Settings, the menus and the shortcuts card (g1–g11).
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import SomethingAgents
import SomethingCore
import Testing
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-command-"))
struct AcceptanceCommand {
    /// ⌘P over Daily brief, the mockup's moment around it: the scrim over the window, the card 84 points down,
    /// the three recent spaces, the others with Daily brief marked open, the actions and the footer. Its words are
    /// read off its picture.
    @Test("g1: the palette") func g1() async throws {
        let stage = try Stage("command")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        library.preferences.groups = Stage.groups.map { Preferences.Group(name: $0.0, spaces: $0.1) }
        library.relist()
        try stage.moment(shell)
        shell.waiting(1, mine: 0)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        // The mockup's recent spaces (CM_RECENT): Daily brief, open, is left out of Recent.
        library.preferences.change { $0.recents = ["brief", "agents", "pet", "logbook", "project", "oracle", "stack"] }
        #expect(Keys.command("palette")?.action == #selector(App.showPalette(_:)) && Keys.enabled("palette", Keys.Situation(space: true)))
        let model = PaletteModel(library: library, eyes: { Stage.moment[$0] ?? .unknown }, enabled: { Keys.enabled($0, Keys.Situation(space: true)) })
        let palette = try #require(Palette.toggle(in: shell.layer, model: model, motion: .reduced))
        #expect((shell.window.firstResponder as? NSTextView)?.delegate === palette.field && palette.accessibilityLabel() == "Go to or ask")
        #expect(palette.frame == shell.layer.bounds, "the scrim covers the window")
        let rows = model.rows
        #expect(rows.prefix(7).map(\.title) == ["My agents", "Pebble", "Logbook", "Daily brief", "Project watch", "Oracle", "Stack"])
        #expect(rows.prefix(3).map(\.kind) == [.space(.wait, open: false), .space(.done, open: false), .space(.sleep, open: false)])
        #expect(rows[3].kind == .space(.think, open: true) && rows[7].title == "New Space" && model.selected == 0 && model.enter == "Open")
        let card = palette.card
        let shows = ["Go to a space, or ask its assistant", "RECENT", "My agents", "Waiting for you", "Pebble", "Breaks", "Done", "Logbook",
                     "Asleep", "SPACES", "Daily brief", "Working", "Project watch", "Ready", "ACTIONS", "New Space", "something", "Move", "Close"]
        try await stage.appearances { suffix in
            shell.window.layoutIfNeeded()
            await wait(10) { card.frame.width == 640 && abs(card.frame.maxY - (760 - 84)) < 1 }
            #expect(card.frame.size == NSSize(width: 640, height: 500) && abs(card.frame.minX - 280) < 1 && abs(card.frame.maxY - 676) < 1)
            let rep = try Picture.bitmap(card.bounds.size)
            card.cacheDisplay(in: card.bounds, to: rep)
            let read = try Picture.text(rep).joined(separator: "\n").replacingOccurrences(of: "…", with: "...")
            for line in shows { #expect(read.contains(line), "g1\(suffix) shows “\(line)”; read: \(read)") }
            // The footer's "↵ Open" and Daily brief's badge: the badge is the second.
            #expect(read.components(separatedBy: "Open").count - 1 == 2, "g1\(suffix) shows Daily brief's Open badge; read: \(read)")
            let scrim = try Picture.bitmap(palette.bounds.size)
            palette.cacheDisplay(in: palette.bounds, to: scrim)
            #expect(palette.drawn == card.frame, "the card's shadow and ring drawn where the card is")
            try await Picture.window(shell, library: library, web: brief.web, "g1" + suffix, root: stage.home.root)
        }
        #expect(Palette.toggle(in: shell.layer, model: model) == nil && shell.layer.isHidden, "⌘P again closes it")
        // Esc in the window closes it first, as it does the shortcut sheet.
        _ = try #require(Palette.toggle(in: shell.layer, model: model, motion: .reduced))
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: shell.window.windowNumber,
                                                   context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        #expect(shell.escape(escape) && Palette.shown(in: shell.layer) == nil)
    }
    @Test("g2: the palette's ask row", .disabled("not built yet: G3")) func g2() async throws {}
    /// General: the three rows of Start and the version line; the open menu of "When something opens" is a menu the
    /// window server draws, so its items are checked as text (g3-menu.txt).
    @Test("g3: Settings, General") func g3() async throws {
        let shows = ["When something opens", "The last space you had open", "Add something to Applications", "Show Again",
                     "something 0.3.0", "installed with Homebrew", "nothing leaves this Mac"]
        try await settings(.general, "g3", shows: shows) { settings, stage in
            let rows = settings.model.sections(.general).flatMap(\.rows)
            #expect(rows.map(\.title) == ["When something opens", "Add something to Applications", "Welcome tour"])
            guard case .choice(let options, let get, _) = rows[0].control else { Issue.record("not a choice"); return }
            #expect(get() == "last")
            let menu = options.map { ($0.heading ? "# " : $0.value == get() ? "✓ " : "  ") + $0.label }
            #expect(menu == ["✓ The last space you had open", "  New Space", "# A space", "  Daily brief", "  My agents", "  Project watch",
                             "  Logbook", "  Oracle", "  Pebble", "  Stack"])
            if case .toggle(let on, _, let enabled) = rows[1].control { #expect(on() && enabled) } else { Issue.record("not a switch") }
            #expect(settings.model.versionLine == ("something 0.3.0", " · installed with Homebrew · nothing leaves this Mac"))
            if let gallery {
                try FileManager.default.createDirectory(at: gallery, withIntermediateDirectories: true)
                try (menu.joined(separator: "\n") + "\n").write(to: gallery.appendingPathComponent("g3-menu.txt"), atomically: true, encoding: .utf8)
            }
        }
    }
    /// Assistant: the defaults for new spaces (Claude Code with the models it last listed), resume, and rest.
    @Test("g4: Settings, Assistant") func g4() async throws {
        let shows = ["Defaults for new spaces", "Agent", "Claude Code", "Model", "Opus 5.5", "Effort", "High", "Conversations",
                     "Resume each space's conversation", "Put idle assistants to sleep after", "10 minutes", "Keep at most", "assistants awake"]
        try await settings(.assistant, "g4", shows: shows) { settings, _ in
            let sections = settings.model.sections(.assistant)
            #expect(sections.map(\.title) == ["Defaults for new spaces", "Conversations", "Rest"])
            #expect(sections.flatMap(\.rows).map(\.title) == ["Agent", "Model", "Effort", "Resume each space’s conversation",
                                                              "Put idle assistants to sleep after", "Keep at most"])
            #expect(sections[2].rows[1].trail == "assistants awake")
            #expect(sections[1].rows[0].note == "Claude Code can. Codex, OpenCode, pi, OMP and Amp start fresh, and say so.")
            guard case .choice(let agents, let get, _) = sections[0].rows[0].control else { Issue.record("not a choice"); return }
            #expect(get() == "claude" && agents.map(\.label) == Registry.app.builders.map(\.name))
        }
    }
    /// Permissions: the README's promise, Ask Before Every Change off, the lock, and Notify me off.
    @Test("g5: Settings, Permissions") func g5() async throws {
        let shows = ["something never answers for you", "Your assistant", "Ask Before Every Change", "Requests from agents",
                     "Requests always wait for your click", "Always", "Notify me when a request waits"]
        try await settings(.permissions, "g5", shows: shows) { settings, _ in
            let rows = settings.model.sections(.permissions).flatMap(\.rows)
            #expect(rows.map(\.title) == ["Ask Before Every Change", "Requests always wait for your click", "Notify me when a request waits"])
            if case .toggle(let on, _, _) = rows[0].control { #expect(!on()) } else { Issue.record("not a switch") }
            if case .toggle(let on, _, _) = rows[2].control { #expect(!on()) } else { Issue.record("not a switch") }
        }
    }
    /// Interface: Auto, Light and Dark (Light chosen, as in the mockup's picture), Motion, the assistant, the sidebar.
    @Test("g6: Settings, Interface") func g6() async throws {
        let shows = ["Auto", "Light", "Dark", "Calm", "Reduced", "Motion", "When a space opens, its assistant is", "Remember where I put the assistant",
                     "Show each assistant's eyes in the sidebar", "to point inside a drawn frame"]
        try await settings(.interface, "g6", shows: shows) { settings, _ in
            let sections = settings.model.sections(.interface)
            #expect(sections.map(\.title) == ["Appearance", "The assistant", "Sidebar and show"] && sections[0].appearance)
            #expect(sections.flatMap(\.rows).map(\.title) == ["Motion", "When a space opens, its assistant is", "Remember where I put the assistant",
                                                              "Show each assistant’s eyes in the sidebar", "Hold ⌥ to point inside a drawn frame"])
        }
    }
    /// Shortcuts: Keys' lines in two columns, and the way to System Settings › Keyboard.
    @Test("g7: Settings, Shortcuts") func g7() async throws {
        let shows = ["SPACES", "SHOW", "ASSISTANT", "WINDOW", "Go to a space, or ask", "Open Keyboard Settings..."]
        try await settings(.shortcuts, "g7", shows: shows) { settings, _ in
            #expect(ShortcutColumns.lines(.spaces).map(\.line) == ["Go to a space, or ask", "New Space", "Templates", "Go to space 1 to 9", "Reload space",
                                                                    "Space info", "Close Info or History"])
            #expect(ShortcutColumns.lines(.window).map(\.shown) == ["⌃⌘F", "⌃⌘S", "⌘,", "⌘/", "⌘W"])
            #expect(settings.model.sections(.shortcuts).isEmpty)
        }
    }

    /// Settings at `tab` on the Stage's home, run from a Homebrew Cellar with its launcher made, and drawn as `id`
    /// in both appearances: the window's frame (title, toolbar) by cacheDisplay, its lights in their key colors. Each
    /// picture is read by Vision and must show every line of `shows`: what the screen shows, not what the model says.
    func settings(_ tab: SettingsTab, _ id: String, shows: [String], _ check: (SettingsWindow, Stage) throws -> Void) async throws {
        let stage = try Stage("command")
        defer { stage.remove() }
        let (_, library, _) = stage.window()
        for (group, spaces) in Stage.groups { spaces.forEach { library.preferences.move($0, to: group) } }
        try Launcher.make(prefix: "/opt/homebrew", places: stage.home.places, icon: nil)
        let model = SettingsModel(preferences: library.preferences, places: stage.home.places,
                                  app: URL(fileURLWithPath: "/opt/homebrew/Cellar/something/0.3.0/something.app"), version: "0.3.0")
        model.spaces = { library.order().filter(\.isSpace).map { ($0.id, $0.title) } }
        model.apply = { _, _ in }
        // Where each agent was found and what its files name, invented (CM_FOUND); the models Claude Code last listed.
        let found = ["claude": ("/opt/homebrew/bin/claude", "2.1.4"), "codex": ("/opt/homebrew/bin/codex", "0.48.0"),
                     "opencode": ("~/.opencode/bin/opencode", "0.15.2"), "pi": ("/opt/homebrew/bin/pi", "0.9.1"), "omp": ("~/.local/bin/omp", "1.3.0"),
                     "amp": ("/opt/homebrew/bin/amp", "0.0.1761"), "cursor": ("/Applications/Cursor.app", "1.8"),
                     "antigravity": ("/Applications/Antigravity.app", "1.2")]
        model.locate = { kind in found[kind].map { .success($0.0) } ?? .failure(CodedError("NOT_INSTALLED", "\(kind) was not found on this Mac.")) }
        model.versions = { found.mapValues(\.1) }
        // The look ended 18 minutes before the picture.
        model.clock = { Stage.local.addingTimeInterval(-18 * 60) }
        var listed = Options()
        listed.model = [Option(value: "opus", label: "Opus 5.5"), Option(value: "sonnet", label: "Sonnet 5.5")]
        listed.effort = [Option(value: "medium", label: "Medium"), Option(value: "high", label: "High")]
        library.preferences.change { ($0.listed["claude"], $0.model, $0.effort) = (listed, "opus", "high") }
        model.find()
        _ = await wait(until: { model.found != nil })
        model.clock = { Stage.local }
        if tab == .interface { model.choose(.light) }
        if tab == .storage {
            model.weigh = { _, _ in AcceptanceCommand.weights }
            model.measure()
            _ = await wait(until: { model.storage != nil })
        }
        let settings = SettingsWindow(model)
        settings.window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        settings.window.alphaValue = 0
        defer { settings.window.close() }
        settings.select(tab)
        #expect(settings.window.title == tab.label && settings.window.toolbarStyle == .preference)
        #expect(settings.window.toolbar?.items.map(\.label) == SettingsTab.allCases.map(\.label))
        try check(settings, stage)
        try await stage.appearances { suffix in
            settings.window.layoutIfNeeded()
            await wait(1.2)
            #expect(abs(settings.window.contentRect(forFrameRect: settings.window.frame).width - 720) < 1)
            let frame = try #require(settings.window.contentView?.superview)
            frame.layoutSubtreeIfNeeded()
            let rep = try Picture.bitmap(frame.bounds.size)
            frame.cacheDisplay(in: frame.bounds, to: rep)
            // Vision reads … as ..., ’ as ' and a middle dot as anything: compare the words alone.
            func plain(_ text: String) -> String { text.replacingOccurrences(of: "…", with: "...").replacingOccurrences(of: "’", with: "'") }
            let read = plain(try Picture.text(rep).joined(separator: "\n"))
            for line in shows { #expect(read.contains(plain(line)), "\(id)\(suffix) shows “\(line)”; read: \(read)") }
            let lights = Picture.lights(of: settings.window)
            try Picture.png(of: frame.bounds.size, id + suffix) {
                rep.draw(in: NSRect(origin: .zero, size: frame.bounds.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                Picture.paint(lights)
            }
        }
    }
    /// Versions & Storage: Keep 50, the store's weight in three parts against 500 MB (invented weights, CM_PREFS'
    /// used:312), Clear Old Versions armed, and where the spaces are.
    @Test("g8: Settings, Versions and Storage") func g8() async throws {
        // Every value of the legend is read off the picture but Memory's "41 MB", which Vision misreads in the light
        // picture; an offscreen window gives VoiceOver nothing to hear, so that one is not read at all.
        let shows = ["Versions", "Keep", "versions per space", "Storage", "312 MB", "used of 500 MB", "Versions", "248 MB", "Memory", "Spaces", "23 MB",
                     "Free", "188 MB", "When it is full", "Clear Old Versions...", "Where", "~/something/spaces", "Show in Finder"]
        try await settings(.storage, "g8", shows: shows) { settings, stage in
            let sections = settings.model.sections(.storage)
            #expect(sections.map(\.title) == ["Versions", "Storage"] && sections[1].storage && sections[1].foot == nil)
            #expect(sections.flatMap(\.rows).map(\.title) == ["Keep", "Storage limit", "When it is full", "Where"])
            #expect(sections[0].rows[0].trail == "versions per space" && sections[1].rows[2].code)
            #expect(settings.model.storage == Self.weights && settings.model.storage?.used == 312_000_000)
            guard case .button(let title, _, let enabled, _) = sections[1].rows[1].control else { Issue.record("not a button"); return }
            #expect(title == "Clear Old Versions…" && enabled)
            #expect(sections[1].rows[2].note == "~/something/spaces")
        }
    }

    /// The mockup's store: 248 MB of versions, 41 of memory, 23 of spaces; 214 MB of old versions in 7 spaces.
    nonisolated static let weights = Storage(versions: 248_000_000, memory: 41_000_000, spaces: 23_000_000, old: Versions.Old(bytes: 214_000_000, spaces: 7))
    /// The menu bar is drawn by the window server, which no offscreen drawing reaches: g9 is checked as text, the
    /// menus against the mockup's table with no space open, then Go, the headers and the greyed items with Daily brief
    /// open. g9-menus.txt is the dump of both states.
    @Test("g9: the menus") func g9() async throws {
        let stage = try Stage("command")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        let bar = MenuBar(builders: nil)
        var open: (id: String, title: String)?
        bar.spaces = { library.order().filter(\.isSpace).map { ($0.id, $0.title) } }
        bar.open = { open }
        bar.refresh()
        let (fixture, _) = try Mockup.menus()
        #expect(bar.menu.items.compactMap(\.submenu).map { Mockup.lines($0) } == fixture.map(\.lines))
        let closed = Mockup.dump(bar.menu, Keys.Situation())
        for line in ["  # No space open", "  Space Info  ⌘I  (greyed)", "  Ask…  ⌘K  (greyed)", "  Go to…  ⌘P",
                     "  New Space  ⌘N", "  Daily brief  ⌘1"] {
            #expect(closed.contains(line + "\n"), "\(line)")
        }
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        open = ("brief", brief.title)
        bar.refresh()
        let go = try #require(bar.submenu("Go")).items.filter { $0.identifier?.rawValue.hasPrefix("space:") == true }
        #expect(go.count == library.entries.filter(\.isSpace).count && go.count == 7)
        #expect(go.filter { $0.state == .on }.map(\.title) == ["Daily brief"])
        let opened = Mockup.dump(bar.menu, Keys.Situation(space: true))
        for line in ["  # Daily brief", "  # Daily brief’s assistant", "  Space Info  ⌘I", "  Ask…  ⌘K", "  ✓ Daily brief  ⌘1",
                     "  Versions…", "  Put Idle Assistants to Sleep"] {
            #expect(opened.contains(line + "\n"), "\(line)")
        }
        #expect(Keys.about(.main)[.applicationVersion] as? String == Resources.version(of: .main))
        if let gallery {
            try FileManager.default.createDirectory(at: gallery, withIntermediateDirectories: true)
            try ("No space open\n\n" + closed + "\nDaily brief open\n\n" + opened).write(to: gallery.appendingPathComponent("g9-menus.txt"),
                                                                                           atomically: true, encoding: .utf8)
        }
    }
    /// The shortcuts card (⌘/) over Daily brief, the mockup's moment around it: the scrim over the window, the card
    /// in its middle, Keys' lines in two columns with their keycaps, and the footer. Its words are read off its picture.
    @Test("g10: the shortcuts card") func g10() async throws {
        let stage = try Stage("command")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        library.preferences.groups = Stage.groups.map { Preferences.Group(name: $0.0, spaces: $0.1) }
        library.relist()
        try stage.moment(shell)
        shell.waiting(1, mine: 0)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        #expect(Keys.command("keys")?.action == #selector(App.showKeys(_:)) && Keys.enabled("keys", Keys.Situation(space: true)))
        let sheet = try #require(KeysSheet.toggle(in: shell.layer, motion: .reduced))
        #expect(shell.window.firstResponder === sheet && sheet.frame == shell.layer.bounds)
        let card = try #require(sheet.subviews.first)
        let shows = ["Keyboard Shortcuts", "SPACES", "SHOW", "ASSISTANT", "WINDOW", "Go to a space, or ask", "Close Info or History",
                     "Point inside a drawn frame", "hold", "Talk to this space's assistant", "Show the request that waits", "Keyboard shortcuts",
                     "Close window", "Menu keys can be changed in System Settings", "Close"]
        try await stage.appearances { suffix in
            shell.window.layoutIfNeeded()
            await wait(10) { card.frame.width == 680 && abs(card.frame.midY - 380) < 1 }
            #expect(card.frame.size.width == 680 && abs(card.frame.midX - 600) < 1 && abs(card.frame.midY - 380) < 1)
            let rep = try Picture.bitmap(card.bounds.size)
            card.cacheDisplay(in: card.bounds, to: rep)
            let read = try Picture.text(rep).joined(separator: "\n").replacingOccurrences(of: "’", with: "'")
            for line in shows { #expect(read.contains(line), "g10\(suffix) shows “\(line)”; read: \(read)") }
            try await Picture.window(shell, library: library, web: brief.web, "g10" + suffix, root: stage.home.root)
        }
        #expect(KeysSheet.toggle(in: shell.layer) == nil && shell.layer.isHidden, "⌘/ again closes it")
        // The toolbar draws above the sheet: a click on one of its controls closes the sheet and is used up; a click
        // on the scrim or a light goes on (the scrim closes it itself, the light is the window's).
        func click(_ view: NSView) throws -> NSEvent {
            let place = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
            return try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: place, modifierFlags: [], timestamp: 0,
                                                   windowNumber: shell.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        let info = try #require(shell.controls[Shell.info]), light = try #require(shell.window.standardWindowButton(.closeButton))
        var over = try #require(KeysSheet.toggle(in: shell.layer, motion: .reduced))
        #expect(over.covers(try click(info)) == nil && KeysSheet.shown(in: shell.layer) == nil && !shell.infoShown, "a toolbar control closes it, unworked")
        over = try #require(KeysSheet.toggle(in: shell.layer, motion: .reduced))
        #expect(over.covers(try click(light)) != nil && KeysSheet.shown(in: shell.layer) == nil, "a light closes it and stays the window's")
        over = try #require(KeysSheet.toggle(in: shell.layer, motion: .reduced))
        #expect(over.covers(try click(over)) != nil && KeysSheet.shown(in: shell.layer) === over, "the scrim's click is its own")
        #expect(KeysSheet.close(in: shell.layer))
        // Esc in the window closes the top thing only: the sheet over point mode, then point mode's step.
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: shell.window.windowNumber,
                                                   context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        shell.point()
        #expect(brief.pointer != nil)
        _ = try #require(KeysSheet.toggle(in: shell.layer, motion: .reduced))
        #expect(shell.escape(escape) && KeysSheet.shown(in: shell.layer) == nil && brief.pointer != nil, "Esc closes the sheet, point mode stays")
        #expect(shell.escape(escape) && brief.pointer == nil, "the next Esc is point mode's")
        #expect(!shell.escape(escape), "then nothing is left to close: the app nudges the assistant")
    }
    /// Agents: the six builders found, Claude Code the default, the two agents something only sees with their
    /// reasons, and when it last looked, by the Stage's clock.
    @Test("g11: Settings, Agents") func g11() async throws {
        let shows = ["The coding agents found on this Mac", "Can build spaces", "Claude Code", "Default", "/opt/homebrew/bin/claude", "2.1.4",
                     "Seen only", "Cursor", "Antigravity", "Looked today at 18:02", "8 agents", "Look Again"]
        try await settings(.agents, "g11", shows: shows) { settings, _ in
            let agents = settings.model.agents
            #expect(agents.filter(\.builds).map(\.name) == ["Claude Code", "Codex", "OpenCode", "pi", "OMP", "Amp"])
            #expect(agents.filter { !$0.builds }.map(\.name) == ["Antigravity", "Cursor"])
            #expect(agents.filter(\.isDefault).map(\.id) == ["claude"] && agents.allSatisfy { $0.path != nil && $0.version != nil })
            #expect(settings.model.sections(.agents).isEmpty && settings.model.lookedLine == "Looked today at 18:02 · 8 agents")
        }
    }
}
