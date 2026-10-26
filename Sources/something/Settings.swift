// Settings (⌘,): a window of its own whose toolbar holds the tabs, as the Mac's own settings do, sized to each tab.
// General, Assistant, Permissions, Interface, Shortcuts, Versions & Storage and Agents are here; each settings tab is a
// list of rows given as data (a title, a note, and a choice, a switch, a button or a lock), so that a test can work
// every control and see which key it wrote. The Shortcuts tab reads Keys, the one list of the commands; Versions &
// Storage weighs the store off the main queue (Storage.swift); Agents reads the registry and where each program is,
// found by a look at files that never runs one. Appearance and Motion apply at once, to every window.
import AppKit
import SomethingAgents
import SomethingCore
import SwiftUI

/// The tabs, in the toolbar's order.
enum SettingsTab: String, CaseIterable {
    case general, assistant, permissions, interface, shortcuts, storage, agents

    var label: String { face.label }
    var symbol: String { face.symbol }

    private var face: (label: String, symbol: String) {
        switch self {
        case .general: ("General", "gearshape")
        case .assistant: ("Assistant", "sparkle")
        case .permissions: ("Permissions", "checkmark.shield")
        case .interface: ("Interface", "eye")
        case .shortcuts: ("Shortcuts", "keyboard")
        case .storage: ("Versions & Storage", "square.3.layers.3d")
        case .agents: ("Agents", "powerplug")
        }
    }
}

/// One row of a settings tab: what it is, a line that says what it does, and its control.
struct SettingsRow: Identifiable {
    /// One item of a choice's menu; a heading is an item that cannot be chosen.
    struct Option: Hashable { let value: String, label: String; var heading = false }

    enum Control {
        case choice([Option], get: () -> String, set: (String) -> Void)
        case toggle(get: () -> Bool, set: (Bool) -> Void, enabled: Bool)
        /// A button, its symbol before its title, greyed when not `enabled`.
        case button(String, symbol: String? = nil, enabled: Bool = true, () -> Void)
        /// A rule nobody can change, said with a lock and a word.
        case locked(String)
    }

    let title: String, note: String, control: Control
    /// The words after the control when it stands inside the title's sentence: "Keep at most [3] assistants awake".
    var trail: String?
    /// The note is a path, in code.
    var code = false
    var id: String { title }
}

/// A titled group of rows; the Interface tab's first one also holds the three appearances, and Storage the store's
/// weight, its first row (the limit's choice) drawn in that block's header.
struct SettingsSection: Identifiable {
    let title: String, rows: [SettingsRow]
    var appearance = false, storage = false
    /// A line under the group that says what was just done.
    var foot: String?
    var id: String { title }
}

/// What Settings shows and changes: the preferences, and the few things a row does beyond writing its key.
@MainActor @Observable final class SettingsModel {
    let preferences: Preferences
    @ObservationIgnored let places: Places
    /// The something.app that runs, and its version: under a Homebrew Cellar, it says so and can add its launcher.
    @ObservationIgnored let app: URL
    @ObservationIgnored let version: String
    /// The spaces "When something opens" offers, by name and title.
    @ObservationIgnored var spaces: () -> [(id: String, title: String)] = { [] }
    /// Applies the appearance and the motion to the whole app; tests record it instead.
    @ObservationIgnored var apply: (Preferences.Appearance, Look.Motion) -> Void = Settings.apply
    /// Plays the welcome tour again (App.showTour).
    @ObservationIgnored var tour: () -> Void = {}
    /// Opens System Settings › Keyboard; tests record it instead.
    @ObservationIgnored var keyboard: () -> Void = {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    /// Says what went wrong, in a sentence.
    @ObservationIgnored var told: (String) -> Void = { _ in }
    /// Whether something's launcher stands in ~/Applications: the disk says it, read again as the window shows.
    var launcher = false
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
    /// What the store weighs (Storage.swift); nil until it was first measured.
    var storage: Storage?
    /// What the last Clear Old Versions freed, said under Storage; nil until one ran.
    var cleared: String?
    /// Weighs the store at a date, off the main queue; tests give invented weights.
    @ObservationIgnored var weigh: @Sendable (Places, Date) -> Storage = Storage.weigh
    /// Asks before Clear Old Versions, then runs the closure only on the alert's Clear Versions; tests record it.
    @ObservationIgnored var confirm: (Versions.Old, @escaping () -> Void) -> Void = Storage.confirm
    /// Show in Finder; tests record it.
    @ObservationIgnored var reveal: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }

