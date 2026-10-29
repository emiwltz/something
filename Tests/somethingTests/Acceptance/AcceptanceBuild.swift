// Acceptance scenarios of the first start and making a space: the welcome, the first space and the hints (x2-1 to
// x2-4), New Space, the build ladder, the arrival, templates and the level sheet. The welcome is drawn alone, as it
// stands on the screen.
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import SwiftUI
import SomethingAgents
import SomethingCore
import Testing
import WebKit
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-build-"))
struct AcceptanceBuild {
    /// X2.1, the welcome (a1, the film, and a2–a8, the five steps, retired): alone, 900 by 560; "Welcome to
    /// something", the title, the three numbered rows beside the picture, who builds already chosen (the first of the
    /// six builders found), the promise and one button.
    @Test("x2-1: the welcome, one screen") func x2_1() async throws {
        let scene = try await Self.welcome()
        defer { scene.remove() }
        #expect(scene.window.title == "Welcome to something" && scene.window.contentView?.frame.size == Welcome.size)
        #expect(scene.assistant.kind == "claude" && scene.assistant.entries.filter(\.enabled).count == 6)
        // Shot with the whole picture lit, as the cycle ends.
        scene.model.light.light(nil)
        try await scene.draw("x2-1") { words in
            #expect(words == Self.welcomeWords(scene.assistant, found: "Found on this Mac. 5 more to choose from."), "\(words)")
        }
    }

    /// X2.2, who builds, changed: the chip opens New Space's own menus, the builders found then the model; choosing
    /// Codex there makes it the builder of the first space, said in the third row and in the picture. A part lit by its
    /// row lights its number.
    @Test("x2-2: Built by, changed") func x2_2() async throws {
        let scene = try await Self.welcome()
        defer { scene.remove() }
        let model = scene.assistant
        #expect(model.entries.filter(\.enabled).map(\.id) == ["claude", "codex", "opencode", "pi", "omp", "amp"])
        model.choose("codex")
        #expect(model.kind == "codex" && model.newKind == "codex")
        scene.model.light.light(.agents)
        try await scene.draw("x2-2") { words in
            #expect(words == Self.welcomeWords(model, found: nil), "\(words)")
        }
        // The chip's menu is a system menu, drawn by the window server where no picture here reaches (cannot_native):
        // its agents and model are written beside the picture as x2-2-menu.txt.
        if let gallery {
            let agents = model.entries.map { "  \($0.title)\($0.checked ? "  ✓" : "")" }
            let models = model.modelMenu.flatMap { part in [part.header.uppercased()] + part.choices.map { "  \($0.title)\($0.checked ? "  ✓" : "")" }
                + (part.note.map { ["  \($0)"] } ?? []) }
            try (["BUILDS THIS SPACE"] + agents + models).joined(separator: "\n").appending("\n")
                .write(to: gallery.appendingPathComponent("x2-2-menu.txt"), atomically: true, encoding: .utf8)
        }
    }

