// The Mac app: the menu bar icon, the Edit menu, one Engine for every space window, the state pushed to the windows
// at most four times a second, and quitting, which stops the agents something launched.
import AppKit
import SomethingAgents
import SomethingCore
import WebKit

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// The space the app opens: a name in the spaces folder or a path; nil for the template.
    let opening: String?
    let places = Places.person
    let engine = Engine(environment: ProcessInfo.processInfo.environment)
    let ask = NativeAsk()
    var windows: [SpaceWindow] = []
    var statusItem: NSStatusItem?
    var pushing = false
    /// Lockdown's rule list, compiled before the first window opens.
    var rules: WKContentRuleList?

    init(opening: String?) {
        self.opening = opening
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = App.mainMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.grid.2x2", accessibilityDescription: "something")
        item.menu = NSMenu()
        item.menu?.delegate = self
        statusItem = item
        engine.changed = { [weak self] in self?.schedulePush() }
        engine.start(often: true)
        Task { @MainActor in
            do { rules = try await Lockdown.ruleList() } catch { fail((error as? SpaceError)?.message ?? "\(error)") }
            openSpace()
        }
    }

    /// Opens the space the app was started with, or fronts its window. Until Home exists, that is the template
    /// (share/template.html) or the space named or given by path on the command line.
    @objc func openSpace() {
        let path = opening ?? Resources.share.appendingPathComponent("template.html").path
        guard let space = Spaces(root: places.spaces).locate(path) else {
            fail("There is no space \(path): give the name of a space in \(places.spaces.path), or the path of its .html file or folder.")
        }
        if let open = windows.first(where: { $0.space == space }) { return open.show() }
        guard let rules else { return }
        do {
            let window = try SpaceWindow(space: space, places: places, engine: engine, ask: ask, share: Resources.share, rules: rules)
            window.closed = { [weak self] closed in self?.windows.removeAll { $0 === closed } }
            windows.append(window)
            window.open()
            window.show()
        } catch {
            fail((error as? SpaceError)?.message ?? "\(error)")
        }
    }

    /// The engine may change many times a second; the windows hear of it at most every quarter of a second.
    func schedulePush() {
        guard !pushing else { return }
        pushing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.pushing = false
            self?.windows.forEach { $0.push() }
        }
    }

    /// The menus every Mac app has. Without an Edit menu, ⌘V, ⌘C, ⌘X and ⌘A do nothing in a page.
    static func mainMenu() -> NSMenu {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(withTitle: "Quit something", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        for submenu in [app, edit] {
            let item = NSMenuItem()
            item.submenu = submenu
            main.addItem(item)
        }
        return main
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Open the window", action: #selector(openSpace), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit something", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    // Closing the window keeps something in the menu bar, with its agents.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Asks first when agents something launched still run, then stops them all before quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = engine.state.agents.filter { $0.origin == "launched" && $0.alive == true }.count
        if running > 0, !Ask.quit(stopping: running) { return .terminateCancel }
        engine.stopAll(within: 5) { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
