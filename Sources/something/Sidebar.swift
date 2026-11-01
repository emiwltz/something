// The sidebar's list, which Drawer.swift holds: its head, Spaces · pages of your own, New Group under the pointer, the
// pin and New Space; Needs You, the spaces whose requests wait for the
// person, oldest first, each still in its group too (so ⌘1–9 never move); the spaces in their groups, each group
// folding under its header, which keeps its count; Templates pinned at the bottom, then the word "something" and
// Settings. Groups are only a view, kept in the preferences: the files never move. A row is a name: the title, and "…"
// under the pointer for the menu a right click also gives; its assistant's state lives on the sticker and its card,
// and in the row's VoiceOver label, which `eyes` gives. A page whose declaration does not read is listed too, in
// secondary color: "not a space yet". A space being built has a ring that fills, at once under the build's words and
// then under its name, and a click shows its build on New Space; a space the assistant made while the person was
// elsewhere has a dot, one that just arrived a ring of ink fading out.
// Rename… gives a space a name shown in place of its title, since its file is its name and its grants are keyed by
// it; a group is renamed in place too, or by a double click. Its rows are drawn here, not by a List: the mockup's
// 25-point rows and the identity's quiet selection, which a sidebar List's own 32-point rows and highlight would
// cover; ↑ and ↓ move through New Space, the headers and the rows shown, Return folds the header the keys rest on.
// Inside the glass the greys are the ink at less strength, so they stay readable over any page.
import AppKit
import SwiftUI

/// The sidebar's own state, apart from the spaces and the preferences.
@Observable final class SidebarState {
    /// What can be renamed in place.
    enum Target: Hashable { case space(String), group(String) }
    /// Where ↑ and ↓ stop.
    enum Stop: Hashable { case newSpace, group(String), space(String) }

    /// What can be under the pointer: one of the fixed rows ("head", "tpls"), a group's header, a space's row,
    /// a space's row in Needs You, apart so that a space named like a fixed row, or listed twice, lights only its own.
    enum Hover: Hashable { case nav(String), group(String), space(String), needs(String) }

    /// The row under the pointer.
    var hovered: Hover?
    /// The row or header whose menu is open: it stays lit, a row ringed, while the pointer is in the menu.
    var menued: Hover?
    /// The spaces whose requests wait for the person, oldest first: Needs You. The Shell says it.
    var needs: [String] = []
    /// The group header the keys rest on; nil while they rest on the selection.
    var cursor: String?
    /// What is being renamed in place, and the name typed so far.
    var renaming: Target?
    var draft = ""
    /// The bottoms of the list's rows, in the list's own space: where its shown part may end (SidebarView.shown).
    var ends: [CGFloat] = []
    /// Whether the pin is pressed, and whether it shows: where there is no room for a docked sidebar it hides.
    var kept = false
    var room = true
    /// What the pin does: the Shell's.
    @ObservationIgnored var pin: () -> Void = {}

    /// A menu began: the row or header under the pointer is the one it was opened on (the menu bar's are over none).
    func menuOpened() {
        if case .nav = hovered { return }
        menued = hovered
    }
}

/// A context menu as data: the sidebar draws it, and the tests read it (a menu cannot be drawn offscreen).
enum SidebarMenu {
    indirect enum Line {
        /// `key` is the id of the command whose key the item shows.
        case item(String, symbol: String, key: String? = nil, checked: Bool = false, enabled: Bool = true, destructive: Bool = false,
                  run: () -> Void)
        case submenu(String, symbol: String, [Line])
        case separator
        case note(String)
    }

}

extension Library {
    func folded(_ group: String) -> Bool { preferences.folded.contains(group) }

    /// Folds the group, or unfolds it.
    func toggle(_ group: String) { preferences.fold(group, !folded(group)) }

    /// Rename… of a space: `title` is shown in place of its declared one, in the sidebar, the toolbar, the Go menu and
    /// ⌘P. Blank, or its declared title, gives it back its own. The file keeps its name.
    func rename(_ space: String, to title: String) {
        guard let entry = entry(space) else { return }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.change { $0.names[space] = title.isEmpty || title == entry.declared ? nil : title }
        relist()
        renamed(space)
    }

    /// Show in Group ▸ a group: the space moves there, and the toast says that only the view changed.
    func move(_ space: String, to group: String) {
        preferences.move(space, to: group)
        told("\(entry(space)?.title ?? space) is in \(group) now · groups are only a view, the file stays where it is")
    }

