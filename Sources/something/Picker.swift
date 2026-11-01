// What the chips open, one drawn popover in the window's top layer (WindowLayer), above whatever holds the chip: the
// models with a line each, the effort as a small gauge, the foot's scope, or the programs. Popover is the floating
// part: it places itself by its chip, above the card when the chip is in it, follows its content's size, takes the keys
// while up, and leaves at Esc or at a click elsewhere, giving the focus back. It is native, like the rest of the
// window: a page can neither draw nor press it.
import AppKit
import SomethingAgents
import SomethingCore
import SwiftUI

final class Popover: NSHostingView<AnyView> {
    /// Which chip is open, for its soft fill.
    @Observable final class Open { var part: String? }
    enum Key { case up, down, left, right, enter, tab, escape }
    /// What a key does in the picker; true when it took it. Called with the popover, for Esc and Return to close it.
    typealias Keys = (Key, Popover) -> Bool

    static let open = Open()
    private(set) static weak var shown: Popover?

    private(set) weak var anchor: NSView?
    private weak var before: NSResponder?
    private var part = "", keys: Keys?, clicks: Any?
    private var placed = NSSize.zero
    /// The room the card keeps around itself for its shadow.
    static let margin: CGFloat = 10

    /// Opens the picker of the chip at `anchor`, or closes it when it is the one up. Any other picker up closes first.
    static func toggle(from anchor: NSView, part: String, keys: Keys?, @ViewBuilder content: (Popover?) -> some View) {
        let same = shown?.anchor === anchor
        shown?.close()
        guard !same, let window = anchor.window, let root = window.contentView else { return }
        // A popover is made empty, then given what closes it.
        let popover = Popover(rootView: AnyView(EmptyView()))
        popover.rootView = AnyView(content(popover))
        (popover.anchor, popover.part, popover.keys, popover.before) = (anchor, part, keys, window.firstResponder)
        popover.sizingOptions = [.intrinsicContentSize]
        (root.subviews.lazy.compactMap { $0 as? WindowLayer }.first ?? WindowLayer(over: root)).hold(popover)
        popover.place()
        window.makeFirstResponder(popover)
        popover.clicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak popover] event in
            popover?.clicked(event)
            return event
        }
        (shown, open.part) = (popover, part)
        NSAccessibility.post(element: popover, notification: .layoutChanged, userInfo: [.uiElements: [popover]])
    }

    /// A click elsewhere closes it; one on its own chip is left to the chip, which toggles it.
    private func clicked(_ event: NSEvent) {
        let inside = event.window === window && bounds.contains(convert(event.locationInWindow, from: nil))
        let chip = anchor.map { $0.window === event.window && $0.bounds.contains($0.convert(event.locationInWindow, from: nil)) } ?? false
        if !inside, !chip { close() }
    }

    func close() {
        if let clicks { NSEvent.removeMonitor(clicks) }
        clicks = nil
        guard superview != nil else { return }
        let window = window, before = before
        removeFromSuperview()
        if Popover.shown === self { (Popover.shown, Popover.open.part) = (nil, nil) }
        if let before, before !== self { window?.makeFirstResponder(before) }
    }

    /// Under its chip, or over it when there is no room; above the card, to its right edge, when the chip is in it.
    private func place() {
        guard let layer = superview, let anchor, let window else { return close() }
        let size = fittingSize, chip = layer.convert(anchor.bounds, from: anchor)
        let card = sequence(first: anchor as NSView, next: \.superview).first { $0 is CardHost }
        let room = layer.convert(window.contentLayoutRect, from: nil)
        let margin = Popover.margin
        var origin = NSPoint(x: chip.minX - margin, y: chip.minY - 6 - size.height + margin)
        if let card {
            let box = layer.convert(card.bounds, from: card).insetBy(dx: AssistantCard.margin, dy: AssistantCard.margin)
            origin = NSPoint(x: box.maxX - size.width + margin, y: box.maxY + 6 - margin)
        } else if origin.y < room.minY { origin.y = chip.maxY + 6 - margin }
        origin.x = max(room.minX, min(room.maxX - size.width, origin.x))
        origin.y = max(room.minY, min(room.maxY - size.height, origin.y))
        frame = NSRect(origin: origin, size: size)
        placed = size
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) { place() }

    /// A list that grows, a pane that takes its place: it stays by its chip.
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in if let self, self.superview != nil, self.fittingSize != self.placed { self.place() } }
    }

    override var acceptsFirstResponder: Bool { true }

    @discardableResult func press(_ key: Key) -> Bool {
        if keys?(key, self) == true { return true }
        guard key == .escape else { return false }
        close()
        return true
    }

    override func keyDown(with event: NSEvent) {
        let key: Key? = switch event.keyCode {
        case 126: .up
        case 125: .down
        case 123: .left
        case 124: .right
        case 36, 76: .enter
        case 48: .tab
        case 53: .escape
        default: nil
        }
        if key == nil || !press(key ?? .escape) { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { press(.escape) }
}

/// The popover's card: the mockup's 344 points on the float shadow.
private struct PopoverCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous), dark = scheme == .dark
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(width: 344)
            .background(shape.fill(Look.Token.bg2.ui))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Look.Token.line2.ui, lineWidth: 1))
            .shadow(color: .black.opacity(dark ? 0.4 : 0.1), radius: 7, y: 4)
            .padding(Popover.margin)
    }
}

