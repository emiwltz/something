// The one list of the app's commands, and the menu bar made from it. Each command has its menu words, its key, the
// action it sends, the slice that wires it, and its line in the shortcut sheet; the menus, the tooltips, Settings ›
// Shortcuts, the ⌘/ sheet and ⌘P all read it, so a key cannot say two things. The table and the menus are the
// mockup's (Tests/Fixtures/mockup), checked both ways. A command not wired yet has no action: its item is present and
// greyed, never hidden. The keys marked `mine` are something's even while a page has the focus: WebKit would hand them
// to the page first, so the app's key monitor gives them to the menu before it (share/guide.md says so).
import AppKit

enum Keys {
    struct Command {
        /// The shortcut sheet's areas, in its order.
        enum Area: String, CaseIterable { case spaces = "Spaces", assistant = "Assistant", show = "Show", window = "Window" }

        let id: String
        /// The menu's words.
        let title: String
        /// The key equivalent, "" for none; "\u{8}" is ⌫.
        var key = ""
        var modifiers: NSEvent.ModifierFlags = .command
        /// What it sends through the responder chain; nil until `owner` wires it.
        var action: Selector?
        /// The slice that wires it, or that built it when it already works.
        let owner: String
        /// Where the shortcut sheet lists it, in its own words; nil when the sheet does not.
        var area: Area?
        var line: String?
        /// A key that is no menu key, said in words ("esc", "hold ⌥", "⌘1 … ⌘9"): it works only where the sheet says.
        var words: String?
        /// Whether something keeps the key while a page has the focus.
        var mine = false
        /// Whether it acts on the open space, and is greyed while none is open.
        var needsSpace = false

        /// The key as the Mac writes it: "⇧⌘K", "⌥⌘R", "⌘⌫"; the words for a key that is no key equivalent; "" for none.
        var shown: String { words ?? (key.isEmpty ? "" : Keys.symbols(modifiers) + Keys.name(key)) }
    }

    /// A selector by name: the actions are App's or AppKit's responders', found through the responder chain.
    private static func app(_ name: String) -> Selector { Selector(name) }

