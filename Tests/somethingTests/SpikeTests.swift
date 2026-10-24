// Block 2's spikes SP5, SP6, SP7 and SP8: the smallest prototypes that answer what block 2 stands on. Each answer is
// written in the commit that adds this file; the file is test code only and is removed at the end of the phase.
// Every window is offscreen at alpha 0 and never ordered front: the app never becomes active. What a never-shown
// window cannot prove (key window, the welcome's inert main window, a real permission prompt) is a hand trial.
import AppKit
import SomethingAgents
import SomethingCore
import SwiftUI
import Testing
@testable import something

/// The card's model: whether it is open, which its view's opacity follows.
@Observable private final class CardModel { var open = false }

/// A card that fades with its model; its frame is the host's, animated by AppKit.
private struct CardView: View {
    let model: CardModel
    var body: some View {
        RoundedRectangle(cornerRadius: 14).fill(Color.red).opacity(model.open ? 1 : 0).animation(.easeOut(duration: 0.2), value: model.open)
    }
}

/// The card's host, recording each frame AppKit gives it on the way: setFrame sets the size, then the origin.
private final class CardHost: NSHostingView<CardView> {
    var frames: [NSRect] = []
    override func setFrameOrigin(_ origin: NSPoint) {
        super.setFrameOrigin(origin)
        frames.append(frame)
    }
}

/// A sticker moved by a drag made of the three overrides, never a tracking loop of `nextEvent`, so that a test can
/// drive it by calling them.
private final class Draggable: NSView {
    private var start: NSPoint?, origin = NSPoint.zero
    override func mouseDown(with event: NSEvent) { (start, origin) = (event.locationInWindow, frame.origin) }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        setFrameOrigin(NSPoint(x: origin.x + event.locationInWindow.x - start.x, y: origin.y + event.locationInWindow.y - start.y))
    }
    override func mouseUp(with event: NSEvent) { start = nil }
}

/// The welcome's view, which takes Return (start) and Escape (later) as the focus, through the key bindings: a bare
/// NSView's keyDown never turns Escape into cancelOperation by itself.
private final class Welcome: NSView {
    var heard: [String] = []
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { interpretKeyEvents([event]) }
    override func insertNewline(_ sender: Any?) { heard.append("start") }
    override func cancelOperation(_ sender: Any?) { heard.append("later") }
}

/// What App would answer for New Space: greyed while the welcome is open, as Keys says otherwise.
private final class NewSpaceTarget: NSObject, NSMenuItemValidation {
    var welcoming = false, made = 0
    @objc func newSpace(_ sender: Any?) { made += 1 }
    func validateMenuItem(_ item: NSMenuItem) -> Bool { !welcoming && Keys.enabled("new", Keys.Situation()) }
}

/// The Engine as Panels sees it once a building assistant answers its own questions inline: those questions are not
/// the panel's; everything else, its permissions included, is.
private final class Elsewhere: PromptSource {
    let engine: Engine
    let inline: (Request) -> Bool
    init(_ engine: Engine, inline: @escaping (Request) -> Bool) { (self.engine, self.inline) = (engine, inline) }
    var requests: [Request] { engine.state.requests.filter { !inline($0) } }
    func prompt(_ request: String) -> Prompt? { engine.prompt(request).flatMap { inline($0.request) ? nil : $0 } }
    func answer(_ request: String, _ answer: Answer) throws { try engine.answer(request, answer) }
}

@MainActor private func mouse(_ type: NSEvent.EventType, _ point: NSPoint, in window: NSWindow) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
}

@MainActor private func key(_ characters: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = [], in window: NSWindow) throws -> NSEvent {
    try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: window.windowNumber, context: nil, characters: characters,
                                  charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
}