/// A heading in small capitals, with its small words at the right.
private struct PickerHead: View {
    let title: String
    var small: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title.uppercased()).font(Look.font(.ui, size: 10.5, weight: .semibold).ui).kerning(0.42).foregroundStyle(Look.Token.ink3.ui)
                .accessibilityAddTraits(.isHeader).accessibilityLabel(title)
            Spacer(minLength: 0)
            if let small { Text(small).font(Look.font(.ui, size: 10.5).ui).foregroundStyle(Look.Token.ink3.ui).lineLimit(1) }
        }
        .padding(EdgeInsets(top: 7, leading: 9, bottom: 4, trailing: 9)).frame(minHeight: 27)
    }
}

/// One row of a picker: what leads it, a name and its line, a check.
private struct PickerRow<Lead: View>: View {
    let name: String
    var about: String? = nil, chosen = false, lit = false, dim = false
    var hover: () -> Void = {}
    @ViewBuilder var lead: () -> Lead
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 8) {
                lead()
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(Look.font(.ui, size: 12.5, weight: .medium).ui).foregroundStyle((dim ? Look.Token.ink3 : .ink).ui).lineLimit(1)
                    if let about { Text(about).font(Look.font(.ui, size: 11).ui).foregroundStyle(Look.Token.ink3.ui).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 0)
                if chosen { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Look.Token.ink.ui) }
            }
            .padding(.horizontal, 9).padding(.vertical, 5).frame(minHeight: 30)
            .background(lit ? Look.Token.sel.ui : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { hover() } }
        .accessibilityLabel([name, about].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// The foot: the choice's scope, and the way to the defaults where it has one.
private struct PickerFoot: View {
    let scope: String, defaults: Bool, close: () -> Void

    var body: some View {
        Rectangle().fill(Look.Token.line.ui).frame(height: 1)
        HStack(spacing: 12) {
            Text(scope).font(Look.font(.ui, size: 11.5).ui).foregroundStyle(Look.Token.ink3.ui).lineLimit(1)
            Spacer(minLength: 0)
            if defaults {
                Button(AssistantModel.defaultsTitle) {
                    close()
                    Keys.send("defaults")
                }
                .buttonStyle(.plain).font(Look.font(.ui, size: 11.5, weight: .medium).ui).foregroundStyle(Look.Token.ink2.ui).fixedSize()
            }
        }
        .padding(.horizontal, 15).frame(minHeight: 36)
    }
}

/// Where a picker's keys are, and its search: a plain object, since no view here may hold state. It walks the rows it is
/// given, then the gauge when there is one, and says each step to VoiceOver, for the list is not where its cursor is.
@MainActor @Observable final class PickerKeys {
    typealias Line = (words: String, pick: () -> Void)
    private let lines: (String) -> [Line], gauge: () -> ModelChoice?
    var query = ""
    var row: Int
    var onEffort = false
    /// Whether the pointer or the keys came here: until then no row is lit.
    var moved = false

    init(lines: @escaping (String) -> [Line], row: Int, gauge: @escaping () -> ModelChoice? = { nil }) {
        (self.lines, self.row, self.gauge) = (lines, row, gauge)
    }

    /// Over a model chip's choice.
    convenience init(_ choice: @escaping () -> ModelChoice) {
        let now = choice()
        self.init(lines: { query in
            let now = choice()
            return now.shown(query).map { row in
                ([row.name, row.about, now.isChosen(row) ? "selected" : nil].compactMap { $0 }.joined(separator: ", "), { now.pick(row.value) })
            }
        }, row: now.rows.firstIndex(where: now.isChosen) ?? 0, gauge: choice)
    }

    /// Over the programs an assistant can choose.
    convenience init(_ model: AssistantModel) {
        let open = model.entries.filter(\.enabled)
        self.init(lines: { _ in open.map { entry in (Registry.app.name(of: entry.id), { model.choose(entry.id) }) } }, row: open.firstIndex(where: \.checked) ?? 0)
    }

    func press(_ key: Popover.Key, _ popover: Popover) -> Bool {
        moved = true
        let rows = lines(query), now = gauge(), levels = now?.efforts ?? []
        let at = levels.firstIndex { $0.value == now?.effort } ?? -1
        switch key {
        case .down where onEffort: break
        case .tab where onEffort: onEffort = false
        case .down where row + 1 < rows.count: row += 1
        case .down, .tab: onEffort = !levels.isEmpty
        case .up where onEffort: (onEffort, row) = (false, max(0, rows.count - 1))
        case .up: row = max(0, row - 1)
        case .left where onEffort && at > 0: now?.pickEffort(levels[at - 1].value)
        case .right where onEffort && at + 1 < levels.count: now?.pickEffort(levels[at + 1].value)
        case .enter:
            popover.close()
            if !onEffort, rows.indices.contains(row) { rows[row].pick() }
            return true
        case .escape where !query.isEmpty: (query, row) = ("", 0)
        default: return false
        }
        let said = onEffort ? gauge().flatMap { $0.words.effort } : rows.indices.contains(row) ? lines(query)[row].words : nil
        if let said { (popover.superview as? WindowLayer)?.announce(said) }
        return true
    }
}

/// The models of a program, the effort under them, and the foot; or, for what is not known, a sentence saying so.
struct ModelPicker: View {
    let choice: () -> ModelChoice
    @Bindable var keyboard: PickerKeys
    let close: () -> Void
    @FocusState private var searching: Bool

    var body: some View {
        let now = choice()
        PopoverCard {
            VStack(alignment: .leading, spacing: 0) {
                PickerHead(title: "Model", small: now.models == .rows || now.models == .reading ? now.from : nil)
                switch now.models {
                case .rows: list(now)
                case .own: pane("\(now.name) chooses its own model", "something shows it and can’t change it. Change it in " + Words.possessive(now.name) + " settings.")
                case .reading: reading
                case .unread: pane("Its models show after its first run", "Until then \(now.name) uses its own default. something doesn’t guess the list.")
                }
            }
            .padding(EdgeInsets(top: 4, leading: 6, bottom: 0, trailing: 6))
            PickerFoot(scope: now.scope, defaults: now.defaults, close: close)
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Model and effort")
    }

    @ViewBuilder private func list(_ now: ModelChoice) -> some View {
        if now.isLong {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Look.Token.ink3.ui)
                TextField("Search \(now.rows.count) models", text: $keyboard.query).textFieldStyle(.plain).font(Look.font(.ui, size: 13).ui)
                    .focused($searching).accessibilityLabel("Search \(now.rows.count) models")
                    .onChange(of: keyboard.query) { keyboard.row = 0 }
                    .onAppear { DispatchQueue.main.async { searching = true } }
                    .onKeyPress(.upArrow) { field(.up) }.onKeyPress(.downArrow) { field(.down) }.onKeyPress(.return) { field(.enter) }
                    .onKeyPress(.tab) { field(.tab) }.onKeyPress(.escape) { field(.escape) }
                    .onKeyPress(.leftArrow) { keyboard.onEffort ? field(.left) : .ignored }.onKeyPress(.rightArrow) { keyboard.onEffort ? field(.right) : .ignored }
            }
            .padding(.horizontal, 9).frame(height: 28)
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Look.Token.line2.ui))
            .padding(EdgeInsets(top: 1, leading: 3, bottom: 5, trailing: 3))
            ScrollViewReader { list in
                ScrollView { rows(now) }.frame(height: 276)
                    .onChange(of: keyboard.row) { list.scrollTo(keyboard.row) }
                    .onAppear { list.scrollTo(keyboard.row, anchor: .center) }
            }
        } else {
            rows(now).padding(.bottom, 6)
        }
        effort(now)
    }

    private func field(_ key: Popover.Key) -> KeyPress.Result {
        Popover.shown?.press(key) == true ? .handled : .ignored
    }

    private func rows(_ now: ModelChoice) -> some View {
        let shown = now.shown(keyboard.query)
        return VStack(alignment: .leading, spacing: 1) {
            if shown.isEmpty {
                Text("No model matches “\(keyboard.query.trimmingCharacters(in: .whitespaces))”.").font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink3.ui)
                    .padding(EdgeInsets(top: 12, leading: 9, bottom: 12, trailing: 9))
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { index, row in
                if let group = row.group, group != (index > 0 ? shown[index - 1].group : nil) {
                    Text(group).font(Look.font(.ui, size: 11, weight: .semibold).ui).foregroundStyle(Look.Token.ink3.ui)
                        .padding(EdgeInsets(top: 8, leading: 9, bottom: 3, trailing: 9)).accessibilityAddTraits(.isHeader)
                }
                PickerRow(name: row.name, about: row.about, chosen: now.isChosen(row), lit: keyboard.moved && !keyboard.onEffort && keyboard.row == index,
                          hover: { (keyboard.row, keyboard.moved, keyboard.onEffort) = (index, true, false) }, lead: { EmptyView() }) { now.pick(row.value) }
                .id(index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The gauge: a notch per level the agent lists, tallest last; an effort beyond the levels comes after them, apart
    /// and outlined, its line in place of the usual one.
    @ViewBuilder private func effort(_ now: ModelChoice) -> some View {
        if !now.efforts.isEmpty || now.effortUnread {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text("Effort").font(Look.font(.ui, size: 12.5, weight: .medium).ui).foregroundStyle(Look.Token.ink.ui)
                    Spacer(minLength: 0)
                    if now.efforts.isEmpty {
                        Text("Shows after its first run").font(Look.font(.ui, size: 11.5).ui).foregroundStyle(Look.Token.ink3.ui)
                    } else { gauge(now) }
                }
                .frame(minHeight: 28)
                if !now.efforts.isEmpty {
                    Text(now.efforts.first { $0.value == now.effort }?.about ?? (now.clears && now.effort != nil ? "Click it again for the agent’s own effort." : "Higher is slower and uses your limits faster."))
                        .font(Look.font(.ui, size: 11).ui).foregroundStyle(Look.Token.ink3.ui)
                }
            }
            .padding(EdgeInsets(top: 9, leading: 7, bottom: 11, trailing: 7))
            .background(alignment: .top) { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }
            .padding(.horizontal, 2)
        }
    }

    private func gauge(_ now: ModelChoice) -> some View {
        let at = now.efforts.firstIndex { $0.value == now.effort } ?? -1, top = CGFloat(max(1, now.efforts.filter { $0.about == nil }.count - 1))
        return HStack(alignment: .bottom, spacing: 1) {
            ForEach(Array(now.efforts.enumerated()), id: \.offset) { index, level in
                let beyond = level.about != nil, on = index <= at
                Button { now.pickEffort(level.value) } label: {
                    RoundedRectangle(cornerRadius: 2).fill((on ? Look.Token.ink : beyond ? .bg2 : .mist).ui)
                        .overlay { if beyond && !on { RoundedRectangle(cornerRadius: 2).strokeBorder(Look.Token.ink3.ui, lineWidth: 1.5) } }
                        .frame(width: beyond ? 7 : 5, height: beyond ? 21 : 8 + 13 * CGFloat(index) / top)
                        .frame(width: beyond ? 14 : 12, height: 24, alignment: .bottom).padding(.bottom, 3).contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.leading, beyond ? 7 : 0)
                .accessibilityLabel(level.label).accessibilityAddTraits(index == at ? .isSelected : [])
            }
            Text(now.words.effort ?? "").font(Look.font(.ui, size: 12, weight: .medium).ui).foregroundStyle(Look.Token.ink2.ui)
                .frame(minWidth: 44, alignment: .trailing).padding(.leading, 6).padding(.bottom, 7).accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Effort")
    }

    private func pane(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Look.font(.ui, size: 13, weight: .semibold).ui).foregroundStyle(Look.Token.ink.ui)
            Text(text).font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink2.ui).fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: 6, leading: 9, bottom: 12, trailing: 9)).frame(maxWidth: .infinity, alignment: .leading)
    }

    /// While something reads the list: the line, and three rows' places.
    private var reading: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Reading its models…").font(Look.font(.ui, size: 12.5, weight: .medium).ui).foregroundStyle(Look.Token.ink2.ui).padding(.bottom, 3)
            ForEach([0.62, 0.44, 0.54], id: \.self) { width in
                VStack(alignment: .leading, spacing: 5) {
                    Capsule().fill(Look.Token.sunk.ui).frame(width: 300 * width, height: 7)
                    Capsule().fill(Look.Token.sunk.ui).frame(width: 300 * (width - 0.18), height: 6).opacity(0.7)
                }
            }
        }
        .padding(EdgeInsets(top: 5, leading: 9, bottom: 14, trailing: 9)).accessibilityElement(children: .ignore).accessibilityLabel("Reading its models…")
    }
}

