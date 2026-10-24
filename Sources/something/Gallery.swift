// Templates: the starting points of share/templates, each one HTML file with its picture, the one `something check`
// took of it (tools/previews.sh); a live miniature would cost a web content process per card. The Templates page shows
// one card model per template: its picture, its name, a shield line of the rights it asks for, one sentence; Preview,
// Show in Finder and Use come on the card under the pointer or with the focus, and only that card has the hard shadow
// of what a person grabs. All · Agents · Notes · Play filters the cards, by categories the app keeps (a declaration has
// none: contract 1 is not changed for them). Preview is a state of the same view: the picture full width under a bar
// that says nothing runs, with Close Preview (esc) and Use This Template. Use makes the template one of the person's
// spaces (Library.use). The blank page and the welcome show the same pictures smaller.
import SomethingAgents
import SomethingCore
import SwiftUI

struct Template: Identifiable {
    /// The templates, in the order they are shown.
    static let names = ["agents", "project", "brief", "logbook", "stack", "pet"]
    /// The folder a template declares when it follows one: Use Template writes the folder the person chose in its place.
    static let placeholder = "~/code/your-project"

    /// The Templates page's filters, in their order.
    enum Category: String, CaseIterable {
        case all = "All", agents = "Agents", notes = "Notes", play = "Play"
    }

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
                  let declared = Declaration.read(space, home: URL(fileURLWithPath: "/"), kinds: Registry.app.kinds).declaration else { return nil }
            return Template(id: name, title: declared.title, line: declared.description ?? "", rights: declared.rights,
                            follows: declared.folder == placeholder, preview: NSImage(contentsOf: folder.appendingPathComponent("\(name).png")))
        }
    }

    /// Its filter on the Templates page: what it is for, not what it may do.
    var category: Category {
        switch id {
        case "agents", "project": .agents
        case "brief", "logbook": .notes
        default: .play
        }
    }

    /// The rights it asks for, every one, in one line: "Sees and writes to your agents", "Sees your agents ·
    /// Remembers". The rights sheet asks for each when the copy first opens.
    var needs: String {
        let has = { (right: String) in rights.contains { Rights.covers([right], $0) } }
        let verbs = [("state", "sees"), ("send", "writes to"), ("launch", "starts")].filter { has($0.0) }.map(\.1)
        var parts: [String] = []
        if !verbs.isEmpty {
            let joined = verbs.count == 1 ? verbs[0] : verbs.dropLast().joined(separator: ", ") + " and " + verbs[verbs.count - 1]
            // Seeing and writing reach the agents already at work, "your agents"; starting makes new ones.
            parts.append(joined.prefix(1).uppercased() + joined.dropFirst() + (verbs.contains("starts") ? " agents" : " your agents"))
        }
        if has("store") { parts.append("Remembers") }
        return parts.isEmpty ? "Asks for nothing" : parts.joined(separator: " · ")
    }
}

/// What the Templates page shows: a filter, the card under the pointer, or one template's preview.
@Observable final class Gallery {
    var shown = Template.Category.all
    /// The card under the pointer, whose actions show (the focus shows them too).
    var hovered: Template.ID?
    /// The template whose preview fills the view; nil shows the cards.
    private(set) var previewing: Template?
    /// Told the toolbar's title and subtitle each time the preview opens or closes.
    @ObservationIgnored var told: (String, String) -> Void = { _, _ in }

    /// The templates of `templates` the filter keeps, in their order.
    func cards(_ templates: [Template]) -> [Template] {
        shown == .all ? templates : templates.filter { $0.category == shown }
    }

    func preview(_ template: Template) {
        (previewing, hovered) = (template, nil)
        told(heading.0, heading.1)
    }

    func close() {
        guard previewing != nil else { return }
        previewing = nil
        told(heading.0, heading.1)
    }

    /// The toolbar's title and subtitle in this state.
    var heading: (String, String) {
        previewing.map { ($0.title, "Template preview") } ?? ("Templates", "Start from one, then make it yours")
    }
}

struct GalleryView: View {
    let library: Library, model: Gallery
    @FocusState private var focused: Template.ID?

    init(library: Library, model: Gallery = Gallery()) {
        (self.library, self.model) = (library, model)
        model.told = { [weak library] in library?.heading($0, $1) }
    }

    /// The columns of cards in `width`: three, two in a narrow window, one when even two would be cramped.
    static func columns(_ width: CGFloat) -> Int { width >= 650 ? 3 : width >= 380 ? 2 : 1 }

    var body: some View {
        Group {
            if let template = model.previewing { preview(template) } else { page }
        }
        .background(Look.Token.bg.swiftUI)
    }

    // MARK: The cards

