// The assistant's card, 412 points at the bottom right of the center, over the space: its header (the eyes of its
// state in the whole sign, "<space>'s assistant" as the conversation menu, the state word, Fold, Reduce and the grip),
// the conversation (⌘J: your bubbles in ink, the agent's voice in Young Serif, tool lines in code, a line between days,
// the messages held for the turn's end outlined with Take Back; a finished build said short: what was made, the reply's
// first paragraph, the steps and the rest folded under Details), one notice when it is stuck or waits for you, the
// present-tense line while it works, and the composer: the agent's own commands while "/" starts the field, its three
// chips (Chips.swift), the held messages' strip while the conversation is folded, and a flat field
// whose Send turns into Stop (New Space reuses it and the notice).
// Its words are the model's and Presence's; the card keeps only the field's focus. A request is never answered here:
// the notice leads to the native panel. CardHost holds it in the glass (Glass.swift) and lets the clicks beside it
// reach the space.
import AppKit
import SomethingAgents
import SomethingCore
import SwiftUI

struct AssistantCard: View {
    @Bindable var model: AssistantModel
    @Environment(\.colorScheme) private var scheme

    /// The card's width, its distance from the center's edges, and the conversation's tallest.
    static let width: CGFloat = 412, margin: CGFloat = 16, thread: CGFloat = 288

