// The acceptance stage: the one invented world every screen scenario starts from, and the drawing that turns a
// window into a picture. The home holds the six templates as the mockup names them and Oracle (an invented page of
// Tests/Fixtures). Each scenario builds its own Stage, rather than one per area suite, so no scenario sees what another
// left; each suite is serialized, and the suites, which run side by side, take turns to draw. Nothing is shown: the
// app is .prohibited, and each window is drawn offscreen (drawing a view needs no permission of macOS, a screenshot
// would need Screen Recording). Pictures are written only when SOMETHING_GALLERY names a folder.
import AppKit
import SwiftUI
@testable import SomethingAgents
import SomethingCore
import Testing
import Vision
import WebKit
@testable import something

let gallery = ProcessInfo.processInfo.environment["SOMETHING_GALLERY"].map { URL(fileURLWithPath: $0) }

@MainActor
final class Stage {
    /// The spaces made from share/templates: file name and title as the mockup shows them.
    static let templates = [("brief", "Daily brief"), ("agents", "My agents"), ("project", "Project watch"),
                            ("logbook", "Logbook"), ("pet", "Pebble"), ("stack", "Stack")]
    /// The sidebar's groups in the mockup, by space name (groups are a view: the spaces stay flat on disk), in round
    /// 2's names, as every frozen step shows them: Work, Notes, Breaks.
    static let groups = [("Work", ["brief", "agents", "project"]), ("Notes", ["logbook", "oracle"]), ("Breaks", ["pet", "stack"])]

