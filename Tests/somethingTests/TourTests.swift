// The welcome tour, the blank page and the launcher: the welcome's keys, its steps with and without a builder and Look
// Again, its end on the blank page with no agent started, the suggestions' whole sentences, the space the assistant
// made opened or said ready, the rights sheet's first line, and the launcher, made in the test home's Applications only
// under a Homebrew prefix and its switch on, never twice, never registered, removed only when something made it.
import AppKit
import Foundation
import SomethingCore
import Testing
@testable import SomethingAgents
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-tour-")) struct TourTests {
    let assistants = AssistantTests()

    /// With no builder, the second step is "No coding agent found"; Look Again, by Return, finds a builder installed
    /// meanwhile and the step lists it. Escape then ends the tour on the blank page, the comforts as they were, and no
    /// agent was started.
    @Test func withoutABuilderLookAgainFindsOne() async throws {
        let (home, model) = try assistants.assistant([], prefix: "something-tour-")
        defer { home.remove() }
        let tour = Tour(places: home.places)
        #expect(tour.screen(model) == .welcome && !tour.offersLauncher && tour.comforts == [.notify])
        let welcome = Welcome.window(tour, assistant: model, motion: .reduced)
        #expect(welcome.contentView?.frame.size == Welcome.size && welcome.title == "Welcome to something")
        Self.press(welcome, .return)
        #expect(tour.screen(model) == .none && tour.searching(model), "nothing is said before the programs were looked for")
        model.engine.lookAgain()
        #expect(await wait(until: { model.noAgent }))
        #expect(tour.screen(model) == .none)
        try assistants.install("claude", in: home.root.appendingPathComponent("bin"))
        Self.press(welcome, .return)
        #expect(tour.looking)
        #expect(await wait(until: { model.kind == "claude" && !tour.looking }))
        #expect(tour.screen(model) == .assistant)
        let (shell, _, _) = window(home, model)
        shell.show(tour)
        // What App's finished does: New Space, whose blank page takes the tour's place.
        var ended = false
        tour.finished = { problem in
            ended = problem == nil
            shell.show(nil)
        }
        tour.toggle(.notify)
        Self.press(welcome, .escape)
        #expect(ended && Preferences(home.places).toured && !Preferences(home.places).launcherOffered && !Preferences(home.places).notify)
        #expect(shell.touring == nil && shell.window.title == "New Space" && model.place == .blank)
        #expect(model.engine.state.agents.isEmpty && model.engine.assistants.isEmpty)
    }

    /// The keys: Return goes on, ⌘[ goes back, the arrows choose among the builders (by rows in the grid) and move
    /// between the comforts, Space turns one on, ⌘K says hello; at the end the notifications follow their switch.
    /// Choosing and finishing start nothing.
    @Test func theWelcomeIsDoneByKeyboard() async throws {
        let (home, model) = try assistants.assistant(["claude", "codex", "opencode", "pi"], prefix: "something-tour-")
        defer { home.remove() }
        let tour = Tour(places: home.places)
        let window = Welcome.window(tour, assistant: model, motion: .reduced)
        await assistants.look(model)
        #expect(model.kind == "claude" && window.firstResponder is WelcomeKeys)
        Self.press(window, .return)
        #expect(tour.step == .assistant && tour.screen(model) == .assistant)
        Self.press(window, .down)
        #expect(model.kind == "opencode", "down moves by a row of two")
        Self.press(window, .right)
        #expect(model.kind == "pi")
        Self.press(window, .down)
        #expect(model.kind == "codex", "the choice wraps around")
        Self.press(window, .up)
        #expect(model.kind == "pi" && Preferences(home.places).assistant == "pi")
        #expect(Self.command(window, "["))
        #expect(tour.step == .welcome && !tour.forward)
        Self.press(window, .return)
        Self.press(window, .return)
        #expect(tour.step == .comforts && tour.cursor == 0 && !tour.notify)
        Self.press(window, .space)
        #expect(tour.notify)
        Self.press(window, .down)
        #expect(tour.cursor == 0, "one comfort only: the launcher is not offered here")
        #expect(Self.command(window, "k"))
        #expect(!tour.met, "⌘K says hello only at its own step")
        Self.press(window, .return)
        #expect(Self.command(window, "k"))
        #expect(tour.step == .meet && tour.met)
        // Any other key equivalent is left to the menus.
        #expect(!Self.command(window, "n"))
        Self.press(window, .return)
        #expect(tour.step == .ready)
        var ended = false
        tour.finished = { ended = $0 == nil }
        Self.press(window, .return)
        #expect(ended && Preferences(home.places).toured && Preferences(home.places).notify)
        try await Task.sleep(for: .milliseconds(500))
        #expect(model.engine.state.agents.isEmpty && model.engine.assistants.isEmpty && model.id == nil)
    }

    /// A click inside the welcome, on a builder's row or on the install commands, leaves the keys to the welcome:
    /// Return still goes on, sent as the window server sends it, through the window. ⌘[ and Back agree: neither goes
    /// back while the builders are looked for.
    @Test func aClickLeavesTheKeysToTheWelcome() async throws {
        let (home, model) = try assistants.assistant(["claude", "codex"], prefix: "something-tour-")
        defer { home.remove() }
        let tour = Tour(places: home.places)
        let window = Self.shown(Welcome.window(tour, assistant: model, motion: .reduced))
        defer { window.orderOut(nil) }
        await assistants.look(model)
        tour.move(.assistant)
        await wait(0.6)
        // The second builder's row: the click chooses it, and the keys stay with the welcome.
        // SwiftUI places the rows when it is ready, later under load: the click is repeated until one lands, as a
        // second click on the same row chooses the same builder.
        #expect(await wait(10, until: {
            Self.click(window, at: NSPoint(x: 200, y: Welcome.size.height - 208))
            return model.kind == "codex"
        }), "the click reached the row")
        #expect(window.firstResponder is WelcomeKeys)
        Self.send(window, .return)
        #expect(tour.step == .comforts)

        let (bare, none) = try assistants.assistant([], prefix: "something-tour-")
        defer { bare.remove() }
        let looking = Tour(places: bare.places), alone = Self.shown(Welcome.window(looking, assistant: none, motion: .reduced))
        defer { alone.orderOut(nil) }
        looking.move(.assistant)
        #expect(looking.searching(none))
        #expect(Self.command(alone, "["))
        #expect(looking.step == .assistant, "no going back while the builders are looked for")
        none.engine.lookAgain()
        #expect(await wait(until: { none.noAgent }))
        await wait(0.6)
        // The first install command. Its line is found by its Copy Command, whose click is seen; the click on the
        // command itself, on that line, must leave the keys with the welcome.
        var copied: [String] = []
        none.copy = { copied.append($0) }
        var line: CGFloat?
        for y in stride(from: 150.0, to: 320, by: 4) where line == nil {
            Self.click(alone, at: NSPoint(x: 595, y: Welcome.size.height - y))
            await wait(0.02)
            if copied.last == InstallList.builders[0].command { line = y }
        }
        let y = try #require(line, "a click reached the first Copy Command")
        Self.click(alone, at: NSPoint(x: 300, y: Welcome.size.height - y))
        #expect(alone.firstResponder is WelcomeKeys)
        Self.send(alone, .return)
        #expect(looking.looking, "Return looks again")
        #expect(await wait(until: { !looking.looking }))
    }

    /// `window` in front but out of sight, far off the screens and transparent, so the window server's events reach it.
    static func shown(_ window: NSWindow) -> NSWindow {
        window.alphaValue = 0
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFront(nil)
        return window
    }

    /// A click of the mouse at `point` in `window`'s content, through the window, as the window server sends it.
    static func click(_ window: NSWindow, at point: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                 context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { continue }
            window.sendEvent(event)
        }
    }

    /// Sends `key` through `window`, which gives it to whatever is its first responder.
    static func send(_ window: NSWindow, _ key: Key) {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                           context: nil, characters: key == .return ? "\r" : "\u{1b}", charactersIgnoringModifiers: key == .return ? "\r" : "\u{1b}",
                                           isARepeat: false, keyCode: key.rawValue) else { return }
        window.sendEvent(event)
    }

    enum Key: UInt16 { case `return` = 36, escape = 53, space = 49, left = 123, right = 124, down = 125, up = 126 }

    /// Sends `key` to `window`, as the window server would, to its first responder.
    static func press(_ window: NSWindow, _ key: Key) {
        let characters: [Key: String] = [.return: "\r", .escape: "\u{1b}", .space: " ", .left: "\u{F702}", .right: "\u{F703}", .down: "\u{F701}", .up: "\u{F700}"]
        let flags: NSEvent.ModifierFlags = [.left, .right, .down, .up].contains(key) ? [.numericPad, .function] : []
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                                           context: nil, characters: characters[key] ?? "", charactersIgnoringModifiers: characters[key] ?? "",
                                           isARepeat: false, keyCode: key.rawValue) else { return }
        window.firstResponder?.keyDown(with: event)
    }

    /// ⌘`key` given to `window` as a key equivalent; whether something took it.
    static func command(_ window: NSWindow, _ key: String) -> Bool {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
                                           context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0) else { return false }
        return window.performKeyEquivalent(with: event)
    }

    /// A suggestion sends its whole sentence, from the blank page, with the conversation open, and leaves the draft as
    /// it was; once the turn ended, the space the agent made opens by itself and its rights sheet says the agent made
    /// it. A turn that made no space ends the build too. One made while the person is on another space is said ready,
    /// and has its dot until it is opened.
    @Test func theSuggestionsSendTheirSentences() async throws {
        #expect(BlankView.chips.map(\.0) == ["Who is waiting for me", "A morning brief of my agents", "A small game for my breaks"])
        let (home, model) = try assistants.assistant(prefix: "something-tour-")
        defer { home.remove() }
        model.engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        // What App does when a build ends, with the space the agent made written just before.
        let library = Library(places: home.places, ask: FakeAsk(), share: Home.share)
        var making: (name: String, title: String)?, open: String?, opened: [String?] = [], answers: [Int] = []
        model.ended = {
            // Never before the agent answered: a build ends with its turn, not with its launch.
            answers.append(model.rows.filter { $0 == .reply("Invented reply.") }.count)
            if let making { _ = try? home.space(making.name, page(#"{"contract": 1, "title": "\#(making.title)"}"#, "")) }
            library.relist()
            opened.append(model.appeared(library.entries, open: open))
        }
        let sentence = BlankView.chips[0].1
        #expect(sentence == "Make me a space that shows which of my agents are waiting for me, and lets me answer the ones I can.")
        making = ("waiting", "Who waits")
        model.draft = "Half written"
        model.send(sentence)
        #expect(model.building && model.threadShown && model.draft == "Half written")
        #expect(await wait(until: { model.rows.contains(.mine(caption: "on the blank page", text: sentence)) }))
        #expect(await wait(until: { !model.building }))
        #expect(opened == ["waiting"] && model.made == ["waiting"] && model.ready == nil)

        // A question makes no space: the build ends with its answer all the same.
        making = nil
        model.send("What can you do?")
        #expect(model.building)
        #expect(await wait(until: { !model.building }))
        #expect(opened == ["waiting", nil] && model.ready == nil && model.light == .ready)

        // Made while the person was on another space: said ready, never opened.
        (making, open) = (("second", "Second"), "waiting")
        model.send("A second one.")
        #expect(await wait(until: { !model.building }))
        #expect(opened == ["waiting", nil, nil] && model.ready?.id == "second" && model.made.contains("second"))
        #expect(answers == [1, 1, 2], "the space made keeps its build's conversation; New Space begins a new one")
        #expect(model.notice?.title == "“Second” is ready." && model.notice?.actions.map(\.title) == ["Open"])
        await assistants.finish(home, model)

        let question = RightsQuestion(space: "Second", description: "Invented.", rights: ["store"], scope: nil, missing: [], folder: nil, made: true)
        let said = PanelsTests.texts(Ask.rights(question).sheet.contentView)
        #expect(Array(said.prefix(3)) == ["Second would like to", "Your agent made this space.", "Invented."])
    }

    /// Under a Homebrew prefix, the tour offers the launcher once and makes it in the home's Applications: a bundle of
    /// its own, never shown in the Dock, never registered with LaunchServices.
    @Test func theLauncherIsMadeOnceUnderHomebrew() async throws {
        let home = Home(prefix: "something-tour-")
        defer { home.remove() }
        #expect(Launcher.prefix(of: URL(fileURLWithPath: "/opt/homebrew/Cellar/something/HEAD-0a1b2c3/something.app")) == "/opt/homebrew")
        #expect(Launcher.prefix(of: URL(fileURLWithPath: "/Users/example/code/something/.build/debug/something")) == nil)
        // The launcher's script quotes the path: a quote in it would break the script.
        #expect(Launcher.prefix(of: URL(fileURLWithPath: "/Users/example/it's/Cellar/something/0.2.0/something.app")) == nil)
        #expect(!Tour(places: home.places, app: URL(fileURLWithPath: "/Users/example/code/something/.build/debug")).offersLauncher)

        let brew = home.root.appendingPathComponent("brew/Cellar/something/0.2.0/something.app")
        let tour = Tour(places: home.places, app: brew)
        #expect(tour.offersLauncher && !tour.addLauncher && tour.comforts == [.launcher, .notify])
        tour.toggle(.launcher)
        // A tour skipped makes none, even with its switch on, and the launcher is not offered again.
        let skipped = Tour(places: home.places, app: brew)
        skipped.toggle(.launcher)
        skipped.skip()
        #expect(Preferences(home.places).launcherOffered && !FileManager.default.fileExists(atPath: Launcher.place(home.places).path))
        var problem: String?
        tour.finished = { problem = $0 }
        tour.end()
        let launcher = Launcher.place(home.places)
        #expect(problem == nil)
        let info = try #require(try PropertyListSerialization.propertyList(
            from: Data(contentsOf: launcher.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any])
        #expect(info["CFBundleIdentifier"] as? String == "io.github.emiwltz.something.launcher" && info["LSUIElement"] as? Bool == true)
        // What Spotlight shows of an app: its name, its kind and its icon.
        #expect(info["CFBundleName"] as? String == "something" && info["CFBundlePackageType"] as? String == "APPL" && info["CFBundleIconFile"] as? String == "something")
        let script = try String(contentsOf: launcher.appendingPathComponent("Contents/MacOS/something"), encoding: .utf8)
        #expect(script.contains("exec /usr/bin/open '\(home.root.path)/brew/opt/something/something.app'"))
        #expect(FileManager.default.isExecutableFile(atPath: launcher.appendingPathComponent("Contents/MacOS/something").path))

        // Never offered twice, never made twice.
        #expect(!Tour(places: home.places, app: brew).offersLauncher)
        try "kept".write(to: launcher.appendingPathComponent("Contents/kept"), atomically: true, encoding: .utf8)
        try Launcher.make(prefix: home.root.appendingPathComponent("brew").path, places: home.places, icon: nil)
        #expect(FileManager.default.fileExists(atPath: launcher.appendingPathComponent("Contents/kept").path))
        // Removed only when it is the one something made.
        #expect(try Launcher.remove(places: home.places) && !FileManager.default.fileExists(atPath: launcher.path))
        try FileManager.default.createDirectory(at: launcher.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        #expect(try !Launcher.remove(places: home.places) && FileManager.default.fileExists(atPath: launcher.path))

        // Nothing registered it with LaunchServices. (Spotlight's importer, mdimport, would: a test never runs it.)
        let known = try await offMain { try PackagingTests.registered() }
        #expect(!known.contains { $0.contains(home.root.path) || $0.contains(home.root.resolvingSymlinksInPath().path) })
    }

    /// Help › Welcome Tour just after a space was selected: the tour is a destination like the space, so the space,
    /// which had not opened yet, never takes the tour's place; leaving the tour brings back the sidebar it folded.
    @Test func theTourIsADestinationLikeASpace() async throws {
        let (home, model) = try assistants.assistant([], prefix: "something-tour-")
        defer { home.remove() }
        let (shell, library, _) = window(home, model)
        let tour = Tour(places: home.places)
        // What App.open does with each destination; no space is listed here, so a space shows the blank page.
        library.opened = { $0 == .tour ? shell.show(tour) : shell.show(nil) }
        library.select(.space("invented"))
        library.select(.tour)
        try await Task.sleep(for: .milliseconds(100))
        #expect(shell.touring === tour && shell.window.title == "something" && shell.glass.isHidden == true)
        #expect(shell.split.splitViewItems[0].isCollapsed)
        library.select(.newSpace)
        try await Task.sleep(for: .milliseconds(100))
        // New Space is its own composer: the assistant's glass stays away from it.
        #expect(shell.touring == nil && shell.window.title == "New Space" && shell.glass.isHidden == true)
        #expect(!shell.split.splitViewItems[0].isCollapsed)
    }

    /// The window of `home`, never shown, with `model` as its assistant.
    func window(_ home: Home, _ model: AssistantModel) -> (Shell, Library, Info) {
        let library = Library(places: home.places, ask: FakeAsk(), share: Home.share), info = Info(places: home.places, ask: FakeAsk())
        return (Shell(library: library, info: info, assistant: model, autosave: false), library, info)
    }
}
