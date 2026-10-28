// Settings (⌘,): a window of its own whose toolbar holds four tabs, as the Mac's own settings do, sized to each tab:
// General (the start, the theme, the interface size, the sidebar), Spaces (where they live, export, versions and
// storage, Storage.swift), Agents (your assistant, what a new space may do, each space's level, and the agents on this
// Mac, found by a look at files that never runs one) and Advanced (Full Access, how your assistant and the agents a
// space starts ask, the lasting rules with Revoke, the assistants' rest and resume, the shortcuts). Each tab is a list of rows given as data (a title, a note, a
// control), so that a test can work every control and see which key it wrote. The theme applies at once, everywhere.
import AppKit
import SomethingAgents
import SomethingCore
import SwiftUI

/// The tabs, in the toolbar's order.
enum SettingsTab: String, CaseIterable {
    case general, spaces, agents, advanced

    var label: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .spaces: "doc"
        case .agents: "powerplug.portrait"
        case .advanced: "checkmark.shield"
        }
    }
}

/// One row of a settings tab: what it is, a line that says what it does (Markdown: `code` is a path), and its control.
struct SettingsRow: Identifiable {
    /// One item of a choice; a heading starts a section of its menu and cannot be chosen.
    struct Option: Hashable { let value: String, label: String; var heading = false }

    enum Control {
        /// A choice; `get` gives the value chosen in each section of the menu.
        case choice([Option], get: () -> [String], set: (String) -> Void)
        case toggle(get: () -> Bool, set: (Bool) -> Void)
        /// A button, its symbol before its title.
        case button(String, symbol: String? = nil, () -> Void)
        /// Words in place of a control: what is not chosen here.
        case said(String)
    }

    /// How a choice is drawn: a menu, "Aa" tiles, the theme's pictures, or segments side by side.
    enum Style { case menu, tiles, thumbs, segments }

    let title: String, note: String, control: Control
    var style = Style.menu
    /// The control under the words rather than beside them.
    var wrap = false
    /// The words after the control when it stands inside the title's sentence: "Keep [50] versions of each space".
    var trail: String?
    /// Keys said under the note.
    var keys: [(key: String, words: String)] = []
    /// What tells two rows of one title apart (two spaces of one name).
    var tag: String?
    /// The title in code (a command), after the monogram of the agent named `mark`.
    var code = false, mark: String?
    var id: String { tag ?? title }
}

/// A titled group: its rows in a card, then a line, then more rows in a card of their own; Storage draws the store's
/// weight with its one row, the limit, and Agents' last group the agents found.
struct SettingsSection: Identifiable {
    enum Block { case storage, found }
    let title: String, rows: [SettingsRow]
    var lead: String?
    var more: [SettingsRow] = []
    var block: Block?
    var id: String { title }
}

/// What Settings shows and changes: the preferences, and the few things a row does beyond writing its key.
@MainActor @Observable final class SettingsModel {
    /// A space and its level as its grant says it; nil when not known.
    struct SpaceLevel: Equatable { let id: String, title: String, level: Grant.Level?, folder: String? }

