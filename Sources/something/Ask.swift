// The native windows that ask the person: the rights a space declares, a mode that makes an agent ask less, a link a
// space wants to open, quitting while agents run. A space cannot draw them, so a space cannot answer them. Each one
// names the space it is about. Space windows ask through `Asking`, so their tests answer without a window.
import AppKit
import SomethingCore

/// What the rights window asks about one space: only what changed since the person last answered (contract 5).
struct RightsQuestion: Equatable {
    var space: String
    var description: String?
    /// The declared rights never answered, each allowed or refused on its own line.
    var rights: [String]
    /// The scope, shown when it is new or wider than the one answered.
    var scope: Scope?
    /// Scope folders, as declared, that are not on this Mac: the person may choose one in place of each.
    var missing: [String]
    /// Set when the folder for launches must be chosen or confirmed.
    var folder: FolderQuestion?
}

struct FolderQuestion: Equatable {
    /// The folder as declared, or nil when the space declares none.
    var declared: String?
    /// The declared folder on this Mac, absolute; nil when it is not here (or none is declared).
    var found: String?
}

/// The person's answers. `folder` is the folder in force for launches; `remap` maps a missing scope folder, as
/// declared, to the one chosen in its place.
struct RightsAnswer: Equatable {
    var allowed: [String], refused: [String], folder: String?, remap: [String: String]
}

enum LinkChoice { case open, cancel, block }

protocol Asking: AnyObject {
    /// The person's answers, or nil when they chose "Not now": nothing is remembered and the space gets nothing new.
    func rights(_ question: RightsQuestion) -> RightsAnswer?
    /// true when the person lets the space put an agent of `kind`, working in `folder`, in `mode`, which makes it ask less.
    func lowers(_ mode: String, kind: String, folder: String?, space: String) -> Bool
    /// What the person chose for `url`. "Open" has already opened it in their browser or mail app.
    func link(_ url: URL, space: String) -> LinkChoice
    /// Says a failure that has no window of its own.
    func tell(_ message: String)
}

final class NativeAsk: Asking {
    func rights(_ question: RightsQuestion) -> RightsAnswer? {
        let alert = NSAlert()
        alert.messageText = "“\(question.space)” asks for:"
        alert.informativeText = question.description ?? ""
        let lines = NSStackView()
        lines.orientation = .vertical
        lines.alignment = .leading
        let boxes = question.rights.map { NSButton(checkboxWithTitle: Ask.words(for: $0), target: nil, action: nil) }
        boxes.forEach(lines.addArrangedSubview)
        if let scope = question.scope {
            let seen: String
            switch scope {
            case .all: seen = "all your agents"
            case .folders(let folders):
                seen = folders.isEmpty ? "only the agents it launches" : "the agents working in " + folders.joined(separator: ", ")
            }
            lines.addArrangedSubview(NSTextField(wrappingLabelWithString: "With the right to see your agents, it sees \(seen)."))
        }
        var remap: [String: String] = [:], folder = question.folder?.found
        var choosers: [Chooser] = []
        for missing in question.missing {
            choosers.append(Chooser(lines, "Agents in \(missing): not on this Mac.", button: "Choose a folder in its place…") { remap[missing] = $0 })
        }
        if let asked = question.folder {
            let now = asked.found.map { "Agents it launches work in \($0)." }
                ?? asked.declared.map { "Agents it launches work in \($0): not on this Mac." } ?? "Agents it launches need a folder."
            choosers.append(Chooser(lines, now, button: asked.found == nil ? "Choose a folder…" : "Choose another folder…") { folder = $0 })
        }
        lines.frame.size = lines.fittingSize
        alert.accessoryView = lines
        // Return keeps nothing: a refusal is remembered, so it takes a click on the button that says what it does.
        alert.addButton(withTitle: "Allow what is ticked").keyEquivalent = ""
        alert.addButton(withTitle: "Not now").keyEquivalent = "\r"
        let response = Ask.run(alert)
        withExtendedLifetime(choosers) {}
        guard response == .alertFirstButtonReturn else { return nil }
        let ticked = zip(question.rights, boxes).filter { $0.1.state == .on }.map(\.0)
        return RightsAnswer(allowed: ticked, refused: question.rights.filter { !ticked.contains($0) }, folder: folder, remap: remap)
    }

    func lowers(_ mode: String, kind: String, folder: String?, space: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Let “\(space)” put \(Ask.name(of: kind)) in a mode where it \(Ask.words(forMode: mode)) (\(mode))?"
        alert.informativeText = "The agent works in \(folder ?? "a folder something does not know"). In this mode it asks you less before it acts."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don't allow").keyEquivalent = "\u{1b}"
        return Ask.run(alert) == .alertFirstButtonReturn
    }

    func link(_ url: URL, space: String) -> LinkChoice {
        let alert = NSAlert()
        alert.messageText = "“\(space)” wants to open a link."
        alert.informativeText = url.absoluteString
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        alert.addButton(withTitle: "Block links until reload")
        switch Ask.run(alert) {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(url)
            return .open
        case .alertThirdButtonReturn: return .block
        default: return .cancel
        }
    }

    func tell(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        _ = Ask.run(alert)
    }
}

/// One line of the rights window with a folder chooser; the line then says the folder chosen.
final class Chooser: NSObject {
    let label: NSTextField, chosen: (String) -> Void

    init(_ lines: NSStackView, _ text: String, button title: String, chosen: @escaping (String) -> Void) {
        label = NSTextField(wrappingLabelWithString: text)
        self.chosen = chosen
        super.init()
        lines.addArrangedSubview(NSStackView(views: [label, NSButton(title: title, target: self, action: #selector(choose))]))
    }

    @objc func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        label.stringValue = "Chosen: \(url.path)"
        chosen(url.path)
    }
}

enum Ask {
    static func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    /// The name a person knows an agent by.
    static func name(of kind: String) -> String {
        ["claude": "Claude Code", "codex": "Codex", "opencode": "OpenCode", "pi": "pi", "omp": "OMP"][kind] ?? kind
    }

    /// A right in plain words, for the rights window.
    static func words(for right: String) -> String {
        let parts = right.split(separator: ":", maxSplits: 1).map(String.init)
        let kind = parts.count == 2 ? name(of: parts[1]) : nil
        switch parts[0] {
        case "state": return "See your agents and what they say"
        case "send": return "Write to, interrupt and change the \(kind.map { $0 + " " } ?? "")agents it launched"
        case "launch": return "Launch or continue \(kind ?? "agents") in the folder chosen for it"
        case "store": return "Keep a memory of its own on this Mac"
        default: return right
        }
    }

    /// What a mode that lowers asking lets the agent do, in plain words.
    static func words(forMode mode: String) -> String {
        ["acceptEdits": "edits files without asking you", "auto": "decides by itself what to ask you",
         "dontAsk": "never asks you, and does only what your settings already allow",
         "never": "never asks you before it runs a command"][mode] ?? "asks you less"
    }

    static func quit(stopping count: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Quit something?"
        alert.informativeText = "\(count) agent(s) will stop."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return run(alert) == .alertFirstButtonReturn
    }
}
