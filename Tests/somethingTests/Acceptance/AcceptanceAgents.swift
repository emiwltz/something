// Acceptance scenarios of the agents, round 4: the panel (a1-1 to a1-12), the three chips and the picker (r9-1 to r9-3),
// Full Access (r8-1, r8-2), a question in full and "/" (f4-1, f4-1b, f4-2) and My agents starting an agent (f4-4).
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import SomethingCore
import Testing
@testable import SomethingAgents
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-agents-"))
struct AcceptanceAgents {
    /// `name`'s window, the panel open, its page at `level` in `folder`, among the mockup's agents with their folders in
    /// the Stage's home, so that rows read ~/code/shop.
    private func panel(_ stage: Stage, _ name: String, level: Grant.Level, folder: String) async throws -> (shell: Shell, library: Library, info: Info, view: SpaceView) {
        try stage.home.space("week-end", AcceptanceShell.weekendPage)
        let (shell, library, info) = stage.window()
        let home = stage.home.places.home.path, scope = home + "/" + folder
        let space = try #require(library.entry(name)?.space)
        let declaration = try #require(Declaration.read(space, home: stage.home.places.home, kinds: Registry.app.kinds).declaration)
        try Grants(stage.home.places.grants).update {
            $0.spaces[name] = Rights.leveled(level, folder: nil, declaration: declaration, at: "2026-10-22T18:00:00Z", after: nil, scope: .folders([scope]))
        }
        let view = try await stage.open(name, in: shell, library)
        view.engine.update(outside: Self.world(home))
        view.push()   // the app's timer pushes four times a second; no timer runs here
        await Picture.settle(view)
        (info.current, info.clock) = ({ view }, { Stage.local })
        info.show(view.space)
        shell.showInfo(true)
        shell.window.layoutIfNeeded()
        return (shell, library, info, view)
    }

    /// `Stage.world`, its folders under `home`.
    private static func world(_ home: String) -> (agents: [Agent], threads: [AgentThread]) {
        var world = Stage.world
        for index in world.agents.indices {
            world.agents[index].folder = world.agents[index].folder?.replacingOccurrences(of: "/Users/example", with: home)
        }
        return world
    }

    /// The panel at rest (A1.1): its tabs, Agents first; the sentence; the assistant; what the page sees, the same three as
    /// the page; the others folded. Then the Info tab, the title's way there, ⌘I and Esc wherever the focus is.
    @Test("a1-1: The panel at rest: Agents, Info, History; the button's count") func a1_1() async throws {
        let stage = try Stage("agents-a1-1")
        defer { stage.remove() }
        let (shell, library, info, view) = try await panel(stage, "week-end", level: .watch, folder: "code/shop")
        defer { view.close() }
        #expect(info.content == .agents && shell.infoShown && (shell.controls[Shell.info] as? ToolButton)?.pressed == true)
        #expect(info.shown.map(\.title) == ["Fix the cart total", "Login form", "Shop tests"], "\(info.shown.map(\.title))")
        #expect(info.shown.map(\.word) == ["Waiting for You", "Working", "Idle"] && info.shown.map(\.tag) == ["In iTerm", "In something", "In something"])
        #expect(info.others.count == 8 && info.othersFolded && info.opened == nil)
        info.refresh()
        #expect(shell.agentsShown.count == 3 && shell.agentsShown.eyes == .wait, "the panel's button: \(shell.agentsShown)")
        #expect(shell.controls[Shell.info]?.accessibilityLabel() == "Your agents: 3. Open the panel")
        let read = await AccessibilityTests.walk(shell.inspector.viewController.view) { $0.contains("Look Again") }
        #expect(read.unnamed.isEmpty, "\(read.unnamed)")
        for words in ["This space: Agents", "Close the panel", "What it may do", "Which agents it shows", "This Space Sees, 3", "Others on This Mac, 8", "Look Again"] {
            #expect(read.words.contains(words), "the panel reads \(words): \(read.words)")
        }
        #expect(read.words.contains { $0.hasPrefix("Week-end’s assistant, ") && $0.contains("~/something/spaces") }, "\(read.words)")
        for gone in ["Chase mode", "something reads them", "Open Conversation", "Export"] {
            #expect(!read.words.contains { $0.contains(gone) }, "at rest it holds no \(gone): \(read.words)")
        }
        #expect(read.words.contains { $0.hasPrefix("Fix the cart total, Waiting for You, Claude Code · ~/code/shop, In iTerm") }, "\(read.words)")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: view.web, "a1-1" + suffix, root: stage.home.root)
        }