    init(preferences: Preferences, places: Places, app: URL = Bundle.main.bundleURL, version: String = Resources.version) {
        (self.preferences, self.places, self.app, self.version) = (preferences, places, app, version)
        look()
    }

    /// Reads again what lives on the disk rather than in the preferences.
    func look() {
        launcher = Launcher.made(places: places)
        seen = versions()
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

    /// Where the program of `kind` was found; nil while a look runs and when it was not found.
    func path(_ kind: String) -> String? { try? found?[kind]?.get() }

    /// The version line under General: Homebrew is named only when something runs from its Cellar.
    var versionLine: (name: String, rest: String) {
        let rest = (Launcher.prefix(of: app) == nil ? [] : ["installed with Homebrew"]) + ["nothing leaves this Mac"]
        return ("something \(version)", rest.map { " · " + $0 }.joined())
    }

    /// The rows of `tab`; Shortcuts has none, it draws Keys.
    func sections(_ tab: SettingsTab) -> [SettingsSection] {
        let preferences = preferences
        func toggle(_ key: WritableKeyPath<Preferences.Values, Bool>) -> SettingsRow.Control {
            .toggle(get: { preferences.values[keyPath: key] }, set: { value in preferences.change { $0[keyPath: key] = value } }, enabled: true)
        }
        func choice<T: RawRepresentable>(_ key: WritableKeyPath<Preferences.Values, T>, _ options: [(T, String)], then: @escaping () -> Void = {})
            -> SettingsRow.Control where T.RawValue == String {
            .choice(options.map { SettingsRow.Option(value: $0.0.rawValue, label: $0.1) }, get: { preferences.values[keyPath: key].rawValue }, set: { raw in
                guard let value = T(rawValue: raw) else { return }
                preferences.change { $0[keyPath: key] = value }
                then()
            })
        }
        switch tab {
        case .general:
            return [SettingsSection(title: "Start", rows: [
                SettingsRow(title: "When something opens", note: "The page you see first.", control: opening()),
                SettingsRow(title: "Add something to Applications", note: "A link in ~/Applications, so Spotlight and Launchpad find it.",
                            control: .toggle(get: { [weak self] in self?.launcher ?? false }, set: { [weak self] in self?.addToApplications($0) },
                                             enabled: launcher || Launcher.prefix(of: app) != nil)),
                SettingsRow(title: "Welcome tour", note: "The short film and the first steps, as on the first day.",
                            control: .button("Show Again") { [weak self] in self?.tour() }),
            ])]
        case .assistant:
            return assistantSections()
        case .permissions:
            return [
                SettingsSection(title: "Your assistant", rows: [
                    SettingsRow(title: "Ask Before Every Change", note: "Your assistant asks you before each change to a space too.",
                                control: .toggle(get: { preferences.askEverything }, set: { [weak self] value in
                                    preferences.askEverything = value
                                    self?.asking(value)
                                }, enabled: true)),
                ]),
                SettingsSection(title: "Requests from agents", rows: [
                    SettingsRow(title: "Requests always wait for your click",
                                note: "Allow Once or Deny, in a panel of the Mac that a space cannot draw. There is no Always Allow.", control: .locked("Always")),
                    SettingsRow(title: "Notify me when a request waits", note: "A banner of the Mac when something is in the background. Off unless you turn it on.",
                                control: toggle(\.notify)),
                ]),
            ]
        case .interface:
            let applied = { [weak self] in self.map { $0.apply($0.preferences.appearance, $0.preferences.motion) } ?? () }
            return [
                SettingsSection(title: "Appearance", rows: [
                    SettingsRow(title: "Motion", note: "Calm follows the identity. Reduced keeps only fades.",
                                control: choice(\.motion, [(.calm, "Calm"), (.reduced, "Reduced")], then: applied)),
                ], appearance: true),
                SettingsSection(title: "The assistant", rows: [
                    SettingsRow(title: "When a space opens, its assistant is", note: "Reduced keeps the space clear: a small sign in a corner.",
                                control: choice(\.assistantAtOpening, [(.reduced, "Reduced"), (.open, "Open")])),
                    SettingsRow(title: "Remember where I put the assistant", note: "One place for every space.", control: toggle(\.rememberSticker)),
                ]),
                SettingsSection(title: "Sidebar and show", rows: [
                    SettingsRow(title: "Show each assistant’s eyes in the sidebar", note: "Its state at a glance: working, waiting for you, asleep.",
                                control: toggle(\.sidebarEyes)),
                    SettingsRow(title: "Hold ⌥ to point inside a drawn frame",
                                note: "Showing a part of a space stays a visible mode; ⌥ only works once a frame is drawn.", control: toggle(\.holdOption)),
                ]),
            ]
        case .storage:
            return storageSections()
        case .shortcuts, .agents:
            return []
        }
    }

    /// Assistant: what a new space's conversation starts with, whether conversations resume, and when assistants rest.
    private func assistantSections() -> [SettingsSection] {
        let preferences = preferences, registry = Registry.app
        let first = offered().first ?? registry.builders.first?.kind ?? "", kind = preferences.assistant ?? first
        let kinds = offered() + (offered().contains(kind) || kind.isEmpty ? [] : [kind])
        // The model and effort that kind last listed; before any, the agent's own, which "" stands for.
        func listed(_ key: KeyPath<Options, [Option]?>, _ own: String, _ value: WritableKeyPath<Preferences.Values, String?>) -> SettingsRow.Control {
            let options = [SettingsRow.Option(value: "", label: own)]
                + (preferences.listed[kind]?[keyPath: key] ?? []).map { SettingsRow.Option(value: $0.value, label: $0.label) }
            return .choice(options, get: { preferences.values[keyPath: value] ?? "" }, set: { chosen in
                preferences.change { $0[keyPath: value] = chosen.isEmpty ? nil : chosen }
            })
        }
        let resuming = registry.builders.filter { Registry.resumesAsBuilt.contains($0.kind) }.map(\.name)
        let fresh = registry.builders.filter { !Registry.resumesAsBuilt.contains($0.kind) }.map(\.name)
        let minutes = [(5, "5 minutes"), (10, "10 minutes"), (30, "30 minutes"), (60, "1 hour"), (0, "Never")]
        return [
            SettingsSection(title: "Defaults for new spaces", rows: [
                SettingsRow(title: "Agent", note: "Each space can change its own, from its assistant.",
                            control: .choice(kinds.map { SettingsRow.Option(value: $0, label: registry.name(of: $0)) }, get: { preferences.assistant ?? first }, set: { [weak self] chosen in
                                // Another agent's model and effort mean nothing to this one (AssistantModel.keepDefault).
                                preferences.change { if $0.assistant != chosen { ($0.assistant, $0.model, $0.effort) = (chosen, nil, nil) } }
                                self?.chose(chosen)
                            })),
                SettingsRow(title: "Model", note: "", control: listed(\.model, registry.limits[kind]?.contains("model") == true ? "Its own model" : "Default model", \.model)),
                SettingsRow(title: "Effort", note: "Higher is slower and uses your limits faster.", control: listed(\.effort, "Default effort", \.effort)),
            ]),
            SettingsSection(title: "Conversations", rows: [
                SettingsRow(title: "Resume each space’s conversation",
                            note: "\(Words.list(resuming, "and")) can. \(Words.list(fresh, "and")) start fresh, and say so.",
                            control: .toggle(get: { preferences.resume }, set: { value in preferences.resume = value }, enabled: true)),
            ]),
            SettingsSection(title: "Rest", rows: [
                SettingsRow(title: "Put idle assistants to sleep after", note: "The open space’s assistant and working ones stay awake.",
                            control: number(\.sleepAfter, minutes)),
                SettingsRow(title: "Keep at most", note: "When one more wakes, the one idle the longest goes to sleep. A sleeping assistant wakes on your next message.",
                            control: number(\.awakeAtMost, (1...5).map { ($0, String($0)) }), trail: "assistants awake"),
            ]),
        ]
    }

    /// A choice among numbers, written to `key`.
    func number(_ key: WritableKeyPath<Preferences.Values, Int>, _ options: [(Int, String)]) -> SettingsRow.Control {
        let preferences = preferences
        return .choice(options.map { SettingsRow.Option(value: String($0.0), label: $0.1) }, get: { String(preferences.values[keyPath: key]) }, set: { raw in
            if let value = Int(raw) { preferences.change { $0[keyPath: key] = value } }
        })
    }

    /// One agent of the Agents tab: where it was found and the version its files name, or why something only sees it.
    struct AgentLine: Identifiable, Equatable {
        let id: String, name: String, builds: Bool, isDefault: Bool
        let path: String?, version: String?, note: String
    }

    /// The agents of the registry, the builders first, each found or not; the default is the one new spaces build with.
    var agents: [AgentLine] {
        let preferred = preferences.assistant ?? offered().first, all = Registry.app.agents
        return (all.filter { $0.builder != nil } + all.filter { $0.builder == nil }).map { agent in
            let path = path(agent.kind), builds = agent.builder != nil
            let note: String
            if !builds { note = agent.unavailable ?? "something only sees \(agent.name)." }
            else if case .failure(let error) = found?[agent.kind] { note = Found.note(error, install: agent.install ?? agent.kind) }
            else { note = Registry.resumesAsBuilt.contains(agent.kind) ? "Resumes each space’s conversation" : "Starts each conversation fresh, and says so" }
            return AgentLine(id: agent.kind, name: agent.name, builds: builds, isDefault: builds && agent.kind == preferred && path != nil,
                             path: path.map { ($0 as NSString).abbreviatingWithTildeInPath },
                             version: path == nil ? nil : seen[agent.kind] ?? "version unknown", note: note)
        }
    }

    /// The footer of Agents: when something last looked, and how many agents it found.
    var lookedLine: String {
        guard let found, let looked else { return "Looking for agents on this Mac…" }
        let count = found.values.filter { (try? $0.get()) != nil }.count, agents = "\(count) agent\(count == 1 ? "" : "s")"
        let day = Info.day(looked, now: clock())
        let when = ["Today", "Yesterday"].contains(day) ? day.lowercased() : "on " + day
        return "Looked \(when) at \(Presence.clock.string(from: looked)) · \(agents)"
    }

    /// "When something opens": the last space, New Space, or one space. A space no longer there reads as the last.
    private func opening() -> SettingsRow.Control {
        let spaces = spaces(), preferences = preferences
        let options = [SettingsRow.Option(value: "last", label: "The last space you had open"), SettingsRow.Option(value: "new", label: "New Space"),
                       SettingsRow.Option(value: "", label: "A space", heading: true)] + spaces.map { SettingsRow.Option(value: $0.id, label: $0.title) }
        return .choice(options, get: {
            let chosen = preferences.openAtStart
            return chosen == "new" || spaces.contains { $0.id == chosen } ? chosen : "last"
        }, set: { value in preferences.openAtStart = value })
    }

    /// The Appearance choice: applied to every window at once.
    func choose(_ appearance: Preferences.Appearance) {
        preferences.appearance = appearance
        apply(appearance, preferences.motion)
    }

    /// Makes or removes the launcher; only the one something made is ever removed.
    private func addToApplications(_ on: Bool) {
        // The disk is the truth (Launcher.made): no key is written, so none can contradict it.
        do {
            if on, let prefix = Launcher.prefix(of: app) {
                try Launcher.make(prefix: prefix, places: places, icon: Bundle.main.url(forResource: "something", withExtension: "icns"))
            } else if !on {
                try Launcher.remove(places: places)
            }
        } catch { told(error.sentence) }
        look()
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

    /// Applies the person's appearance and motion to the whole app: at the start, and as Interface changes them.
    static func apply(_ appearance: Preferences.Appearance, _ motion: Look.Motion) {
        NSApp.appearance = Look.appearance(appearance)
        Look.chosen = motion
    }
}

extension App {
    /// Settings… (⌘,): the window, made the first time, at `tab` when given, else where it was left.
    @MainActor @objc func showSettings(_ sender: Any?) { settings(nil) }

    @MainActor func settings(_ tab: SettingsTab?) {
        Settings.open(tab) {
            let model = SettingsModel(preferences: library.preferences, places: places)
            model.spaces = { [weak self] in self?.library.order().filter(\.isSpace).map { ($0.id, $0.title) } ?? [] }
            model.tour = { [weak self] in self?.showTour(nil) }
            model.told = { [weak self] in self?.ask.tell($0) }
            model.offered = { [weak self] in self.map { app in app.assistant.builders.filter { app.assistant.installed[$0] == true } } ?? [] }
            model.chose = { [weak self] in _ = self?.assistant.buildNew(with: $0) }
            model.asking = { [weak self] on in if let assistant = self?.assistant, assistant.askEverything != on { assistant.toggleAsking() } }
            model.lookAgain = { [weak self] in self?.assistant.lookAgain() }
            model.versions = { [weak self] in self?.engine.state.kinds.compactMapValues(\.seen) ?? [:] }
            model.find()
            let made = SettingsWindow(model)
            made.window.center()
            return made
        }
    }

    /// Assistant › Ask Before Every Change…: Settings › Permissions, where the switch and what it means are.
    @MainActor @objc func showPermissions(_ sender: Any?) { settings(.permissions) }

    /// Defaults for New Spaces…, under the agent chip and Build With ▸: Settings › Assistant.
    @MainActor @objc func showNewSpaceDefaults(_ sender: Any?) { settings(.assistant) }

    /// Look for Agents Again, from the assistant's menu: as Agents' Look Again; a Settings window made later looks itself.
    @MainActor @objc func lookForAgentsAgain(_ sender: Any?) {
        if let model = Settings.shown?.model { return model.again() }
        assistant.lookAgain()
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

    /// What a builder's row says when it was not found: the short sentence for a plain absence, else Programs' own,
    /// which says what is not known or what is missing.
    static func note(_ error: CodedError, install: String) -> String {
        error.code == "NOT_INSTALLED" && error.message.contains("was not found on this Mac")
            ? "Not found on this Mac. To install it, type in Terminal: \(install)" : error.message
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
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.label)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
            tabs.addTabViewItem(item)
        }
        window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.title = SettingsTab.general.label
    }

    var tab: SettingsTab { SettingsTab.allCases[max(0, tabs.selectedTabViewItemIndex)] }

    func select(_ tab: SettingsTab) {
        tabs.selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: tab) ?? 0
    }
}

