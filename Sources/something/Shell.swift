// The Mac shell: an icon in the menu bar, one window showing a page, the agents, and the bridge between
// them. It asks the person through Ask.swift; what a page receives is decided in SomethingCore.
import AppKit
import SomethingCore
import WebKit

// The repository holds web/ (something's own files) and pages/ (the pages). Found from this source file's
// place, which holds while something runs with `swift run` from its clone.
let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let arguments = CommandLine.arguments

final class Shell: NSObject, NSApplicationDelegate, NSMenuDelegate, WKScriptMessageHandlerWithReply,
                   WKNavigationDelegate, BridgeHost {
    let pagesFolder = repository.appendingPathComponent("pages")
    var page = Shell.option("--page") ?? "chat"
    var pageStamp = Date.distantPast
    var sessions: [AgentProcess] = []
    var alwaysAllowed: Set<String> = []
    var asked: Set<String> = []
    var statusItem: NSStatusItem!
    var window: NSWindow!
    var web: WKWebView!
    var store: PageStore?

    static func option(_ name: String) -> String? {
        arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }

    var state: State { State(agents: sessions.map(\.agent)) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.grid.2x2", accessibilityDescription: "something")
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(PageScheme(app: repository.appendingPathComponent("web"), pages: pagesFolder),
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

        open(page: page)
        showWindow()
        // A page your agent is writing reloads as soon as it saves.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.reloadIfChanged() }
        startChecks()
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

    // MARK: Pages

    /// The pages: folders of pages/ that hold an index.html.
    var pageNames: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: pagesFolder.path)) ?? []
        return names.filter { FileManager.default.fileExists(atPath: pagesFolder.appendingPathComponent("\($0)/index.html").path) }.sorted()
    }

    func open(page name: String) {
        guard pageNames.contains(name) else {
            fail("No page \"\(name)\" in \(pagesFolder.path). A page is a folder there with an index.html.")
        }
        page = name
        store = PageStore(file: pagesFolder.appendingPathComponent("\(name)/.store.json"))
        window.title = "something · \(name)"
        pageStamp = stamp(of: name)
        web.load(URLRequest(url: URL(string: "something://pages/\(name)/")!))
    }

    @objc func choosePage(_ item: NSMenuItem) { open(page: item.title); showWindow() }

    /// The latest change among the page's files, hidden files (its memory) left out.
    func stamp(of name: String) -> Date {
        let folder = pagesFolder.appendingPathComponent(name)
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                   options: [.skipsHiddenFiles])
        return (files?.allObjects as? [URL] ?? []).compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }.max() ?? .distantPast
    }

    func reloadIfChanged() {
        let now = stamp(of: page)
        if now != pageStamp { pageStamp = now; web.reload() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Open the window", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(.separator())
        for name in pageNames {
            let item = menu.addItem(withTitle: name, action: #selector(choosePage(_:)), keyEquivalent: "")
            item.state = name == page ? .on : .off
        }
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
            print("asked: \(request.tool) \(request.about ?? "") · always would: \(request.always ?? "null") · answered: \(answer)")
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
