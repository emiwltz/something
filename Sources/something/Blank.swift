// New Space (⌘N), the center when no space is open: the sign lands, "What do you want to make?", a flat field whose
// Return builds (⇧Return adds a line), who builds it and with which model, three suggestions that each send a whole
// sentence, and the first three templates with See All. Without a coding agent, the notice takes the field's place.
// While the assistant builds, the field holds the sentence sent and says what it does; the rest steps aside. The
// assistant's card stays away here (the page is its own composer), so when a turn ends without a new space, its reply
// stays above the field, to be answered there; a template's preview fills the page.
import AppKit
import SwiftUI

struct BlankView: View {
    /// Each suggestion, the sentence it sends and its plain icon.
    static let chips = [
        ("Who is waiting for me", "Make me a space that shows which of my agents are waiting for me, and lets me answer the ones I can.", "bell"),
        ("A morning brief of my agents", "Make me a space like a morning newspaper: what each of my agents did since yesterday.", "doc"),
        ("A small game for my breaks", "Make me a small game I can play in a minute between two tasks, with my best score kept.", "play"),
    ]
    static let placeholder = "A page that shows who is waiting for me, oldest first…"
    /// The field's width, and the page's widest, as the mockup's.
    static let width: CGFloat = 640, widest: CGFloat = 1010

    @Bindable var model: AssistantModel
    let library: Library, gallery: Gallery

    var body: some View {
        Group {
            if gallery.previewing != nil { GalleryView(library: library, model: gallery) } else { page }
        }
        .background(Look.Token.bg.ui)
    }

    private var page: some View {
        GeometryReader { window in
            ScrollView {
                let inner = max(0, window.size.width - 80), field = min(BlankView.width, inner)
                VStack(spacing: 0) {
                    hero(path: Words.path(model.places.spaces.path, home: model.places.home.path))
                    if model.noAgent {
                        if let notice = model.notice { NoticeView(notice: notice).frame(width: field).padding(.top, 30) }
                    } else {
                        if let reply { answer(reply).frame(width: field).padding(.top, 30) }
                        BuildField(model: model, sent: sent).frame(width: field).padding(.top, model.building ? 22 : reply == nil ? 30 : 14)
                        if model.building { building.frame(width: field).padding(.top, 14) } else { meta.frame(width: field).padding(.top, 8) }
                        if let notice = model.notice { NoticeView(notice: notice).frame(width: field).padding(.top, 14) }
                    }
                    if !model.building {
                        if !model.noAgent { suggestions.padding(.top, 22) }
                        templates(min(BlankView.widest, inner))
                    }
                }
                .padding(EdgeInsets(top: model.building ? 40 : 64, leading: 40, bottom: 64, trailing: 40))
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// The sign landing, the question, and where the space is made (folded away while it builds).
    private func hero(path: String) -> some View {
        VStack(spacing: 10) {
            Landing(motion: library.preferences.motion).frame(width: 76, height: 76).padding(.bottom, 10)
            Text("What do you want to make?").font(Look.titleXL.font.ui).kerning(-1.32).foregroundStyle(Look.Token.ink.ui)
                .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                // The mockup's line is 1.04 of the size; Fraunces's own leading is taller.
                .padding(.vertical, -6)
            if !model.building {
                // One text, so that a narrow window wraps it as a sentence; the path in code on the hover fill.
                Text(BlankView.where(path)).font(Look.font(.ui, size: 14).ui).foregroundStyle(Look.Token.ink2.ui).multilineTextAlignment(.center)
            }
        }
    }

    /// "Describe it in your words…", the folder `path` drawn as code.
    static func `where`(_ path: String) -> AttributedString {
        var code = AttributedString("\u{2009}\(path)\u{2009}")
        code.font = Look.font(.code, size: 11.5).ui
        code.foregroundColor = Look.Token.ink.ui
        code.backgroundColor = Look.Token.hover.ui
        return AttributedString("Describe it in your words. Your assistant builds it with you, in ") + code + AttributedString(".")
    }

    /// The sentence the build started with: the person's last message.
    private var sent: String? {
        guard model.building else { return nil }
        return model.rows.reversed().lazy.compactMap { if case .mine(_, let text) = $0 { text } else { nil } }.first ?? ""
    }

    /// The assistant's last words when its turn ended without a space (a question, an error): the last row of the
    /// conversation started here, when it is a reply.
    private var reply: String? { BlankView.reply(in: model) }

    static func reply(in model: AssistantModel) -> String? {
        guard !model.building, model.threadShown else { return nil }
        return model.rows.reversed().lazy.compactMap { row -> String?? in
            switch row { case .reply(let text): text; case .mine: .some(nil); default: nil }
        }.first ?? nil
    }

    /// `text` in the agent's voice, read only, as the card draws a reply.
    private func answer(_ text: String) -> some View {
        Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
            .font(Look.font(.voice, size: 14).ui).lineSpacing(3).foregroundStyle(Look.Token.ink2.ui)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .accessibilityLabel("Your assistant: \(text)")
    }

    /// What a suggestion does: it sends its whole sentence, the draft kept.
    static func suggest(_ chip: (String, String, String), to model: AssistantModel) { model.send(chip.1) }

    /// Who builds it, the model and its effort, and what Return does.
    private var meta: some View {
        HStack(spacing: 1) {
            Text("Built by").padding(.trailing, 3)
            MenuChip(label: "Agent that builds: \(model.name)") {
                Image(nsImage: Sign.miniEyes(.listen)).renderingMode(.template).frame(width: 16, height: 10)
                Text(model.name)
            } items: { AgentMenu(model: model) }
            Text("·").padding(.horizontal, 3)
            let words = model.modelWords
            MenuChip(label: "Model: \(words.model)\(words.effort.map { ", effort \($0)" } ?? "")") {
                Text(words.model) + Text(words.effort.map { " " + $0 } ?? "").fontWeight(.regular).foregroundColor(Look.Token.ink3.ui)
            } items: {
                Text(words.model)
                if let effort = words.effort { Text("Effort: \(effort)") }
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Key("↵"); Text("to build")
                Text("·").padding(.horizontal, 3)
                Key("⇧↵"); Text("new line")
            }
            .accessibilityElement(children: .combine)
        }
        .font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink3.ui)
        .padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 2))
        .disabled(model.blocked)
    }