    let preferences: Preferences
    @ObservationIgnored let places: Places
    /// The spaces "When something opens" offers, by name and title.
    @ObservationIgnored var spaces: () -> [(id: String, title: String)] = { [] }
    /// Applies the appearance to the whole app; tests record it instead.
    @ObservationIgnored var apply: (Preferences.Appearance) -> Void = { NSApp.appearance = Look.appearance($0) }
    /// Applies the interface size to the whole app (Look.scale); tests record it instead.
    @ObservationIgnored var resize: (Look.Size) -> Void = { Look.scale.size = $0 }
    /// Whether the window's sidebar floats (its column hidden), and making it so: the window's.
    @ObservationIgnored var floating: () -> Bool = { false }
    @ObservationIgnored var float: (Bool) -> Void = { _ in }
    /// Shows the shortcuts (⌘/) over the window.
    @ObservationIgnored var shortcuts: () -> Void = {}
    /// Each space's level, and the person's choice of one (Info.choose, which asks for Run's folder).
    @ObservationIgnored var levels: () -> [SpaceLevel] = { [] }
    @ObservationIgnored var setLevel: (String, Grant.Level) -> Void = { _, _ in }
    /// Every lasting rule, and Revoke (Rules.swift).
    @ObservationIgnored var rules: () -> [LastingRule] = { [] }
    @ObservationIgnored var revoke: (LastingRule) -> Void = { _ in }
    /// Full Access turned on (after its confirmation) or off: the app's.
    @ObservationIgnored var fullAccess: (Bool) -> Void = { _ in }
    /// The builders the assistant offers now (AssistantModel); every builder until the window says otherwise.
    @ObservationIgnored var offered: () -> [String] = { Registry.app.builders.map(\.kind) }
    /// The default agent just chosen, for the assistant to take (Build With's own path, AssistantModel.buildNew).
    @ObservationIgnored var chose: (String) -> Void = { _ in }
    /// Ask Before Every Change just turned on or off, for the assistant to take from its next conversation.
    @ObservationIgnored var asking: (Bool) -> Void = { _ in }
    /// Looks for the agents again (AssistantModel.lookAgain, then Engine.lookAgain).
    @ObservationIgnored var lookAgain: () -> Void = {}
    /// Where the program of a kind is, or why it is not known to be there (Found.outcome); called off the main queue,
    /// as a login shell may be read.
    @ObservationIgnored var locate: (String) -> Result<String, CodedError> = Found.outcome
    /// The newest version each kind's files on this Mac name (the state's `seen`).
    @ObservationIgnored var versions: () -> [String: String] = { [:] }
    @ObservationIgnored var clock: () -> Date = Date.init
    /// Where each agent was found, or why not, by kind; nil while a look runs.
    private(set) var found: [String: Result<String, CodedError>]?
    private(set) var seen: [String: String] = [:]
    /// When the last look ended, by `clock`; nil while none has.
    private(set) var looked: Date?
    private(set) var floats = false
    private(set) var spaceLevels: [SpaceLevel] = []
    private(set) var lasting: [LastingRule] = []
    /// How tall each tab's rows are, as last drawn: its page is as tall, up to SettingsPage.most.
    var heights: [SettingsTab: CGFloat] = [:]
    /// What the store weighs (Storage.swift); nil until it was first measured.
    var storage: Storage?
    /// Weighs the store, off the main queue; tests give invented weights.
    @ObservationIgnored var weigh: @Sendable (Places) -> Storage = Storage.weigh
    /// Show in Finder; tests record it.
    @ObservationIgnored var reveal: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }

    init(preferences: Preferences, places: Places) {
        (self.preferences, self.places) = (preferences, places)
        look()
    }

    /// Reads again what lives elsewhere than in the preferences: the window's sidebar, the levels, the versions seen.
    func look() {
        (floats, spaceLevels, seen, lasting) = (floating(), levels(), versions(), rules())
    }

    /// Look Again: the engine looks for the programs again, and so does this window, which says it is looking meanwhile.
    func again() {
        lookAgain()
        find()
    }

    /// Finds where each agent is off the main queue, then shows it with the versions known by then and when it ended.
    func find() {
        found = nil
        let kinds = Registry.app.agents.map(\.kind), locate = locate
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = kinds.reduce(into: [String: Result<String, CodedError>]()) { $0[$1] = locate($1) }
            DispatchQueue.main.async {
                guard let self else { return }
                (self.found, self.looked) = (found, self.clock())
                self.look()
            }
        }
    }

    /// The rows of `tab`.
    func sections(_ tab: SettingsTab) -> [SettingsSection] {
        switch tab {
        case .general: general()
        case .spaces: storageSections()
        case .agents: agentSections()
        case .advanced: advancedSections()
        }
    }

    func toggle(_ key: WritableKeyPath<Preferences.Values, Bool>) -> SettingsRow.Control {
        let preferences = preferences
        return .toggle(get: { preferences.values[keyPath: key] }, set: { value in preferences.change { $0[keyPath: key] = value } })
    }

    func choice<T: RawRepresentable>(_ key: WritableKeyPath<Preferences.Values, T>, _ options: [(T, String)], then: @escaping () -> Void = {})
        -> SettingsRow.Control where T.RawValue == String {
        let preferences = preferences
        return .choice(options.map { SettingsRow.Option(value: $0.0.rawValue, label: $0.1) }, get: { [preferences.values[keyPath: key].rawValue] }, set: { raw in
            guard let value = T(rawValue: raw) else { return }
            preferences.change { $0[keyPath: key] = value }
            then()
        })
    }

    /// A choice among numbers, written to `key`.
    func number(_ key: WritableKeyPath<Preferences.Values, Int>, _ options: [(Int, String)]) -> SettingsRow.Control {
        let preferences = preferences
        return .choice(options.map { SettingsRow.Option(value: String($0.0), label: $0.1) }, get: { [String(preferences.values[keyPath: key])] }, set: { raw in
            if let value = Int(raw) { preferences.change { $0[keyPath: key] = value } }
        })
    }

    /// General: the start; the theme, the interface size and the sidebar.
    private func general() -> [SettingsSection] {
        let preferences = preferences
        let sidebar = SettingsRow.Control.choice([.init(value: "pinned", label: "Pinned"), .init(value: "floating", label: "Floating")],
                                                 get: { [self.floats ? "floating" : "pinned"] }, set: { [weak self] in
            guard let self else { return }
            float($0 == "floating")
            floats = floating()
        })
        return [
            SettingsSection(title: "Start", rows: [SettingsRow(title: "When something opens", note: "The page you see first.", control: opening())]),
            SettingsSection(title: "Look", rows: [
                SettingsRow(title: "Theme", note: "Auto follows your Mac, day and night.",
                            control: choice(\.appearance, [(.system, "Auto"), (.light, "Light"), (.dark, "Dark")]) { [weak self] in self?.apply(preferences.appearance) },
                            style: .thumbs),
                SettingsRow(title: "Interface size",
                            note: "The whole app grows: sidebar, toolbar, assistant, sheets, palette, and your spaces’ pages.",
                            control: choice(\.size, Look.Size.allCases.map { ($0, $0.label) }) { [weak self] in self?.resize(preferences.size) },
                            style: .tiles, keys: [("⌘+", "bigger"), ("⌘−", "smaller"), ("⌘0", "default, from anywhere")]),
                SettingsRow(title: "Sidebar", note: floats ? "Over the page when the pointer rests on the window’s left edge."
                                : "Always beside your spaces. ⌃⌘S hides it for a while.", control: sidebar, style: .segments),
            ]),
        ]
    }

    /// Agents: your assistant, what a new space may do and each space's level, then the agents on this Mac.
    private func agentSections() -> [SettingsSection] {
        let preferences = preferences, registry = Registry.app
        let first = offered().first ?? registry.builders.first?.kind ?? "", kind = preferences.assistant ?? first
        let kinds = offered() + (offered().contains(kind) || kind.isEmpty ? [] : [kind])
        let levels = Grant.Level.allCases.map { ($0, $0.title) }
        return [
            SettingsSection(title: "Your assistant", rows: [
                SettingsRow(title: "Agent", note: "It builds and changes your spaces, only in `~/something/spaces`. Anything else, it asks you.",
                            control: .choice(kinds.map { SettingsRow.Option(value: $0, label: registry.name(of: $0)) }, get: { [preferences.assistant ?? first] }, set: { [weak self] chosen in
                                // Another agent's model and effort mean nothing to this one (AssistantModel.keepDefault).
                                preferences.change { if $0.assistant != chosen { ($0.assistant, $0.model, $0.effort) = (chosen, nil, nil) } }
                                self?.chose(chosen)
                            })),
                model(of: kind),
            ]),
            SettingsSection(title: "Spaces and your agents", rows: [
                SettingsRow(title: "A new space may", note: preferences.level.sentence + " New Space starts here when your words name no agent.",
                            control: choice(\.level, levels), style: .segments, wrap: true),
                SettingsRow(title: "Notify me when an agent asks", note: "A banner of the Mac when something is in the background. It never shows the command.",
                            control: toggle(\.notify)),
            ], lead: "Each space and what it may do. One click changes it.", more: spaceLevels.map { space in
                SettingsRow(title: space.title, note: space.level == .run ? space.folder.map { "in `\(Words.path($0, home: places.home.path))`" } ?? "" : "",
                            control: space.level.map { level in
                                .choice(levels.map { SettingsRow.Option(value: $0.0.rawValue, label: $0.1) }, get: { [level.rawValue] }, set: { [weak self] in
                                    self?.setLevel(space.id, Grant.Level(rawValue: $0) ?? .none)
                                    self?.look()
                                })
                            } ?? .said("Not known"), tag: space.id)
            }),
            SettingsSection(title: "On this Mac", rows: [], block: .found),
        ]
    }

    /// The model, and the effort when the agent takes one, in one menu: the names the agent last listed for `kind`,
    /// "Default" its own setting; before any list, what is known.
    private func model(of kind: String) -> SettingsRow {
        let preferences = preferences, limits = Registry.app.limits[kind] ?? [], listed = preferences.listed[kind]
        guard !limits.contains("model"), let models = listed?.model else {
            return SettingsRow(title: "Model", note: "", control: .said(limits.contains("model") ? "\(Registry.app.name(of: kind)) chooses its own model"
                                                                                                    : "Its models show after its first run"))
        }
        let effort = !limits.contains("effort")
        func options(_ prefix: String, _ own: String, _ listed: [Option]) -> [SettingsRow.Option] {
            [SettingsRow.Option(value: prefix, label: own)] + listed.map { SettingsRow.Option(value: prefix + $0.value, label: $0.label) }
        }
        let all = (effort ? [SettingsRow.Option(value: "", label: "Model", heading: true)] : []) + options("", "Default model", models)
            + (effort ? [SettingsRow.Option(value: "", label: "Effort", heading: true)] + options("effort:", "Default effort", listed?.effort ?? []) : [])
        return SettingsRow(title: effort ? "Model and effort" : "Model", note: "“Default” follows the agent’s own setting.", control: .choice(all, get: {
            [preferences.model ?? "", "effort:" + (preferences.effort ?? "")]
        }, set: { value in
            let effort = value.hasPrefix("effort:"), chosen = effort ? String(value.dropFirst(7)) : value
            preferences.change { $0[keyPath: effort ? \Preferences.Values.effort : \.model] = chosen.isEmpty ? nil : chosen }
        }))
    }

    /// Advanced: who asks, the lasting rules, the assistants' rest and resume, and the shortcuts.
    private func advancedSections() -> [SettingsSection] {
        let preferences = preferences, builders = Registry.app.builders
        let resuming = builders.filter { Registry.resumesAsBuilt.contains($0.kind) }.map(\.name)
        let fresh = builders.filter { !Registry.resumesAsBuilt.contains($0.kind) }.map(\.name)
        let minutes = [(5, "5 minutes"), (10, "10 minutes"), (30, "30 minutes"), (60, "1 hour"), (0, "Never")]
        return [
            SettingsSection(title: "Permissions", rows: [
                SettingsRow(title: "Full Access", note: "Nobody asks: your assistant gets every permission. The agents your spaces start keep their own settings. "
                                + "An orange mark stays in the toolbar while it is on.",
                            control: .toggle(get: { preferences.fullAccess }, set: { [weak self] in self?.fullAccess($0) })),
                SettingsRow(title: "Your assistant asks before every change", note: "Off: it changes your spaces freely and asks for anything else.",
                            control: .toggle(get: { preferences.askEverything }, set: { [weak self] value in
                                preferences.askEverything = value
                                self?.asking(value)
                            })),
                SettingsRow(title: "Agents a space starts", note: "Each agent asks you as it usually does.", control: .said("Their Own Settings")),
            ], lead: Promise.sentence),
            SettingsSection(title: "Lasting rules", rows: [], lead: "Made with “Always for this space” in the request panel, and shown in each space’s Info."
                                + (lasting.isEmpty ? " None yet." : ""), more: lasting.map { kept in
                SettingsRow(title: kept.rule.command, note: Rules.line(kept.rule, space: kept.title, home: places.home.path, now: clock()),
                            control: .button("Revoke") { [weak self] in
                                self?.revoke(kept)
                                self?.look()
                            }, tag: kept.id, code: true, mark: Registry.app.name(of: kept.rule.kind))
            }),
            SettingsSection(title: "Assistants", rows: [
                SettingsRow(title: "Resume each space’s conversation",
                            note: "\(Words.list(resuming, "and")) can. \(Words.list(fresh, "and")) start fresh, and say so.", control: toggle(\.resume)),
                SettingsRow(title: "Put idle assistants to sleep after", note: "The open space’s assistant and working ones stay awake.",
                            control: number(\.sleepAfter, minutes)),
                SettingsRow(title: "Keep at most", note: "When one more wakes, the one idle the longest goes to sleep. A sleeping assistant wakes on your next message.",
                            control: number(\.awakeAtMost, (1...5).map { ($0, String($0)) }), trail: "assistants awake"),
            ]),
            SettingsSection(title: "Keyboard", rows: [
                SettingsRow(title: "Keyboard shortcuts", note: "⌘/ shows them all, wherever you are.",
                            control: .button("Show Shortcuts", symbol: "keyboard") { [weak self] in self?.shortcuts() }),
            ]),
        ]
    }

    /// One agent found on this Mac: its name and what its files say of its version, or that something only sees it.
    struct AgentLine: Identifiable, Equatable { let id: String, name: String, line: String }

    /// The agents found, the builders first.
    var agents: [AgentLine] {
        let all = Registry.app.agents
        return (all.filter { $0.builder != nil } + all.filter { $0.builder == nil }).compactMap { agent in
            guard (try? found?[agent.kind]?.get()) != nil else { return nil }
            return AgentLine(id: agent.kind, name: agent.name,
                             line: agent.builder == nil ? "Seen only" : seen[agent.kind].map { "Version \($0)" } ?? "Version unknown")
        }
    }

    /// Under the agents: how many were found and when something last looked, and what it never does to them.
    var lookedLine: String {
        guard found != nil, let looked else { return "Looking for agents on this Mac…" }
        let count = agents.count, day = Info.day(looked, now: clock())
        let when = ["Today", "Yesterday"].contains(day) ? day.lowercased() : "on " + day
        return "Found \(count) agent\(count == 1 ? "" : "s") · looked \(when) at \(Presence.clock.string(from: looked)). "
            + "something never installs them or changes their settings."
    }

    /// "When something opens": the last space, New Space, or one space. A space no longer there reads as the last.
    private func opening() -> SettingsRow.Control {
        let spaces = spaces(), preferences = preferences
        let options = [SettingsRow.Option(value: "last", label: "The last space you had open"), SettingsRow.Option(value: "new", label: "New Space"),
                       SettingsRow.Option(value: "", label: "A space", heading: true)] + spaces.map { SettingsRow.Option(value: $0.id, label: $0.title) }
        return .choice(options, get: {
            let chosen = preferences.openAtStart
            return [chosen == "new" || spaces.contains { $0.id == chosen } ? chosen : "last"]
        }, set: { value in preferences.openAtStart = value })
    }
}

