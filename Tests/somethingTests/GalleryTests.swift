// A gallery of every native window, drawn offscreen with invented data, one PNG at 2x each, for a person to look at
// what nobody can see in a test: no window is shown, none takes the focus, and drawing a view into a bitmap needs no
// permission of macOS (a screenshot would need Screen Recording). Each window is drawn in the light appearance, then
// in the dark one (its file ends in -dark.png). It runs only when SOMETHING_GALLERY names a folder:
//   SOMETHING_GALLERY=/path/to/folder swift test --filter GalleryTests
import AppKit
import SwiftUI
@testable import SomethingAgents
import SomethingCore
import Testing
import WebKit
@testable import something

let gallery = ProcessInfo.processInfo.environment["SOMETHING_GALLERY"].map { URL(fileURLWithPath: $0) }

@MainActor @Suite(.serialized, .enabled(if: gallery != nil, "SOMETHING_GALLERY does not name a folder, so the gallery of windows is not drawn."),
                  .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-gallery-"))
struct GalleryTests {
    init() { NSApplication.shared.setActivationPolicy(.prohibited) }

    /// A home with the space morning-review and a second one, a grant, ten journal lines of yesterday and today, and a
    /// share folder with the template and the examples; its temporary path is shown as /Users/example in the pictures.
    func invented() throws -> (fixture: Home, share: URL) {
        let fixture = Home(prefix: "something-gallery-")
        let declaration = #"{"contract": 1, "title": "Morning review", "description": "Reads what the agents said overnight and asks each one for a summary.", "agents": {"folders": ["~/code/shop"]}, "folder": "~/code/shop", "rights": ["state", "send:claude", "launch:claude", "store"]}"#
        let space = try fixture.space("morning-review", page(declaration, "<p>Morning review</p>"))
        try fixture.space("garden-notes", page(#"{"contract": 1, "title": "Garden notes", "rights": ["store"]}"#, "<p>Garden</p>"))
        var file = AppFile()
        var grant = Grant(declared: Asked(try #require(Declaration.read(space, home: fixture.root).declaration)), at: "2026-10-17T08:00:00Z")
        grant.granted = ["state", "send:claude", "store"]
        grant.refused = ["launch:claude"]
        grant.folder = fixture.root.appendingPathComponent("code/shop").path
        file.spaces["morning-review"] = grant
        try file.write(fixture.places.grants)
        let journal = Journal(folder: fixture.places.journals)
        let morning = Calendar.current.startOfDay(for: Date()).addingTimeInterval(8 * 3600)
        let lines: [(TimeInterval, String, String?, String?, String?, String)] = [
            (-86_400 - 600, "launch", "a1", "claude", fixture.root.appendingPathComponent("code/shop").path, "ok"),
            (-86_400, "send", "a1", "claude", "What changed in the cart overnight? List the files and the tests that broke.", "ok"),
            (0, "send", "a1", "claude", "Summarize the failing tests.", "ok"),
            (60, "set", "a1", "claude", "mode=plan", "ok"),
            (120, "send", "a2", "codex", "Stop after this file.", "READ_ONLY_AGENT"),
            (180, "interrupt", "a1", "claude", nil, "ok"),
            (240, "open", nil, nil, "https://example.com/notes/overnight", "REFUSED"),
            (300, "send", "a1", "claude", "Then run the tests\nand say which ones still fail.", "ok"),
            (420, "interrupt", "a1", "claude", nil, "NOT_SUPPORTED"),
            (480, "resume", "a9", "claude", "thread-invented", "STILL_RUNNING"),
        ]
        for (offset, action, agent, kind, text, result) in lines {
            let at = ISO8601DateFormatter().string(from: morning.addingTimeInterval(offset))
            try journal.append(JournalLine(at: at, action: action, agent: agent, kind: kind, when: action == "send" ? "next" : nil,
                                           text: text, result: result), space: "morning-review")
        }
        let share = fixture.root.appendingPathComponent("share")
        try FileManager.default.createDirectory(at: share, withIntermediateDirectories: true)
        for name in ["template.html", "examples"] {
            try FileManager.default.copyItem(at: Home.share.appendingPathComponent(name), to: share.appendingPathComponent(name))
        }
        return (fixture, share)
    }

    /// One agent of each kind something knows, with invented names and folders: a Claude Code something launched,
    /// the others started elsewhere.
    func agents() -> [Agent] {
        let invented = [("claude", "shop", "/Users/example/code/shop"), ("codex", "garden", "/Users/example/code/garden"),
                        ("opencode", "notes", "/Users/example/Documents/notes"), ("pi", "scripts", "/Users/example/code/scripts"),
                        ("omp", "site", "/Users/example/code/site")]
        return invented.enumerated().map { index, agent in
            var made = Agent(id: "a\(index + 1)", kind: agent.0, origin: index == 0 ? "launched" : "elsewhere")
            (made.name, made.folder, made.alive, made.state) = (agent.1, agent.2, true, index == 0 ? "working" : "unknown")
            made.can.send = index == 0
            return made
        }
    }

    @Test func drawsEveryWindow() async throws {
        defer { NSApp.appearance = nil }
        // One after the other: the appearance is the app's, so two drawings at once would mix them.
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            try await drawEveryWindow(suffix: dark ? "-dark" : "")
        }
    }

    func drawEveryWindow(suffix: String) async throws {
        let folder = try #require(gallery)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let (fixture, _) = try invented()
        defer { fixture.remove() }
        let invented = try JSONDecoder().decode(SomethingCore.State.self, from: Data(contentsOf: Home.share.appendingPathComponent("contract/state-example.json")))

        // The window with a space and Info: the agents example against the invented agents, then a space whose
        // rights were answered, one refused, with its activity.
        try fixture.space("agents", try String(contentsOf: Home.share.appendingPathComponent("examples/agents.html"), encoding: .utf8))
        try fixture.space("draft", page(nil, "<p>Scratch.</p>"))
        let (shell, library, info) = window(fixture)
        let board = try await fixture.window(try #require(library.entry("agents")?.space))
        defer { board.close() }
        board.open()
        #expect(await wait(until: { !board.web.isLoading && board.frame != nil }), "the agents example did not load")
        board.launched = ["a1"]
        SpaceView.push(try Rights.visible(elsewhere(invented), board.granted, launched: ["a1"]).json(), in: board.web, frame: try #require(board.frame))
        library.select("agents")
        shell.show(board)
        info.show(board.space)
        shell.inspector.isCollapsed = false
        try await draw(shell, library: library, web: board.web, "window-space-info" + suffix, fixture)
        let review = try await fixture.window(try #require(library.entry("morning-review")?.space))
        defer { review.close() }
        review.open()
        library.select("morning-review")
        shell.show(review)
        info.show(review.space)
        try await draw(shell, library: library, web: review.web, "window-info-rights" + suffix, fixture)

        // A space that cannot be shown, Info hidden.
        let newer = try fixture.space("newer", page(#"{"contract": 2, "title": "Garden plan"}"#, ""))
        let unshown = try await fixture.window(newer)
        defer { unshown.close() }
        unshown.open()
        library.relist()
        library.select("newer")
        shell.inspector.isCollapsed = true
        shell.show(unshown)
        try await draw(shell, library: library, web: nil, "window-cannot-be-shown" + suffix, fixture)

        // A first start: no space yet, none open.
        let bare = Home(prefix: "something-gallery-")
        defer { bare.remove() }
        try Library.prepare(bare.places)
        let empty = window(bare)
        try await draw(empty.shell, library: empty.library, web: nil, "window-empty" + suffix, bare)

        // Five folders, two of them long and one not on this Mac: the sheet must still fit a small screen.
        let folders = ["~/code/shop", "~/code/garden", "~/code/clients/example-agency/website-redesign-2026",
                       "~/code/tools/a-rather-long-folder-name-for-the-build-scripts", "~/Documents/notes"]
        let opening = RightsQuestion(space: "Morning review", description: "Reads what the agents said overnight and asks each one for a summary.",
                                   rights: ["state", "send:claude", "launch:claude", "store"], scope: .folders(folders),
                                   missing: [folders[2]], folder: FolderQuestion(declared: "~/code/shop", found: "/Users/example/code/shop"))
        try draw(Ask.rights(opening, home: "/Users/example").alert, "rights-first-opening" + suffix, fixture)
        let pi = RightsQuestion(space: "Morning review", description: nil, rights: ["launch:pi"], scope: nil, missing: [],
                                folder: FolderQuestion(declared: "~/code/garden", found: nil))
        try draw(Ask.rights(pi, home: "/Users/example").alert, "rights-launch-pi" + suffix, fixture)
        try draw(Ask.lowers("acceptEdits", kind: "claude", folder: "/Users/example/code/shop", space: "Morning review", home: "/Users/example"), "lowering-mode" + suffix, fixture)
        try draw(Ask.link(try #require(URL(string: "https://example.com/notes/overnight")), space: "Morning review"), "link" + suffix, fixture)
        try draw(Ask.withData("morning-review", keys: ["drafts", "last-read", "summaries"], bytes: 18_400), "export" + suffix, fixture)
        try draw(Ask.trash("Morning review"), "trash" + suffix, fixture)
        try draw(Ask.quit(2), "quit-while-agents-run" + suffix, fixture)

        let who = App.who(agents()[0], startedBy: "Morning review", home: "/Users/example")
        let permission = Prompt(request: Request(id: "r1", agent: "a1", kind: "permission", tool: "Bash", about: "npm test",
                                                 at: "2026-10-17T09:00:01Z"), input: "npm test -- --runInBand src/cart")
        try draw(try #require(PromptPanel(permission, who: who) { _ in }.contentView), "permission-panel" + suffix, fixture)
        let lost = PromptPanel(permission, who: who) { _ in }
        lost.tell("Claude Code did not receive your answer: it stopped listening.")
        try draw(try #require(lost.contentView), "permission-panel-lost" + suffix, fixture)
        let question = Prompt(request: Request(id: "r2", agent: "a1", kind: "question", tool: nil, about: "Which test runner?",
                                               at: "2026-10-17T09:00:02Z"),
                              questions: [Question(header: "Runner", text: "Which test runner should the cart use?",
                                                   options: ["Jest", "Vitest", "Node's own"], multiple: false),
                                          Question(header: "Scope", text: "Which folders should it cover?",
                                                   options: ["src/cart", "src/checkout"], multiple: true)])
        try draw(try #require(PromptPanel(question, who: who) { _ in }.contentView), "question-panel" + suffix, fixture)

        // The template and each example in a space's view, against the invented state `something check` gives.
        for name in ["template"] + ExamplesTests.examples {
            let source = Home.share.appendingPathComponent(name == "template" ? "template.html" : "examples/\(name).html")
            let state = name == "agents" ? elsewhere(invented) : invented
            try await drawSpace("example-\(name)", try String(contentsOf: source, encoding: .utf8), state, "space-\(name)" + suffix, fixture)
        }
    }

    /// The window of `fixture`'s home, never shown, with its spaces listed; the agents of `agents()` named in Info.
    func window(_ fixture: Home) -> (shell: Shell, library: Library, info: Info) {
        let ask = FakeAsk()
        let library = Library(places: fixture.places, ask: ask), info = Info(places: fixture.places, ask: ask)
        info.agents = { self.agents() }
        library.relist()
        let shell = Shell(library: library, info: info, autosave: false)
        return (shell, library, info)
    }

    /// Draws the whole window, title bar and toolbar included, into `name`.png at 2x, with the page of `web` composed
    /// in its place: WebKit draws in another process, which a view's own drawing does not reach. The sidebar's rows
    /// are vibrant, blended by the window server, which a view's drawing does not reach either: the same sidebar is
    /// drawn apart, on a plain background, and composed in its column.
    func draw(_ shell: Shell, library: Library, web: WKWebView?, _ name: String, _ fixture: Home) async throws {
        let column = shell.split.splitViewItems[0].viewController.view
        let sidebar = NSHostingView(rootView: SidebarView(library: library))
        let offscreen = Offscreen(sidebar)
        // Below the title bar, as the sidebar's own list starts.
        let top = shell.window.frame.height - shell.window.contentLayoutRect.maxY
        offscreen.window.setContentSize(NSSize(width: column.bounds.width, height: column.bounds.height - top))
        // SwiftUI and WebKit draw on the run loop.
        await wait(1.5)
        let frame = try #require(shell.window.contentView?.superview)
        disguise(frame, fixture.root.path)
        frame.layoutSubtreeIfNeeded()
        let rep = try bitmap(frame.bounds.size), side = try bitmap(sidebar.bounds.size)
        frame.cacheDisplay(in: frame.bounds, to: rep)
        sidebar.cacheDisplay(in: sidebar.bounds, to: side)
        let snapshot = web?.superview == nil ? nil : try await web?.takeSnapshot(configuration: nil)
        try png(of: frame.bounds.size, name) {
            rep.draw(in: NSRect(origin: .zero, size: frame.bounds.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            var place = column.convert(column.bounds, to: frame)
            place.size.height -= top
            side.draw(in: place, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            if let snapshot, let web { snapshot.draw(in: web.convert(web.bounds, to: frame)) }
        }
        withExtendedLifetime(offscreen) {}
    }

    /// The invented state, with agents started in a terminal as the readers show them: a Claude Code waiting for the
    /// person there, an OpenCode at work (so OpenCode is installed here), a pi that ended. Watch makes them from
    /// sightings, as it does from a reader's, so they carry what the product gives: ids, `can` and `because`.
    func elsewhere(_ state: SomethingCore.State) -> SomethingCore.State {
        var state = state
        if var opencode = state.kinds["opencode"] {
            opencode.installed = true
            opencode.seen = "2.0.20"
            opencode.reader = "ok"
            state.kinds["opencode"] = opencode
        }
        let now = Date(), minuteAgo = now.addingTimeInterval(-60)
        let claude = Sighting(kind: "claude", key: "c1a0de00-0000-4000-8000-0000000000e2", pid: 47100,
                              facts: StateMap.Facts(alive: true, evidence: "registry", turnOpen: true, waiting: .permission),
                              folder: "/Users/example/code/billing", title: "Rename the invoice fields", updated: minuteAgo)
        let opencode = Sighting(kind: "opencode", key: "ses_0000000000000000000000e3", pid: 47200,
                                facts: StateMap.Facts(alive: true, evidence: "claim", turnOpen: true, waiting: .nothing),
                                folder: "/Users/example/code/site", title: "Draft the release notes", updated: minuteAgo)
        let pi = Sighting(kind: "pi", key: "019a2b3c-4d5e-7f60-8a1b-2c3d4e5f00e4",
                          facts: StateMap.Facts(alive: false, evidence: "process", turnOpen: false, waiting: .nothing),
                          folder: "/Users/example/code/scripts", updated: minuteAgo)
        state.agents += Watch.elsewhere(Seen(sightings: [claude, opencode, pi]), groups: [], keys: [], now: now).agents
        return state
    }

    /// Opens `html` as the space `name` in an offscreen space's view, pushes it `state` as the Engine would (the
    /// agent a1 counted as launched by it), and draws what it painted into `picture`.png.
    func drawSpace(_ name: String, _ html: String, _ state: SomethingCore.State, _ picture: String, _ fixture: Home) async throws {
        let space = try fixture.space(name, html)
        let open = try await fixture.window(space)
        defer { open.close() }
        let offscreen = Offscreen(open.web)
        open.open()
        #expect(await wait(until: { !open.web.isLoading && open.frame != nil }), "the space window did not load \(name)")
        await wait(1)
        // The page then sees the invented agents, through the same filter of rights as the state of the Engine.
        open.launched = ["a1"]
        let visible = Rights.visible(state, open.granted, launched: open.launched)
        SpaceView.push(try visible.json(), in: open.web, frame: try #require(open.frame))
        await wait(0.5)
        let snapshot = try await open.web.takeSnapshot(configuration: nil)
        try png(of: open.web.bounds.size, picture) { snapshot.draw(in: NSRect(origin: .zero, size: open.web.bounds.size)) }
        withExtendedLifetime(offscreen) {}
    }

    /// Draws an alert's window as it would be shown.
    func draw(_ alert: NSAlert, _ name: String, _ fixture: Home) throws {
        alert.layout()
        try draw(try #require(alert.window.contentView), name, fixture)
    }

    /// Draws `view`, laid out at its size (its fitting size when it has none), into `name`.png at 2x, on the window's
    /// background: an alert's content draws nothing behind its text when it is not on the screen.
    func draw(_ view: NSView, _ name: String, _ fixture: Home) throws {
        disguise(view, fixture.root.path)
        if view.frame.isEmpty { view.frame.size = view.fittingSize }
        view.layoutSubtreeIfNeeded()
        let rep = try bitmap(view.bounds.size)
        view.cacheDisplay(in: view.bounds, to: rep)
        // Over the background: a bitmap's plain draw copies its transparent pixels over it.
        try png(of: view.bounds.size, name) {
            rep.draw(in: NSRect(origin: .zero, size: view.bounds.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    func bitmap(_ size: NSSize) throws -> NSBitmapImageRep {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        return rep
    }

    /// Writes `name`.png, `size` points at 2x: the window's background, then what `content` draws.
    func png(of size: NSSize, _ name: String, _ content: () -> Void) throws {
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
        try #require(rep.representation(using: .png, properties: [:])).write(to: try #require(gallery).appendingPathComponent("\(name).png"))
    }

    /// Shows the temporary home as /Users/example: the pictures say what a person would read.
    func disguise(_ view: NSView, _ root: String) {
        if let field = view as? NSTextField { field.stringValue = field.stringValue.replacingOccurrences(of: root, with: "/Users/example") }
        if let text = view as? NSTextView { text.string = text.string.replacingOccurrences(of: root, with: "/Users/example") }
        view.subviews.forEach { disguise($0, root) }
    }
}