// MARK: The pages

/// One tab's page: its sections of rows, or the shortcuts.
struct SettingsPage: View {
    let model: SettingsModel
    let tab: SettingsTab

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if tab == .shortcuts {
                ShortcutColumns().padding(.vertical, 14).padding(.horizontal, 16).card()
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").font(.system(size: 11))
                    Text("To change a menu’s key, use System Settings › Keyboard › App Shortcuts.").frame(maxWidth: .infinity, alignment: .leading)
                    Button("Open Keyboard Settings…", action: model.keyboard).buttonStyle(Secondary()).font(Look.font(.ui, size: 12.5, weight: .medium).ui)
                }
                .font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui).padding(.horizontal, 4)
            }
            if tab == .permissions {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.shield").font(.system(size: 14)).foregroundStyle(Look.Token.ink2.ui).padding(.top, 2)
                    Text(Promise.sentence).font(Look.font(.ui, size: 13.5, weight: .medium).ui).lineSpacing(3).foregroundStyle(Look.Token.ink.ui)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 14).padding(.horizontal, 16)
                .background(Look.Token.sunk.ui, in: RoundedRectangle(cornerRadius: Look.card, style: .continuous))
            }
            if tab == .agents { AgentsList(model: model) }
            ForEach(model.sections(tab)) { section in
                VStack(alignment: .leading, spacing: 7) {
                    Text(section.title).font(Look.font(.ui, size: 11.5, weight: .semibold).ui).foregroundStyle(Look.Token.ink3.ui)
                        .padding(.horizontal, 2).padding(.top, 2)
                    VStack(spacing: 0) {
                        if section.appearance { Appearances(model: model) }
                        if section.storage, let limit = section.rows.first { StorageBlock(storage: model.storage, megabytes: model.preferences.values.storageLimit, limit: limit) }
                        ForEach(Array(section.rows.dropFirst(section.storage ? 1 : 0).enumerated()), id: \.element.id) { index, row in
                            if index > 0 || section.appearance || section.storage { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }
                            RowView(row: row)
                        }
                    }
                    .card()
                    if let foot = section.foot {
                        Label(foot, systemImage: "checkmark").font(Look.small.font.ui).foregroundStyle(Look.Token.ok.ui).padding(.horizontal, 4)
                    }
                }
            }
            if tab == .general {
                HStack(spacing: 10) {
                    PageSign(state: .listen, side: 22, lands: false, motion: model.preferences.motion).frame(width: 22, height: 22)
                    (Text(model.versionLine.name).font(Look.font(.ui, size: 11.5, weight: .semibold).ui).foregroundColor(Look.Token.ink2.ui)
                        + Text(model.versionLine.rest))
                        .font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui)
                }
                .padding(.horizontal, 4).padding(.vertical, 2)
            }
        }
        .padding(.top, 16).padding(.horizontal, 28).padding(.bottom, 24)
        .frame(width: 720, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Look.Token.bg.ui)
    }
}

