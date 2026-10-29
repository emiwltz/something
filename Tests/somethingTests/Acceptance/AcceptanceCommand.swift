// Acceptance scenarios of the palette, the menus and the shortcuts card (g1, g2, g9, g10), Settings' four tabs
// (x7-1 to x7-4), the picture (x8-1, x8-2, x0-1) and the interface size (6-1, 6-3).
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import SomethingAgents
import SomethingCore
import SwiftUI
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
        shell.waiting(["agents"], mine: 0)
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
            await wait { card.frame.width == 640 && abs(card.frame.maxY - (760 - 84)) < 1 }
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
    /// ⌘P over Daily brief with a sentence typed, then Tab once, as the mockup's moment: the ask row alone, "Make a
    /// New Space" and the sentence quoted, the line "Goes to" with New Space on, Return said as Build New Space; and
    /// nothing sent. Its words are read off its picture.
    @Test("g2: the palette's ask row") func g2() async throws {
        let stage = try Stage("command")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        library.preferences.groups = Stage.groups.map { Preferences.Group(name: $0.0, spaces: $0.1) }
        library.relist()
        try stage.moment(shell)
        shell.waiting(["agents"], mine: 0)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        library.preferences.change { $0.recents = ["brief", "agents", "pet", "logbook", "project", "oracle", "stack"] }
        let model = PaletteModel(library: library, eyes: { Stage.moment[$0] ?? .unknown }, enabled: { Keys.enabled($0, Keys.Situation(space: true)) })
        var chosen: [PaletteModel.Row] = []
        model.chose = { chosen.append($0) }
        let palette = try #require(Palette.toggle(in: shell.layer, model: model, motion: .reduced))
        let editor = try #require(shell.window.firstResponder as? NSTextView)
        let sentence = "A small page that tracks my reading list"
        editor.insertText(sentence, replacementRange: editor.selectedRange())
        editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
        #expect(model.query == sentence && shell.window.firstResponder === editor, "Tab keeps the keys in the field")
        #expect(model.rows.map(\.kind) == [.ask(.newSpace, text: sentence, none: false)] && model.rows.first?.title == "Make a New Space")
        #expect(model.enter == "Build New Space" && model.selected == 0)
        #expect(model.segments.map(\.place) == [.here, .new, .another] && model.segments.map(\.on) == [false, true, false])
        #expect(model.segments.map(\.space) == ["brief", nil, "agents"])
        let card = palette.card
        let shows = [sentence, "Make a New Space", "Goes to", "This Space", "Daily brief", "New Space", "Another", "My agents",
                     "Build New Space", "something", "Move", "Close"]
        try await stage.appearances { suffix in
            shell.window.layoutIfNeeded()
            await wait { card.frame.width == 640 && abs(card.frame.maxY - (760 - 84)) < 1 && card.frame.height < 300 }
            #expect(card.frame.size == NSSize(width: 640, height: 196) && abs(card.frame.minX - 280) < 1 && abs(card.frame.maxY - 676) < 1)
            let rep = try Picture.bitmap(card.bounds.size)
            card.cacheDisplay(in: card.bounds, to: rep)
            let read = try Picture.text(rep).joined(separator: "\n")
            for line in shows { #expect(read.contains(line), "g2\(suffix) shows “\(line)”; read: \(read)") }
            #expect(!read.contains("RECENT") && !read.contains("Open"), "g2\(suffix) shows the ask row alone; read: \(read)")
            try await Picture.window(shell, library: library, web: brief.web, "g2" + suffix, root: stage.home.root)
        }
        #expect(chosen.isEmpty, "nothing leaves before Return")
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(chosen.map(\.kind) == [.ask(.newSpace, text: sentence, none: false)] && Palette.shown(in: shell.layer) == nil)
    }
    /// X7.1, General: the start, then Look (the theme's three pictures, the interface size's tiles and its keys, the
    /// sidebar Pinned or Floating). The open menu of "When something opens" is a menu the window server draws, so its
    /// items are checked as text (x7-1-menu.txt).
    @Test("x7-1: Settings, General") func x7_1() async throws {
        let shows = ["Start", "When something opens", "The last space you had open", "Look", "Theme", "Auto follows your Mac", "Auto", "Light",
                     "Dark", "Interface size", "Default", "Large", "Larger", "Sidebar", "Pinned", "Floating"]
        try await settings(.general, "x7-1", shows: shows, hears: ["When something opens: The last space you had open", "Interface size: Default",
                                                                   "Sidebar: Pinned", "Light"]) { settings, _ in
            let sections = settings.model.sections(.general)
            #expect(sections.map(\.title) == ["Start", "Look"] && sections.flatMap(\.rows).map(\.title) == ["When something opens", "Theme", "Interface size", "Sidebar"])
            #expect(sections[1].rows.map(\.style) == [.thumbs, .tiles, .segments])
            guard case .choice(let options, let get, _) = sections[0].rows[0].control else { Issue.record("not a choice"); return }
            let menu = options.map { ($0.heading ? "# " : get().contains($0.value) ? "✓ " : "  ") + $0.label }
            #expect(menu == ["✓ The last space you had open", "  New Space", "# A space", "  Daily brief", "  My agents", "  Project watch",
                             "  Logbook", "  Oracle", "  Pebble", "  Stack"])
            try Self.dump(menu, "x7-1-menu.txt")
        }
    }

    /// X7.2, Agents: your assistant (the agent, then the model and the effort in one menu, checked as text in
    /// x7-2-menu.txt since the window server draws it), what a new space may do (None: the mockup's Watch would let a
    /// page whose words name no agent see them) and the notifications, each
    /// space with its level (Run with its folder), and the agents on this Mac, read only.
    @Test("x7-2: Settings, Agents") func x7_2() async throws {
        // The page scrolls past 680 points, as the mockup's: what is below is heard, not seen.
        let shows = ["Your assistant", "Agent", "Claude Code", "Model and effort", "Opus 5.5", "High", "Spaces and your agents", "A new space may",
                     "None", "Watch", "Talk", "Run", "when an agent asks", "Each space and what it may do", "My agents", "Project watch",
                     // Vision reads ~ and the space before a path in code as anything; "Daily brief" as "Daily briet": heard.
                     "code/atelier"]
        try await settings(.agents, "x7-2", shows: shows, hears: ["Agent: Claude Code", "Model and effort: Opus 5.5 · High", "A new space may: None",
                                                                  "Daily brief: Watch", "Project watch: Run", "Stack: None", "Look Again"]) { settings, stage in
            let sections = settings.model.sections(.agents)
            #expect(sections.map(\.title) == ["Your assistant", "Spaces and your agents", "On this Mac"] && sections[2].block == .found)
            #expect(sections.flatMap(\.rows).map(\.title) == ["Agent", "Model and effort", "A new space may", "Notify me when an agent asks"])
            #expect(sections[1].lead == "Each space and what it may do. One click changes it.")
            #expect(sections[1].more.map(\.title) == ["Daily brief", "My agents", "Project watch", "Logbook", "Oracle", "Pebble", "Stack"])
            #expect(sections[1].more.map(\.note) == ["", "", "in `~/code/atelier`", "", "", "", ""], "\(stage.home.places.home.path)")
            #expect(settings.model.agents.count == 8 && settings.model.agents.suffix(2).allSatisfy { $0.line == "Seen only" })
            // The note says what the chosen agent asks: Claude Code as the README says it, pi as Allow warns of it; and
            // Ask Before Every Change only for an assistant it can hold.
            let agent = sections[0].rows[0], chosen = settings.model.preferences.assistant
            #expect(agent.mark == "Claude Code" && agent.note == "It builds and changes your spaces in ~/something/spaces. "
                        + "Everything else it does asks you, as your agent’s own settings decide.")
            settings.model.preferences.change { $0.assistant = "pi" }
            #expect(settings.model.sections(.agents)[0].rows[0].note == "pi runs commands and edits files without asking you first.")
            #expect(!settings.model.sections(.advanced)[0].rows.map(\.title).contains("Your assistant asks before every change"))
            settings.model.preferences.change { $0.assistant = chosen }
            guard case .choice(let options, let get, _) = sections[0].rows[1].control else { Issue.record("not a choice"); return }
            let menu = options.map { ($0.heading ? "# " : get().contains($0.value) ? "✓ " : "  ") + $0.label }
            #expect(menu == ["# Model", "  Default model", "✓ Opus 5.5", "  Sonnet 5.5", "# Effort", "  Default effort", "  Medium", "✓ High"])
            try Self.dump(menu, "x7-2-menu.txt")
        }
    }

    /// X7.3, Spaces: where they live, the export's memory (off), the versions kept (50), then the store's weight in
    /// three parts against its limit (invented weights, CM_PREFS' used: 312).
    @Test("x7-3: Settings, Spaces") func x7_3() async throws {
        // Every value of the legend is read off the picture but Memory's "41 MB", which Vision misreads in the light
        // picture; VoiceOver hears it.
        let shows = ["Where they live", "something/spaces", "Show in Finder", "Include a space's memory when you export it", "Keep",
                     "versions of each space", "Storage", "312 MB", "used of 500 MB", "Limit", "Versions", "248 MB", "Memory", "Spaces", "23 MB",
                     "Free", "188 MB"]
        try await settings(.spaces, "x7-3", shows: shows, hears: ["Memory 41 MB", "312 MB used of 500 MB", "Keep: 50"]) { settings, _ in
            let sections = settings.model.sections(.spaces)
            #expect(sections.map(\.title) == ["", "Storage"] && sections[1].block == .storage)
            #expect(sections.flatMap(\.rows).map(\.title) == ["Where they live", "Include a space’s memory when you export it", "Keep", "Storage limit"])
            #expect(sections[0].rows[2].trail == "versions of each space" && settings.model.storage == Self.weights)
        }
    }

    /// X7.4, Advanced: Full Access (off; turning it on asks once), whether your assistant asks before every change (off)
    /// and the agents a space starts (their own settings); the lasting rules, each with Revoke (Project watch's, the
    /// mockup's); the assistants' rest and resume, and the shortcuts.
    @Test("x7-4: Settings, Advanced") func x7_4() async throws {
        let shows = ["Permissions", "Full Access", "something allows every permission your assistant asks", "Your assistant asks before every change",
                     "Agents a space starts", "Their Own Settings", "something answers for you only where you said so", "Lasting rules",
                     "git log --oneline -20", "code/atelier", "for Project watch", "Revoke", "Folders", "Assistants",
                     "Resume each space's conversation", "Put idle assistants to sleep after", "10 minutes"]
        try await settings(.advanced, "x7-4", shows: shows, hears: ["Full Access", "Your assistant asks before every change", "Revoke",
                                                                   "Put idle assistants to sleep after: 10 minutes", "Show Shortcuts"]) { settings, _ in
            let model = settings.model, sections = model.sections(.advanced)
            #expect(sections.map(\.title) == ["Permissions", "Lasting rules", "Folders", "Assistants", "Keyboard"] && sections[0].lead == Promise.sentence)
            #expect(sections.flatMap(\.rows).map(\.title) == ["Full Access", "Your assistant asks before every change", "Agents a space starts",
                                                              "Resume each space’s conversation", "Put idle assistants to sleep after", "Keep at most",
                                                              "Keyboard shortcuts"])
            let kept = try #require(sections[1].more.first)
            #expect(sections[1].more.count == 1 && kept.title == "git log --oneline -20" && kept.code && kept.mark == "Claude Code")
            #expect(kept.note == "Claude Code · in ~/code/atelier · for Project watch · since yesterday")
            // Folders: what the levels hold, each Run folder with its spaces (X7.4), and nothing to change there.
            let folder = try #require(sections[2].more.first)
            #expect(sections[2].more.count == 1 && folder.title == "~/code/atelier" && folder.note == "Project watch" && folder.code && folder.symbol == "folder")
            #expect(sections[3].rows[0].note == "Claude Code can. Codex, OpenCode, pi, OMP and Amp start fresh, and say so.")
            // Full Access goes through the app, which asks once; Revoke too.
            var turned: [Bool] = [], revoked: [LastingRule] = []
            (model.fullAccess, model.revoke) = ({ turned.append($0) }, { revoked.append($0) })
            if case .toggle(let get, let set) = sections[0].rows[0].control {
                #expect(!get())
                set(true)
            }
            if case .button(let title, _, let run) = kept.control {
                #expect(title == "Revoke")
                run()
            }
            #expect(turned == [true] && revoked.map(\.rule.command) == ["git log --oneline -20"])
            let confirm = Rules.confirmation()
            #expect(confirm.title == "Turn On Full Access?" && confirm.isAlert)
            #expect(confirm.buttons.map(\.title) == ["Turn On Full Access", "Cancel"] && (confirm.initialFirstResponder as? SheetButton)?.title == "Cancel")
            #expect(PanelsTests.texts(confirm.contentView).contains("The agents your spaces start still ask, as their own settings say."))
        }
    }

    /// Writes `lines` as `name` in the gallery, when there is one.
    static func dump(_ lines: [String], _ name: String) throws {
        guard let gallery else { return }
        try FileManager.default.createDirectory(at: gallery, withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: gallery.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    /// Settings at `tab` on the Stage's home, its spaces at the mockup's levels, drawn as `id` in both appearances: the
    /// window's frame (title bar, the tabs' bar) by cacheDisplay, its lights in their key colors. Each picture is read
    /// by Vision and must show every line of `shows`: what the screen shows, not what the model says; VoiceOver must
    /// hear each of `hears` in the page, and the bar's tabs. Drawn at `size`, set only while the pictures are drawn
    /// (Look.scale is the whole process's), then Default.
    func settings(_ tab: SettingsTab, _ id: String, shows: [String], hears: [String] = [], size: Look.Size = .standard,
                  _ check: (SettingsWindow, Stage) throws -> Void) async throws {
        let stage = try Stage("command")
        defer { stage.remove() }
        let (_, library, _) = stage.window()
        for (group, spaces) in Stage.groups { spaces.forEach { library.preferences.move($0, to: group) } }
        let model = SettingsModel(preferences: library.preferences, places: stage.home.places)
        model.spaces = { library.order().filter(\.isSpace).map { ($0.id, $0.title) } }
        model.apply = { _ in }
        // The mockup's levels (V62.level), Project watch at Run in its folder.
        let levels: [String: Grant.Level] = ["brief": .watch, "agents": .talk, "project": .run, "logbook": .watch, "pet": .watch]
        model.levels = {
            library.order().filter(\.isSpace).map {
                .init(id: $0.id, title: $0.title, level: levels[$0.id] ?? Grant.Level.none, folder: $0.id == "project" ? stage.home.places.home.appendingPathComponent("code/atelier").path : nil)
            }
        }
        // Where each agent was found and what its files name, invented (CM_FOUND); the models Claude Code last listed.
        let found = ["claude": ("/opt/homebrew/bin/claude", "2.1.4"), "codex": ("/opt/homebrew/bin/codex", "0.48.0"),
                     "opencode": ("~/.opencode/bin/opencode", "0.15.2"), "pi": ("/opt/homebrew/bin/pi", "0.9.1"), "omp": ("~/.local/bin/omp", "1.3.0"),
                     "amp": ("/opt/homebrew/bin/amp", "0.0.1761"), "cursor": ("/Applications/Cursor.app", "1.8"),
                     "antigravity": ("/Applications/Antigravity.app", "1.2")]
        model.locate = { kind in found[kind].map { .success($0.0) } ?? .failure(CodedError("NOT_INSTALLED", "\(kind) was not found on this Mac.")) }
        model.versions = { found.mapValues(\.1) }
        // The mockup's one lasting rule: Project watch's, for Claude Code in ~/code/atelier.
        let atelier = stage.home.places.home.appendingPathComponent("code/atelier").path
        model.rules = { [LastingRule(space: "project", title: "Project watch",
                                     rule: Rule(kind: "claude", command: "git log --oneline -20", folder: atelier, at: "2026-10-21T09:00:00Z"))] }
        // The look ended 18 minutes before the picture.
        model.clock = { Stage.local.addingTimeInterval(-18 * 60) }
        var listed = Options()
        listed.model = [Option(value: "opus", label: "Opus 5.5"), Option(value: "sonnet", label: "Sonnet 5.5")]
        listed.effort = [Option(value: "medium", label: "Medium"), Option(value: "high", label: "High")]
        library.preferences.change { ($0.listed["claude"], $0.model, $0.effort, $0.appearance) = (listed, "opus", "high", .light) }
        model.look()
        model.find()
        _ = await wait(until: { model.found != nil })
        model.clock = { Stage.local }
        model.weigh = { _ in AcceptanceCommand.weights }
        model.measure()
        _ = await wait(until: { model.storage != nil })
        let settings = SettingsWindow(model)
        settings.window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        defer { settings.window.close() }
        settings.select(tab)
        #expect(settings.window.title == tab.label && settings.window.toolbar == nil)
        try check(settings, stage)
        // The bar's four tabs are heard with the page, as four buttons.
        let page = try #require(settings.window.contentView), hears = hears + SettingsTab.allCases.map(\.label)
        let heard = await AcceptanceBuild.read(page) { words in hears.allSatisfy(words.contains) }
        for words in hears { #expect(heard.contains(words), "\(id) hears “\(words)”; heard: \(heard)") }
        try await stage.appearances { suffix in
            (Look.scale.size, library.preferences.size) = (size, size)
            // Theme says what the window shows: Light by day, Dark by night.
            library.preferences.change { $0.appearance = suffix.isEmpty ? .light : .dark }
            defer { (Look.scale.size, library.preferences.size) = (.standard, .standard) }
            settings.window.layoutIfNeeded()
            await wait(1.2)
            // The page grows with the size on SwiftUI's time, and the window with it: wait until both hold, the page measured.
            let content = try #require(settings.window.contentView)
            _ = await wait(until: {
                // An offscreen window gets no display cycle under load: lay it out here, as the screen would.
                settings.window.layoutIfNeeded()
                let now = settings.window.contentRect(forFrameRect: settings.window.frame).size
                return abs(now.width - 720 * size.factor) < 1 && abs(now.height - content.fittingSize.height) <= 1 && (settings.model.heights[tab] ?? 0) > 0
            })
            #expect(abs(settings.window.contentRect(forFrameRect: settings.window.frame).width - 720 * size.factor) < 1)
            #expect(abs(settings.window.contentRect(forFrameRect: settings.window.frame).height - content.fittingSize.height) <= 1, "the window holds its page whole")
            let frame = try #require(settings.window.contentView?.superview)
            // Vision reads … as ..., ’ as ' and a middle dot as anything: compare the words alone.
            func plain(_ text: String) -> String { text.replacingOccurrences(of: "…", with: "...").replacingOccurrences(of: "’", with: "'") }
            // Under load the hosting view may still be mid-layout: draw again, a few times, until the page reads whole.
            var rep = try Picture.bitmap(frame.bounds.size), read = ""
            for _ in 0..<4 {
                settings.window.layoutIfNeeded()
                frame.layoutSubtreeIfNeeded()
                rep = try Picture.bitmap(frame.bounds.size)
                frame.cacheDisplay(in: frame.bounds, to: rep)
                read = plain(try Picture.text(rep).joined(separator: "\n"))
                if shows.allSatisfy({ read.contains(plain($0)) }) { break }
                await wait(1)
            }
            for line in shows { #expect(read.contains(plain(line)), "\(id)\(suffix) shows “\(line)”; read: \(read)") }
            let lights = Picture.lights(of: settings.window)
            try Picture.png(of: frame.bounds.size, id + suffix) {
                rep.draw(in: NSRect(origin: .zero, size: frame.bounds.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                Picture.paint(lights)
            }
        }
    }

    /// The mockup's store: 248 MB of versions, 41 of memory, 23 of spaces.
    nonisolated static let weights = Storage(versions: 248_000_000, memory: 41_000_000, spaces: 23_000_000)
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
        for line in ["  # No space open", "  Show Info  ⌘I  (greyed)", "  Ask…  ⌘K  (greyed)", "  Go to…  ⌘P",
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
        for line in ["  # Daily brief", "  # Daily brief’s assistant", "  Show Info  ⌘I", "  Ask…  ⌘K", "  ✓ Daily brief  ⌘1",
                     "  Show History…", "  Put Idle Assistants to Sleep"] {
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
        shell.waiting(["agents"], mine: 0)
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
            await wait { card.frame.width == 680 && abs(card.frame.midY - 380) < 1 }
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
    /// X8.1, Help › How something Works: the picture in a window of its own, its three parts as buttons under it, none
    /// pressed, the promise and Replay; the item is in the Help menu, under something Help.
    @Test("x8-1: something in one picture") func x8_1() async throws {
        let stage = try Stage("command")
        defer { stage.remove() }
        #expect(Keys.command("how")?.title == "How something Works" && Keys.command("how")?.action == #selector(App.showHowItWorks(_:)))
        let help = try #require(Keys.menus.first { $0.title == "Help" }).entries
        #expect(help.prefix(3).map { if case .item(let id) = $0 { id } else { "" } } == ["help", "how", "keys"])
        let window = HowItWorks.made(builder: "Claude Code · Sonnet 5.5", motion: .reduced)
        defer { window.close() }
        #expect(window.title == "How something Works" && window.contentView?.frame.size == HowItWorks.size && HowItWorks.light.lit == nil)
        try await stage.appearances { suffix in
            try await Picture.alone(window, "x8-1" + suffix, root: stage.home.root)
            let words = await AcceptanceBuild.read(try #require(window.contentView))
            #expect(words == Self.howWords, "\(words)")
        }
    }

    /// X8.2, one part lit: Your assistant's button pressed (its number dark), the picture faded but for the assistant
    /// and the panel, the page half; pressed again, all of it again. The welcome lights its parts the same way.
    @Test("x8-2: one part lit") func x8_2() async throws {
        let stage = try Stage("command")
        defer { stage.remove() }
        let window = HowItWorks.made(builder: "Claude Code · Sonnet 5.5", motion: .reduced, lit: .assistant)
        defer { window.close() }
        #expect(HowItWorks.light.lit == .assistant)
        try await stage.appearances { suffix in
            try await Picture.alone(window, "x8-2" + suffix, root: stage.home.root)
            let words = await AcceptanceBuild.read(try #require(window.contentView))
            #expect(words == Self.howWords, "\(words)")
        }
        HowItWorks.light.light(nil)
        HowItWorks.light.cycle(.reduced)
        #expect(HowItWorks.light.lit == nil, "under Reduced motion Replay lights nothing in turn")
    }

    /// X0.1, the picture alone, 720 by 420, as the welcome and Help draw it: one image for VoiceOver, its three agents
    /// the first three the app knows.
    @Test("x0-1: the picture") func x0_1() async throws {
        let stage = try Stage("command")
        defer { stage.remove() }
        let hero = Hero(light: HeroLight(), builder: "Claude Code · Sonnet 5.5", motion: .reduced)
        #expect(hero.agents == ["Claude Code", "Codex", "OpenCode"])
        let view = NSHostingView(rootView: hero)
        view.frame.size = Hero.size
        try await stage.appearances { suffix in
            try Picture.view(view, "x0-1" + suffix, root: stage.home.root)
            #expect(await AcceptanceBuild.read(view) == [Hero.label])
        }
    }

    /// 6.1, the interface size, in Settings › General's Look at Large: the row says what grows and the three keys, and
    /// Settings grows with the app (a page 806 points wide, its type 12 % larger). The View menu says the size and greys
    /// what cannot act there (6.2); ⌘+ ⌘− ⌘0 reach the menu before a page (KeysTests), and say the size in a toast.
    @Test("6-1: the interface size") func v6_1() async throws {
        let shows = ["Look", "Interface size", "The whole app grows", "Large"]
        try await settings(.general, "6-1", shows: shows, size: .large) { settings, _ in
            let look = try #require(settings.model.sections(.general).last), row = look.rows[1]
            #expect(look.title == "Look" && row.title == "Interface size")
            #expect(row.style == .tiles && row.keys.map(\.key) == ["⌘+", "⌘−", "⌘0"])
            guard case .choice(let options, let get, _) = row.control else { Issue.record("not a choice"); return }
            #expect(options.map(\.label) == ["Default", "Large", "Larger"] && get() == ["default"])
            #expect(Look.Size.allCases.map(\.factor) == [1, 1.12, 1.24])
            let view = try #require(MenuBar(builders: nil).submenu("View"))
            #expect(Mockup.lines(view).contains("# Interface Size · Default"))
            #expect(["bigger", "smaller", "defaultSize"].map { Keys.enabled($0, Keys.Situation(size: .large)) } == [true, true, true])
        }
        // The header itself, read past Mockup.lines (which writes it at Default), under the lock that sizes the app.
        try await Stage.alone {
            defer { Look.scale.size = .standard }
            let bar = MenuBar(builders: nil)
            func header() -> String? { bar.submenu("View")?.items.first { $0.identifier?.rawValue == "header.size" }?.title }
            for size in [Look.Size.large, .larger] {
                Look.scale.size = size
                bar.refresh()
                #expect(header() == "Interface Size · " + ["Large", "Larger"][size == .large ? 0 : 1])
            }
        }
    }

    /// ⌘+ ⌘− ⌘0 step the size the person keeps, clamped at Larger, and Look with it, and say it in a toast.
    @Test("The size keys step, clamp and say the size") func sizeKeys() async throws {
        let stage = try Stage("command")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        try await Stage.alone {
            defer { (Look.scale.size, library.preferences.size) = (.standard, .standard) }
            func now() -> [Look.Size] { [library.preferences.size, Look.scale.size] }
            shell.resize(by: 1)
            let toast = shell.resize(by: 1)
            #expect(now() == [.larger, .larger] && toast.words == "Interface: Larger · ⌘+ bigger · ⌘− smaller · ⌘0 default")
            shell.resize(by: 1)
            #expect(now() == [.larger, .larger], "Larger is the largest")
            #expect(shell.resize(by: -1).words == "Interface: Large · ⌘+ bigger · ⌘− smaller · ⌘0 default" && now() == [.large, .large])
            shell.resize(by: nil)
            #expect(now() == [.standard, .standard])
        }
    }

    /// 6.3, the same window at Larger (124 %): the sidebar's rows and width, Info's width, the toolbar's name and the
    /// page's zoom grow together, so the page's CSS viewport narrows; the window's lights do not. Default brings it back.
    @Test("6-3: the window at Larger") func v6_3() async throws {
        let stage = try Stage("command")
        defer { stage.remove() }
        let (shell, library, brief) = try await AcceptanceShell.calm(stage)
        defer { brief.close() }
        let side = shell.split.splitViewItems[0]
        func width() -> CGFloat { side.viewController.view.frame.width }
        func inner() async -> Double { (try? await brief.web.evaluateJavaScript("innerWidth")) as? Double ?? 0 }
        let before = (width(), await inner())
        try await stage.appearances { suffix in
            Look.scale.size = .larger
            defer { Look.scale.size = .standard }
            #expect(await wait(until: { abs(width() - before.0 * 1.24) <= 1 }), "the sidebar grows: \(width()) from \(before.0)")
            let title = shell.titleLine.line.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            #expect(abs(Look.row - 31) < 0.01 && brief.web.pageZoom == 1.24 && abs(shell.inspector.minimumThickness - 396.8) < 0.01)
            #expect(abs((title?.pointSize ?? 0) - 13.5 * 1.24) < 0.01, "\(String(describing: title))")
            let narrowed = await inner()
            #expect(narrowed > 0 && narrowed <= before.1 / 1.24 + 1, "the page's viewport narrows: \(narrowed) from \(before.1)")
            try await Picture.window(shell, library: library, web: brief.web, "6-3" + suffix, root: stage.home.root)
        }
        #expect(await wait(until: { abs(width() - before.0) <= 1 }) && brief.web.pageZoom == 1, "Default brings it back")
    }

    static let howWords = ["A space, your agents, your assistant", Hero.label] + HowItWorksView.parts.map { "\($0.1): \($0.2)" } + ["Replay"]

    /// The palette by its keys, VoiceOver on its field: ↓ and ↑ move the keys from row to row and say the row, Tab
    /// says where a sentence goes, Return opens; the shortcut sheet takes the keys and Esc closes it.
    @Test("Keys only: the palette and the shortcut sheet") func keysOnly() async throws {
        let stage = try Stage("command")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        try stage.moment(shell)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        library.preferences.change { $0.recents = ["brief", "agents", "pet", "logbook", "project", "oracle", "stack"] }
        var said: [String] = []
        shell.layer.announce = { said.append($0) }
        let model = PaletteModel(library: library, eyes: { Stage.moment[$0] ?? .unknown }, enabled: { Keys.enabled($0, Keys.Situation(space: true)) })
        var chosen: [PaletteModel.Row] = []
        model.chose = { chosen.append($0) }
        _ = try #require(Palette.toggle(in: shell.layer, model: model, motion: .reduced))
        let editor = try #require(shell.window.firstResponder as? NSTextView)
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        editor.doCommand(by: #selector(NSResponder.moveUp(_:)))
        #expect(model.selected == 1 && said == ["Pebble, Done", "Logbook, Asleep", "Pebble, Done"], "\(said)")
        editor.insertText("A reading list", replacementRange: editor.selectedRange())
        editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
        #expect(said.last == "New Space, built from this sentence" && shell.window.firstResponder === editor)
        editor.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        #expect(said.last == "This Space, Daily brief")
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(chosen.count == 1 && Palette.shown(in: shell.layer) == nil)

        let sheet = try #require(KeysSheet.toggle(in: shell.layer, motion: .reduced))
        #expect(shell.window.firstResponder === sheet && sheet.accessibilityLabel() == "Keyboard shortcuts")
        sheet.cancelOperation(nil)
        #expect(KeysSheet.shown(in: shell.layer) == nil && shell.layer.isHidden)
    }
}