    /// Starts renaming `target` in place, its group unfolded so its row shows. A rename already open is kept first:
    /// its field, going away, would otherwise commit the new target with its untouched name.
    func beginRename(_ target: SidebarState.Target) {
        if let open = sidebar.renaming, open != target { commitRename() }
        switch target {
        case .group(let name): sidebar.draft = name
        case .space(let name):
            if let group = preferences.group(of: name) { preferences.fold(group, false) }
            sidebar.draft = entry(name)?.title ?? name
        }
        sidebar.renaming = target
    }

    /// Return, or the field losing the focus: the name typed is kept. A group keeps its old name when the new one is
    /// blank or another group's.
    func commitRename() {
        guard let target = sidebar.renaming else { return }
        sidebar.renaming = nil
        switch target {
        case .group(let name): preferences.renameGroup(name, to: sidebar.draft)
        case .space(let name): rename(name, to: sidebar.draft)
        }
    }

    /// Esc: nothing changes.
    func cancelRename() { sidebar.renaming = nil }

    /// New Group: an empty group under the first free name, `space` moved into it when one is given, its name ready
    /// to be typed.
    func addGroup(moving space: String? = nil) {
        let group = preferences.newGroup()
        if let space { preferences.move(space, to: group) }
        beginRename(.group(group))
    }

    /// The stops of ↑ and ↓: New Space, then each group's header and, unfolded, its rows; the rows of no group last.
    /// With no space, no header shows: New Space alone.
    func stops() -> [SidebarState.Stop] {
        [.newSpace] + (entries.isEmpty ? [] : sections()).flatMap { group, entries -> [SidebarState.Stop] in
            (group.map { [.group($0)] } ?? []) + (group.map(folded) == true ? [] : entries.map { .space($0.id) })
        }
    }

    /// ↑ (-1) or ↓ (1): the keys rest on the next stop, which opens when it is a space or New Space. Returns the stop,
    /// nil when there is none to go to (on the Templates page, the keys are not in the list).
    @discardableResult func step(_ by: Int) -> SidebarState.Stop? {
        let all = stops()
        let here: SidebarState.Stop? = sidebar.cursor.map { .group($0) } ?? (selection == .newSpace ? .newSpace : selection.space.map { .space($0) })
        guard let here else { return nil }
        // An open space in a folded group (opened from the Go menu) is not a stop: the keys start from its header.
        let header = selection.space.flatMap(preferences.group(of:)).flatMap { all.firstIndex(of: .group($0)) }
        let at = all.firstIndex(of: here) ?? header ?? (by > 0 ? -1 : all.count)
        let next = all[min(max(at + by, 0), all.count - 1)]
        switch next {
        case .group(let name): sidebar.cursor = name
        case .newSpace:
            sidebar.cursor = nil
            select(.newSpace)
        case .space(let name):
            sidebar.cursor = nil
            select(.space(name))
        }
        return next
    }

    /// Return: folds or unfolds the header the keys rest on. Returns whether there was one.
    func enter() -> Bool {
        guard let group = sidebar.cursor else { return false }
        toggle(group)
        return true
    }

