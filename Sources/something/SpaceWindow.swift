// The window of one open space (design 5): one WKWebView with a new non-persistent data store at each opening, the
// app's page (something://app/) holding the space in a sandboxed frame, something.js and the space's `granted`
// injected in that frame before its scripts, the something:// scheme as its only source, every navigation away from
// it cancelled (a clicked http, https or mailto link goes to the link window), no new window, and a reload when a file
// of the space changes. The rights are asked at the opening and at each reload, before the page runs. What the
// space's calls do is in SpaceBridge.swift.
import AppKit
import SomethingAgents
import SomethingCore
import WebKit

final class SpaceWindow: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, NSWindowDelegate {
    let space: Space, places: Places, engine: Engine, ask: Asking
    /// Whether the space lives in the spaces folder. Only such a space has a memory and a journal, which go by its name.
    let kept: Bool
    let web: WKWebView
    private(set) var window: NSWindow?
    private(set) var title: String
    private(set) var granted = Granted()
    var launched: Set<String> = []
    /// The problems that keep the space from being displayed; empty while it is displayed.
    private(set) var blocked: [Problem] = []
    var linkOpen = false, linksBlocked = false
    var closed: (SpaceWindow) -> Void = { _ in }
    private let bridge: String, scheme: Scheme
    private var stamp: Date?
    private var timer: Timer?
    private var pushed: State?
    /// The answers for a space opened by path, kept for the life of the window only: kept in app.json under its path,
    /// they would pass to whatever file lands at that path later, and a space never inherits rights (contract 5).
    private var held: Grant?
    /// The declaration as the last load read it: the one the person was asked about. A switch in the card applies
    /// new answers to it, never to a newer file that no rights window has shown yet.
    private var reading: DeclarationReading?
    /// The frame that holds the space, once the app's page has asked to load it: pushes and `granted` go to it. The
    /// bridge and the link window answer the frame `isSpace` recognizes, which the navigation policy makes this same
    /// frame. nil before, while the space is blocked, and from each new load of the app's page until its frame asks.
    private(set) var frame: WKFrameInfo?

    /// A window for `space`, not yet shown. `share` is the folder of something.js; `rules` is Lockdown's rule list.
    /// Throws a `SpaceError` when something.js cannot be read: without it the space could not reach anything.
    init(space: Space, places: Places, engine: Engine, ask: Asking, share: URL, rules: WKContentRuleList) throws {
        bridge = try SpaceWindow.bridge(share)
        self.space = space
        self.places = places
        self.engine = engine
        self.ask = ask
        title = space.name
        kept = SpaceWindow.isKept(space, places)
        scheme = Scheme(space: space)
        web = SpaceWindow.webView(scheme, rules: rules)
        super.init()
        SpaceWindow.hold(web, by: self)
    }

    /// The text of something.js in `share`. Throws a `SpaceError` when it cannot be read: without it the space could
    /// not reach anything.
    static func bridge(_ share: URL) throws -> String {
        let file = share.appendingPathComponent("something.js")
        guard let bridge = try? String(contentsOf: file, encoding: .utf8) else {
            throw SpaceError("something cannot read \(file.path); reinstall something, or restore share/ in its clone.")
        }
        return bridge
    }

    /// Whether `space` is the one of that name in the spaces folder, the only kind that has a memory and a journal.
    static func isKept(_ space: Space, _ places: Places) -> Bool {
        Spaces(root: places.spaces).named(space.name).map { App.same($0, space) } ?? false
    }

    /// What answers a web view that holds a space: its calls, its clicked links and its navigations.
    typealias Holder = NSObject & WKNavigationDelegate & WKUIDelegate & WKScriptMessageHandler & WKScriptMessageHandlerWithReply