/// A row: its title and note on the left, its control on the right.
private struct RowView: View {
    let row: SettingsRow

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                if let trail = row.trail {
                    // The control inside the sentence, as the mockup's .cm-inl.
                    HStack(spacing: 7) { Text(row.title); RowControl(row: row); Text(trail) }.font(Look.body.font.ui).foregroundStyle(Look.Token.ink.ui)
                } else {
                    Text(row.title).font(Look.body.font.ui).foregroundStyle(Look.Token.ink.ui)
                }
                if row.code {
                    Text(row.note).font(Look.font(.code, size: 11.5).ui).foregroundStyle(Look.Token.ink2.ui)
                } else if !row.note.isEmpty {
                    Text(row.note).font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if row.trail == nil { RowControl(row: row) }
        }
        .padding(.horizontal, 14).padding(.vertical, 9 * Look.density).frame(minHeight: Look.row + 17)
        .accessibilityElement(children: .contain)
    }
}

/// A row's control: a choice in the mockup's popup button, a switch, a button or a lock.
struct RowControl: View {
    let row: SettingsRow

    var body: some View {
        switch row.control {
        case .choice(let options, let get, let set):
            // The menu itself is the system's, a heading as a section.
            let shown = options.first { !$0.heading && $0.value == get() }?.label ?? ""
            PopMenu(title: row.title, shown: shown, minWidth: row.trail == nil ? 96 : 0) {
                let cut = options.firstIndex(where: \.heading) ?? options.count
                Picker(row.title, selection: Binding(get: get, set: set)) {
                    ForEach(options[..<cut], id: \.self) { Text($0.label).tag($0.value) }
                    if cut < options.count {
                        Section(options[cut].label) { ForEach(options[(cut + 1)...], id: \.self) { Text($0.label).tag($0.value) } }
                    }
                }
            }
        case .toggle(let get, let set, let enabled):
            Toggle(row.title, isOn: Binding(get: get, set: set)).toggleStyle(SwitchStyle()).labelsHidden().disabled(!enabled)
                .opacity(enabled ? 1 : 0.45)
        case .button(let title, let symbol, let enabled, let run):
            Button(action: run) {
                if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
            }
            .buttonStyle(Secondary()).font(Look.font(.ui, size: 12.5, weight: .medium).ui).disabled(!enabled).opacity(enabled ? 1 : 0.45)
        case .locked(let word):
            Label(word, systemImage: "lock").labelStyle(Locked()).accessibilityLabel("\(row.title): \(word), cannot be changed")
        }
    }
}

