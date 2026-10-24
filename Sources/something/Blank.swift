// New Space (⌘N), the center when no space is open: the sign lands, "What do you want to make?", a flat field whose
// Return builds (⇧Return adds a line), who builds it and with which model, three suggestions that each send a whole
// sentence, and the first three templates with See All. Without a coding agent, the notice takes the field's place.
// While the assistant builds, the field holds the sentence sent, the ladder under it says what it does (Ladder.swift),
// and the rest steps aside; a build stopped leaves its ladder and the sentence back in the field. The assistant's card
// stays away here (the page is its own composer), so when a build asked here ends without a new space while the page
// is shown, its reply stays above the field, to be answered there; a template's preview fills the page.
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
    /// The conversation shown when the page opened, and its length then: a reply older than the page belongs to another
    /// moment.
    let opened: ObjectIdentifier, since: Int

    init(model: AssistantModel, library: Library, gallery: Gallery) {
        (self.model, self.library, self.gallery) = (model, library, gallery)
        (opened, since) = (ObjectIdentifier(model.session), model.rows.count)
    }

    /// The first row newer than the page: every row of a conversation begun since it opened (another builder chosen in
    /// Built by, New Conversation, a wake on a new one) is.
    var start: Int { ObjectIdentifier(model.session) == opened ? since : 0 }

    var body: some View {
        Group {
            if gallery.previewing != nil { GalleryView(library: library, model: gallery) } else { page }
        }
        .background(Look.Token.bg.ui)
    }

    private var page: some View {
        GeometryReader { window in
            ScrollView {
                let inner = max(0, window.size.width - 80), field = min(BlankView.width, inner), ladder = model.ladder
                VStack(spacing: 0) {
                    hero(ladder)
                    if model.noAgent {
                        if let notice = model.notice { NoticeView(notice: notice).frame(width: field).padding(.top, 30) }
                    } else {
                        if let reply, ladder == nil { answer(reply).frame(width: field).padding(.top, 30) }
                        BuildField(model: model, sent: sent).frame(width: field).padding(.top, model.building ? 34 : reply == nil || ladder != nil ? 33.5 : 14)
                        // While it builds, Built by keeps its place unseen, as the mockup's.
                        meta.frame(width: field).padding(.top, 8).opacity(model.building ? 0 : 1)
                            .allowsHitTesting(!model.building).accessibilityHidden(model.building)
                        if let ladder { LadderView(ladder: ladder, model: model, motion: library.preferences.motion).frame(width: field).padding(.top, 22) }
                        // The question the page answers needs no notice sending the person to the panel.
                        if let notice = model.notice, model.asked == nil { NoticeView(notice: notice).frame(width: field).padding(.top, 14) }
                    }
                    if !model.building {
                        if !model.noAgent { suggestions.padding(.top, 22) }
                        templates(min(BlankView.widest, inner))
                    }
                }
                .padding(EdgeInsets(top: ladder != nil ? 40 : 64, leading: 40, bottom: 64, trailing: 40))
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// The sign landing, its eyes following the build, the question, and where the space is made (folded away while
    /// it builds).
    private func hero(_ ladder: Ladder?) -> some View {
        VStack(spacing: 10) {
            PageSign(state: model.building ? ladder?.eyes == .wait ? .listen : ladder?.eyes ?? .think : .listen, joy: ladder?.done == true,
                     side: 76, lands: true, motion: library.preferences.motion).padding(.bottom, 10)
            Text("What do you want to make?").font(Look.titleXL.font.ui).kerning(-1.32).foregroundStyle(Look.Token.ink.ui)
                .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                // The mockup's line is 1.04 of the size; Fraunces's own leading is taller.
                .padding(.vertical, -6)
            if !model.building {
                // One text, so that a narrow window wraps it as a sentence; the path in code on the hover fill.
                Text(BlankView.where(model.folder)).font(Look.font(.ui, size: 14).ui).foregroundStyle(Look.Token.ink2.ui).multilineTextAlignment(.center)
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

    /// The assistant's last words when a build asked here ended without a space (a question, an error), while the page
    /// stays New Space (a space made is opening).
    private var reply: String? { library.selection == .newSpace ? BlankView.reply(in: model, since: start) : nil }

    /// The last reply, when it came at or after row `since` and answers a message sent from the blank page; else nil.
    static func reply(in model: AssistantModel, since: Int) -> String? {
        let rows = model.rows
        guard !model.building, let at = rows.lastIndex(where: { if case .reply = $0 { true } else { false } }), at >= since,
              case .reply(let text) = rows[at], !rows[at...].contains(where: { if case .mine = $0 { true } else { false } }),
              case .mine(let caption, _)? = rows[..<at].last(where: { if case .mine = $0 { true } else { false } }),
              caption == "on the blank page" else { return nil }
        return text
    }

    /// `text` in the agent's voice, read only, as the card draws a reply.
    private func answer(_ text: String) -> some View {
        Text(AssistantCard.markdown(text))
            .font(Look.font(.voice, size: 14).ui).lineSpacing(3).foregroundStyle(Look.Token.ink2.ui)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .accessibilityLabel("Your assistant: \(text)")
    }

    /// Who builds it, the model and its effort, and what Return does.
    private var meta: some View {
        HStack(spacing: 1) {
            Text("Built by").padding(.trailing, 3)
            MenuChip(label: "Agent that builds: \(model.name)") {
                Image(nsImage: Sign.miniEyes(.listen)).renderingMode(.template).frame(width: 16, height: 10)
                Text(model.name)
            } items: { AgentMenu(model: model) }
            Text("·").padding(.horizontal, 3)
            ModelChip(model: model)
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

    private var suggestions: some View {
        HStack(spacing: 8) {
            ForEach(BlankView.chips, id: \.0) { chip in
                // The whole sentence is sent, the draft kept.
                Button { model.send(chip.1) } label: {
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
struct Key: View {
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
                            return Field.returned(shift: press.modifiers.contains(.shift), marked: marked, model)
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
