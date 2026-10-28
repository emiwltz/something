// The sheets that ask the person, on the main window: a space's level with your agents (Levels.swift draws it), a mode that makes an agent ask less,
// a link a space wants to open, whether an export carries the space's memory, where to save or find a .something file,
// the folder a template follows, moving a space to the Trash, quitting while requests wait or agents work, switching
// the assistant's builder, and how to get one. A space cannot draw them, so a space cannot answer them.
// Each one names the space it is about. A space asks through `Asking`, so its tests answer without a window.
import AppKit
import SomethingAgents
import SomethingCore
import SwiftUI
import UniformTypeIdentifiers

/// What the level sheet asks about a space made elsewhere (a template, an import, an agent outside something), or one
/// whose page declares what its last answer did not cover.
struct RightsQuestion: Equatable {
    var space: String
    var description: String?
    /// The level pre-set: the one in force, else the highest the page's rights use.
    var level: Grant.Level
    /// Run's folder pre-set: the one in force, else the declared one when it is on this Mac; nil to choose one.
    var folder: String?
    /// The folders the Mac's agents work in, offered for Run.
    var folders: [String] = []
    /// Whether the person's assistant made the space while they waited for it: the sheet says so first.
    var made = false
    /// The space's page (its file, or its folder), absolute, shown under the title; nil shows none.
    var page: String? = nil
}

/// The person's answer: the level, and the folder in force for launches when it is Run.
struct RightsAnswer: Equatable {
    var level: Grant.Level, folder: String?
}

protocol Asking: AnyObject {
    /// The person's answer, or nil when they chose "Don't Allow": nothing is remembered and the space gets nothing new.
    func rights(_ question: RightsQuestion) -> RightsAnswer?
    /// true when the person lets the space put an agent of `kind`, working in `folder`, in `mode`, which makes it ask less.
    func lowers(_ mode: String, kind: String, folder: String?, space: String) -> Bool
    /// true when the person chose to open `url`, which is then already open in their browser or mail app; false when
    /// they pressed Cancel; nil when the sheet could not be shown (no window, or another sheet up), which is no Cancel.
    func link(_ url: URL, space: String) -> Bool?
    /// The .something file to import; nil when the person cancels.
    func importFile() -> URL?
    /// A folder the person chooses, `message` saying what for; nil when they cancel.
    func folder(_ message: String) -> URL?
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

    /// The role of the action the person pressed in `sheet`; nil when it was not shown.
    private func wait(_ sheet: Sheet) -> Sheet.Role? {
        _ = wait(sheet) { window, done in sheet.hang(on: window) { _ in done(.stop) } }
        return sheet.chosen
    }

    func rights(_ question: RightsQuestion) -> RightsAnswer? {
        let sheet = Ask.rights(question)
        return wait(sheet.sheet) == .primary ? sheet.answer() : nil
    }

    func lowers(_ mode: String, kind: String, folder: String?, space: String) -> Bool {
        NativeAsk.agreed(wait(Ask.lowers(mode, kind: kind, folder: folder, space: space)))
    }

