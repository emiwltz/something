// Settings: each control writes only its own key, the values shown at first are the mockup's (CM_PREFS), Auto lets
// the Mac choose the appearance and Dark sets darkAqua, the launcher switch removes only the launcher something made,
// Homebrew is named only under a Cellar, the shortcuts are Keys' own, the window takes each tab's height, and "When
// something opens" decides the space opened at the start. Permissions holds the README's promise and no Always Allow;
// Agents splits the registry by builder and looks again once; the menu items open their tabs.
import AppKit
import SomethingAgents
import SomethingCore
import SwiftUI
import Testing
@testable import something

@MainActor @Suite(.serialized, .leavesNothing("something-settings-")) struct SettingsTests {
    nonisolated static let cellar = URL(fileURLWithPath: "/opt/homebrew/Cellar/something/0.3.0/something.app")

    /// A model on a fresh home, its effects recorded rather than applied to this process.
    func model(_ home: Home, app: URL = SettingsTests.cellar) -> (SettingsModel, Effects) {
        let model = SettingsModel(preferences: Preferences(home.places), places: home.places, app: app, version: "0.3.0")
        let effects = Effects()
        model.spaces = { [("brief", "Daily brief"), ("logbook", "Logbook")] }
        model.apply = { effects.applied.append(($0, $1)) }
        model.tour = { effects.tours += 1 }
        model.keyboard = { effects.keyboards += 1 }
        model.told = { effects.told.append($0) }
        model.chose = { effects.chosen.append($0) }
        model.asking = { effects.asking.append($0) }
        model.lookAgain = { effects.looks += 1 }
        // Invented places; no program is looked for, let alone run.
        model.locate = { ["claude": "/opt/homebrew/bin/claude", "codex": "/Users/example/.local/bin/codex", "cursor": "/Applications/Cursor.app"][$0] }
        model.versions = { ["claude": "2.1.4", "cursor": "1.8"] }
        return (model, effects)
    }

    final class Effects {
        var applied: [(Preferences.Appearance, Look.Motion)] = [], tours = 0, keyboards = 0, told: [String] = []
        var chosen: [String] = [], asking: [Bool] = [], looks = 0
    }

    /// The values as the file would hold them, key by key.
    static func keys(_ values: Preferences.Values) throws -> [String: String] {
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(values)) as? [String: Any])
        return object.mapValues { "\($0)" }
    }

    @Test func eachControlWritesOnlyItsKey() throws {
        let home = Home(prefix: "something-settings-")
        defer { home.remove() }
        let (model, effects) = model(home)
        var listed = Options()
        (listed.model, listed.effort) = ([Option(value: "opus", label: "Opus 5.5")], [Option(value: "high", label: "High")])
        model.preferences.listed["claude"] = listed
        // The launcher switch writes no key: the disk says whether the launcher is there; the lock writes none.
        let expected: [String: String?] = ["When something opens": "openAtStart", "Add something to Applications": nil,
                        "Agent": "assistant", "Model": "model", "Effort": "effort", "Resume each space’s conversation": "resume",
                        "Put idle assistants to sleep after": "sleepAfter", "Keep at most": "awakeAtMost",
                        "Ask Before Every Change": "askEverything", "Requests always wait for your click": nil,
                        "Notify me when a request waits": "notify",
                        "Motion": "motion", "When a space opens, its assistant is": "assistantAtOpening",
                        "Remember where I put the assistant": "rememberSticker", "Show each assistant’s eyes in the sidebar": "sidebarEyes",
                        "Hold ⌥ to point inside a drawn frame": "holdOption"]
        var seen: Set<String> = []
        for tab in SettingsTab.allCases {
            for row in model.sections(tab).flatMap(\.rows) {
                let before = try Self.keys(model.preferences.values)
                switch row.control {
                case .choice(let options, let get, let set):
                    let other = try #require(options.first { !$0.heading && $0.value != get() })
                    set(other.value)
                    #expect(get() == other.value, "\(row.title)")
                case .toggle(let get, let set, let enabled):
                    #expect(enabled, "\(row.title)")
                    let was = get()
                    set(!was)
                    #expect(get() == !was, "\(row.title)")
                case .button(let title, let run):
                    #expect(title == "Show Again")
                    run()
                    #expect(effects.tours == 1)
                case .locked(let word):
                    #expect(word == "Always")
                }
                let after = try Self.keys(model.preferences.values)
                let changed = Set(after.keys).union(before.keys).filter { before[$0] != after[$0] }
                let own = Set((expected[row.title] ?? nil).map { [$0] } ?? [])
                #expect(changed == own, "\(row.title) changed \(changed.sorted())")
                seen.insert(row.title)
            }
        }
        #expect(seen == Set(expected.keys).union(["Welcome tour"]))
        #expect(effects.applied.map(\.1) == [.reduced], "Motion applies at once")
        #expect(effects.chosen == ["codex"] && effects.asking == [true], "the assistant takes the default agent and Ask Before Every Change")
        // Appearance, drawn apart from the rows, writes only its key too.
        let before = try Self.keys(model.preferences.values)
        model.choose(.dark)
        let after = try Self.keys(model.preferences.values)
        #expect(Set(after.keys).filter { before[$0] != after[$0] } == ["appearance"])
        #expect(effects.applied.last?.0 == .dark)
        #expect(Preferences(home.places).values == model.preferences.values, "each change is on the disk")
        #expect(effects.told.isEmpty)
    }

    /// What the rows show on a fresh home: the mockup's CM_PREFS.
    @Test func theDefaultsShownAreTheMockups() throws {
        let home = Home(prefix: "something-settings-")
        defer { home.remove() }
        try Launcher.make(prefix: "/opt/homebrew", places: home.places, icon: nil)
        let (model, _) = model(home)
        var shown: [String: String] = [:]
        for row in SettingsTab.allCases.flatMap({ model.sections($0) }).flatMap(\.rows) {
            switch row.control {
            case .choice(let options, let get, _): shown[row.title] = options.first { $0.value == get() }?.label
            case .toggle(let get, _, _): shown[row.title] = get() ? "on" : "off"
            case .button(let title, _): shown[row.title] = title
            case .locked(let word): shown[row.title] = word
            }
        }
        // open:'last', apps:true, asstOpen:'Reduced', sticker:true, sideEyes:true, motion:'Calm', alt:true.
        #expect(shown == ["When something opens": "The last space you had open", "Add something to Applications": "on",
                          "Welcome tour": "Show Again", "Motion": "Calm", "When a space opens, its assistant is": "Reduced",
                          "Remember where I put the assistant": "on", "Show each assistant’s eyes in the sidebar": "on",
                          "Hold ⌥ to point inside a drawn frame": "on",
                          // agent:'Claude Code', resume:true, sleep:'10 minutes', awake:'3', askAll:false, notify:false; before
                          // Claude Code ever listed its models, its own (cannot_native: no settings file is read).
                          "Agent": "Claude Code", "Model": "Default model", "Effort": "Default effort", "Resume each space’s conversation": "on",
                          "Put idle assistants to sleep after": "10 minutes", "Keep at most": "3", "Ask Before Every Change": "off",
                          "Requests always wait for your click": "Always", "Notify me when a request waits": "off"])
        #expect(model.preferences.appearance == .system, "appearance:'System'")
        let opening = model.sections(.general)[0].rows[0]
        guard case .choice(let options, _, _) = opening.control else { Issue.record("not a choice"); return }
        #expect(options.map(\.label) == ["The last space you had open", "New Space", "A space", "Daily brief", "Logbook"])
        #expect(options.map(\.heading) == [false, false, true, false, false])
    }

    @Test func autoLetsTheMacChooseAndDarkIsDarkAqua() {
        #expect(Look.appearance(.system) == nil)
        #expect(Look.appearance(.dark)?.name == .darkAqua)
        #expect(Look.appearance(.light)?.name == .aqua)
    }

    /// The switch makes the launcher under Homebrew and removes only the one something made; anything else at its
    /// place stays, and the switch reads it as off.
    @Test func theLauncherSwitchRemovesOnlyItsOwnLauncher() throws {
        let home = Home(prefix: "something-settings-")
        defer { home.remove() }
        let (model, effects) = model(home)
        let toggle = try #require(model.sections(.general)[0].rows.first { $0.title == "Add something to Applications" })
        guard case .toggle(let get, let set, _) = toggle.control else { Issue.record("not a switch"); return }
        #expect(!get())
        set(true)
        #expect(get() && Launcher.made(places: home.places))
        set(false)
        #expect(!get() && !FileManager.default.fileExists(atPath: Launcher.place(home.places).path))
        // Someone else's something.app at that place.
        let other = Launcher.place(home.places).appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.example.other"], format: .xml, options: 0)
            .write(to: other.appendingPathComponent("Info.plist"))
        model.look()
        #expect(!get())
        set(false)
        #expect(FileManager.default.fileExists(atPath: other.path), "not something's: kept")
        #expect(effects.told.isEmpty)
        // Away from Homebrew there is nothing to add: the switch is greyed while no launcher of something's is there.
        let (elsewhere, _) = self.model(home, app: URL(fileURLWithPath: "/Applications/something.app"))
        guard case .toggle(_, _, let enabled) = elsewhere.sections(.general)[0].rows[1].control else { Issue.record("not a switch"); return }
        #expect(!enabled)
    }

    @Test func homebrewIsNamedOnlyUnderACellar() {
        let home = Home(prefix: "something-settings-")
        defer { home.remove() }
        let line = { (app: String) in self.model(home, app: URL(fileURLWithPath: app)).0.versionLine }
        #expect(line(SettingsTests.cellar.path) == ("something 0.3.0", " · installed with Homebrew · nothing leaves this Mac"))
        #expect(line("/Applications/something.app") == ("something 0.3.0", " · nothing leaves this Mac"))
        #expect(line("/opt/homebrew/something.app").rest == " · nothing leaves this Mac")
    }

    /// Settings › Shortcuts lists each command of the sheet once, in Keys' words and keys, Spaces and Show on the left.
    @Test func theShortcutsAreKeysOwn() {
        let listed = ShortcutColumns.columns.flatMap { $0.flatMap(ShortcutColumns.lines) }
        #expect(listed.map(\.id) == Keys.commands.filter { $0.area != nil && $0.line != nil }.sorted {
            ShortcutColumns.columns.flatMap { $0 }.firstIndex(of: $0.area!)! < ShortcutColumns.columns.flatMap { $0 }.firstIndex(of: $1.area!)!
        }.map(\.id))
        #expect(ShortcutColumns.columns == [[.spaces, .show], [.assistant, .window]])
        #expect(ShortcutColumns.caps("⇧⌘T") == [.key("⇧"), .key("⌘"), .key("T")])
        #expect(ShortcutColumns.caps("esc") == [.key("esc")])
        #expect(ShortcutColumns.caps("hold ⌥") == [.word("hold"), .key("⌥")])
        #expect(ShortcutColumns.caps("⌘1 … ⌘9") == [.key("⌘"), .key("1"), .word("to"), .key("⌘"), .key("9")])
        #expect(Keys.command("settings")?.action == #selector(App.showSettings(_:)))
    }

    /// Permissions says the README's promise character for character, and offers no Always Allow: the one mention is
    /// the sentence that says there is none.
    @Test func permissionsSayTheReadmesPromiseAndNoAlwaysAllow() throws {
        let readme = try String(contentsOf: Home.share.deletingLastPathComponent().appendingPathComponent("README.md"), encoding: .utf8)
        #expect(readme.split(whereSeparator: \.isWhitespace).joined(separator: " ").contains(Promise.sentence))
        let home = Home(prefix: "something-settings-")
        defer { home.remove() }
        let (model, _) = model(home)
        var words: [String] = []
        for row in SettingsTab.allCases.flatMap({ model.sections($0) }).flatMap(\.rows) {
            words += [row.title, row.note.replacingOccurrences(of: "There is no Always Allow.", with: "")]
            switch row.control {
            case .choice(let options, _, _): words += options.map(\.label)
            case .button(let title, _), .locked(let title): words.append(title)
            case .toggle: break
            }
        }
        #expect(!words.contains { $0.contains("Always Allow") })
        let lock = try #require(model.sections(.permissions).flatMap(\.rows).first { $0.title == "Requests always wait for your click" })
        guard case .locked = lock.control else { Issue.record("not locked"); return }
    }

    /// Agents: the registry's builders, then the agents something only sees, each with where its program was found and
    /// the version its files name; the default is marked; Look Again looks once and says when, by the clock.
    @Test func agentsAreTheRegistrysSplitByBuilder() async throws {
        let home = Home(prefix: "something-settings-")
        defer { home.remove() }
        let (model, effects) = model(home)
        #expect(model.lookedLine == "Looking for agents on this Mac…" && model.agents.allSatisfy { $0.path == nil })
        model.find()
        _ = await wait(3, until: { model.paths != nil })
        let agents = model.agents
        #expect(agents.filter(\.builds).map(\.id) == Registry.app.builders.map(\.kind))
        #expect(agents.filter { !$0.builds }.map(\.id) == Registry.app.agents.filter { $0.builder == nil }.map(\.kind))
        let claude = try #require(agents.first { $0.id == "claude" }), codex = try #require(agents.first { $0.id == "codex" })
        #expect(claude.isDefault && claude.path == "/opt/homebrew/bin/claude" && claude.version == "2.1.4")
        #expect(claude.note == "Resumes each space’s conversation")
        #expect(!codex.isDefault && codex.version == "version unknown" && codex.note == "Starts each conversation fresh, and says so")
        let pi = try #require(agents.first { $0.id == "pi" })
        #expect(pi.path == nil && pi.version == nil && pi.note.hasPrefix("Not found on this Mac. To install it, type in Terminal: "))
        let cursor = try #require(agents.first { $0.id == "cursor" })
        #expect(!cursor.builds && cursor.path == "/Applications/Cursor.app" && cursor.note == Registry.app.agent("cursor")?.unavailable)
        #expect(model.lookedLine == "Looked when something opened · 3 agents")
        // Choosing Codex as the default marks it.
        model.preferences.assistant = "codex"
        #expect(model.agents.filter(\.isDefault).map(\.id) == ["codex"])
        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 18, minute: 2)))
        model.clock = { now }
        model.again()
        #expect(effects.looks == 1, "Look Again asks the engine once")
        _ = await wait(3, until: { model.paths != nil && model.looked != nil })
        #expect(model.lookedLine == "Looked today at 18:02 · 3 agents")
        Settings.looked = nil
    }

    /// The Assistant menu's Ask Before Every Change… and the assistant's Defaults for New Spaces… open their tabs.
    @Test func theMenuItemsOpenTheirTabs() {
        #expect(Keys.command("askAll")?.action == #selector(App.showPermissions(_:)) && Settings.opens["askAll"] == .permissions)
        #expect(Keys.command("defaults")?.action == #selector(App.showNewSpaceDefaults(_:)) && Settings.opens["defaults"] == .assistant)
        #expect(Keys.command("defaults")?.title == AssistantModel.defaultsTitle)
        #expect(Keys.command("lookAgain")?.action == #selector(App.lookForAgentsAgain(_:)))
        #expect(Keys.enabled("askAll", Keys.Situation()))
    }

    /// The window: the preference toolbar with the three tabs, 720 points wide, as high as each tab, titled by it.
    @Test(.enabled(if: windowServer, windowServerMissing)) func theWindowTakesEachTabsHeight() async throws {
        let home = Home(prefix: "something-settings-")
        defer { home.remove() }
        let settings = SettingsWindow(model(home).0)
        settings.window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        settings.window.alphaValue = 0
        defer { settings.window.close() }
        #expect(settings.window.toolbarStyle == .preference)
        #expect(settings.window.toolbar?.items.map(\.label) == ["General", "Assistant", "Permissions", "Interface", "Shortcuts", "Agents"])
        var heights: [CGFloat] = []
        for tab in SettingsTab.allCases {
            settings.select(tab)
            settings.window.layoutIfNeeded()
            _ = await wait(3, until: {
                let page = settings.tabs.tabViewItems[settings.tabs.selectedTabViewItemIndex].viewController
                return abs(settings.window.contentRect(forFrameRect: settings.window.frame).height - (page?.preferredContentSize.height ?? 0)) <= 1
            })
            let content = settings.window.contentRect(forFrameRect: settings.window.frame).size
            #expect(settings.tab == tab && settings.window.title == tab.label)
            #expect(abs(content.width - 720) < 1, "\(tab)")
            heights.append(content.height)
        }
        #expect(Set(heights.map { Int($0) }).count == SettingsTab.allCases.count, "each tab its own height: \(heights)")
        // A click on a toolbar tab goes through the tab view, not the index: the title follows it too.
        settings.tabs.tabView.selectTabViewItem(at: 3)
        #expect(settings.tab == .interface && settings.window.title == "Interface")
        #expect(settings.window.styleMask.contains(.miniaturizable), "three lights, as the Mac's own settings")
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

    /// "When a space opens, its assistant is": Reduced arrives at a space as the sticker, Open with the card open; from
    /// one space to another the card stays as it was.
    @Test func theAssistantAtOpeningFollowsTheSetting() {
        let home = Home(prefix: "something-settings-")
        defer { home.remove() }
        let model = AssistantModel(engine: home.engine(), places: home.places)
        let brief = AssistantModel.Place.space(title: "Daily brief", name: "brief", page: "/Users/example/something/spaces/brief/index.html")
        let logbook = AssistantModel.Place.space(title: "Logbook", name: "logbook", page: "/Users/example/something/spaces/logbook/index.html")
        #expect(Preferences.at(home.places).assistantAtOpening == .reduced)
        model.place = brief
        #expect(!model.open, "Reduced: the sticker")
        model.place = .blank
        model.open = false
        Preferences.at(home.places).assistantAtOpening = .open
        model.place = brief
        #expect(model.open, "Open: the card")
        model.open = false
        model.place = logbook
        #expect(!model.open, "from one space to another the card stays as it was")
    }
}
