// Templates: the starting points of share/templates, each one HTML file with its picture, the one `something check`
// took of it (tools/previews.sh); a live miniature would cost a web content process per card. The Templates page shows
// one card model per template: its picture, its name, a shield line of the rights it asks for, one sentence; Preview,
// Show in Finder and Use come on the card under the pointer or with the focus, and only that card has the hard shadow
// of what a person grabs. All · Agents · Notes · Play filters the cards, by categories the app keeps (a declaration has
// none: contract 1 is not changed for them). Preview is a state of the same view: the picture full width under a bar
// that says nothing runs, with Close Preview (esc) and Use This Template. Use makes the template one of the person's
// spaces (Library.use), which arrives from its card (Arrival). New Space shows the first three cards.
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
    /// The page's own colour, under its picture in Preview; read once here, not at each drawing.
    let ground: NSColor?

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
            let picture = NSImage(contentsOf: folder.appendingPathComponent("\(name).png"))
            return Template(id: name, title: declared.title, line: declared.description ?? "", rights: declared.rights,
                            follows: declared.folder == placeholder, preview: picture, ground: picture.flatMap(ground))
        }
    }

    /// The colour of `picture` near its bottom left corner, where a page's background shows.
    static func ground(_ picture: NSImage) -> NSColor? {
        guard let cg = picture.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).colorAt(x: 1, y: cg.height - 2)
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
            let joined = Words.list(verbs, "and")
            // Seeing and writing reach the agents already at work, "your agents"; starting makes new ones.
            parts.append(joined.prefix(1).uppercased() + joined.dropFirst() + (verbs.contains("starts") ? " agents" : " your agents"))
        }
        if has("store") { parts.append("Remembers") }
        return parts.isEmpty ? "Asks for nothing" : parts.joined(separator: " · ")
    }
}

/// What the Templates page shows: a filter, the card under the pointer, or one template's preview.
@Observable final class Gallery {
    /// The page's title and subtitle in the toolbar when no preview is open.
    static let page = ("Templates", "Start from one, then make it yours")

    var shown = Template.Category.all
    /// The card under the pointer, whose actions show (the focus shows them too).
    var hovered: Template.ID?
    /// The template whose preview fills the view; nil shows the cards.
    private(set) var previewing: Template? { didSet { told(heading.0, heading.1) } }
    /// Told the toolbar's title and subtitle each time the preview opens or closes.
    @ObservationIgnored let told: (String, String) -> Void
    /// Where each card was last drawn in the window, so that a test checks the columns the page shows.
    @ObservationIgnored var drawn: [Template.ID: CGRect] = [:]
    /// The template whose card's Use was just pressed, until the space it made opened: the arrival grows from its card.
    @ObservationIgnored var used: Template.ID?
    /// The toolbar's title and subtitle when no preview is open: the Templates page's, or New Space's.
    @ObservationIgnored let home: (String, String)

    init(home: (String, String) = Gallery.page, told: @escaping (String, String) -> Void = { _, _ in }) { (self.home, self.told) = (home, told) }

    /// The templates of `templates` the filter keeps, in their order.
    func cards(_ templates: [Template]) -> [Template] {
        shown == .all ? templates : templates.filter { $0.category == shown }
    }

    func preview(_ template: Template) { (previewing, hovered) = (template, nil) }

    func close() { if previewing != nil { previewing = nil } }

    /// The toolbar's title and subtitle in this state.
    var heading: (String, String) {
        previewing.map { ($0.title, "Template preview") } ?? home
    }
}

struct GalleryView: View {
    let library: Library, model: Gallery

    /// The columns of cards in `width`: three, two in a narrow window, one when even two would be cramped.
    static func columns(_ width: CGFloat) -> Int { width >= 650 ? 3 : width >= 380 ? 2 : 1 }

    var body: some View {
        Group {
            if let template = model.previewing { preview(template) } else { page }
        }
        .background(Look.Token.bg.ui)
    }

    // MARK: The cards

