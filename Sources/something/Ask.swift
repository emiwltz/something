// The sheets that ask the person, on the main window: the rights a space declares, a mode that makes an agent ask less,
// a link a space wants to open, whether an export carries the space's memory, where to save or find a .something file,
// the folder a template follows, moving a space to the Trash, quitting while requests wait or agents work, switching
// the assistant's builder, and how to get one. A space cannot draw them, so a space cannot answer them.
// Each one names the space it is about. A space asks through `Asking`, so its tests answer without a window. The
// rights sheet's lines share two labels: a line that wraps at a width, and a path on one line.
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
    /// Whether the person's assistant made the space while they waited for it: the sheet says so first.
    var made = false
    /// The space's page (its file, or its folder), absolute, shown under the title; nil shows none.
    var page: String? = nil
    /// Every right the space declares, answered before or not: the fine print says what it does not ask for.
    var declared: [String] = []
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

protocol Asking: AnyObject {
    /// The person's answers, or nil when they chose "Don't Allow": nothing is remembered and the space gets nothing new.
    func rights(_ question: RightsQuestion) -> RightsAnswer?
    /// true when the person lets the space put an agent of `kind`, working in `folder`, in `mode`, which makes it ask less.
    func lowers(_ mode: String, kind: String, folder: String?, space: String) -> Bool
    /// true when the person chose to open `url`, which is then already open in their browser or mail app; false when
    /// they pressed Cancel; nil when the sheet could not be shown (no window, or another sheet up), which is no Cancel.
    func link(_ url: URL, space: String) -> Bool?
    /// Whether the export of `space` carries its memory, shown with its keys and its size: false ("Without Data", the
    /// default) or true; nil when the person cancels.
    func withData(_ space: String, keys: [String], bytes: Int) -> Bool?
    /// Where to save `name` (a .something file); nil when the person cancels.
    func saveAs(_ name: String) -> URL?
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

    func withData(_ space: String, keys: [String], bytes: Int) -> Bool? {
        NativeAsk.withDataChoice(wait(Ask.withData(space, keys: keys, bytes: bytes)))
    }

    // The buttons' meanings, apart from the modal loop so that a test can hold them.

    /// true when the sheet ended with its first button (Allow); false for any other, or none.
    static func agreed(_ response: NSApplication.ModalResponse?) -> Bool { response == .alertFirstButtonReturn }

    /// false for "Without Data" (the first button), true for "With Its Data" (the second), nil for Cancel or none.
    static func withDataChoice(_ response: NSApplication.ModalResponse?) -> Bool? {
        switch response {
        case .alertFirstButtonReturn: return false
        case .alertSecondButtonReturn: return true
        default: return nil
        }
    }

    private func chosen(_ panel: NSSavePanel) -> URL? {
        wait(panel) { panel.beginSheetModal(for: $0, completionHandler: $1) } == .OK ? panel.url : nil
    }

    func saveAs(_ name: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        return chosen(panel)
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

/// What something does, and what it never does, side by side.
struct Promise: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                column("something will", "checkmark.circle.fill", .green, ["See what your coding agents are doing, by reading what they write.",
                                                                      "Start your agent to build spaces with you.",
                                                                      "Ask you, in a window of the Mac, before anything sensitive."])
                column("something never", "xmark.circle.fill", .red, ["Writes into your agents' sessions or settings.", "Lets a space reach the Internet.",
                                                                      "Answers for you."])
            }
            // The promise, in the README's words.
            Text("something never answers for you. Your assistant may change your spaces and run something's own commands without asking; everything else it does asks you, as your agent's own settings decide.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 440)
        .padding(.vertical, 4)
    }