    /// Lists `library`'s spaces in round 2's groups.
    static func work(_ library: Library) {
        library.preferences.groups = groups.map { Preferences.Group(name: $0.0, spaces: $0.1) }
        library.relist()
    }
    /// The mockup's moment: Thursday 22 October 2026, 18:20, in UTC (`zone`), fixed so it cannot fall back to the real
    /// time. Nothing reads it yet: the app has no clock seam, and the slice that adds one (the first to show a date)
    /// passes `now` and `zone` to it, so no picture depends on the calendar or on this Mac's time zone.
    static let now = Date(timeIntervalSince1970: 1_792_693_200)
    static let zone = TimeZone(secondsFromGMT: 0)
    /// The mockup's moment in this Mac's own zone: 18:20 local, as the pages' fixed clock (the state's `at` says it).
    static let local = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 18, minute: 20)) ?? now
    /// Date, in a page, at Thursday 22 October 2026, 18:20 local time: `new Date()` and `Date.now()` give it, a date
    /// built from its parts is as ever.
    static let fixedClock = """
        (() => { const Real = Date, fixed = new Real(2026, 9, 22, 18, 20).getTime();
          class Fixed extends Real { constructor(...parts) { if (parts.length) super(...parts); else super(fixed); } static now() { return fixed; } }
          globalThis.Date = Fixed; })();
        """
    static let oracle = Home.share.deletingLastPathComponent().appendingPathComponent("Tests/Fixtures/spaces/oracle.html")

    /// The window sizes the mockup is shot at, in points; a slice adds the other sizes when it draws at them.
    enum Size {
        static let main = NSSize(width: 1200, height: 760)
    }

    let home: Home
    /// Whether the window lists the spaces in the mockup's groups: the screens of a space at work (show, assistant,
    /// build, trust, stopped) are drawn with the sidebar the mockup shows them with.
    let grouped: Bool
    /// Whether the other rows show the mockup's moment while the open space's row follows its live assistant.
    let lively: Bool
    /// Whether the pages see the mockup's agents (`world`).
    let seeded: Bool

    /// A home named `something-accept-<prefix or area>-…` in $TMPDIR, with every space written; `remove()` deletes it.
    /// A scenario borrowing another area's world keeps its own suite's prefix for the cleanup check.
    init(_ area: String, prefix: String? = nil) throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Look.register(fonts: Home.share.appendingPathComponent("fonts"))   // as the app does at start
        home = Home(prefix: "something-accept-\(prefix ?? area)-")
        grouped = ["show", "assistant", "build", "trust", "stopped"].contains(area)
        lively = area == "assistant"
        seeded = area != "show"
        try Library.prepare(home.places)
        for (name, _) in Stage.templates {
            try home.space(name, try String(contentsOf: Stage.oracle.deletingLastPathComponent().appendingPathComponent("\(name).html"), encoding: .utf8))
        }
        try home.space("oracle", try String(contentsOf: Stage.oracle, encoding: .utf8))
        try Memory(folder: home.places.data, space: "logbook").set("notes", Stage.notes)
    }

    func remove() { home.remove() }

    /// Where each agent of `world` runs, by id, as the panel's tag says it: "something" for one it launched, a terminal
    /// or an editor for one started there, nil for one that is closed.
    static let runs: [String: String?] = [
        "claude-shop": "iTerm", "claude-pacman": "something", "claude-portfolio": "VS Code", "pi-notes": "something", "antigravity-site": "Antigravity",
        "claude-login": "something", "amp-tests": "something", "codex-eval": "something", "claude-slides": "something", "claude-post": nil, "omp-old": nil,
    ]
    /// The agents each space lists (the mockup's YA_THESE), by space name; a space not named here sees them all.
    static let these = ["agents": ["claude-shop", "claude-pacman", "claude-portfolio", "pi-notes", "antigravity-site"],
                        "brief": ["claude-shop", "claude-pacman", "claude-portfolio"], "project": ["codex-eval", "claude-slides"],
                        "logbook": ["claude-pacman", "pi-notes"], "pet": ["claude-pacman"], "week-end": ["claude-shop", "claude-login", "amp-tests"],
                        "oracle": [], "stack": []]

    /// The final mockup's eleven agents (YA.seed in v7a/v7a.js), their words invented: `name` and the thread's title are
    /// the row's title. Fix the cart total waits 34 minutes in iTerm; Draft the post is asleep, it can resume; Image
    /// sizes has ended; Antigravity is seen only by its process, its state unknown. Times are the mockup's, in this Mac's zone.
    static var world: (agents: [Agent], threads: [AgentThread]) {
        func at(_ minutes: Double) -> String { iso8601.string(from: local.addingTimeInterval(-60 * minutes)) }
        func agent(_ key: String, _ kind: String, _ title: String, _ folder: String, _ state: String, started: Double, updated: Double) -> Agent {
            var agent = Agent(id: "\(kind)-\(key)", kind: kind, origin: "elsewhere")
            (agent.folder, agent.state, agent.alive, agent.evidence) = ("/Users/example/\(folder)", state, true, "log")
            (agent.name, agent.thread, agent.started, agent.updated) = (title, key, at(started), at(updated))
            agent.waiting = state == "waiting" ? "permission" : state == "unknown" ? nil : "none"
            agent.because = ["send": "This agent was started outside something; something only reads it."]
            if runs[agent.id] == "something" { (agent.origin, agent.can.send, agent.because) = ("launched", true, [:]) }
            return agent
        }
        func thread(_ key: String, _ kind: String, _ title: String, _ turns: [(state: String, start: Double, end: Double?, items: [(String, String, String?, Double)])]) -> AgentThread {
            AgentThread(id: key, agent: "\(kind)-\(key)", title: title, started: turns.first.map { at($0.start) }, turns: turns.enumerated().map { index, turn in
                Turn(id: "\(key)-\(index)", state: turn.state, started: at(turn.start), ended: turn.end.map(at), items: turn.items.enumerated().map { n, item in
                    Item(id: "\(key)-\(index)-\(n)", kind: item.2 == nil ? "message" : "tool", author: item.0, text: item.1, at: at(item.3),
                         tool: item.2.map { Tool(name: $0, status: turn.state == "working" && n == turn.items.count - 1 ? "running" : "done") })
                })
            })
        }
        /// One finished or running turn: what the person asked, what the agent answered.
        func exchange(_ key: String, _ kind: String, _ title: String, _ state: String, _ start: Double, _ asked: String, _ said: String) -> AgentThread {
            thread(key, kind, title, [(state, start, state == "working" ? nil : start - 1, [("person", asked, nil, start), ("agent", said, nil, start - 1)])])
        }
        var pacman = agent("pacman", "claude", "Chase mode", "code/pacman", "working", started: 12, updated: 1)
        pacman.subagents = ["Explore: read the ghost files", "Writer: chase for Blinky", "Writer: chase for Pinky"].map { Tool(name: $0, status: "running") }
        var antigravity = Agent(id: "antigravity-site", kind: "antigravity", origin: "elsewhere")
        (antigravity.name, antigravity.folder, antigravity.pid, antigravity.alive, antigravity.evidence) = ("Antigravity", "/Users/example/code/site", 4210, true, "process")
        var post = agent("post", "claude", "Draft the post", "code/blog", "idle", started: 3000, updated: 2900)
        (post.alive, post.can.resume) = (false, true)
        var old = agent("old", "omp", "Image sizes", "code/blog", "done", started: 4500, updated: 4400)
        old.alive = false
        let agents = [agent("shop", "claude", "Fix the cart total", "code/shop", "waiting", started: 52, updated: 34), pacman,
                      agent("portfolio", "claude", "Portfolio images", "code/portfolio", "working", started: 25, updated: 2),
                      agent("notes", "pi", "Reading list", "notes", "idle", started: 200, updated: 190), antigravity,
                      agent("login", "claude", "Login form", "code/shop", "working", started: 9, updated: 1), agent("tests", "amp", "Shop tests", "code/shop", "idle", started: 170, updated: 160),
                      agent("eval", "codex", "Evaluation page", "code/atelier", "idle", started: 150, updated: 130), agent("slides", "claude", "Slides", "code/atelier", "working", started: 20, updated: 3),
                      post, old]
        let threads = [
            thread("shop", "claude", "Fix the cart total", [("working", 52, nil, [("person", "The cart total is off by one cent on discounts.", nil, 52), ("agent", "Read cart.js and discounts.js", "Read", 50),
                                                                                    ("agent", "Found it: the discount rounds twice.", nil, 41), ("agent", "npm test", "Bash", 34)])]),
            thread("pacman", "claude", "Chase mode", [("working", 12, nil, [("person", "Bring the chase mode back, and keep the ghosts out of the walls.", nil, 12),
                                                                             ("agent", "The chase mode is back. The ghosts no longer walk through walls.", nil, 6),
                                                                             ("person", "Now give each ghost its own way of chasing.", nil, 4),
                                                                             ("agent", "Started the workflow “Chase mode” · step 2 of 4", "Workflow", 1)])]),
            thread("portfolio", "claude", "Portfolio images", [("working", 25, nil, [("person", "Resize the images for the projects page", nil, 25),
                                                                                       ("agent", "Resizing images for the projects page, 14 of 28", "Bash", 2)])]),
            exchange("notes", "pi", "Reading list", "done", 200, "Summarise the reading list.", "Done: three books, each in two lines, in notes/reading.md."),
            exchange("login", "claude", "Login form", "working", 9, "Add a login form, with an error under each field.", "Writing it now."),
            exchange("tests", "amp", "Shop tests", "done", 170, "Run the shop’s tests.", "24 passed. Nothing to fix."),
            exchange("eval", "codex", "Evaluation page", "done", 150, "Add the evaluation page.", "Added, with the three scores side by side."),
            exchange("slides", "claude", "Slides", "working", 20, "Draft the slides from the milestones.", "Six slides so far. I’m on the results."),
            exchange("post", "claude", "Draft the post", "done", 3000, "Draft a post about the new shop.", "Here is a first draft, 600 words. The ending needs your voice."),
            exchange("old", "omp", "Image sizes", "done", 4500, "Check the image sizes.", "All of them fit. Nothing to change."),
        ]
        return (agents, threads)
    }

    /// What Look Again finds after `world`: a twelfth agent, Cursor in ~/code/site, its state unknown; then nothing new.
    static var twelfth: Agent {
        var cursor = Agent(id: "cursor-site", kind: "cursor", origin: "elsewhere")
        (cursor.name, cursor.folder, cursor.pid, cursor.alive, cursor.evidence) = ("Cursor", "/Users/example/code/site", 4388, true, "process")
        return cursor
    }

    /// `world` as the space `name` lists it.
    static func world(of name: String) -> (agents: [Agent], threads: [AgentThread]) {
        guard let listed = these[name] else { return world }
        let all = world, shown = all.agents.filter { listed.contains($0.id) }
        return (shown, all.threads.filter { thread in shown.contains { $0.id == thread.agent } })
    }

    /// Notes the person wrote in Logbook, as the mockup's page shows them (invented), with its time stamps.
    static var notes: [[String: String]] {
        let day = { (hour: Int, minute: Int, back: Int) in
            iso8601.string(from: Calendar.current.date(byAdding: .day, value: -back, to: Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: local) ?? local) ?? local)
        }
        return [("n1", day(9, 12, 0), "Coffee, then the ghost logic. Keep it simple."), ("n2", day(13, 5, 0), "Idea: a page that shows only who waits for me."),
                ("n3", day(11, 20, 1), "Read the onboarding of a launcher. Everything by keyboard.")].map { ["id": $0.0, "at": $0.1, "text": $0.2] }
    }

    /// The mockup's moment in the sidebar (core/data.js): Daily brief working, My agents waiting for the request the
    /// chip counts, Project watch and Oracle listening, Pebble just done, Logbook and Stack asleep.
    static let moment: [String: Sign.State] = ["brief": .think, "agents": .wait, "project": .listen, "oracle": .listen,
                                               "pet": .done, "logbook": .sleep, "stack": .sleep]

    /// Gives `shell`'s rows the eyes of `moment`; a space it does not name keeps its own assistant's. The rows' eyes are
    /// a closure of the window (e14 and d4 show them following a session): a scenario whose engine runs the fake builder
    /// would forget fake sessions of the others at its next refresh, so the moment is given here, as data.
    func moment(_ shell: Shell) throws {
        let host = shell.drawer.host, own = host.rootView.eyes
        host.rootView = SidebarView(library: host.rootView.library, assistant: host.rootView.assistant, eyes: { Stage.moment[$0] ?? own($0) })
    }

    /// The lines of text the drawn sidebar shows, read off its picture by Vision: what the screen shows, not what the
    /// model computes. SwiftUI builds no accessibility tree while no assistive app asks, so the picture is read.
    func drawn(_ shell: Shell) async throws -> [String] {
        try await Picture.text(sidebar(shell))
    }

    /// The sidebar of `shell` drawn offscreen at its size, or `taller` points taller, as `drawn` reads it.
    func sidebar(_ shell: Shell, taller: CGFloat = 0) throws -> NSBitmapImageRep {
        let host = shell.drawer.host
        let offscreen = Offscreen(NSHostingView(rootView: host.rootView))
        offscreen.window.setContentSize(NSSize(width: host.bounds.width, height: host.bounds.height + taller))
        offscreen.view.layoutSubtreeIfNeeded()
        let rep = try #require(offscreen.view.bitmapImageRepForCachingDisplay(in: offscreen.view.bounds))
        offscreen.view.cacheDisplay(in: offscreen.view.bounds, to: rep)
        return rep
    }

    /// The main window of the home, never shown, at `size`, its spaces listed.
    func window(_ size: NSSize = Size.main) -> (shell: Shell, library: Library, info: Info) {
        let ask = FakeAsk()
        let library = Library(places: home.places, ask: ask, share: Home.share), info = Info(places: home.places, ask: ask)
        // The world's pids are invented: no walk reads a real process, and each agent runs where `runs` says.
        info.runs = RunsIn(find: { agent in Stage.runs[agent.id].flatMap { $0 }.map { URL(fileURLWithPath: "/Stage/\($0).app") } })
        if grouped { library.preferences.groups = Stage.groups.map { Preferences.Group(name: $0.0, spaces: $0.1) } }
        library.relist()
        let shell = Shell(library: library, info: info, assistant: AssistantModel(engine: home.engine(), places: home.places), autosave: false)
        shell.window.setContentSize(size)
        if lively {
            let host = shell.drawer.host, own = host.rootView.eyes
            host.rootView = SidebarView(library: library, assistant: host.rootView.assistant, eyes: { [unowned library] in
                library.selection == .space($0) ? own($0) : Stage.moment[$0] ?? own($0)
            })
        }
        return (shell, library, info)
    }

    /// Opens the space `name` in `shell`'s center, loaded, its animations ended; the caller closes it.
    func open(_ name: String, in shell: Shell, _ library: Library) async throws -> SpaceView {
        let view = try await home.window(try #require(library.entry(name)?.space))
        // The pages see the mockup's agents; the engine is never started, so no watch tick replaces them. The show
        // screens (f) keep the quiet page: their frames and comments are measured on its parts.
        if seeded { view.engine.update(outside: Stage.world(of: name)) }
        // The pages' clock stands at the mockup's moment, in this Mac's own zone, whatever the day of the run, in every
        // run and not only a picture's: the brief's dateline is wider on a Wednesday, and f4's pick moved with it.
        view.staged = [WKUserScript(source: Stage.fixedClock, injectionTime: .atDocumentStart, forMainFrameOnly: false)]
        view.stagedAt = iso8601.string(from: Stage.local)
        view.open()
        #expect(await wait(until: { !view.web.isLoading && view.frame != nil }), "\(name) did not load")
        library.select(.space(name))
        shell.show(view)
        shell.assistant.place = AssistantModel.place(view)
        await Picture.settle(view)
        await Stage.aside()
        return view
    }

    /// Whether a scenario is drawing its pictures now: NSApp's appearance is one for the whole process.
    private static var drawing = false

    /// Runs `body` in the light appearance, then, when pictures are drawn, in the dark one; `body` gets the picture's
    /// suffix ("" or "-dark") and asserts in both. The area suites run side by side on the main actor and meet at each
    /// await: one scenario draws at a time, or another's night would reach this one's day picture.
    func appearances(_ body: (String) async throws -> Void) async throws {
        try await Stage.alone {
            for dark in gallery == nil ? [false] : [false, true] {
                let name: NSAppearance.Name = dark ? .darkAqua : .aqua
                NSApp.appearance = NSAppearance(named: name)
                // The windows follow it later, on the run loop.
                _ = await wait(until: { NSApp.windows.allSatisfy { $0.appearance != nil || $0.effectiveAppearance.name == name } })
                try await body(dark ? "-dark" : "")
            }
        }
    }

    /// Runs `body`, which sets NSApp's appearance, while no other scenario or the gallery does, then gives the app back
    /// its own appearance. Anything that sets NSApp.appearance in a test goes through here, or a night picture drawn at
    /// the same time by another suite would reach a day one (or the reverse). So does a walk that turns on VoiceOver's
    /// mode (also the whole process's), and a timing that either would slow; so does any test that sets the interface
    /// size (Look.scale, the whole process's too) or reads an absolute size, which it gives back at Default. Inside a
    /// turn already held (a read of VoiceOver's labels while a picture is drawn, a moment of set length that takes the
    /// turn before it starts), `body` runs at once, in that turn, and leaves the appearance and the interface size to the
    /// outer turn to restore.
    static func alone<T>(_ body: () async throws -> T) async rethrows -> T {
        if holding { return try await body() }
        _ = await wait(600, until: { !drawing })
        drawing = true
        defer { (drawing, NSApplication.shared.appearance, Look.scale.size) = (false, nil, .standard) }
        return try await $holding.withValue(true) { try await body() }
    }

    /// Whether the running task holds the drawing turn.
    @TaskLocal private static var holding = false

    /// Sets the running test aside while another holds the interface at another size; how long, in seconds. The size
    /// is the whole process's and every window follows it, so a test that ran on meanwhile would measure Larger's
    /// sizes or draw Larger's type in Default's column. All tests share the main actor and meet at each await, and
    /// `wait` comes here, so none runs on; once the size is back, the windows are given the turns they take to follow.
    @discardableResult
    static func aside() async -> TimeInterval {
        guard !holding, Look.scale.size != .standard else { return 0 }
        let start = Date()
        while Look.scale.size != .standard {
            try? await Task.sleep(nanoseconds: 20_000_000)
            guard Look.scale.size == .standard else { continue }
            for _ in 0..<8 {
                await withCheckedContinuation { turn in DispatchQueue.main.async { turn.resume() } }
                NSApp.windows.forEach { $0.layoutIfNeeded() }
            }
        }
        return Date().timeIntervalSince(start)
    }
}

