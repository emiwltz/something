// Templates (plan B.5): the starting points of share/templates, each one HTML file with its preview, the picture
// `something check` took of it (tools/previews.sh). The gallery shows a card per template: its preview, its title and
// description, what it may do in plain words, and Use Template, which makes it one of the person's spaces (Library.use).
// The blank page and the welcome show the same previews smaller.
import SomethingCore
import SwiftUI

struct Template: Identifiable {
    /// The templates, in the order they are shown.
    static let names = ["agents", "project", "brief", "logbook", "stack", "pet"]
    /// The folder a template declares when it follows one: Use Template writes the folder the person chose in its place.
    static let placeholder = "~/code/your-project"

    let id: String, title: String, line: String, rights: [String], follows: Bool, preview: NSImage?

    /// The names of the templates `share`/templates holds, in their order.
    static func present(_ share: URL) -> [String] {
        names.filter { FileManager.default.fileExists(atPath: share.appendingPathComponent("templates/\($0).html").path) }
    }

    /// The templates in `share`/templates, in their order; one whose declaration does not read is left out.
    static func all(_ share: URL) -> [Template] {
        let folder = share.appendingPathComponent("templates")
        return present(share).compactMap { name in
            guard let space = Spaces(root: folder).named(name),
                  let declared = Declaration.read(space, home: URL(fileURLWithPath: "/")).declaration else { return nil }
            return Template(id: name, title: declared.title, line: declared.description ?? "", rights: declared.rights,
                            follows: declared.folder == placeholder, preview: NSImage(contentsOf: folder.appendingPathComponent("\(name).png")))
        }
    }

    /// What the template may do, in the words of the cards.
    var tags: [String] {
        [("state", "Sees your agents"), ("send", "Writes to your agents"), ("launch", "Starts agents"), ("store", "Remembers")]
            .filter { right in rights.contains { Rights.covers([right.0], $0) } }.map(\.1)
    }
}

struct GalleryView: View {
    let library: Library

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 28, alignment: .top)], spacing: 32) {
                ForEach(library.templates) { card($0) }
            }
            // Room under the last row for the assistant floating over it.
            .padding(EdgeInsets(top: 28, leading: 32, bottom: 110, trailing: 32))
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func card(_ template: Template) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Preview(template: template).padding(.bottom, 6)
            Text(template.title).font(.system(size: 14, weight: .semibold))
            Text(template.line).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            // A line breaks between two tags, never inside one.
            Text(template.tags.map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }.joined(separator: " · ")).font(.system(size: 11.5)).foregroundStyle(.tertiary)
            Button("Use Template") { library.use(template) }.padding(.top, 6)
        }
        .font(.system(size: 12.5))
    }
}

/// A template's preview at 16:10, rounded, with a hairline; a button that uses the template when `use` is given.
struct Preview: View {
    let template: Template
    var use: ((Template) -> Void)?

    var body: some View {
        if let use {
            Button { use(template) } label: { picture }.buttonStyle(.plain).help("Use Template: \(template.title)")
        } else {
            picture
        }
    }

    private var picture: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return Group {
            if let preview = template.preview { Image(nsImage: preview).resizable().aspectRatio(contentMode: .fill) } else { Color.secondary.opacity(0.1) }
        }
        .aspectRatio(1.6, contentMode: .fit)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .accessibilityLabel(template.title)
    }
}
