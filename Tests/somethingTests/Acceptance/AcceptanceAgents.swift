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
        #expect(Set(info.shown.map(\.id)) == Set(Bridge.visible(view).agents.map(\.id)).subtracting(view.engine.assistants), "the page's own list")
        #expect(info.shown.map(\.word) == ["Waiting for You", "Working", "Idle"] && info.shown.map(\.tag) == ["In iTerm", "In something", "In something"])
        #expect(info.others.count == 8 && info.othersFolded && info.opened == nil)
        info.refresh()
        #expect(shell.agentsShown.count == 3 && shell.agentsShown.eyes == .wait, "the panel's button: \(shell.agentsShown)")
        #expect(shell.controls[Shell.info]?.accessibilityLabel() == "Your agents: 3. Open the panel")
        #expect((shell.controls[Shell.info] as? AgentsButton)?.attributedTitle.string.hasSuffix("3") == true, "the count on the button")
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
        for words in ["This space: Info", "Export…", "Memory", "Versions", "Show History", "Assistant", "Move to Trash…"] {
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

    /// A page that sees an assistant (decision 12): its own row keeps it out of the list, one quiet line says it, the
    /// count stays true, and what the page gets of it stays its state.
    @Test("the assistants a page sees") func seenAssistants() async throws {
        let stage = try Stage("agents-seen")
        defer { stage.remove() }
        try AcceptanceAssistant.fake(in: stage)
        let (shell, library, info, view) = try await panel(stage, "agents", level: .watch, folder: "something/spaces")
        defer { view.close() }
        let id = try view.engine.launchAssistant("claude", folder: stage.home.places.spaces.path, askEverything: false)
        defer { view.engine.stopAll(within: 1, only: id) {} }
        #expect(await wait(until: { info.refresh(); return info.seenAssistants == 1 }))
        #expect(!info.shown.contains { $0.id == id } && !info.others.contains { $0.id == id })
        let held = try #require(Bridge.visible(view).agents.first { $0.id == id })
        #expect(held.can == Can() && held.thread == nil)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: view.web, "a1-1-assistant" + suffix, root: stage.home.root)
        }
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
        var omp = Agent(id: "omp-live", kind: "omp", origin: "launched")
        omp.alive = true
        #expect(AgentReading(omp, thread: nil, runs: RunsIn { _ in [] }).opened == [.fact("On Its Own", "Never asks by default.")])
        var unheld = Agent(id: "codex-held", kind: "codex", origin: "elsewhere")
        unheld.thread = "t1"
        #expect(AgentReading(unheld, thread: nil, runs: RunsIn { _ in [] }).opened == [.plain("something can’t tell whether it still runs. It doesn’t guess.")])
        #expect(opened("claude-post") == [.plain("Its conversation is closed.")])
        #expect(opened("omp-old") == [.plain("OMP can’t resume this conversation.")], "\(opened("omp-old"))")
        var refused = world.agents[try #require(world.agents.firstIndex { $0.id == "omp-old" })]
        refused.because["resume"] = "An invented reason, proven."
        #expect(AgentReading(refused, thread: nil, runs: RunsIn { _ in [] }).opened == [.plain("An invented reason, proven.")])
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
        info.look = { _, done in found = { done(true) } }
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
    /// The card of Daily brief, its assistant the fake claude with a conversation, ready for a chip.
    private static func card(_ stage: Stage) async throws -> (Shell, Library, SpaceView) {
        try AcceptanceAssistant.fake(in: stage)
        let (shell, library, _) = stage.window()
        let model = shell.assistant
        model.engine.changed = { model.refresh() }
        model.engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        let brief = try await stage.open("brief", in: shell, library)
        model.draft = "Put the agents that wait for me first."
        model.send()
        #expect(await wait(until: { AssistantModel.messages(model.rows) == 2 && !model.working && model.agent?.state == "idle" }), "rows: \(model.rows)")
        shell.glass.card.isHidden = false
        model.focus()
        #expect(await wait { shell.glass.grown == true && !shell.glass.morphing })
        return (shell, library, brief)
    }

    private static func stop(_ shell: Shell) async {
        Popover.shown?.close()
        var stopped = false
        shell.assistant.engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })
    }

    /// The card's three chips; the model chip opens the drawn picker over the card, with each model's line, the gauge
    /// of the levels the model lists and the foot's scope. A click elsewhere closes it, Esc too.
    @Test("r9-1: Three chips, the picker") func r9_1() async throws {
        let stage = try Stage("agents-r9-1")
        defer { stage.remove() }
        let (shell, library, brief) = try await AcceptanceAgents.card(stage)
        defer { brief.close() }
        let model = shell.assistant
        model.choose(model: "opus")
        model.choose(effort: "high")
        #expect(await wait(until: { model.agent?.effort == "high" }))
        #expect(AgentChips.labels(model) == ["Program: Claude Code. Change", "Model: Opus 5.5 · High. Change", "On Its Own: Accepts Edits. Change"])
        let choice = model.modelChoice
        #expect(choice.models == .rows && choice.rows.map(\.name) == ["Opus 5.5", "Sonnet 5.5", "Haiku 5.5"] && choice.rows.map(choice.isChosen) == [true, false, false])
        #expect(choice.efforts.map(\.label) == ["Low", "Medium", "High", "Max"] && choice.scope == "For Daily brief only" && choice.defaults)
        // The picture's list, as the mockup's: the program's own choice, a line under each model, Ultracode after the levels.
        var drawn = ModelChoice(name: "Claude Code", models: .rows, chosen: "opus", effort: "high", scope: "For Daily brief only", defaults: true)
        drawn.list = [Option(value: "default", label: "Default · Sonnet 5.5"), Option(value: "opus", label: "Opus 5.5", about: "The most capable"), Option(value: "haiku", label: "Haiku 5.5", about: "The fastest")]
        drawn.rows = ModelChoice.rows(drawn.list, name: "Claude Code", plain: false)
        drawn.efforts = ["low", "medium", "high", "max"].map { Option(value: $0, label: $0.capitalized) } + [Option(value: "ultracode", label: "Ultracode", about: "A longer, deeper pass for a hard change.")]
        #expect(drawn.rows.map(\.about) == ["Follows Claude Code’s own choice", "The most capable", "The fastest"] && drawn.chip == "Opus 5.5 · High")
        let shown = drawn
        ModelChip.open({ shown }, from: shell.glass.card)
        let popover = try #require(Popover.shown)
        #expect(popover.superview === shell.layer && Popover.open.part == "model")
        let card = shell.glass.card.convert(shell.glass.card.bounds, to: shell.layer).insetBy(dx: AssistantCard.margin, dy: AssistantCard.margin)
        #expect(await wait { Popover.shown?.frame.width ?? 0 > 344 })
        let placed = popover.frame.insetBy(dx: Popover.margin, dy: Popover.margin)
        #expect(abs(placed.minY - card.maxY - 6) < 1 && abs(placed.maxX - card.maxX) < 1, "over the card, to its right edge: \(popover.frame)")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "r9-1" + suffix, root: stage.home.root)
        }
        #expect(Popover.shown === popover && popover.superview === shell.layer && popover.frame.width > 344, "still up after the picture: \(popover.frame)")
        popover.close()
        // The keys: ↓ then Return picks the next model, each step said; Tab goes to the gauge and back.
        var said: [String] = []
        shell.layer.announce = { said.append($0) }
        ModelChip.open({ model.modelChoice }, from: shell.glass.card)
        let keys = try #require(Popover.shown)
        keys.press(.down)
        #expect(said.last == "Sonnet 5.5")
        keys.press(.tab)
        keys.press(.left)
        #expect(await wait(until: { model.modelChoice.effort == "medium" }), "← on the gauge")
        keys.press(.tab)
        keys.press(.enter)
        #expect(Popover.shown == nil && Popover.open.part == nil && model.session.model == "sonnet")
        // Esc, through the window's own path: the picker leaves, and the card under it stays.
        let escape = try AcceptanceShell.escape(shell)
        ModelChip.open({ model.modelChoice }, from: shell.glass.card)
        #expect(shell.escape(escape) && Popover.shown == nil && model.open)
        // The picker leaves with what holds it: a space shown, a card over all.
        ModelChip.open({ model.modelChoice }, from: shell.glass.card)
        shell.show(brief)
        #expect(Popover.shown == nil)
        // The program chip's picker: the programs found, then those something only sees, each with why.
        AgentChips.open(model, from: shell.glass.card)
        #expect(Popover.shown?.press(.down) == true, "the keys walk the programs")
        #expect(Popover.open.part == "program" && model.entries.map(\.id) == ["claude"] && AssistantModel.seenOnly.map(\.name) == ["Antigravity", "Cursor"])
        #expect(await wait { Popover.shown?.frame.height ?? 0 > 200 })
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "r9-1-program" + suffix, root: stage.home.root)
        }
        await AcceptanceAgents.stop(shell)
    }

    /// From seven models: the search field, the providers' groups, a word that narrows them, and none that matches.
    @Test("r9-2: A long list, search and groups") func r9_2() async throws {
        let stage = try Stage("agents-r9-2")
        defer { stage.remove() }
        let (shell, library, brief) = try await AcceptanceAgents.card(stage)
        defer { brief.close() }
        let opencode = ["anthropic/opus": "Anthropic/Opus 5.5", "anthropic/haiku": "Anthropic/Haiku 5.5", "openai/gpt": "OpenAI/GPT-5.5", "openai/mini": "OpenAI/GPT-5.5 Mini",
                        "google/pro": "Google/Gemini 3 Pro", "google/flash": "Google/Gemini 3 Flash", "mistral/large": "Mistral/Large 3", "mistral/small": "Mistral/Small 3"]
        var choice = ModelChoice(name: "OpenCode", models: .rows)
        choice.rows = ModelChoice.rows(opencode.sorted { $0.key < $1.key }.map { Option(value: $0.key, label: $0.value) }, name: "OpenCode", plain: true)
        (choice.chosen, choice.scope, choice.defaults) = ("google/flash", "For Daily brief only", true)
        #expect(choice.isLong && choice.from == "From the providers set in OpenCode" && choice.rows.count == 9 && choice.rows[0].name == "Default")
        #expect(Set(choice.rows.compactMap(\.group)) == ["Anthropic", "OpenAI", "Google", "Mistral"] && !choice.rows.map(\.name).contains { $0.contains("/") })
        #expect(choice.shown("gemini flash").map(\.name) == ["Gemini 3 Flash"] && choice.shown("openai").count == 2 && choice.shown("nothing").isEmpty)
        let held = choice
        let keyboard = PickerKeys({ held })
        #expect(keyboard.row == choice.rows.firstIndex { $0.value == "google/flash" }, "it opens on the chosen row")
        ModelChip.open({ held }, from: shell.glass.card)
        #expect(await wait { Popover.shown?.frame.height ?? 0 > 300 })
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "r9-2" + suffix, root: stage.home.root)
        }
        // Esc in a search clears it, then closes.
        Popover.shown?.close()
        Popover.toggle(from: shell.glass.card, part: "model", keys: keyboard.press) { _ in ModelPicker(choice: { held }, keyboard: keyboard, close: {}) }
        keyboard.query = "gemini"
        let escape = try AcceptanceShell.escape(shell)
        #expect(shell.escape(escape) && keyboard.query.isEmpty && Popover.shown != nil)
        #expect(shell.escape(escape) && Popover.shown == nil)
        await AcceptanceAgents.stop(shell)
    }

    /// What is not known says so: a program that picks its own model, a list being read, a list not read yet with its
    /// effort unknown; and pi's short list says its providers under the names. An id is never drawn.
    @Test("r9-3: Amp, and what is not known") func r9_3() async throws {
        let stage = try Stage("agents-r9-3")
        defer { stage.remove() }
        let (shell, library, brief) = try await AcceptanceAgents.card(stage)
        defer { brief.close() }
        let cases: [(String, ModelChoice)] = [
            ("own", ModelChoice(name: "Amp", models: .own, scope: "For Daily brief only", defaults: true)),
            ("reading", ModelChoice(name: "OMP", models: .reading, scope: "For Daily brief only", defaults: true)),
            ("unread", ModelChoice(name: "OMP", models: .unread, scope: "For Daily brief only", defaults: true)),
        ]
        for (name, choice) in cases {
            ModelChip.open({ choice }, from: shell.glass.card)
            #expect(await wait { Popover.shown?.frame.height ?? 0 > 100 })
            try await stage.appearances { suffix in
                try await Picture.window(shell, library: library, web: brief.web, "r9-3-\(name)" + suffix, root: stage.home.root)
            }
            Popover.shown?.close()
        }
        var short = ModelChoice(name: "pi", models: .rows)
        short.rows = ModelChoice.rows([Option(value: "anthropic/sonnet", label: "Sonnet 5.5"), Option(value: "openai/gpt", label: "GPT-5.5")], name: "pi", plain: true)
        short.effortUnread = true
        #expect(short.rows.map(\.about) == ["Follows pi’s own choice", "anthropic", "openai"] && short.from == "From pi’s own settings" && short.rows.allSatisfy { $0.group == nil })
        #expect(Words.model("claude-example-5", in: nil) == "Another model" && Words.model("sonnet", in: nil) == "Sonnet", "an id is never drawn")
        #expect(Words.model("default", in: [Option(value: "default", label: "Default · Opus 5.5")]) == "Opus 5.5")
        // A running agent's chip: its own list, by the name it gives, no row it could not go back to, and the change goes to it.
        var running = Agent(id: "a1", kind: "claude", origin: "launched")
        (running.model, running.effort, running.options.model, running.options.effort, running.can.effort) = ("opus", "high", [Option(value: "opus", label: "Opus 5.5"), Option(value: "haiku", label: "Haiku 5.5")], [Option(value: "high", label: "High")], true)
        var asked: (String?, String?)?
        // Read again as the picker is drawn: a pick shows while it stays up.
        let row = ModelChoice(agent: running) { asked = ($0, $1) }
        running.effort = nil
        #expect(ModelChoice(agent: running) { _, _ in }.chip == "Opus 5.5")
        #expect(row.chip == "Opus 5.5 · High" && row.rows.map(\.name) == ["Opus 5.5", "Haiku 5.5"] && row.scope == "For this agent · From its next turn" && !row.defaults)
        row.pick("haiku")
        #expect(asked?.0 == "haiku" && asked?.1 == nil)
        ModelChip.open({ short }, from: shell.glass.card)
        #expect(await wait { Popover.shown?.frame.height ?? 0 > 100 })
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "r9-3-noeffort" + suffix, root: stage.home.root)
        }
        await AcceptanceAgents.stop(shell)
    }

    @Test("r8-1: Full Access, the last rung", .disabled("not built yet: AG4")) func r8_1() async throws {}
    @Test("r8-2: The mark's two gestures", .disabled("not built yet: AG4")) func r8_2() async throws {}
    /// F4.1: each answer with what it means, in the agent's words; a free answer, then Skip, which lets the agent
    /// decide. The mockup's sketches beside the answers are for the reading of the person's words (C7): an agent's
    /// question brings none.
    @Test("f4-1: A build's question in full") func f4_1() async throws {
        let (stage, shell, library, host) = try await AcceptanceBuild.building("ask")
        defer { stage.remove() }
        let model = shell.assistant
        #expect(await wait(until: { model.asked != nil }))
        let ladder = try #require(model.ladder)
        #expect(ladder.choices.count == 2 && ladder.details.first == "Big and easy to scan.", "\(ladder.details)")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "f4-1" + suffix, root: stage.home.root)
            let words = await AcceptanceBuild.read(host)
            #expect(words.contains("Your assistant: Before I write it: which way should it read?") && words.contains("One card per agent, Big and easy to scan., 1")
                    && words.contains("Skip") && words.contains("Answer"), "\(words)")
        }
        #expect(await wait { model.arming(now: model.clock()) >= 1 })
        #expect(Ladder.skips(48, modifiers: [], editing: false) && !Ladder.skips(48, modifiers: [], editing: true) && !Ladder.skips(48, modifiers: .shift, editing: false))
        model.ownAnswer = "  "
        model.answerOwn()
        #expect(model.asked != nil, "no empty answer")
        model.ownAnswer = "Biggest first"
        model.answerOwn()
        #expect(await wait(until: { model.asked == nil && model.ownAnswer.isEmpty && model.ladder?.steps[1].mark == .now }))
        #expect(model.ladder?.steps[0].lines.last?.text == "“Biggest first”. Writing it now.", "the answer stays in the steps")
        await AcceptanceBuild.finish(model)
    }

    /// F4.1b: the window's options each say what they mean, the field stays, Skip takes Don't Answer's place.
    @Test("f4-1b: The same, in the window") func f4_1b() async throws {
        let stage = try Stage("trust")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        shell.window.setFrameOrigin(AcceptanceTrust.large)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        let source = FakePrompts()
        let options = ["Top right, next to the date", "In the strip, after “In brief”", "Leave it out for now"]
        let details = ["Always in view. The title moves over a little.", "Small and quiet, with the other headings.", "Nothing changes. You can ask again later."]
        source.prompts = [Prompt(request: Request(id: "q1", agent: "a1", kind: "question", tool: "AskUserQuestion", about: nil, at: iso8601.string(from: Stage.now)),
                                 questions: [Question(header: nil, text: "Where should the weather corner go?", options: options, multiple: false, details: details)])]
        let panels = Panels(source: source, shows: false)
        var time: TimeInterval = 100
        (panels.now, panels.clock) = ({ Stage.now }, { time })
        panels.who = { _ in App.who(Agent(id: "a1", kind: "claude", origin: "launched"), space: "Daily brief", home: "/Users/example", assistant: true) }
        panels.counted = { _ in shell.waiting([], mine: 0) }
        panels.refresh()
        let panel = try #require(panels.panel)
        panel.place(beside: shell.window, screen: AcceptanceTrust.desk)
        #expect(panel.boxes[0].map(\.title) == options && panel.boxes[0].map(\.detail) == details)
        #expect(panel.typed[0].placeholderString == "Or type your answer" && panel.denyButton.title == "Skip")
        time += 1
        panel.tick()
        let rows = panel.boxes[0].map(\.frame.height)
        #expect(rows.allSatisfy { $0 >= 46 }, "two lines each: \(rows)")
        try await stage.appearances { suffix in
            try await Picture.panel(panel, over: shell, library: library, web: brief.web, "f4-1b" + suffix, root: stage.home.root)
        }
        panel.denyButton.performClick(nil)
        #expect(source.answers.map(\.1) == [.deny])
    }

    /// F4.2: Claude Code has never run: its field offers "/", and "/" reads the commands once, with no message. A command
    /// that needs text says "…", stays in the field on Return, says what to write, and goes only with its text. A
    /// program that gives no list says so.
    @Test("f4-2: \"/\" from the first try") func f4_2() async throws {
        let stage = try Stage("assistant")
        defer { stage.remove() }
        try AcceptanceAssistant.fake(in: stage)
        let (shell, library, _) = stage.window()
        let model = shell.assistant
        model.engine.changed = { model.refresh() }
        model.engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        model.focus()
        #expect(await wait { shell.glass.grown == true && !shell.glass.morphing })
        #expect(model.commands.isEmpty && model.agent == nil && model.placeholder == "Ask for a change · / for Claude Code’s commands")
        model.draft = "/"
        #expect(model.noCommands == "Reading its commands…")
        #expect(await wait(until: { model.commands.count == 5 }), "read once, before any message")
        #expect(model.rows.isEmpty && model.agent == nil && model.slashed?.count == 5 && Preferences(stage.home.places).commands["claude"]?.count == 5)
        Preferences.at(stage.home.places).commands["claude"] = [Option(value: "goal", label: "Goals", about: "Describe the goal, then send.")]
        model.draft = "/go"
        try await AcceptanceAssistant.fit(shell)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "f4-2-list" + suffix, root: stage.home.root)
        }
        #expect(Field.slash(.return, model) == .handled && model.draft == "/goal " && model.unfinished?.value == "goal" && !model.canSend)
        model.send()
        #expect(model.draft == "/goal " && model.rows.isEmpty, "it waits for its text")
        try await AcceptanceAssistant.fit(shell)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "f4-2" + suffix, root: stage.home.root)
        }
        model.draft = "/goal Keep the milestones in step with the repo"
        #expect(model.unfinished == nil && model.canSend)
        model.draft = ""
        try await AcceptanceAssistant.stop(model)
    }

    @Test("f4-4: My agents starts an agent", .disabled("not built yet: AG6")) func f4_4() async throws {}
}