    /// What the assistant does now, under the sentence it was sent, until the space opens.
    private var building: some View {
        HStack(spacing: 8) {
            Image(nsImage: Sign.miniEyes(.think, template: false)).frame(width: 18, height: 12)
            if case .working(let step, _) = model.presence.now { Text(step).foregroundStyle(Look.Token.ink.ui).lineLimit(1) }
            Text("It opens here when it is ready. You will be asked what it may do.").lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(Look.font(.ui, size: 12.5).ui).foregroundStyle(Look.Token.ink2.ui)
        .padding(.horizontal, 8)
    }

    private var suggestions: some View {
        HStack(spacing: 8) {
            ForEach(BlankView.chips, id: \.0) { chip in
                Button { BlankView.suggest(chip, to: model) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: chip.2).font(.system(size: 11)).foregroundStyle(Look.Token.ink3.ui)
                        Text(chip.0)
                    }
                    .font(Look.font(.ui, size: 12.5, weight: .medium).ui).foregroundStyle(Look.Token.ink2.ui)
                    .padding(.leading, 10).padding(.trailing, 13).frame(height: 32)
                    .background(Capsule(style: .circular).strokeBorder(Look.Token.line2.ui))
                    .contentShape(Capsule(style: .circular))
                }
                .buttonStyle(.plain)
                .disabled(model.kind == nil || model.blocked)
                .help(chip.1)
                .accessibilityLabel(chip.0)
            }
        }
    }

    /// "Or start from a template", See All, and the first three cards, in rows that fit `width`.
    private func templates(_ width: CGFloat) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Text("Or start from a template").font(Look.font(.title, size: 19, weight: .semibold).ui).kerning(-0.285)
                    .foregroundStyle(Look.Token.ink.ui).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button { library.select(.templates) } label: {
                    HStack(spacing: 6) { Text("See All"); Key(Keys.shown("tpls")) }.chip()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See All Templates")
            }
            TemplateGrid(cards: Array(library.templates.prefix(3)), columns: GalleryView.columns(width), library: library, model: gallery)
        }
        .frame(width: width)
        .padding(.top, 54)
        .opacity(library.templates.isEmpty ? 0 : 1)
    }
}

