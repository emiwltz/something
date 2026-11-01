// A space's level with the person's agents (None · Watch · Talk · Run), as the app says and asks it: each level's
// words, the level a description suggests, New Space's card (the choice made there is the consent), and the level
// sheet a space made elsewhere shows at its first opening; both draw the sentence (Sentence.swift). The rights a level
// grants are the core's (Grant.Level); here are only its words.
import AppKit
import SomethingAgents
import SomethingCore
import SwiftUI

extension Grant.Level {
    var title: String { rawValue.capitalized }

    /// The level in the sentence and its menus: None, Talk and Run stay the contract's nouns.
    var word: String {
        switch self {
        case .none: "not see"
        case .watch: "watch"
        case .talk: "talk to"
        case .run: "start"
        }
    }

    /// What the level's row says in its menu.
    var note: String {
        switch self {
        case .none: "Sees nothing."
        case .watch: "Sees your agents."
        case .talk: "Sees and writes to them."
        case .run: "Sees, writes, starts them."
        }
    }

    /// What the level lets a space do, in one sentence.
    var sentence: String {
        switch self {
        case .none: "It shows no agent."
        case .watch: "It sees your agents: their state, folder and last messages."
        case .talk: "It sees them and writes to them: send a message, stop one, change its model."
        case .run: "It sees them, writes to them, and starts one in a folder you pick."
        }
    }

    /// The level a description in English suggests: starting an agent, then writing to one, then only seeing them,
    /// which words that ask who is waiting or working do too; nil when the words say nothing of agents.
    static func guessed(_ words: String) -> Grant.Level? {
        func says(_ pattern: String) -> Bool { words.range(of: "\\b(\(pattern))\\b", options: [.regularExpression, .caseInsensitive]) != nil }
        return says("start|starts|launch|launches|run|runs|spin up") ? .run : says("talk|tell|send|write to|ask|nudge") ? .talk
            : says("agent|agents|who is (waiting|working)|who['’]s (waiting|working)|waiting for me|who needs me") ? .watch : nil
    }

    /// A hint the person sees and changes in one click; words it does not know suggest `otherwise` (Settings › Agents).
    static func guess(_ words: String, otherwise: Grant.Level = .none) -> Grant.Level { guessed(words) ?? otherwise }
}

enum Levels {
    /// What a level never covers, said under the sentence.
    static let fine = "Whatever an agent asks still waits for you."
    /// What a person must read before choosing Run, when an agent here acts without asking; else nil.
    static var runWarning: String? { Ask.warning(for: "launch").map { $0 + "." } }
    /// That warning under Run, when there is one.
    @ViewBuilder static var runNote: some View { if let runWarning { note(runWarning, warns: true) } }
    /// The one warning that replaces that line: at Talk, the agents the choice reaches that never ask, by their names;
    /// at Run, the agent it starts when that one never asks, or, with none named, what any launch may reach. Else nil.
    static func warning(_ choice: LevelChoice, agents: [Agent]) -> String? {
        func loose(_ kind: String) -> Bool { Registry.app.agent(kind).map { $0.neverAsks || $0.asksNothingByDefault } ?? false }
        let names: [String]
        switch choice.level {
        case .none, .watch: return nil
        case .run:
            guard let start = choice.start else { return runWarning }
            names = loose(start.kind) ? [Registry.app.name(of: start.kind)] : []
        case .talk:
            let reached = agents.filter { loose($0.kind) && $0.alive != false && $0.state != "sleep" && $0.state != "ended" && Rights.contains(choice.scope ?? .all, $0.folder) }
            names = reached.reduce(into: []) { names, agent in
                let name = agent.name ?? Registry.app.name(of: agent.kind)
                if !names.contains(name) { names.append(name) }
            }
        }
        guard let last = names.last else { return nil }
        if names.count == 1 { return "\(last) never asks: this space can make it act without you." }
        return "\(names.dropLast().joined(separator: ", ")) and \(last) never ask: this space can make them act without you."
    }
    static let sheetFine = "Whatever an agent asks still waits for you, in a window of your Mac: Allow Once or Deny. Its memory needs no permission."

