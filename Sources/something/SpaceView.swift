// One open space, shown in the main window's center: one WKWebView with a new non-persistent data store at each
// opening, the app's page (something://app/) holding the space in a sandboxed frame, something.js and the space's
// `granted` injected in that frame before its scripts, the something:// scheme as its only source, every navigation
// away from it cancelled (a clicked http, https or mailto link goes to the link sheet), no new window, and a reload
// when a file of the space changes. The rights are asked at the opening and at each reload, before the page runs. An
// error the page does not catch is reported by its code alone, for the window's "This space has an error."
// What the space's calls do is in SpaceBridge.swift.
import AppKit
import SomethingAgents
import SomethingCore
import WebKit

final class SpaceView: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let space: Space, places: Places, engine: Engine, ask: Asking
    let web: WKWebView
    private(set) var title: String
    private(set) var granted = Granted()
    /// The agents the space launched or resumed. The app keeps them by the space's name for its whole life
    /// (`Launches`): a space closed and opened again still sees and drives them. A space with no answers kept is new
    /// to the person, and `answer` drops them: it never inherits another's agents.
    let launches: Launches
    var launched: Set<String> {
        get { launches.ids[space.name] ?? [] }
        set { launches.ids[space.name] = newValue }
    }
    /// The problems that keep the space from being displayed; empty while it is displayed.
    private(set) var blocked: [Problem] = []
    var linkOpen = false, linksBlocked = false
    /// Called after each load: the title or the problems may have changed, and the window shows them.
    var loaded: () -> Void = {}
    /// Called after each line the space adds to its journal: Info shows it.
    var journaled: () -> Void = {}
    /// Called when a line could not be added to the journal: the window says so.
    var unkept: () -> Void = {}
    /// The codes of the errors the page did not catch since it loaded (SCRIPT_ERROR, PROMISE_REJECTED), never their
    /// words, which the page writes; `faulted` is called at each new one.
    private(set) var faults: [String] = []
    var faulted: () -> Void = {}
    private let bridge: String, scheme: Scheme
    private var stamp: Date?
    private var timer: Timer?
    private var looking = false
    private var pushed: State?
    /// The declaration as the last load read it: the one the person was asked about. A switch in Info applies
    /// new answers to it, never to a newer file that no rights sheet has shown yet.
    private var reading: DeclarationReading?
    /// The frame that holds the space, once the app's page has asked to load it: pushes and `granted` go to it. The
    /// bridge and the link sheet answer the frame `isSpace` recognizes, which the navigation policy makes this same
    /// frame. nil before, while the space is blocked, and from each new load of the app's page until its frame asks.
    private(set) var frame: WKFrameInfo?
    /// One more at each load and at the close: a call answered late is refused when the page it came from is gone.
    private(set) var loads = 0
    /// Whether the person's assistant made this space while they waited for it: the rights sheet says so.
    var made = false

    /// The space `space` of the spaces folder, not yet loaded. `share` is the folder of something.js; `rules` is
    /// Lockdown's rule list. Throws a `SpaceError` when something.js cannot be read: without it the space could not
    /// reach anything.
    init(space: Space, places: Places, engine: Engine, ask: Asking, share: URL, rules: WKContentRuleList, launches: Launches) throws {
        bridge = try SpaceView.bridge(share)
        self.launches = launches
        self.space = space
        self.places = places
        self.engine = engine
        self.ask = ask
        title = space.name
        scheme = Scheme(space: space)
        web = SpaceView.webView(scheme, rules: rules)
        super.init()
        SpaceView.hold(web, by: self)
        web.configuration.userContentController.add(self, contentWorld: Lockdown.world, name: "fault")
    }

    /// Reports each error the space's page leaves uncaught, by its code only, from something's own world, where the
    /// page cannot reach the handler: a page can make an error happen, never choose what it says to the assistant.
    static let faultScript = """
        if (window !== top && parent === top) {
          addEventListener("error", (event) => { if (event.target === window) webkit.messageHandlers.fault.postMessage("SCRIPT_ERROR"); }, true);
          addEventListener("unhandledrejection", () => webkit.messageHandlers.fault.postMessage("PROMISE_REJECTED"));
        }
        """

    /// The text of something.js in `share`. Throws a `SpaceError` when it cannot be read: without it the space could
    /// not reach anything.
    static func bridge(_ share: URL) throws -> String {
        let file = share.appendingPathComponent("something.js")
        guard let bridge = try? String(contentsOf: file, encoding: .utf8) else {
            throw SpaceError("something cannot read \(file.path); reinstall something, or restore share/ in its clone.")
        }
        return bridge
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
    /// space is `open`; any other call is refused (never a frame inside the space, never the app's page).
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

    /// Loads the space and watches its files: when one changes (looked at each second, off the main queue), the
    /// space reloads.
    func open() {
        load()
        watching(true)
    }

    /// Looks at the space's files each second while `on`, and at once when it turns on again: off while nobody can
    /// see the window.
    func watching(_ on: Bool) {
        guard on != (timer != nil) else { return }
        timer?.invalidate()
        timer = nil
        guard on else { return }
        look()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.look() }
    }

    private func look() {
        guard !looking else { return }
        looking = true
        let space = space, loads = loads
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let now = SpaceView.stamp(of: space)
            DispatchQueue.main.async {
                guard let self else { return }
                self.looking = false
                if self.timer != nil, self.loads == loads, now != self.stamp { self.load() }
            }
        }
    }

    /// Past this many entries, a folder space's walk stops: a space that holds a whole project (node_modules) must not
    /// keep the Mac busy each second. A change among its first entries still reloads it.
    static let watched = 2_000

    /// The latest modification among the space's visible files, within the first `watched` entries of a folder; nil
    /// when none can be read. A change of any file, an image as much as the page, changes it.
    static func stamp(of space: Space) -> Date? {
        let key = URLResourceKey.contentModificationDateKey
        // Asked of the file system each time: a URL keeps the values it read once.
        guard space.form == .folder else { return (try? FileManager.default.attributesOfItem(atPath: space.location.path))?[.modificationDate] as? Date }
        let walk = FileManager.default.enumerator(at: space.location, includingPropertiesForKeys: [key, .isRegularFileKey],
                                                  options: [.skipsHiddenFiles])
        var latest: Date?, seen = 0
        while seen < watched, let file = walk?.nextObject() as? URL {
            seen += 1
            guard let values = try? file.resourceValues(forKeys: [key, .isRegularFileKey]), values.isRegularFile == true,
                  let date = values.contentModificationDate else { continue }
            latest = max(latest ?? date, date)
        }
        return latest
    }

    /// Reads the declaration, asks the rights that changed, then loads or reloads the page with the new `granted`;
    /// or, when the declaration keeps the space from being displayed, keeps why in `blocked` for the window to say.
    func load() {
        loads += 1
        stamp = SpaceView.stamp(of: space)
        pushed = nil
        frame = nil
        linksBlocked = false
        faults = []
        let reading = Declaration.read(space, home: places.home, kinds: Engine.kinds)
        self.reading = reading
        blocked = reading.declaration == nil ? reading.problems.filter { Codes.all[$0.code]?.blocks == true } : []
        title = reading.declaration?.title ?? space.name
        if let declaration = reading.declaration {
            granted = Rights.granted(reading, answer(declaration), limits: Engine.limits, home: places.home)
            inject()
            web.load(URLRequest(url: Scheme.shell))
        } else {
            // The page the person can no longer see stops: its scripts, its timers and its links. The empty page has
            // an address of the app, as the navigation policy allows nothing else.
            web.configuration.userContentController.removeAllUserScripts()
            web.loadHTMLString("", baseURL: URL(string: "\(Scheme.name)://\(Scheme.app)/.blocked"))
        }
        loaded()
    }

    /// Puts the guards and the bridge, with the `granted` in force, before the scripts of every page the space loads.
    /// Every frame gets the guards: a frame inside the space has links too. WebKit injects in the main frame or in
    /// every frame; the bridge goes to the space's frame only, the one whose parent is the app's page.
    private func inject() {
        let controller = web.configuration.userContentController
        controller.removeAllUserScripts()
        SpaceView.scripts(bridge, granted).forEach(controller.addUserScript)
        controller.addUserScript(WKUserScript(source: SpaceView.faultScript, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: Lockdown.world))
    }

    /// The guards, then something.js holding `granted`, for every page that holds a space (the check's too).
    static func scripts(_ bridge: String, _ granted: Granted) -> [WKUserScript] {
        let start = "if (window !== top && parent === top) {\n\(bridge)\nsomething._granted(\(json(granted)));\n}\n"
        return [WKUserScript(source: Lockdown.activationScript, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page),
                WKUserScript(source: Lockdown.guardScript, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: Lockdown.world),
                WKUserScript(source: start, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)]
    }

    /// Applies the person's answers as the grants file now keeps them, without asking and without a reload: the page
    /// hears a `granted` event, and the bridge answers by the new rights from its next call. Info calls it when a
    /// right is switched: a revocation reaches an open space as a `granted` event.
    /// When the grants file does not read, the rights in force stay as they are and the failure is said.
    func regrant() {
        guard blocked.isEmpty, let reading, reading.declaration != nil else { return }
        let grant: Grant?
        do { grant = try Grants(places.grants).read().spaces[space.name] } catch { return ask.tell(error.sentence) }
        granted = Rights.granted(reading, grant, limits: Engine.limits, home: places.home)
        inject()
        if let frame { web.evaluateJavaScript("window.something && something._granted(\(SpaceView.json(granted)))", in: frame, in: .page) }
        push()
    }

    /// The grant in force after this opening: the person is asked only what changed since they last answered. The
    /// answers are kept in the grants file, by the space's name. nil when nothing was ever answered or the file cannot
    /// be read.
    func answer(_ declaration: Declaration) -> Grant? {
        let grants = Grants(places.grants)
        let grant: Grant?
        do { grant = try grants.read().spaces[space.name] } catch {
            ask.tell(error.sentence)
            return nil
        }
        // Forgotten answers (a space deleted, then made again under its name): the agents kept under that name are
        // not this space's.
        if grant == nil { launched = [] }
        let toAsk = Rights.toAsk(declaration, since: grant)
        guard !toAsk.isEmpty, let answer = ask.rights(question(declaration, toAsk, grant)) else { return grant }
        // Applied to the grant as the file holds it after the sheet, so that a change made meanwhile stays.
        func answered(_ before: Grant?) -> Grant {
            var next = Rights.answered(declaration, allowed: answer.allowed, refused: answer.refused, folder: answer.folder,
                                       at: iso8601.string(from: Date()), after: before)
            next.remap.merge(answer.remap) { $1 }
            return next
        }
        do { return try grants.update { $0.spaces[space.name] = answered($0.spaces[space.name]) }.spaces[space.name] } catch {
            ask.tell(error.sentence)
            return answered(grant)
        }
    }

    /// What the rights sheet shows: the rights never answered, the scope when it is new or wider, the scope folders
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
                              folder: toAsk.folder ? FolderQuestion(declared: declaration.folder, found: declaration.folder.flatMap(here)) : nil,
                              made: made)
    }

    /// Tells the page the state it sees changed. Called at most four times a second (App.swift); the same state twice
    /// is not sent again.
    func push() {
        guard blocked.isEmpty, let frame else { return }
        let state = Bridge.visible(self)
        var bare = state
        // `at` changes at every reading; only a change of what the space sees is worth a push.
        bare.at = ""
        guard bare != pushed, let data = try? state.json() else { return }
        pushed = bare
        SpaceView.push(data, in: web, frame: frame)
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
        switch SpaceView.route(action, frame: frame) {
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
            return SpaceView.isSpace(target) ? .allow : .cancel
        }
        // about:blank and about:srcdoc frames are the space's own and inherit its policy. A clicked link was handed
        // over by Lockdown's guard before WebKit followed it; the app's page lets the space's frame go nowhere else
        // (Scheme.shellPolicy), and a redirect, a form or a refresh is only cancelled.
        return url.scheme == "about" ? .allow : .cancel
    }

    /// A link the person clicked, from Lockdown's guard: it goes to the link sheet, unless one is open or links are
    /// blocked until the next reload. A link of a frame inside the space goes nowhere. Or an error code (`faultScript`).
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard SpaceView.isSpace(message.frameInfo), blocked.isEmpty, let text = message.body as? String else { return }
        if message.name == "fault" {
            guard ["SCRIPT_ERROR", "PROMISE_REJECTED"].contains(text), !faults.contains(text) else { return }
            faults.append(text)
            return faulted()
        }
        guard let url = URL(string: text) else { return }
        DispatchQueue.main.async { _ = try? self.open(url) }
    }

    /// window.open and target="_blank": no new window, ever.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

    /// Stops watching and lets the web view go; its data store goes with it.
    func close() {
        loads += 1
        watching(false)
        SpaceView.release(web)
    }
}
