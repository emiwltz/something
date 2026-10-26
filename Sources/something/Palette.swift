// ⌘P, go: a card on a scrim in the window layer (ScrimCard, WindowLayer.swift), the field "Go to a space, or ask its
// assistant…" and, under it, what Return can reach. Nothing typed: three recent spaces, then the others, each with its
// group, its assistant's state in words and in eyes, the open one marked; the actions of Keys that can act now (one
// that cannot is left out, not greyed: the palette lists what Return can do); the templates. Typed words keep the rows
// whose name starts with them, then those with a word that does, then those that contain them, section by section.
// ↑ ↓ and the pointer move, Return or a click opens, Esc, a click on the scrim or ⌘P again closes; the footer says
// what Return does. The recent spaces are the preferences' (Preferences.opened), which opening one updates.
import AppKit
import SwiftUI

/// What the palette lists, what is typed and where the keys rest.
@MainActor @Observable final class PaletteModel {
    struct Row: Identifiable {
        enum Section: String { case recent = "Recent", spaces = "Spaces", actions = "Actions", templates = "Templates" }
        enum Kind: Equatable { case space(Sign.State, open: Bool), action(key: String), template }
        /// "space:brief", "action:new", "template:pet": its kind, then the space, command or template it opens.
        let id: String
        let section: Section, title: String, sub: String?, symbol: String, kind: Kind
        var target: String { String(id.drop { $0 != ":" }.dropFirst()) }
    }

    /// The actions ⌘P lists, by Keys' id, with their symbols, in the mockup's order.
    static let actions = [("new", "plus"), ("ask", "bubble.left"), ("convo", "text.bubble"), ("tpls", "square.grid.2x2"),
                          ("full", "arrow.up.left.and.arrow.down.right"), ("sleep", "moon"), ("settings", "gearshape"),
                          ("keys", "keyboard"), ("lookAgain", "arrow.clockwise")]

    @ObservationIgnored let library: Library
    /// The state of the space of that name's assistant.
    @ObservationIgnored let eyes: (String) -> Sign.State
    /// Whether Keys' command of that id can act now.
    @ObservationIgnored let enabled: (String) -> Bool
    /// Whether the window is in full screen.
    @ObservationIgnored let full: () -> Bool
    /// What Return or a click does with a row, once the palette closed.
    @ObservationIgnored var chose: (Row) -> Void = { _ in }
    @ObservationIgnored var close: () -> Void = {}

    /// What is typed; new words put the keys back on the first row, which the list scrolls back to.
    var query = "" { didSet { if query != oldValue { selected = 0; key(rows.first?.id) } } }
    /// The index of the row the keys rest on.
    var selected = 0
    /// The row the keys last moved to, or the first after new words, which the list scrolls into view; the pointer's
    /// needs no scrolling.
    private(set) var keyed: String?
    /// Counts the keys' moves and the new words: landing again on the row last keyed still scrolls it into view.
    private(set) var keyings = 0
    /// Where the pointer last was in the window: a row that scrolls under a pointer that did not move takes nothing
    /// from the keys, as the mockup's pointermove does.
    @ObservationIgnored private var pointer: CGPoint?

    init(library: Library, eyes: @escaping (String) -> Sign.State, enabled: @escaping (String) -> Bool, full: @escaping () -> Bool = { false }) {
        (self.library, self.eyes, self.enabled, self.full) = (library, eyes, enabled, full)
    }

    /// The rows for what is typed, in their sections' order.
    var rows: [Row] {
        let open = library.selection.space, spaces = library.order().filter(\.isSpace)
        func space(_ entry: Library.Entry, _ section: Row.Section) -> Row {
            Row(id: "space:" + entry.id, section: section, title: entry.title, sub: library.preferences.group(of: entry.id),
                symbol: Template.symbol(of: entry.id), kind: .space(eyes(entry.id), open: entry.id == open))
        }
        let actions = Self.actions.filter { enabled($0.0) }.compactMap { id, symbol in
            Keys.command(id).map { Row(id: "action:" + id, section: .actions, title: words(id, $0), sub: nil, symbol: symbol, kind: .action(key: $0.shown)) }
        }
        let templates = library.templates.map { Row(id: "template:" + $0.id, section: .templates, title: $0.title, sub: $0.line, symbol: "square.grid.2x2", kind: .template) }
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else {
            let recent = library.preferences.recents.filter { $0 != open }.compactMap { name in spaces.first { $0.id == name } }.prefix(3)
            let rest = spaces.filter { entry in !recent.contains { $0.id == entry.id } }
            return recent.map { space($0, .recent) } + rest.map { space($0, .spaces) } + actions + templates
        }
        let sections: [Row.Section] = [.spaces, .actions, .templates]
        return (spaces.map { space($0, .spaces) } + actions + templates).enumerated()
            .compactMap { index, row in Self.score(row, query).map { (row, sections.firstIndex(of: row.section) ?? 0, $0, index) } }
            .sorted { ($0.1, $0.2, $0.3) < ($1.1, $1.2, $1.3) }.map(\.0)
    }

