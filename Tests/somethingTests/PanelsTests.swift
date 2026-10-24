// The request panel against a fake prompt source shaped like the Engine's: one panel that shows the requests in the
// order they came and steps through them, Allow Once armed after 0.5 s and pressed by no key, VoiceOver's press only
// on a panel the person took, Deny, Escape and the close button deny, its place across the window's corner, never
// modal, left by a request the agent withdraws, and a question answered with the chosen and typed answers. The queue
// behind it: arrival order, steps that wrap, and each space's own count. The sheets the app waits for mean what their
// buttons say, one at a time. No panel is seen: the one that arrives is transparent.
import AppKit
import SomethingAgents
import SomethingCore
import Testing
@testable import something

/// The Engine's side of the panels, played by the test.
final class FakePrompts: PromptSource {
    var prompts: [Prompt] = []
    var answers: [(String, Answer)] = []
    /// What `answer` throws, as the Engine does when the agent stopped reading.
    var lost: CodedError?
    /// Requests still listed whose details are gone: they closed.
    var gone: [Request] = []
    var requests: [Request] { gone + prompts.map(\.request) }
    func prompt(_ request: String) -> Prompt? { prompts.first { $0.request.id == request } }
    func answer(_ request: String, _ answer: Answer) throws {
        answers.append((request, answer))
        if let lost { throw lost }
    }

