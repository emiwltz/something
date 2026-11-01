// The sentence: what a space may do with the person's agents, "This space may [watch] [all your agents].", each bracket
// a menu whose rows explain themselves, then the lock line or one warning. New Space, the level sheet, the panel and
// Settings all draw this one view over a `LevelChoice`; what the choice means is the core's (`Grant`), and what it says
// to an assistant is `line`. A word's menu is the system's own, drawn by hand for its second lines, and can open from
// code once another word was picked.
import AppKit
import SomethingAgents
import SomethingCore
import SwiftUI

/// What a person says in the sentence: the level, which agents it shows (nil: all of them, unless a grant keeps the
/// page's own scope), the agent it starts, and where.
struct LevelChoice: Equatable {
    /// Where Run starts agents: not chosen yet, a folder, or a blank folder of the space's own.
    enum Folder: Equatable {
        case none, path(String), blank
        var path: String? { if case .path(let path) = self { path } else { nil } }
    }

    var level = Grant.Level.none
    var scope: Scope?
    var start: Grant.Start?
    var folder = Folder.none
}

extension LevelChoice {
    static func agents(_ scope: Scope?, home: String) -> String {
        guard case .folders(let folders)? = scope else { return "all your agents" }
        guard let first = folders.first else { return "only its own agents" }
        return folders.count == 1 ? "the agents in " + Words.path(first, home: home) : "the agents in \(folders.count) folders"
    }

    /// The agent the sentence names, its model after it once chosen; any agent while none is.
    var starts: String {
        guard let start else { return "any agent" }
        return ([Registry.app.name(of: start.kind)] + [start.model].compactMap { $0 }).joined(separator: " · ")
    }

    /// The folder as the sentence's word reads.
    func place(home: String) -> String {
        switch folder {
        case .none: "Choose Folder…"
        case .path(let path): Words.path(path, home: home)
        case .blank: "No Folder"
        }
    }

    /// The sentence in plain words: for the build's page and the summary.
    func said(home: String, subject: String = "This space") -> String {
        switch level {
        case .none: return "\(subject) may not see your agents."
        case .run:
            let place = folder == .none ? "" : folder == .blank ? " in a blank folder of its own" : " in " + place(home: home)
            return "\(subject) may start \(starts)\(place)."
        default: return "\(subject) may \(level.word) \(LevelChoice.agents(scope, home: home))."
        }
    }

    /// The line something adds to the first message of a build, for the assistant to declare exactly this. Run's folder
    /// is always known by then: New Space sends only once it is chosen.
    func line(home: String) -> String {
        var parts = [level.title]
        if level == .run {
            parts += [start.map { "starts " + Registry.app.name(of: $0.kind) }, folder == .blank ? "in a blank folder of its own" : folder.path.map { "in " + Words.path($0, home: home) }].compactMap { $0 }
        } else if level != .none, case .folders(let folders)? = scope {
            parts.append("in " + folders.map { Words.path($0, home: home) }.joined(separator: ", "))
        }
        return "[something] With your agents: \(parts.joined(separator: ", "))."
    }
}

/// A word's menu, apart from showing it: a test reads its rows, which the window server's menu keeps out of reach.
struct WordMenu {
    struct Row {
        let title: String
        var note: String? = nil, symbol: String? = nil, code = false, on = false
        /// A line before it, and what picking it does.
        var apart = false
        let pick: () -> Void
    }

    let title: String, rows: [Row]

    /// The system's menu, its heading then its rows. Each row keeps its action: an item holds its target weakly.
    var menu: NSMenu {
        final class Picked: NSObject {
            let pick: () -> Void
            init(_ pick: @escaping () -> Void) { self.pick = pick }
            @objc func picked() { pick() }
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(.sectionHeader(title: title))
        for row in rows {
            if row.apart { menu.addItem(.separator()) }
            let picked = Picked(row.pick), item = NSMenuItem(title: row.title, action: #selector(Picked.picked), keyEquivalent: "")
            (item.target, item.representedObject, item.subtitle, item.state) = (picked, picked, row.note, row.on ? .on : .off)
            item.image = row.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            if row.code { item.attributedTitle = NSAttributedString(string: row.title, attributes: [.font: Look.font(.code, size: 12)]) }
            menu.addItem(item)
        }
        return menu
    }

    /// Its heading and rows as text, for the gallery's `.txt`.
    var text: String {
        ([title.uppercased()] + rows.map { row in
            "  \(row.title)\(row.on ? "  ✓" : "")" + (row.note.map { "\n    " + $0.replacingOccurrences(of: "\n", with: "\n    ") } ?? "")
        }).joined(separator: "\n") + "\n"
    }
}

/// Where a word stands on the screen, for its menu. A plain object rather than view state: a Button's action and the
/// view beside it come from the same pass of the body, so each pass's spot is the one in use.
@MainActor final class WordSpot {
    /// Shows a menu under a word; a test reads it instead, as no window server menu may run during one.
    static var present: (WordMenu, NSView) -> Void = { menu, view in
        menu.menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.isFlipped ? view.bounds.height + 5 : -5), in: view)
    }