    /// Every command, the shortcut sheet's in its order first.
    static let commands: [Command] = [
        Command(id: "palette", title: "Go to…", key: "p", owner: "G2", area: .spaces, line: "Go to a space, or ask", mine: true),
        Command(id: "new", title: "New Space", key: "n", action: app("newSpace:"), owner: "F5", area: .spaces, line: "New Space", mine: true),
        Command(id: "tpls", title: "Templates", key: "t", modifiers: [.command, .shift], action: app("showTemplates:"), owner: "F5",
                area: .spaces, line: "Templates", mine: true),
        Command(id: "goto", title: "Go to Space", owner: "F5", area: .spaces, line: "Go to space 1 to 9", words: "⌘1 … ⌘9", mine: true),
        Command(id: "reload", title: "Reload Space", key: "r", action: app("reloadSpace:"), owner: "F5", area: .spaces, line: "Reload space",
                mine: true, needsSpace: true),
        Command(id: "insp", title: "Show Info", key: "i", action: app("toggleInfo:"), owner: "W4", area: .spaces, line: "Space info",
                mine: true, needsSpace: true),
        Command(id: "escpanel", title: "Close Info or History", owner: "W4", area: .spaces, line: "Close Info or History", words: "esc"),
        Command(id: "ask", title: "Ask…", key: "k", action: app("askAssistant:"), owner: "F5", area: .assistant,
                line: "Talk to this space’s assistant", mine: true, needsSpace: true),
        Command(id: "convo", title: "Show Conversation", key: "j", action: app("showConversation:"), owner: "F5", area: .assistant,
                line: "Show or hide the conversation", mine: true, needsSpace: true),
        Command(id: "newconvo", title: "New Conversation", key: "k", modifiers: [.command, .shift], action: app("newConversation:"),
                owner: "AB09b", area: .assistant, line: "New conversation", mine: true, needsSpace: true),
        Command(id: "reduce", title: "Reduce or Open", key: "\\", owner: "AB05", area: .assistant, line: "Reduce or open the assistant",
                mine: true, needsSpace: true),
        // Stop also works on the New Space page, where a build runs before its space exists.
        Command(id: "stop", title: "Stop", key: ".", action: app("stopAssistant:"), owner: "F5", area: .assistant, line: "Stop the assistant",
                mine: true),
        Command(id: "showreq", title: "Show Request", key: "p", modifiers: [.command, .option], owner: "T5", area: .assistant,
                line: "Show the request that waits", mine: true),
        Command(id: "pointpart", title: "Point at a Part", key: "s", modifiers: [.command, .option], owner: "T14", area: .show,
                line: "Point at a part", mine: true, needsSpace: true),
        Command(id: "point", title: "Point Inside a Drawn Frame", owner: "T14", area: .show, line: "Point inside a drawn frame", words: "hold ⌥"),
        Command(id: "undo", title: "Undo", key: "z", action: app("undo:"), owner: "T13", area: .show, line: "Undo the last change"),
        Command(id: "full", title: "Enter Full Screen", key: "f", modifiers: [.command, .control], action: app("toggleFullScreen:"),
                owner: "W5", area: .window, line: "Full screen", mine: true),
        Command(id: "sidebar", title: "Show Sidebar", key: "s", modifiers: [.command, .control], action: app("toggleSidebar:"),
                owner: "W2", area: .window, line: "Show or hide the sidebar", mine: true),
        Command(id: "settings", title: "Settings…", key: ",", owner: "G4", area: .window, line: "Settings", mine: true),
        Command(id: "keys", title: "Keyboard Shortcuts", key: "/", owner: "G1", area: .window, line: "Keyboard shortcuts", mine: true),
        Command(id: "close", title: "Close Window", key: "w", action: app("performClose:"), owner: "F5", area: .window, line: "Close window"),
        // Only in the menus.
        Command(id: "about", title: "About something", action: app("showAbout:"), owner: "F5"),
        Command(id: "hide", title: "Hide something", key: "h", action: app("hide:"), owner: "F5"),
        Command(id: "hideOthers", title: "Hide Others", key: "h", modifiers: [.command, .option], action: app("hideOtherApplications:"), owner: "F5"),
        Command(id: "showAll", title: "Show All", action: app("unhideAllApplications:"), owner: "F5"),
        Command(id: "quit", title: "Quit something", key: "q", action: app("terminate:"), owner: "F5"),
        Command(id: "import", title: "Import Space…", action: app("importSpace:"), owner: "F5"),
        Command(id: "export", title: "Export Space…", key: "e", modifiers: [.command, .shift], action: app("exportSpace:"), owner: "F5",
                needsSpace: true),
        Command(id: "finder", title: "Show in Finder", key: "r", modifiers: [.command, .option], action: app("showInFinder:"), owner: "F5",
                needsSpace: true),
        Command(id: "trash", title: "Move to Trash…", key: "\u{8}", action: app("moveToTrash:"), owner: "T8", needsSpace: true),
        Command(id: "redo", title: "Redo", key: "z", modifiers: [.command, .shift], action: app("redo:"), owner: "T13"),
        Command(id: "cut", title: "Cut", key: "x", action: app("cut:"), owner: "F5"),
        Command(id: "copy", title: "Copy", key: "c", action: app("copy:"), owner: "F5"),
        Command(id: "paste", title: "Paste", key: "v", action: app("paste:"), owner: "F5"),
        Command(id: "selectAll", title: "Select All", key: "a", action: app("selectAll:"), owner: "F5"),
        Command(id: "history", title: "Show History…", owner: "T19", needsSpace: true),
        Command(id: "rights", title: "What It May Do…", owner: "W4", needsSpace: true),
        Command(id: "versions", title: "Versions…", owner: "T19", needsSpace: true),
        // The menu item only holds the submenu; its selector is there so that the app can grey it.
        Command(id: "buildWith", title: "Build With", action: app("buildWith:"), owner: "AB11", needsSpace: true),
        Command(id: "askAll", title: "Ask Before Every Change…", owner: "G5"),
        Command(id: "sleep", title: "Put Idle Assistants to Sleep", owner: "AB10"),
        Command(id: "minimize", title: "Minimize", key: "m", action: app("performMiniaturize:"), owner: "F5"),
        Command(id: "zoom", title: "Zoom", action: app("performZoom:"), owner: "W1"),
        Command(id: "front", title: "Bring All to Front", action: app("arrangeInFront:"), owner: "F5"),
        Command(id: "help", title: "something Help", action: app("openHelp:"), owner: "G7"),
        Command(id: "promise", title: "What something Does and Doesn’t", action: app("showPromise:"), owner: "G7"),
        Command(id: "guide", title: "Guide for Coding Agents", action: app("showGuide:"), owner: "G7"),
        Command(id: "tour", title: "Welcome Tour", action: app("showTour:"), owner: "F5"),
        Command(id: "send", title: "Send Comments", owner: "T18", words: "⌘↵"),
    ]

    static func command(_ id: String) -> Command? { commands.first { $0.id == id } }

