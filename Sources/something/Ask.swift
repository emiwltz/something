// The native windows that ask the person: the rights a space declares, a mode that makes an agent ask less, a link a
// space wants to open, whether an export carries the space's memory, where to save or find a .something file,
// quitting while agents run. A space cannot draw them, so a space cannot answer them.
// Each one names the space it is about. Space windows ask through `Asking`, so their tests answer without a window.
import AppKit
import SomethingCore
import UniformTypeIdentifiers

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
    /// Whether the export of `space` carries its memory, shown with its keys and its size: false ("Without data", the
    /// default) or true; nil when the person cancels.
    func withData(_ space: String, keys: [String], bytes: Int) -> Bool?
    /// Where to save `name` (a .something file); nil when the person cancels.
    func saveAs(_ name: String) -> URL?
    /// The .something file to import; nil when the person cancels.
    func importFile() -> URL?
    /// The name of a new space, as typed; nil when the person cancels.
    func newName() -> String?
    /// Says a failure that has no window of its own.
    func tell(_ message: String)
}

final class NativeAsk: Asking {
    func rights(_ question: RightsQuestion) -> RightsAnswer? {
        let window = Ask.rights(question)
        return Ask.run(window.alert) == .alertFirstButtonReturn ? window.answer() : nil
    }

    func lowers(_ mode: String, kind: String, folder: String?, space: String) -> Bool {
        Ask.run(Ask.lowers(mode, kind: kind, folder: folder, space: space)) == .alertFirstButtonReturn
    }

    func link(_ url: URL, space: String) -> LinkChoice {
        switch Ask.run(Ask.link(url, space: space)) {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(url)
            return .open
        case .alertThirdButtonReturn: return .block
        default: return .cancel
        }
    }

    func withData(_ space: String, keys: [String], bytes: Int) -> Bool? {
        switch Ask.run(Ask.withData(space, keys: keys, bytes: bytes)) {
        case .alertFirstButtonReturn: return false
        case .alertSecondButtonReturn: return true
        default: return nil
        }
    }

    func saveAs(_ name: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    func importFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "something") ?? .json, .json]
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    func newName() -> String? {
        let alert = Ask.alert("A new space", "Its name, in small letters, digits and dashes, for example morning-review.",
                              buttons: ["Make", "Cancel"], escape: 1)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard Ask.run(alert) == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespaces)
    }

    func tell(_ message: String) {
        _ = Ask.run(Ask.alert(message))
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
    /// An alert that says `message`, with `details` below it and `buttons` (none: OK), the first one the default.
    /// The button at `escape`, if any, is the one Escape presses.
    static func alert(_ message: String, _ details: String = "", buttons: [String] = [], escape: Int? = nil) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = details
        buttons.forEach { alert.addButton(withTitle: $0) }
        if let escape { alert.buttons[escape].keyEquivalent = "\u{1b}" }
        return alert
    }

    /// The rights window, not yet run, and the answers its boxes and choosers hold once it closed with its first
    /// button. The window is built apart from running it so that a test can draw it without showing it.
    static func rights(_ question: RightsQuestion) -> (alert: NSAlert, answer: () -> RightsAnswer) {
        let alert = Ask.alert("“\(question.space)” asks for:", question.description ?? "", buttons: ["Allow what is ticked", "Not now"])
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
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"
        return (alert, {
            withExtendedLifetime(choosers) {}
            let ticked = zip(question.rights, boxes).filter { $0.1.state == .on }.map(\.0)
            return RightsAnswer(allowed: ticked, refused: question.rights.filter { !ticked.contains($0) }, folder: folder, remap: remap)
        })
    }

    /// The window that asks whether `space` may put an agent of `kind` in `mode`; "Allow" is its first button.
    static func lowers(_ mode: String, kind: String, folder: String?, space: String) -> NSAlert {
        alert("Let “\(space)” put \(name(of: kind)) in a mode where it \(words(forMode: mode)) (\(mode))?",
              "The agent works in \(folder ?? "a folder something does not know"). In this mode it asks you less before it acts.",
              buttons: ["Allow", "Don't allow"], escape: 1)
    }

    /// The link window: Open, Cancel, or Block links until reload, in that order.
    static func link(_ url: URL, space: String) -> NSAlert {
        alert("“\(space)” wants to open a link.", url.absoluteString, buttons: ["Open", "Cancel", "Block links until reload"], escape: 1)
    }

    /// The export window: Without data, With its data, or Cancel, in that order.
    static func withData(_ space: String, keys: [String], bytes: Int) -> NSAlert {
        // Ten keys at most: a memory of hundreds would make the window taller than the screen.
        let shown = keys.prefix(10).joined(separator: ", ") + (keys.count > 10 ? " and \(keys.count - 10) more" : "")
        let alert = alert("Export “\(space)” with its data?", "Its memory holds \(shown) (\(Size.words(bytes))). "
                          + "Whoever receives the file can read all of it. Without data, the space starts empty on the other Mac.",
                          buttons: ["Without data", "With its data", "Cancel"], escape: 2)
        alert.buttons[1].keyEquivalent = ""
        return alert
    }

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
        case "launch":
            let launch = "Launch or continue \(kind ?? "agents") in the folder chosen for it"
            // pi has no permission modes: a space that launches it gets an agent that never waits for a click.
            guard parts.count == 1 || parts[1] == "pi" else { return launch }
            return launch + (parts.count == 1 ? ". One of them, pi," : ". pi") + " runs commands and edits files without asking you first"
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

    static func quit(stopping count: Int) -> Bool { run(quit(count)) == .alertFirstButtonReturn }

    /// The window that asks before quitting while `count` agents something launched run: Quit, then Cancel.
    static func quit(_ count: Int) -> NSAlert {
        let stop = count == 1 ? "The agent something launched stops." : "The \(count) agents something launched stop."
        return alert("Quit something?", stop + " Agents you started yourself keep running.", buttons: ["Quit", "Cancel"])
    }
}