/// A drag in a never-shown window: the view the hit test finds gets the three calls, as AppKit would route them.
@MainActor private func drag(from: NSPoint, to: NSPoint, in window: NSWindow, steps: Int = 4) throws {
    let view = try #require(window.contentView?.hitTest(from))
    view.mouseDown(with: try mouse(.leftMouseDown, from, in: window))
    for step in 1...steps {
        let t = Double(step) / Double(steps)
        view.mouseDragged(with: try mouse(.leftMouseDragged, NSPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t), in: window))
    }
    view.mouseUp(with: try mouse(.leftMouseUp, to, in: window))
}

/// A never-shown titled window holding `view`.
@MainActor private func titled(_ view: NSView, width: Double, height: Double) -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: width, height: height),
                          styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
    (window.alphaValue, window.isReleasedWhenClosed, window.contentView) = (0, false, view)
    return window
}

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-spike-")) struct SpikeTests {
    init() { NSApplication.shared.setActivationPolicy(.prohibited) }

    /// SP5. The card grows from the sticker's corner and shrinks back into it: the host's frame animated by
    /// NSAnimationContext, its opacity from an @Observable flag, no matched geometry. The corner stays put on the way,
    /// the final frame is exact, and nothing is left behind: no animation, no snapshot, no extra view or layer.
    @Test func theCardGrowsFromTheStickersCorner() async throws {
        let center = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 760)), window = titled(center, width: 1200, height: 760)
        defer { window.close() }
        center.wantsLayer = true
        let sticker = NSView(frame: NSRect(x: 1136, y: 20, width: 44, height: 44))
        center.addSubview(sticker)
        let model = CardModel()
        let card = CardHost(rootView: CardView(model: model)), target = NSRect(x: 820, y: 20, width: 360, height: 420)
        // From the sticker's bottom right corner, the card's own.
        card.frame = sticker.frame
        center.addSubview(card)
        card.frames = []
        func animate(to frame: NSRect, open: Bool) async -> Bool {
            var done = false
            model.open = open
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.allowsImplicitAnimation = true
                card.animator().frame = frame
            } completionHandler: { done = true }
            return await wait(5) { done }
        }
        #expect(await animate(to: target, open: true), "the grow ended")
        #expect(card.frame == target, "the final frame is exact")
        let between = card.frames.dropLast().filter { $0 != target }
        // AppKit steps the frame from the run loop: a busy run may skip straight to the end, so the steps are only
        // checked when there are some.
        #expect(between.allSatisfy { $0.maxX == target.maxX && $0.minY == target.minY }, "the corner stays put: \(between)")
        #expect(between.allSatisfy { $0.width > 44 && $0.width < 360 && $0.height > 44 && $0.height < 420 })
        #expect(card.layer?.animationKeys()?.isEmpty ?? true, "no animation remains")
        // The opacity follows the flag: the card's middle is drawn once open, and clear once closed.
        func alpha() async throws -> CGFloat {
            await wait(0.4)
            let bitmap = try #require(card.bitmapImageRepForCachingDisplay(in: card.bounds))
            card.cacheDisplay(in: card.bounds, to: bitmap)
            return bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.alphaComponent ?? -1
        }
        #expect(try await alpha() > 0.9, "the open card is drawn")
        card.frames = []
        #expect(await animate(to: sticker.frame, open: false), "the shrink ended")
        #expect(card.frame == sticker.frame)
        #expect(try await alpha() < 0.1, "the closed card is clear")
        #expect(card.frames.dropLast().allSatisfy { $0.maxX == target.maxX && $0.minY == target.minY })
        card.removeFromSuperview()
        #expect(center.subviews == [sticker], "no snapshot or extra view is left")
        #expect(center.layer?.sublayers?.map { $0 === sticker.layer } == [true], "no layer is left")
    }

    /// SP6. A drag in a never-shown window: the sticker's drag, written with the three overrides, follows the calls a
    /// test makes to them, as it follows the window server's events. The window itself would drop them (SP1).
    @Test func aDragInANeverShownWindow() throws {
        let center = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 760)), window = titled(center, width: 1200, height: 760)
        defer { window.close() }
        let sticker = Draggable(frame: NSRect(x: 1136, y: 20, width: 44, height: 44))
        center.addSubview(sticker)
        try drag(from: NSPoint(x: 1150, y: 40), to: NSPoint(x: 650, y: 400), in: window)
        #expect(sticker.frame.origin == NSPoint(x: 636, y: 380), "the sticker moved by the drag")
        window.sendEvent(try mouse(.leftMouseDown, NSPoint(x: 650, y: 400), in: window))
        window.sendEvent(try mouse(.leftMouseDragged, NSPoint(x: 100, y: 100), in: window))
        window.sendEvent(try mouse(.leftMouseUp, NSPoint(x: 100, y: 100), in: window))
        #expect(sticker.frame.origin == NSPoint(x: 636, y: 380), "the window does not route what it is sent")
    }

    /// SP7. The welcome window takes its keys though never shown: the events it is sent reach its focus. While it is
    /// open, New Space is greyed in the real menu bar and ⌘N does nothing; once it closes, ⌘N works. The notification
    /// seam stays shut in swift test, which has no app bundle. The main window's inertness is a hand trial.
    @Test func theWelcomeTakesItsKeysAndGreysNewSpace() throws {
        let welcome = Welcome(frame: NSRect(x: 0, y: 0, width: 720, height: 480)), window = titled(welcome, width: 720, height: 480)
        defer { window.close() }
        window.makeFirstResponder(welcome)
        #expect(window.firstResponder === welcome)
        window.sendEvent(try key("\r", 36, in: window))
        window.sendEvent(try key("\u{1b}", 53, in: window))
        #expect(welcome.heard == ["start", "later"], "the keys sent to the window reach its focus")

        let saved = NSApp.mainMenu, target = NewSpaceTarget()
        defer { NSApp.mainMenu = saved }
        let menu = Keys.menu()
        NSApp.mainMenu = menu
        let items = menu.items.flatMap { $0.submenu?.items ?? [] }
        let item = try #require(items.first { $0.identifier?.rawValue == "new" })
        #expect(item.keyEquivalent == "n" && item.action == #selector(App.newSpace(_:)))
        item.target = target
        target.welcoming = true
        menu.update()
        item.menu?.update()
        #expect(!item.isEnabled, "New Space is greyed while the welcome is open")
        // The greyed item still takes its key: ⌘N reaches neither a page nor anything else, and makes nothing.
        #expect(menu.performKeyEquivalent(with: try key("n", 45, .command, in: window)))
        #expect(target.made == 0, "⌘N does nothing")
        target.welcoming = false
        item.menu?.update()
        #expect(item.isEnabled)
        #expect(menu.performKeyEquivalent(with: try key("n", 45, .command, in: window)))
        #expect(target.made == 1, "once the welcome closes, ⌘N makes a space")

        // The seam: no app bundle here, so no notifier, and the permission is never asked (UNUserNotificationCenter
        // would stop the process). The welcome's "Notify me" asks only through it.
        #expect(Bundle.main.bundleURL.pathExtension != "app")
        #expect(SystemNotifier.make {} == nil)
        var asked = false
        let ask: (() -> Void)? = SystemNotifier.make {}.map { _ in { asked = true } }
        ask?()
        #expect(ask == nil && !asked)
    }

    /// The fake `claude` of SP8: on a message holding "ask-both" it asks a question (AskUserQuestion) and a permission
    /// (Bash), and writes each line it reads to $HOME/out/input. Invented text.
    static let fake = #"""
        #!/bin/sh
        mkdir -p "$HOME/out"
        while IFS= read -r line; do
          printf '%s\n' "$line" >> "$HOME/out/input"
          case "$line" in
            *'"subtype":"initialize"'*)
              echo '{"type":"control_response","response":{"subtype":"success","request_id":"something-1","response":{"current_permission_mode":"default","models":[{"value":"default","displayName":"Default"}]}}}' ;;
            *'ask-both'*'"type":"user"'*)
              echo '{"type":"system","subtype":"session_state_changed","state":"running","uuid":"u1","session_id":"s1"}'
              echo '{"type":"control_request","request_id":"q1","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","tool_use_id":"toolu_1","input":{"questions":[{"question":"Which colour for the invented button?","header":"Colour","multiSelect":false,"options":[{"label":"Blue","description":"Calm"},{"label":"Green","description":"Fresh"}]}]}}}'
              echo '{"type":"control_request","request_id":"r1","request":{"subtype":"can_use_tool","tool_name":"Bash","tool_use_id":"toolu_2","input":{"command":"npm test"}}}' ;;
            *'"subtype":"end_session"'*)
              echo '{"type":"control_response","response":{"subtype":"success","request_id":"something-end"}}'
              exit 0 ;;
          esac
        done
        """#

    /// SP8. A building assistant asks a question and a permission. Panels, filtering by request (questions of the build
    /// session only), shows the permission and never the question; the question is answered inline through the Engine,
    /// and the permission in the panel. Each reaches the agent once, from one place.
    @Test func aQuestionInlineAndItsPermissionInThePanel() async throws {
        let home = Home(prefix: "something-spike-"), bin = home.root.appendingPathComponent("bin")
        defer { home.remove() }
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.places.spaces, withIntermediateDirectories: true)
        try SpikeTests.fake.write(to: bin.appendingPathComponent("claude"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.appendingPathComponent("claude").path)
        let engine = home.engine(), model = AssistantModel(engine: engine, places: home.places)
        let source = Elsewhere(engine) { [weak model] in $0.kind == "question" && $0.agent == model?.id }
        let panels = Panels(source: source, shows: false)
        var time: TimeInterval = 100, shown: Set<String> = []
        panels.clock = { time }
        engine.changed = { [weak model] in
            model?.refresh()
            panels.refresh()
            panels.panel?.request.map { shown.insert($0.id) }
        }
        engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        model.place = .space(title: "My agents", name: "agents", page: home.places.spaces.appendingPathComponent("agents.html").path)
        model.send("ask-both")
        #expect(await wait(until: { engine.state.requests.count == 2 }), "the fake asked both")
        let agent = try #require(model.id)
        let question = try #require(engine.state.requests.first { $0.kind == "question" })
        let permission = try #require(engine.state.requests.first { $0.kind == "permission" })
        #expect(question.agent == agent && permission.agent == agent, "both come from the build session")

        #expect(panels.queue.waiting.map(\.id) == [permission.id], "the panel queues the permission only")
        #expect(panels.panel?.request?.id == permission.id)
        #expect(engine.prompt(question.id)?.questions.first?.options == ["Blue", "Green"], "the inline view has its options")
        #expect(source.prompt(question.id) == nil, "the panel cannot open the question")

        try engine.answer(question.id, .choice([["Blue"]]))
        func responses(_ id: String) -> Int {
            let lines = ((try? String(contentsOf: home.root.appendingPathComponent("out/input"), encoding: .utf8)) ?? "").split(separator: "\n")
            return lines.count { $0.contains("\"control_response\"") && $0.contains("\"request_id\":\"\(id)\"") }
        }
        #expect(await wait(until: { responses("q1") == 1 }), "the inline answer reached the agent")
        #expect(await wait(until: { !engine.state.requests.contains { $0.id == question.id } }))
        #expect(panels.panel?.request?.id == permission.id, "the permission still waits in the panel")

        time += 0.6
        try #require(panels.panel).allow()
        #expect(await wait(until: { responses("r1") == 1 }), "Allow Once reached the agent")
        #expect(await wait(until: { engine.state.requests.isEmpty }))
        #expect(shown == [permission.id], "the panel never showed the question")
        #expect(responses("q1") == 1 && responses("r1") == 1, "one answer each")
        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        await wait(until: { stopped })
    }
}
