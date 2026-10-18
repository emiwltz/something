// The Mac app: the menu bar icon (Home, the open space, Quit), the Edit menu, one Engine, Home, one space window at a
// time, the spaces and exports LaunchServices hands it, the permission and question panels, the state pushed at most
// four times a second, and quitting, which asks first while agents something launched run, then stops them.
import AppKit
import SomethingAgents
import SomethingCore
import WebKit

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// The space named or given by path on the command line; nil to open what the start chooses (FirstRun.swift).
    let opening: String?
    let places = Places.person
    let engine = Engine(environment: ProcessInfo.processInfo.environment)
    let ask = NativeAsk()
    /// The open space. One at a time (design 9): opening another closes it.
    var current: SpaceWindow?
    lazy var home = Home(places: places, share: Resources.share, ask: ask)
    lazy var panels = Panels(source: engine)
    var statusItem: NSStatusItem?
    var pushing = false
    /// Lockdown's rule list, compiled before the first window opens.
    var rules: WKContentRuleList?
    /// What LaunchServices handed the app before it was ready to open anything; nil once it is.
    var handed: [URL]? = []

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
        home.open = { [weak self] space in
            if let problem = self?.open(space) { self?.ask.tell(problem) }
        }
        home.card.kinds = { [weak self] in self?.engine.state.kinds ?? [:] }
        home.card.agents = { [weak self] in self?.engine.state.agents ?? [] }
        home.card.window = { [weak self] name in self?.current.flatMap { $0.kept && $0.space.name == name ? $0 : nil } }
        panels.who = { [weak self] request in self?.who(request) ?? "An agent" }
        engine.changed = { [weak self] in self?.schedulePush() }
        // This program's main routes `something hook permission`, inside the .app and under `swift run` alike.
        engine.hookCommand = Engine.ownHookCommand
        engine.start(often: false)
        Task { @MainActor in
            do { rules = try await Lockdown.ruleList() } catch { fail(error.sentence) }
            do {
                try FirstRun.prepare(places)
                if let problem = FirstRun.welcome(places, examples: home.examples) { ask.tell(problem) }
            } catch { fail(error.sentence) }
            // A space deleted or renamed while the app was not running loses its grants before any space opens.
            home.forgetGone()
            let early = handed ?? []
            handed = nil
            if let opening, (opening as NSString).pathExtension == "something" {
                receive(URL(fileURLWithPath: opening).standardizedFileURL)
            } else if let opening {
                guard let space = Spaces(root: places.spaces).locate(opening) else {
                    fail("There is no space \(opening): give the name of a space in \(places.spaces.path), or the path of its .html file or folder.")
                }
                if let problem = open(space) { fail(problem) }
            } else if !early.isEmpty {
                early.forEach(receive)
            } else if let space = FirstRun.first(places) {
                // A default space that cannot open says why, and Home shows in its place.
                if let problem = open(space) {
                    ask.tell(problem)
                    home.show()
                }
            } else {
                home.show()
            }
        }
    }

    /// `something open`, a double click on an export, or a file dropped on the Dock icon. It may come before the app
    /// is ready, and then waits for it.
    func application(_ application: NSApplication, open urls: [URL]) {
        if handed != nil { handed?.append(contentsOf: urls) } else { urls.forEach(receive) }
    }

    /// Imports an export into Home, or opens a space.
    func receive(_ url: URL) {
        if url.pathExtension == "something" {
            home.show()
            return home.importSpace(from: url)
        }
        guard let space = Spaces(root: places.spaces).locate(url.path) else {
            return ask.tell("\(url.path) is not a space: something opens an .html file, a folder with an index.html, or an export (.something).")
        }
        if let problem = open(space) { ask.tell(problem) }
    }

    /// Opens `space` in the space window, or fronts it when it is the open one. Returns what went wrong, or nil.
    func open(_ space: Space) -> String? {
        if let current, App.same(current.space, space) {
            current.show()
            return nil
        }
        guard let rules else { return "something is still starting; try again in a moment." }
        do {
            let window = try SpaceWindow(space: space, places: places, engine: engine, ask: ask, share: Resources.share, rules: rules)
            // Closing its window closes the space; a space whose window was never shown is closed directly.
            if let shown = current?.window {
                shown.close()
            } else {
                current?.close()
            }
            window.closed = { [weak self] closed in
                guard let self, current === closed else { return }
                current = nil
                engine.start(often: false)
            }
            current = window
            // The readers look often while a space is open, and rarely when nobody is looking.
            engine.start(often: true)
            window.open()
            window.show()
            return nil
        } catch {
            return error.sentence
        }
    }

    /// Whether two spaces are one, however their paths are written.
    static func same(_ one: Space, _ other: Space) -> Bool {
        one.location.resolvingSymlinksInPath().path == other.location.resolvingSymlinksInPath().path
    }

    /// Who asks, for a panel ("Claude Code “shop”, working in /Users/example/code/shop, asks…"): the agent's name and
    /// folder, and the open space when it launched the agent.
    func who(_ request: Request) -> String {
        let launcher = current.flatMap { $0.launched.contains(request.agent) ? $0.title : nil }
        return App.who(engine.state.agents.first { $0.id == request.agent }, launchedBy: launcher)
    }

    /// Who `agent` is, in words, with the title of the space that launched it when one did; "An agent" when the
    /// state no longer holds it.
    static func who(_ agent: Agent?, launchedBy space: String?) -> String {
        guard let agent else { return "An agent" }
        var words = Programs.name(of: agent.kind)
        if let name = agent.name { words += " “\(name)”" }
        if let folder = agent.folder { words += ", working in \(folder)," }
        if let space { words += " launched by “\(space)”," }
        return words
    }

    @objc func showHome() { home.show() }

    @objc func showCurrent() { current?.show() }

    /// The engine may change many times a second; the windows hear of it at most every quarter of a second.
    func schedulePush() {
        guard !pushing else { return }
        pushing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.pushing = false
            self?.current?.push()
            self?.panels.refresh()
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
        menu.addItem(withTitle: "Home", action: #selector(showHome), keyEquivalent: "").target = self
        if let current { menu.addItem(withTitle: current.title, action: #selector(showCurrent), keyEquivalent: "").target = self }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit something", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    // Closing the window keeps something in the menu bar, with its agents.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// A click on the Dock icon with no window open shows Home.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { home.show() }
        return true
    }

    /// Asks first when agents something launched still run, then stops them all before quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = engine.state.agents.filter { $0.origin == "launched" && $0.alive == true }.count
        if running > 0, Ask.run(Ask.quit(running)) != .alertFirstButtonReturn { return .terminateCancel }
        engine.stopAll(within: 5) { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    /// Ends the app at its start, before any agent was launched: in a window, which is all a person sees when the app
    /// was not started from a terminal, and in the terminal. Later failures go through `ask.tell`, never here, so
    /// that quitting always stops the agents.
    func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        ask.tell(message)
        exit(1)
    }
}
