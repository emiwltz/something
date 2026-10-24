// The assistant's card, 412 points at the bottom right of the center, over the space: its header (the eyes of its
// state, the space's title as the conversation menu, the state word, Reduce and the grip), the conversation (⌘J: your
// bubbles in ink, the agent's voice in Young Serif, tool lines in code, a line between days, the messages held for the
// turn's end outlined with Take Back), one notice when it is stuck or waits for you, the present-tense line while it
// works, and the composer: the agent and model chips, Point's slot, the conversation toggle, the held messages' strip
// while the conversation is folded, and a flat field whose Send turns into Stop (New Space reuses it and the notice).
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
                if model.threadShown { conversation }
                if let notice = model.notice { NoticeView(notice: notice).padding(EdgeInsets(top: 2, leading: 10, bottom: 8, trailing: 10)) }
                if let now = model.presence.now { nowLine(now) }
                if model.place != .blank { composer }
            }
            .frame(width: AssistantCard.width)
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
                        Text(model.title).font(Look.font(.ui, size: 13, weight: .semibold).ui).foregroundStyle(Look.Token.ink.ui)
                        Chevron()
                    }
                    .padding(.horizontal, 6).frame(height: 22).contentShape(Rectangle())
                }
                .plainMenu()
                .accessibilityLabel("Conversation menu")
                Text(presence.header).font(Look.small.font.ui).foregroundStyle(Look.Token.ink2.ui).lineLimit(1).padding(.leading, 6)
            }
            Spacer(minLength: 0)
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
            // Quiet eyes in ink3, red only when stuck; while it works they stay level, the line below moving instead.
            Group {
                if presence.state == .think {
                    HStack(spacing: 3) { ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 1).frame(width: 5, height: 2) } }
                } else {
                    Image(nsImage: Sign.miniEyes(presence.state)).renderingMode(.template)
                }
            }
            .foregroundStyle(presence.state == .limit ? Look.Token.bad.ui : Look.Token.ink3.ui)
            .frame(width: 16, height: 10).position(x: 27, y: 27)
            .accessibilityElement().accessibilityLabel(presence.state.word)
        }
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
                ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in line(row) }
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
        // What scrolled up never shows under the header.
        .clipped()
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

    /// An agent's reply with its inline Markdown (bold, code, links), the line breaks kept; as written when it does not
    /// parse.
    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    /// A button's title split before its shortcut (a last word holding ⌘), nil when it has none.
    static func shortcut(of title: String) -> (String, String?) {
        guard let space = title.lastIndex(of: " "), title[space...].contains("⌘") else { return (title, nil) }
        return (String(title[..<space]), String(title[title.index(after: space)...]))
    }

    /// A message of the person's, held or sent, and the shape of its bubble.
    private static func mine(_ text: String) -> some View {
        Text(text).font(Look.font(.ui, size: 12.8).ui).lineSpacing(2.8).bubble()
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
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                AgentChip(model: model)
                ModelChip(model: model)
                PointChip()
                Spacer(minLength: 0)
                Button { model.threadShown.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left").font(.system(size: 11.5))
                        Text("\(model.messageCount)").foregroundStyle(Look.Token.ink.ui).monospacedDigit()
                        Image(systemName: "chevron.up").font(.system(size: 8, weight: .semibold)).rotationEffect(.degrees(model.threadShown ? 180 : 0))
                    }
                    .chip(pressed: model.threadShown)
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .help(Keys.tooltip("convo", "Conversation")).accessibilityLabel("Conversation")
                .accessibilityAddTraits(model.threadShown ? .isSelected : [])
            }
            .padding(.bottom, 4)
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
                .focused($typing)
                .disabled(model.blocked)
                .accessibilityLabel("Message")
                .onChange(of: model.wantsFocus, initial: true) {
                    if model.wantsFocus { (typing, model.wantsFocus) = (true, false) }
                }
                .onKeyPress(.return, phases: .down) { press in
                    let marked = (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true
                    return Field.returned(shift: press.modifiers.contains(.shift), marked: marked, model)
                }
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

/// One notice above the composer: its title, its sentence and the one or two things that help. Never Allow.
struct NoticeView: View {
    let notice: AssistantModel.Notice

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.symbol).font(.system(size: 12, weight: .medium))
                .foregroundStyle(notice.bad ? Look.Token.bad.ui : Look.Token.ink.ui)
                .frame(width: 24, height: 24)
                .background(Look.Token.bg2.ui, in: RoundedRectangle(cornerRadius: Look.control))
                .overlay(RoundedRectangle(cornerRadius: Look.control).strokeBorder(Look.Token.line.ui))
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
                                    .background(Look.Token.bg2.ui, in: RoundedRectangle(cornerRadius: Look.control + 1))
                                    .overlay(RoundedRectangle(cornerRadius: Look.control + 1).strokeBorder(Look.Token.line2.ui))
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
        .background(Look.Token.bg.ui, in: RoundedRectangle(cornerRadius: Look.card + 2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Look.card + 2, style: .continuous).strokeBorder(Look.Token.line2.ui))
    }
}

// MARK: Chips

