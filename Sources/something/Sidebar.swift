// The sidebar: New Space first, the spaces sorted by title (one click opens one), and Templates pinned at the
// bottom. A page whose declaration does not read is listed too, in secondary color: "not a space yet". Each space has
// Show in Finder, Export… and Move to Trash… in its context menu.
import SwiftUI

struct SidebarView: View {
    @Bindable var library: Library

    var body: some View {
        List(selection: Binding(get: { library.selection }, set: { library.select($0) })) {
            // New Space and Templates come with the blank page and the gallery; until then they are shown, not offered.
            HStack {
                Label("New Space", systemImage: "plus.circle.fill")
                Spacer()
                Text("⌘N").foregroundStyle(.tertiary)
            }
            .foregroundStyle(.tertiary)
            .disabled(true)
            Section("Spaces") {
                if library.entries.isEmpty {
                    Text("No spaces yet.").foregroundStyle(.secondary)
                }
                ForEach(library.entries) { entry in
                    row(entry).tag(entry.id).contextMenu {
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
            Label("Templates", systemImage: "square.grid.2x2")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .foregroundStyle(.tertiary)
                .disabled(true)
        }
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
        }
        .lineLimit(1)
    }
}
