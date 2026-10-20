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
    /// share folder with the template and the templates; its temporary path is shown as /Users/example in the pictures.
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
        for name in ["template.html", "templates"] {
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

        // The window with a space and Info: the My agents template against the invented agents, then a space whose
        // rights were answered, one refused, with its activity.
        try fixture.space("agents", try String(contentsOf: Home.share.appendingPathComponent("templates/agents.html"), encoding: .utf8))
        try fixture.space("draft", page(nil, "<p>Scratch.</p>"))
        let (shell, library, info) = window(fixture)
        let board = try await fixture.window(try #require(library.entry("agents")?.space))
        defer { board.close() }
        board.open()
        #expect(await wait(until: { !board.web.isLoading && board.frame != nil }), "the agents template did not load")
        board.launched = ["a1"]
        SpaceView.push(try Rights.visible(elsewhere(invented), board.granted, launched: ["a1"]).json(), in: board.web, frame: try #require(board.frame))
        library.select("agents")
        shell.show(board)
        shell.assistant.place = AssistantModel.place(board)
        info.show(board.space)
        shell.inspector.isCollapsed = false
        try await draw(shell, library: library, web: board.web, "window-space-info" + suffix, fixture)
        let review = try await fixture.window(try #require(library.entry("morning-review")?.space))
        defer { review.close() }
        review.open()
        library.select("morning-review")
        shell.show(review)
        shell.assistant.place = AssistantModel.place(review)
        info.show(review.space)
        try await draw(shell, library: library, web: review.web, "window-info-rights" + suffix, fixture)

        // A space that cannot be shown, Info hidden, Claude Code found to fix it.
        try installFakeClaude(fixture)
        shell.assistant.engine.lookAgain()
        #expect(await wait(until: { shell.assistant.engine.state.kinds["claude"]?.installed == true }))
        shell.assistant.refresh()
        let newer = try fixture.space("newer", page(#"{"contract": 2, "title": "Garden plan"}"#, ""))
        let unshown = try await fixture.window(newer)
        defer { unshown.close() }
        unshown.open()
        library.relist()
        library.select("newer")
        shell.inspector.isCollapsed = true
        shell.show(unshown)
        shell.assistant.place = AssistantModel.place(unshown)
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

        try await drawAssistant(suffix: suffix, fixture)
        try await drawOnboarding(suffix: suffix, fixture)

        // The template in a space's view, against the invented state `something check` gives.
        try await drawSpace("example-template", try String(contentsOf: Home.share.appendingPathComponent("template.html"), encoding: .utf8),
                            invented, "space-template" + suffix, fixture)

        // The templates: the gallery three and two cards wide, then each one as `something check` draws it, big.
        let (templates, templatesLibrary, _) = window(fixture)
        templatesLibrary.select(Library.gallery)
        templates.show(nil, gallery: true)
        templates.assistant.place = .templates
        try await draw(templates, library: templatesLibrary, web: nil, "templates" + suffix, fixture)
        templates.window.setContentSize(NSSize(width: 900, height: 760))
        try await draw(templates, library: templatesLibrary, web: nil, "templates-narrow" + suffix, fixture)
        for name in TemplatesTests.names {
            let image = try await TemplatesTests.snapshot(name, size: NSSize(width: 1600, height: 1000), dark: !suffix.isEmpty)
            try png(of: NSSize(width: 1600, height: 1000), "template-\(name)" + suffix) { image.draw(in: NSRect(x: 0, y: 0, width: 1600, height: 1000)) }
        }
    }

    /// The window of `fixture`'s home, never shown, with its spaces listed; the agents of `agents()` named in Info.
    func window(_ fixture: Home) -> (shell: Shell, library: Library, info: Info) {
        let ask = FakeAsk()
        let library = Library(places: fixture.places, ask: ask, share: Home.share), info = Info(places: fixture.places, ask: ask)
        info.agents = { self.agents() }
        library.relist()
        let shell = Shell(library: library, info: info, assistant: AssistantModel(engine: fixture.engine(), places: fixture.places), autosave: false)
        return (shell, library, info)
    }

    /// Draws the whole window, title bar and toolbar included, into `name`.png at 2x, with the page of `web` composed
    /// in its place: WebKit draws in another process, which a view's own drawing does not reach. The sidebar's rows
    /// are vibrant, blended by the window server, which a view's drawing does not reach either: the same sidebar is
    /// drawn apart, on a plain background, and composed in its column.
    func draw(_ shell: Shell, library: Library, web: WKWebView?, _ name: String, _ fixture: Home) async throws {
        let column = shell.split.splitViewItems[0].viewController.view, folded = shell.split.splitViewItems[0].isCollapsed
        let sidebar = NSHostingView(rootView: SidebarView(library: library, assistant: shell.assistant))
        let offscreen = Offscreen(sidebar)
        // Below the title bar, as the sidebar's own list starts.
        let top = shell.window.frame.height - shell.window.contentLayoutRect.maxY
        offscreen.window.setContentSize(NSSize(width: max(column.bounds.width, 232), height: max(column.bounds.height - top, 100)))
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
            if !folded { side.draw(in: place, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
            if let snapshot, let web { snapshot.draw(in: web.convert(web.bounds, to: frame)) }
            // The assistant floats over the page, which was drawn over it.
            if web != nil, let floating = shell.floating, let over = try? bitmap(floating.bounds.size) {
                floating.cacheDisplay(in: floating.bounds, to: over)
                over.draw(in: floating.convert(floating.bounds, to: frame), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        }
        withExtendedLifetime(offscreen) {}
    }

    /// The assistant in each of its states, driven by AssistantTests' fake `claude` (invented text): not started,
    /// ready, the conversation with its tools, working, waiting for the person, the red row, no agent found, a space's
    /// error; and How to Get One.
    func drawAssistant(suffix: String, _ fixture: Home) async throws {
        try installFakeClaude(fixture)
        let engine = fixture.engine(), model = AssistantModel(engine: engine, places: fixture.places)
        engine.changed = { model.refresh() }
        defer { engine.stopAll(within: 3) {} }
        engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        // Over a space: on the blank page, the capsule is the page's own input.
        model.place = .space(title: "My agents", name: "agents", page: fixture.places.spaces.appendingPathComponent("agents.html").path)
        try await draw(model, "assistant-off" + suffix, fixture)
        func say(_ text: String, until: () -> Bool) async {
            model.draft = text
            model.send()
            #expect(await wait(until: until), "the fake did not answer \(text)")
        }
        await say("Make the waiting tiles span the whole width, and play a soft sound when one starts waiting. make-board") {
            model.light == .ready && model.rows.count > 5
        }
        try await draw(model, "assistant-ready" + suffix, fixture)
        model.drawer = true
        try await draw(model, "assistant-conversation" + suffix, height: 640, fixture)
        model.drawer = false
        model.newConversation()
        await say("go-slow") { model.light == .working }
        try await draw(model, "assistant-working" + suffix, fixture)
        model.newConversation()
        await say("ask-first") { model.light == .waiting }
        try await draw(model, "assistant-waiting" + suffix, fixture)
        model.newConversation()
        await say("sign-in-please") { model.problem != nil }
        try await draw(model, "assistant-error" + suffix, height: 420, fixture)
        model.newConversation()
        model.drawer = false
        model.place = .space(title: "My agents", name: "agents", page: fixture.places.spaces.appendingPathComponent("agents.html").path)
        model.fault = AssistantModel.Fault(title: "My agents", name: "agents", codes: ["SCRIPT_ERROR"])
        try await draw(model, "assistant-space-error" + suffix, fixture)
        let none = AssistantModel(engine: Home(prefix: "something-gallery-").engine(), places: fixture.places)
        none.place = model.place
        none.engine.changed = { none.refresh() }
        none.engine.lookAgain()
        #expect(await wait(until: { none.noAgent }))
        try await draw(none, "assistant-no-agent" + suffix, fixture)
        try draw(Ask.howToGetOne { _ in }, "how-to-get-one" + suffix, fixture)
    }

    /// The tour's screens (welcome with the launcher's box; four builders, one, none), the blank page (idle, building
    /// with the conversation open, without an agent), a space the assistant made said ready, the rights sheet of a
    /// space it made, and Help › What something Does and Doesn't.
    func drawOnboarding(suffix: String, _ fixture: Home) async throws {
        NSApp.applicationIconImage = NSImage(contentsOf: Home.share.deletingLastPathComponent().appendingPathComponent("packaging/something.icns"))
        /// The window of a home whose PATH has `programs`, the builders looked for.
        func onboarding(_ programs: [String]) async throws -> (shell: Shell, library: Library, home: Home) {
            let home = Home(prefix: "something-gallery-")
            try Library.prepare(home.places)
            let bin = home.root.appendingPathComponent("bin")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            for name in programs { try AssistantTests().install(name, in: bin) }
            let (shell, library, _) = window(home)
            shell.assistant.engine.changed = { shell.assistant.refresh() }
            shell.assistant.engine.lookAgain()
            #expect(await wait(until: { shell.assistant.installed.count == 4 }))
            return (shell, library, home)
        }
        let four = try await onboarding(["claude", "codex", "opencode", "pi"])
        defer { four.home.remove() }
        let welcome = Tour(places: four.home.places, app: four.home.root.appendingPathComponent("brew/Cellar/something/0.2.0/something.app"))
        four.shell.show(welcome)
        try await draw(four.shell, library: four.library, web: nil, "tour-welcome" + suffix, four.home)
        welcome.step = 1
        try await draw(four.shell, library: four.library, web: nil, "tour-builders-four" + suffix, four.home)
        let one = try await onboarding(["claude"]), none = try await onboarding([])
        defer { one.home.remove(); none.home.remove() }
        for (window, name) in [(one, "tour-builders-one"), (none, "tour-none")] {
            let tour = Tour(places: window.home.places)
            tour.step = 1
            window.shell.show(tour)
            try await draw(window.shell, library: window.library, web: nil, name + suffix, window.home)
        }
        none.shell.split.splitViewItems[0].isCollapsed = false
        none.shell.show(nil, endingTour: true)
        try await draw(none.shell, library: none.library, web: nil, "blank-no-agent" + suffix, none.home)

        // The blank page of a home with spaces: idle, then building the third suggestion.
        let (shell, library, _) = window(fixture)
        let model = shell.assistant
        model.engine.changed = { model.refresh() }
        defer { model.engine.stopAll(within: 3) {} }
        model.engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        try await draw(shell, library: library, web: nil, "blank" + suffix, fixture)
        model.draft = BlankView.chips[2].1
        model.send()
        #expect(await wait(until: { model.rows.count >= 4 && model.light == .working }), "the fake did not start building")
        try await draw(shell, library: library, web: nil, "blank-building" + suffix, fixture)

        // The space it made appeared while the person was on another one.
        try fixture.space("stack", page(#"{"contract": 1, "title": "Stack", "rights": ["store"]}"#, ""))
        library.relist()
        _ = model.appeared(library.entries, open: "garden-notes")
        model.newConversation()
        (model.ready, model.drawer) = (library.entry("stack"), false)
        model.place = .space(title: "Garden notes", name: "garden-notes", page: fixture.places.spaces.appendingPathComponent("garden-notes.html").path)
        try await draw(model, "assistant-space-ready" + suffix, fixture)
        let side = NSHostingView(rootView: SidebarView(library: library, assistant: model))
        let offscreen = Offscreen(side)
        offscreen.window.setContentSize(NSSize(width: 232, height: 320))
        side.frame.size = NSSize(width: 232, height: 320)
        await wait(1)
        try draw(side, "sidebar-ready" + suffix, fixture)
        let made = RightsQuestion(space: "Stack", description: "A one-key game for your breaks.", rights: ["store"], scope: nil, missing: [],
                                  folder: nil, made: true)
        try draw(Ask.rights(made, home: "/Users/example").alert, "rights-made-by-agent" + suffix, fixture)
        try draw(Ask.doesAndDoesnt(), "does-and-doesnt" + suffix, fixture)
    }

    /// Puts AssistantTests' fake `claude` in the PATH of `fixture`'s engines.
    func installFakeClaude(_ fixture: Home) throws {
        let bin = fixture.root.appendingPathComponent("bin"), claude = bin.appendingPathComponent("claude")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try AssistantTests.fake.write(to: claude, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
    }

    /// The assistant alone at the bottom of a 760-point-wide center `height` points high, as the window floats it.
    func draw(_ model: AssistantModel, _ name: String, height: CGFloat = 150, _ fixture: Home) async throws {
        let center = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: height))
        let offscreen = Offscreen(center)
        offscreen.window.setContentSize(NSSize(width: 760, height: height))
        Shell.float(Floater(rootView: AssistantView(model: model)), in: center)
        await wait(1)
        try draw(center, name, fixture)
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
