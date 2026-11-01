// The welcome and the blank page: the welcome alone on the screen, done by keyboard, Look Again with no builder at its
// last beat, Skip, its end on New Space with no agent started, and the menus greyed while it is open, the request panel over it; the
// space the assistant made opened or said ready, the level sheet's first line; and the hints, each once.
import AppKit
import Foundation
import SomethingCore
import Testing
@testable import SomethingAgents
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-tour-")) struct WelcomeTests {
    let assistants = AssistantTests()

    /// With no builder, the last beat's Return waits until the programs were looked for, then looks again (busy a
    /// moment) and finds a builder installed meanwhile. Escape then ends it, kept as seen and skipped, and no agent was
    /// started. With no builder at all Escape opens the example instead, which needs none.
    @Test func withoutABuilderLookAgainFindsOne() async throws {
        let (home, model) = try assistants.assistant([], prefix: "something-tour-")
        defer { home.remove() }
        let welcome = WelcomeModel(places: home.places)
        let window = Welcome.window(welcome, assistant: model, motion: .reduced)
        #expect(window.contentView?.frame.size == Welcome.size && window.title == "Welcome to something")
        #expect(welcome.searching(model), "nothing is said before the programs were looked for")
        for _ in 0..<5 { Self.press(window, .return) }
        #expect(!welcome.looking && welcome.beat == .whole)
        model.engine.lookAgain()
        #expect(await wait(until: { model.noAgent }))
        var ended: [WelcomeModel.Ending] = []
        welcome.finished = { ended.append($0) }
        Self.press(window, .escape)
        #expect(ended == [.example])
        try assistants.install("claude", in: home.root.appendingPathComponent("bin"))
        Self.press(window, .return)
        #expect(welcome.looking)
        #expect(await wait(until: { model.kind == "claude" && !welcome.looking }))
        Self.press(window, .escape)
        #expect(ended == [.example, .skipped] && Preferences(home.places).toured)
        #expect(model.engine.state.agents.isEmpty && model.engine.assistants.isEmpty)
    }

    /// The first start of a home with no space: the welcome stands alone, centred on the screen, the window out of
    /// sight on New Space. While it is open the menus grey the window's commands and leave Show Request; a request's
    /// panel floats over it, and Escape there answers the request, not the welcome. Return, a click inside it, Escape
    /// (Skip) and the close button all end it on New Space, its field asked for the keys; it does not open again at the next
    /// start, and nothing was started.
    @Test func theWelcomeStandsAloneAndEndsOnNewSpace() async throws {
        let (home, model) = try assistants.assistant(["claude", "codex"], prefix: "something-tour-")
        defer { home.remove() }
        let (shell, library, _) = window(home, model)
        library.preferences.motion = .reduced
        library.select(.templates)
        #expect(App.welcomes(library), "a first start: never welcomed, no space")
        await assistants.look(model)
        let welcome = WelcomeModel(places: home.places)
        welcome.finished = { shell.welcomed($0) }
        let window = Self.shown(shell.welcome(welcome, onScreen: false))
        defer { window.orderOut(nil) }
        #expect(shell.welcoming === window && library.selection == .templates && window.firstResponder is WelcomeKeys, "what was shown stays until it ends")
        let screen = Welcome.place(on: NSScreen.main)
        #expect(screen.size == Welcome.size && Welcome.place(on: nil).origin == .zero)
        let welcoming = Keys.Situation(space: true, agent: true, welcoming: true, waiting: true)
        for id in ["new", "tpls", "ask", "trash", "close", "full", "sidebar", "tour", "how", "help", "space:invented"] {
            #expect(!Keys.enabled(id, welcoming), "\(id) is greyed while the welcome is open")
        }
        #expect(Keys.enabled("new", Keys.Situation()) && Keys.enabled("showreq", welcoming) && Keys.enabled("quit", welcoming))
        // A click inside leaves the keys to the welcome: Return, sent as the window server sends it, ends it.
        Self.click(window, at: NSPoint(x: 200, y: 300))
        #expect(window.firstResponder is WelcomeKeys)
        model.open = false
        for _ in 0..<4 { Self.send(window, .return) }
        #expect(shell.welcoming === window && welcome.beat == .whole)
        Self.send(window, .return)
        #expect(shell.welcoming == nil && Preferences(home.places).toured && library.selection == .newSpace)
        #expect(model.open, "its field is asked for the keys")
        #expect(shell.window.alphaValue == 1)
        #expect(!App.welcomes(Library(places: home.places, ask: FakeAsk(), share: Home.share)), "the welcome ended is kept")
        // Help › Welcome again: its close button ends it the same way.
        let again = WelcomeModel(places: home.places)
        again.finished = { shell.welcomed($0) }
        let second = shell.welcome(again, onScreen: false)
        library.select(.templates)
        second.performClose(nil)
        #expect(shell.welcoming == nil && library.selection == .newSpace)
        #expect(model.engine.state.agents.isEmpty && model.engine.assistants.isEmpty && model.id == nil)
    }

    /// Tab leaves the welcome's keys for the next view of the window's key loop, and ⇧Tab for the one before. A field
    /// stands in for that view here: SwiftUI's chip joins the loop only when Full Keyboard Access is on.
    @Test func tabMovesTheFocus() async throws {
        let (home, model) = try assistants.assistant(["claude", "codex"], prefix: "something-tour-")
        defer { home.remove() }
        let (shell, _, _) = window(home, model)
        await assistants.look(model)
        let window = Self.shown(shell.welcome(WelcomeModel(places: home.places), onScreen: false))
        defer { window.orderOut(nil) }
        let keys = try #require(window.firstResponder as? WelcomeKeys), field = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 22))
        keys.addSubview(field)
        (keys.nextKeyView, field.nextKeyView) = (field, keys)
        Self.press(window, .tab)
        #expect(!(window.firstResponder is WelcomeKeys), "Tab moved on: \(String(describing: window.firstResponder))")
        #expect(window.makeFirstResponder(keys))
        keys.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        #expect(!(window.firstResponder is WelcomeKeys), "⇧Tab moved back")
    }

    /// A request while the welcome is open: its panel floats over the welcome, and Escape at the panel denies the
    /// request and leaves the welcome open.
    @Test func aRequestFloatsOverTheWelcome() async throws {
        let (home, model) = try assistants.assistant([], prefix: "something-tour-")
        defer { home.remove() }
        let (shell, _, _) = window(home, model)
        let welcome = shell.welcome(WelcomeModel(places: home.places), onScreen: false)
        defer { welcome.close() }
        let source = FakePrompts()
        AcceptanceTrust.request("r", [0], in: source)
        let panels = AcceptanceTrust.panels(source, shell)
        panels.refresh()
        #expect(panels.present(in: nil))
        let panel = try #require(panels.panel)
        #expect(panel.level.rawValue > welcome.level.rawValue, "the panel floats over the welcome")
        panel.cancelOperation(nil)
        #expect(source.answers.map(\.1) == [.deny] && panels.panel == nil)
        #expect(shell.welcoming === welcome, "Escape at the panel answers it, not the welcome")
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

    enum Key: UInt16 { case `return` = 36, escape = 53, space = 49, tab = 48, left = 123, right = 124, down = 125, up = 126 }

    /// Sends `key` to `window`, as the window server would, to its first responder.
    static func press(_ window: NSWindow, _ key: Key) {
        let characters: [Key: String] = [.return: "\r", .escape: "\u{1b}", .space: " ", .tab: "\t", .left: "\u{F702}", .right: "\u{F703}", .down: "\u{F701}", .up: "\u{F700}"]
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

    /// A sentence sent from the blank page builds, with the conversation open, and leaves the draft as it was; once
    /// the turn ended, the space the agent made opens by itself, its level the one New Space pre-set, and its level
    /// sheet, shown elsewhere, says the agent made it. A turn that made no space ends the build too. One made while the
    /// person is on another space is said ready (the window's toast), and has its dot until it is opened.
    @Test func aBuildFromTheBlankPageOpensWhatItMade() async throws {
        let (home, model) = try assistants.assistant(prefix: "something-tour-")
        defer { home.remove() }
        model.engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        // What App does when a build ends, with the space the agent made written just before.
        let library = Library(places: home.places, ask: FakeAsk(), share: Home.share)
        var making: (name: String, title: String)?, opened: [String?] = [], answers: [Int] = [], arrived: [String] = []
        model.arrived = { arrived.append("\($0) · \($1)") }
        model.ended = {
            // Never before the agent answered: a build ends with its turn, not with its launch.
            answers.append(model.rows.filter { $0 == .reply("Invented reply.") }.count)
            if let making { _ = try? home.space(making.name, page(#"{"contract": 1, "title": "\#(making.title)"}"#, "")) }
            library.relist()
            opened.append(model.appeared(library.entries))
        }
        let sentence = BlankView.chips[0].1
        making = ("waiting", "Who waits")
        model.draft = "Half written"
        model.send(sentence)
        #expect(model.building && model.threadShown && model.sessions[.new]?.draft == "Half written")
        #expect(await wait(until: { model.rows.contains(.mine(caption: "on the blank page", text: sentence)) }))
        #expect(await wait(until: { !model.building }))
        #expect(opened == ["waiting"] && model.made == ["waiting"] && model.ready.isEmpty)
        #expect(try AppFile.read(home.places.grants).spaces["waiting"]?.level == .watch, "the level its words pre-set is its consent")

        // A question makes no space: the build ends with its answer all the same.
        making = nil
        model.send("What can you do?")
        #expect(model.building)
        #expect(await wait(until: { !model.building }))
        #expect(opened == ["waiting", nil] && model.ready.isEmpty && model.light == .ready)

        // Made while the person was on another space: said ready, never opened.
        making = ("second", "Second")
        model.send("A second one.")
        model.place = .space(title: "Who waits", name: "waiting", page: home.places.spaces.appendingPathComponent("waiting.html").path)
        #expect(await wait(until: { model.builds.isEmpty }))
        #expect(opened == ["waiting", nil, nil] && model.ready == ["second"] && model.made.contains("second"))
        let second = model.session(for: .space(title: "Second", name: "second", page: home.places.spaces.appendingPathComponent("second.html").path))
        #expect(answers.prefix(2) == [1, 1] && second.rows.filter { $0 == .reply("Invented reply.") }.count == 2,
                "the space made keeps its build's conversation, the question's before it; New Space begins a new one")
        #expect(arrived == ["second · Second"] && model.notice == nil)

        // The whole sentence is the consent: its agent, a blank folder made for the space, and the scope it said.
        model.place = .blank
        making = ("started", "Starts one")
        (model.chosenLevel, model.runFolder, model.chosenStart) = (.run, .blank, Grant.Start(kind: "pi"))
        model.send("A page")
        #expect(await wait(until: { !model.building }))
        let started = try #require(try AppFile.read(home.places.grants).spaces["started"])
        #expect(started.level == .run && started.start == Grant.Start(kind: "pi") && started.granted.last == "launch:pi")
        #expect(started.scope == .folders([started.folder ?? ""]), "at start, its folder is all it sees")
        #expect(started.folder == home.places.agents.appendingPathComponent("started").path && FileManager.default.fileExists(atPath: started.folder ?? ""))
        making = ("told", "Told")
        (model.chosenLevel, model.chosenScope) = (.talk, .folders(["/Users/example/code/shop"]))
        model.send("A page")
        #expect(await wait(until: { !model.building }))
        #expect(try AppFile.read(home.places.grants).spaces["told"]?.scope == .folders(["/Users/example/code/shop"]))
        making = ("everyone", "Everyone")
        model.send("A page of my agents")
        #expect(await wait(until: { !model.building }))
        #expect(try AppFile.read(home.places.grants).spaces["everyone"]?.scope == .all, "said all, it means all")

        await assistants.finish(home, model)

        let question = RightsQuestion(space: "Second", description: "Invented.", level: .watch, folder: nil, made: true)
        let said = PanelsTests.texts(Ask.rights(question).sheet.contentView)
        #expect(Array(said.prefix(3)) == ["Second would like to work with your agents", "Your agent made this space.", "Invented."])
    }

    /// The window of `home`, never shown, with `model` as its assistant.
    func window(_ home: Home, _ model: AssistantModel) -> (Shell, Library, Info) {
        let library = Library(places: home.places, ask: FakeAsk(), share: Home.share), info = Info(places: home.places, ask: FakeAsk())
        return (Shell(library: library, info: info, assistant: model, autosave: false), library, info)
    }
}