    private var page: some View {
        GeometryReader { window in
            ScrollView {
                let width = max(0, min(1010, window.size.width - 80)), cards = model.cards(library.templates), n = Self.columns(width)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text("Templates").font(Look.font(.title, size: 32, weight: .semibold).ui).kerning(-0.9)
                            .foregroundStyle(Look.Token.ink.ui).accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 10)
                        filters
                    }
                    .padding(.bottom, 6)
                    Text("Finished spaces to start from. Use one and you get your own copy to change; its assistant comes with it.")
                        .font(Look.font(.ui, size: 13.5).ui).foregroundStyle(Look.Token.ink2.ui)
                        .fixedSize(horizontal: false, vertical: true).padding(.bottom, 24)
                    TemplateGrid(cards: cards, columns: n, library: library, model: model)
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
                    Text(category.rawValue).font(Look.font(.ui, size: 12, weight: .medium).ui)
                        .foregroundStyle((on ? Look.Token.ink : .ink2).ui)
                        .padding(.horizontal, 11).frame(height: 24)
                        .background {
                            if on {
                                shape.fill(Look.Token.bg2.ui).shadow(color: .black.opacity(0.06), radius: 1, y: 1)
                                    .overlay(shape.strokeBorder(Look.Token.line.ui))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Look.Token.sunk.ui))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Look.Token.line.ui))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show")
    }

    // MARK: The preview

    private func preview(_ template: Template) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "eye").font(.system(size: 13)).frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Look.Token.sunk.ui))
                    .foregroundStyle(Look.Token.ink.ui)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Preview of \(template.title)").font(Look.font(.ui, size: 13, weight: .semibold).ui).foregroundStyle(Look.Token.ink.ui)
                    Text("A picture of the page. Its assistant starts when you use it.").font(Look.font(.ui, size: 11.5).ui)
                        .foregroundStyle(Look.Token.ink3.ui)
                }
                Spacer(minLength: 8)
                Button { model.close() } label: {
                    HStack(spacing: 7) { Text("Close Preview"); Text("esc").font(Look.font(.ui, size: 10).ui).opacity(0.6) }
                }
                .buttonStyle(Secondary())
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close Preview")
                Button("Use This Template") { library.use(template) }.buttonStyle(Primary(height: 30, padding: 13))
            }
            .font(Look.font(.ui, size: 12.5, weight: .semibold).ui)
            .padding(EdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 12))
            .background(Look.Token.bg2.ui)
            .overlay(alignment: .bottom) { Look.Token.line2.ui.frame(height: 1) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Template preview")
            // The picture full width from the top; under it, the page's own colour, so that it reads as one page.
            ScrollView {
                if let picture = template.preview {
                    Image(nsImage: picture).resizable().aspectRatio(contentMode: .fit).accessibilityLabel("A picture of \(template.title)")
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(nsColor: template.ground ?? Look.Token.bg.color))
        }
    }
}

/// The templates in rows of `columns`, 20 points apart: the Templates page's and New Space's.
struct TemplateGrid: View {
    let cards: [Template], columns: Int, library: Library, model: Gallery

    var body: some View {
        let n = max(1, columns)
        Grid(horizontalSpacing: 20, verticalSpacing: 20) {
            ForEach(Array(stride(from: 0, to: cards.count, by: n)), id: \.self) { start in
                GridRow(alignment: .top) {
                    ForEach(cards[start ..< min(start + n, cards.count)]) { TemplateCard(template: $0, library: library, model: model) }
                    // A short last row keeps its cards at the width of the others.
                    ForEach(0 ..< n - min(n, cards.count - start), id: \.self) { _ in Color.clear.gridCellUnsizedAxes(.vertical) }
                }
            }
        }
    }
}

/// One template's card: picture, name, the shield line, one sentence; Preview, Show in Finder and Use on its picture
/// under the pointer or with the focus.
struct TemplateCard: View {
    let template: Template, library: Library, model: Gallery
    @FocusState private var focused: Bool

