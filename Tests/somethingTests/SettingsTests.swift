// Settings: each control writes only its own key, the values shown at first are the mockup's (CM_PREFS and v6.2's),
// the model and the effort share one menu, Auto lets the Mac choose the appearance and Dark sets darkAqua, the shortcuts
// are Keys' own, the window keeps one size with its tabs in a column, and "When something opens" decides the space opened at the start.
// Permissions lists each space's level as its grant says it and changes it as Info does, Agents the agents found, read
// only, looking again once; the default level pre-sets New Space when the words name no agent; the menu items open their
// tabs. The store's parts add up to what the folders weigh.
import AppKit
import SomethingAgents
import SomethingCore
import SwiftUI
import Testing
@testable import something

@MainActor @Suite(.serialized, .leavesNothing("something-settings-")) struct SettingsTests {
    /// A model on a fresh home, its effects recorded rather than applied to this process.
    func model(_ home: Home) -> (SettingsModel, Effects) {
        let model = SettingsModel(preferences: Preferences(home.places), places: home.places)
        let effects = Effects()
        model.spaces = { [("brief", "Daily brief"), ("logbook", "Logbook")] }
        model.apply = { effects.applied.append($0) }
        model.resize = { effects.sized.append($0) }
        model.shortcuts = { effects.shortcuts += 1 }
        model.levels = {
            [.init(id: "brief", title: "Daily brief", level: .watch, folder: nil),
             .init(id: "watch", title: "Project watch", level: .run, folder: "/Users/example/code/atelier"),
             .init(id: "unread", title: "Unread", level: nil, folder: nil)]
        }
        model.setLevel = { effects.levels.append(($0, $1)) }
        model.chose = { effects.chosen.append($0) }
        model.asking = { effects.asking.append($0) }
        // As the app does once its confirmation is answered (App.fullAccess).
        model.fullAccess = { [unowned model] in model.preferences.fullAccess = $0 }
        model.lookAgain = { effects.looks += 1 }
        model.reveal = { effects.revealed.append($0) }
        // Invented places; no program is looked for, let alone run.
        let found = ["claude": "/opt/homebrew/bin/claude", "codex": "/Users/example/.local/bin/codex", "cursor": "/Applications/Cursor.app"]
        model.locate = { kind in
            found[kind].map { .success($0) } ?? .failure(CodedError("NOT_INSTALLED", "\(kind) was not found on this Mac. To install it, type in Terminal: x"))
        }
        model.versions = { ["claude": "2.1.4", "cursor": "1.8"] }
        model.look()
        return (model, effects)
    }

    final class Effects {
        var applied: [Preferences.Appearance] = [], sized: [Look.Size] = [], floats = false, shortcuts = 0
        var levels: [(String, Grant.Level)] = [], chosen: [String] = [], asking: [Bool] = [], looks = 0, revealed: [URL] = []
    }

    /// The values as the file would hold them, key by key.
    static func keys(_ values: Preferences.Values) throws -> [String: String] {
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(values)) as? [String: Any])
        return object.mapValues { "\($0)" }
    }

    /// Every row of every tab: each section's rows, then its more rows.
    static func rows(_ model: SettingsModel) -> [SettingsRow] {
        SettingsTab.allCases.flatMap { model.sections($0) }.flatMap { $0.rows + $0.more }.flatMap { [$0] + $0.beside }
    }

    @Test func eachControlWritesOnlyItsKey() throws {
        let home = Home(prefix: "something-settings-")
        defer { home.remove() }
        let (model, effects) = model(home)
        var listed = Options()
        (listed.model, listed.effort) = ([Option(value: "opus", label: "Opus 5.5")], [Option(value: "high", label: "High")])
        model.preferences.listed["claude"] = listed
        // A space's level, the words and the buttons write no key: the window, the grants or nothing.
        let expected: [String: String?] = ["When something opens": "openAtStart", "Theme": "appearance", "Interface size": "size", "Sidebar": "pinned",
                                           "Program · Model and effort": "assistant", "Model and effort": "model", "A new space may": "level",
                                           "Notify me when an agent asks": "notify", "Daily brief": nil, "Project watch": nil, "Unread": nil, "/Users/example/code/atelier": nil,
                                           "Where they live": nil, "Include a space’s memory when you export it": "exportMemory",
                                           "Keep": "versionsKept", "Ask me a few questions first": "askFirst", "Storage limit": "storageLimit",
                                           "Full Access": "fullAccess", "Your assistant asks before every change": "askEverything", "Agents a space starts": nil,
                                           "Resume each space’s conversation": "resume", "Put idle assistants to sleep after": "sleepAfter",
                                           "Keep at most": "awakeAtMost", "Keyboard shortcuts": nil]
        var seen: Set<String> = []
        for row in Self.rows(model) {
            let before = try Self.keys(model.preferences.values)
            switch row.control {
            case .choice(let options, let get, let set):
                let other = try #require(options.first { !$0.heading && !get().contains($0.value) })
                set(other.value)
                // A space's level is the grants', which the recorded effect does not write.
                if !["Daily brief", "Project watch"].contains(row.title) { #expect(get().contains(other.value), "\(row.title)") }
            case .toggle(let get, let set):
                let was = get()
                set(!was)
                #expect(get() == !was, "\(row.title)")
            case .button(let title, _, let run):
                #expect(["Show in Finder", "Show Shortcuts"].contains(title))
                run()
            case .model(let choice, _):
                choice().pick("opus")
                #expect(choice().chip == "Opus 5.5", "\(row.title)")
            case .said(let words):
                #expect(["Their Own Settings", "Not known"].contains(words), "\(row.title)")
            case .nothing:
                #expect(row.symbol == "folder" && row.note == "Project watch", "\(row.title): only Permissions › Folders says without a control")
            }
            let after = try Self.keys(model.preferences.values)
            let changed = Set(after.keys).union(before.keys).filter { before[$0] != after[$0] }
            let own = Set((expected[row.title] ?? nil).map { [$0] } ?? [])
            #expect(changed == own, "\(row.title) changed \(changed.sorted())")
            seen.insert(row.title)
        }
        #expect(seen == Set(expected.keys))
        #expect(effects.revealed == [home.places.spaces] && effects.shortcuts == 1)
        #expect(effects.applied == [.light] && effects.sized == [.large], "the theme and the size apply at once")
        #expect(effects.levels.map(\.0) == ["brief", "watch"] && effects.levels.map(\.1) == [.none, .none], "each space's level, as Info changes it")
        #expect(effects.chosen == ["codex"] && effects.asking == [true], "the assistant takes the default agent and Ask Before Every Change")
        #expect(Preferences(home.places).values == model.preferences.values, "each change is on the disk")
    }

    /// What the rows show on a fresh home: the mockup's CM_PREFS and v6.2's.
    @Test func theDefaultsShownAreTheMockups() throws {
        let home = Home(prefix: "something-settings-")
        defer { home.remove() }
        let (model, _) = model(home)
        var shown: [String: String] = [:]
        for row in Self.rows(model) {
            switch row.control {
            case .choice(let options, let get, _): shown[row.title] = options.filter { !$0.heading && get().contains($0.value) }.map(\.label).joined(separator: " · ")
            case .toggle(let get, _): shown[row.title] = get() ? "on" : "off"
            case .button(let title, _, _), .said(let title): shown[row.title] = title
            case .model(let choice, _): shown[row.title] = choice().models == .unread ? "Its models show after its first run" : choice().chip
            case .nothing: shown[row.title] = row.note
            }
        }
        #expect(shown == ["When something opens": "The last space you had open", "Theme": "Auto", "Interface size": "Default", "Sidebar": "Floating",
                          // Before Claude Code ever listed its models, nothing is guessed (rule 3).
                          "Program · Model": "Claude Code", "Model": "Its models show after its first run", "A new space may": "None",
                          "Notify me when an agent asks": "off", "Daily brief": "Watch", "Project watch": "Run", "Unread": "Not known",
                          "Where they live": "Show in Finder", "Include a space’s memory when you export it": "off", "Keep": "50",
                          "Ask me a few questions first": "on", "Storage limit": "500 MB", "Full Access": "off", "Your assistant asks before every change": "off", "Agents a space starts": "Their Own Settings",
                          "Resume each space’s conversation": "on", "Put idle assistants to sleep after": "10 minutes", "Keep at most": "3",
                          "/Users/example/code/atelier": "Project watch", "Keyboard shortcuts": "Show Shortcuts"])
        #expect(SettingsTab.allCases.map(\.label) == ["General", "Spaces", "Agents", "Permissions"])
        let run = try #require(model.sections(.permissions)[1].more.first { $0.title == "Project watch" })
        #expect(run.note == "in `/Users/example/code/atelier`" || run.note == "in `~/code/atelier`", "\(run.note)")
        let opening = model.sections(.general)[0].rows[0]
        guard case .choice(let options, _, _) = opening.control else { Issue.record("not a choice"); return }
        #expect(options.map(\.label) == ["The last space you had open", "New Space", "A space", "Daily brief", "Logbook"])
        #expect(RowControl.sections(options).map(\.heading) == ["", "A space"])
    }

    /// The model and the effort in one menu, as Claude Code listed them, "Default" each one's own; an agent that sets
    /// its own model says so and offers none.
    @Test func theModelAndTheEffortShareOneMenu() throws {
        let home = Home(prefix: "something-settings-")
        defer { home.remove() }
        let (model, _) = model(home)
        var listed = Options()
        (listed.model, listed.effort) = ([Option(value: "opus", label: "Opus 5.5"), Option(value: "sonnet", label: "Sonnet 5.5")],
                                         [Option(value: "medium", label: "Medium"), Option(value: "high", label: "High")])
        model.preferences.listed["claude"] = listed
        let row = try #require(model.sections(.agents)[0].rows[0].beside.first)
        guard case .model(let read, _) = row.control else { Issue.record("not the chip"); return }
        #expect(row.title == "Model and effort")
        #expect(read().rows.map(\.name) == ["Default", "Opus 5.5", "Sonnet 5.5"] && read().efforts.map(\.label) == ["Medium", "High"] && read().scope == "For new spaces" && !read().defaults)
        read().pick("opus")
        read().pickEffort("high")
        #expect(read().chip == "Opus 5.5 · High" && model.preferences.model == "opus" && model.preferences.effort == "high")
        read().pickEffort("high")
        #expect(model.preferences.effort == nil, "the chosen notch again: the agent's own")
        read().pick(nil)
        #expect(model.preferences.model == nil && read().chip == "Default model")
        model.preferences.assistant = "amp"
        let amp = try #require(model.sections(.agents)[0].rows[0].beside.first)
        guard case .model(let own, _) = amp.control else { Issue.record("not the chip"); return }
        #expect(amp.title == "Model" && own().models == .own && own().chip.hasPrefix("Its own model"))
    }

    @Test func autoLetsTheMacChooseAndDarkIsDarkAqua() {
        #expect(Look.appearance(.system) == nil)
        #expect(Look.appearance(.dark)?.name == .darkAqua)
        #expect(Look.appearance(.light)?.name == .aqua)
    }

    /// The shortcut sheet lists each command once, in Keys' words and keys, Spaces and Show on the left.
    @Test func theShortcutsAreKeysOwn() {
        let listed = ShortcutColumns.columns.flatMap { $0.flatMap(ShortcutColumns.lines) }
        #expect(listed.map(\.id) == Keys.commands.filter { $0.area != nil && $0.line != nil }.sorted {
            ShortcutColumns.columns.flatMap { $0 }.firstIndex(of: $0.area!)! < ShortcutColumns.columns.flatMap { $0 }.firstIndex(of: $1.area!)!
        }.map(\.id))
        #expect(ShortcutColumns.columns == [[.spaces, .pointing], [.assistant, .window]])
        #expect(ShortcutColumns.caps("⇧⌘T") == [.key("⇧"), .key("⌘"), .key("T")])
        #expect(ShortcutColumns.caps("esc") == [.key("esc")])
        #expect(ShortcutColumns.caps("hold ⌥") == [.word("hold"), .key("⌥")])
        #expect(ShortcutColumns.caps("⌘1 … ⌘9") == [.key("⌘"), .key("1"), .word("to"), .key("⌘"), .key("9")])
        #expect(Keys.command("settings")?.action == #selector(App.showSettings(_:)))
    }

    /// On this Mac: the agents found, the builders first, each with the version its files name or Seen only; Look Again
    /// looks once and says when, by the clock.
    @Test func theAgentsFoundAreListedReadOnly() async throws {
        let home = Home(prefix: "something-settings-")
        defer { home.remove() }
        let (model, effects) = model(home)
        #expect(model.lookedLine == "Looking for agents on this Mac…" && model.agents.isEmpty)
        let calendar = Calendar.current
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 17, minute: 40)))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 18, minute: 2)))
        model.clock = { start }
        model.find()
        _ = await wait(until: { model.found != nil })
        #expect(model.agents == [.init(id: "claude", name: "Claude Code", line: "Version 2.1.4"), .init(id: "codex", name: "Codex", line: "Version unknown"),
                                 .init(id: "cursor", name: "Cursor", line: "Seen only")])
        #expect(model.lookedLine == "Found 3 programs · looked today at 17:40. something never installs them or changes their settings.")
        model.clock = { now }
        model.again()
        #expect(effects.looks == 1, "Look Again asks the engine once")
        #expect(model.lookedLine == "Looking for agents on this Mac…", "while the new look runs")
        _ = await wait(until: { model.found != nil })
        #expect(model.lookedLine.hasPrefix("Found 3 programs · looked today at 18:02."))
    }

    /// The Assistant menu's Ask Before Every Change… and the assistant's Defaults for New Spaces… send their actions.
    @Test func theMenuItemsOpenTheirTabs() async throws {
        #expect(Keys.command("askAll")?.action == #selector(App.showPermissions(_:)))
        #expect(Keys.command("defaults")?.action == #selector(App.showNewSpaceDefaults(_:)))
        #expect(Keys.command("defaults")?.title == AssistantModel.defaultsTitle)
        #expect(Keys.command("lookAgain")?.action == #selector(App.lookForAgentsAgain(_:)))
        #expect(Keys.enabled("askAll", Keys.Situation()))
    }

    /// Settings.open, which showPermissions and showNewSpaceDefaults go through: one window, made once, at the tab given.
    @Test(.enabled(if: windowServer, windowServerMissing)) func openingAtATabShowsThatTab() throws {
        let home = Home(prefix: "something-settings-")
        defer { home.remove() }
        let (model, _) = model(home)
        var made = 0
        func make() -> SettingsWindow {
            made += 1
            let settings = SettingsWindow(model)
            settings.window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
            settings.window.alphaValue = 0
            return settings
        }
        defer { Settings.shown?.window.close(); Settings.shown = nil }
        Settings.open(.permissions, make: make)
        #expect(Settings.shown?.tab == .permissions)
        Settings.open(.agents, make: make)
        #expect(Settings.shown?.tab == .agents && made == 1)
        Settings.open(nil, make: make)
        #expect(Settings.shown?.tab == .agents, "where it was left")
    }

    /// The window: the column with the four tabs, which its own buttons choose, 720 × 560 at every tab, titled by it.
    @Test(.enabled(if: windowServer, windowServerMissing)) func theWindowKeepsOneSize() async throws {
        let home = Home(prefix: "something-settings-")
        defer { home.remove() }
        let settings = SettingsWindow(model(home).0)
        settings.window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        settings.window.alphaValue = 0
        defer { settings.window.close() }
        #expect(settings.window.toolbar != nil && settings.window.toolbar?.items.isEmpty == true, "an empty toolbar, to centre the lights")
        let content = try #require(settings.window.contentView), frame = settings.window.frame
        for tab in SettingsTab.allCases {
            settings.select(tab)
            await wait(0.05)
            #expect(settings.tab == tab && settings.window.title == tab.label)
            #expect(settings.window.frame == frame, "\(tab) moves nothing")
            #expect(settings.window.contentRect(forFrameRect: frame).size == SettingsWindow.size, "\(tab)")
        }
        // VoiceOver hears the column as the window's first four elements, one per tab, before the page's scroll area.
        // Offscreen, SwiftUI's elements carry only their words (AXAttributedDescription): no role, no selected trait,
        // and no press reaches them, so the choice is proved by calling the column's `choose`.
        let labels = SettingsTab.allCases.map(\.label)
        var column: [String] = []
        _ = await AcceptanceBuild.read(content) { _ in
            column = (content.accessibilityChildren() ?? []).prefix(4).map(AcceptanceBuild.said)
            return column == labels
        }
        #expect(column == labels, "the column's tabs, heard: \(column)")
        settings.select(.general)
        let view = try #require(content as? NSHostingView<SettingsFrame>).rootView
        view.choose(.permissions)
        #expect(settings.tab == .permissions && settings.window.title == "Permissions")
        #expect(settings.window.styleMask.contains(.miniaturizable), "three lights, as the Mac's own settings")
    }

    /// Over the main window, inside its screen, until the person moves it: then it stays, and the interface size
    /// keeps its top edge.
    @Test(.enabled(if: windowServer, windowServerMissing)) func theWindowOpensOverTheMainWindowUntilMoved() async throws {
        let main = NSRect(x: 100, y: 100, width: 1200, height: 760), screen = NSRect(x: 0, y: 0, width: 1440, height: 875)
        #expect(SettingsWindow.spot(NSSize(width: 720, height: 560), over: main, in: screen) == NSPoint(x: 340, y: 200))
        #expect(SettingsWindow.spot(NSSize(width: 720, height: 560), over: NSRect(x: 1200, y: 700, width: 400, height: 300), in: screen) == NSPoint(x: 720, y: 315),
                "kept inside the screen")
        let home = Home(prefix: "something-settings-")
        defer { home.remove() }
        let settings = SettingsWindow(model(home).0), window = NSWindow(contentRect: main, styleMask: .titled, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        settings.window.alphaValue = 0
        defer { settings.window.close(); window.close() }
        settings.place(over: window)
        let spot = settings.window.frame
        #expect(spot.origin == SettingsWindow.spot(spot.size, over: window.frame, in: (window.screen ?? NSScreen.main)?.visibleFrame))
        window.setFrame(window.frame.offsetBy(dx: 10, dy: 0), display: false)
        settings.place()
        #expect(settings.window.frame.minX != spot.minX, "not moved by the person, it follows")
        let moved = NSPoint(x: 40, y: 50)
        settings.window.setFrameOrigin(moved)
        settings.place(over: window)
        #expect(settings.window.frame.origin == moved, "moved by the person, it stays")
        let top = settings.window.frame.maxY
        try await Stage.alone {
            defer { Look.scale.size = .standard }
            Look.scale.size = .large
            settings.place()
            #expect(settings.window.frame.maxY == top && settings.window.frame.minX == moved.x, "the interface size keeps its top edge")
        }
    }

    /// "When something opens": New Space opens nothing, a space opens that space while it is there, else the last one.
    @Test func whenSomethingOpensDecidesTheStart() throws {
        let home = Home(prefix: "something-settings-")
        defer { home.remove() }
        try home.space("shop", "<!doctype html><title>Shop</title>")
        try home.space("today", "<!doctype html><title>Today</title>")
        let library = Library(places: home.places, ask: FakeAsk(), share: Home.share)
        library.relist()
        library.preferences.opened("today")
        #expect(library.atStart() == "today")
        library.preferences.openAtStart = "shop"
        #expect(library.atStart() == "shop")
        library.preferences.openAtStart = "new"
        #expect(library.atStart() == nil)
        library.preferences.openAtStart = "gone"
        #expect(library.atStart() == "today")
    }

    /// "A new space may": New Space's level when the words name no agent; words that do still pre-set theirs. A space
    /// arrives as its sticker, the card closed.
    @Test func theDefaultLevelPresetsNewSpace() {
        let home = Home(prefix: "something-settings-")
        defer { home.remove() }
        let model = AssistantModel(engine: home.engine(), places: home.places)
        model.draft = "My reading list"
        #expect(model.level == .none, "Settings' default, None")
        Preferences.at(home.places).level = .watch
        #expect(model.level == .watch)
        model.draft = "A page that starts a reviewer agent in my shop"
        #expect(model.level == .run)
        model.place = .space(title: "Daily brief", name: "brief", page: "/Users/example/something/spaces/brief/index.html")
        #expect(!model.open, "the sticker")
    }

    /// Each space's level as its grant says it, None when never answered; a choice in Settings is Info's for that
    /// space, whichever space Info shows, and Run asks for its folder. Grants that do not read leave each unknown.
    @Test func eachSpacesLevelIsItsGrants() throws {
        let home = Home(prefix: "something-settings-"), ask = FakeAsk()
        defer { home.remove() }
        let shop = try home.space("shop", page(#"{"contract": 1, "title": "Shop", "rights": ["state", "send", "launch"]}"#, ""))
        let library = Library(places: home.places, ask: ask, share: Home.share)
        library.relist()
        #expect(library.levels() == [.init(id: "shop", title: "Shop", level: Grant.Level.none, folder: nil)])
        let info = Info(places: home.places, ask: ask)
        info.choose(.talk, in: shop)
        #expect(library.levels().first?.level == .talk && info.level == nil, "Info, showing no space, shows none")
        var asked = 0
        info.pick = { answer in
            asked += 1
            answer("/Users/example/code/shop")
        }
        info.choose(.run, in: shop)
        #expect(asked == 1 && library.levels() == [.init(id: "shop", title: "Shop", level: .run, folder: "/Users/example/code/shop")])
        #expect(ask.told.isEmpty, "\(ask.told)")
        try "not json".write(to: home.places.grants, atomically: true, encoding: .utf8)
        #expect(library.levels().first?.level == nil)
    }

    /// The three parts are what their folders weigh, file by file, and the used weight is their sum.
    @Test func theStoresPartsAddUpToWhatTheFoldersWeigh() throws {
        let home = Home(prefix: "something-settings-")
        defer { home.remove() }
        let page = home.places.spaces.appendingPathComponent("board/index.html")
        try FileManager.default.createDirectory(at: page.deletingLastPathComponent(), withIntermediateDirectories: true)
        try String(repeating: "a", count: 1_000).write(to: page, atomically: true, encoding: .utf8)
        let space = try #require(Spaces(root: home.places.spaces).named("board"))
        try Versions(root: home.places.versions, keep: 0, limit: 0).capture(space, kind: .turn, sentence: "An invented change", who: "Claude Code", at: Date())
        try FileManager.default.createDirectory(at: home.places.data, withIntermediateDirectories: true)
        try Data(count: 300).write(to: home.places.data.appendingPathComponent("board.json"))
        try Data(count: 50).write(to: home.places.spaces.appendingPathComponent(".hidden"))
        let storage = Storage.weigh(home.places)
        let index = try #require(try home.places.versions.appendingPathComponent("board/index.json").resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(storage.spaces == 1_050 && storage.memory == 300 && storage.versions == 1_000 + index)
        #expect(storage.used == storage.versions + storage.memory + storage.spaces)
        #expect(Storage.bytes(home.root.appendingPathComponent("nowhere")) == 0)
        #expect(Storage.megabytes(312_400_000) == "312 MB" && Storage.megabytes(0) == "0 MB" && Storage.megabytes(1_000) == "less than 1 MB")
    }
}
