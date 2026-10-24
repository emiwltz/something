// The sidebar: New Space first, selected on the blank page; the spaces in the library's order (one click opens one),
// with an italic "New Space" on top while the assistant makes one; and Templates pinned at the bottom. A page whose
// declaration does not read is listed too, in secondary color: "not a space yet". A space the assistant made while
// the person was elsewhere has a dot. Each space has Show in Finder, Export… and Move to Trash… in its context menu.
import SwiftUI

struct SidebarView: View {
    @Bindable var library: Library
    let assistant: AssistantModel
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
            HStack {
                Label { Text("New Space") } icon: { Image(systemName: "plus.circle.fill").foregroundStyle(.tint) }
                Spacer()
                Text(Keys.shown("new")).foregroundStyle(.tertiary)
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
                Label { Text("Templates") } icon: { Image(systemName: "square.grid.2x2").foregroundStyle(.tint) }
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
        .background(Color(nsColor: Look.Token.side.color).ignoresSafeArea())
    }

    private func row(_ entry: Library.Entry) -> some View {
        Label {
            if entry.isSpace {
                Text(entry.title)
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