    private func column(_ title: String, _ symbol: String, _ tint: Color, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).fontWeight(.semibold)
            ForEach(lines, id: \.self) { line in
                Label { Text(line).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol).foregroundStyle(tint) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One line of the rights sheet with a folder chooser: a sentence, the folder on a line of its own below it, so that
/// a path is never broken, and the button beside them. Once a folder is chosen, the sentence becomes `then`, which
/// still says what the folder is for, and the chosen folder is shown below it.
final class Chooser: NSObject {
    let row = NSStackView(), home: String, width: CGFloat, then: String, chosen: (String) -> Void

    init(_ lines: NSStackView, _ text: String, folder: String?, then: String, button title: String, home: String,
         chosen: @escaping (String) -> Void) {
        let button = PanelButton(title, action: #selector(choose))
        (button.least, button.height) = (0, 26)
        self.home = home
        self.then = then
        self.chosen = chosen
        width = Ask.rightsColumn - button.intrinsicContentSize.width - 8
        super.init()
        button.target = self
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 2
        // As wide as the sheet's lines leave it: every Choose… button stands at the same place.
        row.widthAnchor.constraint(equalToConstant: width).isActive = true
        say(text, folder)
        let line = NSStackView(views: [row, button])
        line.alignment = .centerY
        lines.addArrangedSubview(line)
    }

    private func say(_ text: String, _ folder: String?) {
        row.arrangedSubviews.forEach { $0.removeFromSuperview() }
        row.addArrangedSubview(Ask.line(text, width: width))
        if let folder { row.addArrangedSubview(Ask.path(folder, home: home, width: width)) }
    }

    /// Asks for a folder in a sheet over the rights sheet.
    @objc func choose() {
        let panel = NSOpenPanel()
        (panel.canChooseDirectories, panel.canChooseFiles) = (true, false)
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

    /// A label in the sheet's small type that wraps at `width` points: a long sentence must not widen its window.
    static func line(_ text: String, width: CGFloat) -> NSTextField {
        Sheet.label([(text, false)], Look.small, color: .ink2, width: width)
    }

    /// `path` on one line, with ~ for `home`, its middle names given way to "…" until it fits `width`; the whole path
    /// shows when the pointer rests on it.
    static func path(_ path: String, home: String, width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        let font = Look.font(.code, size: 11)
        (label.font, label.textColor) = (font, Look.Token.ink2.color)
        label.stringValue = Words.path(path, home: home) { ($0 as NSString).size(withAttributes: [.font: font]).width <= width }
        label.toolTip = path
        // Even its first and last names may not fit: AppKit then cuts what is left, rather than widen the window.
        label.lineBreakMode = .byTruncatingMiddle
        label.widthAnchor.constraint(lessThanOrEqualToConstant: width).isActive = true
        return label
    }

    /// How wide the rights sheet is, as the mockup sets it, and how wide its text runs beside the tile.
    static let rightsWidth: CGFloat = 440, rightsColumn = Sheet.column(width: rightsWidth)

    /// The rights sheet, not yet shown, and the answers its switches and choosers hold once it closed with "Allow".
    /// "<Space> would like to", where its page is, then one row per right with a switch that starts off: Allow is
    /// armed only once a switch is on, and Return and Escape press Don't Allow, which holds the focus. Paths are shown
    /// from `home`. The sheet is built apart from showing it so that a test can draw it without showing it.
    static func rights(_ question: RightsQuestion, home: String = NSHomeDirectory()) -> (sheet: Sheet, answer: () -> RightsAnswer) {
        let text = rightsColumn
        let lines = NSStackView()
        (lines.orientation, lines.alignment, lines.spacing) = (.vertical, .leading, 10)
        func indented(_ view: NSView) {
            let line = NSStackView(views: [view])
            line.edgeInsets.left = 14
            lines.addArrangedSubview(line)
        }
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
            lines.addArrangedSubview(line("Your agent made this space.", width: text))
        }
        if let description = question.description { lines.addArrangedSubview(Sheet.label([(description, false)], Look.medium, color: .ink2, width: text)) }
        if let last = lines.arrangedSubviews.last { lines.setCustomSpacing(14, after: last) }
        let switches = question.rights.map { SheetSwitch(right($0).title) }
        lines.addArrangedSubview(list(question.rights, switches, width: text))
        if let scope = question.scope {
            let sentence = "With “\(right("state").title)”, it sees "
            switch scope {
            case .all: lines.addArrangedSubview(line(sentence + "all your agents.", width: text))
            case .folders(let folders) where folders.isEmpty:
                lines.addArrangedSubview(line(sentence + "only the agents it starts.", width: text))
            case .folders(let folders):
                lines.addArrangedSubview(line(sentence + "only the agents working in:", width: text))
                // Six at most: a sheet does not scroll, and twenty folders would push its buttons off the screen.
                folders.prefix(6).forEach { indented(path($0, home: home, width: text - 14)) }
                if folders.count > 6 {
                    let more = line("and \(folders.count - 6) more", width: text - 14)
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
        let sheet = Sheet(icon: .symbol("doc"), title: "\(question.space) would like to", block: lines, fine: fine(question),
                          actions: [.init(title: "Don't Allow", role: .cancel, hint: "esc"), .init(title: "Allow", role: .primary)],
                          width: rightsWidth)
        // Every switch starts off, and this sheet opens by itself at a first opening: Allow waits for one to be on.
        let allow = sheet.buttons[1]
        allow.enable(false)
        for one in switches { one.changed = { allow.enable(switches.contains { $0.state == .on }) } }
        return (sheet, {
            withExtendedLifetime(choosers) {}
            let on = zip(question.rights, switches).filter { $0.1.state == .on }.map(\.0)
            return RightsAnswer(allowed: on, refused: question.rights.filter { !on.contains($0) }, folder: folder, remap: remap)
        })
    }

    /// One row per right, in a ringed list: its symbol in a tile, its name and what it lets the space do, its switch.
    private static func list(_ rights: [String], _ switches: [SheetSwitch], width: CGFloat) -> NSView {
        let rows = NSStackView()
        (rows.orientation, rows.spacing) = (.vertical, 0)
        for (index, (one, toggle)) in zip(rights, switches).enumerated() {
            if index > 0 {
                let rule = Box(NSView(), fill: .line)
                rule.heightAnchor.constraint(equalToConstant: 1).isActive = true
                rows.addArrangedSubview(rule)
            }
            let words = right(one)
            let image = NSImageView(image: NSImage(systemSymbolName: words.symbol, accessibilityDescription: nil) ?? NSImage())
            (image.symbolConfiguration, image.contentTintColor) = (NSImage.SymbolConfiguration(pointSize: 11, weight: .regular), Look.Token.ink2.color)
            let tile = Box(image, fill: .bg2, ring: .line, radius: 7, insets: NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5))
            NSLayoutConstraint.activate([image.widthAnchor.constraint(equalToConstant: 16), image.heightAnchor.constraint(equalToConstant: 16)])
            let room = width - 24 - 26 - 30 - 22
            let name = Sheet.label([(words.title, false)], Look.Style(face: .ui, size: 13, weight: .semibold, leading: 1.3), width: room)
            let detail = Sheet.label([(words.detail, false)], Look.Style(face: .ui, size: 11.5, weight: .regular, leading: 1.4), color: .ink2, width: room)
            if let warning = words.warning {
                let said = NSMutableAttributedString(attributedString: detail.attributedStringValue)
                said.append(NSAttributedString(string: " " + warning + ".", attributes: [.font: Look.font(.ui, size: 11.5, weight: .medium),
                                                                                         .foregroundColor: Look.Token.bad.color,
                                                                                         .paragraphStyle: said.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as Any]))
                detail.attributedStringValue = said
            }
            let label = NSStackView(views: [name, detail])
            (label.orientation, label.alignment, label.spacing) = (.vertical, .leading, 1)
            label.widthAnchor.constraint(equalToConstant: room).isActive = true
            let line = NSStackView(views: [tile, label, toggle])
            (line.spacing, line.alignment) = (11, .centerY)
            rows.addArrangedSubview(Box(line, insets: NSEdgeInsets(top: 7.5, left: 12, bottom: 7.5, right: 12)))
        }
        // The rules between the rows run from edge to edge, as the mockup's borders do.
        rows.arrangedSubviews.forEach { $0.widthAnchor.constraint(equalToConstant: width).isActive = true }
        return Box(rows, fill: .bg, ring: .line, radius: Look.card)
    }

    /// The rights sheet's fine print: what the space does not ask for, among the four rights, then that each starts off.
    static func fine(_ question: RightsQuestion) -> String {
        let asked = Set((question.declared.isEmpty ? question.rights : question.declared).map { $0.split(separator: ":")[0] })
        let not = [("state", "see your agents"), ("send", "write to your agents"), ("launch", "start agents"), ("store", "remember things")]
            .filter { !asked.contains(Substring($0.0)) }.map(\.1)
        let lead = not.isEmpty ? "" : "It does not ask to " + Words.list(not, "or") + ". "
        return lead + "Each right starts off; change it later in its Info."
    }

    /// A right as the rights sheet says it: its name, what it lets the space do, the warning a person must read before
    /// allowing it (or nil), and its symbol.
    static func right(_ right: String) -> (title: String, detail: String, warning: String?, symbol: String) {
        let parts = right.split(separator: ":", maxSplits: 1).map(String.init)
        let kind = parts.count == 2 ? Registry.app.name(of: parts[1]) : nil
        let warning = warning(for: right)
        switch parts[0] {
        case "state": return ("See your agents", "Which agents run on this Mac, what each one is doing, and its last messages. It only reads.", nil, "eye")
        case "send": return ("Write to your \(kind.map { $0 + " " } ?? "")agents",
                             "Send a message to an agent you pick, stop it, or change its settings. It shows in that agent’s own conversation.", nil, "message")
        case "launch": return ("Start \(kind ?? "agents")",
                               "Launch \(kind == nil ? "one of your agents" : "it") in a folder." + (warning == nil ? " Anything that agent then needs still asks you." : ""),
                               warning, "play")
        case "store": return ("Remember things", "Keep a small memory in its own folder, so it knows what you saw last time.", nil, "note.text")
        default: return (right, "", nil, "shield")
        }
    }

    /// The sheet that asks whether `space` may put an agent of `kind` in `mode`; "Allow" is its first button. The
    /// folder is shown from `home`.
    static func lowers(_ mode: String, kind: String, folder: String?, space: String, home: String = NSHomeDirectory()) -> NSAlert {
        alert("Let “\(space)” put \(Registry.app.name(of: kind)) in a mode where it \(words(forMode: mode)) (\(mode))?",
              "The agent works in \(folder.map { Words.path($0, home: home) } ?? "a folder something does not know"). In this mode it asks you less before it acts.",
              buttons: ["Allow", "Don't Allow"], escape: 1)
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

    /// Help › What something Does and Doesn't: two columns, and the promise.
    static func doesAndDoesnt() -> NSAlert {
        alert("What something does and doesn't", accessory: NSHostingView(rootView: Promise()))
    }

    /// A right's word and the name of the agent kind it narrows to, nil for all of them: "launch:pi" is ("launch", "pi").
    static func parts(of right: String) -> (word: String, kind: String?) {
        let parts = right.split(separator: ":", maxSplits: 1).map(String.init)
        return (parts.first ?? right, parts.count == 2 ? Registry.app.name(of: parts[1]) : nil)
    }

    /// What a right lets the space do, in plain words: the title of its box in the rights sheet.
    static func title(for right: String) -> String {
        let (word, kind) = parts(of: right)
        switch word {
        case "state": return "See your agents and what they say"
        case "send": return "Write to your \(kind.map { $0 + " " } ?? "")agents, stop them, change their settings"
        case "launch": return "Start \(kind ?? "agents") in a folder you choose"
        case "store": return "Remember things on this Mac"
        default: return right
        }
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