    /// "⌘K" for `id`, "" when it has no key: for tooltips and sentences.
    static func shown(_ id: String) -> String { command(id)?.shown ?? "" }

    /// A tooltip: the words, then the key in parentheses when there is one.
    static func tooltip(_ id: String) -> String {
        guard let command = command(id) else { return "" }
        return command.shown.isEmpty ? command.title : "\(command.title) (\(command.shown))"
    }

    static func symbols(_ modifiers: NSEvent.ModifierFlags) -> String {
        [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { modifiers.contains($0.0) }.map(\.1).joined()
    }

    static func name(_ key: String) -> String { key == "\u{8}" ? "⌫" : key.uppercased() }

    // MARK: The menus

    /// One line of a menu: a command's item (with its own words when the menu says it differently), a separator, a
    /// section header, the spaces (Go), or a submenu the system fills (Services).
    enum Entry {
        case item(String, String? = nil)
        case separator
        case header(String)
        case spaces
        case services
    }

    /// The menu bar, as the mockup has it. The headers of Space and Assistant, and Go's spaces, are filled by MenuBar.
    static let menus: [(title: String, entries: [Entry])] = [
        ("something", [.item("about"), .separator, .item("settings"), .separator, .services, .separator,
                       .item("hide"), .item("hideOthers"), .item("showAll"), .separator, .item("quit")]),
        ("File", [.item("new"), .item("tpls", "New from Template…"), .separator, .item("import"), .item("export"), .separator,
                  .item("finder"), .item("trash"), .separator, .item("close")]),
        ("Edit", [.item("undo"), .item("redo"), .separator, .item("cut"), .item("copy"), .item("paste"), .item("selectAll")]),
        ("View", [.item("sidebar"), .item("insp"), .separator, .item("history"), .item("keys", "Show Keyboard Shortcuts"), .separator,
                  .item("reload"), .separator, .item("full")]),
        ("Go", [.item("palette"), .separator, .header("Spaces"), .spaces, .separator, .item("new"), .item("tpls")]),
        ("Space", [.header("space"), .item("insp", "Space Info"), .item("reload", "Reload"), .item("rights"), .item("versions"), .separator,
                   .item("finder"), .item("export", "Export…"), .separator, .item("trash")]),
        ("Assistant", [.header("assistant"), .item("ask"), .item("convo"), .item("newconvo"), .item("reduce"), .item("stop"),
                       .item("showreq"), .separator, .item("pointpart"), .separator, .item("buildWith"), .item("askAll"), .separator,
                       .item("sleep")]),
        ("Window", [.item("minimize"), .item("zoom"), .separator, .item("front")]),
        ("Help", [.item("help"), .item("keys"), .item("promise"), .item("guide"), .separator, .item("tour")]),
    ]

    /// The menu bar made from `menus`, every item acting through the responder chain. Each command's item carries
    /// the command's id; the header of a menu that names the open space carries "header.<menu>".
    static func menu() -> NSMenu {
        let main = NSMenu()
        for (title, entries) in menus {
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            holder.submenu = menu
            for entry in entries {
                switch entry {
                case .separator: menu.addItem(.separator())
                case .spaces: break
                case .services:
                    let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
                    services.submenu = NSMenu(title: "Services")
                    menu.addItem(services)
                case .header(let words):
                    let header = NSMenuItem.sectionHeader(title: words == "space" || words == "assistant" ? "No space open" : words)
                    if words == "space" || words == "assistant" { header.identifier = NSUserInterfaceItemIdentifier("header." + words) }
                    menu.addItem(header)
                case .item(let id, let words):
                    guard let command = command(id) else { continue }
                    let item = NSMenuItem(title: words ?? command.title, action: command.action, keyEquivalent: command.key)
                    item.keyEquivalentModifierMask = command.modifiers
                    item.identifier = NSUserInterfaceItemIdentifier(id)
                    if id == "buildWith" { item.submenu = NSMenu(title: "Build With") }
                    menu.addItem(item)
                }
            }
            main.addItem(holder)
        }
        return main
    }

    // MARK: When an item can act

    /// What the items' enabled state depends on.
    struct Situation {
        var space = false, working = false, agent = true, touring = false, editingText = false
    }

    /// Whether the item of `id` can act in `situation`: never before its owner wires it, never without a space when it
    /// acts on one.
    static func enabled(_ id: String, _ situation: Situation) -> Bool {
        guard let command = command(id) else { return true }
        guard command.action != nil, !(command.needsSpace && !situation.space) else { return false }
        switch id {
        case "stop": return situation.working
        case "ask": return situation.agent
        case "new", "tpls": return !situation.touring
        // ⌘⌫ deletes text in a field; the item steps aside (MenuBar also takes its key away).
        case "trash": return !situation.editingText
        default: return true
        }
    }

    /// Whether `event` is a key something keeps from a page: a `mine` command's, or ⌘1 to ⌘9.
    static func claims(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command, let digit = Int(key), (1...9).contains(digit) { return true }
        return commands.contains { $0.mine && !$0.key.isEmpty && $0.key == key && $0.modifiers == modifiers }
    }

    // MARK: About

    /// "Version 0.3.0 (31)" from `bundle`'s Info.plist; "Version dev" from a clone.
    static func versionLine(_ bundle: Bundle) -> String {
        let short = Resources.version(of: bundle), build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return "Version \(short)" + (build.map { " (\($0))" } ?? "")
    }

    /// The About panel's contents: the sign (the app's icon), its version line, and the promise.
    static func about(_ bundle: Bundle) -> [NSApplication.AboutPanelOptionKey: Any] {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        let credits = NSAttributedString(string: "Spaces you build with your own coding agent, on your Mac.\n\nNothing leaves this Mac.",
                                         attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .paragraphStyle: centered,
                                                      .foregroundColor: NSColor.secondaryLabelColor])
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        // The panel writes "Version <applicationVersion> (<version>)" itself, as versionLine says it.
        return [.applicationName: "something", .applicationVersion: Resources.version(of: bundle), .version: build ?? "",
                .applicationIcon: NSApplication.shared.applicationIconImage as Any, .credits: credits]
    }
}

