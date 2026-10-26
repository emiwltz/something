// The narrow window's sidebar, a rail of icons (the mockup's .wn-rail): the toggle that lays the whole sidebar over the
// space (⌃⌘S), New Space, Go to…, a line, New Group, then each space's icon with its assistant's eyes under it, every
// group's rows shown even folded since no header is, a line between groups; Templates and Settings at the foot. No
// words fit: each button says what it is under the pointer, a space "name · state", and to VoiceOver, a space
// "Title, state" as in the sidebar. ↑ and ↓ move through New Space and the spaces.
import AppKit
import SwiftUI

struct Rail: View {
    let library: Library
    let assistant: AssistantModel
    let eyes: (String) -> Sign.State

    /// The rail's width, the mockup's 64 points: its 40-point buttons with 12 on each side.
    static let width: CGFloat = 64

    private var state: SidebarState { library.sidebar }

    /// What a space's icon says under the pointer.
    static func tip(_ entry: Library.Entry, _ state: Sign.State) -> String {
        "\(entry.title) · \(entry.isSpace ? state.word : "not a space yet")"
    }

    var body: some View {
        VStack(spacing: 0) {
            nav("Show Sidebar", tip: Keys.tooltip("sidebar", "Show Sidebar"), on: false, open: { Keys.send("sidebar") }) {
                Image(systemName: "sidebar.left").font(.system(size: 13, weight: .medium)).foregroundStyle(Look.Token.ink2.ui)
            }
            nav("New Space", tip: tip("new", "New Space"), on: library.selection == .newSpace, open: newSpace) {
                Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(Look.Token.actfg.ui)
                    .frame(width: 20, height: 20).background(Look.Token.act.ui, in: RoundedRectangle(cornerRadius: 6))
            }
            nav("Go to…", tip: tip("palette", "Go to…"), on: false, open: { Keys.send("palette") }) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Look.Token.ink2.ui)
            }
            .disabled(Keys.command("palette")?.action == nil)
            Self.line.padding(.top, 6)
            Button { library.addGroup() } label: {
                Image(systemName: "folder.badge.plus").font(.system(size: 12)).foregroundStyle(Look.Token.ink3.ui)
                    .frame(width: 40, height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("New Group").accessibilityLabel("New Group")
            .padding(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(library.sections().filter { !$0.entries.isEmpty }.enumerated()), id: \.offset) { index, section in
                        if index > 0 { Self.line.frame(width: 44) }
                        VStack(spacing: 2) { ForEach(section.entries) { space($0) } }
                    }
                }
            }
            .scrollIndicators(.never)
            Spacer(minLength: 0)
            nav("Templates", tip: tip("tpls", "Templates"), on: library.selection == .templates && !library.previewing,
                open: { library.select(.templates) }) {
                Image(systemName: "square.grid.2x2").font(.system(size: 13)).foregroundStyle(Look.Token.ink2.ui)
            }
            Self.line.padding(.top, 8)
            Button { Keys.send("settings") } label: {
                Image(systemName: "gearshape").font(.system(size: 13)).foregroundStyle(Look.Token.ink2.ui).frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(Keys.tooltip("settings", "Settings")).accessibilityLabel("Settings")
            .padding(.top, 8)
        }
        // The toggle's row starts 48 points down the window, just under the toolbar's band, as the mockup's rail head.
        .padding(EdgeInsets(top: -4, leading: 0, bottom: 10, trailing: 0))
        .frame(width: Self.width)
        .foregroundStyle(Look.Token.ink.ui)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { step(-1) }
        .onKeyPress(.downArrow) { step(1) }
        .background(Look.Token.side.ui.ignoresSafeArea())
    }

    /// The thin line between the rail's parts, 40 points wide.
    private static var line: some View { Rectangle().fill(Look.Token.line.ui).frame(width: 40, height: 1) }

    /// The mockup's rail tooltip: the words, two spaces, the key.
    private func tip(_ key: String, _ words: String) -> String {
        let shown = Keys.shown(key)
        return shown.isEmpty ? words : "\(words)  \(shown)"
    }

    private func newSpace() {
        state.cursor = nil
        library.select(.newSpace)
        assistant.focus()
    }

    private func step(_ by: Int) -> KeyPress.Result {
        guard let stop = library.step(by) else { return .ignored }
        if stop == .newSpace { assistant.focus() }
        return .handled
    }

    /// A button of the head or foot: 40 by 34, its icon alone, filled while it is the page shown or under the pointer.
    private func nav(_ label: String, tip: String, on: Bool, open: @escaping () -> Void, @ViewBuilder icon: () -> some View) -> some View {
        let key = SidebarState.Hover.nav("rail." + label)
        return Button(action: open) {
            icon().frame(width: 40, height: 34)
                .background(on ? Look.Token.sel.ui : state.hovered == key ? Look.Token.hover.ui : .clear, in: RoundedRectangle(cornerRadius: Look.control))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tip)
        .onHover { inside in if inside { state.hovered = key } else if state.hovered == key { state.hovered = nil } }
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A space's button, 44 by 38: its template's symbol raised, its assistant's eyes under it (unless Settings ›
    /// Interface hides them), the selection's fill when it is open.
    private func space(_ entry: Library.Entry) -> some View {
        let on = library.selection == .space(entry.id), now = eyes(entry.id), key = SidebarState.Hover.space(entry.id)
        return ZStack {
            Image(systemName: Template.symbol(of: entry.id)).font(.system(size: 14)).foregroundStyle(on ? Look.Token.ink.ui : Look.Token.ink2.ui)
                .frame(width: 17, height: 17).offset(y: entry.isSpace ? -4 : 0)
                .overlay(alignment: .topTrailing) {
                    if assistant.ready?.id == entry.id { Circle().fill(Look.Token.ink.ui).frame(width: 6, height: 6).offset(x: 3, y: -7) }
                }
            if entry.isSpace && library.preferences.sidebarEyes {
                Image(nsImage: Sign.miniEyes(now, template: false)).resizable().frame(width: 13.6, height: 8.5)
                    .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 4)
            }
        }
        .frame(width: 44, height: 38)
        .background(on ? Look.Token.sel.ui : state.hovered == key ? Look.Token.hover.ui : .clear, in: RoundedRectangle(cornerRadius: Look.control))
        .contentShape(Rectangle())
        .onTapGesture {
            state.cursor = nil
            library.select(.space(entry.id))
        }
        .onHover { inside in if inside { state.hovered = key } else if state.hovered == key { state.hovered = nil } }
        .help(Self.tip(entry, now))
        .contextMenu { SidebarView.items(library.menu(for: entry)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Library.label(entry, now))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { library.select(.space(entry.id)) }
    }
}
