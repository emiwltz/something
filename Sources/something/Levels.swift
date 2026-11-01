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

    /// A hint the person sees and changes in one click; words it does not know suggest `otherwise` (Settings › Permissions).
    static func guess(_ words: String, otherwise: Grant.Level = .none) -> Grant.Level { guessed(words) ?? otherwise }
}

enum Levels {
    /// What a level never covers, said under the sentence.
    static let fine = "Whatever an agent asks still waits for you."
    /// What a person must read before choosing Run, when an agent here acts without asking; else nil.
    static var runWarning: String? { Ask.warning(for: "launch").map { $0 + "." } }
    /// The one warning that replaces that line, at Talk and at Run: the agent it starts, when that one never asks, and
    /// those it can write to that never ask, by their titles; an agent it only reads is out of its reach. With no agent
    /// named at Run, what any launch may reach. `reach` is the agents' scope when it is not the sentence's. Else nil.
    static func warning(_ choice: LevelChoice, agents: [Agent], threads: [AgentThread] = [], reach: Scope? = nil) -> String? {
        guard choice.level >= .talk else { return nil }
        if choice.level == .run, choice.start == nil { return runWarning }
        func loose(_ kind: String) -> Bool { Registry.app.agent(kind).map { $0.neverAsks || $0.asksNothingByDefault } ?? false }
        let scope = reach ?? (choice.level == .run ? .folders([choice.folder.path].compactMap { $0 }) : choice.scope ?? .all)
        var names: [String] = [], kinds: [String] = []
        for (name, kind) in [choice.start.map { (Registry.app.name(of: $0.kind), $0.kind) }].compactMap({ $0 })
            + agents.filter({ $0.can.send && Rights.contains(scope, $0.folder) }).map({ agent in
                (AgentReading.title(agent, threads.first { $0.agent == agent.id }) ?? Registry.app.name(of: agent.kind), agent.kind)
            }) where loose(kind) && !names.contains(name) {
            (names, kinds) = (names + [name], kinds + [kind])
        }
        guard let last = names.last else { return nil }
        if names.count > 1 { return "\(names.dropLast().joined(separator: ", ")) and \(last) never ask: this space can make them act without you." }
        let usual = kinds.last.flatMap(Registry.app.agent)?.neverAsks == false
        return "\(last) never asks\(usual ? " by default" : ""): this space can make it act without you."
    }
    /// What a page keeps at Run besides starting, in a sheet, where its own scope stays: nil when that is only the
    /// folder, or nothing.
    static func also(_ choice: LevelChoice, home: String) -> String? {
        guard choice.level == .run, let scope = choice.scope, ![.folders([]), .folders([choice.folder.path].compactMap { $0 })].contains(scope) else { return nil }
        return "It also sees and writes to \(LevelChoice.agents(scope, home: home))."
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
    static func folders(_ state: SomethingCore.State) -> [String] { folders(state.agents) }
    static func folders(_ agents: [Agent]) -> [String] {
        Array(Set(agents.compactMap(\.folder))).sorted().prefix(8).map { $0 }
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

/// What the level sheet holds under its title: the sentence, and at Run what the page keeps besides starting: its own
/// scope, which the person reads here as nothing else says it. `changed` hears each change, once the view drew it.
struct LevelSheetView: View {
    @Bindable var answer: LevelAnswer
    let question: RightsQuestion, home: String, width: CGFloat, changed: () -> Void

    var body: some View {
        let chosen = answer.choice
        VStack(alignment: .leading, spacing: 6) {
            // The sheet's own line says what a level never covers.
            Sentence("This space", choice: $answer.choice, folders: question.folders, home: home,
                     warning: Levels.warning(chosen, agents: question.agents, reach: chosen.scope), agents: question.kinds.isEmpty ? nil : question.kinds,
                     space: question.name, locks: false, anyAgent: question.kinds.count != 1)
            if let also = Levels.also(chosen, home: home) {
                Text(also).font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink2.ui)
            }
        }
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
    static func rights(_ question: RightsQuestion, home: String = NSHomeDirectory()) -> (sheet: Sheet, answer: () -> LevelChoice) {
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
        let choice = choosing(question, home: home, width: text)
        lines.addArrangedSubview(choice.view)
        let sheet = Sheet(icon: .symbol("person.2"), title: "\(question.space) would like to work with your agents", block: lines, fine: Levels.sheetFine,
                          actions: [.init(title: "Don’t Allow", role: .cancel, hint: "esc"), .init(title: "Allow", role: .primary)], width: rightsWidth)
        choice.follow(sheet, sheet.buttons[1])
        return (sheet, choice.chosen)
    }

    /// The sentence as a part of a sheet, pre-set from `question`: its view; `follow`, which keeps a sheet's height and
    /// its action, which waits for Run's folder, with the sentence; and what the person chose.
    static func choosing(_ question: RightsQuestion, home: String, width: CGFloat) -> (view: NSView, follow: (Sheet, SheetButton) -> Void, chosen: () -> LevelChoice) {
        let answer = LevelAnswer(LevelChoice(level: question.level, scope: question.scope, start: question.kinds.count == 1 ? Grant.Start(kind: question.kinds[0]) : nil,
                                             folder: question.folder.map { .path($0) } ?? .none))
        var refit: () -> Void = {}
        let view = NSHostingView(rootView: LevelSheetView(answer: answer, question: question, home: home, width: width) { refit() })
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        return (view, { sheet, action in
            action.enable(answer.ready)
            refit = { [weak sheet] in
                action.enable(answer.ready)
                sheet?.refit()
            }
        }, {
            var chosen = answer.choice
            // A scope left as the page declares it follows the page: only a change of the person's is kept.
            if chosen.scope == question.scope { chosen.scope = nil }
            if chosen.level != .run { (chosen.start, chosen.folder) = (nil, .none) }
            return chosen
        })
    }

    /// How wide the level sheet is, as the mockup's sheets.
    static let rightsWidth: CGFloat = 440
}