/// The Settings window and its one copy.
@MainActor enum Settings {
    static var shown: SettingsWindow?

    /// Shows the one Settings window, made by `make` the first time, at `tab` when given, else where it was left.
    @discardableResult static func open(_ tab: SettingsTab?, make: () -> SettingsWindow) -> SettingsWindow {
        let window = shown ?? make()
        shown = window
        if let tab { window.select(tab) }
        window.model.look()
        window.model.measure()
        window.window.makeKeyAndOrderFront(nil)
        return window
    }

    /// Applies the person's appearance and motion to the whole app, at the start.
    static func apply(_ appearance: Preferences.Appearance, _ motion: Look.Motion) {
        NSApp.appearance = Look.appearance(appearance)
        Look.chosen = motion
    }
}

extension Shell {
    /// The size `step` sizes from the person's, clamped at the ends, or Default for nil: kept, followed by Look, and
    /// said in the toast it returns.
    @discardableResult func resize(by step: Int?) -> Toast {
        let sizes = Look.Size.allCases, now = sizes.firstIndex(of: library.preferences.size) ?? 0
        let size = step.map { sizes[max(0, min(sizes.count - 1, now + $0))] } ?? .standard
        // The views that read Look follow it, and Shell the rest.
        (library.preferences.size, Look.scale.size) = (size, size)
        return toast("Interface: \(size.label) · ⌘+ bigger · ⌘− smaller · ⌘0 default", quiet: true)
    }
}