    /// Set when a pick leaves Run without a folder: the folder word, drawn next, opens by itself.
    static var opening = false

    weak var view: NSView?
    func open(_ menu: WordMenu) { view.map { WordSpot.present(menu, $0) } }
}

/// The word's place in AppKit's coordinates, and the moment to open at once: right after the view exists.
private struct WordPlace: NSViewRepresentable {
    let spot: WordSpot
    var opens: WordMenu?

    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        spot.view = view
        if let opens {
            WordSpot.opening = false
            DispatchQueue.main.async { spot.open(opens) }
        }
    }
}

/// One word of the sentence: a button over its system menu.
private struct Word: View {
    let text: String, label: String, menu: WordMenu
    var monogram: String? = nil
    /// Open by itself at this drawing.
    var opens = false
    var spot = WordSpot()

    var body: some View {
        Button { spot.open(menu) } label: {
            HStack(spacing: 4) {
                if let monogram { Monogram(name: monogram, side: 15) }
                Text(text).font(Look.font(.ui, size: 14.5, weight: .semibold).ui).foregroundStyle(Look.Token.ink.ui).lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Look.Token.ink3.ui)
            }
            .padding(.leading, 7).padding(.trailing, 6).frame(height: 26)
            .background(Look.Token.hover.ui, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(WordPlace(spot: spot, opens: opens ? menu : nil))
        .accessibilityLabel(label)
        .accessibilityValue(text)
        .accessibilityHint("Opens a menu")
    }
}

/// Lays its parts on lines, as words: the sentence wraps where its column ends, its words whole.
private struct Flow: Layout {
    let spacing: CGFloat = 5, line: CGFloat = 30

    /// The left edge and the line of each part, for a column `width` wide.
    private func places(_ parts: Subviews, width: CGFloat) -> (places: [CGPoint], width: CGFloat, lines: Int) {
        var (x, row, widest) = (CGFloat(0), 0, CGFloat(0)), places: [CGPoint] = []
        for part in parts {
            let size = part.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { (x, row) = (0, row + 1) }
            places.append(CGPoint(x: x, y: CGFloat(row)))
            widest = max(widest, x + size.width)
            x += size.width + spacing
        }
        return (places, widest, row + 1)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let laid = places(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? laid.width, height: CGFloat(laid.lines) * line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (part, place) in zip(subviews, places(subviews, width: bounds.width).places) {
            part.place(at: CGPoint(x: bounds.minX + place.x, y: bounds.minY + (place.y + 0.5) * line), anchor: .leading, proposal: .unspecified)
        }
    }
}

/// The sentence and, under it, the lock line or the warning.
struct Sentence: View {
    let subject: String, choice: Binding<LevelChoice>, folders: [String], home: String, warning: String?
    /// The agents it can name at Run, kinds; the builders, unless found ones are given.
    let agents: [String]
    /// The space's name, for its blank folder's path; without one the folder alone is said.
    let space: String?
    /// Whether the lock line shows when no warning does: a sheet says it in its own words.
    let locks: Bool

    private let scopeSpot = WordSpot()

    init(_ subject: String, choice: Binding<LevelChoice>, folders: [String], home: String, warning: String?, agents: [String]? = nil, space: String? = nil, locks: Bool = true) {
        (self.subject, self.choice, self.folders, self.home, self.warning) = (subject, choice, folders, home, warning)
        (self.agents, self.space, self.locks) = (agents ?? Registry.app.builders.map(\.kind), space, locks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Flow {
                plain(subject + " may")
                Word(text: choice.wrappedValue.level.word, label: "What it may do", menu: levelMenu)
                words
            }
            if let warning { Levels.note(warning, warns: true) } else if locks { lock }
        }
    }