    var body: some View {
        // Still drawn while it shrinks into the sticker (folding).
        if model.cardShown || model.folding {
            VStack(spacing: 0) {
                header
                // The "/" list opens over what is above the field, as a menu: the card keeps its size unless that is
                // shorter than the list.
                ZStack(alignment: .bottom) {
                    VStack(spacing: 0) {
                        if model.threadShown { conversation }
                        if let notice = model.notice { NoticeView(notice: notice).padding(EdgeInsets(top: 2, leading: 10, bottom: 8, trailing: 10)) }
                        if let now = model.presence.now { nowLine(now) }
                    }
                    if model.place != .blank, let shown = model.slashed { CommandList(model: model, shown: shown).padding(EdgeInsets(top: 0, leading: 8, bottom: 4, trailing: 8)) }
                }
                if model.place != .blank { composer }
            }
            .frame(width: model.cardWidth)
            .background {
                let shape = RoundedRectangle(cornerRadius: Look.card + 4, style: .continuous)
                let dark = scheme == .dark
                shape.fill(Look.Token.bg2.ui)
                    // The float shadow, kept inside the card's 16-point margin, where the host draws.
                    .shadow(color: .black.opacity(dark ? 0.35 : 0.06), radius: 1, y: 1)
                    .shadow(color: .black.opacity(dark ? 0.5 : 0.12), radius: 7, y: 6)
                    .overlay(shape.strokeBorder(Look.Token.line2.ui, lineWidth: 1))
            }
            .padding(AssistantCard.margin)
            // While it grows or shrinks, the host is smaller than the card, which stays pinned to the sticker's corner.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    // MARK: The header

    private var header: some View {
        let presence = model.presence
        return HStack(spacing: 2) {
            VStack(alignment: .leading, spacing: 1) {
                Menu { ConversationMenu(model: model) } label: {
                    HStack(spacing: 5) {
                        Text(heading).font(Look.font(.ui, size: 13, weight: .semibold).ui).foregroundStyle(Look.Token.ink.ui).lineLimit(1)
                            // What the sign, the chevron, the two buttons and the grip leave it: a narrow card cuts its end.
                            .frame(maxWidth: model.cardWidth - 156, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        Chevron()
                    }
                    .padding(.horizontal, 6).frame(height: 22).contentShape(Rectangle())
                }
                .plainMenu()
                .accessibilityLabel("Conversation menu")
                Text(model.header).font(Look.small.font.ui).foregroundStyle(Look.Token.ink2.ui).lineLimit(1).padding(.leading, 6)
            }
            // The state line takes the room before the buttons rather than the heading's width.
            .layoutPriority(1)
            Spacer(minLength: 0)
            // Fold: the conversation folds away, the card keeping its header and field (⌘J).
            Button { model.threadShown.toggle() } label: {
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).rotationEffect(.degrees(model.threadShown ? 0 : 180))
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(Look.Token.ink2.ui).help(Keys.tooltip("convo", model.threadShown ? "Fold Conversation" : nil))
            .accessibilityLabel(model.threadShown ? "Fold Conversation" : "Show Conversation")
            Button { model.open = false } label: {
                Image(systemName: "minus").font(.system(size: 12, weight: .medium)).frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(Look.Token.ink2.ui).help(Keys.tooltip("reduce", "Reduce")).accessibilityLabel("Reduce")
            .padding(.trailing, 2)
            // The grip: six 2-point dots, two by three, as the mockup's 13-point icon (AB06 makes it drag the card).
            Grid(horizontalSpacing: 1.25, verticalSpacing: 1.25) {
                ForEach(0..<3, id: \.self) { _ in GridRow { ForEach(0..<2, id: \.self) { _ in Circle().frame(width: 2, height: 2) } } }
            }
            .foregroundStyle(Look.Token.ink3.ui).frame(width: 22, height: 28).accessibilityHidden(true)
        }
        .padding(.leading, 42).padding(.trailing, 8)
        .frame(height: 54)
        .overlay(alignment: .topLeading) {
            // The whole sign, its corners and the eyes of its state, as the mockup's header.
            Image(nsImage: Sign.image(presence.state, side: 28))
                .frame(width: 28, height: 28).position(x: 25, y: 27)
                .accessibilityElement().accessibilityLabel(presence.state.word)
        }
    }

    /// "Week-end's assistant" in a space; where the person is elsewhere.
    private var heading: String {
        model.inSpace ? Words.possessive(model.title) + " assistant" : model.title
    }

    // MARK: The conversation

    private var conversation: some View {
        // The scroll view asks for the whole conversation, and the card gives it what is left under 288 points: all of
        // it when it fits, else its end, which stays in view while at the bottom.
        ScrollView {
            VStack(alignment: .leading, spacing: 6 * Look.density) {
                // How it works here, said when the conversation begins, gone once it has rows, as the mockup's thread.
                ForEach(model.rows.isEmpty ? model.firstLines : [], id: \.self) {
                    Text($0).font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 4)
                if let word = model.firstWord { line(.reply(word)) }
                let rows = model.rows, ended = !model.working
                // A finished build's steps are its Details': drawn there, not in the thread.
                let built = rows.indices.compactMap { at in AssistantModel.built(rows, at: at, ended: ended).map { (at, $0) } }
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if let build = built.first(where: { $0.0 == index })?.1 { reply(build, rows, index) }
                    else if built.contains(where: { $0.1.steps.lowerBound - 1 == index }), let text = row.mine { line(.mine(caption: nil, text: text)) }
                    else if !built.contains(where: { $0.1.steps.contains(index) }) { line(row) }
                }
                ForEach(Array(model.held.enumerated()), id: \.offset) { _, text in
                    AssistantCard.mine(text).foregroundStyle(Look.Token.ink2.ui).overlay(AssistantCard.mineShape.strokeBorder(Look.Token.line2.ui))
                        .padding(.leading, 50)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if !model.held.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "clock").font(.system(size: 9.5))
                        Text("Sends when it finishes")
                        Button("Take Back") { model.takeBack() }.buttonStyle(.plain)
                            .font(Look.font(.ui, size: 10.5, weight: .semibold).ui).foregroundStyle(Look.Token.ink2.ui)
                            .padding(.horizontal, 5).padding(.leading, 4)
                    }
                    .font(Look.font(.ui, size: 10.5).ui).foregroundStyle(Look.Token.ink3.ui)
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.top, -4)
                }
            }
            .padding(EdgeInsets(top: 2, leading: 14, bottom: 14, trailing: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
        .defaultScrollAnchor(.bottom)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: AssistantCard.thread)
        // What scrolled up fades out under the header, never cut there.
        .mask(VStack(spacing: 0) { LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 12); Color.black })
    }

    @ViewBuilder private func line(_ row: AssistantModel.Row) -> some View {
        switch row {
        case .day(let date):
            HStack(spacing: 10) {
                Rectangle().fill(Look.Token.line.ui).frame(height: 1)
                Text(AssistantCard.day(date, now: model.clock())).font(Look.xs.font.ui).foregroundStyle(Look.Token.ink3.ui).fixedSize()
                Rectangle().fill(Look.Token.line.ui).frame(height: 1)
            }
            .padding(EdgeInsets(top: 4, leading: 0, bottom: 2, trailing: 0))
        case .mine(let caption, let text):
            VStack(alignment: .trailing, spacing: 2) {
                if let caption, caption != model.here { Text(caption).font(Look.xs.font.ui).foregroundStyle(Look.Token.ink3.ui) }
                AssistantCard.mine(text).foregroundStyle(Look.Token.bg.ui).background(Look.Token.ink.ui, in: AssistantCard.mineShape)
            }
            .padding(.leading, 50)
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .reply(let text):
            Text(AssistantCard.markdown(text))
                .font(Look.font(.voice, size: 13).ui).lineSpacing(1.5).foregroundStyle(Look.Token.ink.ui)
                .bubble()
                .background(Look.Token.sunk.ui, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4, bottomTrailingRadius: 18, topTrailingRadius: 18))
                .padding(.trailing, 50)
        case .tool(let failed, let words, let command):
            HStack(spacing: 7) {
                Image(systemName: failed ? "xmark" : "checkmark").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(failed ? Look.Token.ink3.ui : Look.Token.ok.ui).frame(width: 12)
                Text(command.map { "Ran \($0)\(words)" } ?? words).lineLimit(2).truncationMode(.middle)
            }
            .font(Look.font(.code, size: 11).ui).foregroundStyle(Look.Token.ink2.ui)
            .padding(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 4))
        }
    }

    /// A finished build: what was made in one line, the reply's first paragraph, then Details, which unfolds the steps
    /// and the reply's rest.
    private func reply(_ build: AssistantModel.Built, _ rows: [AssistantModel.Row], _ index: Int) -> some View {
        let open = model.unfolded.contains(index)
        return VStack(alignment: .leading, spacing: 4) {
            if let made = build.made { line(.tool(failed: made.hasSuffix("found errors"), words: made, command: nil)) }
            line(.reply(build.short))
            Button { if open { model.unfolded.remove(index) } else { model.unfolded.insert(index) } } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right").font(.system(size: 8.5, weight: .semibold)).rotationEffect(.degrees(open ? 90 : 0))
                    Text("Details")
                }
                .font(Look.font(.ui, size: 11.5, weight: .medium).ui).foregroundStyle(Look.Token.ink2.ui).padding(.leading, 6).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? "Hide Details" : "Details")
            if open {
                ForEach(Array(build.steps), id: \.self) { line(rows[$0]) }
                if let rest = build.rest {
                    Text(AssistantCard.markdown(rest)).font(Look.font(.voice, size: 12).ui).lineSpacing(1.5).foregroundStyle(Look.Token.ink2.ui)
                        .padding(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 50))
                }
            }
        }
    }

    /// An agent's reply with its inline Markdown (code, links, emphasis; bold set regular), the line breaks kept; as
    /// written when it does not parse.
    static func markdown(_ text: String) -> AttributedString {
        var parsed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        // Young Serif has one weight: bold words would be thickened by the system, a synthetic bold. They stay regular.
        for run in parsed.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            parsed[run.range].inlinePresentationIntent?.remove(.stronglyEmphasized)
        }
        return parsed
    }

    /// A button's title split before its shortcut (a last word holding ⌘), nil when it has none.
    static func shortcut(of title: String) -> (String, String?) {
        guard let space = title.lastIndex(of: " "), title[space...].contains("⌘") else { return (title, nil) }
        return (String(title[..<space]), String(title[title.index(after: space)...]))
    }

    /// A message of the person's, held or sent, and the shape of its bubble.
    private static func mine(_ text: String) -> some View {
        // A command of the agent's, sent as is, reads as code.
        Text(text).font(text.hasPrefix("/") ? Look.font(.code, size: 12, weight: .semibold).ui : Look.font(.ui, size: 12.8).ui).lineSpacing(2.8).bubble()
    }
    private static let mineShape = UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 4, topTrailingRadius: 18)

    /// One formatter for every day line, which the card draws on the main thread only.
    private static let dayFormat = { let format = DateFormatter(); format.locale = Locale(identifier: "en_GB"); return format }()

    /// The words of a day line: "Today", "Yesterday", a weekday within the week, else the date ("3 October").
    static func day(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        let format = dayFormat
        (format.calendar, format.timeZone) = (calendar, calendar.timeZone)
        format.dateFormat = days == 1 ? "'Yesterday'" : days > 1 && days < 7 ? "EEEE" : "d MMMM"
        return format.string(from: date)
    }

    // MARK: The present-tense line

    private func nowLine(_ now: Presence.Now) -> some View {
        HStack(spacing: 8) {
            switch now {
            case .working(let step, let late):
                Image(nsImage: Sign.miniEyes(.think, template: false)).frame(width: 18, height: 12)
                Text(step).lineLimit(1).truncationMode(.tail)
                if late {
                    Spacer(minLength: 4)
                    Text("Still working").font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui)
                    Button { model.stop() } label: {
                        HStack(spacing: 6) {
                            Text("Stop").font(Look.font(.ui, size: 12, weight: .semibold).ui)
                            Text(Keys.shown("stop")).font(Look.font(.ui, size: 10, weight: .medium).ui).foregroundStyle(Look.Token.ink3.ui)
                                .padding(.vertical, 2).padding(.horizontal, 4)
                                .background(Look.Token.hover.ui, in: RoundedRectangle(cornerRadius: 5))
                        }
                            .padding(.leading, 9).padding(.trailing, 6).frame(height: 24)
                            .overlay(RoundedRectangle(cornerRadius: Look.control).strokeBorder(Look.Token.line2.ui))
                    }
                    .buttonStyle(.plain).help(model.presence.stopHelp)
                } else {
                    Spacer(minLength: 0)
                }
            case .waking:
                Image(nsImage: Sign.miniEyes(.sleep, template: false)).frame(width: 18, height: 12)
                Text("Waking up…")
                Spacer(minLength: 0)
            case .changed(let file):
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Look.Token.ok.ui).frame(width: 13)
                Text("Changed ") + Text(file).font(Look.font(.ui, size: 12, weight: .semibold).ui)
                Spacer(minLength: 4)
                Text("Just now").font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui)
            }
        }
        .font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink.ui)
        .padding(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 4))
        .frame(height: 30)
        .padding(.horizontal, 10)
    }

    // MARK: The composer

    /// What waits for the turn's end while the conversation is folded, and Take Back.
    private var heldStrip: some View {
        let count = model.held.count
        return HStack(spacing: 7) {
            Image(systemName: "clock").font(.system(size: 10.5))
            (Text("\(count) message\(count > 1 ? "s" : "") wait\(count > 1 ? "" : "s")").font(Look.font(.ui, size: 11.5, weight: .semibold).ui).foregroundColor(Look.Token.ink.ui)
                + Text(count > 1 ? " · they send when it finishes" : " · sends when it finishes"))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            Button { model.takeBack() } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(Look.Token.ink3.ui).help("Take Back").accessibilityLabel(count > 1 ? "Take back the waiting messages" : "Take back the waiting message")
        }
        .font(Look.font(.ui, size: 11.5).ui).foregroundStyle(Look.Token.ink2.ui)
        .padding(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 3))
        .background(Look.Token.sunk.ui, in: RoundedRectangle(cornerRadius: Look.control + 2, style: .continuous))
        .padding(.bottom, 6)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            AgentChips(model: model).padding(.bottom, 4)
            if !model.threadShown, !model.held.isEmpty { heldStrip }
            Field(model: model)
        }
        .padding(EdgeInsets(top: 2, leading: 8, bottom: 8, trailing: 8))
    }
}

