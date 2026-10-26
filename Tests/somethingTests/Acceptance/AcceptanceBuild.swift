// Acceptance scenarios of the first start and making a space: the welcome and the film (a1–a8), New Space, the build
// ladder, the arrival, templates and the rights sheet (d1–d8). The welcome is drawn over a stated reconstruction of
// the main window dimmed behind it, as the window server would compose them.
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
    /// The first-launch film at its hold point, on a first start: the sign's frame grown to the window's edges, 12
    /// points in, its eyes gone, the paper faded onto New Space, whose own sign landed; an empty sidebar.
    @Test("a1: the film on the glass") func a1() async throws {
        let stage = try Stage("build")
        defer { stage.remove() }
        for file in try FileManager.default.contentsOfDirectory(at: stage.home.places.spaces, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: file)
        }
        let (shell, library, host) = try await Self.newSpace(stage, builder: true)
        shell.waiting(0, mine: 0)
        library.relist()
        #expect(App.welcomes(library) && library.entries.allSatisfy { !$0.isSpace })
        #expect(await wait(until: { Arrival.sign(in: shell.center) != nil }), "New Space's sign, under the film")
        let film = Film(over: shell, motion: .calm)
        #expect(film.cover.frame == shell.window.frame && shell.film === film)
        film.layoutSubtreeIfNeeded()
        film.hold()
        let frame = try #require(film.grown), shape = frame.shape
        #expect(shape.rect == film.bounds.insetBy(dx: 12, dy: 12) && shape.eyes == 0 && shape.stroke == Arrival.thin, "\(shape)")
        #expect(abs(shape.arm - 84 * 0.31) < 0.01 && film.paper.alphaValue == 0 && film.sign.isHidden)
        #expect(Arrival.sign(in: shell.center)?.isHidden == false)
        try await stage.appearances { suffix in
            // The mockup has no night of this screen.
            if suffix.isEmpty { try await Picture.window(shell, library: library, web: nil, "a1", root: stage.home.root) }
            let shown = Self.newSpaceWords + ["My agents", "Project watch", "Daily brief"], words = await Self.read(host) { $0 == shown }
            #expect(words == shown, "\(words)")
        }
        film.leave()
        #expect(shell.film == nil && film.superview == nil)
    }
    /// The welcome's first step over the main window of a first start, dimmed: the sign, "something", the one sentence,
    /// 1 of 5, Skip Tour and Continue; Return goes on to the builders (Escape is TourTests').
    @Test("a2: welcome, step 1") func a2() async throws {
        let scene = try await Self.welcome(.welcome)
        defer { scene.remove() }
        #expect(scene.window.title == "Welcome to something" && scene.window.contentView?.frame.size == Welcome.size)
        try await scene.draw("a2") { words in
            #expect(words == ["something. Ready to build something today?", "Skip Tour", "Continue"], "\(words)")
        }
        TourTests.press(scene.window, .return)
        #expect(scene.tour.step == .assistant)
    }

    /// Choose your assistant: the six builders found in two columns, each with its model, Claude Code chosen, the two seen
    /// only and why, and ↑ ↓ Choose with Back.
    @Test("a3: welcome, the builders") func a3() async throws {
        let scene = try await Self.welcome(.assistant)
        defer { scene.remove() }
        #expect(scene.assistant.entries.filter(\.enabled).map(\.id) == ["claude", "codex", "opencode", "pi", "omp", "amp"])
        // Chosen is the radio's selected trait, which an offscreen SwiftUI view does not give (only descriptions): the
        // model's choice is read.
        #expect(scene.assistant.entries.filter(\.checked).map(\.id) == ["claude"])
        // A kind that picks its own model says so; the others, never run here, have their default.
        let rows = ["Claude Code", "Codex", "OpenCode", "pi", "OMP", "Amp"].map { name in
            let kind = Registry.app.agents.first { $0.name == name }?.kind ?? ""
            return "\(name), \(Registry.app.limits[kind]?.contains("model") == true ? "Its own model" : "Default model")"
        }
        #expect(rows.filter { $0.hasSuffix("Its own model") }.count >= 1)
        let why = Registry.app.agents.filter { $0.builder == nil }.compactMap(\.unavailable)
        let seen = "Seen only: Antigravity and Cursor. Antigravity needs its own Google sign-in, and Cursor would ask you before every small step "
            + "of a build, so something shows them but doesn't build with them."
        try await scene.draw("a3") { words in
            #expect(why.count == 2 && words == ["Choose your assistant"] + rows + [seen, "Skip Tour", "Choose", "Back", "Continue"], "\(words)")
        }
    }

    /// A few comforts, under a Homebrew prefix: the launcher and the notifications, both off, the cursor on the first.
    @Test("a4: welcome, launcher and notices") func a4() async throws {
        let scene = try await Self.welcome(.comforts, homebrew: true)
        defer { scene.remove() }
        #expect(scene.tour.comforts == [.launcher, .notify] && !scene.tour.addLauncher && !scene.tour.notify && scene.tour.cursor == 0)
        try await scene.draw("a4") { words in
            #expect(words.contains("Add something to Applications") && words.contains("Tell me when an agent waits for me"), "\(words)")
            #expect(words.suffix(3) == ["Turn On or Off", "Back", "Continue"], "\(words)")
        }
    }

    /// Meet your assistant: the sticker, who it is, ⌘ and K.
    @Test("a5: welcome, the sticker and its keys") func a5() async throws {
        let scene = try await Self.welcome(.meet)
        defer { scene.remove() }
        try await scene.draw("a5") { words in
            #expect(words == ["Ready", "Meet your assistant", "Press ⌘K to talk to it", "Skip Tour", "Back", "Continue"], "\(words)")
        }
    }

    /// Ready: who builds, the comforts as chosen, the promise about requests, and Make Your First Space; no Skip Tour.
    /// Not under a Homebrew prefix, no Applications row: the launcher was never offered.
    @Test("a6: welcome, the summary") func a6() async throws {
        let promise = "Requests: When an agent asks for something, a small window of your Mac asks you. Only you answer."
        let scene = try await Self.welcome(.ready, homebrew: true)
        defer { scene.remove() }
        try await scene.draw("a6") { words in
            #expect(words == ["Make your first space", "Assistant: Claude Code · Default model", "Applications: Not added", "Notifications: Off",
                              promise, "Back", "Make Your First Space"], "\(words)")
        }
        let elsewhere = try await Self.welcome(.ready)
        defer { elsewhere.remove() }
        let words = await Self.read(try #require(elsewhere.window.contentView?.subviews.first))
        #expect(!words.contains { $0.hasPrefix("Applications") } && words.contains("Notifications: Off") && words.contains(promise), "\(words)")
    }

    /// No builder on this Mac: the install commands of the first two, each read with its agent's name, Copy Command, What is a coding agent?, Look Again.
    @Test("a7: welcome with no builder") func a7() async throws {
        let scene = try await Self.welcome(.assistant, programs: [])
        defer { scene.remove() }
        #expect(scene.tour.screen(scene.assistant) == .none && !scene.tour.searching(scene.assistant))
        try await scene.draw("a7") { words in
            #expect(words.contains("No coding agent found") && words.contains("What is a coding agent?") && words.suffix(2) == ["Back", "Look Again"], "\(words)")
            #expect(words.filter { $0.hasPrefix("Copy the command that installs") }.count == 2, "\(words)")
            #expect(words.contains("Claude Code: brew install --cask claude-code") && words.contains("Codex: brew install --cask codex"), "\(words)")
        }
        var copied: [String] = []
        scene.assistant.copy = { copied.append($0) }
        scene.tour.copy(InstallList.builders[0].command, with: scene.assistant.copy)
        #expect(copied == [InstallList.builders[0].command] && scene.tour.copied == copied.first)
    }

    /// After ⌘K at the fourth step: the eyes smile and the assistant says hello in its own voice.
    @Test("a8: welcome after the first hello") func a8() async throws {
        let scene = try await Self.welcome(.meet)
        defer { scene.remove() }
        #expect(TourTests.command(scene.window, "k") && scene.tour.met)
        try await scene.draw("a8") { words in
            // Its eyes, beside its name, smile; the state they say is still Ready, never Done: nothing ran.
            #expect(words == ["Ready, smiling", "Meet your assistant", "Skip Tour", "Back", "Continue"], "\(words)")
        }
        #expect(scene.assistant.engine.state.agents.isEmpty && scene.assistant.id == nil, "hello sends nothing to the agent")
    }

    /// A first start for the welcome: a home with no space, `programs` on its PATH (every agent's by default), the main
    /// window on New Space, and the welcome window at `step`; under a Homebrew prefix with `homebrew`.
    /// The welcome by keys alone, as the window server sends them: Return goes on, → chooses another builder, Space
    /// turns a comfort on, ⌘[ goes back, ⌘K says hello, and Return at Ready ends the tour with the choices; Escape, at
    /// any step, skips it.
    @Test("Keys only: the welcome") func keysOnly() async throws {
        let scene = try await Self.welcome(.welcome, homebrew: true)
        defer { scene.remove() }
        let window = scene.window, tour = scene.tour
        var ended: [(String?, Bool)] = []
        tour.finished = { ended.append(($0, $1)) }
        func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = []) throws {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                                                      context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
            if !flags.contains(.command) || !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
        }
        #expect(window.firstResponder is WelcomeKeys)
        try key(36, "\r")
        #expect(tour.step == .assistant && scene.assistant.entries.filter(\.checked).map(\.id) == ["claude"])
        try key(124, "\u{f703}", [.numericPad, .function])
        #expect(scene.assistant.entries.filter(\.checked).map(\.id) == ["codex"], "→ chooses the next builder")
        try key(36, "\r")
        #expect(tour.step == .comforts && tour.cursor == 0 && !tour.addLauncher)
        try key(49, " ")
        #expect(tour.addLauncher, "Space turns the comfort under the cursor on")
        try key(33, "[", .command)
        #expect(tour.step == .assistant, "⌘[ goes back")
        try key(36, "\r")
        try key(36, "\r")
        #expect(tour.step == .meet && !tour.met)
        try key(40, "k", .command)
        #expect(tour.met, "⌘K says hello")
        try key(36, "\r")
        #expect(tour.step == .ready && ended.isEmpty)
        try key(36, "\r")
        #expect(ended.count == 1 && ended.first?.1 == false, "Return at Ready ends the tour, its choices applied")

        let other = try await Self.welcome(.comforts)
        defer { other.remove() }
        var skipped = false
        other.tour.finished = { skipped = $1 }
        other.window.sendEvent(try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: other.window.windowNumber,
                                                             context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)))
        #expect(skipped, "Escape skips the tour")
    }

    @MainActor struct WelcomeScene {
        let stage: Stage, shell: Shell, library: Library, tour: Tour, window: NSWindow
        var assistant: AssistantModel { shell.assistant }

        func remove() {
            window.close()
            stage.remove()
        }

        /// Asserts what VoiceOver reads of the welcome with `words`, and draws `name` over the dimmed main window.
        func draw(_ name: String, _ words: ([String]) -> Void) async throws {
            try await stage.appearances { suffix in
                try await Picture.welcome(window, over: shell, library: library, name + suffix, root: stage.home.root)
                let host = try #require(window.contentView?.subviews.first)
                words(await AcceptanceBuild.read(host))
            }
        }
    }

    static func welcome(_ step: Tour.Step, programs: [String] = Registry.app.agents.map(\.kind), homebrew: Bool = false) async throws -> WelcomeScene {
        let stage = try Stage("build")
        for file in try FileManager.default.contentsOfDirectory(at: stage.home.places.spaces, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: file)
        }
        let bin = stage.home.root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        for kind in programs { try AssistantTests().install(kind, in: bin) }
        let (shell, library, _) = stage.window()
        try stage.moment(shell)
        let model = shell.assistant
        model.engine.changed = { model.refresh() }
        model.engine.lookAgain()
        #expect(await wait(until: { programs.isEmpty ? model.noAgent : model.kind == "claude" }))
        library.select(.newSpace)
        shell.show(nil)
        let app = homebrew ? stage.home.root.appendingPathComponent("brew/Cellar/something/0.3.0/something.app") : URL(fileURLWithPath: "/Users/example/Applications/something.app")
        let tour = Tour(places: stage.home.places, app: app)
        tour.move(step)
        return WelcomeScene(stage: stage, shell: shell, library: library, tour: tour, window: Welcome.window(tour, assistant: model, motion: .reduced))
    }

    /// New Space with Claude Code as its builder: the sign, the question, the field with Build greyed until something
    /// is written, Built by and the model, the three suggestions, the first three templates and See All; the assistant
    /// away. d1-smallest in the smallest window; d1-no-agent: the notice in the field's place, no suggestion.
    @Test("d1: New Space") func d1() async throws {
        let stage = try Stage("build")
        defer { stage.remove() }
        let (shell, library, host) = try await Self.newSpace(stage, builder: true)
        let model = shell.assistant
        #expect(shell.window.title == "New Space" && shell.window.subtitle == "" && shell.glass.isHidden && !model.cardShown)
        #expect(model.kind == "claude" && model.draft.isEmpty && !model.canSend)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d1" + suffix, root: stage.home.root)
            let shown = Self.newSpaceWords + ["My agents", "Project watch", "Daily brief"], words = await Self.read(host) { $0 == shown }
            #expect(words == shown, "\(words)")
        }
        // Build is greyed while the field is empty or blank, and only then. (An offscreen SwiftUI view gives VoiceOver only
        // its descriptions: neither a control's enabled state nor its press can be reached here, so the model's are read.)
        model.draft = "  \n "
        #expect(!model.canSend)
        model.draft = "A page of my agents."
        #expect(model.canSend)
        model.draft = ""

        shell.window.setContentSize(NSSize(width: 640, height: 480))
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d1-smallest" + suffix, root: stage.home.root)
        }
        // Each suggestion sends its whole sentence, the draft kept, and so does Return in the field (the draft sent); an
        // input method's Return builds nothing. The fake answers the first two and the field in words: each build ends
        // without a new space, and its reply stays on the page above the field, to be answered there, since the
        // assistant's card stays away. (A plain text is out of reach offscreen: the page's own choice is read, and
        // d1-answer shows it.)
        shell.window.setContentSize(Stage.Size.main)
        let since = try #require((host as? NSHostingView<BlankView>)?.rootView.since)
        model.draft = "Half written"
        for chip in BlankView.chips.prefix(2) {
            model.send(chip.1)
            #expect(model.building && model.draft == "Half written")
            #expect(await wait(until: { !model.building && model.rows.suffix(2) == [.mine(caption: "on the blank page", text: chip.1), .reply("Invented reply.")] }))
            #expect(BlankView.reply(in: model, since: since) == "Invented reply.")
        }
        #expect(Field.returned(shift: false, marked: true, model) == .ignored && !model.building && model.draft == "Half written")
        model.draft = "A page for my mornings."
        #expect(Field.returned(shift: false, marked: false, model) == .handled && model.building && model.draft.isEmpty)
        #expect(await wait(until: { !model.building && model.rows.suffix(2) == [.mine(caption: "on the blank page", text: "A page for my mornings."), .reply("Invented reply.")] }))
        #expect(BlankView.reply(in: model, since: since) == "Invented reply." && !model.blocked)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d1-answer" + suffix, root: stage.home.root)
            let answered = await Self.read(host) { $0.contains("Who is waiting for me") }
            #expect(shell.glass.isHidden && answered.contains("Who is waiting for me"), "\(answered)")
        }
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
        // The game: the build starts (the fake keeps working on it), the field holds the sentence read only, the
        // suggestions and templates step aside, Stop is offered, the assistant stays away.
        model.draft = "Half written"
        model.send(BlankView.chips[2].1)
        #expect(model.building && model.draft == "Half written")
        #expect(await wait(until: { model.rows.contains(.mine(caption: "on the blank page", text: BlankView.chips[2].1)) && model.light == .working }))
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d1-building" + suffix, root: stage.home.root)
            let building = await Self.read(fresh)
            #expect(shell.glass.isHidden && !building.contains("Build") && !building.contains("Who is waiting for me") && building.contains("Stop"), "\(building)")
        }
        var stopped = false
        model.engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })

        let none = try Stage("build")
        defer { none.remove() }
        let (bare, alone, page) = try await Self.newSpace(none, builder: false)
        #expect(bare.assistant.noAgent && bare.assistant.notice?.title == "No coding agent found.")
        try await none.appearances { suffix in
            try await Picture.window(bare, library: alone, web: nil, "d1-no-agent" + suffix, root: none.home.root)
            let words = await Self.read(page)
            #expect(!words.contains("Build") && !words.contains("Who is waiting for me") && words.contains("How to Get One"), "\(words)")
        }
    }

    /// What VoiceOver reads of New Space before the templates' cards, as far as an offscreen SwiftUI view gives it (its
    /// field, menus and the sign are out of reach here).
    static let newSpaceWords = ["What do you want to make?", "Build", "Who is waiting for me", "A morning brief of my agents", "A small game for my breaks", "Or start from a template",
                                "See All Templates"]

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
        shell.waiting(1, mine: 0)
        let host = try #require(shell.center.subviews.first { $0 is NSHostingView<BlankView> })
        return (shell, library, host)
    }

    /// The build ladder: the sentence held read only in the field, the agent's words in its voice, Plan done with its
    /// time, Write writing waiting-room.html with its time running, Check to come, where it is built and Stop; Built by
    /// keeps its place unseen and the suggestions and templates step aside. d2-stopped: after Stop.
    @Test("d2: the build ladder") func d2() async throws {
        let (stage, shell, library, host) = try await Self.building("")
        defer { stage.remove() }
        let model = shell.assistant
        #expect(await wait(until: { model.ladder?.steps[1].mark == .now }))
        let ladder = try #require(model.ladder)
        #expect(ladder.steps.map(\.name) == ["Plan", "Write", "Check"] && ladder.steps.map(\.mark) == [.done, .now, .later])
        #expect(ladder.steps[1].file == "waiting-room.html" && ladder.steps[2].note == "Opens it, reads it, looks for errors" && ladder.eyes == .think)
        #expect(ladder.say == "I’ll make “Waiting room”: one card per agent that waits for you, oldest first.")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d2" + suffix, root: stage.home.root)
            let says = { (words: [String]) in
                words.contains("Your assistant: \(ladder.say ?? "")") && words.contains("Stop") && !words.contains("Build")
                    && !words.contains("Who is waiting for me") && words.contains { $0.hasPrefix("Write, now, waiting-room.html, ") }
                    && words.contains("Check, to come, Opens it, reads it, looks for errors")
            }
            let words = await Self.read(host, until: says)
            #expect(says(words), "\(words)")
        }
        // d2-stopped: Stop mid-Write leaves the ladder saying what stays on disk, the sentence back in the field.
        model.stop()
        #expect(!model.building && model.draft == "Who is waiting for me" && model.ladder?.steps.map(\.mark) == [.done, .off, .off])
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d2-stopped" + suffix, root: stage.home.root)
            let says = { (words: [String]) in
                words.contains("Your assistant: Stopped. waiting-room.html stays in your spaces folder, unchecked.") && words.contains("Build Again")
                    && !words.contains("Stop")
            }
            let words = await Self.read(host, until: says)
            #expect(says(words), "\(words)")
        }
        await Self.finish(model)
    }

    /// A build that runs, in "Who is waiting for me" sent from New Space, the fake claude in `mode` (see AssistantTests).
    static func building(_ mode: String) async throws -> (Stage, Shell, Library, NSView) {
        let stage = try Stage("build")
        let out = stage.home.root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try mode.write(to: out.appendingPathComponent("ladder"), atomically: true, encoding: .utf8)
        let (shell, library, host) = try await newSpace(stage, builder: true)
        shell.assistant.send("Who is waiting for me")
        return (stage, shell, library, host)
    }

    static func finish(_ model: AssistantModel) async {
        var stopped = false
        model.engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })
    }
    /// The arrival after a build from New Space: the page written and the turn ended, the space appears and opens, and
    /// the sign's frame grows from New Space's sign to the center's edges over a still of the page left; drawn at 0.6
    /// of its time (d3-growing). Then it plays to its end through `Arrival.open`, as App.open calls it: the page is not loaded and
    /// no rights are asked while it plays; once it is gone the page loads and asks its rights (d3). A space no longer shown
    /// when its arrival ends is not opened, and a new opening ends an arrival still playing.
    @Test("d3: the arrival") func d3() async throws {
        let (stage, shell, library, _) = try await Self.building("fail")
        defer { stage.remove() }
        let model = shell.assistant
        #expect(await wait(until: { model.ladder?.done == true }))
        // The page the fake says it wrote, then the end of its turn: the app's `ended` lists the spaces and opens the new one.
        try stage.home.space("waiting-room", Self.waitingRoom)
        var made: String?
        model.ended = {
            library.relist()
            made = model.appeared(library.entries, open: nil)
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
        // It starts on the sign of 76 points, its arm and stroke the sign's, its eyes on.
        #expect(arrival.start.face && abs(arrival.start.arm - 76 * 0.31) < 0.01 && arrival.start.stroke == 35)
        #expect(abs(arrival.start.rect.width - 76 * 0.88) < 0.5 && abs(arrival.start.rect.midX - arrival.room.midX) < 1, "\(arrival.start.rect)")
        arrival.progress = 0.6
        let shape = arrival.shape
        #expect(shape.rect.width > arrival.start.rect.width && shape.rect.width < arrival.room.width - 28 && shape.eyes == 0)
        library.select(.space(name))
        try await stage.appearances { suffix in
            // One picture: the still keeps the day it was taken in (the mockup has no night of this screen).
            if suffix.isEmpty { try await Picture.window(shell, library: library, web: room.web, "d3-growing", root: stage.home.root) }
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
        // Once it is gone: the page loads and asks for its rights.
        #expect(await wait(until: { room.web.url != nil && !ask.questions.isEmpty }), "\(String(describing: room.web.url))")
        #expect(ask.questions.first?.rights == ["state", "store"])
        // The mockup's d3 is the end of it: the space arrived, its row selected and fresh.
        #expect(library.fresh == name && library.selection == .space(name))
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: room.web, "d3" + suffix, root: stage.home.root)
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
    /// The rights sheet over the space just made: "Waiting room would like to", where its page is, one row per right
    /// with its switch off, the fine print, Don't Allow holding the focus and Allow greyed until a switch is on.
    @Test("d4: the rights sheet") func d4() async throws {
        let stage = try Stage("build")
        defer { stage.remove() }
        let space = try stage.home.space("waiting-room", Self.waitingRoom)
        let (shell, library, _) = stage.window()
        let room = try await stage.open("waiting-room", in: shell, library)
        defer { room.close() }
        try stage.moment(shell)
        shell.waiting(1, mine: 0)
        // The build's conversation, handed to the space it made (AssistantModel.hand): its agent alive and listening, the
        // row's eyes awake until the Preferences' delay.
        var builder = Agent(id: "a1", kind: "claude", origin: "launched")
        (builder.state, builder.alive) = ("idle", true)
        let handed = shell.assistant.session(for: shell.assistant.place)
        handed.id = builder.id
        handed.read(SomethingCore.State(at: iso8601.string(from: Stage.now), kinds: [:], agents: [builder]))
        #expect(shell.assistant.eyes(of: "waiting-room") == .listen)
        let question = RightsQuestion(space: "Waiting room", description: nil, rights: ["state", "store"], scope: nil, missing: [],
                                      folder: nil, made: true, page: space.location.path, declared: ["state", "store"])
        let sheet = Ask.rights(question, home: stage.home.root.path).sheet
        #expect(sheet.title == "Waiting room would like to" && sheet.frame.width == 440 && !sheet.isAlert)
        #expect(PanelsTests.texts(sheet.contentView) == [
            "Waiting room would like to", "~/something/spaces/waiting-room.html · made just now",
            "See your agents", "Which agents run on this Mac, what each one is doing, and its last messages. It only reads.",
            "Remember things", "Keep a small memory in its own folder, so it knows what you saw last time.",
            "It does not ask to write to your agents or start agents. Each right starts off; change it later in its Info."])
        let switches = SpaceViewTests.switches(sheet.contentView)
        #expect(switches.map(\.state) == [.off, .off] && switches.map { $0.accessibilityLabel() } == ["See your agents", "Remember things"])
        #expect(sheet.buttons.map(\.title) == ["Don't Allow", "Allow"] && sheet.buttons.map(\.hint) == ["esc", nil])
        #expect(sheet.firstResponder === sheet.buttons[0] && sheet.buttons[0].keyEquivalent == "\u{1b}" && !sheet.buttons[1].isEnabled)
        #expect(sheet.accessibilitySubrole() == .dialog)
        // Under the toolbar, centred over the space beside the sidebar.
        let hang = shell.window(shell.window, willPositionSheet: sheet, using: .zero)
        #expect(hang.minY == shell.window.contentLayoutRect.maxY && hang.minX == shell.split.splitViewItems[0].viewController.view.frame.width)
        try await stage.appearances { suffix in
            try await Picture.sheet(sheet, over: shell, library: library, web: room.web, "d4" + suffix, root: stage.home.root)
        }
        switches[1].performClick(nil)
        #expect(sheet.buttons[1].isEnabled)
    }

    /// The space the assistant just made in the mockup, its words invented: one agent waiting in its terminal.
    static let waitingRoom = """
        <!doctype html><html><head><meta charset="utf-8"><title>Waiting room</title>
        <script type="application/json" id="something">{"contract": 1, "title": "Waiting room", "rights": ["state", "store"]}</script><style>
        body{margin:0;padding:34px 46px;background:#F4F4F1;color:#121316;font:13.5px -apple-system,sans-serif}
        @media (prefers-color-scheme:dark){body{background:#15171C;color:#F1F1EE}.w{background:#1F2126!important}button{background:rgba(241,241,238,.08)!important}}
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
        shell.waiting(1, mine: 0)
        let host = try #require(shell.center.subviews.first { $0 is NSHostingView<GalleryView> } as? NSHostingView<GalleryView>)
        return (shell, library, host.rootView.model, host)
    }


    /// The labels VoiceOver reads in `view`, depth first, once `says` holds of them (else once two reads 0.1 s apart
    /// agree, for a view with no live clock), or after a minute. A SwiftUI view offscreen gives only the description of
    /// its outer elements (AXAttributedDescription): what is inside a card or a bar is out of reach here.
    static func read(_ view: NSView, until says: (([String]) -> Bool)? = nil) async -> [String] {
        let enhanced = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
        // As an assistive app asks: SwiftUI makes its elements only then.
        NSApp.accessibilitySetValue(true, forAttribute: enhanced)
        defer { NSApp.accessibilitySetValue(false, forAttribute: enhanced) }
        // The first question makes them, and SwiftUI updates them, on the run loop, as late as a busy runner lets it:
        // read again until they hold still and say what is awaited. The minute only stops a hang.
        _ = view.accessibilityChildren()
        let end = Date() + 60
        var last: [String]?
        while true {
            await wait(0.1)
            let words = labels(view)
            if says.map({ $0(words) }) ?? (words == last && !words.isEmpty) || Date() > end { return words }
            last = words
        }
    }

    private static func labels(_ element: Any) -> [String] {
        let object = element as AnyObject
        let described = object.accessibilityAttributeValue(NSAccessibility.Attribute(rawValue: "AXAttributedDescription")) as? NSAttributedString
        let words = [NSAccessibility.Attribute.description, .title, .value].compactMap { object.accessibilityAttributeValue($0) as? String }
            + [described?.string].compactMap { $0 }
        let children = (object as? NSAccessibilityProtocol)?.accessibilityChildren() ?? []
        return words.filter { !$0.isEmpty } + children.flatMap(labels)
    }

    /// Six cards in three columns, the first under the pointer with Preview, Show in Finder and Use; Agents keeps two.
    /// d5-narrow: two columns in the narrow window.
    @Test("d5: templates") func d5() async throws {
        let stage = try Stage("build")
        defer { stage.remove() }
        let (shell, library, gallery, host) = try Self.templates(stage)
        #expect(shell.window.title == "Templates" && shell.window.subtitle == "Start from one, then make it yours")
        #expect(gallery.cards(library.templates).map(\.title) == ["My agents", "Project watch", "Daily brief", "Logbook", "Stack", "Pebble"])
        #expect(library.templates.map(\.needs) == ["Sees and writes to your agents", "Sees, writes to and starts agents · Remembers",
                                                   "Sees your agents · Remembers", "Sees your agents · Remembers", "Remembers",
                                                   "Sees your agents · Remembers"])
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
        #expect(await wait(until: { model.ladder?.steps[2].mark == .done && model.ladder?.say?.hasPrefix("Fixed both") == true }))
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
    /// The main window of a first start, stepped back as the mockup dims it (its center blurred and faded, its sidebar
    /// faded, a veil of the background over it all), and the welcome window centred over it with its float shadow and
    /// its lights in their colors (gray when not `keyed`). The dimming is the mockup's CSS, redrawn here: the real
    /// window's filters are its layers', which an offscreen drawing does not apply.
    static func welcome(_ welcome: NSWindow, over shell: Shell, library: Library, web: WKWebView? = nil, _ name: String, root: URL,
                        keyed: Bool = true) async throws {
        guard let gallery else { return }
        try await window(shell, library: library, web: web, name + "-window", root: root, keyed: false)
        let file = gallery.appendingPathComponent(name + "-window.png")
        defer { try? FileManager.default.removeItem(at: file) }
        let page = try #require(NSImage(contentsOf: file)), size = shell.window.frame.size
        let frame = try #require(shell.window.contentView?.superview)
        let side = shell.split.splitViewItems[0].viewController.view, top = size.height - shell.window.contentLayoutRect.maxY
        let sidebar = side.convert(side.bounds, to: frame), center = NSRect(x: sidebar.maxX, y: 0, width: size.width - sidebar.maxX, height: size.height - top)
        // The center, blurred 7 points and desaturated, as CSS filters it.
        let cg = try #require(page.cgImage(forProposedRect: nil, context: nil, hints: nil)), scale = CGFloat(cg.width) / size.width
        let blur = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: 7 * scale]), tone = CIFilter(name: "CIColorControls", parameters: [kCIInputSaturationKey: 0.6])
        let blurred = filtered(page, [blur, tone].compactMap { $0 })
        // The sticker and its badge stay sharp under the veil: the step back filters the page, not the glass.
        let sticker = shell.glass.sticker, spot = sticker.convert(sticker.bounds, to: frame)
        let sharp = sticker.isHidden || sticker.window == nil ? nil : try bitmap(sticker.bounds.size)
        sharp.map { sticker.cacheDisplay(in: sticker.bounds, to: $0) }
        let content = try #require(welcome.contentView?.superview)
        disguise(content, root.path)
        await wait(1.0)
        content.layoutSubtreeIfNeeded()
        let drawn = try bitmap(content.bounds.size)
        content.cacheDisplay(in: content.bounds, to: drawn)
        let place = NSRect(x: ((size.width - Welcome.size.width) / 2).rounded(), y: size.height - 152 - Welcome.size.height,
                           width: Welcome.size.width, height: Welcome.size.height)
        try png(of: size, name) {
            page.draw(in: NSRect(origin: .zero, size: size))
            Look.Token.bg.color.setFill()
            center.fill()
            blurred.draw(in: center, from: center, operation: .sourceOver, fraction: 0.35)
            sharp?.draw(in: spot, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            Look.Token.bg.color.withAlphaComponent(0.3).setFill()
            sidebar.fill()
            Look.Token.bg.color.withAlphaComponent(0.42).setFill()
            NSRect(origin: .zero, size: size).fill()
            let shape = NSBezierPath(roundedRect: place, xRadius: Look.window, yRadius: Look.window)
            for shade in Look.float(NSAppearance.currentDrawing()) {
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                (shadow.shadowColor, shadow.shadowOffset, shadow.shadowBlurRadius) = (shade.color, NSSize(width: 0, height: -shade.y), shade.blur)
                shadow.set()
                Look.Token.bg.color.setFill()
                shape.fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            drawn.draw(in: place, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            Look.Token.line2.color.setStroke()
            shape.stroke()
            if keyed { paint(lights(of: welcome).map { ($0.0.offsetBy(dx: place.minX, dy: place.minY), $0.1) }) }
        }
    }
}