/// Auto, Light and Dark, each a small picture of the window in it; the chosen one ringed in ink.
private struct Appearances: View {
    let model: SettingsModel

    var body: some View {
        HStack(spacing: 18) {
            ForEach([(Preferences.Appearance.system, "Auto"), (.light, "Light"), (.dark, "Dark")], id: \.0) { choice, label in
                let on = model.preferences.appearance == choice
                Button { model.choose(choice) } label: {
                    VStack(spacing: 6) {
                        Thumb(choice: choice).frame(width: 76, height: 50).clipShape(RoundedRectangle(cornerRadius: Look.control, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Look.control, style: .continuous)
                                .strokeBorder((on ? Look.Token.ink : .line2).ui, lineWidth: on ? 2 : 1).padding(on ? -2 : -1))
                        Text(label).font(Look.font(.ui, size: 11.5, weight: on ? .semibold : .regular).ui).foregroundStyle((on ? Look.Token.ink : .ink2).ui)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label).accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// A lock and its word, small, in ink3.
private struct Locked: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon.font(.system(size: 10)); configuration.title }
            .font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui)
    }
}

/// Agents: what something never does to them, the builders and the agents it only sees, and Look Again.
private struct AgentsList: View {
    let model: SettingsModel

    var body: some View {
        let agents = model.agents
        Text("The coding agents found on this Mac. something never installs them, signs them in or changes their settings.")
            .font(Look.medium.font.ui).foregroundStyle(Look.Token.ink2.ui).padding(.horizontal, 4)
        ForEach([true, false], id: \.self) { builds in
            let shown = agents.filter { $0.builds == builds }
            VStack(alignment: .leading, spacing: 7) {
                Text(builds ? "Can build spaces · \(shown.filter { $0.path != nil }.count)" : "Seen only · \(shown.count)")
                    .font(Look.font(.ui, size: 11.5, weight: .semibold).ui).foregroundStyle(Look.Token.ink3.ui).padding(.horizontal, 2).padding(.top, 2)
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, agent in
                        if index > 0 { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }
                        AgentRow(agent: agent, motion: model.preferences.motion)
                    }
                }
                .card()
            }
        }
        HStack(spacing: 10) {
            Text(model.lookedLine).font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui).frame(maxWidth: .infinity, alignment: .leading)
            Button { model.again() } label: { Label("Look Again", systemImage: "arrow.clockwise") }
                .buttonStyle(Secondary()).font(Look.font(.ui, size: 12.5, weight: .medium).ui).disabled(model.found == nil)
        }
        .padding(.horizontal, 4)
    }
}