/// A button drawn only by its label, never dimmed by the system when disabled: the label says it.
private struct Bare: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.opacity(configuration.isPressed ? 0.86 : 1) }
}

/// The flat field and its Send button, which turns into Stop while the agent works and nothing is written. Return
/// sends, ⇧Return adds a line, and Return that confirms what an input method composes sends nothing.
struct Field: View {
    @Bindable var model: AssistantModel
    @FocusState private var typing: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            TextField("", text: $model.draft, prompt: Text(model.placeholder).foregroundStyle(Look.Token.ink3.ui), axis: .vertical)
                .textFieldStyle(.plain)
                .font(Look.font(.ui, size: 13.5).ui)
                .foregroundStyle(Look.Token.ink.ui)
                .lineLimit(1...5)
                .padding(.horizontal, 2).padding(.vertical, 5)
                .frame(minHeight: 30)
                .accessibilityLabel(model.messageLabel)
                .composing(model, $typing)
                // Outside composing's Return, which would send the "/" typed: the outer handler is asked first.
                .onKeyPress(keys: [.upArrow, .downArrow, .return, .tab], phases: .down) { Field.slash($0.key, model) }
            let stop = model.stops
            Button { stop ? model.stop() : model.send() } label: {
                Group {
                    if stop {
                        RoundedRectangle(cornerRadius: 1.8).frame(width: 8, height: 8)
                    } else {
                        Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold))
                    }
                }
                .foregroundStyle(Look.Token.actfg.ui)
                .frame(width: 30, height: 30)
                // Only the disc fades when nothing can be sent, as the mockup's: the plain style would fade it twice.
                .background(Look.Token.act.ui.opacity(model.canSend || stop ? 1 : 0.3), in: Circle())
            }
            .buttonStyle(Bare())
            .disabled(!model.canSend && !stop)
            .help(stop ? model.presence.stopHelp : model.working ? "Send when it finishes (Return)" : "Send (Return)")
            .accessibilityLabel(stop ? "Stop" : model.working ? "Send when it finishes" : "Send")
        }
        .padding(EdgeInsets(top: 5, leading: 4, bottom: 5, trailing: 5))
        .background(Look.Token.bg.ui, in: RoundedRectangle(cornerRadius: Look.control + 5, style: .continuous))
        // A calm 1.5-point line when it has the focus; no shadow, no ring.
        .overlay(RoundedRectangle(cornerRadius: Look.control + 5, style: .continuous)
            .strokeBorder(typing ? Look.Token.ink2.ui : Look.Token.line.ui, lineWidth: typing ? 1.5 : 1))
    }

    /// A key while the "/" list shows (else ignored): ↑↓ move the choice, Return sends the command chosen as is, Tab
    /// leaves it in the field for its text; handled then.
    static func slash(_ key: KeyEquivalent, _ model: AssistantModel) -> KeyPress.Result {
        guard let shown = model.slashed, !shown.isEmpty else { return .ignored }
        let at = min(model.commandPick, shown.count - 1)
        switch key {
        case .upArrow, .downArrow: model.commandPick = (at + (key == .upArrow ? shown.count - 1 : 1)) % shown.count
        default: model.use(shown[at], send: key == .return)
        }
        return .handled
    }

    /// What Return does in the field.
    enum Return: Equatable { case send, newline, compose }

    /// Return sends, ⇧Return adds a line; while an input method composes (Japanese, Chinese, Korean), Return is its.
    static func onReturn(shift: Bool, marked: Bool) -> Return {
        marked ? .compose : shift ? .newline : .send
    }

    /// What Return does in this field or New Space's: nothing while an input method composes (`marked`, ignored), a new
    /// line with `shift`, else it sends; handled then.
    static func returned(shift: Bool, marked: Bool, _ model: AssistantModel) -> KeyPress.Result {
        switch onReturn(shift: shift, marked: marked) {
        case .compose: return .ignored
        case .send: model.send()
        case .newline:
            if !NSApp.sendAction(#selector(NSTextView.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil) { model.draft += "\n" }
        }
        return .handled
    }
}

