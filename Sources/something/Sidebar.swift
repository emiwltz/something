// The sidebar: New Space first, selected on the blank page; the spaces in the library's order (one click opens one),
// with an italic "New Space" on top while the assistant makes one; and Templates pinned at the bottom. A page whose
// declaration does not read is listed too, in secondary color: "not a space yet". A space the assistant made while
// the person was elsewhere has a dot, and each space the eyes of its own assistant, which `eyes` gives (W3 adds the
// ring, the folded groups and the preference). Each space has Show in Finder, Export… and Move to Trash… in its context
// menu. Its rows are drawn here, not by a List: the mockup's 25-point rows and the identity's quiet selection, by day
// and by night, which a sidebar List's own highlight would cover; ↑ and ↓ move through them.
import SwiftUI

struct SidebarView: View {
    @Bindable var library: Library
    let assistant: AssistantModel
    /// The state of the space of that name's assistant, read from its own conversation.
    let eyes: (String) -> Sign.State

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    nav(on: library.selection == .newSpace && !assistant.building, key: "new", label: "New Space", open: newSpace) {
                        // The identity's ink, never the system's accent: a rounded square of ink with its plus.
                        Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(Look.Token.actfg.ui)
                            .frame(width: 20, height: 20).background(Look.Token.act.ui, in: RoundedRectangle(cornerRadius: 6)).padding(.leading, -2)
                    }
                    Text("SPACES").font(Look.font(.ui, size: 10.5, weight: .semibold).ui).kerning(0.5).foregroundStyle(Look.Token.ink3.ui)
                        .padding(EdgeInsets(top: 16, leading: 8, bottom: 4, trailing: 2)).accessibilityAddTraits(.isHeader)
                    if assistant.building {
                        row(on: library.selection == .newSpace, open: newSpace) {
                            Image(systemName: "sparkle")
                        } label: { Text("New Space").italic() }
                    }
                    if library.entries.isEmpty, !assistant.building {
                        Text("Your spaces appear here").font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink3.ui)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                    }
                    ForEach(library.order()) { entry in
                        space(entry).contextMenu {
                            Button("Show in Finder") { library.showInFinder(entry.id) }
                            Button("Export…") { library.export(entry.id) }
                            Divider()
                            Button("Move to Trash…") { library.trashing(entry) }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.never)
            nav(on: library.selection == .templates, key: "tpls", label: "Templates", open: { library.select(.templates) }) {
                Image(systemName: "square.grid.2x2").font(.system(size: 13)).foregroundStyle(Look.Token.ink2.ui)
            }
            .padding(EdgeInsets(top: 4, leading: 10, bottom: 10, trailing: 10))
        }
        .font(Look.body.font.ui)
        .foregroundStyle(Look.Token.ink.ui)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { step(-1) }
        .onKeyPress(.downArrow) { step(1) }
        // Opaque, the identity's sidebar colour: no vibrancy lets the desktop through.
        .background(Look.Token.side.ui.ignoresSafeArea())
    }

    private func newSpace() {
        library.select(.newSpace)
        assistant.focus()
    }

    /// ↑ and ↓: New Space, then each space in order.
    private func step(_ by: Int) -> KeyPress.Result {
        let all: [Library.Destination] = [.newSpace] + library.order().map { .space($0.id) }
        guard let at = all.firstIndex(of: library.selection) else { return .ignored }
        let next = min(max(at + by, 0), all.count - 1)
        if next != at { all[next] == .newSpace ? newSpace() : library.select(all[next]) }
        return .handled
    }

    /// New Space and Templates: 30 points, medium, their shortcut shown on the selected one, as the mockup's.
    private func nav(on: Bool, key: String, label: String, open: @escaping () -> Void, @ViewBuilder icon: () -> some View) -> some View {
        Button(action: open) {
            HStack(spacing: 9) {
                icon().frame(width: 16)
                Text(label).font(Look.font(.ui, size: 13, weight: .medium).ui)
                Spacer(minLength: 0)
                if on { Text(Keys.shown(key)).font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui) }
            }
            .padding(.horizontal, 8).frame(height: 30)
            .background(on ? Look.Token.sel.ui : .clear, in: RoundedRectangle(cornerRadius: Look.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A row of the list, 25 points in Emi's compact density: its symbol, its words, the selection's quiet fill.
    private func row(on: Bool, open: @escaping () -> Void, @ViewBuilder icon: () -> some View, @ViewBuilder label: () -> some View) -> some View {
        Button(action: open) {
            HStack(spacing: 9) {
                icon().font(.system(size: 12, weight: .light)).foregroundStyle(on ? Look.Token.ink.ui : Look.Token.ink3.ui).frame(width: 15)
                label()
            }
            .lineLimit(1)
            .padding(EdgeInsets(top: 0, leading: 9, bottom: 0, trailing: 6)).frame(height: Look.row)
            .background(on ? Look.Token.sel.ui : .clear, in: RoundedRectangle(cornerRadius: Look.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func space(_ entry: Library.Entry) -> some View {
        let on = library.selection == .space(entry.id)
        return row(on: on, open: { library.select(.space(entry.id)) }) {
            Image(systemName: "doc").overlay(alignment: .topTrailing) {
                if assistant.ready?.id == entry.id { Circle().fill(Look.Token.ink.ui).frame(width: 6, height: 6).offset(x: 3, y: -3) }
            }
        } label: {
            if entry.isSpace {
                Text(entry.title).fontWeight(on ? .semibold : .regular)
                Spacer(minLength: 4)
                let state = eyes(entry.id)
                Image(nsImage: Sign.miniEyes(state, template: false)).frame(width: 22).help(state.word)
                    .accessibilityLabel("Assistant: \(state.word)")
            } else {
                Text(entry.title).foregroundStyle(Look.Token.ink3.ui)
                Spacer(minLength: 4)
                Text("not a space yet").font(Look.xs.font.ui).foregroundStyle(Look.Token.ink3.ui)
            }
        }
    }
}