extension App {
    /// Settings… (⌘,): the window, made the first time, at `tab` when given, else where it was left.
    @MainActor @objc func showSettings(_ sender: Any?) { settings(nil) }

    /// View › Make Interface Bigger (⌘+), Smaller (⌘−) and Default Size (⌘0): the next size, said in a toast.
    @MainActor @objc func biggerInterface(_ sender: Any?) { shell.resize(by: 1) }
    @MainActor @objc func smallerInterface(_ sender: Any?) { shell.resize(by: -1) }
    @MainActor @objc func defaultInterfaceSize(_ sender: Any?) { shell.resize(by: nil) }

    @MainActor func settings(_ tab: SettingsTab?) {
        Settings.open(tab) {
            let model = SettingsModel(preferences: library.preferences, places: places)
            model.spaces = { [weak self] in self?.library.order().filter(\.isSpace).map { ($0.id, $0.title) } ?? [] }
            model.floating = { [weak self] in self?.shell.split.splitViewItems[0].isCollapsed ?? false }
            model.float = { [weak self] in self?.shell.split.splitViewItems[0].isCollapsed = $0 }
            model.shortcuts = { [weak self] in self?.showKeys(nil) }
            model.levels = { [weak self] in self?.library.levels() ?? [] }
            model.setLevel = { [weak self] name, level in
                if let space = self?.library.entry(name)?.space { self?.info.choose(level, in: space) }
            }
            model.offered = { [weak self] in self.map { app in app.assistant.builders.filter { app.assistant.installed[$0] == true } } ?? [] }
            model.chose = { [weak self] in _ = self?.assistant.buildNew(with: $0) }
            model.asking = { [weak self] on in if let assistant = self?.assistant, assistant.askEverything != on { assistant.toggleAsking() } }
            model.lookAgain = { [weak self] in self?.assistant.lookAgain() }
            let grants = Grants(places.grants)
            model.rules = { [weak self] in Rules.all(grants, spaces: self?.library.order().filter(\.isSpace).map { ($0.id, $0.title) } ?? []) }
            model.revoke = { [weak self] kept in self?.info.revoke(kept.rule, in: kept.space) }
            model.fullAccess = { [weak self] in self?.fullAccess($0, over: Settings.shown?.window) }
            model.versions = { [weak self] in self?.engine.state.kinds.compactMapValues(\.seen) ?? [:] }
            model.look()
            model.find()
            let made = SettingsWindow(model)
            made.window.center()
            return made
        }
    }