    /// The menu of a space, by a right click or its "…": the mockup's, Show in Group listing every group with a check
    /// on its own, then New Group… and the reminder that the file does not move.
    func menu(for entry: Entry) -> [SidebarMenu.Line] {
        let id = entry.id, mine = preferences.group(of: id)
        let groups: [SidebarMenu.Line] = preferences.groups.map { group in
            .item(group.name, symbol: "folder", checked: group.name == mine, enabled: group.name != mine) { [weak self] in
                self?.move(id, to: group.name)
            }
        }
        return [
            .item("Open", symbol: "doc") { [weak self] in self?.select(.space(id)) },
            .item("Show Info", symbol: "info.circle", key: "insp") { [weak self] in
                self?.select(.space(id))
                NSApp.sendAction(#selector(App.showSpaceInfo(_:)), to: nil, from: nil)
            },
            .item("Rename…", symbol: "pencil") { [weak self] in self?.beginRename(.space(id)) },
            .submenu("Show in Group", symbol: "folder", groups + (groups.isEmpty ? [] : [.separator]) + [
                .item("New Group…", symbol: "folder.badge.plus") { [weak self] in self?.addGroup(moving: id) },
                .note("Groups are only in the sidebar. The file does not move."),
            ]),
            .separator,
            .item("Show in Finder", symbol: "macwindow") { [weak self] in self?.showInFinder(id) },
            .item("Export…", symbol: "square.and.arrow.up") { [weak self] in self?.export(id) },
            .separator,
            .item("Move to Trash…", symbol: "trash", destructive: true) { [weak self] in
                if let entry = self?.entry(id) { self?.trashing(entry) }
            },
        ]
    }

    /// The menu of a group's header.
    func menu(forGroup group: String) -> [SidebarMenu.Line] {
        [.item("Rename…", symbol: "pencil") { [weak self] in self?.beginRename(.group(group)) },
         .item("New Group", symbol: "folder.badge.plus") { [weak self] in self?.addGroup() }]
    }

    /// What VoiceOver says of a space's row: its title and its assistant's state, or that it is not a space yet.
    static func label(_ entry: Entry, _ state: Sign.State) -> String {
        entry.isSpace ? "\(entry.title), \(state.word)" : "\(entry.title), not a space yet"
    }

    /// What VoiceOver says of a group's header.
    func label(group: String, count: Int) -> String {
        "\(group), \(count) \(count == 1 ? "space" : "spaces"), \(folded(group) ? "folded" : "open")"
    }

    /// The spaces Needs You lists: those of `needs` the sidebar lists, in its order.
    func needing() -> [Entry] { sidebar.needs.compactMap(entry) }

    /// Where a click on a Needs You row goes.
    enum NeedsGo: Equatable { case space(String), request }

    /// Where a click on `id`'s Needs You row goes: the open space's row shows its request in the panel, any other
    /// opens its space. Never an answer: only the panel's Allow Once or Deny decides (rule 2).
    func needsGo(_ id: String) -> NeedsGo { selection == .space(id) ? .request : .space(id) }
}

extension App {
    /// Show Info from a row's menu: Info opens beside the space the menu just selected, and stays open when it was.
    @objc func showSpaceInfo(_ sender: Any?) {
        shell.showInfo(true)
    }
}

struct SidebarView: View {
    @Bindable var library: Library
    let assistant: AssistantModel
    /// The state of the space of that name's assistant, read from its own conversation.
    let eyes: (String) -> Sign.State
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var state: SidebarState { library.sidebar }
    /// Greys as the mockup's glass mixes them: the ink at less strength.
    private var ink2: Color { Look.Token.ink.ui.opacity(0.74) }
    private var ink3: Color { Look.Token.ink.ui.opacity(0.6) }
    private var hoverFill: Color { Look.Token.ink.ui.opacity(0.07) }
    private var selected: Color { Look.Token.ink.ui.opacity(0.11) }
    /// What the list says while there is no space, and no group header shows: the center invites to make one.
    static let empty = "Your spaces appear here"
    /// The height of the list's fade, the mockup's 22 points: most of the last row shown.
    static let fade: CGFloat = 22
    /// Templates' height, at the interface size.
    static var nav: CGFloat { 30 * Look.scale.size.factor }