extension View {
    /// The focus and keys of this field or New Space's: ⌘K's focus a turn after the request, once a field just drawn is
    /// in the window (before, it refuses it), and Return as `returned` says, which reads an input method composing.
    func composing(_ model: AssistantModel, _ typing: FocusState<Bool>.Binding) -> some View {
        focused(typing)
            .disabled(model.blocked)
            .onChange(of: model.wantsFocus, initial: true) {
                if model.wantsFocus { DispatchQueue.main.async { (typing.wrappedValue, model.wantsFocus) = (true, false) } }
            }
            .onKeyPress(.return, phases: .down) { press in
                let marked = (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true
                return Field.returned(shift: press.modifiers.contains(.shift), marked: marked, model)
            }
    }
}

/// The agent's own commands over the field while "/" starts it, as the mockup's .ag-cm: those whose name starts as
/// typed, the chosen one marked; a click uses one as Return does.
struct CommandList: View {
    let model: AssistantModel, shown: [Option]

    var body: some View {
        let at = min(model.commandPick, shown.count - 1)
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 7) {
                Monogram(name: model.name)
                Text(Words.possessive(model.name) + " commands").font(Look.font(.ui, size: 12, weight: .semibold).ui).foregroundStyle(Look.Token.ink.ui)
                Spacer(minLength: 4)
                Text("as \(model.name) lists them").font(Look.xs.font.ui)
            }
            .padding(EdgeInsets(top: 4, leading: 7, bottom: 6, trailing: 7))
            ScrollViewReader { list in ScrollView {
                VStack(spacing: 1) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { index, command in
                        Button { model.use(command, send: true) } label: {
                            HStack(spacing: 8) {
                                Text("/" + command.value).font(Look.font(.code, size: 11.5, weight: .semibold).ui).foregroundStyle(Look.Token.ink.ui).frame(width: 86, alignment: .leading)
                                Text(command.label).font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink2.ui).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8).frame(minHeight: 36).contentShape(Rectangle())
                            .background(index == at ? Look.Token.sel.ui : .clear, in: RoundedRectangle(cornerRadius: Look.control))
                        }
                        .buttonStyle(.plain).id(index)
                        .accessibilityLabel("/\(command.value), \(command.label)").accessibilityAddTraits(index == at ? .isSelected : [])
                    }
                    if shown.isEmpty { Text(model.noCommands).font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink2.ui).padding(8).frame(maxWidth: .infinity, alignment: .leading) }
                }
            }
            .onChange(of: at) { list.scrollTo(at) } }
            .frame(height: CGFloat(min(max(shown.count, 1), 6)) * 37)
            HStack(spacing: 12) {
                Text("↑↓ choose"); Text("↩ send"); Text("⇥ add text"); Spacer(minLength: 4); Text("Passed to \(model.name) as is")
            }
            .font(Look.xs.font.ui).padding(EdgeInsets(top: 7, leading: 8, bottom: 2, trailing: 8))
            .overlay(alignment: .top) { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }.padding(.top, 4)
        }
        .foregroundStyle(Look.Token.ink3.ui)
        .padding(6)
        .boxed(RoundedRectangle(cornerRadius: Look.card, style: .continuous), Look.Token.bg.ui, ring: Look.Token.line2.ui)
        .accessibilityElement(children: .contain).accessibilityLabel(Words.possessive(model.name) + " commands")
    }
}