    /// X2.3, the first space for real: Make My First Space (Return) ends the welcome, kept as seen; the window arrives
    /// on New Space, its field asked for the keys, with the builder chosen. The space it builds then arrives alone in
    /// the sidebar, opened, with nothing to allow.
    @Test("x2-3: the first space, for real") func x2_3() async throws {
        let scene = try await Self.welcome()
        defer { scene.remove() }
        let (shell, library, model) = (scene.shell, scene.library, scene.assistant)
        scene.model.finished = { shell.welcomed() }
        model.choose("codex")
        model.open = false
        WelcomeTests.press(scene.window, .return)
        #expect(shell.welcoming == nil && library.preferences.toured && library.selection == .newSpace && model.newKind == "codex")
        #expect(model.open, "its field is asked for the keys")
        let room = try await Self.first(scene)
        defer { room.close() }
        #expect(shell.window.title == "Waiting room" && room.web.url != nil && shell.window.attachedSheet == nil)
        #expect(library.order().map(\.title) == ["Waiting room"])
        await Self.built(model, sticker: shell.glass.sticker)
        model.open = false
        try await scene.stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: room.web, "x2-3" + suffix, root: scene.stage.home.root)
        }
    }

    /// X2.4, the hints, each once: your assistant's by the sticker when the space a build made opens ("Got It", gone
    /// once the card opens); at the next opening, Info's under the title (gone as Info opens); then Point's under its
    /// button (gone once pointing starts). None comes again, and someone who never built a space gets none.
    @Test("x2-4: your assistant, said once") func x2_4() async throws {
        let scene = try await Self.welcome()
        defer { scene.remove() }
        let (shell, library, model) = (scene.shell, scene.library, scene.assistant)
        scene.model.end()
        shell.welcomed()
        shell.made = "elsewhere"
        let room = try await Self.first(scene)
        defer { room.close() }
        #expect(HintBubble.shown(in: shell.layer) == nil && shell.made == "elsewhere", "no hint for a space no build made")
        await Self.built(model, sticker: shell.glass.sticker)
        model.open = false
        var said: [String] = []
        shell.layer.announce = { said.append($0) }
        // As App's `ended` does after a build: the space it made opens, the card open on its conversation. The hint
        // stays owed under the card, and comes once the card shrinks into the sticker.
        shell.made = "waiting-room"
        model.place = AssistantModel.place(room)
        model.open = true
        shell.show(room)
        #expect(model.cardShown)
        await wait(1.8)
        #expect(HintBubble.shown(in: shell.layer) == nil && shell.made == "waiting-room" && library.preferences.hinted.isEmpty)
        model.open = false
        #expect(await wait(until: { HintBubble.shown(in: shell.layer)?.kind == .ask }), "by the sticker once the card is reduced")
        #expect(shell.made == nil && library.preferences.hinted == ["ask"])
        #expect(said == ["Your assistant. It built this space, and changes it when you ask. Press ⌘K, or click it."])
        let bubble = try #require(HintBubble.shown(in: shell.layer)), sticker = shell.glass.sticker
        let spot = shell.layer.convert(sticker.convert(sticker.bounds, to: nil), from: nil)
        #expect(bubble.frame.maxX <= spot.minX && abs(bubble.frame.minY - spot.minY) < 5, "left of the sticker, at its foot: \(bubble.frame) \(spot)")
        #expect(bubble.accessibilityLabel() == said.first && bubble.accessibilityRole() == .group)
        try await scene.stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: room.web, "x2-4" + suffix, root: scene.stage.home.root)
        }
        model.open = true
        #expect(await wait(until: { HintBubble.shown(in: shell.layer) == nil }), "the card open, the hint goes")
        model.open = false
        // The next opening: Info's, under the title; it goes as Info opens.
        shell.show(room)
        #expect(await wait(until: { HintBubble.shown(in: shell.layer)?.kind == .info }))
        let info = try #require(HintBubble.shown(in: shell.layer)), title = shell.titleLine
        #expect(info.frame.maxY <= shell.layer.convert(title.convert(title.bounds, to: nil), from: nil).minY)
        #expect(info.accessibilityLabel() == "Everything about this space. Its file and Export, what it may do with your agents, and who builds it. "
                + "Click its title, or press ⌘I.")
        shell.showInfo(true)
        #expect(HintBubble.shown(in: shell.layer) == nil)
        shell.showInfo(false)
        // Then Point's; once pointing starts, it goes. Then none, ever.
        shell.show(room)
        #expect(await wait(until: { HintBubble.shown(in: shell.layer)?.kind == .point }))
        #expect(HintBubble.shown(in: shell.layer)?.accessibilityLabel() == "Point at a part. To change one part, point at it, then say what should change there. ⌥⌘S")
        shell.point()
        #expect(HintBubble.shown(in: shell.layer) == nil)
        shell.stopPointing()
        #expect(library.preferences.hinted == ["ask", "info", "point"])
        shell.show(room)
        await wait(1.6)
        #expect(HintBubble.shown(in: shell.layer) == nil)
    }

    /// What VoiceOver reads of the welcome, the builder of `model` building; with `found`, the line that says it was
    /// chosen for the person.
    static func welcomeWords(_ model: AssistantModel, found: String?) -> [String] {
        ["Welcome to something", "Pages of your own, that work with your agents.",
         "1. A space, a page of your own. One HTML file on your Mac, blank at first. Export it in one click.",
         "2. Your agents. The coding agents on this Mac. A space can watch them, talk to them or run them, if you say so.",
         "3. Your assistant. One of your agents, \(model.name), builds the space and changes it when you ask.", Hero.label, "Built by",
         AgentModelChip.label(model)] + (found.map { [$0] } ?? []) + ["Nothing leaves your Mac.", "Make My First Space"]
    }

    @MainActor struct WelcomeScene {
        let stage: Stage, shell: Shell, library: Library, model: WelcomeModel, window: NSWindow
        var assistant: AssistantModel { shell.assistant }

        func remove() {
            window.close()
            stage.remove()
        }

        /// Asserts what VoiceOver reads of the welcome with `words`, and draws `name`: the welcome alone.
        func draw(_ name: String, _ words: ([String]) -> Void) async throws {
            try await stage.appearances { suffix in
                try await Picture.alone(window, name + suffix, root: stage.home.root)
                words(await AcceptanceBuild.read(try #require(window.contentView?.subviews.first), whole: true))
            }
        }
    }

    /// A first start: a home with no space, every builder on its PATH, the welcome open alone over the window kept out
    /// of sight, under Reduced motion.
    static func welcome() async throws -> WelcomeScene {
        let stage = try Stage("build")
        for file in try FileManager.default.contentsOfDirectory(at: stage.home.places.spaces, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: file)
        }
        let bin = stage.home.root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        for kind in Registry.app.agents.map(\.kind) { try AssistantTests().install(kind, in: bin) }
        let (shell, library, _) = stage.window()
        library.preferences.motion = .reduced
        library.preferences.groups = []
        library.relist()
        let model = shell.assistant
        model.engine.changed = { model.refresh() }
        model.engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        #expect(App.welcomes(library))
        let welcome = WelcomeModel(places: stage.home.places)
        let window = shell.welcome(welcome, onScreen: false)
        return WelcomeScene(stage: stage, shell: shell, library: library, model: welcome, window: window)
    }

    /// The state a build leaves the open space's assistant in: awake, listening, after a short conversation with the
    /// fake Claude Code the welcome's bin holds.
    static func built(_ model: AssistantModel, sticker: Sticker) async {
        if model.kind != "claude" { model.choose("claude") }
        model.draft = "A waiting room for my agents."
        model.send()
        #expect(await wait(until: { AssistantModel.messages(model.rows) == 2 && !model.working && model.agent?.state == "idle" }), "rows: \(model.rows)")
        // A few seconds on, past the turn's brief "done", the sticker listens.
        #expect(await wait(until: { sticker.sign.state == .listen }), "\(model.presence.state)")
    }

    /// The first space the build made, Waiting room, open alone in Work.
    static func first(_ scene: WelcomeScene) async throws -> SpaceView {
        let (stage, library) = (scene.stage, scene.library)
        try stage.home.space("waiting-room", Self.waitingRoom)
        library.preferences.groups = [Preferences.Group(name: "Work", spaces: ["waiting-room"])]
        library.relist()
        scene.shell.waiting([], mine: 0)
        return try await stage.open("waiting-room", in: scene.shell, library)
    }

    /// X3.1, New Space (d1 retired): the sign, the question, where it is built; the field with, in its bar, the agent
    /// and its model in one chip, ⇧↵ and Build greyed until something is written; under it the level row, pre-set from
    /// the words, Run's folder after it, then "Your choice"; three suggestions that fill the field; no template. x3-1:
    /// the countdown typed, Run chosen in ~/code/shop, as the mockup's. x3-1-empty, x3-1-smallest, x3-1-answer,
    /// x3-1-building, x3-1-no-agent.
    @Test("x3-1: New Space, one field and the level") func x3_1() async throws {
        let stage = try Stage("build")
        defer { stage.remove() }
        let (shell, library, host) = try await Self.newSpace(stage, builder: true)
        // As the mockup's step: round 2's groups, nothing waiting.
        Stage.work(library)
        shell.waiting([], mine: 0)
        let model = shell.assistant
        #expect(shell.window.title == "New Space" && shell.window.subtitle == "" && shell.glass.isHidden && !model.cardShown)
        #expect(model.kind == "claude" && model.draft.isEmpty && !model.canSend && model.level == .none && model.chosenLevel == nil)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "x3-1-empty" + suffix, root: stage.home.root)
            let words = await Self.read(host) { $0 == Self.newSpaceWords() }
            #expect(words == Self.newSpaceWords(), "\(words)")
        }
        // Build is greyed while the field is empty or blank, and only then. (An offscreen SwiftUI view gives VoiceOver only
        // its descriptions: neither a control's enabled state nor its press can be reached here, so the model's are read.)
        model.draft = "  \n "
        #expect(!model.canSend)
        model.draft = "A page of my agents."
        #expect(model.canSend && model.level == .watch)
        model.draft = ""

        // The words pre-set the level while nothing was chosen; a suggestion fills the field with words of its own.
        #expect(BlankView.chips.map(\.0) == ["A countdown to Saturday", "A small game for my breaks", "My reading list"])
        #expect(BlankView.chips.map { Grant.Level.guess($0.1) } == [.watch, .none, .none])
        model.draft = BlankView.chips[0].1
        #expect(model.level == .watch && model.chosenLevel == nil)
        let shop = stage.home.root.appendingPathComponent("code/shop")
        try FileManager.default.createDirectory(at: shop, withIntermediateDirectories: true)
        (model.chosenLevel, model.runFolder) = (.run, shop.path)
        #expect(model.level == .run)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "x3-1" + suffix, root: stage.home.root)
            let words = await Self.read(host) { $0 == Self.newSpaceWords(BlankView.chips[0].1, level: .run) }
            #expect(words == Self.newSpaceWords(BlankView.chips[0].1, level: .run), "\(words)")
        }
        (model.chosenLevel, model.draft) = (nil, "")

        shell.window.setContentSize(NSSize(width: 640, height: 480))
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "x3-1-smallest" + suffix, root: stage.home.root)
        }
        // Return in the field builds (the draft sent); an input method's Return builds nothing. The fake answers in words:
        // each build ends without a new space, and its reply stays on the page above the field, to be answered there,
        // since the assistant's card stays away. (A plain text is out of reach offscreen: the page's own choice is read,
        // and x3-1-answer shows it.)
        shell.window.setContentSize(Stage.Size.main)
        let since = try #require((host as? NSHostingView<BlankView>)?.rootView.since)
        model.draft = "Half written"
        #expect(Field.returned(shift: false, marked: true, model) == .ignored && !model.building && model.draft == "Half written")
        model.draft = "A page for my mornings."
        #expect(Field.returned(shift: false, marked: false, model) == .handled && model.building && model.draft.isEmpty)
        #expect(await wait(until: { !model.building && model.rows.suffix(2) == [.mine(caption: "on the blank page", text: "A page for my mornings."), .reply("Invented reply.")] }))
        #expect(BlankView.reply(in: model, since: since) == "Invented reply." && !model.blocked)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "x3-1-answer" + suffix, root: stage.home.root)
            let answered = await Self.read(host) { $0.contains(BlankView.chips[0].0) }
            #expect(shell.glass.isHidden && answered.contains(BlankView.chips[0].0), "\(answered)")
        }
        // Run without a folder: Build asks one first, then builds with it; the level goes with the build, said to the
        // agent on a line of its own that the conversation does not show, and the next build starts from its words.
        var asked = 0
        model.chooseFolder = { chosen in
            asked += 1
            chosen(shop.path)
        }
        model.draft = "A page that starts a reviewer agent in my shop."
        #expect(model.level == .run && model.runFolder == shop.path, "the folder chosen earlier stays")
        model.runFolder = nil
        model.send()
        #expect(asked == 1 && model.building && model.before?.level == .run && model.before?.folder == shop.path && model.chosenLevel == nil)
        #expect(await wait(until: { !model.building && model.rows.last == .reply("Invented reply.") }))
        #expect(model.rows.contains(.mine(caption: "on the blank page", text: "A page that starts a reviewer agent in my shop.")))
        // A reply older than the page belongs to another moment: back on New Space (as after a space made opens, or a
        // conversation in a space), the page shows none, whether or not the conversation is shown.
        model.threadShown = true
        shell.show(nil)
        let fresh = try #require(shell.center.subviews.first { $0 is NSHostingView<BlankView> } as? NSHostingView<BlankView>)
        #expect(fresh.rootView.since == model.rows.count && BlankView.reply(in: model, since: fresh.rootView.since) == nil)
        // A conversation begun while the page is open (New Conversation, another builder) is all newer than the page:
        // its reply shows, though the earlier one had more rows.
        model.newConversation()
        #expect(model.rows.isEmpty && fresh.rootView.start == 0 && fresh.rootView.since > 0)
        model.send(BlankView.chips[0].1)
        #expect(await wait(until: { !model.building && model.rows.last == .reply("Invented reply.") }))
        #expect(BlankView.reply(in: model, since: fresh.rootView.start) == "Invented reply.")
        // A reply given in a space never comes to New Space: each place has its own conversation.
        let blank = model.rows
        model.place = .space(title: "My agents", name: "agents", page: "/Users/example/something/spaces/agents.html")
        let count = model.rows.count
        model.send("Hello.")
        #expect(await wait(until: { model.rows.count >= count + 2 && model.rows.last == .reply("Invented reply.") && !model.working }))
        model.place = .blank
        #expect(model.rows == blank && BlankView.reply(in: model, since: fresh.rootView.start) == "Invented reply.")
        // The game: the build starts (the fake keeps working on it), the field holds the sentence read only, the level
        // row and the suggestions step aside, Stop is offered, the assistant stays away.
        model.draft = "Half written"
        model.send(BlankView.chips[1].1)
        #expect(model.building && model.draft.isEmpty && model.sessions[.new]?.draft == "Half written", "what was written stays with New Space's field")
        #expect(await wait(until: { model.rows.contains(.mine(caption: "on the blank page", text: BlankView.chips[1].1)) && model.light == .working }))
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "x3-1-building" + suffix, root: stage.home.root)
            let building = await Self.read(fresh)
            #expect(shell.glass.isHidden && !building.contains("Build") && !building.contains(BlankView.chips[0].0) && building.contains("Stop")
                    && building.filter { $0.hasPrefix("With your agents") } == ["With your agents: None"], "\(building)")
        }
        var stopped = false
        model.engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })

        let none = try Stage("build")
        defer { none.remove() }
        let (bare, alone, page) = try await Self.newSpace(none, builder: false)
        #expect(bare.assistant.noAgent && bare.assistant.notice?.title == "No coding agent found.")
        try await none.appearances { suffix in
            try await Picture.window(bare, library: alone, web: nil, "x3-1-no-agent" + suffix, root: none.home.root)
            let words = await Self.read(page)
            #expect(!words.contains("Build") && !words.contains(BlankView.chips[0].0) && words.contains("How to Get One"), "\(words)")
        }
    }

    /// What VoiceOver reads of New Space with `draft` in its field, as far as an offscreen SwiftUI view gives it (its
    /// menus, plain texts and the sign are out of reach here; the level, its sentence and Run's folder are the model's).
    static func newSpaceWords(_ draft: String = "", level: Grant.Level = .none) -> [String] {
        ["What do you want to make?"] + (draft.isEmpty ? [] : [draft]) + ["Build", "With your agents: \(level.title)"] + BlankView.chips.map(\.0)
    }

    /// New Space in a window of `stage`, the toolbar's chip at the mockup's one request; with `builder`, AssistantTests'
    /// fake claude is the builder found, else none is.
    static func newSpace(_ stage: Stage, builder: Bool) async throws -> (Shell, Library, NSView) {
        let bin = stage.home.root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        if builder {
            let claude = bin.appendingPathComponent("claude")
            try AssistantTests.fake.write(to: claude, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
        }
        let (shell, library, _) = stage.window()
        try stage.moment(shell)
        let model = shell.assistant
        model.engine.changed = { model.refresh() }
        model.engine.lookAgain()
        #expect(await wait(until: { builder ? model.kind == "claude" : model.noAgent }))
        library.select(.newSpace)
        shell.show(nil)
        shell.waiting(["agents"], mine: 0)
        let host = try #require(shell.center.subviews.first { $0 is NSHostingView<BlankView> })
        return (shell, library, host)
    }

    /// It builds (S4, J3.4): Build made it a build of its own, which New Space shows: its words for a name, the
    /// sentence held read only with the level chosen under it as one chip, the agent's words in its voice, Plan done
    /// with its time, Write writing waiting-room.html with its time running, Check to come, where it is built, that the
    /// person may leave, and Stop; its row in the sidebar has the ring and is selected. j3-4-stopped: after Stop.
    @Test("j3-4: it builds, you may leave") func j3_4() async throws {
        let (stage, shell, library, host) = try await Self.building("")
        defer { stage.remove() }
        let model = shell.assistant
        #expect(await wait(until: { model.ladder?.steps[1].mark == .now }))
        let ladder = try #require(model.ladder), build = try #require(model.before)
        #expect(ladder.steps.map(\.name) == ["Plan", "Write", "Check"] && ladder.steps.map(\.mark) == [.done, .now, .later])
        #expect(ladder.steps[1].file == "waiting-room.html" && ladder.steps[2].note == "Opens it, reads it, looks for errors" && ladder.eyes == .think)
        #expect(ladder.say == "I’ll make “Waiting room”: one card per agent that waits for you, oldest first." && ladder.progress == 0.5)
        #expect(model.builds.map(\.id) == [build.id] && model.watched == build.id && build.level == .watch)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "j3-4" + suffix, root: stage.home.root)
            let says = { (words: [String]) in
                words.contains("Your assistant: \(ladder.say ?? "")") && words.contains("Stop") && !words.contains("Build")
                    && words.contains("Who is waiting for me") && words.contains("With your agents: Watch")
                    && words.contains { $0.hasPrefix("Write, now, waiting-room.html, ") }
                    && words.contains("Check, to come, Opens it, reads it, looks for errors")
            }
            let words = await Self.read(host, until: says)
            #expect(says(words), "\(words)")
            let side = await Self.read(shell.split.splitViewItems[0].viewController.view) { $0.contains("Who is waiting for me, building, 50 %") }
            #expect(side.contains("Who is waiting for me, building, 50 %"), "\(side)")
        }
        // j3-4-stopped: Stop mid-Write leaves the ladder saying what stays on disk, the sentence back in the field with the
        // level it was built with, and its row gone.
        model.stop()
        #expect(!model.building && model.builds.isEmpty && model.draft == "Who is waiting for me" && model.level == .watch && model.ladder?.steps.map(\.mark) == [.done, .off, .off])
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "j3-4-stopped" + suffix, root: stage.home.root)
            let says = { (words: [String]) in
                words.contains("Your assistant: Stopped. waiting-room.html stays in your spaces folder, unchecked.") && words.contains("Build Again")
                    && !words.contains("Stop")
            }
            let words = await Self.read(host, until: says)
            #expect(says(words), "\(words)")
        }
        await Self.finish(model)
    }

    /// You may leave (S4, X3.2): the person goes to read Daily brief; the build goes on, its page already written, so
    /// its row has its name, in its group, with the ring at half; New Space shows its own field again, and the row
    /// brings the build back. Nothing is said: the toast comes when it is ready (x3-3's other end, LadderTests).
    @Test("x3-2: it builds, you left") func x3_2() async throws {
        let (stage, shell, library, _) = try await Self.building("")
        defer { stage.remove() }
        let model = shell.assistant
        #expect(await wait(until: { model.ladder?.steps[1].mark == .now }))
        let build = try #require(model.before)
        // The page as the agent's first write left it, listed in Notes as the mockup's Week-end.
        Stage.work(library)
        library.preferences.groups[1].spaces.insert("waiting-room", at: 0)
        _ = try stage.home.space("waiting-room", Self.waitingRoom)
        library.relist()
        try AcceptanceShell.eyes(shell, Stage.moment)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        #expect(!model.building && model.watched == nil && model.builds.map(\.id) == [build.id] && model.build(writing: "waiting-room")?.id == build.id)
        #expect(library.sections().first { $0.group == "Notes" }?.entries.contains { $0.id == "waiting-room" } == true)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "x3-2" + suffix, root: stage.home.root)
            let side = await Self.read(shell.split.splitViewItems[0].viewController.view) { $0.contains("Waiting room, building, 50 %") }
            #expect(side.contains("Waiting room, building, 50 %") && !side.contains("Who is waiting for me, building, 50 %"), "\(side)")
        }
        // Its row shows the build on New Space again.
        model.watch(build.id)
        library.select(.newSpace)
        model.place = .blank
        #expect(model.building && model.ladder?.steps[1].mark == .now)
        await Self.finish(model)
    }

    /// A build that runs, in "Who is waiting for me" sent from New Space, the fake claude in `mode` (see AssistantTests).
    static func building(_ mode: String) async throws -> (Stage, Shell, Library, NSView) {
        let stage = try Stage("build")
        let out = stage.home.root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try mode.write(to: out.appendingPathComponent("ladder"), atomically: true, encoding: .utf8)
        let (shell, library, host) = try await newSpace(stage, builder: true)
        // The page watches the person's agents: chosen on New Space, before Build.
        shell.assistant.chosenLevel = .watch
        shell.assistant.send("Who is waiting for me")
        return (stage, shell, library, host)
    }

    static func finish(_ model: AssistantModel) async {
        var stopped = false
        model.engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })
    }
    /// It arrives and opens (S4, X3.3): the page written and the turn ended while New Space shows the build, the space
    /// appears and opens, and the sign's frame grows from New Space's sign to the center's edges over a still of the
    /// page left; drawn at 0.6 of its time (x3-3-growing). Then it plays to its end through `Arrival.open`, as App.open
    /// calls it: the page is not loaded while it plays; once it is gone the page loads with the level chosen before
    /// Build, nothing asked, and the card opens on the conversation: the reply said short, its details folded (x3-3).
    /// A space no longer shown when its arrival ends is not opened, and a new opening ends an arrival still playing.
    @Test("x3-3: it arrives and opens") func x3_3() async throws {
        let (stage, shell, library, _) = try await Self.building("fail")
        defer { stage.remove() }
        let model = shell.assistant
        #expect(await wait(until: { model.ladder?.done == true }))
        // The page the fake says it wrote, then the end of its turn: the app's `ended` lists the spaces and opens the new one.
        try stage.home.space("waiting-room", Self.waitingRoom)
        var made: String?
        model.ended = {
            library.relist()
            made = model.appeared(library.entries)
        }
        try "".write(to: stage.home.root.appendingPathComponent("out/finish"), atomically: true, encoding: .utf8)
        #expect(await wait(until: { made != nil }))
        let name = try #require(made)
        #expect(name == "waiting-room" && library.fresh == nil)
        let ask = FakeAsk()
        let room = try await stage.home.window(try #require(library.entry(name)?.space), ask)
        defer { room.close() }
        room.made = true
        // The still is taken once, in the appearance of the moment: the day's, for the picture.
        let arrival = try await Stage.alone {
            NSApp.appearance = NSAppearance(named: .aqua)
            await wait { shell.window.effectiveAppearance.name == .aqua }
            return try #require(Arrival.made(name, in: shell))
        }
        shell.show(room)
        #expect(shell.window.title == "Waiting room")
        // What App.open does around it: the conversation follows the space shown.
        model.place = AssistantModel.place(room)
        // It starts on the sign of 52 points, its arm and stroke the sign's, its eyes on.
        #expect(arrival.start.face && abs(arrival.start.arm - 52 * 0.31) < 0.01 && arrival.start.stroke == 35)
        #expect(abs(arrival.start.rect.width - 52 * 0.88) < 0.5 && abs(arrival.start.rect.midX - arrival.room.midX) < 1, "\(arrival.start.rect)")
        arrival.progress = 0.6
        let shape = arrival.shape
        #expect(shape.rect.width > arrival.start.rect.width && shape.rect.width < arrival.room.width - 28 && shape.eyes == 0)
        library.select(.space(name))
        try await stage.appearances { suffix in
            // One picture: the still keeps the day it was taken in (the mockup has no night of this screen).
            if suffix.isEmpty { try await Picture.window(shell, library: library, web: room.web, "x3-3-growing", root: stage.home.root) }
        }
        var current = true
        Arrival.open(room, after: arrival, library: library, motion: .calm) { current }
        #expect(arrival.playing && library.fresh == name)
        // While it plays, however long a busy runner makes it: nothing loads, nothing is asked.
        while arrival.playing {
            #expect(room.web.url == nil && ask.questions.isEmpty && shell.window.attachedSheet == nil)
            await wait(0.02)
        }
        #expect(await wait(until: { arrival.superview == nil }))
        #expect(arrival.progress == 1 && !shell.glass.subviews.contains { $0 is Arrival })
        // The mockup's d3 is the end of it: the space arrived, its row selected and fresh (let go 1.6 s after, however
        // long the page then takes to load on a busy Mac).
        #expect(library.fresh == name && library.selection == .space(name))
        // Once it is gone: the page loads with the level chosen on New Space, which was the consent: nothing is asked.
        #expect(await wait(until: { room.web.url != nil }), "\(String(describing: room.web.url))")
        let grant = try #require(try AppFile.read(stage.home.places.grants).spaces[name])
        #expect(ask.questions.isEmpty && grant.level == .watch && room.granted.rights == ["state", "store"] && library.selection == .space(name))
        // The card, open on its conversation: the sentence, what was made, the reply's first paragraph, Details folding the steps.
        #expect(model.open && model.threadShown && model.session.space == name && model.cardShown)
        let at = try #require(model.rows.lastIndex { $0.reply != nil })
        let folded = try #require(AssistantModel.built(model.rows, at: at, ended: !model.working))
        #expect(folded.made == "Made waiting-room.html · checked, 0 errors" && folded.steps.lowerBound > 0)
        #expect(folded.short == "Waiting room is ready. It shows who waits for you, oldest first; try answering Amp, then reopen it.")
        #expect(folded.rest == "Checked twice: the first check found 2 problems, both fixed.")
        #expect(model.rows.contains(.mine(caption: "on the blank page", text: "Who is waiting for me")))
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: room.web, "x3-3" + suffix, root: stage.home.root)
            let card = try #require(shell.glass.subviews.first { $0 is CardHost })
            // The conversation's texts are selectable, which offscreen SwiftUI reads no label of: Details is the card's own.
            let says = { (words: [String]) in words.contains("Details") && words.contains("Fold Conversation") && !words.contains("Hide Details") }
            let words = await Self.read(card, until: says)
            #expect(says(words), "\(words)")
        }

        // Back on New Space, a new page: opening the space again arrives from nowhere.
        shell.show(nil)
        #expect(Arrival.made(name, in: shell) == nil)
        // A space no longer shown when its arrival ends does not open; a new opening ends an arrival still playing.
        let gone = FakeAsk()
        let other = try await stage.home.window(try #require(library.entry(name)?.space), gone)
        defer { other.close() }
        let late = Arrival(start: arrival.start, still: nil, stillRect: .zero)
        shell.glass.hold(late)
        current = false
        Arrival.open(other, after: late, library: library, motion: .reduced) { current }
        #expect(await wait(until: { late.superview == nil }))
        await wait(0.3)
        #expect(other.web.url == nil && gone.questions.isEmpty)
        let ended = Arrival(start: arrival.start, still: nil, stillRect: .zero)
        shell.glass.hold(ended)
        Arrival.open(other, after: ended, library: library, motion: .calm) { current }
        Arrival.end(in: shell)
        #expect(ended.superview == nil && !shell.glass.subviews.contains { $0 is Arrival })
        await Self.finish(model)
    }
    /// The level sheet over a space made elsewhere (by an agent outside something, a template, an import), at its first
    /// opening: "Waiting room would like to work with your agents", where its page is, the four levels pre-set to what
    /// it declares (Watch) and its sentence, the fine print; Don't Allow holding the focus, Allow ready. d4-run: Run,
    /// its folder still to choose, Allow greyed.
    @Test("d4: the level sheet") func d4() async throws {
        let stage = try Stage("build")
        defer { stage.remove() }
        let space = try stage.home.space("waiting-room", Self.waitingRoom)
        let (shell, library, _) = stage.window()
        let room = try await stage.open("waiting-room", in: shell, library)
        defer { room.close() }
        try stage.moment(shell)
        shell.waiting(["agents"], mine: 0)
        let declaration = try #require(Declaration.read(space, home: stage.home.places.home, kinds: Registry.app.kinds).declaration)
        let question = room.question(declaration, nil)
        #expect(question == RightsQuestion(space: "Waiting room", description: nil, level: .watch, folder: nil,
                                           folders: Levels.folders(room.engine.state), page: space.location.path))
        #expect(question.folders == ["/Users/example/code/pacman", "/Users/example/code/portfolio", "/Users/example/code/shop", "/Users/example/notes"],
                "the folders the stage's agents work in")
        let (sheet, answer) = Ask.rights(question, home: stage.home.root.path)
        #expect(sheet.title == "Waiting room would like to work with your agents" && sheet.frame.width == 440 && !sheet.isAlert)
        #expect(PanelsTests.texts(sheet.contentView) == ["Waiting room would like to work with your agents", "~/something/spaces/waiting-room.html",
                                                         "Whatever an agent asks still waits for you, in a window of your Mac: Allow Once or Deny. Its memory needs no permission."])
        #expect(sheet.buttons.map(\.title) == ["Don’t Allow", "Allow"] && sheet.buttons.map(\.hint) == ["esc", nil])
        #expect(sheet.firstResponder === sheet.buttons[0] && sheet.buttons[0].keyEquivalent == "\u{1b}" && sheet.buttons[1].isEnabled)
        #expect(sheet.accessibilitySubrole() == .dialog && answer() == RightsAnswer(level: .watch, folder: nil))
        // What VoiceOver reads (the level's sentence, a plain text of SwiftUI, is out of reach offscreen).
        let said = ["Two people", "Waiting room would like to work with your agents", "~/something/spaces/waiting-room.html", "With your agents: Watch"]
            + [Levels.sheetFine, "Don’t Allow", "Allow"]
        let words = await Self.read(try #require(sheet.contentView)) { $0 == said }
        #expect(words == said, "\(words)")
        // Under the toolbar, centred over the space beside the sidebar.
        let hang = shell.window(shell.window, willPositionSheet: sheet, using: .zero)
        #expect(hang.minY == shell.window.contentLayoutRect.maxY && hang.minX == shell.split.splitViewItems[0].viewController.view.frame.width)
        try await stage.appearances { suffix in
            try await Picture.sheet(sheet, over: shell, library: library, web: nil, "d4" + suffix, root: stage.home.root)
        }
        var run = question
        run.level = .run
        let (runSheet, runAnswer) = Ask.rights(run, home: stage.home.root.path)
        #expect(!runSheet.buttons[1].isEnabled && runAnswer() == RightsAnswer(level: .run, folder: nil))
        try await stage.appearances { suffix in
            try await Picture.sheet(runSheet, over: shell, library: library, web: nil, "d4-run" + suffix, root: stage.home.root)
        }
    }

    /// The space the assistant just made in the mockup, its words invented: one agent waiting in its terminal.
    static let waitingRoom = """
        <!doctype html><html><head><meta charset="utf-8"><title>Waiting room</title>
        <script type="application/json" id="something">{"contract": 1, "title": "Waiting room", "rights": ["state", "store"]}</script><style>
        body{margin:0;padding:34px 46px;background:#F4F4F1;color:#121316;font:13.5px -apple-system,sans-serif}
        @media (prefers-color-scheme:dark){body{background:#15171C;color:#F1F1EE}.w{background:#1F2126!important}button{background:rgba(241,241,238,.08)!important}span,.lead{color:#B4B6BC!important}.none,.age small{color:#9A9CA2!important}}
        h2{font:600 31px/1.1 Georgia,serif;letter-spacing:-.025em;margin:0}
        .lead{color:#5C5E66;margin:8px 0 22px}
        .w{display:grid;grid-template-columns:auto 1fr auto;gap:16px;align-items:center;background:#fff;border-radius:10px;
           box-shadow:0 0 0 1px rgba(18,19,22,.1);padding:14px 16px}
        .age{font:600 22px/1 -apple-system;width:64px}.age small{display:block;font-size:11px;font-weight:500;color:#8A8C92;margin-top:3px}
        b{display:block;font-size:13px}span{color:#5C5E66;font-size:12.5px}
        button{font:500 12px -apple-system;height:28px;padding:0 12px;border-radius:999px;border:0;box-shadow:inset 0 0 0 1px rgba(18,19,22,.17);background:rgba(18,19,22,.06);color:inherit}
        .none{color:#8A8C92;font-size:12.5px;margin:12px 2px}
        </style></head><body><h2>Waiting room</h2><p class="lead">Agents that wait for you in their own terminal, oldest first.</p>
        <div class="w"><div class="age">34<small>minutes</small></div><div><b>Amp · ~/code/shop</b><span>Asks to run the tests before touching the cart page.</span></div><button>Open Terminal</button></div>
        <p class="none">Nobody else waits. Two Claude Code sessions are working, and pi is idle.</p></body></html>
        """
    /// The Templates page in the window, the toolbar's chip at the mockup's one request, the assistant's glass hidden (the
    /// mockup shows the page alone); and the page's model.
    static func templates(_ stage: Stage) throws -> (Shell, Library, Gallery, NSView) {
        let (shell, library, _) = stage.window()
        library.select(.templates)
        shell.show(nil, templates: true)
        shell.glass.isHidden = true
        shell.waiting(["agents"], mine: 0)
        let host = try #require(shell.center.subviews.first { $0 is NSHostingView<GalleryView> } as? NSHostingView<GalleryView>)
        return (shell, library, host.rootView.model, host)
    }


    /// The labels VoiceOver reads in `view`, depth first, once `says` holds of them (else once two reads 0.1 s apart
    /// agree, for a view with no live clock), or after a minute. A SwiftUI view offscreen gives only the description of
    /// its outer elements (AXAttributedDescription): what is inside a card or a bar is out of reach here. With `whole`,
    /// also what its static texts and menu buttons say (their value and title), as VoiceOver reads them.
    static func read(_ view: NSView, whole: Bool = false, until says: (([String]) -> Bool)? = nil) async -> [String] {
        // The mode is the whole process's, and slows every SwiftUI view made meanwhile: the read takes Stage's turn,
        // as what is timed does.
        await Stage.alone {
            let enhanced = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
            // As an assistive app asks: SwiftUI makes its elements only then.
            NSApp.accessibilitySetValue(true, forAttribute: enhanced)
            defer { NSApp.accessibilitySetValue(false, forAttribute: enhanced) }
            // The first question makes them, and SwiftUI updates them, on the run loop, as late as a busy runner lets
            // it: read again until they hold still and say what is awaited. The minute only stops a hang.
            _ = view.accessibilityChildren()
            let end = Date() + 60
            var last: [String]?
            while true {
                await wait(0.1)
                let words = labels(view, whole: whole)
                if says.map({ $0(words) }) ?? (words == last && !words.isEmpty) || Date() > end { return words }
                last = words
            }
        }
    }

    /// What VoiceOver says of `element` alone, as SwiftUI gives it offscreen; empty when it says nothing.
    static func said(_ element: Any) -> String {
        ((element as AnyObject).accessibilityAttributeValue(NSAccessibility.Attribute(rawValue: "AXAttributedDescription")) as? NSAttributedString)?.string ?? ""
    }

    private static func labels(_ element: Any, whole: Bool = false) -> [String] {
        let object = element as AnyObject
        var words = [NSAccessibility.Attribute.description, .title, .value].compactMap { object.accessibilityAttributeValue($0) as? String }
            + [said(element)]
        // SwiftUI's nodes answer these getters only, a title sometimes as attributed text.
        if whole, let node = object as? NSObject {
            words += ["accessibilityTitle", "accessibilityValue"].filter { node.responds(to: Selector($0)) }.compactMap {
                let value = node.value(forKey: $0)
                return value as? String ?? (value as? NSAttributedString)?.string
            }
        }
        let children = (object as? NSAccessibilityProtocol)?.accessibilityChildren() ?? []
        let all = words.filter { !$0.isEmpty } + children.flatMap { labels($0, whole: whole) }
        // A menu's button comes as several nodes of one title: VoiceOver says it once.
        return whole ? all.enumerated().filter { $0.offset == 0 || all[$0.offset - 1] != $0.element }.map(\.element) : all
    }

    /// Six cards in three columns, the first under the pointer with Preview, Show in Finder and Use; Agents keeps two.
    /// d5-narrow: two columns in the narrow window.
    @Test("d5: templates") func d5() async throws {
        let stage = try Stage("build")
        defer { stage.remove() }
        let (shell, library, gallery, host) = try Self.templates(stage)
        #expect(shell.window.title == "Templates" && shell.window.subtitle == "Start from one, then make it yours")
        #expect(gallery.cards(library.templates).map(\.title) == ["My agents", "Project watch", "Daily brief", "Logbook", "Stack", "Pebble"])
        #expect(library.templates.map(\.needs) == ["Sees and writes to your agents", "Sees, writes to and starts agents\u{00A0}· Remembers",
                                                   "Sees your agents\u{00A0}· Remembers", "Sees your agents\u{00A0}· Remembers", "Remembers",
                                                   "Sees your agents\u{00A0}· Remembers"])
        gallery.hovered = "agents"
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d5" + suffix, root: stage.home.root)
            // VoiceOver reads the heading, the filters and one element per card, named by its template.
            let cards = ["Templates", "Show", "My agents", "Project watch", "Daily brief", "Logbook", "Stack", "Pebble"]
            #expect(await Self.read(host) { $0 == cards } == cards)
        }
        gallery.shown = .agents
        #expect(gallery.cards(library.templates).map(\.id) == ["agents", "project"])
        gallery.shown = .all
        // The cards as drawn: their left edges make three columns, then two in the narrow window.
        let columns = { Set(gallery.drawn.values.map { $0.minX.rounded() }).count }
        #expect(gallery.drawn.count == 6 && columns() == 3, "\(gallery.drawn)")
        // Forgotten first, so that only cards drawn at the new size count.
        gallery.drawn = [:]
        shell.window.setContentSize(NSSize(width: 760, height: 680))
        #expect(await wait { gallery.drawn.count == 6 && columns() == 2 }, "\(gallery.drawn)")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d5-narrow" + suffix, root: stage.home.root)
        }
    }

    /// My agents' preview: its picture under the bar, the toolbar naming it; Escape goes back to the cards
    /// (TemplatesTests uses one from its preview).
    @Test("d6: a template's preview") func d6() async throws {
        let stage = try Stage("build")
        defer { stage.remove() }
        let (shell, library, gallery, host) = try Self.templates(stage)
        let agents = try #require(library.templates.first { $0.id == "agents" })
        gallery.preview(agents)
        #expect(shell.window.title == "My agents" && shell.window.subtitle == "Template preview")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d6" + suffix, root: stage.home.root)
            // The bar, then the picture; the cards are gone.
            let bar = ["Template preview", "A picture of My agents"]
            #expect(await Self.read(host) { $0 == bar } == bar)
        }
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: shell.window.windowNumber,
                                                   context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        #expect(shell.window.performKeyEquivalent(with: escape))
        #expect(gallery.previewing == nil && shell.window.title == "Templates")
    }

    /// The build's question on the page: what it asks in the agent's voice, its two labels numbered, Write waiting for
    /// the answer; the choice goes back to the agent, which writes.
    @Test("d7: inline choices") func d7() async throws {
        let (stage, shell, library, host) = try await Self.building("ask")
        defer { stage.remove() }
        let model = shell.assistant
        #expect(await wait(until: { model.asked != nil }))
        let ladder = try #require(model.ladder)
        #expect(ladder.say == "Before I write it: which way should it read?" && ladder.choices == ["One card per agent", "A single list, oldest first"])
        #expect(ladder.steps.map(\.mark) == [.done, .waits, .later] && ladder.steps[1].note == "Waits for your answer" && ladder.eyes == .wait)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d7" + suffix, root: stage.home.root)
            let words = await Self.read(host)
            #expect(words.contains("One card per agent, 1") && words.contains("A single list, oldest first, 2")
                    && words.contains("Write, waits for you, Waits for your answer"), "\(words)")
        }
        model.answer(1)
        #expect(await wait(until: { model.asked == nil && model.ladder?.steps[1].mark == .now }))
        await Self.finish(model)
    }

    /// The check step after a failed check: two edits fix it, the second check passes, and every step says its time.
    @Test("d8: the check step") func d8() async throws {
        let (stage, shell, library, host) = try await Self.building("fail")
        defer { stage.remove() }
        let model = shell.assistant
        #expect(await wait(until: { model.ladder?.steps[2].note == "Found problems · Fixing them…" || model.ladder?.steps[2].mark == .done }))
        #expect(await wait(until: { model.ladder?.steps[2].mark == .done && model.ladder?.say?.hasPrefix("Waiting room is ready.") == true }))
        let ladder = try #require(model.ladder)
        #expect(ladder.done && ladder.eyes == .done && ladder.steps[2].note == "Passed after 2 fixes")
        #expect(ladder.steps.allSatisfy { Ladder.took($0, now: model.clock()) != nil })
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d8" + suffix, root: stage.home.root)
            let words = await Self.read(host)
            #expect(!words.contains("Stop") && words.contains { $0.hasPrefix("Check, done, Passed after 2 fixes, ") }, "\(words)")
        }
        await Self.finish(model)
    }
}

extension Picture {
    /// A window of its own (the welcome, How something Works) as it stands alone: its frame drawn at 2x, title bar
    /// included, in its rounded corners, its lights in their colors.
    static func alone(_ window: NSWindow, _ name: String, root: URL) async throws {
        guard gallery != nil else { return }
        let frame = try #require(window.contentView?.superview)
        disguise(frame, root.path)
        await wait(1.0)
        frame.layoutSubtreeIfNeeded()
        let drawn = try bitmap(frame.bounds.size)
        frame.cacheDisplay(in: frame.bounds, to: drawn)
        let lights = lights(of: window)
        try png(of: frame.bounds.size, name) {
            NSBezierPath(roundedRect: frame.bounds, xRadius: Look.window, yRadius: Look.window).addClip()
            drawn.draw(in: frame.bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            paint(lights)
        }
    }
}