    /// How tall the list is drawn in `room`: all of it when it fits; else down to the end of the last row that fits
    /// whole (`ends`, the rows' bottoms in the list), so that no row is cut through and the last one is the faded one.
    static func shown(_ room: CGFloat, ends: [CGFloat]) -> CGFloat {
        guard let last = ends.max(), last + fade > room else { return room }
        return ends.filter { $0 <= room }.max() ?? room
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            // A list longer than the sidebar ends on a whole row, which fades out above Templates, rather than being
            // cut through a row; scrolled to its end, the last row clears the fade.
            GeometryReader { box in
                ScrollView {
                    list.padding(.bottom, Self.fade).coordinateSpace(.named(RowEnds.space))
                        .onPreferenceChange(RowEnds.self) { ends in MainActor.assumeIsolated { if state.ends != ends { state.ends = ends } } }
                }
                .scrollIndicators(.never)
                .mask(VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: Self.fade)
                })
                .frame(height: Self.shown(box.size.height, ends: state.ends))
            }
            templates
            footer
        }
        .padding(EdgeInsets(top: 6, leading: 8, bottom: 8, trailing: 8))
        .font(Look.body.font.ui)
        .foregroundStyle(Look.Token.ink.ui)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { step(-1) }
        .onKeyPress(.downArrow) { step(1) }
        .onKeyPress(.return) { library.enter() ? .handled : .ignored }
        // A right click or "…" opens a menu over the row under the pointer; SwiftUI says neither, the menu's tracking does.
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in state.menuOpened() }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in state.menued = nil }
        .background(tint.ignoresSafeArea())
        .overlay { lip.allowsHitTesting(false) }
    }

    /// What lies over the blur: at night black first, which darkens a light page, then the sidebar's colour.
    @ViewBuilder private var tint: some View {
        ZStack {
            if scheme == .dark { Color.black.opacity(0.5) }
            Look.Token.side.ui.opacity(scheme == .dark ? 0.74 : 0.72)
        }
    }

    /// The glass's fine light edge, which detaches it from the page.
    private var lip: some View {
        let light = Color.white.opacity(scheme == .dark ? 0.1 : 0.5)
        return RoundedRectangle(cornerRadius: Drawer.radius, style: .continuous).strokeBorder(light, lineWidth: 0.5)
            .overlay(alignment: .top) { Rectangle().fill(light).frame(height: 1).padding(.horizontal, Drawer.radius) }
    }

    /// The head, 30 points: the word, New Group under the pointer, the pin where there is room, and New Space.
    private var head: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Text("Spaces").font(Look.font(.ui, size: 13, weight: .semibold).ui).kerning(-0.13).foregroundStyle(Look.Token.ink.ui)
                Text("pages of your own").font(Look.font(.ui, size: 11).ui).foregroundStyle(ink3).lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Spaces, pages of your own")
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            action("folder.badge.plus", "New Group", help: "New Group") { library.addGroup() }.opacity(state.hovered == .nav("head") || voiceOver ? 1 : 0)
            if state.room {
                action("pin", state.kept ? "Let It Float" : "Keep Open", help: state.kept ? "Let It Float" : "Keep Open", turned: 45) { state.pin() }
                    .background(state.kept ? selected : .clear, in: RoundedRectangle(cornerRadius: Look.control))
            }
            action("plus", "New Space", help: Keys.tooltip("new", "New Space")) { newSpace() }
        }
        .padding(EdgeInsets(top: 0, leading: 9, bottom: 0, trailing: 6)).frame(height: 30 * Look.scale.size.factor).padding(.bottom, 4)
        .contentShape(Rectangle())
        .onHover { hover(.nav("head"), $0) }
    }

    /// A button of the head, 22 points wide.
    private func action(_ symbol: String, _ label: String, help: String, turned: Double = 0, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol).font(Look.icon(12)).foregroundStyle(ink2).rotationEffect(.degrees(turned))
                .frame(width: 22, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(label)
    }

    /// The groups and their rows, or, with no space at all, only the words that say where they will be.
    @ViewBuilder private var list: some View {
        // The builds whose space has no file yet: first among the spaces, under Needs You.
        let pending = assistant.builds.filter { build in assistant.space(of: build).map { library.entry($0) == nil } ?? true }
        let builds = VStack(alignment: .leading, spacing: 1) { ForEach(pending) { building($0).rowEnd() } }
        if library.entries.isEmpty {
            if pending.isEmpty {
                Text(Self.empty).font(Look.font(.ui, size: 12).ui).foregroundStyle(ink3)
                    .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).rowEnd()
            } else { builds }
        } else {
            let sections = library.sections()
            VStack(alignment: .leading, spacing: 7) {
                needs
                if !pending.isEmpty { builds }
                ForEach(sections, id: \.group) { section in
                    VStack(alignment: .leading, spacing: 1) {
                        if let group = section.group {
                            header(group, count: section.entries.count).rowEnd()
                        }
                        if section.group.map(library.folded) != true {
                            ForEach(section.entries) { space($0).rowEnd() }
                            if section.entries.isEmpty {
                                Text("No spaces in this group").font(Look.small.font.ui).foregroundStyle(ink3)
                                    .padding(EdgeInsets(top: 4, leading: 33, bottom: 6, trailing: 8)).rowEnd()
                            }
                        }
                    }
                }
            }
        }
    }

    /// Needs You, over the groups while a request waits: a mark, the words and the count in the colour of what waits,
    /// then a row per space, a bar of that colour at its edge. A click opens the space, or, open already, shows its
    /// request in the panel, the only place that answers (rule 2).
    @ViewBuilder private var needs: some View {
        let spaces = library.needing()
        if !spaces.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Circle().fill(Look.Token.need.ui).frame(width: 7, height: 7)
                        .background(Circle().fill(Look.Token.needSoft.ui).frame(width: 13, height: 13))
                    Text("Needs You")
                    Spacer(minLength: 0)
                    // On the groups' count column.
                    Text("\(spaces.count)").font(Look.font(.ui, size: 11, weight: .medium).ui).monospacedDigit().frame(width: 22)
                }
                .font(Look.font(.ui, size: 11.5, weight: .semibold).ui)
                .foregroundStyle(Look.Token.needInk.ui)
                .padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 6)).frame(height: 26 * Look.scale.size.factor)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Needs You, \(spaces.count) \(spaces.count == 1 ? "space" : "spaces")")
                .accessibilityAddTraits(.isHeader)
                .rowEnd()
                ForEach(spaces) { space($0, needs: true).rowEnd() }
            }
            .padding(EdgeInsets(top: 2, leading: 0, bottom: 6, trailing: 0))
            .overlay(alignment: .bottom) { Rectangle().fill(selected).frame(height: 1) }
        }
    }

    /// The word "something", and Settings.
    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(selected).frame(height: 1)
            HStack(spacing: 8) {
                Text("something").font(Look.font(.title, size: 15, weight: .bold).ui).kerning(-0.4)
                Spacer(minLength: 0)
                Button { Keys.send("settings") } label: {
                    Image(systemName: "gearshape").font(Look.icon(15)).foregroundStyle(ink2).frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(Keys.tooltip("settings", "Settings")).accessibilityLabel("Settings")
            }
            .padding(EdgeInsets(top: 9, leading: 9, bottom: 0, trailing: 5))
        }
        .padding(.top, 6)
    }

    func newSpace() {
        follow(nil)
        assistant.focus()
    }

    /// Shows the build `number` on New Space, a click on its row, or its own field for nil.
    private func follow(_ number: Int?) {
        state.cursor = nil
        library.select(.newSpace)
        assistant.watch(number)
    }

    /// The row of a build whose space has no name yet: its ring and its words, shortened.
    private func building(_ build: AssistantModel.Build) -> some View {
        let on = library.selection == .newSpace && assistant.watched == build.id, progress = assistant.ladder(build).progress
        let title = AssistantModel.provisional(build.sentence)
        return HStack(spacing: 7) {
            BuildRing(progress: progress)
            Text(title).font(Self.title(on: on).ui).foregroundStyle(ink2)
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(EdgeInsets(top: 0, leading: 9, bottom: 0, trailing: 6)).frame(height: Look.row)
        .background(on ? selected : .clear, in: RoundedRectangle(cornerRadius: Look.control))
        .contentShape(Rectangle())
        .onTapGesture { follow(build.id) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.building(title, progress))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { follow(build.id) }
    }

    /// What VoiceOver says of a building row.
    static func building(_ title: String, _ progress: Double) -> String { "\(title), building, \(Int((progress * 100).rounded())) %" }

    private func step(_ by: Int) -> KeyPress.Result {
        guard let stop = library.step(by) else { return .ignored }
        if stop == .newSpace { assistant.focus() }
        return .handled
    }

    /// Notes which row the pointer is over, and forgets it when the pointer leaves that row.
    private func hover(_ key: SidebarState.Hover, _ inside: Bool) {
        if inside { state.hovered = key } else if state.hovered == key { state.hovered = nil }
    }

    /// Templates: 30 points, medium, its shortcut shown under the pointer and while its page shows.
    private var templates: some View {
        let on = library.selection == .templates && !library.previewing, hovered = state.hovered == .nav("tpls")
        return Button { library.select(.templates) } label: {
            HStack(spacing: 9) {
                Image(systemName: "square.grid.2x2").font(Look.icon(13)).foregroundStyle(ink2).frame(width: 16)
                Text("Templates").font(Look.font(.ui, size: 13, weight: .medium).ui)
                Spacer(minLength: 0)
                if on || hovered { Text(Keys.shown("tpls")).font(Look.small.font.ui).foregroundStyle(ink3) }
            }
            .padding(.horizontal, 9).frame(height: Self.nav)
            .background(on ? selected : hovered ? hoverFill : .clear, in: RoundedRectangle(cornerRadius: Look.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .onHover { hover(.nav("tpls"), $0) }
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A group's header, 25 points: its name, and its count on a 22-point column where the chevron takes its place
    /// under the pointer, turned a quarter while folded; at rest a folded group still says how many spaces it hides.
    /// A click folds it; a double click renames it in place.
    private func header(_ group: String, count: Int) -> some View {
        let folded = library.folded(group), key = SidebarState.Hover.group(group)
        let lit = state.hovered == key || state.menued == key || state.cursor == group
        return HStack(spacing: 6) {
            if state.renaming == .group(group) {
                RenameField(state: state, target: .group(group), commit: library.commitRename, cancel: library.cancelRename).frame(maxWidth: 160)
            } else {
                Text(group).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("\(count)").font(Look.font(.ui, size: 11, weight: .medium).ui).monospacedDigit()
                .frame(width: 22).opacity(lit ? 0 : 1)
                .overlay {
                    Image(systemName: "chevron.down").font(Look.icon(9, weight: .semibold))
                        .rotationEffect(.degrees(folded ? -90 : 0)).opacity(lit ? 1 : 0)
                }
        }
        .font(Look.font(.ui, size: 11.5, weight: .semibold).ui)
        .foregroundStyle(lit ? ink2 : ink3)
        .padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 6)).frame(height: 25 * Look.scale.size.factor)
        .background(lit ? hoverFill : .clear, in: RoundedRectangle(cornerRadius: Look.control))
        .contentShape(Rectangle())
        // The double click first, so that SwiftUI waits for it and a rename does not fold the group on the way.
        .onTapGesture(count: 2) { library.beginRename(.group(group)) }
        .onTapGesture {
            state.cursor = nil
            library.toggle(group)
        }
        .onHover { hover(key, $0) }
        .contextMenu { Self.items(library.menu(forGroup: group)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(library.label(group: group, count: count))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { library.toggle(group) }
        .accessibilityAction(named: "Rename") { library.beginRename(.group(group)) }
    }

    /// A row of the list, 25 points in Emi's compact density: its name, the dot of a space made while the person was
    /// elsewhere, "…" under the pointer. In Needs You (`needs`), the bar of what waits at its edge, no "…", and a
    /// click on the open space shows its request.
    private func space(_ entry: Library.Entry, needs: Bool = false) -> some View {
        let on = library.selection == .space(entry.id), fresh = library.fresh == entry.id, key = needs ? SidebarState.Hover.needs(entry.id) : .space(entry.id),
            menued = state.menued == key, hovered = state.hovered == key || menued
        let menu = library.menu(for: entry), build = needs ? nil : assistant.build(writing: entry.id)
        let open = {
            if let build { return follow(build.id) }
            state.cursor = nil
            switch needs ? library.needsGo(entry.id) : .space(entry.id) {
            case .request: Keys.send("showreq")
            case let .space(id): library.select(.space(id))
            }
        }
        let progress = build.map { assistant.ladder($0).progress }
        return HStack(spacing: 6) {
            if let progress { BuildRing(progress: progress).padding(.trailing, 1) }
            if state.renaming == .space(entry.id) && !needs {
                RenameField(state: state, target: .space(entry.id), commit: library.commitRename, cancel: library.cancelRename).font(Self.title(on: true).ui)
            } else {
                Text(entry.title).font(Self.title(on: on).ui).foregroundStyle(entry.isSpace ? Look.Token.ink.ui : ink3)
                if assistant.ready.contains(entry.id) { Circle().fill(Look.Token.ink.ui).frame(width: 6, height: 6).accessibilityHidden(true) }
                Spacer(minLength: 4)
                if hovered && !needs {
                    Menu { Self.items(menu, live: false) } label: {
                        Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)).foregroundStyle(ink2)
                    }
                    .plainMenu().frame(width: 22, height: 20)
                    .accessibilityLabel("More for \(entry.title)")
                }
                if !entry.isSpace {
                    Text("not a space yet").font(Look.xs.font.ui).foregroundStyle(ink3)
                }
            }
        }
        .lineLimit(1)
        .padding(EdgeInsets(top: 0, leading: 9, bottom: 0, trailing: 6)).frame(height: Look.row)
        .background(on ? selected : hovered ? hoverFill : .clear, in: RoundedRectangle(cornerRadius: Look.control))
        .overlay(alignment: .leading) {
            if needs { RoundedRectangle(cornerRadius: 2).fill(Look.Token.need.ui).frame(width: 3).padding(.vertical, 8).offset(x: 1) }
        }
        .overlay {
            if menued { RoundedRectangle(cornerRadius: Look.control).strokeBorder(ink2, lineWidth: 1.5).allowsHitTesting(false) }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hover(key, $0) }
        .contextMenu { Self.items(menu) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.map { Self.building(entry.title, $0) } ?? Library.label(entry, needs ? .wait : eyes(entry.id)))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { open() }
        // The mockup's .fresh: the ring at once, then gone in 1.6 s on the "out" curve; a row it leaves goes 0 to 0.
        .overlay {
            RoundedRectangle(cornerRadius: Look.control).strokeBorder(Look.Token.ink.ui, lineWidth: 1.5).allowsHitTesting(false)
                .keyframeAnimator(initialValue: 0.0, trigger: library.fresh) { ring, alpha in ring.opacity(alpha) } keyframes: { _ in
                    MoveKeyframe(fresh && !needs ? 1.0 : 0)
                    LinearKeyframe(0.0, duration: fresh && !needs ? 1.6 : 0.01, timingCurve: Look.out.unit)
                }
        }
    }

    /// A row's title: semibold when it is the open space. The face is picked by name, since `fontWeight` does not
    /// change a bundled font.
    private static func title(on: Bool) -> NSFont { Look.font(.ui, size: Look.body.size, weight: on ? .semibold : .regular) }

    /// The lines of a menu as SwiftUI draws them in a context menu or the "…" menu. `live` registers an item's key:
    /// the "…" menu exists while the pointer is over its row, and a key it registered would act on that row, not on
    /// the open space, so it only writes the key in its title.
    static func items(_ lines: [SidebarMenu.Line], live: Bool = true) -> some View {
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in item(line, live: live) }
    }

    private static func item(_ line: SidebarMenu.Line, live: Bool) -> AnyView {
        switch line {
        case let .item(title, symbol, key, checked, enabled, destructive, run):
            let shown = live ? title : ([title] + [key.map(Keys.shown)].compactMap { $0 }).joined(separator: "  ")
            let button = Button(role: destructive ? .destructive : nil, action: run) { Label(shown, systemImage: checked ? "checkmark" : symbol) }
                .disabled(!enabled)
            guard live, let command = key.flatMap(Keys.command), let character = command.key.first else { return AnyView(button) }
            return AnyView(button.keyboardShortcut(KeyEquivalent(character), modifiers: EventModifiers(command.modifiers)))
        case let .submenu(title, symbol, lines): return AnyView(Menu { items(lines, live: live) } label: { Label(title, systemImage: symbol) })
        case .separator: return AnyView(Divider())
        case .note(let words): return AnyView(Text(words))
        }
    }
}

/// The field of a name renamed in place, which takes the focus as it appears: Return keeps the name, Esc puts the
/// old one back, leaving the field keeps it, unless another rename began meanwhile (it kept this one first).
private struct RenameField: View {
    @Bindable var state: SidebarState
    let target: SidebarState.Target
    let commit: () -> Void, cancel: () -> Void
    @FocusState private var typing: Bool

    var body: some View {
        TextField("Name", text: $state.draft)
            .textFieldStyle(.plain)
            .padding(.horizontal, 4).frame(height: 22)
            .boxed(RoundedRectangle(cornerRadius: 5), Look.Token.bg2.ui, ring: Look.Token.ink.ui, width: 2)
            .padding(.horizontal, -4)
            .focused($typing)
            .accessibilityLabel("Name")
            .onSubmit(commit)
            .onExitCommand(perform: cancel)
            .onChange(of: typing) { _, now in if !now && state.renaming == target { commit() } }
            .onAppear { typing = true }
    }
}

private extension EventModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
    }
}

/// The bottoms of the sidebar list's rows, gathered in the list's own space.
struct RowEnds: PreferenceKey {
    static let space = "sidebar.list"
    static let defaultValue: [CGFloat] = []
    static func reduce(value: inout [CGFloat], nextValue: () -> [CGFloat]) { value += nextValue() }
}

extension View {
    /// Tells the list where this row ends.
    func rowEnd() -> some View {
        background(GeometryReader { Color.clear.preference(key: RowEnds.self, value: [$0.frame(in: .named(RowEnds.space)).maxY]) })
    }
}
