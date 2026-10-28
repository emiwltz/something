// A gallery of every native window, drawn offscreen with invented data, one PNG at 2x each, for a person to look at
// what nobody can see in a test: no window is shown, none takes the focus, and drawing a view into a bitmap needs no
// permission of macOS (a screenshot would need Screen Recording). Each window is drawn in the light appearance, then
// in the dark one (its file ends in -dark.png). A window never shown is drawn as an inactive one: default buttons
// without the accent color, switches that are on in gray (making the windows report themselves key changes nothing,
// it was tried). The drawing itself is Stage.swift's (Picture). Only pictures with no screen id of the mockup stay
// here; a screen's picture is its acceptance scenario's. It runs only when SOMETHING_GALLERY names a folder:
//   SOMETHING_GALLERY=/path/to/folder swift test --filter GalleryTests
import AppKit
import SwiftUI
@testable import SomethingAgents
import SomethingCore
import Testing
import WebKit
@testable import something


@MainActor @Suite(.serialized, .enabled(if: gallery != nil, "SOMETHING_GALLERY does not name a folder, so the gallery of windows is not drawn."),
                  .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-gallery-"))
struct GalleryTests {
    init() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Look.register(fonts: Home.share.appendingPathComponent("fonts"))
    }

    /// A home with the space morning-review and a second one, a grant, ten journal lines of yesterday and today, and a
    /// share folder with the template and the templates; its temporary path is shown as /Users/example in the pictures.
    func invented() throws -> (fixture: Home, share: URL) {
        let fixture = Home(prefix: "something-gallery-")
        let declaration = #"{"contract": 1, "title": "Morning review", "description": "Reads what the agents said overnight and asks each one for a summary.", "agents": {"folders": ["~/code/shop"]}, "folder": "~/code/shop", "rights": ["state", "send:claude", "launch:claude", "store"]}"#
        let space = try fixture.space("morning-review", page(declaration, "<p>Morning review</p>"))
        try fixture.space("garden-notes", page(#"{"contract": 1, "title": "Garden notes", "rights": ["store"]}"#, "<p>Garden</p>"))
        var file = AppFile()
        var grant = Grant(declared: Asked(try #require(Declaration.read(space, home: fixture.root, kinds: Registry.app.kinds).declaration)), at: "2026-10-17T08:00:00Z")
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
        // The sheets and the tour show the app's icon, as in the app; this test program has none of its own.
        NSApp.applicationIconImage = NSImage(contentsOf: Home.share.deletingLastPathComponent().appendingPathComponent("packaging/something.icns"))

        // One after the other: the appearance is the app's, so two drawings at once would mix them.
        // Alone with the acceptance scenarios too, which may run beside it.
        try await Stage.alone {
            for dark in [false, true] {
                NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                try await drawEveryWindow(suffix: dark ? "-dark" : "")
            }
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
        library.select(.space("agents"))
        shell.show(board)
        shell.assistant.place = AssistantModel.place(board)
        info.show(board.space)
        shell.inspector.isCollapsed = false
        await settle(board)
        try await draw(shell, library: library, web: board.web, "window-space-info" + suffix, fixture)
        let review = try await fixture.window(try #require(library.entry("morning-review")?.space))
        defer { review.close() }
        review.open()
        library.select(.space("morning-review"))
        shell.show(review)
        shell.assistant.place = AssistantModel.place(review)
        info.show(review.space)
        await settle(review)
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
        library.select(.space("newer"))
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

        // The level sheet of a space made elsewhere, pre-set to what it needs: Watch; Run with its folder found, the
        // Mac's agents' folders offered, one of them long; Run with none yet, pi on this Mac (it never asks).
        let folders = ["/Users/example/code/shop", "/Users/example/code/garden", "/Users/example/code/clients/example-agency/website-redesign-2026"]
        let opening = RightsQuestion(space: "Morning review", description: "Reads what the agents said overnight and asks each one for a summary.",
                                     level: .watch, folder: nil, folders: folders)
        try draw(try #require(Ask.rights(opening, home: "/Users/example").sheet.contentView), "rights-first-opening" + suffix, fixture)
        let run = RightsQuestion(space: "Morning review", description: nil, level: .run, folder: folders[2], folders: folders)
        try draw(try #require(Ask.rights(run, home: "/Users/example").sheet.contentView), "rights-run-folder" + suffix, fixture)
        let pi = RightsQuestion(space: "Morning review", description: nil, level: .run, folder: nil, folders: [])
        try draw(try #require(Ask.rights(pi, home: "/Users/example").sheet.contentView), "rights-run-no-folder" + suffix, fixture)
        try draw(Ask.lowers("acceptEdits", kind: "claude", folder: "/Users/example/code/shop", space: "Morning review", home: "/Users/example"), "lowering-mode" + suffix, fixture)
        let link = try #require(URL(string: "https://example.com/notes/overnight"))
        try Picture.view(try #require(Ask.link(link, space: "Morning review").contentView), "link" + suffix, root: fixture.root)

        let who = App.who(agents()[0], space: "Morning review", home: "/Users/example")
        let permission = Prompt(request: Request(id: "r1", agent: "a1", kind: "permission", tool: "Bash", about: "npm test",
                                                 at: "2026-10-17T09:00:01Z"), input: "npm test -- --runInBand src/cart")
        func panel(_ prompt: Prompt) -> RequestPanel {
            let panel = RequestPanel { _ in }
            panel.clock = { 100 }
            panel.show(prompt, who: who, age: "asked 3 min ago")
            panel.clock = { 101 }
            panel.tick()
            return panel
        }
        try draw(try #require(panel(permission).contentView), "permission-panel" + suffix, fixture)
        let lost = panel(permission)
        lost.tell("Claude Code did not receive your answer: it stopped listening.")
        try draw(try #require(lost.contentView), "permission-panel-lost" + suffix, fixture)
        let question = Prompt(request: Request(id: "r2", agent: "a1", kind: "question", tool: nil, about: "Which test runner?",
                                               at: "2026-10-17T09:00:02Z"),
                              questions: [Question(header: "Runner", text: "Which test runner should the cart use?",
                                                   options: ["Jest", "Vitest", "Node's own"], multiple: false),
                                          Question(header: "Scope", text: "Which folders should it cover?",
                                                   options: ["src/cart", "src/checkout"], multiple: true)])
        try draw(try #require(panel(question).contentView), "question-panel" + suffix, fixture)

        try await drawAssistant(suffix: suffix, fixture)
        try await drawOnboarding(suffix: suffix, fixture)

        // The template in a space's view, against the invented state `something check` gives.
        try await drawSpace("example-template", try String(contentsOf: Home.share.appendingPathComponent("template.html"), encoding: .utf8),
                            invented, "space-template" + suffix, fixture)

        // The templates: the gallery three and two cards wide, then each one as `something check` draws it, big.
        let (templates, templatesLibrary, _) = window(fixture)
        templatesLibrary.select(.templates)
        templates.show(nil, templates: true)
        templates.assistant.place = .templates
        try await draw(templates, library: templatesLibrary, web: nil, "templates" + suffix, fixture)
        templates.window.setContentSize(NSSize(width: 900, height: 760))
        try await draw(templates, library: templatesLibrary, web: nil, "templates-narrow" + suffix, fixture)
        for name in TemplatesTests.names {
            let image = try await TemplatesTests.snapshot(name, size: NSSize(width: 1600, height: 1000), dark: !suffix.isEmpty)
            try png(of: NSSize(width: 1600, height: 1000), "template-\(name)" + suffix) { image.draw(in: NSRect(x: 0, y: 0, width: 1600, height: 1000)) }
        }
    }

    /// The window of `fixture`'s home, never shown, with its spaces listed.
    func window(_ fixture: Home) -> (shell: Shell, library: Library, info: Info) {
        let ask = FakeAsk()
        let library = Library(places: fixture.places, ask: ask, share: Home.share), info = Info(places: fixture.places, ask: ask)
        library.relist()
        let shell = Shell(library: library, info: info, assistant: AssistantModel(engine: fixture.engine(), places: fixture.places), autosave: false)
        return (shell, library, info)
    }

    /// Draws the whole window into `name`.png at 2x (Stage.swift's Picture), the page of `web` composed in its place.
    func draw(_ shell: Shell, library: Library, web: WKWebView?, _ name: String, _ fixture: Home) async throws {
        try await Picture.window(shell, library: library, web: web, name, root: fixture.root)
    }

    /// The assistant in each of its states, driven by AssistantTests' fake `claude` (invented text): not started,
    /// ready, the conversation with its tools, working, retrying its model, its sign-in refused, waiting for the
    /// person, the red row, no agent found, a space's error; and How to Get One.
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
        await say("Make the waiting tiles span the whole width, and play a soft sound when one starts waiting.") {
            model.light == .ready && model.rows.count > 5
        }
        try await draw(model, "assistant-ready" + suffix, fixture)
        model.threadShown = true
        try await draw(model, "assistant-conversation" + suffix, height: 748, fixture)
        // As narrow as the center of the smallest window with the sidebar and Info open.
        try await draw(model, "assistant-conversation-narrow" + suffix, width: 340, height: 560, fixture)
        model.threadShown = false
        model.newConversation()
        await say("go-slow") { model.light == .working }
        try await draw(model, "assistant-working" + suffix, fixture)
        model.newConversation()
        await say("Make the counters bigger.") { model.presence.stuck == .cannotReachModel }
        try await draw(model, "assistant-retrying" + suffix, fixture)
        model.newConversation()
        await say("Give it a darker header.") { model.signedOut }
        try await draw(model, "assistant-signed-out" + suffix, height: 748, fixture)
        model.newConversation()
        await say("ask-first") { model.light == .waiting }
        try await draw(model, "assistant-waiting" + suffix, fixture)
        model.newConversation()
        await say("Add a clock in the corner.") { model.light == .error }
        try await draw(model, "assistant-error" + suffix, height: 748, fixture)
        model.newConversation()
        model.threadShown = false
        model.place = .space(title: "My agents", name: "agents", page: fixture.places.spaces.appendingPathComponent("agents.html").path)
        let none = AssistantModel(engine: Home(prefix: "something-gallery-").engine(), places: fixture.places)
        none.place = model.place
        none.engine.changed = { none.refresh() }
        none.engine.lookAgain()
        #expect(await wait(until: { none.noAgent }))
        try await draw(none, "assistant-no-agent" + suffix, fixture)
        // A Codex alone, which could not start the tools something lends it.
        let alone = Home(prefix: "something-gallery-"), bin = alone.root.appendingPathComponent("bin")
        defer { alone.remove() }
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: bin.appendingPathComponent("codex"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.appendingPathComponent("codex").path)
        let old = AssistantModel(engine: alone.engine(), places: fixture.places)
        old.place = model.place
        old.engine.changed = { old.refresh() }
        old.engine.lookAgain()
        #expect(await wait(until: { old.installed["codex"] == true }))
        old.cannotBuild("codex", "Codex could not start something's tools, so it can't build spaces. Fix what it said, then look for agents again: “MCP client for `something` failed to start: MCP startup failed: No such file or directory (os error 2)”.")
        try await draw(old, "assistant-cannot-build" + suffix, fixture)
        try draw(Ask.howToGetOne { _ in }, "how-to-get-one" + suffix, fixture)
    }

    /// The blank page (without an agent, idle, building with the conversation open), a space the assistant made said
    /// ready, the level sheet of a space it made, and Help › What something Does and Doesn't.
    func drawOnboarding(suffix: String, _ fixture: Home) async throws {
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
            #expect(await wait(until: { shell.assistant.installed.count == Registry.app.builders.count }))
            return (shell, library, home)
        }
        // The welcome's steps are drawn by AcceptanceBuild (a2–a8), over the window they step back.
        let none = try await onboarding([])
        defer { none.home.remove() }
        none.shell.show(nil)
        try await draw(none.shell, library: none.library, web: nil, "blank-no-agent" + suffix, none.home)

        // The blank page of a home with spaces: idle, then building the third suggestion.
        let (shell, library, _) = window(fixture)
        let model = shell.assistant
        model.engine.changed = { model.refresh() }
        defer { model.engine.stopAll(within: 3) {} }
        model.engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        try await draw(shell, library: library, web: nil, "blank" + suffix, fixture)
        // The smallest window: the templates wrap, nothing is cut.
        shell.window.setContentSize(NSSize(width: 640, height: 480))
        try await draw(shell, library: library, web: nil, "blank-smallest" + suffix, fixture)
        shell.window.setContentSize(NSSize(width: 1200, height: 760))
        model.draft = BlankView.chips[2].1
        model.send()
        #expect(await wait(until: { model.rows.count >= 4 && model.light == .working }), "the fake did not start building")
        try await draw(shell, library: library, web: nil, "blank-building" + suffix, fixture)
        // The smallest window: the page scrolls clear of the conversation; with Info open, the conversation wraps
        // narrower and still shows whole.
        shell.window.setContentSize(NSSize(width: 640, height: 480))
        try await draw(shell, library: library, web: nil, "blank-building-smallest" + suffix, fixture)
        shell.inspector.isCollapsed = false
        try await draw(shell, library: library, web: nil, "blank-building-smallest-info" + suffix, fixture)
        shell.inspector.isCollapsed = true
        shell.window.setContentSize(NSSize(width: 1200, height: 760))

        // The space it made appeared while the person was on another one.
        try fixture.space("stack", page(#"{"contract": 1, "title": "Stack", "rights": ["store"]}"#, ""))
        library.relist()
        _ = model.appeared(library.entries, open: "garden-notes")
        model.newConversation()
        (model.ready, model.threadShown) = (library.entry("stack"), false)
        model.place = .space(title: "Garden notes", name: "garden-notes", page: fixture.places.spaces.appendingPathComponent("garden-notes.html").path)
        try await draw(model, "assistant-space-ready" + suffix, fixture)
        let side = NSHostingView(rootView: SidebarView(library: library, assistant: model, eyes: model.eyes))
        let offscreen = Offscreen(side)
        offscreen.window.setContentSize(NSSize(width: 232, height: 320))
        side.frame.size = NSSize(width: 232, height: 320)
        await wait(1)
        try draw(side, "sidebar-ready" + suffix, fixture)
        let made = RightsQuestion(space: "Stack", description: "A one-key game for your breaks.", level: .watch, folder: nil, made: true)
        try draw(try #require(Ask.rights(made, home: "/Users/example").sheet.contentView), "rights-made-by-agent" + suffix, fixture)
        let promise = try #require(Help.page("promise", share: Home.share).flatMap { Help.window($0) })
        promise.appearance = NSAppearance(named: suffix.isEmpty ? .aqua : .darkAqua)
        try draw(try #require(promise.contentView), "help-promise" + suffix, fixture)
    }

    func settle(_ view: SpaceView) async { await Picture.settle(view) }

    /// Puts AssistantTests' fake `claude` in the PATH of `fixture`'s engines.
    func installFakeClaude(_ fixture: Home) throws {
        let bin = fixture.root.appendingPathComponent("bin"), claude = bin.appendingPathComponent("claude")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try AssistantTests.fake.write(to: claude, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
    }

    /// The assistant alone at the bottom of a center `width` by `height` points, on the glass as the window holds it.
    func draw(_ model: AssistantModel, _ name: String, width: CGFloat = 760, height: CGFloat = 150, _ fixture: Home) async throws {
        let center = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let offscreen = Offscreen(center)
        offscreen.window.setContentSize(NSSize(width: width, height: height))
        model.open = true // a space opens with the sticker; these are the card's pictures
        let glass = Glass(over: center, model: model)
        await wait(1)
        try draw(center, name, fixture)
        withExtendedLifetime((offscreen, glass)) {}
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
        state.agents += Watch.elsewhere(Seen(sightings: [claude, opencode, pi]), registry: .app, groups: [], keys: [], now: now).agents
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

    func draw(_ alert: NSAlert, _ name: String, _ fixture: Home) throws { try Picture.alert(alert, name, root: fixture.root) }
    func draw(_ view: NSView, _ name: String, _ fixture: Home) throws { try Picture.view(view, name, root: fixture.root) }
    func png(of size: NSSize, _ name: String, _ content: () -> Void) throws { try Picture.png(of: size, name, content) }
}
