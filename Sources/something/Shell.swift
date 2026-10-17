// The Mac shell: an icon in the menu bar, one window showing a page, the agents, and the bridge between
// them. It asks the person through Ask.swift; what a page receives is decided in SomethingCore.
import AppKit
import SomethingAgents
import SomethingCore
import WebKit

let arguments = CommandLine.arguments

final class Shell: NSObject, NSApplicationDelegate, NSMenuDelegate, WKScriptMessageHandlerWithReply,
                   WKNavigationDelegate, BridgeHost {
    // Until spaces exist, the window shows share/template.html, served as something://app/template.html.
    let page = "template"
    var pageStamp = Date.distantPast
    var sessions: [AgentProcess] = []
    var alwaysAllowed: Set<String> = []
    var asked: Set<String> = []
    var statusItem: NSStatusItem!
    var window: NSWindow!
    var web: WKWebView!
    var store: PageStore?
    var pasted = false

    static func option(_ name: String) -> String? {
        arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }

    var state: State { State(agents: sessions.map(\.agent)) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Shell.mainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.grid.2x2", accessibilityDescription: "something")
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(PageScheme(app: Resources.share),
                                   forURLScheme: "something")
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "something")
        web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        window.center()

        openPage()
        showWindow()
        // A page your agent is writing reloads as soon as it saves.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.reloadIfChanged() }
        startChecks()
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

    // Closing the window keeps something in the menu bar, with its agents.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = sessions.filter { $0.agent.status != "stopped" }.count
        guard running > 0, !checking else { return .terminateNow }
        return Ask.quit(stopping: running) ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessions.forEach { $0.stop() }
    }

    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: The page

    var pageFile: URL { Resources.share.appendingPathComponent("\(page).html") }

    func openPage() {
        guard FileManager.default.fileExists(atPath: pageFile.path) else {
            fail("No page at \(pageFile.path). Reinstall something, or restore share/ in its clone.")
        }
        // The page's memory lives in the person's data folder: share/ is part of something, and read-only in the app.
        // $HOME first, so that a trial with a throwaway home never touches the person's own folder.
        let home = ProcessInfo.processInfo.environment["HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let data = home.appendingPathComponent("something/data")
        try? FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        store = PageStore(file: data.appendingPathComponent("\(page).json"))
        window.title = "something · \(page)"
        pageStamp = stamp()
        web.load(URLRequest(url: URL(string: "something://app/\(page).html")!))
    }

    func stamp() -> Date {
        (try? pageFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    func reloadIfChanged() {
        let now = stamp()
        if now != pageStamp { pageStamp = now; web.reload() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Open the window", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit something", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    // MARK: BridgeHost: what the bridge asks of this shell

    static let harnesses = ["claude", "codex", "opencode", "pi"]

    func launch(harness: String) throws -> String {
        guard Shell.harnesses.contains(harness) else {
            throw BridgeError("something cannot launch \"\(harness)\" yet. It can launch: \(Shell.harnesses.joined(separator: ", ")).")
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose the folder \(Ask.name(of: harness)) will work in."
        panel.prompt = "Launch \(Ask.name(of: harness)) here"
        guard panel.runModal() == .OK, let folder = panel.url else { throw BridgeError("No folder chosen.") }
        return try start(harness, in: folder).agent.id
    }

    func send(agent id: String, text: String) throws {
        guard let session = sessions.first(where: { $0.agent.id == id }) else {
            throw BridgeError("No agent \"\(id)\". Ask for the state to see the agents.")
        }
        if !alwaysAllowed.contains(id) {
            switch Ask.send(text, to: session.agent) {
            case .once: break
            case .always: alwaysAllowed.insert(id)
            case .refused: throw BridgeError("You refused to send this message.")
            }
        }
        try session.send(text)
    }

    /// Launches an agent with the person's own configuration. The checks may ask it to ask before
    /// every action (`forceAsk`) or to use another model for this conversation (`model`).
    func start(_ harness: String, in folder: URL, forceAsk: Bool = false, model: String? = nil) throws -> AgentProcess {
        let id = "\(harness)-\(sessions.filter { $0.agent.harness == harness }.count + 1)"
        let session: AgentProcess
        switch harness {
        case "codex":
            session = CodexSession(id: id, folder: folder, threadOptions: forceAsk ? ["approvalPolicy": "untrusted"] : [:])
        case "opencode":
            session = ACPSession(id: id, folder: folder, harness: harness, arguments: ["opencode", "acp"],
                                 settings: model.map { ["model": $0] } ?? [:],
                                 adding: forceAsk ? ["OPENCODE_CONFIG_CONTENT": #"{"permission":{"edit":"ask","bash":"ask"}}"#] : [:])
        case "pi":
            session = PiSession(id: id, folder: folder, model: model)
        default:
            session = ClaudeSession(id: id, folder: folder)
        }
        session.onChange = { [weak self] agent in
            DispatchQueue.main.async { self?.changed(session, agent) }
        }
        try session.start()
        sessions.append(session)
        pushState()
        return session
    }

    func changed(_ session: AgentProcess, _ agent: Agent) {
        pushState()
        askPermission(of: session, agent)
        checkTurn(of: session, agent)
    }

    /// Shows the agent's permission request in a native window, once per request. A page sees that the
    /// agent waits (`request` in the state) but cannot answer for the person.
    func askPermission(of session: AgentProcess, _ agent: Agent) {
        guard let request = agent.request, !asked.contains(request.id) else { return }
        asked.insert(request.id)
        let answer: PermissionAnswer
        if let scripted = scriptedAnswer {
            answer = scripted
            print("asked: \(request.tool) \(request.about ?? "") · answered: \(answer)")
        } else {
            showWindow()
            answer = Ask.permission(request, of: agent)
        }
        do { try session.answer(request.id, answer) } catch { pushState() }
    }

    /// Tells the page the state changed; something.js passes it to the page's subscribers.
    func pushState() {
        guard let data = try? JSONSerialization.data(withJSONObject: Bridge.json(state)) else { return }
        web.evaluateJavaScript("window.something && something._changed(\(String(decoding: data, as: UTF8.self)))")
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        let request = message.body as? [String: Any] ?? [:]
        replyHandler(Bridge.answer(request, host: self), nil)
    }

    func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
