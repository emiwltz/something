// The narrow window's sidebar, a rail of icons (the mockup's .wn-rail): the toggle that lays the whole sidebar over the
// space (⌃⌘S), New Space, Go to…, a line, New Group, then each space as a letter on its colour (the only place a space
// has one: the sidebar is a list of names), every group's rows shown even folded since no header is, a line between
// groups; Templates and Settings at the foot. No words fit: each button says what it is under the pointer, a space in a
// bubble beside its tile (RailTip: its name and its assistant's state, drawn at once, which a system tooltip is not), and
// to VoiceOver, a space "Title, state" as in the sidebar. ↑ and ↓ move through New Space and the spaces.
import AppKit
import SwiftUI

struct Rail: View {
    /// The sidebar it stands in for: its library, its eyes, and its ways to New Space, the keys and the pointer.
    let side: SidebarView

    /// The rail's width, the mockup's 64 points: its 40-point buttons with 12 on each side.
    static let width: CGFloat = 64

    private var library: Library { side.library }
    private var state: SidebarState { side.state }

    /// What a space's tile says under the pointer, on one line: its name, and its assistant's state, the rail's only word
    /// for it (RailTip draws the same two).
    static func tip(_ entry: Library.Entry, _ state: Sign.State) -> String {
        "\(entry.title) · \(entry.isSpace ? state.word : "not a space yet")"
    }

