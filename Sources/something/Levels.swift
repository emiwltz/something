// A space's level with the person's agents (None · Watch · Talk · Run), as the app says and asks it: each level's
// words, the level a description suggests, New Space's row (the choice made there is the consent), and the one-line
// level sheet a space made elsewhere shows at its first opening. The rights a level grants are the core's
// (Grant.Level); here are only its words and its controls.
import AppKit
import SomethingCore
import SwiftUI

extension Grant.Level {
    var title: String { rawValue.capitalized }

    /// What the level lets a space do, in one sentence.
    var sentence: String {
        switch self {
        case .none: "It shows no agent."
        case .watch: "It sees your agents: their state, folder and last messages."
        case .talk: "It sees them and writes to them: send a message, stop one, change its model."
        case .run: "It sees them, writes to them, and starts one in a folder you pick."
        }
    }

    /// The level a description in English suggests: starting an agent, then writing to one, then only seeing them.
    /// A hint the person sees and changes in one click; words it does not know suggest `otherwise` (Settings › Agents).
    static func guess(_ words: String, otherwise: Grant.Level = .none) -> Grant.Level {
        func says(_ pattern: String) -> Bool { words.range(of: "\\b(\(pattern))\\b", options: [.regularExpression, .caseInsensitive]) != nil }
        return says("start|starts|launch|launches|run|runs|spin up") ? .run : says("talk|tell|send|write to|ask|nudge") ? .talk
            : says("agent|agents") ? .watch : otherwise
    }

    /// The line something adds to the first message of a build, for the assistant to declare exactly these rights. Run's
    /// folder is always known by then: New Space sends only once it is chosen.
    func line(folder: String?, home: String) -> String {
        "[something] With your agents: \(title)\(self == .run ? folder.map { ", in " + Words.path($0, home: home) } ?? "" : "")."
    }
}

enum Levels {
    /// What a level never covers, said under the choice.
    static let fine = "Nothing else to allow when it opens. Whatever an agent asks still waits for you."
    /// What a person must read before choosing Run, when an agent here acts without asking; else nil.
    static var runWarning: String? { Ask.warning(for: "launch").map { $0 + "." } }
    /// That warning under Run, when there is one.
    @ViewBuilder static var runNote: some View { if let runWarning { note(runWarning, warns: true) } }
    static let sheetFine = "Whatever an agent asks still waits for you, in a window of your Mac: Allow Once or Deny. Its memory needs no permission."

    /// `text` under the choice, a quiet line after its mark: a warning, read before choosing, never an alarm; or, by a
    /// lock, what a level never covers.
    static func note(_ text: String, warns: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: warns ? "exclamationmark.triangle" : "lock").font(.system(size: 9.5)).accessibilityHidden(true)
            Text(text)
        }
        .font(Look.small.font.ui).foregroundStyle((warns ? Look.Token.ink2 : .ink3).ui).fixedSize(horizontal: false, vertical: true)
    }

    /// The folders the Mac's agents work in, as `state` knows them, each once, in order: Run's choices.
    static func folders(_ state: SomethingCore.State) -> [String] {
        Array(Set(state.agents.compactMap(\.folder))).sorted().prefix(8).map { $0 }
    }

    /// `folder`, as a page declares it ("~/code/shop"), made absolute when it is a folder on this Mac; else nil.
    static func onThisMac(_ folder: String?, home: URL) -> String? {
        var directory: ObjCBool = false
        guard let path = folder.flatMap({ Declaration.expand($0, home: home) }), FileManager.default.fileExists(atPath: path, isDirectory: &directory),
              directory.boolValue else { return nil }
        return path
    }

    /// Asks for a folder in the Mac's open panel, as a sheet on the key window (or alone without one), and gives it
    /// to `chosen`; nothing when the person cancels.
    static func chooseFolder(_ chosen: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        (panel.canChooseDirectories, panel.canChooseFiles, panel.prompt) = (true, false, "Choose")
        panel.message = "The folder where agents this space starts will work."
        let picked = { (answer: NSApplication.ModalResponse) in if answer == .OK, let url = panel.url { chosen(url.path) } }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: picked) } else { picked(panel.runModal()) }
    }
}