    /// Assistant › Ask Before Every Change…: Settings › Advanced, where the switch and what it means are.
    @MainActor @objc func showPermissions(_ sender: Any?) { settings(.advanced) }

    /// Defaults for New Spaces…, under the agent chip and Build With ▸: Settings › Agents.
    @MainActor @objc func showNewSpaceDefaults(_ sender: Any?) { settings(.agents) }

    /// Look for Agents Again, from the assistant's menu: as Agents' Look Again; a Settings window made later looks itself.
    @MainActor @objc func lookForAgentsAgain(_ sender: Any?) {
        if let model = Settings.shown?.model { return model.again() }
        assistant.lookAgain()
    }
}

extension Library {
    /// Each space's level as its grant says it (None when never answered); grants that do not read leave each unknown.
    func levels() -> [SettingsModel.SpaceLevel] {
        let grants = try? Grants(places.grants).read()
        return order().filter(\.isSpace).map { entry in
            let grant = grants?.spaces[entry.id]
            return .init(id: entry.id, title: entry.title, level: grants.map { _ in grant.map(Rights.level(of:)) ?? .none }, folder: grant?.folder)
        }
    }
}

/// Where an agent's program is: for a builder, the file the engine would launch (Programs.find), or why it is not known
/// to be there; for an agent something only sees, that file or its app in /Applications. Never runs an agent; like the
/// engine's Programs, it may run the login shell once to read its PATH.
enum Found {
    /// A second Programs, apart from the engine's: Engine.programs is internal to the host, which only AB01 changes.
    static let programs = Programs(environment: ProcessInfo.processInfo.environment, registry: .app)