    /// How well `row` answers `query` (lowercased): 0 when its name starts with it, 1 when one of its words does, 2
    /// when its name or the words under it contain it; nil when it does not answer.
    static func score(_ row: Row, _ query: String) -> Int? {
        let title = row.title.lowercased()
        if title.hasPrefix(query) { return 0 }
        if title.split(whereSeparator: \.isWhitespace).contains(where: { $0.hasPrefix(query) }) { return 1 }
        return (title + " " + (row.sub ?? "").lowercased()).contains(query) ? 2 : nil
    }

    /// An action's words in the palette: the open space's assistant named, full screen as it would change, no "…".
    func words(_ id: String, _ command: Keys.Command) -> String {
        switch id {
        case "ask": "Talk to \(Words.possessive(library.entry(library.selection.space)?.title ?? "this space")) Assistant"
        case "full": full() ? "Exit Full Screen" : "Enter Full Screen"
        default: command.title.replacingOccurrences(of: "…", with: "")
        }
    }

    /// ↑ (-1) or ↓ (1): the keys move to the next row, round from the last to the first.
    func move(_ by: Int) {
        let rows = rows
        guard !rows.isEmpty else { return }
        selected = ((selected + by) % rows.count + rows.count) % rows.count
        key(rows[selected].id)
    }

    private func key(_ id: String?) { (keyed, keyings) = (id, keyings + 1) }

    /// The pointer at `point`, in the window, over the row at `index`: the keys move to it only if the pointer moved.
    func hover(_ index: Int, at point: CGPoint) {
        guard point != pointer else { return }
        pointer = point
        if selected != index { selected = index }
    }

    /// Return, or a click on the row at `index`: the palette closes, then the row opens. Nothing when there is no row.
    func pick(_ index: Int? = nil) {
        let rows = rows, index = index ?? selected
        guard rows.indices.contains(index) else { return }
        close()
        chose(rows[index])
    }

    /// What the footer says Return does.
    var enter: String { "Open" }
}

/// The palette over the window: the card and its field, which has the keys while it is up.
final class Palette: ScrimCard, NSTextFieldDelegate {
    let model: PaletteModel
    let field: NSTextField
    /// The card's distance from the window's top: 6 points less while it arrives, as the mockup's palin does.
    private var drop: NSLayoutConstraint?

    private init(_ model: PaletteModel) {
        let field = NSTextField()
        (self.model, self.field) = (model, field)
        let host = NSHostingView(rootView: PaletteCard(model: model, field: field))
        super.init(card: host, radius: PaletteCard.radius, label: "Go to or ask")
        (field.isBordered, field.drawsBackground, field.focusRingType, field.delegate) = (false, false, .none, self)
        field.font = Look.font(.ui, size: 16, weight: .medium)
        field.textColor = Look.Token.ink.color
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.placeholderAttributedString = NSAttributedString(string: "Go to a space, or ask its assistant…",
                                                               attributes: [.font: field.font as Any, .foregroundColor: Look.Token.ink3.color])
        field.setAccessibilityLabel("Go to or ask")
        model.close = { [weak self] in self?.close() }
        let drop = host.topAnchor.constraint(equalTo: topAnchor, constant: PaletteCard.top)
        NSLayoutConstraint.activate([drop, host.centerXAnchor.constraint(equalTo: centerXAnchor)])
        self.drop = drop
    }

    required init?(coder: NSCoder) { nil }

    /// Shows the palette of `model` over all of `layer`, the keys in its field, or closes it when it is up, as ⌘P
    /// does; returns the palette when it shows. It fades in and comes down 6 points under Calm `motion`.
    @discardableResult
    static func toggle(in layer: WindowLayer, model: PaletteModel, motion: Look.Motion = .calm) -> Palette? {
        if close(in: layer) { return nil }
        let palette = Palette(model)
        palette.present(in: layer) { palette.field }
        let calm = Look.duration(0.22, Look.motion(motion))
        guard calm > 0, let drop = palette.drop else { return palette }
        (palette.alphaValue, drop.constant) = (0, PaletteCard.top - 6)
        layer.layoutSubtreeIfNeeded()
        Look.animate(calm, Look.out, settle: [palette]) {
            palette.animator().alphaValue = 1
            drop.animator().constant = PaletteCard.top
        }
        return palette
    }

