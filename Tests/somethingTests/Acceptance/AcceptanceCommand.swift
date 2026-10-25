// Acceptance scenarios of the palette, Settings, the menus and the shortcuts card (g1–g11).
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import Testing
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-command-"))
struct AcceptanceCommand {
    @Test("g1: the palette", .disabled("not built yet: G2")) func g1() async throws {}
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
    @Test("g4: Settings, Assistant", .disabled("not built yet: G5")) func g4() async throws {}
    @Test("g5: Settings, Permissions", .disabled("not built yet: G5")) func g5() async throws {}
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
        if tab == .interface { model.choose(.light) }
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
    @Test("g8: Settings, Versions and Storage", .disabled("not built yet: G6")) func g8() async throws {}
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
        for line in ["  # No space open", "  Space Info  ⌘I  (greyed)", "  Ask…  ⌘K  (greyed)", "  Go to…  ⌘P  (greyed)",
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
                     "  Versions…  (greyed)", "  Put Idle Assistants to Sleep"] {
            #expect(opened.contains(line + "\n"), "\(line)")
        }
        #expect(Keys.about(.main)[.applicationVersion] as? String == Resources.version(of: .main))
        if let gallery {
            try FileManager.default.createDirectory(at: gallery, withIntermediateDirectories: true)
            try ("No space open\n\n" + closed + "\nDaily brief open\n\n" + opened).write(to: gallery.appendingPathComponent("g9-menus.txt"),
                                                                                           atomically: true, encoding: .utf8)
        }
    }
    @Test("g10: the shortcuts card", .disabled("not built yet: G1")) func g10() async throws {}
    @Test("g11: Settings, Agents", .disabled("not built yet: G5")) func g11() async throws {}
}