    var body: some View {
        let lifted = model.hovered == template.id || focused
        return VStack(alignment: .leading, spacing: 4) {
            Button { model.preview(template) } label: { picture }
                .buttonStyle(.plain)
                .focused($focused)
                .accessibilityLabel("Preview \(template.title)")
                .overlay(alignment: .bottomTrailing) {
                    actions.padding(8).opacity(lifted ? 1 : 0).offset(y: lifted ? 0 : 4).allowsHitTesting(lifted)
                }
                .padding(.bottom, 7)
            Group {
                Text(template.title).font(Look.font(.ui, size: 13.5, weight: .semibold).ui).foregroundStyle(Look.Token.ink.ui)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "checkmark.shield").font(.system(size: 10.5)).foregroundStyle(Look.Token.ink3.ui)
                    // Every right it asks for, wrapped rather than cut: a right never hides behind an ellipsis.
                    Text(template.needs).font(Look.font(.ui, size: 11.5).ui).foregroundStyle(Look.Token.ink2.ui)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                Text(template.line).font(Look.font(.ui, size: 12).ui).lineSpacing(3.5).foregroundStyle(Look.Token.ink3.ui)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
            }
            .padding(.horizontal, 5)
        }
        .padding(EdgeInsets(top: 8, leading: 8, bottom: 13, trailing: 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Grabbed(lifted: lifted, radius: 12))
        .offset(x: lifted ? -1 : 0, y: lifted ? -1 : 0)
        .animation(Look.out.animation(Look.duration(0.22, Look.motion(library.preferences.motion))), value: lifted)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.drawn[template.id] = $0 }
        .onHover { inside in
            if inside { model.hovered = template.id } else if model.hovered == template.id { model.hovered = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(template.title)
    }

    /// The template's picture at 16:9, its top kept and the rest cut, rounded with a hairline inside.
    private var picture: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return Look.Token.sunk.ui
            .aspectRatio(16 / 9, contentMode: .fit)
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

    /// Preview, Show in Finder and Use, on glass at the picture's corner.
    private var actions: some View {
        HStack(spacing: 5) {
            Button { model.preview(template) } label: {
                HStack(spacing: 5) { Image(systemName: "eye"); Text("Preview") }.padding(.horizontal, 10).frame(height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(Look.Token.ink.ui)
            .accessibilityLabel("Preview")
            Button { library.revealTemplate(template) } label: {
                Image(systemName: "macwindow").font(.system(size: 12)).frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(Look.Token.ink.ui)
            .help("Show in Finder").accessibilityLabel("Show \(template.title) in Finder")
            Button("Use") {
                // The opening is queued by Use; the card is forgotten after it, whether a space opened or not.
                model.used = template.id
                library.use(template)
                DispatchQueue.main.async { model.used = nil }
            }
            .buttonStyle(Primary(height: 26, padding: 10))
        }
        .font(Look.font(.ui, size: 12, weight: .semibold).ui)
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Look.Token.glass.ui)
            .shadow(color: .black.opacity(0.18), radius: 9, y: 6))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Look.Token.line2.ui))
    }
}

/// A card's surface: a hairline at rest; under the pointer or with the focus, the hard offset shadow of what a person
/// grabs, drawn as Sign.grab draws the sticker's (a ring of ink and its copy 3 points down and right).
private struct Grabbed: View {
    let lifted: Bool, radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous), ring = RoundedRectangle(cornerRadius: radius + 1.5, style: .continuous)
        let ink = Look.Token.ink.ui.opacity(scheme == .dark ? 0.88 : 1)
        ZStack {
            if lifted {
                ring.fill(ink).padding(-1.5).offset(x: 3, y: 3)
                ring.fill(ink).padding(-1.5)
            }
            shape.fill(Look.Token.bg2.ui)
            if !lifted { shape.strokeBorder(Look.Token.line.ui) }
        }
    }
}

/// The mockup's primary button: act on actfg, no shadow and no lift (Emi dislikes them there), dimmed when pressed.
struct Primary: ButtonStyle {
    var height: CGFloat = 30, padding: CGFloat = 13

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Look.Token.actfg.ui).padding(.horizontal, padding).frame(height: height)
            .background(RoundedRectangle(cornerRadius: Look.control + 1, style: .continuous).fill(Look.Token.act.ui))
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

/// The mockup's secondary button: bg2 inside a ring of line2.
struct Secondary: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Look.control + 1, style: .continuous)
        return configuration.label.foregroundStyle(Look.Token.ink.ui).padding(.horizontal, 13).frame(height: 30)
            .background(shape.fill((configuration.isPressed ? Look.Token.sunk : .bg2).ui))
            .overlay(shape.strokeBorder(Look.Token.line2.ui))
    }
}