/// The four levels side by side (Segments), read by VoiceOver as "With your agents: Watch". As wide as its words, or
/// as its column (`wide`, Info's).
struct LevelPicker: View {
    let level: Binding<Grant.Level>
    var wide = false

    var body: some View {
        Segments(title: "With your agents", options: Grant.Level.allCases.map { .init(value: $0.rawValue, label: $0.title) },
                 chosen: level.wrappedValue.rawValue, set: { level.wrappedValue = Grant.Level(rawValue: $0) ?? .none }, wide: wide)
    }
}

/// Run's folder: the folder in force, or Choose Folder…; its menu lists the folders the Mac's agents work in.
struct FolderChip: View {
    let folder: String?, folders: [String], home: String
    let chosen: (String) -> Void

    var body: some View {
        Menu {
            Section("Where it may start them") {
                ForEach(folders, id: \.self) { path in
                    Toggle(Words.path(path, home: home), isOn: Binding(get: { path == folder }, set: { _ in chosen(path) }))
                }
            }
            Divider()
            Button("Choose Folder…") { Levels.chooseFolder(chosen) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder").font(.system(size: 10.5)).foregroundStyle(Look.Token.ink3.ui)
                Text(folder.map { Words.path($0, home: home) } ?? "Choose Folder…")
                    .font(folder == nil ? Look.font(.ui, size: 12, weight: .medium).ui : Look.font(.code, size: 12).ui)
                    .foregroundStyle(Look.Token.ink.ui).lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Look.Token.ink3.ui)
            }
            .padding(.horizontal, 8).frame(height: 26)
            .boxed(RoundedRectangle(cornerRadius: Look.control), Look.Token.bg.ui, ring: Look.Token.line2.ui)
        }
        .plainMenu()
        .accessibilityLabel("Folder: \(folder.map { Words.path($0, home: home) } ?? "none chosen")")
    }
}

/// New Space's row, under the field: "With your agents" and the four levels, Run's folder after them, the level's
/// sentence and whether the words pre-set it or the person chose it, and what the choice means.
struct LevelRow: View {
    @Bindable var model: AssistantModel

    var body: some View {
        let level = model.level, home = model.places.home.path
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // The picker says it to VoiceOver, with the choice.
                Text("With your agents").font(Look.font(.ui, size: 12.5, weight: .semibold).ui).foregroundStyle(Look.Token.ink.ui)
                    .accessibilityHidden(true)
                LevelPicker(level: Binding(get: { model.level }, set: { model.chosenLevel = $0 }))
                if level == .run {
                    Text("in").font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink3.ui)
                    FolderChip(folder: model.runFolder, folders: Levels.folders(model.engine.state), home: home) { (model.runFolder, model.chosenLevel) = ($0, .run) }
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(level.sentence).font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink2.ui)
                Spacer(minLength: 8)
                // Before any words, nothing was pre-set from them.
                if model.chosenLevel != nil || !model.draft.isEmpty {
                    Text(model.chosenLevel != nil ? "Your choice" : "Pre-set from your words").font(Look.font(.ui, size: 11).ui).foregroundStyle(Look.Token.ink3.ui)
                }
            }
            .accessibilityElement(children: .combine)
            if level == .run { Levels.runNote }
            Levels.note(Levels.fine)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .boxed(RoundedRectangle(cornerRadius: 12, style: .continuous), Look.Token.bg2.ui, ring: Look.Token.line.ui)
        .disabled(model.blocked)
    }
}

/// The level sheet's choice while it is open: the level, pre-set to what the page needs, and Run's folder.
@Observable final class LevelAnswer {
    var level: Grant.Level
    var folder: String?
    /// Whether Allow may be pressed: Run needs its folder.
    var ready: Bool { level != .run || folder != nil }
    init(level: Grant.Level, folder: String?) { (self.level, self.folder) = (level, folder) }
}