    func controlTextDidChange(_ notification: Notification) { model.query = field.stringValue }

    /// The field's keys: ↑ ↓ move, Return opens, Esc closes; any other is the field's.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): model.move(1)
        case #selector(NSResponder.moveUp(_:)): model.move(-1)
        case #selector(NSResponder.insertNewline(_:)): model.pick()
        case #selector(NSResponder.cancelOperation(_:)): close()
        default: return false
        }
        return true
    }
}

/// The card: the field, the sections of rows (or what says nothing answers), and the footer.
struct PaletteCard: View {
    static let radius: CGFloat = 14, top: CGFloat = 84, width: CGFloat = 640
    /// The list's height at most, its sections' headers' and its rows' heights (the compact row and 11).
    static let list: CGFloat = 404, header: CGFloat = 29, row: CGFloat = Look.row + 11
    @Bindable var model: PaletteModel
    let field: NSTextField
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let rows = model.rows
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(Look.Token.ink3.ui)
                Hosted(view: field).frame(height: 22)
                Keycap(words: "esc")
            }
            .padding(.horizontal, 16).frame(height: 56)
            .overlay(alignment: .bottom) { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }
            if rows.isEmpty { nothing } else { list(rows) }
            footer
        }
        .frame(width: Self.width)
        .background(Look.Token.bg2.ui)
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
    }

    /// The rows under their sections' headers, scrolled to keep the keys' row in view.
    private func list(_ rows: [PaletteModel.Row]) -> some View {
        let headed = rows.indices.filter { $0 == 0 || rows[$0 - 1].section != rows[$0].section }
        let tall = 12 + CGFloat(headed.count) * Self.header + CGFloat(rows.count) * Self.row
        return ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows.indices, id: \.self) { index in
                        if headed.contains(index) {
                            Text(rows[index].section.rawValue.uppercased()).font(Look.font(.ui, size: 10.5, weight: .semibold).ui).kerning(0.525)
                                .foregroundStyle(Look.Token.ink3.ui).accessibilityAddTraits(.isHeader)
                                .padding(EdgeInsets(top: 0, leading: 10, bottom: 4, trailing: 10))
                                .frame(maxWidth: .infinity, minHeight: Self.header, maxHeight: Self.header, alignment: .bottomLeading)
                        }
                        row(rows[index], at: index)
                    }
                }
                .padding(6)
            }
            .scrollIndicators(.never)
            .frame(height: min(tall, Self.list))
            .onChange(of: model.keyings) { if let id = model.keyed { scroller.scrollTo(id) } }
        }
    }

    private func row(_ row: PaletteModel.Row, at index: Int) -> some View {
        let on = index == model.selected
        return HStack(spacing: 11) {
            Image(systemName: row.symbol).font(.system(size: 12.5)).foregroundStyle(Look.Token.ink2.ui).frame(width: 26, height: 26)
                .background(on ? Look.Token.bg2.ui : Look.Token.hover.ui, in: RoundedRectangle(cornerRadius: 7))
                .overlay { if on { RoundedRectangle(cornerRadius: 7).strokeBorder(Look.Token.line.ui, lineWidth: 1) } }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.title).font(Look.font(.ui, size: 13.5).ui).foregroundStyle(Look.Token.ink.ui)
                if let sub = row.sub, !sub.isEmpty { Text(sub).font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink3.ui) }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            trail(row.kind)
        }
        .padding(.horizontal, 10).frame(height: Self.row)
        .background(on ? Look.Token.sel.ui : .clear, in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .global) { if case .active(let point) = $0 { model.hover(index, at: point) } }
        .onTapGesture { model.pick(index) }
        .id(row.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.label(row))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.pick(index) }
    }

    /// What VoiceOver says of a row: its name, its group or line, and a space's state, open or not.
    static func label(_ row: PaletteModel.Row) -> String {
        var parts = [row.title] + [row.sub].compactMap { $0 }
        if case .space(let state, let open) = row.kind { parts += (open ? ["open"] : []) + [state.word] }
        return parts.joined(separator: ", ")
    }

    /// The right of a row: a space's "Open", its state and its eyes; an action's key.
    @ViewBuilder private func trail(_ kind: PaletteModel.Row.Kind) -> some View {
        switch kind {
        case .space(let state, let open):
            HStack(spacing: 8) {
                if open {
                    Text("Open").font(Look.font(.ui, size: 10.5, weight: .semibold).ui).foregroundStyle(Look.Token.ink2.ui)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Look.Token.line2.ui, lineWidth: 1))
                }
                Text(state.word).font(Look.font(.ui, size: 11.5, weight: state == .wait ? .medium : .regular).ui)
                    .foregroundStyle(state == .wait ? Look.Token.ink.ui : Look.Token.ink3.ui)
                Image(nsImage: drawn(Sign.miniEyes(state, template: false))).frame(width: 18)
            }
        case .action(let key): if !key.isEmpty { Keycap(words: key) }
        case .template: EmptyView()
        }
    }

    /// `image`, which resolves its colours where it is drawn, drawn in the card's appearance: SwiftUI draws an image
    /// in the app's, which Settings › Interface may have made the other one.
    private func drawn(_ image: NSImage) -> NSImage {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        return NSImage(size: image.size, flipped: false) { rect in
            if let appearance { appearance.performAsCurrentDrawingAppearance { image.draw(in: rect) } } else { image.draw(in: rect) }
            return true
        }
    }

    /// Nothing answers what is typed.
    private var nothing: some View {
        VStack(spacing: 6) {
            Image(nsImage: drawn(Sign.image(.listen, side: 34))).accessibilityHidden(true)
            Text("Nothing called “\(model.query.trimmingCharacters(in: .whitespaces))”").font(Look.font(.ui, size: 13, weight: .semibold).ui)
                .foregroundStyle(Look.Token.ink.ui).padding(.top, 6)
            Text("Type a few words to ask an assistant, or press \(Keys.shown("new")) to make it.").font(Look.font(.ui, size: 13).ui)
                .foregroundStyle(Look.Token.ink3.ui)
        }
        .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(EdgeInsets(top: 34, leading: 12, bottom: 30, trailing: 12))
    }

    /// The sign and the wordmark, then the keys and what they do.
    private var footer: some View {
        HStack(spacing: 16) {
            HStack(spacing: 7) {
                Image(nsImage: drawn(Sign.image(.listen, side: 15))).accessibilityHidden(true)
                Text("something").font(Look.font(.ui, size: 11.5, weight: .medium).ui).foregroundStyle(Look.Token.ink2.ui)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) { Keycap(words: "↑", boxed: true); Keycap(words: "↓", boxed: true); Text("Move") }
            HStack(spacing: 4) { Keycap(words: "↵", boxed: true); Text(model.enter) }
            HStack(spacing: 4) { Keycap(words: "esc", boxed: true); Text("Close") }
        }
        .font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui)
        .padding(.horizontal, 14).frame(height: 40)
        .background(Look.Token.bg.ui)
        .overlay(alignment: .top) { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }
    }
}

