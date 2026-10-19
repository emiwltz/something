// The sheets that ask the person, on the main window: the rights a space declares, a mode that makes an agent ask less,
// a link a space wants to open, whether an export carries the space's memory, where to save or find a .something file,
// moving a space to the Trash, quitting while agents run, switching the assistant's builder, and how to get one. A
// space cannot draw them, so a space cannot answer them.
// Each one names the space it is about. A space asks through `Asking`, so its tests answer without a window.
import AppKit
import SomethingAgents
import SomethingCore
import SwiftUI
import UniformTypeIdentifiers

/// What the rights sheet asks about one space: only what changed since the person last answered.
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
    /// The person's answers, or nil when they chose "Not Now": nothing is remembered and the space gets nothing new.
    func rights(_ question: RightsQuestion) -> RightsAnswer?
    /// true when the person lets the space put an agent of `kind`, working in `folder`, in `mode`, which makes it ask less.
    func lowers(_ mode: String, kind: String, folder: String?, space: String) -> Bool
    /// What the person chose for `url`. "Open" has already opened it in their browser or mail app.
    func link(_ url: URL, space: String) -> LinkChoice
    /// Whether the export of `space` carries its memory, shown with its keys and its size: false ("Without Data", the
    /// default) or true; nil when the person cancels.
    func withData(_ space: String, keys: [String], bytes: Int) -> Bool?
    /// Where to save `name` (a .something file); nil when the person cancels.
    func saveAs(_ name: String) -> URL?
    /// The .something file to import; nil when the person cancels.
    func importFile() -> URL?
    /// Says a failure that has no window of its own.
    func tell(_ message: String)
}

/// The person, in sheets on the main window. A sheet that needs an answer before the caller goes on (rights before a
/// page runs, a link the page waits for) keeps the app waiting until it is answered, as a modal window would, but on
/// the window it is about; the agents' permission panels still answer meanwhile.
final class NativeAsk: Asking {
    /// The window the sheets go on; the app gives its own.
    var window: () -> NSWindow? = { nil }

    /// Shows `sheet`, begun by `begin` on the window, and waits for its answer. nil when there is no window or another
    /// sheet is up: one question at a time, and the second is answered as Escape would.
    private func wait(_ sheet: NSWindow, _ begin: (NSWindow, @escaping (NSApplication.ModalResponse) -> Void) -> Void) -> NSApplication.ModalResponse? {
        guard let window = window(), window.attachedSheet == nil else { return nil }
        // The focus stays where the person is: an app in the background shows the sheet behind and bounces its icon.
        if NSApp.isActive {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
            NSApp.requestUserAttention(.informationalRequest)
        }
        begin(window) { NSApp.stopModal(withCode: $0) }
        return NSApp.runModal(for: sheet)
    }

    private func wait(_ alert: NSAlert) -> NSApplication.ModalResponse? {
        wait(alert.window) { alert.beginSheetModal(for: $0, completionHandler: $1) }
    }

    func rights(_ question: RightsQuestion) -> RightsAnswer? {
        let sheet = Ask.rights(question)
        return wait(sheet.alert) == .alertFirstButtonReturn ? sheet.answer() : nil
    }

    func lowers(_ mode: String, kind: String, folder: String?, space: String) -> Bool {
        wait(Ask.lowers(mode, kind: kind, folder: folder, space: space)) == .alertFirstButtonReturn
    }

    func link(_ url: URL, space: String) -> LinkChoice {
        switch wait(Ask.link(url, space: space)) {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(url)
            return .open
        case .alertThirdButtonReturn: return .block
        default: return .cancel
        }
    }

    func withData(_ space: String, keys: [String], bytes: Int) -> Bool? {
        switch wait(Ask.withData(space, keys: keys, bytes: bytes)) {
        case .alertFirstButtonReturn: return false
        case .alertSecondButtonReturn: return true
        default: return nil
        }
    }