/// A chip that opens a menu: what it shows and a chevron. The agent's (a dot of its state's colour and its name) and
/// the model's (the effort lighter).
struct MenuChip<Shown: View, Items: View>: View {
    let label: String
    @ViewBuilder let shown: () -> Shown
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu { items() } label: {
            HStack(spacing: 6) {
                shown()
                Chevron()
            }
            .chip()
        }
        .plainMenu()
        .accessibilityLabel(label)
    }
}

/// The agent chip: a dot of its state's colour and the builder's name, opening the agent menu. New Space shows it too.
struct AgentChip: View {
    let model: AssistantModel

    var body: some View {
        MenuChip(label: "Agent: \(model.name)") {
            Circle().fill(model.dot.ui).frame(width: 7, height: 7)
            Text(model.name)
        } items: { AgentMenu(model: model) }
    }
}

/// The model chip: the model and, lighter, the effort, opening their menu for this conversation alone. New Space
/// shows it too.
struct ModelChip: View {
    let model: AssistantModel

    var body: some View {
        let words = model.modelWords
        MenuChip(label: "Model: \(words.model)\(words.effort.map { ", effort \($0)" } ?? "")") {
            Text(words.model) + Text(words.effort.map { " " + $0 } ?? "").fontWeight(.regular).foregroundColor(Look.Token.ink3.ui)
        } items: {
            ForEach(model.modelMenu, id: \.header) { part in
                Section(part.header) {
                    ForEach(part.choices, id: \.value) { choice in
                        Toggle(choice.title, isOn: Binding(get: { choice.checked }, set: { _ in
                            choice.effort ? model.choose(effort: choice.value) : model.choose(model: choice.value)
                        }))
                    }
                    if let note = part.note { Button(note) {}.disabled(true) }
                }
            }
        }
    }
}

/// Point's place in the composer row: greyed, as in the toolbar, until its slice (T14) gives it an action.
struct PointChip: View {
    var body: some View {
        let enabled = Keys.command("pointpart")?.action != nil
        return HStack(spacing: 6) {
            Image(systemName: "scope").font(.system(size: 11.5))
            Text("Point")
        }
        .chip()
        // Whole beside a long model name: the row's spacer gives way first.
        .fixedSize()
        .opacity(enabled ? 1 : 0.32)
        .help(Keys.tooltip("pointpart", "Point"))
        .accessibilityLabel("Point")
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

    /// The mockup's .chip: 26 points high, 9 on each side, Onest 12 medium in ink2; `pressed` has the selection's fill.
    func chip(pressed: Bool = false) -> some View {
        font(Look.font(.ui, size: 12, weight: .medium).ui)
            .foregroundStyle(Look.Token.ink2.ui)
            .padding(.horizontal, 9).frame(height: 26)
            .background(pressed ? Look.Token.sel.ui : .clear, in: RoundedRectangle(cornerRadius: Look.control + 1))
            .contentShape(Rectangle())
    }
}

// MARK: Menus

/// The title's menu: the conversation and how it asks.
struct ConversationMenu: View {
    let model: AssistantModel

    var body: some View {
        Section("\(model.title) · its assistant") {
            Button("New Conversation") { model.newConversation() }
            Button("Stop") { model.stop() }.disabled(!model.working).help(model.presence.stopHelp)
            Button("Put to Sleep") { model.putToSleep() }.disabled(!model.canSleep)
        }
        if model.canAskEverything {
            Divider()
            Toggle("Ask Before Every Change", isOn: Binding(get: { model.askEverything }, set: { _ in model.toggleAsking() }))
        }
        Divider()
        Button("Look for Agents Again") { model.lookAgain() }
    }
}

/// The agent chip's menu: the builders found, then the agents something only sees, greyed with their reason.
struct AgentMenu: View {
    let model: AssistantModel

