// New Space (⌘N), the center when no space is open: the sign lands, "What do you want to make?", a flat field whose
// Return builds (⇧Return adds a line) with, in its bar, who builds it and with which model, Build Now and Continue;
// under it, the sentence of what the space may do with your agents (Sentence.swift), pre-set from the words, which is the
// consent; and three suggestions that each fill the field. Without a coding agent, the notice takes the field's place.
// Build makes it a build of its own, which has its own page (BuildView.swift); the person may leave, it goes on, and its
// row in the sidebar brings it back here. A build stopped comes back to the field with its words, and a toast. The
// assistant's card stays away here (the page is its own composer), so when a build ends without a new space, its reply
// stays above the field, to be answered there; a template's preview fills the page.
import AppKit
import SwiftUI

struct BlankView: View {
    /// Each suggestion, the sentence it puts in the field and its plain icon.
    static let chips = [
        ("A countdown to Saturday", "A countdown to Saturday, with what my agents still have to finish before the weekend.", "sun.max"),
        ("A small game for my breaks", "A small game I can play in a minute between two tasks, with my best score kept.", "play"),
        ("My reading list", "My reading list: what I want to read, a line on each, the ones I finished folded away.", "bookmark"),
    ]
    static let placeholder = "A space that shows who is waiting for me, oldest first…"
    /// The field's width, as the mockup's.
    static let width: CGFloat = 640

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
            if gallery.previewing != nil {
                GalleryView(library: library, model: gallery)
            } else if let build = model.before {
                BuildView(build: build, model: model, library: library)
            } else {
                page
            }
        }
        .background(Look.Token.bg.ui)
    }

    private var page: some View {
        GeometryReader { window in
            ScrollView {
                let inner = max(0, window.size.width - 80), field = min(BlankView.width, inner)
                VStack(spacing: 0) {
                    hero
                    if model.noAgent {
                        if let notice = model.notice { NoticeView(notice: notice).frame(width: field).padding(.top, 30) }
                    } else {
                        if let reply { answer(reply).frame(width: field).padding(.top, 30) }
                        BuildField(model: model).frame(width: field).padding(.top, reply == nil ? 30 : 14)
                        LevelCard(model: model).frame(width: field).padding(.top, 12)
                        // The question the page answers needs no notice sending the person to the panel.
                        if let notice = model.notice, model.asked == nil { NoticeView(notice: notice).frame(width: field).padding(.top, 14) }
                        suggestions.padding(.top, 20)
                    }
                }
                .padding(EdgeInsets(top: 58, leading: 40, bottom: 64, trailing: 40))
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// The sign landing, the question, and where the space is made.
    private var hero: some View {
        VStack(spacing: 10) {
            PageSign(state: .listen, side: 52, lands: true, motion: library.preferences.motion).padding(.bottom, 10)
            Text("What do you want to make?").font(Look.titleXL.font.ui).kerning(-1.32).foregroundStyle(Look.Token.ink.ui)
                .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                // The mockup's line is 1.04 of the size; Fraunces's own leading is taller.
                .padding(.vertical, -6)
            // One text, so that a narrow window wraps it as a sentence; the path in code on the hover fill.
            Text(BlankView.where(model.folder)).font(Look.font(.ui, size: 14).ui).foregroundStyle(Look.Token.ink2.ui).multilineTextAlignment(.center)
        }
    }

    /// "Describe it in your words…", the folder `path` drawn as code.
    static func `where`(_ path: String) -> AttributedString {
        var code = AttributedString("\u{2009}\(path)\u{2009}")
        code.font = Look.font(.code, size: 11.5).ui
        code.foregroundColor = Look.Token.ink.ui
        code.backgroundColor = Look.Token.hover.ui
        return AttributedString("Describe it in your words. Your assistant builds it in ") + code + AttributedString(".")
    }

    /// The assistant's last words when a build asked here ended without a space (a question, an error), while the page
    /// stays New Space (a space made is opening).
    private var reply: String? { library.selection == .newSpace ? BlankView.reply(in: model, since: start) : nil }

    /// The last reply, when it came at or after row `since` and answers a message sent from the blank page; else nil.
    static func reply(in model: AssistantModel, since: Int) -> String? {
        let rows = model.rows
        guard !model.building, !model.halted, let at = rows.lastIndex(where: { $0.reply != nil }), at >= since, let text = rows[at].reply,
              !rows[at...].contains(where: { $0.mine != nil }), case .mine(let caption, _)? = rows[..<at].last(where: { $0.mine != nil }),
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
            // The label goes on an element of its own: given to the selectable text itself, SwiftUI resolved it through
            // the text's own label without end, and an assistive app reading the page crashed the app.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your assistant: \(text)")
    }

    private var suggestions: some View {
        HStack(spacing: 8) {
            ForEach(BlankView.chips, id: \.0) { chip in
                // The sentence fills the field, to change or build: its words pre-set the level unless one was chosen.
                Button {
                    model.draft = chip.1
                    model.wantsFocus = true
                } label: {
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

/// New Space's field: flat, bg2 in a line2 ring that turns ink with the focus, no shadow; Onest 16, two lines high;
/// its bar under the words: who builds it and with which model in one chip, then Build Now and Continue, greyed while
/// nothing is written. Return builds, ⇧Return adds a line, and Return that confirms what an input method composes
/// builds nothing.
struct BuildField: View {
    @Bindable var model: AssistantModel
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("", text: $model.draft, prompt: Text(BlankView.placeholder).foregroundStyle(Look.Token.ink3.ui), axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundStyle(Look.Token.ink.ui)
                .lineLimit(2...6)
                .frame(minHeight: 50, alignment: .topLeading)
                .accessibilityLabel("Describe the space you want")
                .composing(model, $typing)
                .font(Look.font(.ui, size: 16).ui).kerning(-0.16).lineSpacing(4.5)
                .padding(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))
            bar
        }
        .boxed(RoundedRectangle(cornerRadius: 12, style: .continuous), Look.Token.bg2.ui, ring: typing ? Look.Token.ink.ui : Look.Token.line2.ui)
    }

    /// The agent and its model in one chip, Build Now ⌘↵ and Continue ↵. Both build, until a reading of the words
    /// stands between them.
    private var bar: some View {
        HStack(spacing: 8) {
            AgentModelChip(model: model)
            Spacer(minLength: 8)
            Button { model.send() } label: {
                HStack(spacing: 5) {
                    Text("Build Now")
                    Key("⌘↵")
                }
                .font(Look.font(.ui, size: 12.5, weight: .medium).ui).foregroundStyle(Look.Token.ink2.ui)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canSend)
            .opacity(model.canSend ? 1 : 0.45)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Build Now (⌘Return)")
            .accessibilityLabel("Build Now")
            .padding(.trailing, 6)
            Button { model.send() } label: {
                HStack(spacing: 6) {
                    Text("Continue")
                    Text("↵").opacity(0.7)
                }
                .font(Look.font(.ui, size: 12.5, weight: .semibold).ui).foregroundStyle(Look.Token.actfg.ui)
                .padding(.leading, 12).padding(.trailing, 10).frame(height: 28)
                .background(Look.Token.act.ui.opacity(model.canSend ? 1 : 0.45), in: RoundedRectangle(cornerRadius: Look.control + 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canSend)
            .help("Continue (Return)")
            .accessibilityLabel("Continue")
        }
        .padding(EdgeInsets(top: 0, leading: 10, bottom: 8, trailing: 8))
    }
}