    func saveAs(_ name: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        return wait(panel) { panel.beginSheetModal(for: $0, completionHandler: $1) } == .OK ? panel.url : nil
    }

    func importFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "something") ?? .json, .json]
        return wait(panel) { panel.beginSheetModal(for: $0, completionHandler: $1) } == .OK ? panel.url : nil
    }

    /// Says `message` on standard error, which a terminal shows, and in a sheet once the window has none.
    func tell(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        say(message)
    }

    private func say(_ message: String) {
        guard window()?.attachedSheet == nil else {
            return DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.say(message) }
        }
        _ = wait(Ask.alert(message))
    }
}

/// One line of the rights sheet with a folder chooser: a sentence, the folder on a line of its own below it, so that
/// a path is never broken, and the button beside them. Once a folder is chosen, the sentence becomes `then`, which
/// still says what the folder is for, and the chosen folder is shown below it.
final class Chooser: NSObject {
    let row = NSStackView(), home: String, width: CGFloat, then: String, chosen: (String) -> Void

    init(_ lines: NSStackView, _ text: String, folder: String?, then: String, button title: String, home: String,
         chosen: @escaping (String) -> Void) {
        let button = NSButton(title: title, target: nil, action: #selector(choose))
        self.home = home
        self.then = then
        self.chosen = chosen
        width = Ask.rightsWidth - button.fittingSize.width - 8
        super.init()
        button.target = self
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 2
        // As wide as the sheet's lines leave it: every Choose… button stands at the same place.
        row.widthAnchor.constraint(equalToConstant: width).isActive = true
        say(text, folder)
        lines.addArrangedSubview(NSStackView(views: [row, button]))
    }

    private func say(_ text: String, _ folder: String?) {
        row.arrangedSubviews.forEach { $0.removeFromSuperview() }
        row.addArrangedSubview(Style.line(text, width: width))
        if let folder { row.addArrangedSubview(Style.path(folder, home: home, width: width)) }
    }

    /// Asks for a folder in a sheet over the rights sheet.
    @objc func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard let sheet = row.window else { return }
        panel.beginSheetModal(for: sheet) { [weak self] answer in
            if answer == .OK, let url = panel.url { self?.picked(url.path) }
        }
    }