    /// The program's path, or Programs.find's error: not installed, the login shell's PATH unread (so not known), or
    /// what it runs on missing. An app bundle stands only for an agent something only sees, which is never launched.
    static func outcome(_ kind: String) -> Result<String, CodedError> {
        let found = Result { try programs.find(kind).path }.mapError { $0 as? CodedError ?? CodedError("NOT_INSTALLED", $0.localizedDescription) }
        guard case .failure = found, Registry.app.agent(kind)?.builder == nil else { return found }
        let app = "/Applications/\(Registry.app.name(of: kind)).app"
        return FileManager.default.fileExists(atPath: app) ? .success(app) : found
    }
}

/// The window: an NSTabViewController in toolbar style, in the preference toolbar, each tab a page 720 points wide whose
/// height the window takes.
@MainActor final class SettingsWindow {
    let model: SettingsModel
    let tabs = Tabs()
    let window: NSWindow

    /// The tab view controller whose toolbar items are plain, as the mockup draws them: a 14-point symbol and its label,
    /// no box around each; the preference toolbar marks only the selected one.
    final class Tabs: NSTabViewController {
        override func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                              willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
            let item = super.toolbar(toolbar, itemForItemIdentifier: itemIdentifier, willBeInsertedIntoToolbar: flag)
            item?.isBordered = false
            return item
        }
    }

    init(_ model: SettingsModel) {
        self.model = model
        tabs.tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let page = NSHostingController(rootView: SettingsPage(model: model, tab: tab))
            page.sizingOptions = [.preferredContentSize]
            // The tab view controller titles the window with the selected page's title, however the tab was chosen.
            page.title = tab.label
            let item = NSTabViewItem(viewController: page)
            (item.label, item.identifier) = (tab.label, tab.rawValue)
            // powerplug.portrait is SF Symbols 6's: an older system shows the plug lying down.
            item.image = (NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.label) ?? NSImage(systemSymbolName: "powerplug", accessibilityDescription: tab.label))?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
            tabs.addTabViewItem(item)
        }
        window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.title = SettingsTab.general.label
        follow()
    }

    /// Takes the page's size at a new interface size: the tab view takes a page's size only as its tab is chosen, and
    /// the page's own measure follows on SwiftUI's time, so a page made now measures it.
    private func follow() {
        withObservationTracking { _ = Look.scale.size } onChange: { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.refit() }
        }
    }

    private func refit() {
        follow()
        window.setContentSize(NSHostingView(rootView: SettingsPage(model: model, tab: tab)).fittingSize)
    }

    var tab: SettingsTab { SettingsTab.allCases[max(0, tabs.selectedTabViewItemIndex)] }

    func select(_ tab: SettingsTab) {
        tabs.selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: tab) ?? 0
    }
}

// MARK: The pages

/// One tab's page: its sections, each its title, its rows in a card, a line, and more rows or its block. As tall as
/// they are up to `most` points, as the mockup's window; past it, they scroll.
struct SettingsPage: View {
    let model: SettingsModel
    let tab: SettingsTab
    static let most: CGFloat = 680

    var body: some View {
        let factor = Look.scale.size.factor
        ScrollView {
            sections.frame(width: 720 * factor, alignment: .topLeading).fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.heights[tab] = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 720 * factor, height: min(max(model.heights[tab] ?? 0, 1), Self.most * factor))
        .background(Look.Token.bg.ui)
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(model.sections(tab)) { section in
                VStack(alignment: .leading, spacing: 7) {
                    if !section.title.isEmpty {
                        Text(section.title).font(Look.font(.ui, size: 11.5, weight: .semibold).ui).foregroundStyle(Look.Token.ink3.ui)
                            .padding(.horizontal, 2).padding(.top, 2)
                    }
                    if section.block == .storage, let limit = section.rows.first {
                        StorageBlock(storage: model.storage, megabytes: model.preferences.values.storageLimit, limit: limit).card()
                    } else if !section.rows.isEmpty {
                        Rows(rows: section.rows)
                    }
                    if let lead = section.lead {
                        Text(lead).font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui).padding(.horizontal, 2).padding(.top, 4)
                    }
                    if !section.more.isEmpty { Rows(rows: section.more) }
                    if section.block == .found { AgentsFound(model: model) }
                }
            }
        }
        .padding(.top, 16).padding(.horizontal, 28).padding(.bottom, 24)
    }
}

/// Rows in a card, a line between two.
private struct Rows: View {
    let rows: [SettingsRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }
                RowView(row: row)
            }
        }
        .card()
    }
}

/// A row: its title and note, its control on the right or under them.
private struct RowView: View {
    let row: SettingsRow