    /// The letter a space's tile shows: the first of its name, in capitals; "?" for a name with none.
    static func letter(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        VStack(spacing: 0) {
            nav("Show Sidebar", tip: Keys.tooltip("sidebar", "Show Sidebar"), on: false, open: { Keys.send("sidebar") }) {
                Image(systemName: "sidebar.left").font(.system(size: 12)).foregroundStyle(Look.Token.ink2.ui)
            }
            nav("New Space", tip: tip("new", "New Space"), on: library.selection == .newSpace, open: side.newSpace) {
                Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(Look.Token.actfg.ui)
                    .frame(width: 20, height: 20).background(Look.Token.act.ui, in: RoundedRectangle(cornerRadius: 6))
            }
            nav("Go to…", tip: tip("palette", "Go to…"), on: false, open: { Keys.send("palette") }) {
                Image(systemName: "magnifyingglass").font(.system(size: 11.5)).foregroundStyle(Look.Token.ink2.ui)
            }
            .disabled(Keys.command("palette")?.action == nil)
            Self.line.padding(.top, 6)
            Button { library.addGroup() } label: {
                Image(systemName: "folder.badge.plus").font(.system(size: 11)).foregroundStyle(Look.Token.ink3.ui)
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
                Image(systemName: "square.grid.2x2").font(.system(size: 12)).foregroundStyle(Look.Token.ink2.ui)
            }
            Self.line.padding(.top, 8)
            Button { Keys.send("settings") } label: {
                Image(systemName: "gearshape").font(.system(size: 12)).foregroundStyle(Look.Token.ink2.ui).frame(width: 26, height: 26)
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
        .onKeyPress(.upArrow) { side.step(-1) }
        .onKeyPress(.downArrow) { side.step(1) }
        .background(Look.Token.side.ui.ignoresSafeArea())
    }

    /// The thin line between the rail's parts, 40 points wide.
    private static var line: some View { Rectangle().fill(Look.Token.line.ui).frame(width: 40, height: 1) }

    /// The mockup's rail tooltip: the words, two spaces, the key.
    private func tip(_ key: String, _ words: String) -> String {
        let shown = Keys.shown(key)
        return shown.isEmpty ? words : "\(words)  \(shown)"
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
        .onHover { side.hover(key, $0) }
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A space's button, 44 by 38: its letter tile, 22 points, white on the colour of its name (a page that is not a
    /// space yet, grey), ringed in that colour when it is open, on the selection's fill.
    private func space(_ entry: Library.Entry) -> some View {
        let on = library.selection == .space(entry.id), now = side.eyes(entry.id), key = SidebarState.Hover.space(entry.id)
        let tone = entry.isSpace ? Color(nsColor: Look.tile(entry.id)) : Look.Token.mist.ui
        return Text(Self.letter(entry.title)).font(Look.font(.ui, size: 11, weight: .semibold).ui)
            .foregroundStyle(entry.isSpace ? Color.white : Look.Token.ink2.ui)
            .frame(width: 22, height: 22)
            .background(tone, in: RoundedRectangle(cornerRadius: 6.16))
            .overlay { RoundedRectangle(cornerRadius: 6.16).strokeBorder(.black.opacity(0.06), lineWidth: 1) }
            // The mockup's selected tile: 2 points of the background around it, then 1.5 of its colour.
            .overlay {
                if on {
                    RoundedRectangle(cornerRadius: 8.16).strokeBorder(Look.Token.bg.ui, lineWidth: 2).padding(-2)
                    RoundedRectangle(cornerRadius: 9.66).strokeBorder(tone, lineWidth: 1.5).padding(-3.5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if side.assistant.ready.contains(entry.id) { Circle().fill(Look.Token.ink.ui).frame(width: 6, height: 6).offset(x: 4, y: -4) }
            }
            .frame(width: 44, height: 38)
            .background(TileAnchor(id: entry.id, state: state))
        .background(on ? Look.Token.sel.ui : state.hovered == key ? Look.Token.hover.ui : .clear, in: RoundedRectangle(cornerRadius: Look.control))
        .contentShape(Rectangle())
        .onTapGesture {
            state.cursor = nil
            library.select(.space(entry.id))
        }
        .onHover { side.hover(key, $0) }
        .contextMenu { SidebarView.items(library.menu(for: entry)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Library.label(entry, now))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { library.select(.space(entry.id)) }
    }
}

/// Where a space's tile is, for the Shell to lay its bubble beside it: a view of its own, which AppKit can place.
private struct TileAnchor: NSViewRepresentable {
    let id: String, state: SidebarState

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        state.tiles[id] = SidebarState.Weak(view: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { state.tiles[id] = SidebarState.Weak(view: view) }
}

/// The name of the rail's tile under the pointer, in a bubble beside it (the mockup's .wn-rail tooltip): an arrow
/// towards the tile, the name in semibold, its assistant's eyes and state. It lies in the window layer, over the space,
/// which the rail's own column could not draw over; it takes no click.
final class RailTip: NSHostingView<RailTip.Bubble> {
    struct Bubble: View {
        /// The tile's name, and its assistant's state; nil for a page that is not a space yet.
        let name: String, state: Sign.State?

        var body: some View {
            HStack(spacing: 0) {
                Rectangle().fill(Look.Token.act.ui).frame(width: 7, height: 7).rotationEffect(.degrees(45)).offset(x: 4)
                HStack(spacing: 7) {
                    Text(name).font(Look.font(.ui, size: 12, weight: .semibold).ui)
                    if let state { Image(nsImage: Sign.miniEyes(state)).renderingMode(.template).resizable().frame(width: 12, height: 7.5) }
                    Text(state?.word ?? "not a space yet").font(Look.font(.ui, size: 11.5).ui).opacity(0.75)
                }
                .foregroundStyle(Look.Token.actfg.ui).lineLimit(1)
                .padding(.horizontal, 9).frame(height: 26)
                .background(Look.Token.act.ui, in: RoundedRectangle(cornerRadius: 6))
            }
            .fixedSize()
            .accessibilityHidden(true)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Shows the bubble of `entry` beside `tile` in `layer`, in place of any other; none for nil.
    static func show(_ entry: Library.Entry?, _ state: Sign.State, beside tile: NSView?, in layer: WindowLayer) {
        layer.subviews.filter { $0 is RailTip }.forEach { $0.removeFromSuperview() }
        guard let entry, let tile, tile.window === layer.window else { return }
        let tip = RailTip(rootView: Bubble(name: entry.title, state: entry.isSpace ? state : nil))
        let size = tip.fittingSize, at = layer.convert(tile.bounds, from: tile)
        tip.frame = NSRect(x: at.maxX - 2, y: at.midY - size.height / 2, width: size.width, height: size.height)
        layer.hold(tip)
    }
}

extension Shell {
    /// Keeps the rail's bubble on the tile under the pointer, while the column is the rail.
    func watchRailTip() {
        let side = library.sidebar
        let hovered = withObservationTracking { side.rail ? side.hovered : nil } onChange: { [weak self] in
            DispatchQueue.main.async { self?.watchRailTip() }
        }
        guard case .space(let id)? = hovered, let entry = library.entry(id) else { return RailTip.show(nil, .sleep, beside: nil, in: layer) }
        let eyes = (split.splitViewItems[0].viewController as? NSHostingController<SidebarView>)?.rootView.eyes
        RailTip.show(entry, eyes?(id) ?? .sleep, beside: side.tiles[id]?.view, in: layer)
    }
}
