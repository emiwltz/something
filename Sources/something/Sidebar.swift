// The sidebar: New Space first, selected on the blank page; the spaces sorted by title (one click opens one), with
// an italic "New Space" on top while the assistant makes one; and Templates pinned at the bottom. A page whose
// declaration does not read is listed too, in secondary color: "not a space yet". A space the assistant made while
// the person was elsewhere has a dot. Each space has Show in Finder, Export… and Move to Trash… in its context menu.
import SwiftUI

struct SidebarView: View {
    @Bindable var library: Library
    let assistant: AssistantModel
    /// The tags of the two rows that are not spaces; a space's name never starts with "+".
    static let new = "+new", pending = "+pending"

    var body: some View {
        let pending = assistant.building && library.selection == nil
        List(selection: Binding(get: { library.selection ?? (pending ? SidebarView.pending : SidebarView.new) }, set: { tag in
            if tag == SidebarView.new || tag == SidebarView.pending {
                library.select(nil)
                assistant.focus()
            } else {
                library.select(tag)
            }
        })) {
            HStack {
                Label { Text("New Space") } icon: { Image(systemName: "plus.circle.fill").foregroundStyle(.tint) }
                Spacer()
                Text("⌘N").foregroundStyle(.tertiary)
            }
            .tag(SidebarView.new)
            Section("Spaces") {
                if pending {
                    Label("New Space", systemImage: "sparkle").italic().tag(SidebarView.pending)
                }
                if library.entries.isEmpty, !pending {
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
                .overlay(alignment: .topTrailing) {
                    if assistant.ready?.id == entry.id { Circle().fill(.tint).frame(width: 7, height: 7).offset(x: 3, y: -3) }
                }
        }
        .lineLimit(1)
    }
}
