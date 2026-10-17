// The window of one open space (design 5): one WKWebView with a new non-persistent data store at each opening,
// something.js and the space's `granted` injected before its scripts, the something:// scheme as its only source,
// every navigation away from it cancelled (a clicked http, https or mailto link goes to the link window), no new
// window, and a reload when a file of the space changes. The rights are asked at the opening and at each reload,
// before the page runs. What the space's calls do is in SpaceBridge.swift.
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
    private var stamp: Date?, timer: Timer?, pushed: State?

    /// A window for `space`, not yet shown. `share` is the folder of something.js; `rules` is Lockdown's rule list.
    /// Throws a `SpaceError` when something.js cannot be read: without it the space could not reach anything.
    init(space: Space, places: Places, engine: Engine, ask: Asking, share: URL, rules: WKContentRuleList) throws {
        let file = share.appendingPathComponent("something.js")
        guard let bridge = try? String(contentsOf: file, encoding: .utf8) else {
            throw SpaceError("something cannot read \(file.path); reinstall something, or restore share/ in its clone.")
        }
        (self.space, self.places, self.engine, self.ask, self.bridge, title) = (space, places, engine, ask, bridge, space.name)
        let named = Spaces(root: places.spaces).named(space.name)?.location.resolvingSymlinksInPath().path
        kept = named == space.location.resolvingSymlinksInPath().path
        scheme = Scheme(space: space)
        let config = WKWebViewConfiguration()
        // A new store at each opening: localStorage and cookies end with the window, and no space reads another's.
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(scheme, forURLScheme: Scheme.name)
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        // Safe Browsing looks addresses up on the Internet.
        config.preferences.isFraudulentWebsiteWarningEnabled = false
        config.userContentController.add(rules)
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 640), configuration: config)
        super.init()
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "something")
        config.userContentController.add(self, contentWorld: Lockdown.world, name: "link")
        web.navigationDelegate = self
        web.uiDelegate = self
    }

    /// The key of this space's grant in app.json: its name in the spaces folder, its path elsewhere, so a space opened
    /// by path never takes the rights of a space of the same name (a name holds no "/").
    var grantKey: String { kept ? space.name : space.page.resolvingSymlinksInPath().path }

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
        (stamp, pushed, linksBlocked) = (space.stamp(), nil, false)
        let reading = Declaration.read(space, home: places.home)
        blocked = reading.declaration == nil ? reading.problems.filter { Codes.all[$0.code]?.blocks == true } : []
        if let declaration = reading.declaration {
            title = declaration.title
            granted = Rights.granted(reading, answer(declaration), limits: [:], home: places.home)
            let controller = web.configuration.userContentController
            controller.removeAllUserScripts()
            let start = bridge + "\nsomething._granted(\(String(decoding: encoded(granted), as: UTF8.self)));\n"
            controller.addUserScript(WKUserScript(source: start, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
            controller.addUserScript(WKUserScript(source: Lockdown.guardScript, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: Lockdown.world))
            if web.url?.scheme == Scheme.name { web.reload() } else { web.load(URLRequest(url: scheme.page)) }
        }
        present()
    }

    /// The grant in force after this opening: the person is asked only what changed since they last answered, and
    /// their answers are kept in the grants file. nil when nothing was ever answered or the file cannot be read.
    func answer(_ declaration: Declaration) -> Grant? {
        var file: AppFile
        do { file = try AppFile.read(places.grants) } catch {
            ask.tell((error as? SpaceError)?.message ?? "\(error)")
            return nil
        }
        var grant = file.spaces[grantKey]
        var toAsk = Rights.toAsk(declaration, since: grant)
        // The scope only says which agents `state` shows: without that right, or with it refused, it asks nothing.
        if !declaration.rights.contains("state") || grant?.refused.contains("state") == true { toAsk.scope = false }
        guard !toAsk.isEmpty, let answer = ask.rights(question(declaration, toAsk, grant)) else { return grant }
        grant = Rights.answered(declaration, allowed: answer.allowed, refused: answer.refused, folder: answer.folder,
                                at: ISO8601DateFormatter().string(from: Date()), after: grant)
        grant?.remap.merge(answer.remap) { $1 }
        file.spaces[grantKey] = grant
        do { try file.write(places.grants) } catch { ask.tell((error as? SpaceError)?.message ?? "\(error)") }
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
        guard blocked.isEmpty else { return }
        let state = Rights.visible(engine.state, granted, launched: launched)
        var bare = state
        // `at` changes at every reading; only a change of what the space sees is worth a push.
        bare.at = ""
        guard bare != pushed, let data = try? state.json() else { return }
        pushed = bare
        web.evaluateJavaScript("window.something && something._push(\(String(decoding: data, as: UTF8.self)))")
    }

    func encoded(_ granted: Granted) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Granted holds only strings, lists and maps of them: encoding it cannot fail.
        return try! encoder.encode(granted)
    }

    // MARK: Navigation: something:// only

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = action.request.url, main = action.targetFrame?.isMainFrame ?? true
        // about:blank and about:srcdoc frames are the page's own and inherit its policy.
        if url?.scheme == Scheme.name || (url?.scheme == "about" && !main) { return decisionHandler(.allow) }
        // A clicked link was handed over by Lockdown's guard before WebKit followed it; a redirect, a form, a refresh
        // or a link the guard could not see (inside a closed shadow root) is only cancelled.
        decisionHandler(.cancel)
    }

    /// A link the person clicked, from Lockdown's guard: it goes to the link window, unless one is open or links are
    /// blocked until the next reload.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let text = message.body as? String, let url = URL(string: text) else { return }
        DispatchQueue.main.async { _ = try? self.open(url) }
    }

    /// window.open and target="_blank": no new window, ever.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

    func windowWillClose(_ notification: Notification) { close() }

    /// Stops watching and lets the window go; its data store goes with it.
    func close() {
        timer?.invalidate()
        web.stopLoading()
        web.configuration.userContentController.removeAllScriptMessageHandlers()
        closed(self)
    }
}
