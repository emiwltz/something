// Acceptance scenarios of the first start and making a space: the welcome, the first space and the hints, New Space,
// the build ladder, the arrival, templates and the level sheet. The welcome is drawn alone, as it stands on the screen.
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import SwiftUI
@testable import SomethingAgents
import SomethingCore
import Testing
import WebKit
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-build-"))
struct AcceptanceBuild {
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
        // Past the 1.3 s the hint waits, by that clock: closing the card before it looked would race the sticker's return.
        await mainQueue(after: 1.8)
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

    /// What VoiceOver reads of a beat's window, up to its footer.
    static func beatWords(_ beat: WelcomeModel.Beat, schema: [String] = [PageSchema.label], back: Bool = false, right: [String] = ["Continue"]) -> [String] {
        ["Welcome to something", beat.title, beat.sentence] + schema + ["\(beat.rawValue + 1) of 5", "Skip"] + (back ? ["Back"] : []) + right
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
        (model.chosenLevel, model.runFolder) = (.run, .path(shop.path))
        #expect(model.level == .run)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "x3-1" + suffix, root: stage.home.root)
            let words = await Self.read(host) { $0 == Self.newSpaceWords(BlankView.chips[0].1, sentence: Self.startWords) }
            #expect(words == Self.newSpaceWords(BlankView.chips[0].1, sentence: Self.startWords), "\(words)")
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
        #expect(model.level == .run && model.runFolder == .path(shop.path), "the folder chosen earlier stays")
        model.runFolder = .none
        model.send()
        #expect(asked == 1 && model.building && model.before?.choice.level == .run && model.before?.choice.folder == .path(shop.path) && model.chosenLevel == nil)
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
        // The game: the build starts (the fake keeps working on it), its page takes New Space's place: the field, the
        // level row and the suggestions step aside, Stop is offered, the assistant stays away.
        model.draft = "Half written"
        model.send(BlankView.chips[1].1)
        #expect(model.building && model.draft.isEmpty && model.sessions[.new]?.draft == "Half written", "what was written stays with New Space's field")
        #expect(await wait(until: { model.rows.contains(.mine(caption: "on the blank page", text: BlankView.chips[1].1)) && model.light == .working }))
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "x3-1-building" + suffix, root: stage.home.root)
            let building = await Self.read(fresh)
            #expect(shell.glass.isHidden && !building.contains("Build Now") && !building.contains(BlankView.chips[0].0) && building.contains("Stop"), "\(building)")
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
    static func newSpaceWords(_ draft: String = "", sentence: [String] = ["Your default", "What it may do", "Who answers"]) -> [String] {
        ["What do you want to make?"] + (draft.isEmpty ? [] : [draft]) + ["Program: Claude Code. Change", "Model: Default model. Change", "On Its Own: Accepts Edits. Change", "Build Now", "Continue"] + sentence + BlankView.chips.map(\.0)
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

    /// It builds (C2, the page of R3.2 before its picture; r3-2, C3's, retires this id): Build gave it a page of its own,
    /// the words for a name, who builds and with which model, Stop; on the left the words and the sentence, then the three
    /// steps with their real lines; on the right the skeleton; at the foot where it is built and that the person may
    /// leave. No field, no level card, no suggestion. Its row in the sidebar has the ring and is selected. Then Stop.
    @Test("j3-4: it builds, you may leave") func j3_4() async throws {
        let (stage, shell, library, host) = try await Self.building("")
        defer { stage.remove() }
        let model = shell.assistant
        #expect(await wait(until: { model.ladder?.steps[1].mark == .now }))
        let ladder = try #require(model.ladder), build = try #require(model.before)
        let planned = "Planned: I’ll make “Waiting room”: one card per agent that waits for you, oldest first."
        #expect(ladder.steps.map(\.name) == ["Plan", "Write", "Check"] && ladder.steps.map(\.mark) == [.done, .now, .later])
        #expect(ladder.steps[0].lines.map(\.text) == ["Read the guide", planned])
        #expect(ladder.steps[1].lines == [.init(text: "Writing waiting-room.html", mark: .now)] && ladder.steps[2].note == "Opens it, reads it, looks for errors")
        #expect(ladder.eyes == .think && ladder.say == nil && ladder.progress == 0.5)
        #expect(model.builds.map(\.id) == [build.id] && model.watched == build.id && build.choice.level == .watch)
        #expect(build.choice.said(home: library.places.home.path) == "This space may watch all your agents.")
        #expect(model.whoBuilds == "\(model.name) · \(model.modelWords.model)")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "j3-4" + suffix, root: stage.home.root)
            let says = { (words: [String]) in
                words.contains("Stop") && !words.contains("Build Now") && !words.contains("Continue") && !words.contains(BlankView.chips[0].0)
                    && words.contains("Your words: Who is waiting for me. This space may watch all your agents.")
                    && words.contains("Building · \(model.whoBuilds)")
                    && words.contains { $0.hasPrefix("Plan, done, Read the guide, \(planned), ") }
                    && words.contains { $0.hasPrefix("Write, now, Writing waiting-room.html, ") }
                    && words.contains("Check, to come, Opens it, reads it, looks for errors")
            }
            let words = await Self.read(host, until: says)
            #expect(says(words), "\(words)")
            #expect(await wait(until: { !shell.drawer.state.dock }), "pressing Build sends the sidebar away")
            shell.drawer.open()
            let side = await Self.read(shell.drawer.host) { $0.contains("Who is waiting for me, building, 50 %") }
            #expect(side.contains("Who is waiting for me, building, 50 %"), "\(side)")
        }
        // One column under 720 points of content, the foot's right side gone.
        let wide = shell.window.frame.size
        shell.window.setContentSize(NSSize(width: 640, height: 480))
        try await stage.appearances { suffix in try await Picture.window(shell, library: library, web: nil, "j3-4-narrow" + suffix, root: stage.home.root) }
        shell.window.setContentSize(wide)
        // Stop mid-Write goes back to the field: the words in it, the level they were built with, its row gone, a toast.
        model.stop()
        #expect(!model.building && model.builds.isEmpty && model.draft == "Who is waiting for me" && model.level == .watch && model.ladder == nil)
        let toast = try #require(shell.layer.subviews.compactMap { $0 as? Toast }.last)
        #expect(toast.words == "Stopped · what it changed stays in your spaces folder", "the fake writes nothing to disk: the toast names no file")
        toast.leave(now: true)
        let back = { (words: [String]) in words.contains("Build Now") && !words.contains("Stop") && !words.contains { $0.hasPrefix("Your assistant:") } }
        let words = await Self.read(host, until: back)
        #expect(back(words), "\(words)")
        await Self.finish(model)
    }

