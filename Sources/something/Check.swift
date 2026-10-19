// `something check`: it loads a space as the app would (same
// scheme, policy, app's page and injection) in a window nobody sees, against an invented state, with the declared
// rights granted except those --refuse names, and reports what the page did wrong. Its output is read by an agent's
// model, which may run off this Mac: it never reads a real agent's state or the person's memory.
import AppKit
import SomethingAgents
import SomethingCore
import WebKit

extension Check {
    /// Runs the check in this process with `runner`, prints its report (--json or the human lines) and returns its
    /// exit status. The process is an app only while it renders, one macOS never puts in the Dock nor in front: an
    /// accessory app would take the focus when it starts.
    @MainActor func main(_ runner: CheckRunner, say: (String, Bool) -> Void) -> Int32 {
        var outcome: Result<Report, SpaceError>?
        if runner.windowServer { NSApplication.shared.setActivationPolicy(.prohibited) }
        Task { @MainActor in
            do { outcome = .success(try await runner.run(self)) } catch { outcome = .failure(error as? SpaceError ?? SpaceError(error.sentence)) }
            guard runner.windowServer else { return }
            NSApp.stop(nil)
            // run() returns once it has handled an event after stop().
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                               context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: false)
        }
        // requestAnimationFrame fires only while AppKit runs the app; without a window server there is no app to run.
        if runner.windowServer {
            NSApp.run()
        } else {
            while outcome == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        }
        guard let outcome else { say("The check stopped before it had a report.", true); return 2 }
        return printed(outcome, home: runner.places.home.path, say: say)
    }

    /// Prints the report of `outcome` (--json or the human lines, with `home` written ~) and returns the exit status:
    /// 2 when the check could not run, and then its sentence is printed as an error.
    func printed(_ outcome: Result<Report, SpaceError>, home: String, say: (String, Bool) -> Void) -> Int32 {
        let report: Report
        switch outcome {
        case .success(let done): report = done
        case .failure(let wrong): say(wrong.message, true); return 2
        }
        var text = report.text(home: home)
        if json {
            guard let data = try? report.json() else { say("The report could not be written as JSON.", true); return 2 }
            text = String(decoding: data, as: UTF8.self)
        }
        say(text.hasSuffix("\n") ? String(text.dropLast()) : text, false)
        return report.exitStatus
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

    init(places: Places, share: URL) {
        self.places = places
        self.share = share
    }

    /// The report of one check: what went wrong with the space is a problem of the report. Throws a `SpaceError`
    /// when a --refuse word names no right the space declares, as wrong words of the command.
    func run(_ check: Check) async throws -> Report {
        let start = Date()
        CheckRunner.prune(output, before: start.addingTimeInterval(-86_400))
        var report = try await checked(check)
        // Fatal problems first, then errors, warnings and information, each in the order it was found.
        let order: [Level] = [.fatal, .error, .warning, .info]
        report.problems = order.flatMap { level in report.problems.filter { $0.level == level } }
        report.ms = Int(Date().timeIntervalSince(start) * 1000)
        return report
    }

    /// Removes what `folder` holds from before `date`: nothing else removes the snapshot each check leaves there.
    static func prune(_ folder: URL, before date: Date) {
        let key = URLResourceKey.contentModificationDateKey
        for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [key])) ?? []
        where ((try? file.resourceValues(forKeys: [key]))?.contentModificationDate ?? date) < date {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func checked(_ check: Check) async throws -> Report {
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
        if check.journal { journal(of: space, kept: kept, into: &report) }
        let reading = Declaration.read(space, home: places.home)
        report.declaration = reading.declaration
        report.problems = reading.problems
        // The app does not display such a space, so there is nothing to render.
        guard let declaration = reading.declaration else { return report }
        // The person answers each declared right as a whole, so a refusal names a declared right or a whole kind of them.
        for word in check.refuse where !declaration.rights.contains(where: { Rights.covers([word], $0) }) {
            let rights = declaration.rights.isEmpty ? "it declares none" : "it declares: \(declaration.rights.joined(separator: ", "))"
            throw SpaceError("--refuse \(word) names no right the space declares (\(rights)); refuse a right as it is declared.")
        }
        let refused = declaration.rights.filter { Rights.covers(check.refuse, $0) }
        var grant = Grant(declared: Asked(declaration), at: "")
        grant.granted = declaration.rights.filter { !refused.contains($0) }
        grant.refused = refused
        let folder = declaration.folder.flatMap { Declaration.expand($0, home: CheckRunner.invented) }
        grant.folder = folder ?? CheckRunner.invented.appendingPathComponent("code").path
        let granted = Rights.granted(reading, grant, limits: Engine.limits, home: CheckRunner.invented)
        report.rights.granted = granted.rights
        report.rights.refused = granted.refused
        report.rights.unavailable = reading.unavailable
        report.rights.unknown = reading.unknown
        let state: State
        do { state = try read(check.state) } catch {
            report.problems.append(Problem("STATE_FILE_UNREADABLE", error.sentence))
            return report
        }
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
            // Only what reached the page is said as received.
            if rendered.pushed { report.received = CheckRunner.received(Bridge.visible(host), source: check.state ?? "invented") }
            let found = rendered.rejections.map { host.problem($0, refused: refused) } + host.problems(refused: refused)
            for problem in found where !report.problems.contains(problem) { report.problems.append(problem) }
            report.calls = host.recorded
        } catch {
            // Without its bridge or its network lock, a space is not opened, in the app as here.
            report.problems.append(Problem("LOAD_FAILED", error.sentence))
        }
        return report
    }

    /// The space's last journal lines, or null with the reason; the person's journal is read, never written.
    private func journal(of space: Space, kept: Bool, into report: inout Report) {
        guard kept else { return report.journal = [] }
        do {
            let lines = try Journal(folder: places.journals).last(Self.journalLines + 1, space: space.name)
            report.journal = Array(lines.suffix(Self.journalLines))
            if lines.count > Self.journalLines { report.journalNote = "the last \(Self.journalLines) lines; older ones are left out" }
        } catch {
            report.journalNote = "not read: \(error.sentence)"
        }
    }

    static let journalLines = 100

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
    /// An unhandled rejection: its code when the reason has one, and its text.
    struct Rejection { let code: String?, message: String }
    struct Rendered {
        var problems: [Problem] = [], console: [JSONValue] = [], rejections: [Rejection] = []
        var snapshot: URL?
        /// Whether the state was handed to the page.
        var pushed = false
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
        self.space = space
        self.host = host
        scheme = Scheme(space: space)
        let bridge = try SpaceWindow.bridge(share)
        web = SpaceWindow.webView(scheme, rules: rules)
        super.init()
        let controller = web.configuration.userContentController
        controller.addUserScript(WKUserScript(source: CheckPage.probe, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        SpaceWindow.scripts(bridge, host.granted).forEach(controller.addUserScript)
        // Lockdown's guard hands clicked links over; nothing clicks during a check.
        SpaceWindow.hold(web, by: self)
        controller.add(self, contentWorld: .page, name: "check")
        scheme.missed = { [weak self] url in self?.missed(url) }
    }

    /// How long the page is still heard after its snapshot: a timer or a late answer may still throw.
    static let settling: TimeInterval = 0.5

    /// Loads, paints and photographs the page, all within `seconds`, then listens a little longer and closes it.
    func render(within seconds: TimeInterval, snapshot file: URL) async -> Rendered {
        let screen = NSScreen.main?.frame ?? .zero
        let window = NSWindow(contentRect: NSRect(x: screen.minX, y: screen.minY, width: 900, height: 640), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.contentView = web
        window.orderFrontRegardless()
        let deadline = Date().addingTimeInterval(seconds)
        let timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.end(.late) }
        }
        defer {
            timer.invalidate()
            SpaceWindow.release(web)
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
            if let frame, let data = try? Bridge.visible(host).json() {
                SpaceWindow.push(data, in: web, frame: frame)
                rendered.pushed = true
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
            let left = deadline.timeIntervalSinceNow
            if left > 0 { try? await Task.sleep(nanoseconds: UInt64(min(CheckPage.settling, left) * 1_000_000_000)) }
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
    /// app's page, it reports where the space's frame was refused to go, and what of the space's policy WebKit tells
    /// only the app's page (code from a string).
    static let probe = """
        (function () {
          const handler = window.webkit.messageHandlers.check;
          const send = (message) => { try { handler.postMessage(message); } catch (error) {} };
          // The app's page refuses to let the space's frame go anywhere but the space (its frame-src), and says so in its
          // own document.
          if (window === top) {
            return addEventListener("securitypolicyviolation", (event) =>
              send({ type: event.effectiveDirective === "frame-src" ? "navigation" : "blocked", url: event.blockedURI }));
          }
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
        if message.frameInfo.isMainFrame {
            switch words("type") {
            case "navigation": add(Problem("NAVIGATION_BLOCKED", "The page tried to go to \(words("url"))."))
            case "blocked": blocked(words("url"))
            default: break
            }
            return
        }
        guard SpaceWindow.isSpace(message.frameInfo) else { return }
        switch words("type") {
        case "start": started = started || words("url").hasPrefix("\(Scheme.name)://\(Scheme.host)/")
        case "error":
            let file = place(words("file"))
            // WebKit hides what an error says when it comes from a script that is not the page's own.
            let message = words("message") == "Script error." && file.isEmpty
                ? "An error was thrown from code something runs for the page (a listener of something.on, or a script "
                    + "that tried to change the address of the app's page); WebKit does not say its file and line."
                : words("message")
            add(Problem("SCRIPT_ERROR", message, where: file.isEmpty ? nil : Where(file: file, line: body["line"] as? Int, column: body["column"] as? Int)))
        case "resource": loadFailed(words("url"))
        case "blocked": blocked(words("url"))
        case "rejection": rendered.rejections.append(Rejection(code: body["code"] as? String, message: words("message")))
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

    private func blocked(_ url: String) {
        add(Problem("RESOURCE_BLOCKED", ["eval", "inline"].contains(url) ? "The page ran code from a string (eval or new Function), which a space cannot do."
            : "\(url) was blocked: a space loads only its own files."))
    }

    private func loadFailed(_ address: String) {
        guard !address.isEmpty else { return }
        if URL(string: address)?.scheme == Scheme.name { missed(URL(string: address)!) } else { blocked(address) }
    }

    /// An address of the space that is none of its files. The page itself is LOAD_FAILED, said once it loaded.
    private func missed(_ url: URL) {
        guard url.host == Scheme.host, url.absoluteString != scheme.page.absoluteString else { return }
        add(Problem("RESOURCE_MISSING", "\(place(url.absoluteString)) is not a file of the space.", where: Where(file: place(url.absoluteString))))
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        SpaceWindow.reply(message, open: true, host.answer, replyHandler)
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