        // A word of the sentence applies at once, as the page hears; the list follows.
        var said = info.choice
        said.scope = .all
        info.say(said)
        #expect(view.granted.agents == .all && info.shown.count == 11 && info.others.isEmpty, "\(info.shown.count)")
        said.scope = .folders([stage.home.places.home.path + "/code/shop"])
        info.say(said)
        #expect(try info.shown.count == 3 && AppFile.read(stage.home.places.grants).spaces["week-end"]?.scope == said.scope)
        // Run waits for its folder: the sentence says so, and nothing is granted meanwhile.
        said.level = .run
        said.folder = .none
        info.say(said)
        #expect(info.choice.level == .run && info.level == .watch && view.granted.rights.contains("launch") == false)

        // The title opens Info, which keeps what is not about agents; ⌘I closes and opens on Agents.
        info.show(view.space)
        shell.showInfo(false)
        shell.toggleTitle()
        #expect(shell.infoShown && info.content == .info && shell.titleLine.held)
        let tab = await AccessibilityTests.walk(shell.inspector.viewController.view) { $0.contains("Move to Trash…") }.words
        for words in ["This space: Info", "Export", "Memory", "Versions", "Show History", "Assistant", "Move to Trash…"] {
            #expect(tab.contains(words), "the Info tab reads \(words): \(tab)")
        }
        #expect(info.memory == "It keeps no memory.")
        shell.toggleTitle()
        #expect(!shell.infoShown)
        shell.toggleInfo(spaceOpen: true)
        #expect(shell.infoShown && info.content == .agents && shell.infoWords == "Hide Agents")
        info.select(.history)
        #expect(info.content == .history && (shell.controls[Shell.info] as? ToolButton)?.pressed == true)
        shell.toggleInfo(spaceOpen: true)
        #expect(!shell.infoShown && shell.infoWords == "Show Agents")
        // Esc closes it with the focus on the page: the panel's own close, whatever the page would do with the key.
        shell.showInfo(true)
        #expect(shell.window.makeFirstResponder(view.web))
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: shell.window.windowNumber,
                                                   context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        #expect(shell.escape(escape) && !shell.infoShown)
    }

    /// A row's detail, in place, one at a time: what it says by where the agent stands, an error's words included; a
    /// person with one agent keeps a short panel.
    @Test("a row opened in place, by phase") func openedRows() async throws {
        let stage = try Stage("agents-rows")
        defer { stage.remove() }
        let (shell, library, info, view) = try await panel(stage, "agents", level: .talk, folder: "code")
        defer { view.close() }
        var world = Self.world(stage.home.places.home.path)
        let errored = try #require(world.agents.firstIndex { $0.id == "claude-slides" })
        world.agents[errored].error = AgentError(code: "invented", message: "The invented model refused the turn.")
        (world.agents[errored].state, world.agents[errored].mode, world.agents[errored].model) = ("error", "plan", "Sonnet")
        view.engine.update(outside: world)
        info.othersOpen = true
        info.refresh()
        func opened(_ id: String) -> [AgentReading.Line] { (info.shown + info.others).first { $0.id == id }?.opened ?? [] }
        #expect(info.shown.contains { $0.title == "Chase mode" && $0.agent.subagents?.count == 3 })
        #expect(opened("claude-pacman") == [.fact("On Its Own", "Its own settings")])
        #expect(opened("claude-shop") == [.fact("On Its Own", "Its own settings"), .plain("It runs in iTerm. Answer it there.")])
        #expect(opened("pi-notes") == [.fact("On Its Own", "Never asks, by design.")])
        #expect(opened("claude-post") == [.plain("Its conversation is closed.")])
        #expect(opened("omp-old") == [.plain("OMP can’t resume this conversation.")])
        #expect(opened("claude-slides") == [.plain("The invented model refused the turn."), .fact("Model", "Sonnet"), .fact("On Its Own", "plan")], "\(opened("claude-slides"))")
        #expect(opened("antigravity-site") == [.plain("something sees it running, not what it does. It doesn’t guess.")])
        // In place, one at a time, its state said to VoiceOver.
        info.opened = "claude-slides"
        info.opened = "antigravity-site"
        #expect(info.opened == "antigravity-site")
        let heard = await AccessibilityTests.walk(shell.inspector.viewController.view) { $0.contains { $0.hasPrefix("Antigravity") } }
        #expect(heard.unnamed.isEmpty && heard.words.contains { $0.hasPrefix("Chase mode") && $0.contains("+3 helpers") }, "\(heard)")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: view.web, "a1-2-rows" + suffix, root: stage.home.root)
        }
        // One person, one agent: the assistant, one row, and Others · 0 in one line, with Look Again still there.
        var one = Self.world(stage.home.places.home.path)
        one.agents = one.agents.filter { $0.id == "claude-login" }
        view.engine.update(outside: one)
        (info.opened, info.othersOpen) = (nil, nil)
        info.refresh()
        #expect(info.others.isEmpty && !info.othersFolded)
        let short = await AccessibilityTests.walk(shell.inspector.viewController.view) { $0.contains("Others on This Mac, 0") }.words
        #expect(short.contains("Look Again") && short.contains("This Space Sees, 1"), "\(short)")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: view.web, "a1-1-one" + suffix, root: stage.home.root)
        }
    }

    @Test("a1-2: Reading a row, each kind of agent", .disabled("not built yet: AG7")) func a1_2() async throws {}
    @Test("a1-3: At not see: the fallback, Show to This Space, Undo", .disabled("not built yet: AG3")) func a1_3() async throws {}
    @Test("a1-4: Modify: three chips, the ladder, the confirmation", .disabled("not built yet: AG4")) func a1_4() async throws {}
    @Test("a1-5: Talk: one card, its title's menu", .disabled("not built yet: AG5")) func a1_5() async throws {}
    @Test("a1-6: Read: no composer, Go to iTerm", .disabled("not built yet: AG5")) func a1_6() async throws {}
    @Test("a1-7: Hide: the page loses it, Undo", .disabled("not built yet: AG3")) func a1_7() async throws {}
    @Test("a1-8: + Start: the form, In something", .disabled("not built yet: AG6")) func a1_8() async throws {}
    /// Others on This Mac (A1.9): folded when long; opened, by folder; Look Again says Looking…, what it found with a halo,
    /// then "Nothing new."
    @Test("a1-9: Others on This Mac, Look Again") func a1_9() async throws {
        let stage = try Stage("agents-a1-9")
        defer { stage.remove() }
        let (shell, library, info, view) = try await panel(stage, "agents", level: .talk, folder: "code/shop")
        defer { view.close() }
        let home = stage.home.places.home.path
        var world = Self.world(home)
        var found: (() -> Void)?
        info.look = { _, done in found = done }
        func finish() throws {
            let done = try #require(found)
            done()
        }
        #expect(info.othersFolded && info.others.count > 3)
        info.lookAgain()
        #expect(info.looking && info.said == nil)
        info.lookAgain()   // a second click while it looks changes nothing
        let read = await AccessibilityTests.walk(shell.inspector.viewController.view) { $0.contains("Looking…") }.words
        #expect(read.contains("Looking…"), "\(read)")
        var twelfth = Stage.twelfth
        twelfth.folder = home + "/code/site"
        world.agents.append(twelfth)
        view.engine.update(outside: world)
        try finish()
        #expect(!info.looking && info.said == "Found Cursor in ~/code/site." && !info.othersFolded)
        #expect(info.fresh == [Rights.key(twelfth)] && info.groups.contains { $0.folder == home + "/code/site" })
        #expect(info.groups.first?.folder == home + "/code/pacman", "by folder, each where its first agent stands: \(info.groups.map(\.folder))")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: view.web, "a1-9" + suffix, root: stage.home.root)
        }
        info.lookAgain()
        try finish()
        #expect(info.said == "Nothing new.")
        #expect(await wait(until: { info.fresh.isEmpty }), "the halo ends")
        info.othersOpen = false
        #expect(info.othersFolded)
        // What it found goes with the space: another space starts folded and says nothing.
        info.show(nil)
        #expect(info.said == nil && info.othersOpen == nil)
    }
    @Test("a1-10: Continue in Terminal and in something, the sheet", .disabled("not built yet: AG7")) func a1_10() async throws {}
    @Test("a1-11: Quit and come back: who can't continue, Asleep", .disabled("not built yet: AG7")) func a1_11() async throws {}
    @Test("a1-12: ⌘P finds an agent; the window says its title; Show Agent", .disabled("not built yet: AG8")) func a1_12() async throws {}
    @Test("r9-1: Three chips, the picker", .disabled("not built yet: AG4")) func r9_1() async throws {}
    @Test("r9-2: A long list, search and groups", .disabled("not built yet: AG4")) func r9_2() async throws {}
    @Test("r9-3: Amp, and what is not known", .disabled("not built yet: AG4")) func r9_3() async throws {}
    @Test("r8-1: Full Access, the last rung", .disabled("not built yet: AG4")) func r8_1() async throws {}
    @Test("r8-2: The mark's two gestures", .disabled("not built yet: AG4")) func r8_2() async throws {}
    @Test("f4-1: A build's question in full", .disabled("not built yet: AG5")) func f4_1() async throws {}
    @Test("f4-1b: The same, in the window", .disabled("not built yet: AG5")) func f4_1b() async throws {}
    @Test("f4-2: \"/\" from the first try", .disabled("not built yet: AG5")) func f4_2() async throws {}
    @Test("f4-4: My agents starts an agent", .disabled("not built yet: AG6")) func f4_4() async throws {}
}