/// One notice above the composer: its title, its sentence and the one or two things that help. Never Allow.
struct NoticeView: View {
    let notice: AssistantModel.Notice

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.symbol).font(.system(size: 12, weight: .medium))
                .foregroundStyle(notice.bad ? Look.Token.bad.ui : Look.Token.ink.ui)
                .frame(width: 24, height: 24)
                .boxed(RoundedRectangle(cornerRadius: Look.control), Look.Token.bg2.ui, ring: Look.Token.line.ui)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title).font(Look.font(.ui, size: 12.5, weight: .semibold).ui).foregroundStyle(Look.Token.ink.ui)
                if !notice.text.isEmpty {
                    Text(notice.text).font(Look.font(.ui, size: 11.8).ui).lineSpacing(2).foregroundStyle(Look.Token.ink2.ui)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                if !notice.actions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(notice.actions, id: \.title) { action in
                            Button(action: action.run) {
                                HStack(spacing: 6) {
                                    if let symbol = action.symbol { Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold)) }
                                    // Its shortcut, when it ends with one, smaller and quiet beside the words, as the mockup's.
                                    let (words, keys) = AssistantCard.shortcut(of: action.title)
                                    Text(words)
                                    if let keys { Text(keys).font(Look.font(.ui, size: 11).ui).foregroundStyle(Look.Token.ink3.ui) }
                                }
                                .font(Look.font(.ui, size: 12, weight: .semibold).ui).foregroundStyle(Look.Token.ink.ui)
                                    .padding(.horizontal, 11).frame(height: 27)
                                    .boxed(RoundedRectangle(cornerRadius: Look.control + 1), Look.Token.bg2.ui, ring: Look.Token.line2.ui)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 11, leading: 12, bottom: 11, trailing: 12))
        .boxed(RoundedRectangle(cornerRadius: Look.card + 2, style: .continuous), Look.Token.bg.ui, ring: Look.Token.line2.ui)
    }
}