    private var page: some View {
        GeometryReader { window in
            ScrollView {
                let width = max(0, min(1010, window.size.width - 80)), cards = model.cards(library.templates), n = Self.columns(width)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text("Templates").font(Font(Look.font(.title, size: 32, weight: .semibold))).kerning(-0.9)
                            .foregroundStyle(Look.Token.ink.swiftUI).accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 10)
                        filters
                    }
                    .padding(.bottom, 6)
                    Text("Finished spaces to start from. Use one and you get your own copy to change; its assistant comes with it.")
                        .font(Font(Look.font(.ui, size: 13.5))).foregroundStyle(Look.Token.ink2.swiftUI)
                        .fixedSize(horizontal: false, vertical: true).padding(.bottom, 24)
                    Grid(horizontalSpacing: 20, verticalSpacing: 20) {
                        ForEach(Array(stride(from: 0, to: cards.count, by: n)), id: \.self) { start in
                            GridRow(alignment: .top) {
                                ForEach(cards[start ..< min(start + n, cards.count)]) { card($0) }
                                // A short last row keeps its cards at the width of the others.
                                ForEach(0 ..< n - min(n, cards.count - start), id: \.self) { _ in Color.clear.gridCellUnsizedAxes(.vertical) }
                            }
                        }
                    }
                }
                .frame(width: width)
                .padding(EdgeInsets(top: 36, leading: 40, bottom: 60, trailing: 40))
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// All · Agents · Notes · Play, the mockup's segmented control.
    private var filters: some View {
        HStack(spacing: 0) {
            ForEach(Template.Category.allCases, id: \.self) { category in
                let on = model.shown == category, shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
                Button { model.shown = category } label: {
                    Text(category.rawValue).font(Font(Look.font(.ui, size: 12, weight: .medium)))
                        .foregroundStyle((on ? Look.Token.ink : .ink2).swiftUI)
                        .padding(.horizontal, 11).frame(height: 24)
                        .background {
                            if on {
                                shape.fill(Look.Token.bg2.swiftUI).shadow(color: .black.opacity(0.06), radius: 1, y: 1)
                                    .overlay(shape.strokeBorder(Look.Token.line.swiftUI))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Look.Token.sunk.swiftUI))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Look.Token.line.swiftUI))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show")
    }

    /// One template's card: picture, name, the shield line, one sentence; its actions on the picture.
    private func card(_ template: Template) -> some View {
        let lifted = model.hovered == template.id || focused == template.id
        return VStack(alignment: .leading, spacing: 4) {
            Button { model.preview(template) } label: { Self.picture(template, ratio: 16 / 9, radius: 7) }
                .buttonStyle(.plain)
                .focused($focused, equals: template.id)
                .accessibilityLabel("Preview \(template.title)")
                .overlay(alignment: .bottomTrailing) {
                    actions(template).padding(8).opacity(lifted ? 1 : 0).offset(y: lifted ? 0 : 4).allowsHitTesting(lifted)
                }
                .padding(.bottom, 7)
            Group {
                Text(template.title).font(Font(Look.font(.ui, size: 13.5, weight: .semibold))).foregroundStyle(Look.Token.ink.swiftUI)
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.shield").font(.system(size: 10.5)).foregroundStyle(Look.Token.ink3.swiftUI)
                    Text(template.needs).font(Font(Look.font(.ui, size: 11.5))).foregroundStyle(Look.Token.ink2.swiftUI)
                }
                .accessibilityElement(children: .combine)
                Text(template.line).font(Font(Look.font(.ui, size: 12))).lineSpacing(3.5).foregroundStyle(Look.Token.ink3.swiftUI)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
            }
            .padding(.horizontal, 5)
        }
        .padding(EdgeInsets(top: 8, leading: 8, bottom: 13, trailing: 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Grabbed(lifted: lifted, radius: 12))
        .offset(x: lifted ? -1 : 0, y: lifted ? -1 : 0)
        .animation(.timingCurve(0.16, 1, 0.3, 1, duration: Look.duration(0.22, Look.motion(library.preferences.motion))), value: lifted)
        .onHover { inside in
            if inside { model.hovered = template.id } else if model.hovered == template.id { model.hovered = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(template.title)
    }

    /// Preview, Show in Finder and Use, on glass at the picture's corner.
    private func actions(_ template: Template) -> some View {
        HStack(spacing: 5) {
            Button { model.preview(template) } label: {
                HStack(spacing: 5) { Image(systemName: "eye"); Text("Preview") }.padding(.horizontal, 10).frame(height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(Look.Token.ink.swiftUI)
            .accessibilityLabel("Preview")
            Button { library.reveal(library.share.appendingPathComponent("templates/\(template.id).html")) } label: {
                Image(systemName: "macwindow").font(.system(size: 12)).frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(Look.Token.ink.swiftUI)
            .help("Show in Finder").accessibilityLabel("Show \(template.title) in Finder")
            Button("Use") { library.use(template) }.buttonStyle(Primary(height: 26, padding: 10))
        }
        .font(Font(Look.font(.ui, size: 12, weight: .semibold)))
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Look.Token.glass.swiftUI)
            .shadow(color: .black.opacity(0.18), radius: 9, y: 6))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Look.Token.line2.swiftUI))
    }

    /// A template's picture at `ratio`, its top kept and the rest cut, rounded with a hairline inside.
    static func picture(_ template: Template, ratio: CGFloat, radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return Look.Token.sunk.swiftUI
            .aspectRatio(ratio, contentMode: .fit)
            .overlay(alignment: .top) {
                // As wide as the box, so its top fills it and its bottom is cut.
                if let preview = template.preview, preview.size.width > 0 {
                    GeometryReader { box in
                        Image(nsImage: preview).resizable().frame(width: box.size.width, height: box.size.width * preview.size.height / preview.size.width)
                    }
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color(nsColor: Look.srgb(0x121316, 0.10))))
            .contentShape(shape)
    }

    // MARK: The preview

    private func preview(_ template: Template) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "eye").font(.system(size: 13)).frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Look.Token.sunk.swiftUI))
                    .foregroundStyle(Look.Token.ink.swiftUI)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Preview of \(template.title)").font(Font(Look.font(.ui, size: 13, weight: .semibold))).foregroundStyle(Look.Token.ink.swiftUI)
                    Text("A picture of the page. Its assistant starts when you use it.").font(Font(Look.font(.ui, size: 11.5)))
                        .foregroundStyle(Look.Token.ink3.swiftUI)
                }
                Spacer(minLength: 8)
                Button { model.close() } label: {
                    HStack(spacing: 7) { Text("Close Preview"); Text("esc").font(Font(Look.font(.ui, size: 10))).opacity(0.6) }
                }
                .buttonStyle(Secondary())
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close Preview")
                Button("Use This Template") { library.use(template) }.buttonStyle(Primary(height: 30, padding: 13))
            }
            .font(Font(Look.font(.ui, size: 12.5, weight: .semibold)))
            .padding(EdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 12))
            .background(Look.Token.bg2.swiftUI)
            .overlay(alignment: .bottom) { Look.Token.line2.swiftUI.frame(height: 1) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Template preview")
            // The picture full width from the top; under it, the page's own colour, so that it reads as one page.
            ScrollView {
                if let picture = template.preview {
                    Image(nsImage: picture).resizable().aspectRatio(contentMode: .fit).accessibilityLabel("A picture of \(template.title)")
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(nsColor: template.preview.flatMap(Self.ground) ?? Look.Token.bg.color))
        }
    }

    /// The colour of `picture` near its bottom left corner, where a page's background shows.
    static func ground(_ picture: NSImage) -> NSColor? {
        guard let cg = picture.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).colorAt(x: 1, y: cg.height - 2)
    }
}