    var body: some View {
        Section("Builds this space") {
            ForEach(model.entries) { entry in
                Toggle(entry.title, isOn: Binding(get: { entry.checked }, set: { _ in model.choose(entry.id) }))
                    .disabled(!entry.enabled).help(entry.note ?? "")
            }
        }
        Section("Seen only") {
            ForEach(AssistantModel.seenOnly, id: \.name) { seen in
                Button("\(seen.name) · Can't build yet") {}.disabled(true).help(seen.why)
            }
        }
        Divider()
        let settings = Keys.command("settings")?.action
        Button(AssistantModel.defaultsTitle) { settings.map { _ = NSApp.sendAction($0, to: nil, from: nil) } }.disabled(settings == nil)
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

    /// The last item of the agent menu and of Build With ▸: Settings › Assistant, once Settings has it (G5).
    static let defaultsTitle = "Defaults for New Spaces…"

    /// One part of the model chip's menu: its header, the values to choose, checked when they are this
    /// conversation's, and a sentence when there is nothing to choose.
    struct ModelPart: Equatable {
        struct Choice: Equatable { let title: String, value: String, effort: Bool, checked: Bool }
        let header: String
        var choices: [Choice] = []
        var note: String?
    }

    /// The model chip's menu: the models, then the efforts, that the running agent lists, else those its kind last
    /// listed; before any, a sentence. A builder that picks its own model says so, and offers none.
    var modelMenu: [ModelPart] {
        let offered = offered, chosen = (model: session.model ?? agent?.model, effort: session.effort ?? agent?.effort)
        var model = ModelPart(header: "Model · this space")
        if ownModel {
            model.note = "\(name) picks its own model. Change it in \(name)'s settings."
        } else if let models = offered.model, !models.isEmpty {
            model.choices = models.map { .init(title: $0.label, value: $0.value, effort: false, checked: $0.value == chosen.model) }
        } else {
            model.note = "Default model · \(name) lists its models once it runs."
        }
        guard let efforts = offered.effort, !efforts.isEmpty, Registry.app.limits[kind ?? ""]?.contains("effort") != true else { return [model] }
        return [model, ModelPart(header: "Effort", choices: efforts.map { .init(title: $0.label, value: $0.value, effort: true, checked: $0.value == chosen.effort) })]
    }

    /// What the running agent lists, else what its kind last listed (Preferences.listed).
    var offered: Options {
        if let live = agent?.options, agent?.alive != false, live.model?.isEmpty == false { return live }
        return kind.flatMap { Preferences.at(places).listed[$0] } ?? Options()
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

    /// The caption of a message written here, which the conversation leaves out.
    var here: String? { AssistantModel.shown(AssistantModel.context(place, home: places.home.path) + "\n").caption }

    /// The colour of the agent chip's dot: ok while it can listen or works, red when stopped, ink3 asleep or unknown.
    var dot: Look.Token {
        switch presence.state {
        case .limit: .bad
        case .sleep, .unknown: .ink3
        default: .ok
        }
    }

    /// The model chosen for this conversation, else the one its agent reported, by the name its options give; and its
    /// effort likewise. The choice comes first: an agent reports a new model only with its next turn.
    var modelWords: (model: String, effort: String?) {
        let offered = offered
        if ownModel { return ("Its own model", nil) }
        let model = (session.model ?? agent?.model).map { m in offered.model?.first { $0.value == m }?.label ?? m } ?? "Default model"
        let effort = (session.effort ?? agent?.effort).map { e in offered.effort?.first { $0.value == e }?.label ?? Option.effortLabels[e] ?? e }
        return (model, effort)
    }

    /// The model and effort `kind` would build with: modelWords for the kind chosen; for another, "Its own model" when
    /// it picks its own, else "Default model" until it has run, since something reads no agent's settings.
    func modelWords(of kind: String) -> (model: String, effort: String?) {
        if kind == self.kind { return modelWords }
        return (Registry.app.limits[kind]?.contains("model") == true ? "Its own model" : "Default model", nil)
    }

    /// The messages of the conversation, the person's and the agent's.
    var messageCount: Int { AssistantModel.messages(rows) }

    /// Whether Send sends now, and whether it is Stop: while the agent works and nothing is written.
    var canSend: Bool { kind != nil && !blocked && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// Not while its model does not answer: the card says Stopped, and Try Again is the way on; nor while it waits for
    /// an answer, which its request's window gives.
    var stops: Bool { light == .working && presence.stuck != .cannotReachModel && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The notice above the composer, the most pressing first; nil when nothing blocks or waits.
    var notice: Notice? {
        if noAgent {
            return Notice(symbol: "powerplug", title: noBuilder, text: "something launches the coding agent you already use.", bad: true,
                          actions: [.init(title: "How to Get One", run: howTo), .init(title: "Look Again", run: lookAgain)])
        }
        // What went wrong in the agent's or the engine's own words, which the notice says when its sentence does not.
        let said = failure ?? problem.map { "\(name) said: “\($0)”" }
        if signedOut {
            return Notice(symbol: "exclamationmark.triangle", title: "\(name) isn't signed in to its model.",
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
            var text = notice.text
            // A crash is said as quitting; what the agent wrote as it went is no sentence for the person.
            if stuck != .crashed, let problem, let said, !text.contains(problem) { text += (text.isEmpty ? "" : " ") + said }
            return Notice(symbol: symbol, title: notice.title, text: text, bad: stuck != .unknown, actions: actions)
        }
        if presence.state == .wait {
            return Notice(symbol: "checkmark.shield", title: "\(name) is waiting for your answer",
                          text: "The request is in its own window, outside the space. Only you can answer it there.", bad: false,
                          actions: [.init(title: "Show Request \(Keys.shown("showreq"))", run: showRequest)])
        }
        if let ready, !working {
            return Notice(symbol: "checkmark", title: "“\(ready.title)” is ready.", text: "", bad: false,
                          actions: [.init(title: "Open", run: { [weak self] in self?.openReady(ready.id) })])
        }
        if unkept {
            return Notice(symbol: "exclamationmark.triangle", title: "Couldn't keep this space's journal",
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

    /// Esc in the card reduces it, as Reduce does.
    override func cancelOperation(_ sender: Any?) { rootView.model.escape() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let inside = convert(point, from: superview), card = bounds.insetBy(dx: AssistantCard.margin, dy: AssistantCard.margin)
        return rootView.model.cardShown && !isHidden && card.contains(inside) ? super.hitTest(point) : nil
    }
}
