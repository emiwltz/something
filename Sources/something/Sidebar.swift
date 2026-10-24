// The sidebar: New Space first, selected on the blank page; the spaces in the library's order (one click opens one),
// with an italic "New Space" on top while the assistant makes one; and Templates pinned at the bottom. A page whose
// declaration does not read is listed too, in secondary color: "not a space yet". A space the assistant made while
// the person was elsewhere has a dot, and each space the eyes of its own assistant, which `eyes` gives (W3 adds the
// ring, the folded groups and the preference). Each space has Show in Finder, Export… and Move to Trash… in its context
// menu.
import SwiftUI

struct SidebarView: View {
    @Bindable var library: Library
    let assistant: AssistantModel
    /// The state of the space of that name's assistant, read from its own conversation.
    let eyes: (String) -> Sign.State
    /// A row of the list: a destination, or the space being made, which is where New Space is while it is made.
    enum Row: Hashable { case to(Library.Destination), pending }

    var body: some View {
        List(selection: Binding<Row?>(get: {
            switch library.selection {
            case .newSpace: assistant.building ? .pending : .to(.newSpace)
            case .space: .to(library.selection)
            case .templates, .tour: nil
            }
        }, set: { row in
            if row == .pending || row == .to(.newSpace) {
                library.select(.newSpace)
                assistant.focus()
            } else if case .to(let destination)? = row {
                library.select(destination)
            }
        })) {
            // The identity's ink, never the system's accent: a rounded square of ink with its plus, as the mockup's.
            Label {
                Text("New Space")
            } icon: {
                Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(Look.Token.actfg.ui)
                    .frame(width: 20, height: 20).background(Look.Token.act.ui, in: RoundedRectangle(cornerRadius: 6))
            }
            .tag(Row.to(.newSpace))
            Section("Spaces") {
                if assistant.building {
                    Label("New Space", systemImage: "sparkle").italic().tag(Row.pending)
                }
                if library.entries.isEmpty, !assistant.building {
                    Text("No spaces yet.").foregroundStyle(.secondary)
                }
                ForEach(library.order()) { entry in
                    row(entry).tag(Row.to(.space(entry.id))).contextMenu {
                        Button("Show in Finder") { library.showInFinder(entry.id) }
                        Button("Export…") { library.export(entry.id) }
                        Divider()
                        Button("Move to Trash…") { library.trashing(entry) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button { library.select(.templates) } label: {
                Label { Text("Templates") } icon: { Image(systemName: "square.grid.2x2").foregroundStyle(Look.Token.ink2.ui) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(library.selection == .templates ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(10)
        }
        // Opaque, the identity's sidebar colour: no vibrancy lets the desktop through.
        .scrollContentBackground(.hidden)
        .background(Look.Token.side.ui.ignoresSafeArea())
    }

    private func row(_ entry: Library.Entry) -> some View {
        Label {
            if entry.isSpace {
                HStack(spacing: 4) {
                    Text(entry.title)
                    Spacer(minLength: 0)
                    let state = eyes(entry.id)
                    Image(nsImage: Sign.miniEyes(state, template: false)).frame(width: 22).help(state.word)
                        .accessibilityLabel("Assistant: \(state.word)")
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                    Text("not a space yet").font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "square.text.square")
                .overlay(alignment: .topTrailing) {
                    if assistant.ready?.id == entry.id { Circle().fill(.tint).frame(width: 7, height: 7).offset(x: 3, y: -3) }
                }
        }
        .lineLimit(1)
    }
}