    func permission(_ id: String, about: String) -> Prompt {
        Prompt(request: Request(id: id, agent: "a1", kind: "permission", tool: "Bash", about: about, at: "2026-10-17T09:00:01Z"),
               input: about)
    }
}

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing)) struct PanelsTests {
    init() { NSApplication.shared.setActivationPolicy(.prohibited) }

    /// Every text the panel shows, top to bottom.
    static func texts(_ view: NSView?) -> [String] {
        guard let view else { return [] }
        return ((view as? NSTextField).map { [$0.stringValue] } ?? (view as? NSTextView).map { [$0.string] } ?? []) + view.subviews.flatMap(texts)
    }

    @Test func permissionsAreQueuedAndAnswered() throws {
        let source = FakePrompts()
        var time: TimeInterval = 100
        let panels = Panels(source: source, shows: false)
        panels.clock = { time }
        source.prompts = [source.permission("r1", about: "npm test"), source.permission("r2", about: "rm -rf build")]
        panels.refresh()
        #expect(panels.queue.waiting.map(\.id) == ["r1", "r2"] && panels.panel?.request?.id == "r1")
        panels.refresh()
        #expect(panels.panel?.request?.id == "r1", "a refresh with nothing new changes nothing")

        let panel = try #require(panels.panel)
        panel.allow()
        #expect(source.answers.isEmpty, "Allow Once is not armed yet")
        time += 0.6
        panel.allow()
        #expect(source.answers.map(\.0) == ["r1"] && source.answers[0].1 == .once)
        #expect(panels.panel === panel && panel.request?.id == "r2" && !panel.dismissed, "the next request takes its place")
        panel.allow()
        #expect(source.answers.count == 1, "a new request arms again")
        // The agent has not taken the answer yet: r1 stays in the state, and is not shown again.
        panels.refresh()
        #expect(panel.request?.id == "r2" && panels.queue.waiting.map(\.id) == ["r2"])

        // Escape denies, before the arming too.
        panel.cancelOperation(nil)
        #expect(source.answers.map(\.0) == ["r1", "r2"] && source.answers[1].1 == .deny)
        #expect(panels.panel == nil && panel.dismissed)
    }

    /// Allow Once answers a click only once armed; no key ever presses it; the close button denies.
    @Test func allowOnceArmsAndTakesNoKey() throws {
        var time: TimeInterval = 100, answers: [Answer] = []
        let panel = RequestPanel { answers.append($0) }
        panel.clock = { time }
        panel.show(FakePrompts().permission("r1", about: "npm test"), who: Asker(program: "Codex"), age: nil)
        #expect(!panel.armed && !panel.allowButton.isEnabled && panel.allowButton.progress == 0)
        time += 0.25
        panel.tick()
        #expect(panel.allowButton.progress == 0.5 && !panel.allowButton.isEnabled)
        panel.allow()
        time += 0.25
        panel.tick()
        #expect(panel.armed && panel.allowButton.isEnabled && panel.allowButton.progress == 1 && answers.isEmpty)
        for (key, code) in [("\r", UInt16(36)), (" ", 49), ("\u{3}", 76)] {
            for modifiers in [NSEvent.ModifierFlags(), .command, .option] {
                let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                                                          context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code))
                #expect(!panel.allowButton.performKeyEquivalent(with: event))
                panel.allowButton.keyDown(with: event)
                _ = panel.performKeyEquivalent(with: event)
            }
        }
        #expect(answers.isEmpty && !panel.allowButton.acceptsFirstResponder && panel.allowButton.keyEquivalent.isEmpty,
                "Return, Space, Enter and key equivalents never answer")
        panel.allow()
        #expect(answers == [.once])
        panel.standardWindowButton(.closeButton)?.performClick(nil)
        #expect(answers == [.once, .deny] && panel.standardWindowButton(.closeButton)?.accessibilityLabel() == "Close: deny")
    }

    /// The panel as VoiceOver finds it: key or not as a test says.
    final class KeyPanel: RequestPanel {
        var key = false
        override var isKeyWindow: Bool { key }
    }

    /// VoiceOver's press answers only once armed, and only while the person made the panel key, by a click on it.
    @Test func voiceOverPressesOnlyAnArmedPanelThePersonTook() throws {
        var time: TimeInterval = 100, answers: [Answer] = []
        let panel = KeyPanel { answers.append($0) }
        panel.clock = { time }
        panel.show(FakePrompts().permission("r1", about: "npm test"), who: Asker(program: "Codex"), age: nil)
        panel.key = true
        #expect(!panel.allowButton.accessibilityPerformPress() && answers.isEmpty, "refused before the arming")
        time += 1
        #expect(!panel.allowButton.accessibilityPerformPress() && answers.isEmpty, "refused when the person did not take the panel")
        let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 330, y: panel.frame.height - 12), modifierFlags: [],
                                                    timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        panel.sendEvent(click)
        panel.key = false
        #expect(panel.held && !panel.allowButton.accessibilityPerformPress() && answers.isEmpty, "refused when the panel lost the keys")
        panel.key = true
        #expect(panel.allowButton.accessibilityPerformPress() && answers == [.once])
        panel.resignKey()
        #expect(!panel.held && !panel.voicePress(), "the keys gone, the person's hold goes too")
    }

    /// The panel arrives in front without the keys: keys typed in the main window (a page's, or the person's in a
    /// page) never make it key, nor answer it.
    @Test func keysInTheMainWindowNeverReachThePanel() throws {
        var time: TimeInterval = 100, answers: [Answer] = []
        let panel = RequestPanel { answers.append($0) }
        panel.clock = { time }
        panel.alphaValue = 0
        defer { panel.orderOut(nil) }
        panel.show(FakePrompts().permission("r1", about: "npm test"), who: Asker(program: "Codex"), age: nil)
        let main = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 640), styleMask: .titled, backing: .buffered, defer: false)
        let text = NSTextView()
        (main.alphaValue, main.contentView) = (0, text)
        defer { main.orderOut(nil) }
        // The test's app is never active, so the main window cannot hold the keys; a panel that took them would still be
        // key, as a nonactivating panel is.
        main.makeKeyAndOrderFront(nil)
        main.makeFirstResponder(text)
        panel.arrive(beside: main)
        time += 1
        for (key, code) in [("\r", UInt16(36)), (" ", 49), ("\u{1b}", 53)] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: main.windowNumber,
                                                      context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code))
            main.sendEvent(event)
        }
        #expect(panel.isVisible)
        #expect(!panel.isKeyWindow && !panel.held && answers.isEmpty)
    }

    /// Allow Once arms while a sheet waits in a modal loop: its ticker runs in every mode of the run loop.
    @Test func allowOnceArmsWhileASheetWaits() {
        var time: TimeInterval = 100
        let panel = RequestPanel { _ in }
        panel.clock = { time }
        panel.show(FakePrompts().permission("r1", about: "npm test"), who: Asker(program: "Codex"), age: nil)
        time += 1
        let end = Date() + 0.1
        while Date() < end { RunLoop.main.run(mode: .modalPanel, before: end) }
        #expect(panel.allowButton.isEnabled)
    }

    /// The panel goes across the window's top-right corner, below its toolbar, kept inside the screen; at the screen's
    /// top right in full screen. Its header moves it.
    @Test func thePanelSitsAcrossTheWindowsCorner() throws {
        let size = NSSize(width: 392, height: 440), screen = NSRect(x: 0, y: 0, width: 1440, height: 875)
        func place(_ window: NSRect, full: Bool = false) -> NSPoint {
            RequestPanel.place(size, window: window, toolbar: 50, screen: full ? NSRect(x: 0, y: 0, width: 1440, height: 900) : screen, fullScreen: full)
        }
        #expect(place(NSRect(x: 120, y: 102, width: 1200, height: 760)) == NSPoint(x: 1032, y: 364), "large: kept 16 points inside the screen")
        #expect(place(NSRect(x: 220, y: 180, width: 1000, height: 660)) == NSPoint(x: 1024, y: 342), "medium: half outside the window")
        #expect(place(NSRect(x: 340, y: 160, width: 760, height: 680)) == NSPoint(x: 904, y: 342), "narrow")
        #expect(place(NSRect(x: 0, y: 0, width: 1440, height: 900), full: true) == NSPoint(x: 1032, y: 402), "full screen")
        #expect(place(NSRect(x: -900, y: -500, width: 1000, height: 600)) == NSPoint(x: 16, y: 0), "a window mostly off the screen")

        let panel = RequestPanel { _ in }
        panel.show(FakePrompts().permission("r1", about: "npm test"), who: Asker(program: "Codex"), age: nil)
        panel.setFrameOrigin(NSPoint(x: 100, y: 100))
        let height = panel.frame.height
        func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: height - y), modifierFlags: [], timestamp: 0,
                                            windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        panel.header.mouseDown(with: try mouse(.leftMouseDown, 300, 12))
        panel.header.mouseDragged(with: try mouse(.leftMouseDragged, 340, 32))
        panel.header.mouseUp(with: try mouse(.leftMouseUp, 340, 32))
        #expect(panel.frame.origin == NSPoint(x: 140, y: 80))
    }

    /// An answer the agent no longer reads is said in the panel, which stays, even once the request left the state,
    /// until the person puts it away; then the next request has its panel.
    @Test func aLostAnswerIsSaidInThePanel() throws {
        let source = FakePrompts()
        let panels = Panels(source: source, shows: false)
        panels.clock = { 100 }
        source.prompts = [source.permission("r1", about: "npm test"), source.permission("r2", about: "git push")]
        source.lost = CodedError("AGENT_STOPPED", "Claude Code did not receive your answer: it stopped listening.")
        panels.refresh()
        let first = try #require(panels.panel)
        first.setFrameOrigin(NSPoint(x: 100, y: 300))
        let top = first.frame.maxY
        first.deny()
        #expect(Self.texts(first.contentView).contains("Claude Code did not receive your answer: it stopped listening."))
        #expect(Self.texts(first.contentView).contains("An agent wants to run a command"), "who asked stays above the sentence")
        #expect(!Self.texts(first.contentView).contains("npm test"))
        #expect(first.frame.maxY == top, "the panel keeps its top")
        #expect(first.told && !first.dismissed && panels.panel === first)
        source.prompts.removeFirst()
        panels.refresh()
        #expect(panels.panel === first && !first.dismissed, "the sentence stays when the request leaves the state")
        first.cancelOperation(nil)
        #expect(first.dismissed && source.answers.count == 1, "putting it away answers nothing")
        #expect(panels.panel?.request?.id == "r2")
    }

    @Test func aWithdrawnRequestLeavesThePanel() throws {
        let source = FakePrompts()
        let panels = Panels(source: source, shows: false)
        source.prompts = [source.permission("r1", about: "npm test"), source.permission("r2", about: "git push")]
        panels.refresh()
        let panel = try #require(panels.panel)
        #expect(panel.position == "1 of 2")
        source.prompts.removeFirst()
        panels.refresh()
        #expect(panel.request?.id == "r2" && panel.position == nil && !panel.dismissed)
        #expect(source.answers.isEmpty, "nothing is answered for the person")
        // A request whose details are already gone is passed over.
        source.prompts = [Prompt(request: Request(id: "r3", agent: "a1", kind: "permission", tool: nil, about: nil, at: "2026-10-17T09:00:02Z"))]
        panels.refresh()
        #expect(panels.panel?.request?.id == "r3")
        source.prompts = []
        panels.refresh()
        #expect(panels.panel == nil && panel.dismissed && panels.queue.waiting.isEmpty)
    }

    /// Several requests: the header's steps walk them, wrapping, and each one arms again.
    @Test func theStepsWalkTheQueue() throws {
        let source = FakePrompts()
        var time: TimeInterval = 100
        let panels = Panels(source: source, shows: false)
        panels.clock = { time }
        source.prompts = ["r1", "r2", "r3"].map { source.permission($0, about: "npm test") }
        panels.refresh()
        let panel = try #require(panels.panel)
        time += 1
        #expect(panel.armed && panel.position == "1 of 3")
        panel.step(-1)
        #expect(panel.request?.id == "r3" && panel.position == "3 of 3" && !panel.armed)
        panel.step(1)
        #expect(panel.request?.id == "r1" && panel.position == "1 of 3")
        time += 1
        panel.allow()
        #expect(source.answers.map(\.0) == ["r1"] && panel.request?.id == "r2" && panel.position == "1 of 2")
    }

    @Test func aQuestionIsAnsweredWithTheChoices() throws {
        let source = FakePrompts()
        let panels = Panels(source: source, shows: false)
        let request = Request(id: "q1", agent: "a1", kind: "question", tool: "AskUserQuestion", about: "Which color?", at: "2026-10-17T09:00:03Z")
        source.prompts = [Prompt(request: request, questions: [
            Question(header: "Color", text: "Which color for the cart page?", options: ["Blue", "Green"], multiple: false),
            Question(header: nil, text: "Which pages?", options: ["Cart", "Home", "Help"], multiple: true),
            Question(header: nil, text: "Anything else?", options: [], multiple: false),
        ])]
        panels.refresh()
        let panel = try #require(panels.panel)
        #expect(panel.title == "An agent asks you a question")
        #expect(panel.boxes.map { $0.map(\.title) } == [["Blue", "Green"], ["Cart", "Home", "Help"], []])
        panel.boxes[0][1].state = .on
        panel.boxes[1][0].state = .on
        panel.boxes[1][2].state = .on
        panel.typed[2].stringValue = "An invented remark."
        panel.reply()
        #expect(source.answers.map(\.0) == ["q1"])
        #expect(source.answers[0].1 == .choice([["Green"], ["Cart", "Help"], ["An invented remark."]]))

        source.prompts = [Prompt(request: Request(id: "q2", agent: "a1", kind: "question", tool: nil, about: nil, at: "2026-10-17T09:00:04Z"),
                                 questions: [Question(header: nil, text: "Go on?", options: ["Yes"], multiple: false)])]
        panels.refresh()
        try #require(panels.panel).cancelOperation(nil)
        #expect(source.answers.last?.0 == "q2" && source.answers.last?.1 == .deny, "Escape leaves a question unanswered")
    }

    /// An invented command of several lines, as long as the mockup's.
    static let long = """
        cd ~/something/spaces && \\
          something check agents --strict --report /tmp/something-check/agents.json && \\
          python3 - <<'EOF'
        import json
        r = json.load(open('/tmp/check/agents.json'))
        print(len(r['errors']), 'errors', sorted(r['agents']), [a['kind'] for a in r['agents'].values()])
        EOF
        """

    func commandPanel(_ input: String = long) throws -> (RequestPanel, CommandBox) {
        let panel = RequestPanel { _ in }
        panel.show(Prompt(request: Request(id: "r1", agent: "a1", kind: "permission", tool: "Bash", about: nil, at: "2026-10-23T18:00:00Z"),
                          input: input), who: Asker(program: "Codex", space: "My agents", assistant: true), age: nil)
        return (panel, try #require(panel.code))
    }

    /// The command breaks only at spaces, never inside `--strict` or a path, at every width; its caption counts its
    /// lines, and its text is what the agent sent. (A word longer than a whole line has to be cut: none is here.)
    @Test func theCommandBreaksOnlyAtSpaces() throws {
        let (panel, code) = try commandPanel()
        #expect(Self.texts(panel.contentView).contains("The exact command · 7 lines") && code.text.string == Self.long)
        for width in [360.0, 392, 560] {
            panel.size(width: width)
            let manager = try #require(code.text.layoutManager), string = code.text.string as NSString
            var starts: [Int] = []
            manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: try #require(code.text.textContainer))) { _, _, _, glyphs, _ in
                starts.append(manager.characterIndexForGlyph(at: glyphs.location))
            }
            #expect(starts.count > 7, "at \(width), the long lines wrap")
            for start in starts where start > 0 {
                let before = Character(UnicodeScalar(string.character(at: start - 1)) ?? " ")
                #expect(before.isWhitespace, "at \(width), a line starts inside a word: \(string.substring(from: start).prefix(20))")
            }
        }
        let (short, box) = try commandPanel("npm test")
        #expect(Self.texts(short.contentView).contains("The exact command") && box.shown == CommandBox.line + 2 * CommandBox.inset)
    }

    /// Copy Command writes the exact text, newlines and all; Why am I asked? opens and closes its sentence.
    @Test func copyAndWhy() throws {
        let (panel, _) = try commandPanel()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("something-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        panel.pasteboard = pasteboard
        func links(_ view: NSView) -> [NSButton] { ((view as? NSButton).map { [$0] } ?? []) + view.subviews.flatMap(links) }
        let buttons = links(try #require(panel.contentView)).filter { ["Copy Command", "Why am I asked?"].contains($0.title) }
        #expect(buttons.count == 2)
        buttons[0].performClick(nil)
        #expect(pasteboard.string(forType: .string) == Self.long && buttons[0].title == "Copied")
        let height = panel.frame.height
        buttons[1].performClick(nil)
        #expect(Self.texts(panel.contentView).last?.hasPrefix("Codex is this space's assistant: it may change your spaces and run something's own commands without asking; everything else it does asks you") == true)
        #expect(panel.frame.height > height && buttons[1].isAccessibilityExpanded())
        buttons[1].performClick(nil)
        #expect(panel.frame.height == height && !buttons[1].isAccessibilityExpanded())
        // A trailing newline ends the one line; it does not make two.
        let one = CommandBox("ls\n", target: panel, action: #selector(RequestPanel.expand))
        #expect(Self.texts(one).contains("The exact command") && one.text.string == "ls\n")
    }

    /// ↕ makes the panel 560 wide and shows the whole command, within the screen, its footer in sight; again, it folds
    /// back to 392 and four lines. The grip sizes it between 360 and 720 points wide, its top-left corner staying put.
    @Test func expandAndTheGrip() throws {
        let (panel, code) = try commandPanel()
        #expect(panel.frame.width == RequestPanel.width && code.shown == CommandBox.folded && code.full > CommandBox.folded)
        let folded = panel.frame
        code.expand.performClick(nil)
        #expect(panel.sized && panel.frame.width == RequestPanel.wide && code.shown >= code.full && panel.frame.maxY == folded.maxY)
        code.expand.performClick(nil)
        #expect(!panel.sized && panel.frame == folded && code.shown == CommandBox.folded)

        // A longer command than the screen holds: the panel stops 16 points above the screen's bottom.
        let window = NSWindow(contentRect: NSRect(x: 120, y: 102, width: 1200, height: 760), styleMask: [.titled], backing: .buffered, defer: true)
        let (tall, box) = try commandPanel(String(repeating: "echo one line of an invented script\n", count: 80))
        let desk = NSRect(x: 0, y: 0, width: 1440, height: 875)
        tall.place(beside: window, screen: desk)
        box.expand.performClick(nil)
        #expect(tall.frame.minY == desk.minY + 16 && box.shown < box.full && tall.frame.maxX > window.frame.maxX)

        let grip = try #require(panel.contentView?.subviews.compactMap { $0 as? Grip }.first)
        panel.setFrameOrigin(NSPoint(x: 100, y: 100))
        let top = panel.frame.maxY
        func drag(by x: Double, _ y: Double) throws {
            let frame = panel.frame
            func mouse(_ type: NSEvent.EventType, _ dx: Double, _ dy: Double) throws -> NSEvent {
                try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: frame.width - 4 + dx, y: 4 - dy), modifierFlags: [], timestamp: 0,
                                                windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            }
            grip.mouseDown(with: try mouse(.leftMouseDown, 0, 0))
            grip.mouseDragged(with: try mouse(.leftMouseDragged, x, y))
            grip.mouseUp(with: try mouse(.leftMouseUp, x, y))
        }
        try drag(by: 1000, 200)
        #expect(panel.sized && panel.frame.width == 720 && panel.frame.maxY == top && panel.frame.minX == 100)
        try drag(by: -1000, 0)
        #expect(panel.frame.width == 360 && panel.frame.maxY == top)
        // A new request keeps the size the person gave the panel.
        panel.show(FakePrompts().permission("r2", about: "npm test"), who: Asker(program: "Codex"), age: nil)
        #expect(panel.frame.width == 360 && panel.sized)
    }

    /// A long name, folder and command wrap: the panel keeps its width instead of growing past the screen.
    @Test func aLongRequestKeepsThePanelsWidth() throws {
        let who = Asker(program: "Claude Code", space: "Morning review", name: "an-invented-agent-name-that-goes-on",
                        folder: "~/code/clients/example-agency/" + String(repeating: "a-very-deep-folder/", count: 10) + "website")
        let input = "npm test -- " + String(repeating: "--an-invented-flag ", count: 20)
        let panel = RequestPanel { _ in }
        panel.show(Prompt(request: Request(id: "r1", agent: "a1", kind: "permission", tool: "Bash", about: nil, at: "2026-10-17T09:00:01Z"),
                          input: input), who: who, age: "asked 2 hours ago")
        #expect(panel.frame.width == RequestPanel.width)
    }

    /// The panel's title says what the agent wants, by its tool; under it, the space, who asks and when; then where it
    /// acts: the space and the folder, from the home folder.
    @Test func thePanelSaysWhatAndWho() throws {
        let cases: [(String?, String)] = [("Bash", "run a command"), ("commandExecution", "run a command"), ("execute", "run a command"),
                                          ("Edit", "change a file"), ("fileChange", "change a file"), ("permissions", "change its permissions"),
                                          ("WebFetch", "use WebFetch"), (nil, "do something that needs your permission")]
        for (tool, words) in cases { #expect(Words.wants(tool) == words, "\(tool ?? "nil")") }
        var agent = Agent(id: "a1", kind: "claude", origin: "launched")
        (agent.name, agent.folder) = ("shop", "/Users/example/code/shop")
        let shop = App.who(agent, space: "My agents", home: "/Users/example")
        #expect(shop == Asker(program: "Claude Code", space: "My agents", name: "shop", folder: "~/code/shop"))
        #expect(App.who(nil, space: nil, home: "/Users/example") == Asker(program: "An agent"))
        agent.folder = "/Users/example/something/spaces"
        let assistant = App.who(agent, space: "Daily brief", home: "/Users/example", assistant: true)
        #expect(assistant == Asker(program: "Claude Code", space: "Daily brief", assistant: true, folder: "~/something/spaces"))
        let panel = RequestPanel { _ in }
        panel.show(FakePrompts().permission("r1", about: "npm test"), who: assistant, age: "asked 3 min ago")
        #expect(panel.title == "Claude Code wants to run a command")
        func sign(_ view: NSView) -> SignView? { view as? SignView ?? view.subviews.lazy.compactMap(sign).first }
        #expect(panel.contentView.flatMap(sign)?.accessibilityLabel()?.hasPrefix("Claude Code is waiting, ") == true)
        #expect(Self.texts(panel.contentView) == ["something", "·  Permission", "", "Claude Code wants to run a command",
                                                  "Daily brief · its assistant · asked 3 min ago", "It will run one command in the Daily brief space.",
                                                  "Space", "Daily brief", "Folder", "~/something/spaces", "The exact command", "npm test"])
    }

    func request(_ id: String, agent: String = "a1", at: String = "2026-10-23T18:00:00Z") -> Request {
        Request(id: id, agent: agent, kind: "permission", tool: "Bash", about: nil, at: at)
    }

    /// One queue: in the order the requests came, steps that wrap, a withdrawn request leaves, an answered one never
    /// comes back, and the one on screen stays on screen while the others come and go.
    @Test func theQueueKeepsArrivalOrderAndWraps() {
        let queue = RequestQueue()
        #expect(queue.shown == nil && queue.position == nil)
        queue.follow([request("r2", at: "2026-10-23T18:05:00Z")])
        queue.follow([request("r2", at: "2026-10-23T18:05:00Z"), request("r1"), request("r3")])
        #expect(queue.waiting.map(\.id) == ["r2", "r1", "r3"], "the order they came, not their dates")
        #expect(queue.shown?.id == "r2" && queue.position == "1 of 3")
        queue.step(-1)
        #expect(queue.shown?.id == "r3" && queue.position == "3 of 3", "back from the first wraps to the last")
        queue.step(1)
        #expect(queue.shown?.id == "r2", "on from the last wraps to the first")
        queue.step(2)
        queue.follow([request("r1"), request("r3")])
        #expect(queue.shown?.id == "r3" && queue.position == "2 of 2", "a request withdrawn before it keeps the one on screen")
        queue.follow([request("r1")])
        #expect(queue.shown?.id == "r1" && queue.position == nil, "the one on screen withdrawn: the next takes its place")
        queue.answer("r1")
        #expect(queue.waiting.isEmpty && queue.shown == nil)
        queue.follow([request("r1"), request("r4")])
        #expect(queue.waiting.map(\.id) == ["r4"], "an answered request still in the state never comes back")
        queue.follow([request("r4")])
        queue.follow([request("r1"), request("r4")])
        #expect(queue.waiting.map(\.id) == ["r4", "r1"], "once the agent took the answer, the same id is a new request")
        queue.step(1)
        queue.follow([])
        #expect(queue.shown == nil && queue.waiting.isEmpty)
    }

    /// The counts: all requests for the Dock and the chip; a space's own for its sticker, by the space that launched
    /// the agent, and for the assistant by the space it works on.
    @Test func eachSpaceCountsItsOwnRequests() {
        var place = AssistantModel.Place.space(title: "Daily brief", name: "brief", page: "/Users/example/something/spaces/brief/index.html")
        var launches = ["agents": Set(["a1"]), "project": ["a2"]]
        let queue = RequestQueue()
        queue.space = { RequestQueue.space(of: $0.agent, assistant: $0.agent == "assistant", place: place, launches: launches) }
        queue.follow([request("r1"), request("r2", agent: "a2"), request("r3", agent: "a1"), request("r4", agent: "assistant"),
                      request("r5", agent: "a9")])
        #expect(queue.waiting.count == 5, "an agent started by hand is counted in all")
        #expect(queue.count(in: "agents") == 2 && queue.count(in: "project") == 1 && queue.count(in: "brief") == 1)
        place = .blank
        #expect(queue.count(in: "brief") == 0, "the assistant on the blank page belongs to no space")
        place = .space(title: "Logbook", name: "logbook", page: "/Users/example/something/spaces/logbook/index.html")
        #expect(queue.count(in: "logbook") == 1, "the assistant's request follows where it works")
        queue.answer("r3")
        #expect(queue.count(in: "agents") == 1 && queue.waiting.count == 4)
        launches["project", default: []].insert("a9")
        #expect(queue.count(in: "project") == 2, "an agent a space launches after its request came is counted there")
    }

    /// A request still in the state whose details are gone has closed: it gets no panel and is not counted.
    @Test func aRequestWithoutDetailsGetsNoPanel() {
        let source = FakePrompts()
        source.prompts = [source.permission("r1", about: "npm test")]
        source.gone = [Request(id: "r0", agent: "a1", kind: "permission", tool: "Bash", about: nil, at: "2026-10-17T09:00:00Z")]
        let panels = Panels(source: source, shows: false)
        panels.refresh()
        #expect(panels.panel?.request?.id == "r1" && panels.queue.waiting.map(\.id) == ["r1"])
        panels.refresh()
        #expect(panels.queue.waiting.map(\.id) == ["r1"] && source.answers.isEmpty, "never shown, never answered")
    }

    /// The quit sheet says how many agents stop, in the singular and the plural, the person's assistant first.
    @Test func theQuitSheetSaysWhoStops() {
        #expect(Ask.quit(1).informativeText == "An agent something started is still running. Quitting stops it.")
        #expect(Ask.quit(2).informativeText == "2 agents something started are still running. Quitting stops them.")
        #expect(Ask.quit(1, assistant: true).informativeText == "Your assistant is still running. Quitting stops it.")
        #expect(Ask.quit(2, assistant: true).informativeText == "Your assistant and 1 other agent something started are still running. Quitting stops them.")
        #expect(Ask.quit(3, assistant: true).informativeText == "Your assistant and 2 other agents something started are still running. Quitting stops them.")
    }

    /// The sheets the app waits for (the rights, a link, an export) mean what their buttons say, the second of the
    /// export being With Its Data. The modal loop itself is not run: in this process, which never ran NSApp, runModal
    /// and a modal session alike end the whole test run quietly (it still exits 0).
    @Test func theSheetsButtonsMeanWhatTheySay() {
        #expect(Ask.withData("board", keys: ["seen"], bytes: 12).buttons.map(\.title) == ["Without Data", "With Its Data", "Cancel"])
        #expect(NativeAsk.withDataChoice(.alertFirstButtonReturn) == false && NativeAsk.withDataChoice(.alertSecondButtonReturn) == true)
        #expect(NativeAsk.withDataChoice(.alertThirdButtonReturn) == nil && NativeAsk.withDataChoice(nil) == nil)
        #expect(Ask.link(URL(string: "https://example.com")!, space: "board").buttons.map(\.title)
                == ["Open", "Cancel", "Block Links Until Reload"])
        #expect(NativeAsk.linkChoice(.alertFirstButtonReturn) == .open && NativeAsk.linkChoice(.alertSecondButtonReturn) == .cancel)
        #expect(NativeAsk.linkChoice(.alertThirdButtonReturn) == .block && NativeAsk.linkChoice(nil) == .cancel)
        #expect(NativeAsk.agreed(.alertFirstButtonReturn) && !NativeAsk.agreed(.alertSecondButtonReturn) && !NativeAsk.agreed(nil))
    }

    /// A sheet asked for with no window, or while another sheet is up, is answered as Escape would, and begins none:
    /// one question at a time. Its window is offscreen and the app inactive: nothing is shown and the focus is not taken.
    @Test func aSecondSheetIsAnsweredAsEscapeWould() throws {
        let ask = NativeAsk()
        #expect(ask.withData("board", keys: [], bytes: 0) == nil, "no window")
        let offscreen = Offscreen(NSView())
        ask.window = { offscreen.window }
        let first = Ask.trash("board")
        first.beginSheetModal(for: offscreen.window) { _ in }
        defer { offscreen.window.endSheet(first.window) }
        #expect(ask.withData("board", keys: ["seen"], bytes: 12) == nil)
        #expect(ask.link(URL(string: "https://example.com")!, space: "board") == .cancel)
        #expect(offscreen.window.attachedSheet === first.window, "no second sheet began")
        #expect(!NSApp.isActive)
    }
}
