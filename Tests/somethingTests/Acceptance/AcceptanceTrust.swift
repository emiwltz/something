// Acceptance scenarios of what asks the person: the request panel and its queue, the Dock, the sheets and the quit alerts
// (e1–e9, e13–e15). Key-window and focus claims are not asserted offscreen: each slice lists them for the hand trial.
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import SomethingAgents
import SomethingCore
import Testing
import WebKit
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-trust-"))
struct AcceptanceTrust {
    /// The desk the pictures stand on, as the mockup's: a 1440x900 screen under a 25-point menu bar, the main window at
    /// its "large" place. Offscreen windows have no screen of their own.
    static let desk = NSRect(x: 0, y: 0, width: 1440, height: 875), large = NSPoint(x: 120, y: 102)

    /// The panel's requests, asked by the mockup's agents: Codex for My agents' assistant, then Claude Code for Project
    /// watch and pi for Logbook; `ago` minutes ago each.
    static func request(_ id: String, _ ago: [Int], in source: FakePrompts, command: String = short) {
        for (index, minutes) in ago.enumerated() {
            let at = iso8601.string(from: Stage.now.addingTimeInterval(-60 * Double(minutes)))
            source.prompts.append(Prompt(request: Request(id: "\(id)\(index + 1)", agent: "a\(index + 1)", kind: "permission", tool: "Bash",
                                                          about: nil, at: at), input: command))
        }
    }