// MARK: Chips

/// An agent's monogram, as the mockup's .xg-mono: its letters on a sunk tile, its descriptor's ("CC", "π"), else
/// its name's initials ("GC" for two words, the capitals of one word written in two, else its first letter), so that
/// no line here names an agent.
struct Monogram: View {
    let name: String
    var side: CGFloat = 18
    /// Inside a drawing that grows as one (Look.fixed).
    var fixed = false
    @Environment(\.colorScheme) private var scheme

    static func letters(_ name: String) -> String {
        if let mark = Registry.app.agents.first(where: { $0.name == name })?.monogram { return mark }
        let words = name.split(separator: " ").filter { !$0.isEmpty }
        if words.count > 1 { return words.prefix(2).compactMap { $0.first.map { String($0).uppercased() } }.joined() }
        let capitals = name.filter(\.isUppercase)
        if capitals.count == 2, name.contains(where: \.isLowercase) { return capitals }
        return name.first.map { String($0).uppercased() } ?? "?"
    }

    /// The tile for a menu item, which draws only text and images: a template, tinted as the menu's text. Drawn once
    /// per letters, since the menu's body is asked again at every refresh.
    @MainActor static func image(_ name: String) -> NSImage? {
        let mark = letters(name)
        if let image = images[mark] { return image }
        let image = ImageRenderer(content: Text(mark).font(Look.font(.ui, size: 9, weight: .semibold).ui).frame(width: 18, height: 18)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(lineWidth: 1))).nsImage
        image?.isTemplate = true
        images[mark] = image
        return image
    }
    @MainActor private static var images: [String: NSImage] = [:]

    var body: some View {
        Text(Monogram.letters(name)).font(fixed ? Look.fixed(.ui, size: side * 0.5, weight: .semibold) : Look.font(.ui, size: side * 0.5, weight: .semibold).ui)
            .foregroundStyle(Look.Token.ink2.ui)
            .frame(width: side, height: side)
            .background((scheme == .dark ? Look.Token.mist : .sunk).ui, in: RoundedRectangle(cornerRadius: side * 0.28))
            .accessibilityHidden(true)
    }
}

private struct Chevron: View {
    var body: some View { Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Look.Token.ink3.ui) }
}

extension View {
    /// A menu drawn only by its label.
    func plainMenu() -> some View { menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize() }

    /// A bubble's room around its words.
    func bubble() -> some View { padding(.horizontal, 11).padding(.vertical, 8 * Look.density) }
}

// MARK: Menus

/// The title's menu: the conversation and how it asks.
struct ConversationMenu: View {
    let model: AssistantModel

    var body: some View {
        Section("\(model.title) · its assistant") {
            Button("New Conversation") { model.newConversation() }
            Button("Stop") { model.stop() }.disabled(!model.stoppable).help(model.presence.stopHelp)
            Button("Put to Sleep") { model.putToSleep() }.disabled(!model.canSleep)
        }
        if model.canAskEverything {
            Divider()
            Toggle("Ask Before Every Change", isOn: Binding(get: { model.askEverything }, set: { _ in model.toggleAsking() }))
        }
        Divider()
        Button(Keys.command("lookAgain")?.title ?? "") { Keys.send("lookAgain") }
    }
}

// MARK: What the card says