    func link(_ url: URL, space: String) -> Bool? {
        guard let role = wait(Ask.link(url, space: space)) else { return nil }
        guard role == .primary else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    // The buttons' meanings, apart from the modal loop so that a test can hold them.

    /// true when the sheet ended with its first button (Allow); false for any other, or none.
    static func agreed(_ response: NSApplication.ModalResponse?) -> Bool { response == .alertFirstButtonReturn }

    private func chosen(_ panel: NSSavePanel) -> URL? {
        wait(panel) { panel.beginSheetModal(for: $0, completionHandler: $1) } == .OK ? panel.url : nil
    }

    func importFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "something") ?? .json, .json]
        return chosen(panel)
    }

    func folder(_ message: String) -> URL? {
        let panel = NSOpenPanel()
        (panel.canChooseDirectories, panel.canChooseFiles, panel.message, panel.prompt) = (true, false, message, "Choose")
        return chosen(panel)
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

/// The README's promise, word for word (AGENTS.md rule 2): under Settings › Advanced's permissions, and in the README.
enum Promise {
    static let sentence = "something never answers for you. Your assistant may change your spaces and run something's own commands without asking; everything else it does asks you, as your agent's own settings decide."
}

enum Ask {
    /// An alert that says `message`, with `details` below it, `accessory` under them, and `buttons` (none: OK), the
    /// first one the default. The button at `escape`, if any, is the one Escape presses.
    static func alert(_ message: String, _ details: String = "", buttons: [String] = [], escape: Int? = nil, accessory: NSView? = nil) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = details
        buttons.forEach { alert.addButton(withTitle: $0) }
        if let escape { alert.buttons[escape].keyEquivalent = "\u{1b}" }
        if let accessory {
            accessory.frame.size = accessory.fittingSize
            alert.accessoryView = accessory
        }
        return alert
    }

    /// The sheet that asks whether `space` may put an agent of `kind` in `mode`; "Allow" is its first button, and takes
    /// no Return: a page can raise this sheet while the person types in it, and a Return meant for the page must not
    /// lower the mode. The folder is shown from `home`.
    static func lowers(_ mode: String, kind: String, folder: String?, space: String, home: String = NSHomeDirectory()) -> NSAlert {
        let sheet = alert("Let “\(space)” put \(Registry.app.name(of: kind)) in a mode where it \(words(forMode: mode)) (\(mode))?",
              "The agent works in \(folder.map { Words.path($0, home: home) } ?? "a folder something does not know"). In this mode it asks you less before it acts.",
              buttons: ["Allow", "Don't Allow"], escape: 1)
        sheet.buttons[0].keyEquivalent = ""
        return sheet
    }

    /// The link sheet: whose page asks, the server (or address) in bold, the whole link with it in bold too, then
    /// Cancel and Open in Browser (Open in Mail for an address).
    static func link(_ url: URL, space: String) -> Sheet {
        let whole = url.absoluteString, mail = url.scheme == "mailto", name = url.host ?? url.path
        // The server where the link itself says it, not where its user part or its query repeats the name.
        var shown: Sheet.Words = [(whole, false)]
        if let parts = URLComponents(string: whole), let at = parts.rangeOfHost ?? parts.rangeOfPath, !at.isEmpty {
            shown = [(String(whole[..<at.lowerBound]), false), (String(whole[at]), true), (String(whole[at.upperBound...]), false)]
        }
        let address = Sheet.label(shown, Look.Style(face: .code, size: 12, weight: .regular, leading: 1.5), color: .ink2,
                                  width: Sheet.column() - 22)
        // The scheme is quieter than the rest, as the mockup sets it.
        if let scheme = url.scheme {
            let quiet = NSMutableAttributedString(attributedString: address.attributedStringValue)
            let lead = scheme.count + (whole.hasPrefix(scheme + "://") ? 3 : 1)
            quiet.addAttribute(.foregroundColor, value: Look.Token.ink3.color, range: NSRange(location: 0, length: min(lead, quiet.length)))
            address.attributedStringValue = quiet
        }
        // A page chooses the link: a very long one is cut, whole when the pointer rests on it.
        (address.lineBreakMode, address.maximumNumberOfLines, address.toolTip) = (.byCharWrapping, 6, whole)
        (address.cell as? NSTextFieldCell)?.truncatesLastVisibleLine = true
        return Sheet(icon: .symbol("globe"), title: "Open this link?",
                     body: [(space + " wants to open ", false), (name, true), (mail ? " in your mail app." : " in your browser.", false)],
                     block: Box(address, fill: .sunk, ring: .line, radius: 9, insets: NSEdgeInsets(top: 9, left: 11, bottom: 9, right: 11)),
                     fine: "Spaces can't reach the Internet. A link opens only when you say so, in your own browser, outside something.",
                     actions: [.init(title: "Cancel", role: .cancel), .init(title: mail ? "Open in Mail" : "Open in Browser", role: .primary)])
    }

    /// The sheet before Move to Trash: what goes with the space, its page, how many entries its memory holds (nil
    /// when it does not read) and its assistant's conversation, of `messages` messages; then Cancel and Move to Trash.
    static func trash(_ entry: Library.Entry, remembers: Int?, messages: Int) -> Sheet {
        let page = entry.space.location.lastPathComponent + (entry.space.form == .folder ? "/" : "")
        let memory = remembers.map { $0 == 0 ? "nothing yet" : "\($0) entr\($0 == 1 ? "y" : "ies")" } ?? "does not read"
        return Sheet(icon: .symbol("trash"), title: "Move \(entry.title) and its memory to the Trash?", body: [("These go with it:", false)],
                     rows: [.init(mark: .symbol("doc"), label: [("Its page", false)], meta: page),
                            .init(mark: .symbol("square.3.layers.3d"), label: [("What it remembers", false)], meta: memory),
                            .init(mark: .symbol("bubble.left"), label: [("Its assistant's conversation", false)],
                                  meta: messages == 0 ? "empty" : "\(messages) message\(messages == 1 ? "" : "s")")],
                     fine: "Your agents and their own files stay where they are. You can put the space back from the Trash in Finder.",
                     actions: [.init(title: "Cancel", role: .cancel), .init(title: "Move to Trash", role: .destructive)])
    }

    /// The alert before quitting while something waits or works: each request waiting, which quitting denies, then
    /// each agent at work, which it stops, by space and program; Quit, then Cancel, the default.
    static func quit(_ leaving: Leaving) -> Sheet {
        func row(_ one: Leaving.Row, _ state: Sign.State, _ meta: String, bad: Bool) -> Sheet.Row {
            Sheet.Row(mark: .eyes(state), label: one.space.map { [($0, true), (" · " + one.program, false)] } ?? [(one.program, true)],
                      meta: meta, plain: true, bad: bad)
        }
        let words = Words.quit(requests: leaving.requests.count, working: leaving.working.count)
        return Sheet(icon: .sign, title: words.title,
                     rows: leaving.requests.map { row($0, .wait, "will be denied", bad: true) } + leaving.working.map { row($0, .think, $0.doing, bad: false) },
                     fine: words.fine, actions: [.init(title: "Quit", role: .secondary), .init(title: "Cancel", role: .primary)], alert: true)
    }

    /// The sheet before a switch of builder ends the conversation: Switch, then Cancel.
    static func switching(from: String, to: String) -> NSAlert {
        alert("Switch to \(to)?", "Your conversation with \(from) ends here. \(from) keeps it in its own history.",
              buttons: ["Switch", "Cancel"], escape: 1)
    }

    /// How to Get One: each coding agent something builds with (none it refuses), its install command and a Copy button; Look Again,
    /// then Close. something downloads nothing itself.
    static func howToGetOne(copy: @escaping (String) -> Void) -> NSAlert {
        alert("Get a coding agent", "Install one, sign it in once in Terminal, then click Look Again.", buttons: ["Look Again", "Close"],
              escape: 1, accessory: NSHostingView(rootView: InstallList(rows: InstallList.builders, copy: copy)))
    }

    /// What the person must know before allowing `right`, or nil when nothing: a launch that may reach an agent that
    /// acts without asking, never (pi) or by its own default setting (OMP), so never waits for a click.
    static func warning(for right: String) -> String? {
        let loose = Registry.app.agents.filter { $0.neverAsks || $0.asksNothingByDefault }
        if right == "launch", let first = loose.first {
            if loose.count == 1 {
                return "One of them, \(first.name), runs commands and edits files without asking you first" + (first.neverAsks ? "" : " by default")
            }
            let names = loose.map { $0.neverAsks ? $0.name : $0.name + " by default" }
            return "Some of them run commands and edit files without asking you first: "
                + names.dropLast().joined(separator: ", ") + ", and " + names[names.count - 1]
        }
        guard let agent = loose.first(where: { right == "launch:" + $0.kind }) else { return nil }
        return agent.neverAsks ? "\(agent.name) runs commands and edits files without asking you first"
            : "\(agent.name), by default, runs commands and edits files without asking you first (its own setting)"
    }

    /// What a mode that lowers asking lets the agent do, in plain words: by the mode's name, whichever agent's
    /// descriptor says it.
    static func words(forMode mode: String) -> String {
        Registry.app.agents.lazy.compactMap { $0.modeWords[mode] }.first ?? "asks you less"
    }
}

/// How to Get One's list: each agent, the command that installs it, and a button that copies that command.
struct InstallList: View {
    let rows: [(name: String, command: String)], copy: (String) -> Void

    /// The coding agents something builds with, each with its install command.
    static var builders: [(name: String, command: String)] {
        Registry.app.builders.compactMap { agent in agent.install.map { (agent.name, $0) } }
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            ForEach(rows, id: \.name) { row in
                GridRow {
                    Text(row.name).fontWeight(.medium)
                    Text(row.command).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Button("Copy") { copy(row.command) }.controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