    var body: some View {
        let words = VStack(alignment: .leading, spacing: 1) {
            if let trail = row.trail {
                // The control inside the sentence, as the mockup's .sf-inl.
                HStack(spacing: 7) { Text(row.title); RowControl(row: row); Text(trail) }.font(Look.body.font.ui).foregroundStyle(Look.Token.ink.ui)
            } else {
                Text(row.title).font(row.code ? Look.font(.code, size: 12.5).ui : Look.body.font.ui).foregroundStyle(Look.Token.ink.ui)
            }
            if !row.note.isEmpty {
                Text(LocalizedStringKey(row.note)).font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui).fixedSize(horizontal: false, vertical: true)
            }
            if !row.keys.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(row.keys.enumerated()), id: \.offset) { index, pair in
                        Keycap(words: pair.key, boxed: true)
                        Text(pair.words + (index < row.keys.count - 1 ? " ·" : ""))
                    }
                }
                .font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui).padding(.top, 5)
            }
        }
        Group {
            if row.wrap {
                VStack(alignment: .leading, spacing: 8) { words; RowControl(row: row) }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 16) {
                    if let mark = row.mark { Monogram(name: mark, side: 22).padding(.trailing, -6) }
                    words.frame(maxWidth: .infinity, alignment: .leading)
                    if row.trail == nil { RowControl(row: row) }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9 * Look.density).frame(minHeight: Look.row + 17)
    }
}

/// A row's control: a choice in the mockup's popup button, its tiles, pictures or segments; a switch; a button; words.
struct RowControl: View {
    let row: SettingsRow

    var body: some View {
        switch row.control {
        case .choice(let options, let get, let set):
            switch row.style {
            case .tiles: Tiles(title: row.title, options: options, chosen: get().first ?? "", set: set)
            case .thumbs: Appearances(options: options, chosen: get().first ?? "", set: set)
            case .segments: Segments(title: row.title, options: options, chosen: get().first ?? "", set: set)
            case .menu:
                let chosen = get()
                PopMenu(title: row.title, shown: options.filter { !$0.heading && chosen.contains($0.value) }.map(\.label).joined(separator: " · "),
                        minWidth: row.trail == nil ? 96 : 0) {
                    // The menu itself is the system's, a heading as a section, each chosen item checked.
                    ForEach(Array(Self.sections(options).enumerated()), id: \.offset) { _, section in
                        Section(section.heading) {
                            ForEach(section.items, id: \.self) { option in
                                Toggle(option.label, isOn: Binding(get: { get().contains(option.value) }, set: { _ in set(option.value) }))
                            }
                        }
                    }
                }
            }
        case .toggle(let get, let set):
            Toggle(row.title, isOn: Binding(get: get, set: set)).toggleStyle(SwitchStyle()).labelsHidden()
        case .button(let title, let symbol, let run):
            Button(action: run) {
                if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
            }
            .buttonStyle(Secondary()).font(Look.font(.ui, size: 12.5, weight: .medium).ui)
        case .said(let words):
            Text(words).font(Look.small.font.ui).foregroundStyle(Look.Token.ink2.ui).accessibilityLabel("\(row.title): \(words)")
        }
    }

    /// The options in the menu's sections: those before the first heading, then each heading's.
    static func sections(_ options: [SettingsRow.Option]) -> [(heading: String, items: [SettingsRow.Option])] {
        options.reduce(into: []) { sections, option in
            if option.heading || sections.isEmpty { sections.append((option.heading ? option.label : "", [])) }
            if !option.heading { sections[sections.count - 1].items.append(option) }
        }
    }
}

/// Options side by side, as the mockup's .xc-seg: a sunk track, the chosen one a raised pill of the page's colour, no
/// dividers; read by VoiceOver as one adjustable control that says the choice. As wide as its words, or as its column
/// (`wide`).
struct Segments: View {
    let title: String, options: [SettingsRow.Option], chosen: String, set: (String) -> Void
    var wide = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let on = option.value == chosen
                Button { set(option.value) } label: {
                    Text(option.label).font(Look.font(.ui, size: 12, weight: on ? .semibold : .medium).ui)
                        .foregroundStyle((on ? Look.Token.ink : .ink2).ui)
                        .padding(.horizontal, wide ? 4 : 10).frame(minWidth: wide ? 0 : 58, maxWidth: wide ? .infinity : nil).frame(height: 24)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 6).fill(Look.Token.bg.ui).shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Look.Token.line2.ui) }
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .boxed(RoundedRectangle(cornerRadius: 8), Look.Token.sunk.ui, ring: Look.Token.line.ui)
        .fixedSize(horizontal: !wide, vertical: true)
        // One control to VoiceOver, the choice in its label: offscreen and on, the words read are the same.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(options.first { $0.value == chosen }?.label ?? "")")
        .accessibilityHint(Words.list(options.map(\.label), "or"))
        .accessibilityAdjustableAction { direction in
            let at = options.firstIndex { $0.value == chosen } ?? 0
            let next = direction == .increment ? min(at + 1, options.count - 1) : direction == .decrement ? max(at - 1, 0) : at
            set(options[next].value)
        }
    }
}