extension AssistantModel {
    /// One notice: a symbol, its title and sentence, red when something broke, and the actions that help.
    struct Notice {
        struct Action { let title: String; var symbol: String? = nil; let run: () -> Void }
        let symbol: String, title: String, text: String, bad: Bool, actions: [Action]
    }

    /// Use Another Agent: the other builders in a menu at the pointer, the person choosing one (App.chooseBuilder).
    func chooseAnother() {
        let menu = NSMenu()
        menu.items = Self.builderItems(others)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// One menu item per builder in `entries`, each sending `action` with its kind: Use Another Agent chooses this
    /// conversation's builder, Build With ▸ New Space's (checking `checked` rather than this conversation's).
    static func builderItems(_ entries: [Entry], action: Selector = #selector(App.chooseBuilder(_:)), checked: String?? = .none) -> [NSMenuItem] {
        entries.map { entry in
            let item = NSMenuItem(title: entry.title, action: entry.enabled ? action : nil, keyEquivalent: "")
            let on = checked.map { $0 == entry.id } ?? entry.checked
            (item.representedObject, item.state, item.toolTip) = (entry.id, on ? .on : .off, entry.note)
            return item
        }
    }

    /// The way from a picker's foot and Build With ▸ to Settings › Agents.
    static let defaultsTitle = "Defaults for New Spaces…"

    /// What the running agent lists, else what its kind last listed (Preferences.listed).
    var offered: Options {
        if let live = agent?.options, agent?.alive != false, live.model?.isEmpty == false { return live }
        return kind.flatMap { Preferences.at(places).listed[$0] } ?? Options()
    }

    /// Its agent's own commands as it lists them now, else as its kind last listed them (Preferences.commands).
    var commands: [Option] { agent?.commands ?? kind.flatMap { Preferences.at(places).commands[$0] } ?? [] }

    /// What "/" offers while the field holds "/" and the start of a name: the commands whose name starts so; nil when
    /// it holds anything else, on New Space (its field has no list), or once Esc closed the list.
    var slashed: [Option]? {
        guard place != .blank, commandPick >= 0, draft.first == "/", !draft.contains(where: \.isWhitespace) else { return nil }
        return commands.filter { $0.value.lowercased().hasPrefix(draft.dropFirst().lowercased()) }
    }

    /// Puts `command` in the field, and sends it as is with `send`, else leaves a space after it for its text.
    func use(_ command: Option, send: Bool) {
        draft = "/" + command.value + (send ? "" : " ")
        if send { self.send() }
    }

    /// The list's line when no command shows: none starts so, or none is known yet.
    var noCommands: String {
        commands.isEmpty ? (agent == nil ? "Its commands show once it has started." : "\(name) lists no commands here.") : "No command of \(name) starts with that."
    }

    /// The agents something sees but does not launch, each with why.
    static var seenOnly: [(name: String, why: String)] {
        Registry.app.agents.filter { $0.builder == nil }.map { ($0.name, $0.unavailable ?? "something only sees \($0.name).") }
    }

    /// The presence of this conversation's agent now.
    var presence: Presence { presence(of: session) }

    /// The presence of the agent of `session` now: the card's, or a space's in the sidebar.
    func presence(of session: Session) -> Presence {
        _ = beat
        return Presence(Presence.Facts(name: name(of: session), installed: session.kind.flatMap { installed[$0] }, waking: session.launching,
                                       failure: session.failure, stopped: session.stopped, resumes: resumes(session)),
                        agent: session.agent, turn: session.turn, now: clock())
    }

    /// Whether the card is drawn: open, and on the blank page (whose field is its own) only while it has a
    /// conversation to show.
    var cardShown: Bool { open && (place != .blank || threadShown || building) }

    /// The card's title: the open space's, else where the person is.
    var title: String {
        switch place {
        case .space(let title, _, _): AssistantModel.clean(title)
        case .blank: "New Space"
        case .templates: "Templates"
        }
    }

    /// Whether the person is in a space, where the chip's menus say "this space".
    var inSpace: Bool { if case .space = place { true } else { false } }
    /// The field's name for VoiceOver: whose assistant the message goes to, inside a space.
    var messageLabel: String { inSpace ? "Message to " + Words.possessive(title) + " assistant" : "Message" }

    /// The caption of a message written here, which the conversation leaves out.
    var here: String? { AssistantModel.shown(AssistantModel.context(place, home: places.home.path) + "\n").caption }

    /// The model chosen for this conversation, else the one its agent reported, by the name its options give; and its
    /// effort likewise. The choice comes first: an agent reports a new model only with its next turn.
    var modelWords: (model: String, effort: String?) {
        let offered = offered
        if ownModel { return ("Its own model", nil) }
        let model = (session.model ?? agent?.model).map { Words.model($0, in: offered.model) } ?? "Default model"
        let effort = (session.effort ?? agent?.effort).map { e in offered.effort?.first { $0.value == e }?.label ?? Option.effortLabels[e] ?? e }
        return (model, effort)
    }

    /// The model and effort `kind` would build with: modelWords for the kind chosen; for another, "Its own model" when
    /// it picks its own, else "Default model" until it has run, since something reads no agent's settings.
    func modelWords(of kind: String) -> (model: String, effort: String?) {
        if kind == self.kind { return modelWords }
        return (Registry.app.limits[kind]?.contains("model") == true ? "Its own model" : "Default model", nil)
    }

    /// Whether Send sends now, and whether it is Stop: while the agent works and nothing is written.
    var canSend: Bool { kind != nil && !blocked && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// Not while its model does not answer: the card says Ended, and Try Again is the way on; nor while it waits for
    /// an answer, which its request's window gives.
    var stops: Bool { (light == .working || quickWorks(on: place.space)) && presence.stuck != .cannotReachModel && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The notice above the composer, the most pressing first; nil when nothing blocks or waits.
    var notice: Notice? {
        if noAgent {
            return Notice(symbol: "powerplug", title: noBuilder, text: "something launches the coding agent you already use.", bad: true,
                          actions: [.init(title: "How to Get One", run: howTo), .init(title: "Look Again", run: lookAgain)])
        }
        // What went wrong in the agent's or the engine's own words, which the notice says when its sentence does not.
        let said = failure ?? problem.map { "\(name) said: “\($0)”" }
        if signedOut {
            return Notice(symbol: "exclamationmark.triangle", title: "\(name) isn’t signed in to its model.",
                          text: [said, "Open Terminal, type \(command) and sign in, then click Try Again."].compactMap { $0 }.joined(separator: " "), bad: true,
                          actions: [.init(title: "Copy Command", run: copyCommand), .init(title: "Try Again", run: tryAgain)])
        }
        let presence = presence
        if let notice = presence.notice, let stuck = presence.stuck {
            // The one or two things that help; a state nobody reads has none, since something will not guess.
            let actions: [Notice.Action] = switch stuck {
            case .missing: [.init(title: "How to Get One", run: howTo)] + (others.isEmpty ? [] : [.init(title: "Use Another Agent", run: chooseAnother)])
            case .crashed: [.init(title: "Start Again", run: startAgain)]
            case .cannotReachModel, .undelivered: session.last == nil ? [] : [.init(title: "Try Again", symbol: "arrow.clockwise", run: tryAgain)]
            case .unknown: []
            }
            let symbol = stuck == .unknown ? "questionmark" : stuck == .missing ? "powerplug" : "exclamationmark.triangle"
            // With no other agent to choose, the notice names only the way that is left.
            var text = stuck == .missing && others.isEmpty ? "something launches the agent you already use. Install \(name)." : notice.text
            // A crash is said as quitting; what the agent wrote as it went is no sentence for the person.
            if stuck != .crashed, let problem, let said, !text.contains(problem) { text += (text.isEmpty ? "" : " ") + said }
            return Notice(symbol: symbol, title: notice.title, text: text, bad: stuck != .unknown, actions: actions)
        }
        if presence.state == .wait {
            return Notice(symbol: "checkmark.shield", title: "\(name) is waiting for your answer",
                          text: "The request is in its own window, outside the space. Only you can answer it there.", bad: false,
                          actions: [.init(title: "Show Request \(Keys.shown("showreq"))", run: showRequest)])
        }
        if unkept {
            return Notice(symbol: "exclamationmark.triangle", title: "Couldn’t keep this space’s journal",
                          text: "Its activity is not saved.", bad: true, actions: [])
        }
        return nil
    }
}

/// The card's hosting view in the glass, which gives it its frame: grown from the sticker's corner, shrunk back into it.
/// It takes only the clicks on the card: those in its margin, where the shadow falls, reach the space under it.
final class CardHost: NSHostingView<AssistantCard> {
    /// Called when what the card shows asks for another size: the glass places it again.
    var resized: () -> Void = {}

    convenience init(model: AssistantModel) {
        self.init(rootView: AssistantCard(model: model))
        sizingOptions = [.intrinsicContentSize]
        // Clipped while it grows from the sticker, rounded wider than the card so the card itself is never cut.
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = Look.card + 10
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        resized()
    }

    /// Esc in the card closes the "/" list when it shows, else reduces the card, as Reduce does.
    override func cancelOperation(_ sender: Any?) {
        if rootView.model.slashed != nil { rootView.model.commandPick = -1 } else { rootView.model.escape() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let inside = convert(point, from: superview), card = bounds.insetBy(dx: AssistantCard.margin, dy: AssistantCard.margin)
        return rootView.model.cardShown && !isHidden && card.contains(inside) ? super.hitTest(point) : nil
    }
}
