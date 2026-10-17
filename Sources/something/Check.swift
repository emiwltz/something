// `something check` (contract 9; design 3.6 and 5, "The check runner"): it loads a space as the app would (same
// scheme, policy, app's page and injection) in a window nobody sees, against an invented state, with the declared
// rights granted except those --refuse names, and reports what the page did wrong. Its output is read by an agent's
// model, which may run off this Mac: it never reads a real agent's state or the person's memory.
import AppKit
import SomethingCore
import WebKit

extension Check {
    /// Runs the check in this process, prints its report (--json or the human lines) and returns its exit status.
    /// The process is an app only while it renders, one macOS never puts in the Dock nor in front: an accessory app
    /// would take the focus when it starts.
    @MainActor func main(places: Places, share: URL, say: (String, Bool) -> Void) -> Int32 {
        let runner = CheckRunner(places: places, share: share)
        var report: Report?
        if runner.windowServer { NSApplication.shared.setActivationPolicy(.prohibited) }
        Task { @MainActor in
            report = await runner.run(self)
            guard runner.windowServer else { return }
            NSApp.stop(nil)
            // run() returns once it has handled an event after stop().
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                               context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: false)
        }
        // requestAnimationFrame fires only while AppKit runs the app; without a window server there is no app to run.
        if runner.windowServer { NSApp.run() } else { while report == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) } }
        let text = json ? (try? report!.json()).map { String(decoding: $0, as: UTF8.self) } ?? "{}" : report!.text(home: places.home.path)
        say(text.hasSuffix("\n") ? String(text.dropLast()) : text, false)
        return report!.exitStatus
    }
}