/// A choice in tiles, each "Aa" a size larger than the one before over two lines of text; the chosen one ringed in
/// ink, its label in semibold.
private struct Tiles: View {
    let title: String, options: [SettingsRow.Option], chosen: String, set: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let on = chosen == option.value
                Button { set(option.value) } label: {
                    VStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Aa").font(Look.font(.ui, size: 14 + 3 * CGFloat(index), weight: .semibold).ui).foregroundStyle(Look.Token.ink.ui)
                            ForEach([0.5, 0.35], id: \.self) { Capsule().fill(Look.Token.line2.ui).frame(width: 64 * $0, height: 2.5) }
                        }
                        .padding(.horizontal, 10).frame(width: 84, height: 54, alignment: .leading)
                        .boxed(RoundedRectangle(cornerRadius: Look.control, style: .continuous), Look.Token.bg2.ui, ring: (on ? Look.Token.ink : .line2).ui, width: on ? 2 : 1)
                        Text(option.label).font(Look.font(.ui, size: 11.5, weight: on ? .semibold : .regular).ui).foregroundStyle((on ? Look.Token.ink : .ink2).ui)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title): \(option.label)").accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// Auto, Light and Dark, each a small picture of the window in it; the chosen one ringed in ink.
private struct Appearances: View {
    let options: [SettingsRow.Option], chosen: String, set: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(options, id: \.self) { option in
                let on = chosen == option.value
                Button { set(option.value) } label: {
                    VStack(spacing: 6) {
                        Thumb(choice: Preferences.Appearance(rawValue: option.value) ?? .system).frame(width: 76, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: Look.control, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Look.control, style: .continuous)
                                .strokeBorder((on ? Look.Token.ink : .line2).ui, lineWidth: on ? 2 : 1).padding(on ? -2 : -1))
                        Text(option.label).font(Look.font(.ui, size: 11.5, weight: on ? .semibold : .regular).ui).foregroundStyle((on ? Look.Token.ink : .ink2).ui)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label).accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A window in day or night: its sidebar and a card; Auto shows the night across its right half.
private struct Thumb: View {
    let choice: Preferences.Appearance

    var body: some View {
        ZStack {
            window(dark: choice == .dark)
            if choice == .system {
                window(dark: true).clipShape(Slant())
            }
        }
    }

    private func window(dark: Bool) -> some View {
        func tone(_ token: Look.Token) -> Color {
            let tone = token.tone
            return Color(nsColor: dark ? Look.srgb(tone.night, tone.nightAlpha) : Look.srgb(tone.day, tone.dayAlpha))
        }
        let edge = dark ? Look.srgb(0xF1F1EE, 0.08) : Look.srgb(0x121316, 0.08)
        return ZStack(alignment: .topLeading) {
            tone(.bg)
            tone(.side).frame(width: 22).overlay(alignment: .trailing) { Color(nsColor: edge).frame(width: 1) }
            RoundedRectangle(cornerRadius: 4).fill(tone(.bg2)).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(nsColor: edge)))
                .frame(width: 36, height: 24).offset(x: 30, y: 9)
        }
    }

    /// The right part of the picture, cut on a slant from 60 % at the top to 40 % at the bottom.
    private struct Slant: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.6, y: rect.minY))
                path.addLines([CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY),
                               CGPoint(x: rect.minX + rect.width * 0.4, y: rect.maxY)])
                path.closeSubpath()
            }
        }
    }
}

/// On this Mac: the agents found, three to a line, each its tile, its name and its version, read only; then how many
/// were found and when, and Look Again.
private struct AgentsFound: View {
    let model: SettingsModel

    var body: some View {
        let agents = model.agents
        if !agents.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(stride(from: 0, to: agents.count, by: 3)), id: \.self) { start in
                    HStack(spacing: 12) {
                        ForEach(start..<start + 3, id: \.self) { index in
                            HStack(spacing: 9) {
                                if index < agents.count {
                                    Monogram(name: agents[index].name, side: 22)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(agents[index].name).font(Look.font(.ui, size: 12.5, weight: .semibold).ui).foregroundStyle(Look.Token.ink.ui)
                                        Text(agents[index].line).font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .padding(14).card()
        }
        HStack(spacing: 10) {
            Text(model.lookedLine).font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui).frame(maxWidth: .infinity, alignment: .leading)
            Button { model.again() } label: { Label("Look Again", systemImage: "arrow.clockwise") }
                .buttonStyle(Secondary()).font(Look.font(.ui, size: 12.5, weight: .medium).ui).disabled(model.found == nil)
        }
        .padding(.horizontal, 4)
    }
}

private extension View {
    /// A group of rows: bg2 inside a ring of line, at the card radius.
    func card() -> some View {
        let shape = RoundedRectangle(cornerRadius: Look.card, style: .continuous)
        return background(shape.fill(Look.Token.bg2.ui)).overlay(shape.strokeBorder(Look.Token.line.ui)).clipShape(shape)
    }
}

/// The mockup's switch: 30 by 18, ink when on, mist when off, its knob bg2.
struct SwitchTrack: View {
    let on: Bool

    var body: some View {
        Capsule().fill((on ? Look.Token.ink : .mist).ui).frame(width: 30, height: 18)
            .overlay(alignment: on ? .trailing : .leading) { Circle().fill(Look.Token.bg2.ui).frame(width: 14, height: 14).padding(2) }
    }
}

/// A toggle drawn as the mockup's switch.
struct SwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: { SwitchTrack(on: configuration.isOn) }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}