    static let short = "cd ~/something/spaces && something check agents --strict --report /tmp/something-check/agents.json && python3 -c \"import json; print(1)\""
    /// The mockup's long command, fourteen lines.
    static let long = #"""
        cd ~/something/spaces && \
          something check agents --strict \
            --report /tmp/something-check/agents.json && \
          python3 - <<'EOF'
        import json, pathlib
        r = json.load(open('/tmp/something-check/agents.json'))
        counts = {k: len(v) for k, v in r['agents'].items()}
        herdr = json.load(open(pathlib.Path.home() / '.herdr/state.json'))
        for kind, n in counts.items():
            seen = sum(1 for a in herdr['agents'] if a['kind'] == kind)
            flag = 'ok' if seen == n else 'DIFF'
            print(f"{kind:<12} page={n:<3} herdr={seen:<3} {flag}")
        print(len(r['errors']), 'errors')
        EOF
        """#

    /// Panels on the Stage's clock, their requests asked by the agents `request` names.
    static func panels(_ source: FakePrompts) -> Panels {
        let panels = Panels(source: source, shows: false)
        panels.now = { Stage.now }
        let agents = [("codex", "My agents", "/Users/example/something/spaces", true), ("claude", "Project watch", "/Users/example/code/watch", false),
                      ("pi", "Logbook", "/Users/example/notes", false)]
        panels.who = { request in
            let (kind, space, folder, assistant) = agents[(Int(request.agent.dropFirst()) ?? 1) - 1]
            var agent = Agent(id: request.agent, kind: kind, origin: "launched")
            (agent.name, agent.folder) = (assistant ? nil : "watcher", folder)
            return App.who(agent, space: space, home: "/Users/example", assistant: assistant, building: assistant)
        }
        return panels
    }

    @Test("e1: the request panel") func e1() async throws {
        let stage = try Stage("trust")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        shell.window.setFrameOrigin(Self.large)
        let agents = try await stage.open("agents", in: shell, library)
        defer { agents.close() }
        let source = FakePrompts()
        Self.request("r", [0], in: source)
        var time: TimeInterval = 100
        let panels = Self.panels(source)
        panels.clock = { time }
        panels.refresh()
        let panel = try #require(panels.panel)
        panel.place(beside: shell.window, screen: Self.desk)
        #expect(panel.title == "Codex wants to run a command" && panel.position == nil)
        #expect(PanelsTests.texts(panel.contentView).starts(with: ["something", "·  Permission", "", "Codex wants to run a command",
                                                                   "My agents · its assistant · just now", "It will run one command in the My agents space.",
                                                                   "Space", "My agents", "Folder", "~/something/spaces", "The exact command"]))
        // Across the window's top-right corner, half outside it, below the toolbar.
        let window = shell.window.frame, toolbar = window.height - shell.window.contentLayoutRect.maxY
        #expect(panel.frame.width == RequestPanel.width && panel.frame.minX < window.maxX && panel.frame.maxX > window.maxX)
        #expect(panel.frame.maxY == window.maxY - toolbar - 8)
        #expect(panel.styleMask.contains(.nonactivatingPanel) && panel.level == .floating && panel.worksWhenModal && !panel.isKeyWindow)
        #expect(panel.allowButton.title == "Allow Once" && panel.denyButton.title == "Deny" && panel.denyButton.keyEquivalent == "\u{1b}")
        #expect(panel.standardWindowButton(.closeButton)?.accessibilityLabel() == "Close: deny")
        // Arming: the fill half across, then the button takes a click.
        time += 0.25
        panel.tick()
        #expect(!panel.allowButton.isEnabled && panel.allowButton.progress == 0.5 && !panel.armed)
        try await stage.appearances { suffix in
            if suffix.isEmpty { try await Picture.panel(panel, over: shell, library: library, web: agents.web, "e1-arming", root: stage.home.root) }
        }
        time += 0.25
        panel.tick()
        #expect(panel.allowButton.isEnabled && panel.armed)
        try await stage.appearances { suffix in
            try await Picture.panel(panel, over: shell, library: library, web: agents.web, "e1" + suffix, root: stage.home.root)
        }
        panel.allow()
        #expect(source.answers.map(\.1) == [.once] && panels.panel == nil)
    }
    /// A command of fourteen lines, expanded by ↕: the panel 560 wide shows all of it, still across the window's
    /// corner below the toolbar, its footer in sight.
    @Test("e2: the command box") func e2() async throws {
        let stage = try Stage("trust")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        shell.window.setFrameOrigin(Self.large)
        let agents = try await stage.open("agents", in: shell, library)
        defer { agents.close() }
        let source = FakePrompts()
        Self.request("r", [0], in: source, command: Self.long)
        var time: TimeInterval = 100
        let panels = Self.panels(source)
        panels.clock = { time }
        panels.refresh()
        let panel = try #require(panels.panel), code = try #require(panel.code)
        panel.place(beside: shell.window, screen: Self.desk)
        time += 1
        panel.tick()
        #expect(PanelsTests.texts(panel.contentView).contains("The exact command · 14 lines") && code.text.string == Self.long)
        #expect(code.shown == CommandBox.folded && code.full > code.shown, "folded to four lines, the last one fading")
        #expect(code.expand.image?.accessibilityDescription == "Expand the command")
        code.expand.performClick(nil)
        let window = shell.window.frame, toolbar = window.height - shell.window.contentLayoutRect.maxY
        #expect(panel.sized && panel.frame.width == RequestPanel.wide && code.shown >= code.full)
        #expect(code.expand.accessibilityLabel() == "Fold the command")
        // As in the picture: at 560 the 14 source lines stand on 14 lines, none wrapped.
        let manager = try #require(code.text.layoutManager)
        var fragments = 0
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { _, _, _, _, _ in fragments += 1 }
        #expect(fragments == 14)
        #expect(panel.frame.minX < window.maxX && panel.frame.maxX > window.maxX && panel.frame.maxY == window.maxY - toolbar - 8)
        #expect(panel.frame.minY >= Self.desk.minY + 16 && panel.allowButton.isEnabled, "the footer stays in sight")
        try await stage.appearances { suffix in
            try await Picture.panel(panel, over: shell, library: library, web: agents.web, "e2" + suffix, root: stage.home.root)
        }
        code.expand.performClick(nil)
        #expect(!panel.sized && panel.frame.width == RequestPanel.width && code.shown == CommandBox.folded)
        #expect(code.expand.accessibilityLabel() == "Expand the command")
    }
    @Test("e3: the request queue") func e3() async throws {
        let stage = try Stage("trust")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        shell.window.setFrameOrigin(Self.large)
        let agents = try await stage.open("agents", in: shell, library)
        defer { agents.close() }
        let source = FakePrompts()
        Self.request("r", [34, 12, 2], in: source)
        var time: TimeInterval = 100
        let panels = Self.panels(source)
        panels.clock = { time }
        panels.refresh()
        let panel = try #require(panels.panel)
        panel.place(beside: shell.window, screen: Self.desk)
        #expect(panel.position == "1 of 3" && panel.header.of.stringValue == "1 of 3")
        #expect(PanelsTests.texts(panel.contentView).contains("My agents · its assistant · asked 34 min ago"))
        // The steps, as the header's arrows press them: on to the second, which arms again, and back.
        time += 1
        let arrows = panel.header.subviews.flatMap(\.subviews).flatMap(\.subviews).compactMap { $0 as? NSButton }
        #expect(arrows.map { $0.image?.accessibilityDescription } == ["Previous request", "Next request"])
        arrows[1].performClick(nil)
        #expect(panel.request?.id == "r2" && panel.position == "2 of 3" && !panel.armed)
        #expect(panel.title == "Claude Code wants to run a command")
        #expect(PanelsTests.texts(panel.contentView).contains("Project watch · “watcher” · asked 12 min ago"))
        arrows[0].performClick(nil)
        #expect(panel.request?.id == "r1" && panel.position == "1 of 3")
        time += 1
        panel.tick()
        try await stage.appearances { suffix in
            try await Picture.panel(panel, over: shell, library: library, web: agents.web, "e3" + suffix, root: stage.home.root)
        }
        panel.allow()
        #expect(source.answers.map(\.0) == ["r1"] && panel.request?.id == "r2" && panel.position == "1 of 2")
    }
    @Test("e4: Show Request", .disabled("not built yet: T5")) func e4() async throws {}
    @Test("e5: the Dock badge", .disabled("not built yet: T6")) func e5() async throws {}
    /// Daily brief's assistant asks where the weather corner goes: the same panel, at the same place, its options
    /// numbered; a click on the second answers with it.
    @Test("e6: a question") func e6() async throws {
        let stage = try Stage("trust")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        shell.window.setFrameOrigin(Self.large)
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        let source = FakePrompts()
        let options = ["Top right, next to the date", "In the strip, after “In brief”", "Leave it out for now"]
        source.prompts = [Prompt(request: Request(id: "q1", agent: "a1", kind: "question", tool: "AskUserQuestion", about: nil,
                                                  at: iso8601.string(from: Stage.now)),
                                 questions: [Question(header: nil, text: "Where should the weather corner go?", options: options, multiple: false)])]
        let panels = Panels(source: source, shows: false)
        var time: TimeInterval = 100
        (panels.now, panels.clock) = ({ Stage.now }, { time })
        panels.who = { _ in App.who(Agent(id: "a1", kind: "claude", origin: "launched"), space: "Daily brief", home: "/Users/example", assistant: true) }
        panels.refresh()
        let panel = try #require(panels.panel)
        panel.place(beside: shell.window, screen: Self.desk)
        #expect(panel.title == "Claude Code asks you a question" && panel.header.kind == "Question")
        #expect(PanelsTests.texts(panel.contentView) == ["something", "·  Question", "", "Claude Code asks you a question",
                                                         "Daily brief · its assistant · just now", "Where should the weather corner go?",
                                                         "", "The space can't see this window."])
        #expect(panel.boxes[0].map(\.title) == options && panel.boxes[0].map(\.number) == [1, 2, 3])
        #expect(panel.typed[0].placeholderString == "Or type your answer" && panel.denyButton.title == "Don't Answer")
        let window = shell.window.frame, toolbar = window.height - shell.window.contentLayoutRect.maxY
        #expect(panel.frame.width == RequestPanel.width && panel.frame.minX < window.maxX && panel.frame.maxX > window.maxX)
        #expect(panel.frame.maxY == window.maxY - toolbar - 8 && !panel.isKeyWindow)
        try await stage.appearances { suffix in
            try await Picture.panel(panel, over: shell, library: library, web: brief.web, "e6" + suffix, root: stage.home.root)
        }
        panel.boxes[0][1].performClick(nil)
        #expect(source.answers.isEmpty, "a click before the panel armed answers nothing")
        time += RequestPanel.arming
        panel.boxes[0][1].performClick(nil)
        #expect(source.answers.map(\.0) == ["q1"] && source.answers[0].1 == .choice([[options[1]]]) && panels.panel == nil)
    }
    @Test("e7: the link sheet", .disabled("not built yet: T7")) func e7() async throws {}
    @Test("e8: the trash sheet", .disabled("not built yet: T8")) func e8() async throws {}
    @Test("e9: quit while assistants work", .disabled("not built yet: T9")) func e9() async throws {}
    /// Full screen cannot be entered offscreen: the window is drawn at the screen's size, and the panel placed as it is
    /// for a window in full screen, at the screen's top right below the toolbar.
    @Test("e13: the panel in full screen") func e13() async throws {
        let stage = try Stage("trust")
        defer { stage.remove() }
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let (shell, library, _) = stage.window(screen.size)
        shell.window.setFrameOrigin(.zero)
        let agents = try await stage.open("agents", in: shell, library)
        defer { agents.close() }
        let source = FakePrompts()
        Self.request("r", [0], in: source)
        let panels = Self.panels(source)
        var time: TimeInterval = 100
        panels.clock = { time }
        panels.refresh()
        let panel = try #require(panels.panel)
        time += 1
        panel.tick()
        let toolbar = shell.window.frame.height - shell.window.contentLayoutRect.maxY
        panel.setFrameOrigin(RequestPanel.place(panel.frame.size, window: shell.window.frame, toolbar: toolbar, screen: screen, fullScreen: true))
        #expect(panel.frame.maxX == screen.maxX - 16 && panel.frame.maxY == screen.maxY - toolbar - 8)
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary), "it shows over a window in full screen")
        #expect(panel.title == "Codex wants to run a command" && panel.allowButton.isEnabled)
        try await stage.appearances { suffix in
            try await Picture.panel(panel, over: shell, library: library, web: agents.web, "e13" + suffix, root: stage.home.root)
        }
    }
    @Test("e14: the panel over the welcome", .disabled("not built yet: AB17w")) func e14() async throws {}
    @Test("e15: quit with requests", .disabled("not built yet: T9")) func e15() async throws {}
}

extension Picture {
    /// The main window and the request panel on one canvas, as they stand on the screen, with 40 points of desk
    /// around them: the panel is a window of its own and overhangs the main one. The window is drawn as `window`
    /// draws it; the panel by its frame, its corners and its shadow, which the window server draws, reconstructed.
    static func panel(_ panel: RequestPanel, over shell: Shell, library: Library, web: WKWebView?, _ name: String, root: URL) async throws {
        guard let gallery else { return }
        try await window(shell, library: library, web: web, name + "-window", root: root)
        let file = gallery.appendingPathComponent(name + "-window.png")
        defer { try? FileManager.default.removeItem(at: file) }
        let image = try #require(NSImage(contentsOf: file))
        let frame = try #require(panel.contentView?.superview)
        disguise(frame, root.path)
        frame.layoutSubtreeIfNeeded()
        let drawn = try bitmap(frame.bounds.size)
        frame.cacheDisplay(in: frame.bounds, to: drawn)
        let canvas = shell.window.frame.union(panel.frame).insetBy(dx: -40, dy: -40)
        let place = panel.frame.offsetBy(dx: -canvas.minX, dy: -canvas.minY)
        try png(of: canvas.size, name) {
            Look.Token.bg.color.setFill()
            NSRect(origin: .zero, size: canvas.size).fill()
            image.draw(in: shell.window.frame.offsetBy(dx: -canvas.minX, dy: -canvas.minY))
            let shape = NSBezierPath(roundedRect: place, xRadius: Look.window, yRadius: Look.window)
            for shade in Look.float(NSAppearance.currentDrawing()) {
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                (shadow.shadowColor, shadow.shadowOffset, shadow.shadowBlurRadius) = (shade.color, NSSize(width: 0, height: -shade.y), shade.blur)
                shadow.set()
                Look.Token.bg2.color.setFill()
                shape.fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            drawn.draw(in: place, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            Look.Token.line2.color.setStroke()
            shape.stroke()
        }
    }
}