@MainActor
final class CheckRunner {
    let places: Places, share: URL
    /// Whether this session can render. An agent's sandbox has no window server: then only the static checks run.
    var windowServer = CGSessionCopyCurrentDictionary() != nil
    var timeout: TimeInterval = 15
    /// Where the snapshots go, one PNG per space name.
    var output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()).appendingPathComponent("something-check")
    /// Told the web view when it is made, and once the page loaded, before it paints; for the tests.
    var created: (WKWebView) -> Void = { _ in }, loaded: (WKWebView) -> Void = { _ in }
    /// The home the invented state's folders are under: `~` in a declaration stands for it, so a scope or a launch
    /// folder written with `~` meets the invented agents.
    static let invented = URL(fileURLWithPath: "/Users/example")

    init(places: Places, share: URL) { (self.places, self.share) = (places, share) }

    /// The report of one check. Never throws: what went wrong is a problem of the report.
    func run(_ check: Check) async -> Report {
        let start = Date()
        var report = await checked(check)
        // Fatal problems first, then errors, warnings and information, each in the order it was found.
        let order: [Level] = [.fatal, .error, .warning, .info]
        report.problems = order.flatMap { level in report.problems.filter { $0.level == level } }
        report.ms = Int(Date().timeIntervalSince(start) * 1000)
        return report
    }

    private func checked(_ check: Check) async -> Report {
        guard let space = Spaces(root: places.spaces).locate(check.space) else {
            let path = check.space.contains("/") ? URL(fileURLWithPath: check.space) : places.spaces.appendingPathComponent(check.space)
            var report = Report(space: check.space, path: path.path)
            report.problems = [Problem("SPACE_NOT_FOUND", check.space.contains("/") || check.space.hasSuffix(".html")
                ? "There is no space at \(check.space): give a space's .html file or a folder with an index.html."
                : "There is no space \(check.space) in \(places.spaces.path).")]
            return report
        }
        var report = Report(space: space.name, path: space.location.path)
        let kept = SpaceWindow.isKept(space, places)
        report.size = space.size()
        if check.journal { report.journal = kept ? ((try? Journal(folder: places.journals).last(100, space: space.name)) ?? []) : [] }
        let reading = Declaration.read(space, home: places.home)
        (report.declaration, report.problems) = (reading.declaration, reading.problems)
        // The app does not display such a space, so there is nothing to render.
        guard let declaration = reading.declaration else { return report }
        let refused = declaration.rights.filter { Rights.covers(check.refuse, $0) }
        var grant = Grant(declared: Asked(declaration), at: "")
        (grant.granted, grant.refused) = (declaration.rights.filter { !refused.contains($0) }, refused)
        grant.folder = declaration.folder.flatMap { Declaration.expand($0, home: CheckRunner.invented) } ?? CheckRunner.invented.appendingPathComponent("code").path
        let granted = Rights.granted(reading, grant, limits: SpaceWindow.limits, home: CheckRunner.invented)
        (report.rights.granted, report.rights.refused) = (granted.rights, granted.refused)
        (report.rights.unavailable, report.rights.unknown) = (reading.unavailable, reading.unknown)
        let state: State
        do { state = try read(check.state) } catch {
            report.problems.append(Problem("STATE_FILE_UNREADABLE", (error as? SpaceError)?.message ?? "\(error)"))
            return report
        }
        report.received = CheckRunner.received(Rights.visible(state, granted, launched: []), source: check.state ?? "invented")
        guard windowServer else {
            report.problems.append(Problem("NO_WINDOW_SERVER", "This session has no window server (an agent's sandbox has none), "
                                           + "so the page was not loaded; the declaration and the files were checked."))
            return report
        }
        let memory = output.appendingPathComponent("memory-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: memory) }
        let host = CheckHost(state: state, granted: granted, declared: declaration.rights, memory: kept ? Memory(folder: memory, space: space.name) : nil)
        do {
            let page = try CheckPage(space: space, host: host, share: share, rules: try await Lockdown.ruleList())
            page.loaded = loaded
            created(page.web)
            let rendered = await page.render(within: timeout, snapshot: output.appendingPathComponent("\(space.name).png"))
            report.problems += rendered.problems
            report.console = rendered.console
            report.snapshot = rendered.snapshot?.path
            // An unhandled rejection of a call --refuse refused is the page throwing instead of adapting to granted.
            for rejection in rendered.rejections {
                let refusedCall = rejection.code == "RIGHT_NOT_GRANTED" && host.calls.contains { call in
                    (call.answer["error"] as? [String: Any])?["code"] as? String == "RIGHT_NOT_GRANTED" && host.needs(call).map { Rights.covers(refused, $0) } == true
                }
                let problem = refusedCall ? Problem("RIGHT_REFUSED", "A call to a refused right was not caught: \(rejection.message)")
                    : Problem("PROMISE_REJECTED", rejection.message)
                if !report.problems.contains(problem) { report.problems.append(problem) }
            }
            report.problems += host.problems(refused: refused).filter { !report.problems.contains($0) }
            report.calls = host.recorded
        } catch {
            // Without its bridge or its network lock, a space is not opened, in the app as here.
            report.problems.append(Problem("LOAD_FAILED", (error as? SpaceError)?.message ?? "\(error)"))
        }
        return report
    }

    /// The state the page receives: the --state file, or the invented one of share/contract. Throws a `SpaceError`
    /// that says why it does not read.
    func read(_ file: String?) throws -> State {
        let url = file.map { URL(fileURLWithPath: $0) } ?? share.appendingPathComponent("contract/state-example.json")
        guard let data = try? Data(contentsOf: url) else {
            throw SpaceError(file == nil ? "The invented state cannot be read at \(url.path); reinstall something." : "\(url.path) cannot be read.")
        }
        do { return try JSONDecoder().decode(State.self, from: data) } catch {
            let why: String
            func path(_ keys: [CodingKey]) -> String {
                keys.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined().drop { $0 == "." }.description
            }
            switch error {
            case DecodingError.keyNotFound(let key, let context): why = "the key \(path(context.codingPath + [key])) is missing"
            case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
                why = "\(path(context.codingPath)) has the wrong type"
            default: why = "it is not valid JSON"
            }
            throw SpaceError("\(url.path) is not a state of contract 1: \(why).")
        }
    }

    /// What `state` gives the page: how many agents, in which states, how many requests, and the agent keys that
    /// are null in at least one agent, which the page must show as not known.
    static func received(_ state: State, source: String) -> Report.Received {
        var states: [String: Int] = [:]
        state.agents.forEach { states[$0.state, default: 0] += 1 }
        let agents = (try? JSONSerialization.jsonObject(with: state.json()) as? [String: Any])?["agents"] as? [[String: Any]] ?? []
        let nulls = Set(agents.flatMap { agent in agent.filter { $0.value is NSNull }.map(\.key) })
        return Report.Received(source: source, agents: state.agents.count, states: states, requests: state.requests.count, nullKeys: nulls.sorted())
    }
}