/// A card's surface: a hairline at rest; under the pointer or with the focus, the hard offset shadow of what a person
/// grabs, drawn as Sign.grab draws the sticker's (a ring of ink and its copy 3 points down and right).
private struct Grabbed: View {
    let lifted: Bool, radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous), ring = RoundedRectangle(cornerRadius: radius + 1.5, style: .continuous)
        let ink = Look.Token.ink.swiftUI.opacity(scheme == .dark ? 0.88 : 1)
        ZStack {
            if lifted {
                ring.fill(ink).padding(-1.5).offset(x: 3, y: 3)
                ring.fill(ink).padding(-1.5)
            }
            shape.fill(Look.Token.bg2.swiftUI)
            if !lifted { shape.strokeBorder(Look.Token.line.swiftUI) }
        }
    }
}

/// The mockup's primary button: act on actfg, no shadow and no lift (Emi dislikes them there), dimmed when pressed.
struct Primary: ButtonStyle {
    var height: CGFloat = 30, padding: CGFloat = 13

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Look.Token.actfg.swiftUI).padding(.horizontal, padding).frame(height: height)
            .background(RoundedRectangle(cornerRadius: Look.control + 1, style: .continuous).fill(Look.Token.act.swiftUI))
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

/// The mockup's secondary button: bg2 inside a ring of line2.
struct Secondary: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Look.control + 1, style: .continuous)
        return configuration.label.foregroundStyle(Look.Token.ink.swiftUI).padding(.horizontal, 13).frame(height: 30)
            .background(shape.fill((configuration.isPressed ? Look.Token.sunk : .bg2).swiftUI))
            .overlay(shape.strokeBorder(Look.Token.line2.swiftUI))
    }
}

extension Look.Token {
    /// The token as a SwiftUI colour, resolved by the appearance it is drawn in.
    var swiftUI: Color { Color(nsColor: color) }
}

/// A template's picture at 16:10, rounded, with a hairline; a button that uses the template when `use` is given.
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