    /// `text` under the choice, a quiet line after its mark: a warning, read before choosing, never an alarm; or, by a
    /// lock, what a level never covers.
    static func note(_ text: String, warns: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: warns ? "exclamationmark.triangle" : "lock").font(.system(size: 9.5)).accessibilityHidden(true)
            Text(text)
        }
        .font(warns ? Look.font(.ui, size: 12, weight: .medium).ui : Look.small.font.ui).foregroundStyle((warns ? Look.Token.ink : .ink3).ui)
        .fixedSize(horizontal: false, vertical: true)
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

/// New Space's card, under the field: "With your agents", whether the words pre-set it, the person chose it or it is
/// their default, and the sentence.
struct LevelCard: View {
    @Bindable var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("With your agents").font(Look.font(.ui, size: 12.5, weight: .semibold).ui).foregroundStyle(Look.Token.ink.ui)
                Spacer(minLength: 8)
                tag
            }
            Sentence("This space", choice: $model.choice, folders: Levels.folders(model.engine.state), home: model.places.home.path,
                     warning: model.warning, agents: model.entries.filter(\.enabled).map(\.id))
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 11, trailing: 14))
        .boxed(RoundedRectangle(cornerRadius: 12, style: .continuous), Look.Token.bg2.ui, ring: Look.Token.line.ui)
        .disabled(model.blocked)
    }

    /// Where the sentence comes from; a default can be changed where it is set.
    @ViewBuilder private var tag: some View {
        let words = Text(model.origin).font(Look.font(.ui, size: 11).ui).foregroundStyle(Look.Token.ink3.ui)
        if model.origin == AssistantModel.defaultOrigin {
            Button { Keys.send("defaults") } label: { words }.buttonStyle(.plain).help("Set in Settings")
        } else {
            words
        }
    }
}

/// The level sheet's choice while it is open, pre-set to what the page needs.
@Observable final class LevelAnswer {
    var choice: LevelChoice
    /// Whether Allow may be pressed: Run needs its folder.
    var ready: Bool { choice.level != .run || choice.folder != .none }
    init(_ choice: LevelChoice) { self.choice = choice }
}

/// What the level sheet holds under its title: the sentence. `changed` hears each change, once the view drew it.
struct LevelSheetView: View {
    @Bindable var answer: LevelAnswer
    let question: RightsQuestion, home: String, width: CGFloat, changed: () -> Void

    var body: some View {
        // The sheet's own line says what a level never covers.
        Sentence("This space", choice: $answer.choice, folders: question.folders, home: home,
                 warning: Levels.warning(answer.choice, agents: question.agents), space: question.name, locks: false)
            // As wide as the sheet's text, so that a sentence wraps there and the sheet measures its height.
            .frame(width: width, alignment: .leading)
            .padding(.top, 4)
            .onChange(of: answer.choice) { DispatchQueue.main.async(execute: changed) }
    }
}

extension Ask {
    /// The level sheet, not yet shown, and the answer it holds once it closed with Allow: "<Space> would like to work
    /// with your agents", where its page is, the sentence pre-set to what the page needs, and Run's folder. Allow
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
        let answer = LevelAnswer(LevelChoice(level: question.level, scope: question.scope, folder: question.folder.map { .path($0) } ?? .none))
        var refit: () -> Void = {}
        let choice = NSHostingView(rootView: LevelSheetView(answer: answer, question: question, home: home, width: text) { refit() })
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
        return (sheet, {
            let chosen = answer.choice
            // A scope left as the page declares it follows the page: only a change of the person's is kept.
            return RightsAnswer(level: chosen.level, folder: chosen.level == .run ? chosen.folder.path : nil, blank: chosen.level == .run && chosen.folder == .blank,
                                scope: chosen.scope == question.scope ? nil : chosen.scope, start: chosen.start)
        })
    }

    /// How wide the level sheet is, as the mockup's sheets.
    static let rightsWidth: CGFloat = 440
}