    /// Says and keeps `folder`, as chosen in the panel.
    func picked(_ folder: String) {
        say(then, folder)
        chosen(folder)
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

    /// How wide the rights sheet's lines wrap: a long folder or many of them would otherwise widen it past the screen.
    static let rightsWidth: CGFloat = 400

    /// The rights sheet, not yet shown, and the answers its boxes and choosers hold once it closed with its first
    /// button, "Allow". Every right is ticked: the person unticks what they refuse, and clicks Allow, which Return does
    /// not press. Paths are shown from `home`.
    /// The sheet is built apart from showing it so that a test can draw it without showing it.
    static func rights(_ question: RightsQuestion, home: String = NSHomeDirectory()) -> (alert: NSAlert, answer: () -> RightsAnswer) {
        let alert = Ask.alert("Allow “\(question.space)” to:", question.description ?? "", buttons: ["Allow", "Not Now"], escape: 1)
        // Every box is ticked, and this sheet opens by itself at a first opening: Return must not allow it all
        // unread. Allow is clicked; Escape is Not Now.
        alert.buttons[0].keyEquivalent = ""
        let lines = NSStackView()
        lines.orientation = .vertical
        lines.alignment = .leading
        func indented(_ view: NSView) {
            let line = NSStackView(views: [view])
            line.edgeInsets.left = 20
            lines.addArrangedSubview(line)
        }
        // A box's title does not wrap: the warning a right may carry goes in a label under its box.
        let boxes = question.rights.map { NSButton(checkboxWithTitle: Ask.title(for: $0), target: nil, action: nil) }
        for (right, box) in zip(question.rights, boxes) {
            box.state = .on
            lines.addArrangedSubview(box)
            if let warning = Ask.warning(for: right) { indented(Style.line(warning + ".", width: Ask.rightsWidth - 20)) }
        }
        if let scope = question.scope {
            let sentence = "With “\(Ask.title(for: "state"))”, it sees "
            switch scope {
            case .all: lines.addArrangedSubview(Style.line(sentence + "all your agents.", width: Ask.rightsWidth))
            case .folders(let folders) where folders.isEmpty:
                lines.addArrangedSubview(Style.line(sentence + "only the agents it starts.", width: Ask.rightsWidth))
            case .folders(let folders):
                lines.addArrangedSubview(Style.line(sentence + "only the agents working in:", width: Ask.rightsWidth))
                // Six at most: a sheet does not scroll, and twenty folders would push its buttons off the screen.
                folders.prefix(6).forEach { indented(Style.path($0, home: home, width: Ask.rightsWidth - 20)) }
                if folders.count > 6 {
                    let more = Style.line("and \(folders.count - 6) more", width: Ask.rightsWidth - 20)
                    more.toolTip = folders.dropFirst(6).joined(separator: "\n")
                    indented(more)
                }
            }
        }
        var remap: [String: String] = [:], folder = question.folder?.found
        var choosers: [Chooser] = []
        for missing in question.missing {
            choosers.append(Chooser(lines, "This folder is not on this Mac:", folder: missing,
                                    then: "In place of \(Words.path(missing, home: home)):", button: "Choose…",
                                    home: home) { remap[missing] = $0 })
        }
        if let asked = question.folder {
            let now = asked.found != nil ? "Agents it starts will work in:"
                : asked.declared != nil ? "Agents it starts would work in this folder, not on this Mac:" : "Agents it starts need a folder."
            choosers.append(Chooser(lines, now, folder: asked.found ?? asked.declared, then: "Agents it starts will work in:",
                                    button: "Choose…", home: home) { folder = $0 })
        }
        let footer = Style.line("You can change this anytime in Info (⌥⌘I).", width: Ask.rightsWidth)
        footer.textColor = .secondaryLabelColor
        lines.addArrangedSubview(footer)
        lines.setCustomSpacing(14, after: lines.arrangedSubviews[lines.arrangedSubviews.count - 2])
        lines.frame.size = lines.fittingSize
        alert.accessoryView = lines
        return (alert, {
            withExtendedLifetime(choosers) {}
            let ticked = zip(question.rights, boxes).filter { $0.1.state == .on }.map(\.0)
            return RightsAnswer(allowed: ticked, refused: question.rights.filter { !ticked.contains($0) }, folder: folder, remap: remap)
        })
    }

    /// The sheet that asks whether `space` may put an agent of `kind` in `mode`; "Allow" is its first button. The
    /// folder is shown from `home`.
    static func lowers(_ mode: String, kind: String, folder: String?, space: String, home: String = NSHomeDirectory()) -> NSAlert {
        alert("Let “\(space)” put \(Programs.name(of: kind)) in a mode where it \(words(forMode: mode)) (\(mode))?",
              "The agent works in \(folder.map { Words.path($0, home: home) } ?? "a folder something does not know"). In this mode it asks you less before it acts.",
              buttons: ["Allow", "Don't Allow"], escape: 1)
    }

    /// The link sheet: Open, Cancel, or Block Links Until Reload, in that order.
    static func link(_ url: URL, space: String) -> NSAlert {
        alert("“\(space)” wants to open a link", url.absoluteString, buttons: ["Open", "Cancel", "Block Links Until Reload"], escape: 1)
    }

    /// The export sheet: Without Data, With Its Data, or Cancel, in that order.
    static func withData(_ space: String, keys: [String], bytes: Int) -> NSAlert {
        // Ten keys at most: a memory of hundreds would make the sheet taller than the screen.
        let shown = keys.prefix(10).joined(separator: ", ") + (keys.count > 10 ? " and \(keys.count - 10) more" : "")
        let alert = alert("Export “\(space)” with its data?", "Its memory holds \(shown) (\(Size.words(bytes))). "
                          + "Whoever receives the file can read all of it. Without data, the space starts empty on the other Mac.",
                          buttons: ["Without Data", "With Its Data", "Cancel"], escape: 2)
        alert.buttons[1].keyEquivalent = ""
        return alert
    }

    /// The sheet before Move to Trash: Move to Trash, then Cancel (Escape).
    static func trash(_ title: String) -> NSAlert {
        alert("Move “\(title)” to the Trash?", "Its memory on this Mac goes with it. You can put both back from the Trash.",
              buttons: ["Move to Trash", "Cancel"], escape: 1)
    }

    /// The sheet that asks before quitting while `count` agents something launched run, the person's assistant among
    /// them when `assistant`: Quit, then Cancel.
    static func quit(_ count: Int, assistant: Bool = false) -> NSAlert {
        let others = assistant ? count - 1 : count
        let running = assistant && others == 0 ? "Your assistant is still running. Quitting stops it."
            : assistant ? "Your assistant and \(others) other agent\(others == 1 ? "" : "s") something started are still running. Quitting stops them."
            : count == 1 ? "An agent something started is still running. Quitting stops it."
            : "\(count) agents something started are still running. Quitting stops them."
        return alert("Quit something?", running, buttons: ["Quit", "Cancel"], escape: 1)
    }

    /// The sheet before a switch of builder ends the conversation: Switch, then Cancel.
    static func switching(from: String, to: String) -> NSAlert {
        alert("Switch to \(to)?", "Your conversation with \(from) ends here. \(from) keeps it in its own history.",
              buttons: ["Switch", "Cancel"], escape: 1)
    }

    /// How to Get One: each coding agent something builds with (none it refuses), its install command and a Copy button; Look Again,
    /// then Close. something downloads nothing itself.
    static func howToGetOne(copy: @escaping (String) -> Void) -> NSAlert {
        let alert = alert("Get a coding agent", "Install one, sign it in once in Terminal, then click Look Again.",
                          buttons: ["Look Again", "Close"], escape: 1)
        let rows = AssistantModel.builders.filter { AssistantModel.cannotBuild[$0] == nil }
            .compactMap { kind in Programs.install[kind].map { (Programs.name(of: kind), $0) } }
        let list = NSHostingView(rootView: InstallList(rows: rows, copy: copy))
        list.frame.size = list.fittingSize
        alert.accessoryView = list
        return alert
    }

    /// A right in plain words, with its warning when it has one: what Info says.
    static func words(for right: String) -> String {
        [title(for: right), warning(for: right)].compactMap { $0 }.joined(separator: ". ")
    }

    /// What a right lets the space do, in plain words: the title of its box in the rights sheet.
    static func title(for right: String) -> String {
        let parts = right.split(separator: ":", maxSplits: 1).map(String.init)
        let kind = parts.count == 2 ? Programs.name(of: parts[1]) : nil
        switch parts[0] {
        case "state": return "See your agents and what they say"
        case "send": return "Write to your \(kind.map { $0 + " " } ?? "")agents, stop them, change their settings"
        case "launch": return "Start \(kind ?? "agents") in a folder you choose"
        case "store": return "Remember things on this Mac"
        default: return right
        }
    }

    /// What the person must know before allowing `right`, or nil when nothing: a launch that may reach pi.
    static func warning(for right: String) -> String? {
        // pi has no permission modes: a space that launches it gets an agent that never waits for a click.
        switch right {
        case "launch": return "One of them, pi, runs commands and edits files without asking you first"
        case "launch:pi": return "pi runs commands and edits files without asking you first"
        default: return nil
        }
    }

    /// What a mode that lowers asking lets the agent do, in plain words.
    static func words(forMode mode: String) -> String {
        ["acceptEdits": "edits files without asking you", "auto": "decides by itself what to ask you",
         "dontAsk": "never asks you, and does only what your settings already allow",
         "never": "never asks you before it runs a command"][mode] ?? "asks you less"
    }
}