/// A key as the mockup's kbd draws it: on the hover tint, or `boxed` on the card's white with a hairline.
struct Keycap: View {
    let words: String
    var boxed = false

    var body: some View {
        Text(words).font(Look.font(.ui, size: 10.5, weight: .medium).ui).kerning(0.21).foregroundStyle(Look.Token.ink3.ui)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(boxed ? Look.Token.bg2.ui : Look.Token.hover.ui, in: RoundedRectangle(cornerRadius: 5))
            .overlay { if boxed { RoundedRectangle(cornerRadius: 5).strokeBorder(Look.Token.line.ui, lineWidth: 1) } }
    }
}

/// An AppKit view made elsewhere, placed in a SwiftUI layout as it is.
private struct Hosted: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ view: NSView, context: Context) {}
}

extension App {
    /// ⌘P: shows the palette over the window, or closes it.
    @MainActor @objc func showPalette(_ sender: Any?) {
        shell.front()
        let model = PaletteModel(library: library, eyes: { [unowned self] in assistant.eyes(of: $0) }, enabled: { [unowned self] in Keys.enabled($0, situation) },
                                 full: { [unowned self] in shell.window.styleMask.contains(.fullScreen) })
        model.chose = { [weak self] row in self?.go(row) }
        Palette.toggle(in: shell.layer, model: model, motion: library.preferences.motion)
    }

    /// Opens what a row of the palette names, the window brought to the front for a space.
    @MainActor func go(_ row: PaletteModel.Row) {
        row.open(in: library, send: Keys.send)
        if case .space = row.kind { front() }
    }
}

extension PaletteModel.Row {
    /// Opens what the row names in `library`: selects its space, gives its command's id to `send`, or opens the
    /// Templates page asked for its template's preview, which the page opens as it draws (GalleryView).
    @MainActor func open(in library: Library, send: (String) -> Void) {
        switch kind {
        case .space: library.select(.space(target))
        case .action: send(target)
        case .template:
            library.asked = target
            library.select(.templates)
        }
    }
}
