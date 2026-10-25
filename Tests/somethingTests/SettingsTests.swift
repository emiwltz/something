// Settings: each control writes only its own key, the values shown at first are the mockup's (CM_PREFS), Auto lets
// the Mac choose the appearance and Dark sets darkAqua, the launcher switch removes only the launcher something made,
// Homebrew is named only under a Cellar, the shortcuts are Keys' own, the window takes each tab's height, and "When
// something opens" decides the space opened at the start.
import AppKit
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
        return (model, effects)
    }

    final class Effects {
        var applied: [(Preferences.Appearance, Look.Motion)] = [], tours = 0, keyboards = 0, told: [String] = []
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
        // The launcher switch writes no key: the disk says whether the launcher is there.
        let expected: [String: String?] = ["When something opens": "openAtStart", "Add something to Applications": nil,
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
            }
        }
        // open:'last', apps:true, asstOpen:'Reduced', sticker:true, sideEyes:true, motion:'Calm', alt:true.
        #expect(shown == ["When something opens": "The last space you had open", "Add something to Applications": "on",
                          "Welcome tour": "Show Again", "Motion": "Calm", "When a space opens, its assistant is": "Reduced",
                          "Remember where I put the assistant": "on", "Show each assistant’s eyes in the sidebar": "on",
                          "Hold ⌥ to point inside a drawn frame": "on"])
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

    /// The window: the preference toolbar with the three tabs, 720 points wide, as high as each tab, titled by it.
    @Test(.enabled(if: windowServer, windowServerMissing)) func theWindowTakesEachTabsHeight() async throws {
        let home = Home(prefix: "something-settings-")
        defer { home.remove() }
        let settings = SettingsWindow(model(home).0)
        settings.window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        settings.window.alphaValue = 0
        defer { settings.window.close() }
        #expect(settings.window.toolbarStyle == .preference)
        #expect(settings.window.toolbar?.items.map(\.label) == ["General", "Interface", "Shortcuts"])
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
        #expect(Set(heights.map { Int($0) }).count == 3, "each tab its own height: \(heights)")
        // A click on a toolbar tab goes through the tab view, not the index: the title follows it too.
        settings.tabs.tabView.selectTabViewItem(at: 1)
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