/// What the level sheet holds under its title: the four levels, the level's sentence, and for Run the folder agents
/// start in. `changed` hears each change, once the view drew it.
struct LevelSheetView: View {
    @Bindable var answer: LevelAnswer
    let folders: [String], home: String, width: CGFloat, changed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            LevelPicker(level: $answer.level)
            Text(answer.level.sentence).font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink2.ui)
                .fixedSize(horizontal: false, vertical: true)
            if answer.level == .run {
                HStack(spacing: 8) {
                    Text("Starts agents in").font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink2.ui)
                    FolderChip(folder: answer.folder, folders: folders, home: home) { answer.folder = $0 }
                    Spacer(minLength: 0)
                }
                Levels.runNote
            }
        }
        // As wide as the sheet's text, so that a sentence wraps there and the sheet measures its height.
        .frame(width: width, alignment: .leading)
        .padding(.top, 4)
        .onChange(of: answer.level) { DispatchQueue.main.async(execute: changed) }
        .onChange(of: answer.folder) { DispatchQueue.main.async(execute: changed) }
    }
}

extension Ask {
    /// The level sheet, not yet shown, and the answer it holds once it closed with Allow: "<Space> would like to work
    /// with your agents", where its page is, the four levels pre-set to what the page needs, and Run's folder. Allow
    /// waits for Run's folder; Return and Escape press Don't Allow, which holds the focus. Paths are shown from `home`.
    /// Built apart from showing it, so that a test can draw it without showing it.
    static func rights(_ question: RightsQuestion, home: String = NSHomeDirectory()) -> (sheet: Sheet, answer: () -> RightsAnswer) {
        let text = Sheet.column(width: rightsWidth)
        let lines = NSStackView()
        (lines.orientation, lines.alignment, lines.spacing) = (.vertical, .leading, 10)
        if let page = question.page {
            let words = NSMutableAttributedString(string: Words.path(page, home: home),
                                                  attributes: [.font: Look.font(.code, size: 11.5), .foregroundColor: Look.Token.ink3.color])
            if question.made {
                words.append(NSAttributedString(string: " · made just now", attributes: [.font: Look.medium.font, .foregroundColor: Look.Token.ink3.color]))
            }
            let place = NSTextField(labelWithAttributedString: words)
            (place.lineBreakMode, place.toolTip) = (.byTruncatingMiddle, page)
            place.widthAnchor.constraint(lessThanOrEqualToConstant: text).isActive = true
            lines.addArrangedSubview(place)
        } else if question.made {
            lines.addArrangedSubview(Sheet.label([("Your agent made this space.", false)], Look.small, color: .ink2, width: text))
        }
        if let description = question.description { lines.addArrangedSubview(Sheet.label([(description, false)], Look.medium, color: .ink2, width: text)) }
        if let last = lines.arrangedSubviews.last { lines.setCustomSpacing(14, after: last) }
        let answer = LevelAnswer(level: question.level, folder: question.folder)
        var refit: () -> Void = {}
        let choice = NSHostingView(rootView: LevelSheetView(answer: answer, folders: question.folders, home: home, width: text) { refit() })
        lines.addArrangedSubview(choice)
        choice.widthAnchor.constraint(equalToConstant: text).isActive = true
        let sheet = Sheet(icon: .symbol("person.2"), title: "\(question.space) would like to work with your agents", block: lines, fine: Levels.sheetFine,
                          actions: [.init(title: "Don’t Allow", role: .cancel, hint: "esc"), .init(title: "Allow", role: .primary)], width: rightsWidth)
        let allow = sheet.buttons[1]
        allow.enable(answer.ready)
        refit = { [weak sheet] in
            allow.enable(answer.ready)
            sheet?.refit()
        }
        return (sheet, { RightsAnswer(level: answer.level, folder: answer.level == .run ? answer.folder : nil) })
    }

    /// How wide the level sheet is, as the mockup's sheets.
    static let rightsWidth: CGFloat = 440
}