    /// A web view for a space, the app's window's and the check's alike: `scheme` as its only source and Lockdown's
    /// `rules`. Nothing answers it until `hold` gives it its holder.
    static func webView(_ scheme: Scheme, rules: WKContentRuleList) -> WKWebView {
        let config = WKWebViewConfiguration()
        // A new store at each opening: localStorage and cookies end with the window, and no space reads another's.
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(scheme, forURLScheme: Scheme.name)
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        // Safe Browsing looks addresses up on the Internet.
        config.preferences.isFraudulentWebsiteWarningEnabled = false
        config.userContentController.add(rules)
        return WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 640), configuration: config)
    }

    /// Makes `holder` answer `web`: the space's calls (something), the links Lockdown's guard hands over (link), and
    /// every navigation and new window.
    static func hold(_ web: WKWebView, by holder: Holder) {
        web.configuration.userContentController.addScriptMessageHandler(holder, contentWorld: .page, name: "something")
        web.configuration.userContentController.add(holder, contentWorld: Lockdown.world, name: "link")
        web.navigationDelegate = holder
        web.uiDelegate = holder
    }

    /// Stops `web` and lets its holder go: the message handlers keep their holder alive until they are removed.
    static func release(_ web: WKWebView) {
        web.stopLoading()
        web.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    /// Answers one call of a page: `answer` gives the answer when the call comes from the space's own frame and the
    /// space is `open`; any other call is refused (contract 4.4: never a frame inside the space, never the app's page).
    static func reply(_ message: WKScriptMessage, open: Bool, _ answer: ([String: Any]) -> [String: Any],
                      _ replyHandler: @escaping (Any?, String?) -> Void) {
        guard isSpace(message.frameInfo), open, let request = message.body as? [String: Any] else {
            return replyHandler(nil, "something answers only the page of the open space.")
        }
        replyHandler(answer(request), nil)
    }

    /// Hands the page in `frame` the state it sees, as JSON `data`.
    static func push(_ data: Data, in web: WKWebView, frame: WKFrameInfo) {
        web.evaluateJavaScript("window.something && something._push(\(String(decoding: data, as: UTF8.self)))", in: frame, in: .page)
    }

    /// Loads the space and watches its files: when one changes (checked each second), the space reloads.
    func open() {
        load()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.space.stamp() != self.stamp else { return }
            self.load()
        }
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
            present()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Reads the declaration, asks the rights that changed, then loads or reloads the page with the new `granted`;
    /// or, when the declaration keeps the space from being displayed, says why in the window.
    func load() {
        stamp = space.stamp()
        pushed = nil
        frame = nil
        linksBlocked = false
        let reading = Declaration.read(space, home: places.home)
        self.reading = reading
        blocked = reading.declaration == nil ? reading.problems.filter { Codes.all[$0.code]?.blocks == true } : []
        if let declaration = reading.declaration {
            title = declaration.title
            granted = Rights.granted(reading, answer(declaration), limits: Engine.limits, home: places.home)
            inject()
            web.load(URLRequest(url: Scheme.shell))
        } else {
            // The page the person can no longer see stops: its scripts, its timers and its links. The empty page has
            // an address of the app, as the navigation policy allows nothing else.
            web.configuration.userContentController.removeAllUserScripts()
            web.loadHTMLString("", baseURL: URL(string: "\(Scheme.name)://\(Scheme.app)/.blocked"))
        }
        present()
    }

    /// Puts the guards and the bridge, with the `granted` in force, before the scripts of every page the space loads.
    /// Every frame gets the guards: a frame inside the space has links too. WebKit injects in the main frame or in
    /// every frame; the bridge goes to the space's frame only, the one whose parent is the app's page.
    private func inject() {
        let controller = web.configuration.userContentController
        controller.removeAllUserScripts()
        SpaceWindow.scripts(bridge, granted).forEach(controller.addUserScript)
    }

    /// The guards, then something.js holding `granted`, for every page that holds a space (the check's too).
    static func scripts(_ bridge: String, _ granted: Granted) -> [WKUserScript] {
        let start = "if (window !== top && parent === top) {\n\(bridge)\nsomething._granted(\(json(granted)));\n}\n"
        return [WKUserScript(source: Lockdown.activationScript, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page),
                WKUserScript(source: Lockdown.guardScript, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: Lockdown.world),
                WKUserScript(source: start, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)]
    }

    /// Applies the person's answers as the grants file now keeps them, without asking and without a reload: the page
    /// hears a `granted` event, and the bridge answers by the new rights from its next call. The space's card calls it
    /// when a right is switched (contract 5: a revocation reaches an open space as a `granted` event).
    /// When the grants file does not read, the rights in force stay as they are and the failure is said.
    func regrant() {
        guard blocked.isEmpty, let reading, reading.declaration != nil else { return }
        var grant = held
        if kept {
            do { grant = try AppFile.read(places.grants).spaces[space.name] } catch {
                return ask.tell(error.sentence)
            }
        }
        granted = Rights.granted(reading, grant, limits: Engine.limits, home: places.home)
        inject()
        if let frame { web.evaluateJavaScript("window.something && something._granted(\(SpaceWindow.json(granted)))", in: frame, in: .page) }
        push()
    }

    /// The grant in force after this opening: the person is asked only what changed since they last answered. The
    /// answers for a space of the spaces folder are kept in the grants file, by its name. nil when nothing was ever
    /// answered or the file cannot be read.
    func answer(_ declaration: Declaration) -> Grant? {
        var file = AppFile()
        if kept {
            do { file = try AppFile.read(places.grants) } catch {
                ask.tell(error.sentence)
                return nil
            }
        }
        var grant = kept ? file.spaces[space.name] : held
        let toAsk = Rights.toAsk(declaration, since: grant)
        guard !toAsk.isEmpty, let answer = ask.rights(question(declaration, toAsk, grant)) else { return grant }
        grant = Rights.answered(declaration, allowed: answer.allowed, refused: answer.refused, folder: answer.folder,
                                at: ISO8601DateFormatter().string(from: Date()), after: grant)
        grant?.remap.merge(answer.remap) { $1 }
        guard kept else {
            held = grant
            return grant
        }
        file.spaces[space.name] = grant
        do { try file.write(places.grants) } catch { ask.tell(error.sentence) }
        return grant
    }

    /// What the rights window shows: the rights never answered, the scope when it is new or wider, the scope folders
    /// that are not on this Mac, and the launch folder when one must be chosen or confirmed.
    func question(_ declaration: Declaration, _ toAsk: ToAsk, _ grant: Grant?) -> RightsQuestion {
        func here(_ path: String) -> String? {
            var folder: ObjCBool = false
            guard let path = Declaration.expand(path, home: places.home),
                  FileManager.default.fileExists(atPath: path, isDirectory: &folder), folder.boolValue else { return nil }
            return path
        }
        var missing: [String] = []
        if case .folders(let folders) = declaration.agents { missing = folders.filter { here($0) == nil && grant?.remap[$0] == nil } }
        return RightsQuestion(space: declaration.title, description: declaration.description, rights: toAsk.rights,
                              scope: toAsk.scope ? declaration.agents : nil, missing: missing,
                              folder: toAsk.folder ? FolderQuestion(declared: declaration.folder, found: declaration.folder.flatMap(here)) : nil)
    }

    /// Puts the page, or the reason it cannot be displayed, in the window.
    private func present() {
        guard let window else { return }
        window.title = title
        if blocked.isEmpty {
            if window.contentView !== web { window.contentView = web }
        } else {
            let lines = blocked.map { "\($0.message) \($0.fix)" }.joined(separator: "\n")
            let label = NSTextField(wrappingLabelWithString: "This space cannot be displayed.\n\(lines)\nIt reloads when its files change.")
            let content = NSView()
            content.addSubview(label)
            label.frame = NSRect(x: 24, y: 24, width: 852, height: 592)
            window.contentView = content
        }
    }

    /// Tells the page the state it sees changed. Called at most four times a second (App.swift); the same state twice
    /// is not sent again.
    func push() {
        guard blocked.isEmpty, let frame else { return }
        let state = Rights.visible(engine.state, granted, launched: launched)
        var bare = state
        // `at` changes at every reading; only a change of what the space sees is worth a push.
        bare.at = ""
        guard bare != pushed, let data = try? state.json() else { return }
        pushed = bare
        SpaceWindow.push(data, in: web, frame: frame)
    }

    /// `granted` as the JSON the page receives.
    static func json(_ granted: Granted) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Granted holds only strings, lists and maps of them: encoding it cannot fail.
        return String(decoding: try! encoder.encode(granted), as: UTF8.self)
    }

    // MARK: Navigation: something:// only

    /// Whether `frame` is the space's: a frame of the app's page that holds a file of the space. A frame inside the
    /// space never holds one (the navigation policy), so this is the space's frame and no other.
    static func isSpace(_ frame: WKFrameInfo?) -> Bool {
        guard let frame, !frame.isMainFrame, let url = frame.request.url else { return false }
        return url.scheme == Scheme.name && url.host == Scheme.host
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        switch SpaceWindow.route(action, frame: frame) {
        case .shell:
            frame = nil
            pushed = nil
            decisionHandler(.allow)
        case .space(let target):
            frame = target
            decisionHandler(.allow)
        case .allow: decisionHandler(.allow)
        case .cancel: decisionHandler(.cancel)
        }
    }

    /// Where a navigation may go. `shell`: a new app's page; `space`: the frame that now holds the space.
    enum Route { case shell, space(WKFrameInfo), allow, cancel }

    /// The navigation policy of every web view that holds a space: something:// only. `frame` is the space's frame
    /// once the app's page has asked to load it.
    static func route(_ action: WKNavigationAction, frame: WKFrameInfo?) -> Route {
        guard let url = action.request.url, let target = action.targetFrame else { return .cancel }
        if target.isMainFrame {
            // A new app's page, whatever loads it (load(), WebKit's Reload, a restart after the web content process
            // ended): its frame is a new one, and it must be taken for the space again.
            return url.scheme == Scheme.name && url.host == Scheme.app ? .shell : .cancel
        }
        if url.scheme == Scheme.name && url.host == Scheme.host {
            // The app's page loads the space, the first frame to load; then the space may go to another of its pages.
            // A frame inside the space may not hold a file of the space, so the bridge can tell the space's frame
            // from the frames it holds.
            if frame == nil, action.sourceFrame.isMainFrame { return .space(target) }
            return SpaceWindow.isSpace(target) ? .allow : .cancel
        }
        // about:blank and about:srcdoc frames are the space's own and inherit its policy. A clicked link was handed
        // over by Lockdown's guard before WebKit followed it; the app's page lets the space's frame go nowhere else
        // (Scheme.shellPolicy), and a redirect, a form or a refresh is only cancelled.
        return url.scheme == "about" ? .allow : .cancel
    }

    /// A link the person clicked, from Lockdown's guard: it goes to the link window, unless one is open or links are
    /// blocked until the next reload. A link of a frame inside the space goes nowhere.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard SpaceWindow.isSpace(message.frameInfo), blocked.isEmpty, let text = message.body as? String, let url = URL(string: text) else { return }
        DispatchQueue.main.async { _ = try? self.open(url) }
    }

    /// window.open and target="_blank": no new window, ever.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

    func windowWillClose(_ notification: Notification) { close() }

    /// Stops watching and lets the window go; its data store goes with it.
    func close() {
        timer?.invalidate()
        SpaceWindow.release(web)
        closed(self)
    }
}