/// The space loaded once in a web view of its own, in a window that is on screen (only then does WebKit paint and
/// fire requestAnimationFrame), transparent, deaf to the mouse and unable to become key.
@MainActor
final class CheckPage: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    struct Rendered {
        var problems: [Problem] = [], console: [JSONValue] = [], rejections: [(code: String?, message: String)] = []
        var snapshot: URL?
    }

    let space: Space, host: CheckHost, scheme: Scheme
    let web: WKWebView
    var loaded: (WKWebView) -> Void = { _ in }
    private var frame: WKFrameInfo?
    private var rendered = Rendered()
    /// Whether a file of the space reached the space's frame: the probe says so from the document's start.
    private var started = false, finished = false
    private var waiting: CheckedContinuation<Step, Never>?
    /// The step that ended the render early, kept so every later step returns it at once.
    private var ended: Step?
    private enum Step { case loaded, painted, image(NSImage?), failed(String), crashed, late }

    /// Throws a `SpaceError` when something.js cannot be read.
    init(space: Space, host: CheckHost, share: URL, rules: WKContentRuleList) throws {
        (self.space, self.host, scheme) = (space, host, Scheme(space: space))
        let bridge = try SpaceWindow.bridge(share)
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 640), configuration: SpaceWindow.configuration(scheme, rules: rules))
        super.init()
        let controller = web.configuration.userContentController
        controller.addUserScript(WKUserScript(source: CheckPage.probe, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        SpaceWindow.scripts(bridge, host.granted).forEach(controller.addUserScript)
        controller.addScriptMessageHandler(self, contentWorld: .page, name: "something")
        controller.add(self, contentWorld: .page, name: "check")
        // Lockdown's guard hands clicked links over; nothing clicks during a check.
        controller.add(self, contentWorld: Lockdown.world, name: "link")
        web.navigationDelegate = self
        web.uiDelegate = self
        scheme.missed = { [weak self] url in self?.missed(url) }
    }

    /// Loads, paints and photographs the page, all within `seconds`, then closes it.
    func render(within seconds: TimeInterval, snapshot file: URL) async -> Rendered {
        let screen = NSScreen.main?.frame ?? .zero
        let window = NSWindow(contentRect: NSRect(x: screen.minX, y: screen.minY, width: 900, height: 640), styleMask: .borderless,
                              backing: .buffered, defer: false)
        (window.alphaValue, window.ignoresMouseEvents, window.hasShadow, window.isReleasedWhenClosed) = (0, true, false, false)
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.contentView = web
        window.orderFrontRegardless()
        let timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.end(.late) }
        }
        defer {
            timer.invalidate()
            web.stopLoading()
            web.configuration.userContentController.removeAllScriptMessageHandlers()
            window.orderOut(nil)
            window.contentView = nil
        }
        var step = await next { web.load(URLRequest(url: Scheme.shell)) }
        if case .loaded = step {
            loaded(web)
            if !started {
                add(Problem("LOAD_FAILED", "\(space.page.lastPathComponent) could not be served from the space: "
                            + "it cannot be read, or it is a link to a file outside the space."))
                return rendered
            }
            if let frame, let data = try? Rights.visible(host.state, host.granted, launched: host.launched).json() {
                web.evaluateJavaScript("window.something && something._push(\(String(decoding: data, as: UTF8.self)))", in: frame, in: .page)
            }
            step = await next { web.callAsyncJavaScript("await new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)))",
                                                        arguments: [:], in: frame, in: .defaultClient) { [weak self] _ in self?.settle(.painted) } }
        }
        if case .painted = step { step = await next { web.takeSnapshot(with: nil) { [weak self] image, _ in self?.settle(.image(image)) } } }
        switch step {
        case .image(let image):
            if let image, let png = CheckPage.png(image) {
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                if (try? png.write(to: file, options: .atomic)) != nil { rendered.snapshot = file }
            }
        case .failed(let why): add(Problem("LOAD_FAILED", "The page did not load: \(why)"))
        case .crashed: add(Problem("PAGE_CRASHED", "The web process that ran the page ended before the check was done."))
        case .late:
            let time = "\(Int(seconds)) second\(Int(seconds) == 1 ? "" : "s")"
            add(Problem("LOAD_TIMEOUT", finished
                ? "The page loaded but did not paint within \(time): a script may run without end."
                : "The page did not finish loading within \(time)."))
        case .loaded, .painted: break
        }
        return rendered
    }

    /// Starts one step and waits for what ends it, or returns at once the step that already ended the render.
    private func next(_ start: () -> Void) async -> Step {
        if let ended { return ended }
        return await withCheckedContinuation { continuation in
            waiting = continuation
            start()
        }
    }

    private func settle(_ step: Step) {
        waiting?.resume(returning: step)
        waiting = nil
    }

    /// Ends the render: the page failed, its process ended or time ran out.
    private func end(_ step: Step) {
        if ended == nil { ended = step }
        settle(step)
    }

    private func add(_ problem: Problem) {
        if !rendered.problems.contains(problem) { rendered.problems.append(problem) }
    }

    private static func png(_ image: NSImage) -> Data? {
        image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:])
    }

    // MARK: What the page did

    /// Before the page's scripts, in the space's frame: it reports the document's start, uncaught errors, failed
    /// loads of elements, unhandled rejections, loads the policy blocked, and the console, which keeps working. In the
    /// app's page, it reports where the space's frame was refused to go.
    static let probe = """
        (function () {
          const handler = window.webkit.messageHandlers.check;
          const send = (message) => { try { handler.postMessage(message); } catch (error) {} };
          // The app's page refuses to let the space's frame go anywhere but the space, and says so in its own document.
          if (window === top) return addEventListener("securitypolicyviolation", (event) => send({ type: "navigation", url: event.blockedURI }));
          if (parent !== top) return;
          const text = (value) => {
            if (typeof value === "string") return value;
            if (value instanceof Error) return value.name + ": " + value.message;
            try { return JSON.stringify(value) ?? String(value); } catch (error) { return String(value); }
          };
          send({ type: "start", url: location.href });
          addEventListener("error", (event) => {
            if (event instanceof ErrorEvent) send({ type: "error", message: event.message, file: event.filename, line: event.lineno, column: event.colno });
            else if (event.target && event.target !== window) send({ type: "resource", url: event.target.currentSrc || event.target.src || event.target.href || "" });
          }, true);
          addEventListener("unhandledrejection", (event) => {
            const reason = event.reason;
            send({ type: "rejection", message: text(reason), code: reason && typeof reason.code === "string" ? reason.code : null });
          });
          addEventListener("securitypolicyviolation", (event) => send({ type: "blocked", url: event.blockedURI }));
          for (const level of ["log", "info", "warn", "error", "debug"]) {
            const original = console[level];
            console[level] = function (...values) { send({ type: "console", level, text: values.map(text).join(" ") }); return original.apply(this, values); };
          }
        })();
        """

    /// The probe's messages: from the space's frame, and the navigations the app's page refused.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "check", let body = message.body as? [String: Any] else { return }
        let words = { (key: String) in String((body[key] as? String ?? "").prefix(2_000)) }
        if message.frameInfo.isMainFrame, words("type") == "navigation" {
            return add(Problem("NAVIGATION_BLOCKED", "The page tried to go to \(words("url"))."))
        }
        guard SpaceWindow.isSpace(message.frameInfo) else { return }
        switch words("type") {
        case "start": started = started || words("url").hasPrefix("\(Scheme.name)://\(Scheme.host)/")
        case "error":
            let file = place(words("file"))
            add(Problem("SCRIPT_ERROR", words("message"), where: file.isEmpty ? nil : Where(file: file, line: body["line"] as? Int, column: body["column"] as? Int)))
        case "resource": loadFailed(words("url"))
        case "blocked":
            let url = words("url")
            add(Problem("RESOURCE_BLOCKED", ["eval", "inline"].contains(url) ? "The page ran code from a string (eval or new Function), which a space cannot do."
                : "\(url) was blocked: a space loads only its own files."))
        case "rejection": rendered.rejections.append((body["code"] as? String, words("message")))
        case "console":
            guard rendered.console.count < 200 else { return }
            rendered.console.append(.object(["level": .string(words("level")), "text": .string(words("text"))]))
            if words("level") == "error" { add(Problem("CONSOLE_ERROR", words("text"))) }
        default: break
        }
    }

    /// A file of the space by its path in the space, or the address as it is when it is not one.
    private func place(_ address: String) -> String {
        guard let url = URL(string: address), url.scheme == Scheme.name, url.host == Scheme.host else { return address }
        let path = String(url.path.drop { $0 == "/" })
        return path.isEmpty ? space.page.lastPathComponent : path
    }

    private func loadFailed(_ address: String) {
        guard !address.isEmpty else { return }
        if URL(string: address)?.scheme == Scheme.name { missed(URL(string: address)!) } else {
            add(Problem("RESOURCE_BLOCKED", "\(address) was blocked: a space loads only its own files."))
        }
    }

    /// An address of the space that is none of its files. The page itself is LOAD_FAILED, said once it loaded.
    private func missed(_ url: URL) {
        guard url.host == Scheme.host, url.absoluteString != scheme.page.absoluteString else { return }
        add(Problem("RESOURCE_MISSING", "\(place(url.absoluteString)) is not a file of the space.", where: Where(file: place(url.absoluteString))))
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard SpaceWindow.isSpace(message.frameInfo), let request = message.body as? [String: Any] else {
            return replyHandler(nil, "something answers only the page of the open space.")
        }
        replyHandler(host.answer(request), nil)
    }

    // MARK: Navigation, as in the app's window

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        switch SpaceWindow.route(action, frame: frame) {
        case .shell: frame = nil; decisionHandler(.allow)
        case .space(let target): frame = target; decisionHandler(.allow)
        case .allow: decisionHandler(.allow)
        case .cancel:
            add(Problem("NAVIGATION_BLOCKED", "The page tried to go to \(action.request.url?.absoluteString ?? "an address it did not give")."))
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        add(Problem("NAVIGATION_BLOCKED", "The page tried to open a window at \(action.request.url?.absoluteString ?? "an empty address")."))
        return nil
    }

    /// Only the first load counts: a page that goes to another of its pages has already loaded once.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if !finished { settle(.loaded) }
        finished = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { end(.failed(error.localizedDescription)) }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        end(.failed(error.localizedDescription))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { end(.crashed) }
}