    /// You may leave (S4, X3.2): the person goes to read Daily brief; the build goes on, its page already written, so
    /// its row has its name, in its group, with the ring at half; New Space shows its own field again, and the row
    /// brings the build back. Nothing is said: the toast comes when it is ready (x3-3's other end, LadderTests).
    /// A live build that cannot go on is said as it is, with its notice: its model out of reach is no "Building".
    @Test("A stuck build says so on its page") func stuckBuild() async throws {
        let stage = try Stage("build")
        defer { stage.remove() }
        let (shell, _, host) = try await Self.newSpace(stage, builder: true)
        let model = shell.assistant
        model.send("Make the counters bigger")
        #expect(await wait(until: { model.building && model.presence.stuck != nil }))
        let notice = try #require(model.notice), word = model.presence.word
        let says = { (words: [String]) in words.contains(word) && words.contains(notice.title) && !words.contains { $0.hasPrefix("Building") } }
        let words = await Self.read(host, until: says)
        #expect(says(words), "\(words)")
        await Self.finish(model)
    }

    /// R1.1, the sentence: under the field, "With your agents", its tag, "This space may [talk to] [all your agents].", each
    /// word a menu in the sentence's own words; the warning names the agents that never ask and replaces the lock line.
    /// The bar says Build Now ⌘↵ and Continue ↵. Words that ask for agents pre-set watch (promises E 31).
    @Test("r1-1: the sentence") func r1_1() async throws {
        let stage = try Stage("build")
        defer { stage.remove() }
        let (shell, library, host) = try await Self.newSpace(stage, builder: true)
        Stage.work(library)
        shell.waiting([], mine: 0)
        let model = shell.assistant
        // As the mockup's: two agents of a space's own that never ask, and the Stage's, which it only reads.
        var world = Stage.world
        for (id, kind, title, folder) in [("reading", "pi", "Reading list", "notes"), ("tests", "amp", "Shop tests", "code/shop")] {
            var agent = Agent(id: id, kind: kind, origin: "launched")
            (agent.folder, agent.alive, agent.state, agent.can.send) = ("/Users/example/" + folder, true, "idle", true)
            world.agents.append(agent)
            world.threads.append(AgentThread(id: id, agent: id, title: title, started: nil, turns: []))
        }
        model.engine.update(outside: world)
        #expect(model.origin == "Your default" && model.choice.line(home: "/Users/example") == "[something] With your agents: None.")
        #expect(model.warning == nil && Levels.fine == "Whatever an agent asks still waits for you.")
        #expect(BlankView.placeholder == "A space that shows who is waiting for me, oldest first…")
        model.draft = "A space that shows who is waiting for me, oldest first"
        #expect(model.level == .watch && model.origin == "Pre-set from your words", "words that ask for agents pre-set watch")
        model.draft = BlankView.chips[0].1
        #expect(model.choice.line(home: "/Users/example") == "[something] With your agents: Watch." && model.warning == nil)
        let sentence = Self.sentence(model)
        #expect(sentence.levelMenu.title == "What it may do with your agents")
        #expect(sentence.levelMenu.rows.map(\.title) == ["not see", "watch", "talk to", "start"])
        #expect(sentence.levelMenu.rows.map(\.note) == ["Sees nothing.", "Sees your agents.", "Sees and writes to them.", "Sees, writes, starts them."])
        #expect(sentence.levelMenu.rows.map(\.on) == [false, true, false, false])
        #expect(sentence.scopeMenu.title == "Which agents it shows" && sentence.scopeMenu.rows.map(\.title) == ["All agents on this Mac", "Only in a folder…"])
        #expect(sentence.scopeMenu.rows.map(\.note) == ["Every one of them, now and later.", "Only the agents working in the folder you pick."])
        // The system's menu keeps the rows' two lines; no window server menu runs here.
        let system = sentence.levelMenu.menu
        #expect(system.items.map(\.title) == ["What it may do with your agents", "not see", "watch", "talk to", "start"] && system.items[3].subtitle == "Sees and writes to them.")
        sentence.levelMenu.rows[2].pick()
        #expect(model.level == .talk && model.origin == "Your choice")
        #expect(model.warning == "Reading list and Shop tests never ask: this space can make them act without you.", "\(model.warning ?? "")")
        // A folder narrows who it reaches: the warning, the line and what the page will see follow.
        #expect(sentence.scopeFolderMenu.title == "Which folder")
        #expect(sentence.scopeFolderMenu.rows.map(\.title) == ["atelier", "blog", "pacman", "portfolio", "shop", "site"].map { "~/code/" + $0 } + ["~/notes", "Choose Folder…"])
        sentence.scopeFolderMenu.rows[4].pick()
        #expect(model.choice.scope == .folders(["/Users/example/code/shop"]) && model.warning == "Shop tests never asks: this space can make it act without you.")
        #expect(model.choice.line(home: "/Users/example") == "[something] With your agents: Talk, in ~/code/shop.")
        sentence.scopeMenu.rows[0].pick()
        #expect(model.warning == "Reading list and Shop tests never ask: this space can make them act without you.")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "r1-1" + suffix, root: stage.home.root)
            let words = await Self.read(host) { $0 == Self.newSpaceWords(BlankView.chips[0].1, sentence: Self.talkWords) }
            #expect(words == Self.newSpaceWords(BlankView.chips[0].1, sentence: Self.talkWords), "\(words)")
        }
        if let gallery { try (Self.text(sentence.levelMenu) + Self.text(sentence.scopeMenu)).write(to: gallery.appendingPathComponent("r1-1-menu.txt"), atomically: true, encoding: .utf8) }
        await Self.finish(model)
    }

    /// R1.2, Run: "This space may [start] [Claude Code] in [~/code/shop]."; picking start without a folder opens the folder
    /// menu at once; the warning names the agent chosen, and the build's line and grant keep it.
    @Test("r1-2: start, its agent and folder") func r1_2() async throws {
        let stage = try Stage("build")
        defer { stage.remove() }
        let (shell, library, host) = try await Self.newSpace(stage, builder: true)
        Stage.work(library)
        shell.waiting([], mine: 0)
        let model = shell.assistant
        model.engine.update(outside: Stage.world)
        model.draft = BlankView.chips[0].1
        var shown: [WordMenu] = []
        let shows = WordSpot.present
        WordSpot.present = { menu, _ in shown.append(menu) }
        defer { WordSpot.present = shows }
        Self.sentence(model).levelMenu.rows[3].pick()
        #expect(model.choice.start == Grant.Start(kind: "claude"), "the assistant's program, until Settings gives another")
        #expect(await wait(until: { shown.count == 1 }), "the folder menu opens at once")
        #expect(shown.first?.title == "Where it starts them")
        #expect(shown.first?.rows.map(\.title).suffix(2) == ["No Folder", "Choose Folder…"] && shown.first?.rows.count == 9)
        shown.first?.rows[4].pick()
        #expect(model.warning == "Shop tests never asks: this space can make it act without you.", "start also writes to its folder's agents")
        #expect(model.choice.line(home: "/Users/example") == "[something] With your agents: Run, starts Claude Code, in ~/code/shop.")
        await wait(0.1)
        #expect(shown.count == 1, "it opens once")
        // The agent word, a plain menu until the agents' picker lands.
        let sentence = Self.sentence(model, agents: ["claude", "pi"])
        #expect(sentence.agentMenu.title == "Which agent it starts" && sentence.agentMenu.rows.map(\.title) == ["Claude Code", "pi"])
        #expect(sentence.agentMenu.rows.map(\.note) == [nil, "never asks"] && sentence.agentMenu.rows.map(\.on) == [true, false])
        sentence.agentMenu.rows[1].pick()
        #expect(model.warning == "pi and Shop tests never ask: this space can make them act without you.")
        // As the mockup draws it: a folder under this home reads ~/code/shop, and none of the Stage's agents works there.
        model.runFolder = .path(stage.home.root.appendingPathComponent("code/shop").path)
        #expect(model.warning == "pi never asks: this space can make it act without you.")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "r1-2" + suffix, root: stage.home.root)
            let words = await Self.read(host) { $0 == Self.newSpaceWords(BlankView.chips[0].1, sentence: Self.startLine) }
            #expect(words == Self.newSpaceWords(BlankView.chips[0].1, sentence: Self.startLine), "\(words)")
        }
        if let gallery { try (Self.text(sentence.agentMenu) + Self.text(sentence.folderMenu)).write(to: gallery.appendingPathComponent("r1-2-menu.txt"), atomically: true, encoding: .utf8) }
        await Self.finish(model)
    }

    /// A menu's heading and rows as text, for the gallery: no picture reaches a system menu.
    static func text(_ menu: WordMenu) -> String {
        ([menu.title.uppercased()] + menu.rows.map { "  \($0.title)\($0.on ? "  ✓" : "")" + ($0.note.map { "\n    " + $0.replacingOccurrences(of: "\n", with: "\n    ") } ?? "") })
            .joined(separator: "\n") + "\n"
    }

    /// The sentence New Space draws, for reading its menus.
    static func sentence(_ model: AssistantModel, agents: [String]? = nil) -> Sentence {
        Sentence("This space", choice: Binding(get: { model.choice }, set: { model.choice = $0 }), folders: Levels.folders(model.engine.state),
                 home: "/Users/example", warning: model.warning, agents: agents)
    }

    /// What VoiceOver's outer read gives of the sentence (its plain words are out of reach offscreen) at talk to and at
    /// start, the lock line's "?" after it where no warning stands.
    static let talkWords = ["What it may do", "Which agents it shows"]
    static var startWords: [String] { startLine + ["Who answers"] }
    static let startLine = ["What it may do", "The agent it starts", "Where it starts it"]

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
            shell.drawer.open()
            let side = await Self.read(shell.drawer.host) { $0.contains("Waiting room, building, 50 %") }
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
    static func building(_ mode: String, prefix: String? = nil) async throws -> (Stage, Shell, Library, NSView) {
        let stage = try Stage("build", prefix: prefix)
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
    /// appears and opens, and the sign's frame grows from the sign of the build's page to the center's edges; drawn at 0.6 of its time (x3-3-growing). Then it plays to its end through `Arrival.open`, as App.open
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
        // As App does, the arrival is made in the same turn: its sign is the one the build's page still shows.
        var made: String?, begun: Arrival?
        model.ended = {
            library.relist()
            made = model.appeared(library.entries)
            begun = made.flatMap { Arrival.made($0, in: shell) }
        }
        try "".write(to: stage.home.root.appendingPathComponent("out/finish"), atomically: true, encoding: .utf8)
        #expect(await wait(until: { made != nil }))
        let name = try #require(made)
        #expect(name == "waiting-room" && library.fresh == nil)
        // The build over, New Space holds the sidebar again: the app's `ended` opens the space in the same turn, this
        // test a moment later, so the sign is measured beside it.
        #expect(await wait(until: { shell.drawer.state.dock }))
        shell.window.layoutIfNeeded()
        let ask = FakeAsk()
        let room = try await stage.home.window(try #require(library.entry(name)?.space), ask)
        defer { room.close() }
        room.made = true
        let arrival = try #require(begun)
        shell.show(room)
        #expect(shell.window.title == "Waiting room")
        // What App.open does around it: the conversation follows the space shown.
        model.place = AssistantModel.place(room)
        // It starts on the page's sign of 44 points, at its top left, its arm and stroke the sign's, its eyes on.
        #expect(arrival.start.face && abs(arrival.start.arm - 44 * 0.31) < 0.01 && arrival.start.stroke == 35)
        #expect(abs(arrival.start.rect.width - 44 * 0.88) < 0.5 && arrival.start.rect.midX < arrival.room.midX, "\(arrival.start.rect)")
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
                                           folders: Levels.folders(room.engine.state), page: space.location.path, scope: .folders([]), name: "waiting-room",
                                           agents: room.engine.state.agents))
        #expect(question.folders == ["atelier", "blog", "pacman", "portfolio", "shop", "site"].map { "/Users/example/code/\($0)" } + ["/Users/example/notes"],
                "the folders the stage's agents work in")
        let (sheet, answer) = Ask.rights(question, home: stage.home.root.path)
        #expect(sheet.title == "Waiting room would like to work with your agents" && sheet.frame.width == 440 && !sheet.isAlert)
        #expect(PanelsTests.texts(sheet.contentView) == ["Waiting room would like to work with your agents", "~/something/spaces/waiting-room.html",
                                                         "Whatever an agent asks still waits for you, in a window of your Mac: Allow Once or Deny. Its memory needs no permission."])
        #expect(sheet.buttons.map(\.title) == ["Don’t Allow", "Allow"] && sheet.buttons.map(\.hint) == ["esc", nil])
        #expect(sheet.firstResponder === sheet.buttons[0] && sheet.buttons[0].keyEquivalent == "\u{1b}" && sheet.buttons[1].isEnabled)
        #expect(sheet.accessibilitySubrole() == .dialog && answer() == LevelChoice(level: .watch))
        #expect(LevelChoice.agents(question.scope, home: "/Users/example") == "only its own agents")
        // What VoiceOver reads (the level's sentence, a plain text of SwiftUI, is out of reach offscreen).
        let said = ["Two people", "Waiting room would like to work with your agents", "~/something/spaces/waiting-room.html", "What it may do", "Which agents it shows"]
            + [Levels.sheetFine, "Don’t Allow", "Allow"]
        let words = await Self.read(try #require(sheet.contentView)) { $0 == said }
        #expect(words == said, "\(words)")
        // Under the toolbar, centred over the space beside the sidebar.
        let hang = shell.window(shell.window, willPositionSheet: sheet, using: .zero)
        #expect(hang.minY == shell.window.contentLayoutRect.maxY && hang.minX == (shell.drawer.state.dock ? Drawer.column : 0))
        try await stage.appearances { suffix in
            try await Picture.sheet(sheet, over: shell, library: library, web: nil, "d4" + suffix, root: stage.home.root)
        }
        var run = question
        run.level = .run
        let (runSheet, runAnswer) = Ask.rights(run, home: stage.home.root.path)
        #expect(!runSheet.buttons[1].isEnabled && runAnswer() == LevelChoice(level: .run))
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
    /// agree, for a view with no live clock), or after `patience`. A SwiftUI view offscreen gives only the description of
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
            // it: read again until they hold still and say what is awaited. The limit only stops a hang.
            _ = view.accessibilityChildren()
            let end = Date() + patience
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
        #expect(gallery.cards(library.templates).map(\.title) == ["One Line", "Decision Deck", "Council", "Living Answers", "Consent Ledger", "Prompt Town"])
        #expect(library.templates.map(\.needs) == ["Sees, writes to and starts agents", "Sees, writes to and starts agents",
                                                   "Sees, writes to and starts agents\u{00A0}· Remembers", "Sees, writes to and starts agents\u{00A0}· Remembers",
                                                   "Sees your agents\u{00A0}· Remembers", "Sees, writes to and starts agents\u{00A0}· Remembers"])
        gallery.hovered = "deck"
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d5" + suffix, root: stage.home.root)
            // VoiceOver reads the heading, the filters and one element per card, named by its template.
            let cards = ["Templates", "Show", "One Line", "Decision Deck", "Council", "Living Answers", "Consent Ledger", "Prompt Town"]
            #expect(await Self.read(host) { $0 == cards } == cards)
        }
        gallery.shown = .agents
        #expect(gallery.cards(library.templates).map(\.id) == ["one-line", "deck", "council"])
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
        let deck = try #require(library.templates.first { $0.id == "deck" })
        gallery.preview(deck)
        #expect(shell.window.title == "Decision Deck" && shell.window.subtitle == "Template preview")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d6" + suffix, root: stage.home.root)
            // The bar, then the picture; the cards are gone.
            let bar = ["Template preview", "A picture of Decision Deck"]
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
        #expect(ladder.steps[1].lines.last == .init(text: "Waits for your answer", mark: .waits))
        #expect(ladder.steps.map(\.mark) == [.done, .waits, .later] && ladder.eyes == .wait)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d7" + suffix, root: stage.home.root)
            let words = await Self.read(host)
            #expect(words.contains("One card per agent, Big and easy to scan., 1") && words.contains("A single list, oldest first, Compact., 2")
                    && words.contains("Write, waits for you, Waits for your answer"), "\(words)")
        }
        #expect(await wait { model.arming(now: model.clock()) >= 1 })
        model.answer(1)
        #expect(await wait(until: { model.asked == nil && model.ladder?.steps[1].mark == .now }))
        #expect(model.ladder?.steps[0].lines.last?.text == "A single list, oldest first. Writing it now.")
        await Self.finish(model)
    }

    /// The check step after a failed check: two edits fix it, the second check passes, and every step says its time.
    @Test("d8: the check step") func d8() async throws {
        let (stage, shell, library, host) = try await Self.building("fail")
        defer { stage.remove() }
        let model = shell.assistant
        #expect(await wait(until: { model.ladder?.steps[2].lines.last?.text == "Found problems · Fixing them…" || model.ladder?.steps[2].mark == .done }))
        #expect(await wait(until: { model.ladder?.steps[2].mark == .done }))
        let ladder = try #require(model.ladder)
        #expect(ladder.done && ladder.steps[2].lines.last?.text == "Passed after 2 fixes")
        #expect(ladder.steps.allSatisfy { Ladder.took($0, now: model.clock()) != nil })
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d8" + suffix, root: stage.home.root)
            let words = await Self.read(host)
            #expect(words.contains("Stop") && words.contains("Checked · \(model.whoBuilds)") && words.contains { $0.hasPrefix("Check, done, Passed after 2 fixes, ") }, "\(words)")
        }
        await Self.finish(model)
    }

    // MARK: Round 4, the final mockup

    /// F1.1, the first beat: 980 by 640 alone, the words at the left, the schema *A space* on its paper, finished at
    /// t = ∞ as Reduced motion draws it, the small map, the footer with no Back. ← stays here, → and ← walk the beats.
    @Test("f1-1: Beat 1, alone on the desktop, 980 × 640, footer \"1 of 5\", Skip") func f1_1() async throws {
        let scene = try await Self.welcome()
        defer { scene.remove() }
        #expect(scene.window.title == "Welcome to something" && Welcome.base == NSSize(width: 980, height: 640) && scene.window.contentView?.frame.size == Welcome.size)
        #expect(scene.assistant.kind == "claude" && scene.model.beat == .page && WelcomeModel.Beat.allCases.count == 5)
        try await scene.draw("f1-1") { words in
            #expect(words == Self.beatWords(.page), "\(words)")
        }
        WelcomeTests.press(scene.window, .left)
        #expect(scene.model.beat == .page)
        WelcomeTests.press(scene.window, .right)
        #expect(scene.model.beat == .agent && scene.model.forward)
        WelcomeTests.press(scene.window, .left)
        #expect(scene.model.beat == .page && !scene.model.forward)
        // Each beat's lens stands inside the Hero, and the schema's first moment is a blank page.
        for beat in WelcomeModel.Beat.allCases { #expect(beat.lit?.allSatisfy { CGRect(origin: .zero, size: Hero.size).contains(Hero.place($0)) } ?? true) }
        #expect(WelcomeModel.Beat.whole.lit == nil && WelcomeModel.Beat.roles.lit == [.assistant, .agents])
        #expect(Schemas.ease(0, 0.8, 0.9) == 0 && Schemas.ease(.infinity, 3, 0.8) == 1 && Schemas.ease(3.4, 3, 0.8) > 0.5)
    }

    /// F1.2, the second beat: the programs found, all six, the first looked at. A tile redraws the schema: its program,
    /// its path, its home folder. The conversations are not counted: the drawing says they stay with the program.
    @Test("f1-2: Beat 2: a tile redraws the schema, the tag In iTerm") func f1_2() async throws {
        let scene = try await Self.welcome()
        defer { scene.remove() }
        scene.model.locate = { .success("/Users/example/bin/\($0)") }
        await scene.model.find(["claude", "codex"])
        #expect(scene.model.paths.count == 2)
        scene.model.go(1)
        #expect(scene.assistant.entries.count == 6 && Registry.app.agent("codex")?.home == "~/.codex")
        func label(_ name: String, _ home: String, _ kind: String) -> String {
            "An agent is one conversation, here in iTerm, with \(name): the program at /Users/example/bin/\(kind), its home folder \(home), your project folders. something sees them all and changes nothing."
        }
        let tiles = ["Programs on this Mac   6"] + Registry.app.builders.map(\.name)
        try await scene.draw("f1-2") { words in
            #expect(words == Self.beatWords(.agent, schema: tiles + [label("Claude Code", "~/.claude", "claude"), "Antigravity, Cursor: something sees them, and can’t start them."], back: true), "\(words)")
        }
        // Tab reaches the programs, ← → walk them round and the schema follows; Return still goes on.
        WelcomeTests.press(scene.window, .tab)
        WelcomeTests.press(scene.window, .right)
        #expect(scene.model.beat == .agent && scene.model.look == "codex")
        let words = await Self.read(try #require(scene.window.contentView?.subviews.first), whole: true)
        #expect(words.contains(label("Codex", "~/.codex", "codex")), "\(words)")
        for _ in 0..<2 { WelcomeTests.press(scene.window, .left) }
        #expect(scene.model.look == "amp")
        WelcomeTests.press(scene.window, .return)
        #expect(scene.model.beat == .roles && !scene.model.walking)
    }

    /// F1.3, the third beat: both roles joined by ≠, the assistant's chips (today's chip until the three land), the line
    /// about folders.
    @Test("f1-3: Beat 3: ≠, three chips, no Full Access rung here") func f1_3() async throws {
        let scene = try await Self.welcome()
        defer { scene.remove() }
        for _ in 0..<2 { scene.model.go(1) }
        try await scene.draw("f1-3") { words in
            #expect(words == Self.beatWords(.roles, schema: Self.rolesWords + AgentChips.labels(scene.assistant).prefix(2) + ["Your assistant’s folder gives a space nothing."], back: true), "\(words)")
        }
    }

    static let rolesWords = ["Your assistant, An agent with a job: it builds a space. Each space has its own., Works in this folder, May change your spaces and run something’s own commands, Anything else asks you",
                             "is not the same as", "Agents a space shows, They live on your Mac. A space only shows them., Work in your project folders, This space may watch these agents. You choose, for each space, They keep their own settings", "Your assistant"]

    /// F1.4, the fourth beat: one image for VoiceOver, the same map as Settings, the programs that never ask named.
    @Test("f1-4: Beat 4: Settings' map, the real window, the two powers") func f1_4() async throws {
        let scene = try await Self.welcome()
        defer { scene.remove() }
        for _ in 0..<3 { scene.model.go(1) }
        #expect(Schemas.neverAsk == ["pi", "OMP", "Amp"] && WelcomeModel.Beat.answer.sentence.contains("except pi, OMP and Amp, which never ask"))
        try await scene.draw("f1-4") { words in
            #expect(words == Self.beatWords(.answer, schema: [AnswerSchema.label], back: true), "\(words)")
        }
    }

    /// F1.5, the last beat: the title above the whole Hero, which now speaks, Back, the sentence that nothing starts, and
    /// the two doors. → stays here.
    @Test("f1-5: Beat 5: \"Ready to build something today?\", the whole Hero, two doors") func f1_5() async throws {
        let scene = try await Self.welcome()
        defer { scene.remove() }
        for _ in 0..<4 { WelcomeTests.press(scene.window, .right) }
        #expect(scene.model.beat == .whole)
        WelcomeTests.press(scene.window, .right)
        #expect(scene.model.beat == .whole && scene.shell.welcoming != nil)
        #expect(WelcomeModel.Beat.whole.title == "Ready to build something today?")
        try await scene.draw("f1-5") { words in
            #expect(words == Self.beatWords(.whole, schema: [Hero.label], back: true, right: ["No agent starts, nothing is spent.", "Open an Example", "Make My First Space"]), "\(words)")
        }
    }

    /// F1.6, the window's first arrival: Return through the beats ends the welcome, kept as seen, on New Space, its field
    /// asked for the keys, the builder chosen. The space it builds then arrives alone in the sidebar, opened, with nothing
    /// to allow.
    @Test("f1-6: Make My First Space: the window arrives on New Space") func f1_6() async throws {
        let scene = try await Self.welcome()
        defer { scene.remove() }
        let (shell, library, model) = (scene.shell, scene.library, scene.assistant)
        scene.model.finished = { shell.welcomed($0) }
        model.choose("codex")
        model.open = false
        for _ in 0..<4 { WelcomeTests.press(scene.window, .return) }
        #expect(shell.welcoming != nil && scene.model.beat == .whole)
        WelcomeTests.press(scene.window, .return)
        #expect(shell.welcoming == nil && library.preferences.toured && library.selection == .newSpace && model.newKind == "codex")
        #expect(model.open, "its field is asked for the keys")
        try await scene.stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "f1-6" + suffix, root: scene.stage.home.root)
        }
        let room = try await Self.first(scene)
        defer { room.close() }
        #expect(shell.window.title == "Waiting room" && room.web.url != nil && shell.window.attachedSheet == nil)
        #expect(library.order().map(\.title) == ["Waiting room"])
        await Self.built(model, sticker: shell.glass.sticker)
    }
    @Test("f1-7: Five bubbles, once each, no counter", .disabled("not built yet: S9")) func f1_7() async throws {}
    @Test("f1-8: Open an Example: My agents, nothing started, no sheet", .disabled("not built yet: S9")) func f1_8() async throws {}
    /// F1.9, no program: beat 2 says so with Look Again and the install commands, in dashes; beat 3 says "an agent you
    /// install"; beat 5 keeps the example and offers Look Again.
    @Test("f1-9: No program found: beats 2, 3 and 5, Look Again") func f1_9() async throws {
        let stage = try Stage("build")
        let (home, model) = try AssistantTests().assistant([], prefix: "something-accept-build-")
        defer { stage.remove(); home.remove() }
        let welcome = WelcomeModel(places: home.places)
        welcome.go(1)
        let window = Welcome.window(welcome, assistant: model, motion: .reduced)
        defer { window.close() }
        // While the look runs nothing says there is no program.
        let looking = await Self.read(try #require(window.contentView?.subviews.first), whole: true)
        #expect(looking.contains("Looking for programs on this Mac…") && !looking.contains("No program yet. something sees them all and changes nothing."), "\(looking)")
        model.engine.lookAgain()
        #expect(await wait(until: { model.noAgent }))
        try await stage.appearances { suffix in
            try await Picture.alone(window, "f1-9" + suffix, root: home.root)
            let words = await Self.read(try #require(window.contentView?.subviews.first), whole: true)
            for line in ["No coding program found on this Mac yet", "Look Again", "No program yet. something sees them all and changes nothing.",
                         "Install one in Terminal, with your own account. something never installs one for you."] { #expect(words.contains(line), "\(line) in \(words)") }
        }
        welcome.go(1)
        var words = await Self.read(try #require(window.contentView?.subviews.first), whole: true)
        #expect(words.contains { $0.contains("An agent you install, with a job: it builds a space. Each space has its own.") }, "\(words)")
        for _ in 0..<2 { welcome.go(1) }
        words = await Self.read(try #require(window.contentView?.subviews.first), whole: true)
        #expect(words.suffix(3) == ["No agent starts, nothing is spent.", "Open an Example", "Look Again"], "\(words)")
    }
    @Test("f1-10: Help › How something Works: four schemas, one button each", .disabled("not built yet: S9")) func f1_10() async throws {}
    @Test("r2-1: Up to three questions, one agent turn", .disabled("not built yet: C7")) func r2_1() async throws {}
    @Test("r2-2: Build Now skips them", .disabled("not built yet: C7")) func r2_2() async throws {}
    @Test("r3-1: The summary, one row for the sentence", .disabled("not built yet: C7")) func r3_1() async throws {}
    @Test("r3-2: Two columns, the page as it is written", .disabled("not built yet: C3")) func r3_2() async throws {}
    @Test("r3-3: A build finished elsewhere", .disabled("not built yet: C4")) func r3_3() async throws {}
    @Test("r3-4: A failed build keeps its place, Try Again", .disabled("not built yet: C4")) func r3_4() async throws {}
    @Test("f2-1: Problems said in clear", .disabled("not built yet: C5")) func f2_1() async throws {}
    @Test("f2-1b: One problem left", .disabled("not built yet: C5")) func f2_1b() async throws {}
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