/// A key as the mockup draws it: Onest 10.5 medium in ink3, on the hover fill.
private struct Key: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key).font(Look.font(.ui, size: 10.5, weight: .medium).ui).kerning(0.2).foregroundStyle(Look.Token.ink3.ui)
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(Look.Token.hover.ui, in: RoundedRectangle(cornerRadius: 5))
    }
}

/// New Space's field: flat, bg2 in a line2 ring that turns ink2 with the focus, no shadow; Onest 16, two lines high,
/// and Build, a disc greyed while nothing is written. Return builds, ⇧Return adds a line, and Return that confirms
/// what an input method composes builds nothing. While it builds it holds `sent`, read only.
struct BuildField: View {
    @Bindable var model: AssistantModel
    let sent: String?
    @FocusState private var typing: Bool

    var body: some View {
        let busy = sent != nil, shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        HStack(alignment: .bottom, spacing: 10) {
            Group {
                if let sent {
                    Text(sent).foregroundStyle(Look.Token.ink2.ui).lineLimit(1...3).frame(maxWidth: .infinity, minHeight: 26, alignment: .topLeading)
                } else {
                    TextField("", text: $model.draft, prompt: Text(BlankView.placeholder).foregroundStyle(Look.Token.ink3.ui), axis: .vertical)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Look.Token.ink.ui)
                        .lineLimit(2...6)
                        .frame(minHeight: 50, alignment: .topLeading)
                        .focused($typing)
                        .disabled(model.blocked)
                        .accessibilityLabel("Describe the space you want")
                        .onChange(of: model.wantsFocus, initial: true) {
                            if model.wantsFocus { (typing, model.wantsFocus) = (true, false) }
                        }
                        .onKeyPress(.return, phases: .down) { press in
                            let marked = (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true
                            switch Field.onReturn(shift: press.modifiers.contains(.shift), marked: marked) {
                            case .compose: return .ignored
                            case .send: model.send()
                            case .newline:
                                if !NSApp.sendAction(#selector(NSTextView.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil) { model.draft += "\n" }
                            }
                            return .handled
                        }
                }
            }
            .font(Look.font(.ui, size: 16).ui).kerning(-0.16).lineSpacing(4.5)
            .padding(.vertical, 2)
            if !busy {
                Button { model.send() } label: {
                    Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold)).foregroundStyle(Look.Token.actfg.ui)
                        .frame(width: 32, height: 32)
                        .background(Look.Token.act.ui.opacity(model.canSend ? 1 : 0.18), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canSend)
                .help("Build (Return)")
                .accessibilityLabel("Build")
            }
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 12))
        .background(busy ? Color.clear : Look.Token.bg2.ui, in: shape)
        .overlay(shape.strokeBorder(busy ? Look.Token.line.ui : typing ? Look.Token.ink2.ui : Look.Token.line2.ui))
    }
}

/// The sign of New Space, 76 points: it lands as the page opens (its corners one after the other, then its eyes),
/// then listens. Under Reduced motion it is simply there.
private struct Landing: NSViewRepresentable {
    let motion: Look.Motion

    func makeNSView(context: Context) -> SignView {
        let sign = SignView(.listen, side: 76)
        sign.name = "something"
        sign.motion = motion
        sign.arrive()
        return sign
    }

    func updateNSView(_ sign: SignView, context: Context) {
        if sign.motion != motion { sign.motion = motion }
    }
}