/// The programs found, each with its monogram and what to know of it, then the ones something only sees.
struct ProgramPicker: View {
    let model: AssistantModel
    @Bindable var keyboard: PickerKeys
    let close: () -> Void

    var body: some View {
        PopoverCard {
            VStack(alignment: .leading, spacing: 1) {
                PickerHead(title: "Program")
                let open = model.entries.filter(\.enabled)
                ForEach(model.entries) { entry in
                    let at = open.firstIndex { $0.id == entry.id }
                    PickerRow(name: Registry.app.name(of: entry.id), about: entry.note ?? entry.because, chosen: entry.checked, lit: keyboard.moved && at == keyboard.row, dim: !entry.enabled,
                              lead: { Monogram(name: Registry.app.name(of: entry.id), side: 22) }) {
                        close()
                        model.choose(entry.id)
                    }
                    .disabled(!entry.enabled)
                }
                PickerHead(title: "Seen only")
                ForEach(AssistantModel.seenOnly, id: \.name) { seen in
                    PickerRow(name: seen.name, about: seen.why, dim: true, lead: { Monogram(name: seen.name, side: 22).opacity(0.55) }) {}.disabled(true)
                }
            }
            .padding(EdgeInsets(top: 4, leading: 6, bottom: 6, trailing: 6))
            PickerFoot(scope: model.modelChoice.scope, defaults: true, close: close)
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Program")
    }
}