/// One agent: its sign, its name, Default, where it is and its version, then what it does or why it is only seen.
private struct AgentRow: View {
    let agent: SettingsModel.AgentLine
    let motion: Look.Motion

    var body: some View {
        HStack(spacing: 12) {
            PageSign(state: agent.builds ? .listen : .sleep, side: 22, lands: false, motion: motion).frame(width: 26, height: 26)
                .opacity(agent.builds && agent.path != nil ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(agent.name).font(Look.font(.ui, size: 13, weight: .semibold).ui).foregroundStyle(Look.Token.ink.ui)
                    if agent.isDefault {
                        Text("Default").font(Look.font(.ui, size: 10, weight: .semibold).ui).foregroundStyle(Look.Token.ink2.ui).padding(.horizontal, 6)
                            .padding(.vertical, 1).overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Look.Token.line2.ui))
                    }
                    if let path = agent.path { Text(path).font(Look.font(.code, size: 11).ui).foregroundStyle(Look.Token.ink3.ui).lineLimit(1) }
                    if let version = agent.version { Text(version).font(Look.font(.ui, size: 11).ui).foregroundStyle(Look.Token.ink3.ui) }
                }
                Text(agent.note).font(Look.small.font.ui).foregroundStyle((agent.builds ? Look.Token.ink3 : .ink2).ui)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !agent.builds {
                Label("Seen only", systemImage: "eye").labelStyle(Badge())
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 50)
        .accessibilityElement(children: .combine)
    }

    /// The mockup's .cm-badge: hover's fill, 22 high, ink2.
    private struct Badge: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 5) { configuration.icon.font(.system(size: 10)); configuration.title }
                .font(Look.font(.ui, size: 11.5, weight: .medium).ui).foregroundStyle(Look.Token.ink2.ui)
                .padding(.horizontal, 8).frame(height: 22).background(Look.Token.hover.ui, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: The shortcuts

/// The shortcut list in two columns, Spaces and Show on the left, Assistant and Window on the right, read from Keys.
struct ShortcutColumns: View {
    /// What a key reads as: a keycap, or a word between them ("hold", "to").
    enum Cap: Equatable { case key(String), word(String) }

    static let columns: [[Keys.Command.Area]] = [[.spaces, .show], [.assistant, .window]]

    /// The commands the sheet lists in `area`, in Keys' order.
    static func lines(_ area: Keys.Command.Area) -> [Keys.Command] { Keys.commands.filter { $0.area == area && $0.line != nil } }

    /// "⇧⌘T" as one keycap per symbol; "esc" one keycap; "hold ⌥" the word, then ⌥; "⌘1 … ⌘9" ⌘ 1 to ⌘ 9.
    static func caps(_ shown: String) -> [Cap] {
        if shown == "esc" { return [.key(shown)] }
        return shown.split(separator: " ").flatMap { part -> [Cap] in
            if part == "…" { return [.word("to")] }
            if part.allSatisfy(\.isLowercase) { return [.word(String(part))] }
            return part.map { .key(String($0)) }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            ForEach(Self.columns, id: \.self) { areas in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(areas, id: \.self) { area in
                        Text(area.rawValue.uppercased()).font(Look.font(.ui, size: 11, weight: .semibold).ui).tracking(0.44)
                            .foregroundStyle(Look.Token.ink3.ui).padding(.top, area == areas[0] ? 0 : 10).padding(.bottom, 4)
                        ForEach(Array(Self.lines(area).enumerated()), id: \.element.id) { index, command in
                            if index > 0 { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }
                            HStack(spacing: 12) {
                                Text(command.line ?? command.title).font(Look.medium.font.ui).foregroundStyle(Look.Token.ink.ui)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                KeyCaps(caps: Self.caps(command.shown))
                            }
                            .frame(minHeight: 27)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Keycaps: each a small rounded square ringed in line2, with a line under it; words between them in ink3.
struct KeyCaps: View {
    let caps: [ShortcutColumns.Cap]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                switch cap {
                case .word(let word): Text(word).font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui).padding(.horizontal, 3)
                case .key(let key):
                    let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
                    // One stack, back to front: the line under the cap, the cap, its ring, its symbol.
                    ZStack {
                        shape.fill(Look.Token.line2.ui).offset(y: 1)
                        shape.fill(Look.Token.bg2.ui)
                        shape.strokeBorder(Look.Token.line2.ui)
                        Text(key).font(Look.font(.ui, size: 11.5, weight: .medium).ui).foregroundStyle(Look.Token.ink.ui).padding(.horizontal, 5)
                    }
                    .frame(minWidth: 21, minHeight: 21).fixedSize()
                }
            }
        }
        .fixedSize()
    }
}

private extension View {
    /// A group of rows: bg2 inside a ring of line, at the card radius.
    func card() -> some View {
        let shape = RoundedRectangle(cornerRadius: Look.card, style: .continuous)
        return background(shape.fill(Look.Token.bg2.ui)).overlay(shape.strokeBorder(Look.Token.line.ui)).clipShape(shape)
    }
}