/// How a picture is drawn: the window's frame by cacheDisplay, the page by WebKit's snapshot (it draws in another
/// process, which a view's drawing does not reach), then the assistant that floats over the page. T2 adds the
/// request panel, drawn on a canvas that holds the window and the panel together.
/// The vibrant columns (sidebar, Info) are blended by the window server, which no drawing here reaches: the same
/// views are drawn apart on a plain background and composed in their place.
@MainActor
enum Picture {
    /// Draws the whole window of `shell`, title bar and toolbar included, into `name`.png at 2x; its lights gray when
    /// it lost the keys (`keyed` false); `page` holds the page in an appearance of its own, as a page that keeps its
    /// colours does.
    static func window(_ shell: Shell, library: Library, web: WKWebView?, _ name: String, root: URL, keyed: Bool = true, page: NSAppearance? = nil) async throws {
        let inspector = try #require(shell.inspector.viewController as? NSHostingController<InspectorView>)
        let columns: [(item: NSSplitViewItem, view: NSView)] = [(shell.inspector, NSHostingView(rootView: inspector.rootView))].filter { !$0.0.isCollapsed }
        // A column's part below the title bar: all of a full-height one but the bar, all of one that starts under it.
        func shown(_ column: NSView) -> NSRect {
            var place = column.convert(column.bounds, to: nil)
            place.size.height = min(place.maxY, shell.window.contentLayoutRect.maxY) - place.minY
            return place
        }
        let offscreens = columns.map { column in
            let offscreen = Offscreen(column.view), place = shown(column.item.viewController.view)
            offscreen.window.setContentSize(NSSize(width: max(place.width, 232), height: max(place.height, 100)))
            return offscreen
        }
        // SwiftUI and WebKit draw on the run loop.
        await wait(1.5)
        // WebKit hands a page the window's appearance on its own time, after the window: wait until the page wears the
        // picture's, or a day picture shows the page in the Mac's night (or the reverse).
        if let web, web.superview != nil, web.url != nil {
            let dark = (page ?? NSApp.appearance ?? web.effectiveAppearance).bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            if NSApp.appearance != nil { web.appearance = page ?? NSApp.appearance }
            for _ in 0..<50 {
                if (try? await web.evaluateJavaScript("matchMedia('(prefers-color-scheme: dark)').matches")) as? Bool == dark { break }
                _ = await wait(0.1)
            }
        }
        // The band read the page before it changed its colours, or is about to: it reads it as it is now.
        if web?.superview != nil, (web?.navigationDelegate as? SpaceView)?.frame != nil {
            let reads = shell.band.reads
            shell.readPage()
            _ = await wait(until: { shell.band.reads > reads })
        }
        let frame = try #require(shell.window.contentView?.superview)
        disguise(frame, root.path)
        frame.layoutSubtreeIfNeeded()
        let rep = try bitmap(frame.bounds.size)
        // The window layer is drawn once, over everything, with `over` below: drawn here too, its scrim would dim the
        // title bar's band twice (the columns and the page, drawn apart, hide the first one everywhere else).
        // Made clear rather than hidden: hiding it would take the keys from what it holds (the palette's field).
        let alpha = shell.layer.alphaValue
        shell.layer.alphaValue = 0
        // No drawing here reaches the sidebar's blur, which the window server does: it is made again below.
        shell.drawer.blur.alphaValue = 0
        defer { shell.drawer.blur.alphaValue = 1 }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        shell.layer.alphaValue = alpha
        let apart = try columns.map { column in
            disguise(column.view, root.path)
            let drawn = try bitmap(column.view.bounds.size)
            selected(column.view) { column.view.cacheDisplay(in: column.view.bounds, to: drawn) }
            let place = frame.convert(shown(column.item.viewController.view), from: nil)
            return (drawn, place)
        }
        // The page says the home as a person's would be, as disguise does for the window's own words.
        if let web, web.superview != nil, let frame = (web.navigationDelegate as? SpaceView)?.frame {
            let script = "(() => { const walk = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); "
                + "for (let node; (node = walk.nextNode());) if (node.data.includes(root)) node.data = node.data.split(root).join('/Users/example'); return 0; })()"
            _ = try? await web.callAsyncJavaScript("return \(script)", arguments: ["root": root.path], in: frame, contentWorld: .page)
        }
        // A page not loaded yet (a space arriving, its rights not asked) has nothing to take: its area is drawn empty.
        let snapshot = web?.superview == nil || web?.url == nil ? nil : try await web?.takeSnapshot(configuration: nil)
        // What covers the page in its area (Stopped), then the assistant, float over the page, which was drawn over
        // them; the window layer (the toast) covers all.
        let covers = web?.superview?.subviews.filter { $0 !== web && !$0.isHidden && !($0 is Glimpse.Cover) } ?? []
        // A version held to compare lies over the page: its own page, then its label, as faded in as it is.
        var held: [(NSImage, NSRect, CGFloat)] = []
        for cover in web?.superview?.subviews.compactMap({ $0 as? Glimpse.Cover }) ?? [] {
            for view in cover.subviews {
                let image = try await (view as? WKWebView)?.takeSnapshot(configuration: nil) ?? {
                    let drawn = try bitmap(view.bounds.size)
                    view.cacheDisplay(in: view.bounds, to: drawn)
                    let image = NSImage(size: view.bounds.size)
                    image.addRepresentation(drawn)
                    return image
                }()
                held.append((image, view.convert(view.bounds, to: frame), cover.alphaValue))
            }
        }
        // In Page Full Screen the header brought back lies over the page; else the frame drew it, under the toolbar's
        // items, and the chrome over it must not draw it again.
        let header = shell.pageFull && !shell.band.isHidden
        let floating = covers + (web == nil ? [] : [shell.glass].filter { !$0.isHidden }) + (header ? [shell.band] : []) as [NSView]
            + [shell.chrome] + [shell.layer].filter { !$0.isHidden }
        let placed = floating.map { ($0, $0.convert($0.bounds, to: frame)) }
        let over = try placed.map { view, place in
            let drawn = try bitmap(view.bounds.size)
            let band = shell.band.alphaValue
            if view === shell.chrome { shell.band.alphaValue = 0 }
            view.cacheDisplay(in: view.bounds, to: drawn)
            shell.band.alphaValue = band
            return (drawn, place)
        }
        // The toolbar draws above the window layer: what the layer holds over its band (a scrim card's scrim) dims the
        // band, not its controls, which are drawn again over it, as faded as a scrim card leaves them.
        let band = shell.window.contentLayoutRect.maxY
        let reaches = shell.layer.subviews.contains { !shell.layer.isHidden && $0.convert($0.bounds, to: frame).maxY > band }
        // The toolbar back over the page in Page Full Screen: its items whole, the group of tools in one row.
        let items = header ? (shell.window.toolbar?.items ?? []).compactMap(\.view) : reaches ? shell.toolbarItems.compactMap(\.view) : []
        let bar = try items.filter { $0.window != nil && !$0.isHiddenOrHasHiddenAncestor }.map { view in
            let drawn = try bitmap(view.bounds.size)
            view.cacheDisplay(in: view.bounds, to: drawn)
            return (drawn, view.convert(view.bounds, to: frame), view.alphaValue)
        }
        // A window never shown is never key, and draws its lights gray: the main window keeps the keys while the
        // request panel, which never takes them, stands in front, so its lights are drawn in their colors.
        let lights = keyed ? Self.lights(of: shell.window) : []
        try png(of: frame.bounds.size, name) {
            rep.draw(in: NSRect(origin: .zero, size: frame.bounds.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            for (drawn, place) in apart {
                NSColor.windowBackgroundColor.setFill()
                place.fill()
                drawn.draw(in: place, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            if let snapshot, let web {
                // The window server applies a cover's background filters (Stopped's grey and blur), which no drawing
                // here reaches: the page is filtered as they would.
                let filters = covers.compactMap { $0.layer?.backgroundFilters as? [CIFilter] }.flatMap { $0 }.compactMap { $0.copy() as? CIFilter }
                filtered(snapshot, filters).draw(in: web.convert(web.bounds, to: frame))
                // The sidebar's glass over the page, a reconstruction, not the window server's own pixels.
                if shell.drawer.state.peek, let blur = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: 26]) {
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(roundedRect: shell.drawer.convert(shell.drawer.card, to: frame), xRadius: Drawer.radius, yRadius: Drawer.radius).addClip()
                    filtered(snapshot, [blur]).draw(in: web.convert(web.bounds, to: frame))
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
            for (image, place, alpha) in held { image.draw(in: place, from: .zero, operation: .sourceOver, fraction: alpha) }
            for (drawn, place) in over {
                drawn.draw(in: place, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            for (drawn, place, alpha) in bar {
                drawn.draw(in: place, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
            }
            paint(lights)
        }
        withExtendedLifetime(offscreens) {}
    }

    /// The places of `window`'s lights in its frame view, 12 points each, with the colors a key window draws them in.
    static func lights(of window: NSWindow) -> [(NSRect, NSColor)] {
        let colors: [(NSWindow.ButtonType, UInt32)] = [(.closeButton, 0xFF5F57), (.miniaturizeButton, 0xFEBC2E), (.zoomButton, 0x28C840)]
        return colors.compactMap { type, rgb -> (NSRect, NSColor)? in
            // A button the window disables (a panel's minimize and zoom) stays grey, as macOS draws it.
            guard let button = window.standardWindowButton(type), button.isEnabled, let frame = window.contentView?.superview else { return nil }
            let place = button.convert(button.bounds, to: frame)
            let color = NSColor(srgbRed: CGFloat(rgb >> 16) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
            return (NSRect(x: place.midX - 6, y: place.midY - 6, width: 12, height: 12), color)
        }
    }

    static func paint(_ lights: [(NSRect, NSColor)]) {
        for (place, color) in lights {
            color.setFill()
            NSBezierPath(ovalIn: place).fill()
            (color.shadow(withLevel: 0.12) ?? color).setStroke()
            NSBezierPath(ovalIn: place.insetBy(dx: 0.25, dy: 0.25)).stroke()
        }
    }

    /// Draws an alert's window as it would be shown, with its own icon.
    static func alert(_ alert: NSAlert, _ name: String, root: URL) throws {
        alert.layout()
        try view(try #require(alert.window.contentView), name, root: root)
    }

    /// Draws `view`, laid out at its size (its fitting size when it has none), into `name`.png at 2x, on the window's
    /// background: an alert's content draws nothing behind its text when it is not on the screen.
    static func view(_ view: NSView, _ name: String, root: URL) throws {
        disguise(view, root.path)
        if view.frame.isEmpty { view.frame.size = view.fittingSize }
        view.layoutSubtreeIfNeeded()
        let rep = try bitmap(view.bounds.size)
        selected(view) { view.cacheDisplay(in: view.bounds, to: rep) }
        try png(of: view.bounds.size, name) {
            rep.draw(in: NSRect(origin: .zero, size: view.bounds.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    /// Ends the page's animations that end, as its first second on the screen would: a window never shown has no
    /// animation clock, and a tile that arrives from transparent would stay transparent in the picture.
    static func settle(_ view: SpaceView) async {
        guard let frame = view.frame else { return }
        _ = try? await view.web.evaluateJavaScript("document.getAnimations().forEach((one) => { try { one.finish(); } catch (error) {} }); 0",
                                                   in: frame, contentWorld: .page)
    }

    /// Runs `draw` with the selected rows of `view`'s lists in the color of a selection: a row's highlight is a view of
    /// the selection material, its layer black, and the window server colors it on the screen with a filter
    /// (vibrantColorMatrixSourceOver) that no drawing in this process applies: cacheDisplay, CALayer.render and
    /// CARenderer all give black. Meanwhile it is the gray of a selection whose list does not have the focus, as the
    /// sidebar's when the person works in the open space: a reconstruction, not the window server's own pixels.
    static func selected(_ view: NSView, _ draw: () -> Void) {
        func highlights(_ view: NSView) -> [CALayer] {
            let own = (view as? NSVisualEffectView)?.material == .selection ? view.layer?.sublayers ?? [] : []
            return own + view.subviews.flatMap(highlights)
        }
        let layers = highlights(view), before = layers.map(\.backgroundColor)
        (NSApp.appearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance {
            layers.forEach { $0.backgroundColor = NSColor.unemphasizedSelectedContentBackgroundColor.cgColor }
        }
        draw()
        zip(layers, before).forEach { $0.backgroundColor = $1 }
    }

    /// The lines of text `rep` shows, read by Vision.
    static func text(_ rep: NSBitmapImageRep) async throws -> [String] {
        try await lines(rep).map(\.words)
    }

    /// Vision's one queue: a reading can take a minute on a loaded Mac, so it leaves the main actor, where it would
    /// stop every other test and the deadlines they count; one at a time, as the memory it takes is large.
    private static let reader = DispatchQueue(label: "acceptance.vision")

    /// As `text`, each line with where it is drawn, in the picture's pixels, measured from its top left. The classic
    /// reading needs its model made ready by the system's neural services: on a loaded Mac that may take a minute, then
    /// fail with an e5rtError (13), for any process and on any device, and the process remembers the failure, so asking
    /// again changes nothing. That says nothing of the picture: the document reading, as accurate, reads it instead;
    /// when it is refused too, the scenario ends cancelled, said in the log: no verdict, neither a pass nor a false red.
    /// The fast reading never refuses, but misreads what the scenarios assert word for word. Any other error is thrown.
    static func lines(_ rep: NSBitmapImageRep) async throws -> [(words: String, box: CGRect)] {
        let read = try await reading(rep)
        // A reading is a long await: the interface may have left Default meanwhile.
        await Stage.aside()
        return read
    }

    private static func reading(_ rep: NSBitmapImageRep) async throws -> [(words: String, box: CGRect)] {
        let image = try #require(rep.cgImage)
        let (wide, high) = (CGFloat(image.width), CGFloat(image.height))
        func place(_ box: CGRect) -> CGRect {
            CGRect(x: box.minX * wide, y: (1 - box.maxY) * high, width: box.width * wide, height: box.height * high)
        }
        do {
            return try await withCheckedThrowingContinuation { done in
                reader.async {
                    done.resume(with: Result(catching: {
                        let read = VNRecognizeTextRequest()
                        read.recognitionLevel = .accurate
                        read.usesLanguageCorrection = false
                        try VNImageRequestHandler(cgImage: image).perform([read])
                        return (read.results ?? []).compactMap { line in line.topCandidates(1).first.map { ($0.string, place(line.boundingBox)) } }
                    }))
                }
            }
        } catch where "\(error)".contains("e5rtError") {
            #if compiler(>=6.2)
            guard #available(macOS 26, *) else { throw error }
            do {
                let page = try await RecognizeDocumentsRequest().perform(on: image).first
                return (page?.document.text.lines ?? []).map { ($0.transcript, place($0.boundingRegion.boundingBox.cgRect)) }
            } catch where "\(error)".contains("e5rtError") {
                #if compiler(>=6.3)
                try Test.cancel("No verdict: this Mac's neural services refuse Vision's text reading (e5rtError 13)")
                #else
                throw error
                #endif
            }
            #else
            throw error
            #endif
        }
    }

    static func bitmap(_ size: NSSize) throws -> NSBitmapImageRep {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        return rep
    }

    /// Writes `name`.png in the gallery folder, `size` points at 2x: the window's background, then what `content`
    /// draws. Nothing is drawn when SOMETHING_GALLERY names no folder.
    static func png(of size: NSSize, _ name: String, _ content: () -> Void) throws {
        guard let gallery else { return }
        try FileManager.default.createDirectory(at: gallery, withIntermediateDirectories: true)
        let rep = try bitmap(size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // NSApp.effectiveAppearance follows a change of NSApp.appearance only later, on the run loop.
        (NSApp.appearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: size).fill()
            content()
        }
        NSGraphicsContext.restoreGraphicsState()
        try #require(rep.representation(using: .png, properties: [:])).write(to: gallery.appendingPathComponent("\(name).png"))
    }

    /// `image` through `filters`, in order, at its own size.
    static func filtered(_ image: NSImage, _ filters: [CIFilter]) -> NSImage {
        guard !filters.isEmpty, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let start = CIImage(cgImage: cg)
        let out = filters.reduce(start) { image, filter in
            filter.setValue(image, forKey: kCIInputImageKey)
            return filter.outputImage ?? image
        }.cropped(to: start.extent)
        guard let made = CIContext().createCGImage(out, from: start.extent) else { return image }
        return NSImage(cgImage: made, size: image.size)
    }

    /// Shows the temporary home as /Users/example: the pictures say what a person would read. Each sign holds its pose
    /// at rest, so that a picture never catches it mid-blink.
    static func disguise(_ view: NSView, _ root: String) {
        (view as? SignView)?.systemReduces = { true }
        // Only what names the home is set again: setting a text view's string scrolls it to its end.
        if let field = view as? NSTextField, field.stringValue.contains(root) {
            field.stringValue = field.stringValue.replacingOccurrences(of: root, with: "/Users/example")
        }
        if let text = view as? NSTextView, text.string.contains(root) { text.string = text.string.replacingOccurrences(of: root, with: "/Users/example") }
        view.subviews.forEach { disguise($0, root) }
    }
}