    @ViewBuilder private var words: some View {
        let chosen = choice.wrappedValue
        switch chosen.level {
        case .none: plain("your agents.")
        case .run:
            Word(text: chosen.starts, label: "The agent it starts", menu: agentMenu, monogram: chosen.start == nil ? nil : chosen.starts)
            plain("in")
            ended(Word(text: chosen.place(home: home), label: "Where it starts it", menu: folderMenu, opens: WordSpot.opening))
        default:
            ended(Word(text: LevelChoice.agents(chosen.scope, home: home), label: "Which agents it shows", menu: scopeMenu, spot: scopeSpot))
        }
    }

    /// The last word and the sentence's full stop, never apart.
    private func ended(_ word: Word) -> some View {
        HStack(spacing: 1) {
            word
            plain(".")
        }
    }

    private func plain(_ words: String) -> some View {
        Text(words).font(Look.font(.ui, size: 15).ui).kerning(-0.15).foregroundStyle(Look.Token.ink.ui)
    }

    private var lock: some View {
        HStack(spacing: 6) {
            Levels.note(Levels.fine)
            Button { Keys.send("how") } label: {
                Text("?").font(Look.font(.ui, size: 10, weight: .medium).ui).foregroundStyle(Look.Token.ink3.ui)
                    .frame(width: 15, height: 15).background(Circle().strokeBorder(Look.Token.line2.ui)).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("How It Works")
            .accessibilityLabel("Who answers")
        }
    }

    // MARK: The menus

    var levelMenu: WordMenu {
        WordMenu(title: "What it may do with your agents", rows: Grant.Level.allCases.map { level in
            .init(title: level.word, note: level.note, on: level == choice.wrappedValue.level) {
                WordSpot.opening = level == .run && choice.wrappedValue.folder == .none
                choice.wrappedValue.level = level
            }
        })
    }

    var scopeMenu: WordMenu {
        let scope = choice.wrappedValue.scope
        return WordMenu(title: "Which agents it shows", rows: [
            .init(title: "All agents on this Mac", note: "Every one of them, now and later.", on: scope == nil || scope == .all) { choice.wrappedValue.scope = .all },
            .init(title: "Only in a folder…", note: "Only the agents working in the folder you pick.", on: scope != nil && scope != .all) {
                DispatchQueue.main.async { scopeSpot.open(scopeFolderMenu) }
            },
        ])
    }

    /// The folders it may show agents from.
    var scopeFolderMenu: WordMenu {
        var shown: [String] = []
        if case .folders(let folders)? = choice.wrappedValue.scope { shown = folders }
        let pick = { (folder: String) in choice.wrappedValue.scope = .folders([folder]) }
        return WordMenu(title: "Which folder", rows: rows(known: shown, on: shown.first, pick) + [choose(pick)])
    }

    var agentMenu: WordMenu {
        let chosen = choice.wrappedValue.start
        return WordMenu(title: "Which agent it starts", rows: agents.map { kind in
            let agent = Registry.app.agent(kind), never = agent?.neverAsks == true || agent?.asksNothingByDefault == true
            return .init(title: Registry.app.name(of: kind), note: never ? "never asks" : nil, on: kind == chosen?.kind) { choice.wrappedValue.start = Grant.Start(kind: kind) }
        })
    }

    var folderMenu: WordMenu {
        let chosen = choice.wrappedValue.folder, pick = { (folder: String) in choice.wrappedValue.folder = .path(folder) }
        let blank = Words.path(Places(home: URL(fileURLWithPath: home)).agents.path, home: home) + (space.map { "/" + $0 } ?? "")
        return WordMenu(title: "Where it starts them", rows: rows(known: [chosen.path].compactMap { $0 }, on: chosen.path, pick) + [
            .init(title: "No Folder", note: "It starts in a blank folder of its own.\n" + blank, on: chosen == .blank, apart: true) { choice.wrappedValue.folder = .blank },
            choose(pick),
        ])
    }

    /// A row per folder the Mac's agents work in, and those already chosen.
    private func rows(known: [String], on: String?, _ pick: @escaping (String) -> Void) -> [WordMenu.Row] {
        (folders + known.filter { !folders.contains($0) }).map { path in
            .init(title: Words.path(path, home: home), symbol: "folder", code: true, on: path == on) { pick(path) }
        }
    }

    private func choose(_ pick: @escaping (String) -> Void) -> WordMenu.Row {
        .init(title: "Choose Folder…", symbol: "folder.badge.plus", apart: !folders.isEmpty) { Levels.chooseFolder(pick) }
    }
}