/// The menu bar while the app runs: Go lists the spaces with ⌘1 to ⌘9 and checks the open one, the headers of Space
/// and Assistant name it, and ⌘⌫ is Move to Trash only while no text is being edited. It is made again each time a
/// menu opens or a key reaches it.
final class MenuBar: NSObject, NSMenuDelegate {
    let menu = Keys.menu()
    /// The spaces in the sidebar's order.
    var spaces: () -> [(id: String, title: String)] = { [] }
    /// The open space, nil when none is.
    var open: () -> (id: String, title: String)? = { nil }
    /// Whether text is being edited in a native field, where ⌘⌫ deletes.
    var editingText: () -> Bool = { false }

    /// `builders` fills Build With ▸ each time it opens.
    init(builders: NSMenuDelegate?) {
        super.init()
        ["Go", "Space", "Assistant", "File"].forEach { submenu($0)?.delegate = self }
        submenu("Assistant")?.items.first { $0.identifier?.rawValue == "buildWith" }?.submenu?.delegate = builders
    }

    func submenu(_ title: String) -> NSMenu? { menu.item(withTitle: title)?.submenu }

    /// Gives the app its menus, and the system its Window, Help and Services menus to fill.
    func install() {
        NSApp.mainMenu = menu
        NSApp.windowsMenu = submenu("Window")
        NSApp.helpMenu = submenu("Help")
        NSApp.servicesMenu = submenu("something")?.item(withTitle: "Services")?.submenu
    }

    func menuNeedsUpdate(_ menu: NSMenu) { refresh() }

    /// Brings Go, the headers and ⌘⌫ up to date.
    func refresh() {
        let open = open()
        let possessive = open.map { $0.title + ($0.title.lowercased().hasSuffix("s") ? "’" : "’s") + " assistant" }
        for (menu, title) in [("Space", open?.title), ("Assistant", possessive)] {
            submenu(menu)?.items.first { $0.identifier?.rawValue == "header.\(menu.lowercased())" }?.title = title ?? "No space open"
        }
        let trash = Keys.command("trash")?.key ?? ""
        for item in ["File", "Space"].compactMap({ submenu($0) }).flatMap(\.items) where item.identifier?.rawValue == "trash" {
            item.keyEquivalent = editingText() ? "" : trash
        }
        guard let go = submenu("Go"), let header = go.items.firstIndex(where: { $0.isSectionHeader }) else { return }
        go.items.filter { $0.identifier?.rawValue.hasPrefix("space:") == true }.forEach(go.removeItem)
        for (index, space) in spaces().enumerated() {
            let item = NSMenuItem(title: space.title, action: #selector(App.goToSpace(_:)), keyEquivalent: index < 9 ? "\(index + 1)" : "")
            (item.identifier, item.representedObject) = (NSUserInterfaceItemIdentifier("space:" + space.id), space.id)
            item.state = space.id == open?.id ? .on : .off
            go.insertItem(item, at: header + 1 + index)
        }
    }
}
