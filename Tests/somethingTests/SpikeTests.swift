// Block 1's spikes SP1, SP2 and SP3: the smallest prototypes that answer what the interface stands on. Each answer is
// written in the commit that adds this file; the file is test code only and is removed once the answers are kept.
// Every window is offscreen at alpha 0 and never ordered front, except the modal one SP2 runs, offscreen too: the app
// never becomes active. What a never-shown window cannot prove (key window, focus, routing by the window server) is
// left to the hand trial.
import AppKit
import Testing
import WebKit
@testable import something

/// A layer that takes only the events on what it draws (`drawn`, in its own coordinates): all others fall through.
private final class PassThrough: NSView {
    var drawn: [NSRect] = []
    override func hitTest(_ point: NSPoint) -> NSView? {
        drawn.contains { $0.contains(convert(point, from: superview)) } ? self : nil
    }
}

/// Allow Once as a click only: no key reaches it, it never takes the focus, and VoiceOver's press works only once it
/// is armed, a moment after the panel arrived, so a press meant for what was there before never answers.
private final class ArmedButton: NSButton {
    var armed = false
    override var acceptsFirstResponder: Bool { false }
    override func becomeFirstResponder() -> Bool { false }
    override var canBecomeKeyView: Bool { false }
    override func keyDown(with event: NSEvent) {}
    override func performKeyEquivalent(with key: NSEvent) -> Bool { false }
    override func accessibilityPerformPress() -> Bool { armed ? super.accessibilityPerformPress() : false }
}

/// Records the titles of the items and buttons that sent it their action.
private final class Recorder: NSObject {
    var fired: [String] = []
    @objc func act(_ sender: Any?) { fired.append((sender as? NSMenuItem)?.title ?? (sender as? NSButton)?.title ?? "?") }
}

/// The toolbar of Shell, its separators made for `split` when the split view controller is not the window's content.
private final class Bar: NSObject, NSToolbarDelegate {
    let split: NSSplitView?
    init(split: NSSplitView?) { self.split = split }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, .inspectorTrackingSeparator, .toggleInspector]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let split, [.sidebarTrackingSeparator, .inspectorTrackingSeparator].contains(id) else { return NSToolbarItem(itemIdentifier: id) }
        return NSTrackingSeparatorToolbarItem(identifier: id, splitView: split, dividerIndex: id == .sidebarTrackingSeparator ? 0 : 1)
    }
}

@MainActor private func key(_ characters: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = [], in window: NSWindow,
                            up: Bool = false) throws -> NSEvent {
    try #require(NSEvent.keyEvent(with: up ? .keyUp : .keyDown, location: .zero, modifierFlags: flags,
                                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                                  characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
}

@MainActor private func mouse(_ type: NSEvent.EventType, _ point: NSPoint, in window: NSWindow) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
}

@MainActor private func js(_ web: WKWebView, _ code: String) async throws -> Any? {
    let value = try await web.callAsyncJavaScript(code, contentWorld: .page)
    return value is NSNull ? nil : value
}

/// A web view with `html`, loaded once the page set `window.done`. No base URL: the page reaches nothing.
@MainActor private func loaded(_ html: String) async throws -> WKWebView {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), configuration: WKWebViewConfiguration())
    web.loadHTMLString(html, baseURL: nil)
    for _ in 0..<600 where try await (try? js(web, "return window.done === true")) as? Bool != true { await wait(0.05) }
    return web
}

/// A titled window that is never shown, holding `view`.
@MainActor private func titled(_ view: NSView, width: Double = 600, height: Double = 400) -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: width, height: height),
                          styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.alphaValue = 0
    window.isReleasedWhenClosed = false
    window.contentView = view
    return window
}

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing)) struct SpikeTests {
    /// SP1. A pass-through layer over the whole split view, put in the split view controller's own view or in a
    /// container controller around it: the tracking separators stay bound to the split view and the title follows
    /// the divider, the panes stay three, and only what the layer draws takes the mouse.
    @Test(arguments: [false, true]) func aLayerAboveTheSplitView(container: Bool) throws {
        let split = NSSplitViewController(), side = NSViewController(), content = NSViewController(), info = NSViewController()
        (side.view, content.view, info.view) = (NSView(), NSView(), NSView())
        [NSSplitViewItem(sidebarWithViewController: side), NSSplitViewItem(viewController: content),
         NSSplitViewItem(inspectorWithViewController: info)].forEach(split.addSplitViewItem)
        let window = titled(NSView(), width: 1200, height: 760), layer = PassThrough()
        defer { window.close() }
        layer.autoresizingMask = [.width, .height]
        if container {
            let holder = NSViewController()
            holder.view = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 760))
            holder.addChild(split)
            split.view.frame = holder.view.bounds
            split.view.autoresizingMask = [.width, .height]
            holder.view.addSubview(split.view)
            layer.frame = holder.view.bounds
            holder.view.addSubview(layer)
            window.contentViewController = holder
        } else {
            window.contentViewController = split
            layer.frame = split.view.bounds
            split.view.addSubview(layer)
        }
        window.setContentSize(NSSize(width: 1200, height: 760))
        let bar = Bar(split: container ? split.splitView : nil), toolbar = NSToolbar(identifier: "spike")
        toolbar.delegate = bar
        (window.toolbar, window.toolbarStyle) = (toolbar, .unified)
        window.layoutIfNeeded()
        split.splitView.setPosition(232, ofDividerAt: 0)
        split.splitView.setPosition(900, ofDividerAt: 1)
        window.layoutIfNeeded()
        let separators = toolbar.items.compactMap { $0 as? NSTrackingSeparatorToolbarItem }
        #expect(separators.map { $0.splitView === split.splitView } == [true, true])
        #expect(separators.map(\.dividerIndex) == [0, 1])
        // The title sits just after the sidebar's divider, and moves with it.
        func title() throws -> Double {
            var found: NSView?
            func walk(_ view: NSView) {
                if String(describing: type(of: view)) == "NSToolbarTitleView" { found = view }
                view.subviews.forEach(walk)
            }
            try walk(#require(window.contentView?.superview))
            return try #require(found).convert(try #require(found).bounds, to: nil).minX
        }
        let before = try title()
        split.splitView.setPosition(300, ofDividerAt: 0)
        window.layoutIfNeeded()
        #expect(try title() - before == 68, "the title follows the divider")
        #expect(split.splitView.arrangedSubviews.map { $0.frame.minX } == [0, 300, 930], "the layer is no pane")
        #expect(layer.frame.size == NSSize(width: 1200, height: 760), "the layer covers the window")
        layer.drawn = [NSRect(x: 400, y: 300, width: 400, height: 200)]
        let root = try #require(window.contentView?.superview)
        #expect(root.hitTest(NSPoint(x: 500, y: 400)) === layer)
        let beside = try #require(root.hitTest(NSPoint(x: 100, y: 100)))
        #expect(beside !== layer && beside.isDescendant(of: side.view))
    }

    /// SP1. A glass over the page (the sticker, a card) takes the mouse on what it draws only: a click, the wheel and
    /// a drag beside it reach the page, as AppKit routes them, by hit testing. The events are given to the view the
    /// hit test found: a never-shown window does not route a mouse event it is sent.
    @Test func aGlassAboveThePage() async throws {
        let lines = String(repeating: "<p>Words of an invented page, enough to scroll and to select.</p>", count: 200)
        let web = try await loaded("""
            <!doctype html><body style="margin:0;font:16px sans-serif">\(lines)<script>
            window.clicks = 0; addEventListener('click', () => window.clicks++, true); window.done = true</script></body>
            """)
        let center = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400)), glass = PassThrough(frame: center.bounds)
        web.autoresizingMask = [.width, .height]
        glass.drawn = [NSRect(x: 400, y: 0, width: 200, height: 120)]
        [web, glass].forEach(center.addSubview)
        let window = titled(center)
        defer { window.close() }
        #expect(center.hitTest(NSPoint(x: 500, y: 50)) === glass)
        let hit = try #require(center.hitTest(NSPoint(x: 100, y: 300)))
        #expect(hit === web)
        let point = NSPoint(x: 100, y: 300)
        for _ in 0..<5 where try await js(web, "return window.clicks") as? Int == 0 {
            hit.mouseDown(with: try mouse(.leftMouseDown, point, in: window))
            hit.mouseUp(with: try mouse(.leftMouseUp, point, in: window))
            await wait(3) { false }
        }
        #expect(try await js(web, "return window.clicks") as? Int ?? 0 > 0, "a click beside the glass reaches the page")
        let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -200, wheel2: 0, wheel3: 0))
        hit.scrollWheel(with: try #require(NSEvent(cgEvent: cg)))
        for _ in 0..<100 where try await js(web, "return window.scrollY") as? Double == 0 { await wait(0.05) }
        #expect(try await js(web, "return window.scrollY") as? Double ?? 0 > 0, "the wheel beside the glass scrolls the page")
        _ = try await js(web, "getSelection().removeAllRanges(); window.scrollTo(0, 0); return 1")
        hit.mouseDown(with: try mouse(.leftMouseDown, NSPoint(x: 10, y: 390), in: window))
        hit.mouseDragged(with: try mouse(.leftMouseDragged, NSPoint(x: 300, y: 300), in: window))
        hit.mouseUp(with: try mouse(.leftMouseUp, NSPoint(x: 300, y: 300), in: window))
        for _ in 0..<100 where try await js(web, "return getSelection().toString().length") as? Int == 0 { await wait(0.05) }
        #expect(try await js(web, "return getSelection().toString().length") as? Int ?? 0 > 0, "a drag beside the glass selects text")
    }

    /// SP2. Allow Once takes no key: Space and Return do nothing, a key equivalent never reaches it, and it refuses the
    /// focus, while a plain button given Return answers it. VoiceOver's press does nothing until it is armed.
    @Test func allowOnceTakesNoKey() throws {
        let recorder = Recorder(), content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        let armed = ArmedButton(title: "Allow Once", target: recorder, action: #selector(Recorder.act))
        let plain = NSButton(title: "Plain", target: recorder, action: #selector(Recorder.act))
        (armed.frame, plain.frame) = (NSRect(x: 20, y: 20, width: 120, height: 30), NSRect(x: 200, y: 20, width: 120, height: 30))
        [armed, plain].forEach(content.addSubview)
        let window = titled(content)
        defer { window.close() }
        window.makeFirstResponder(armed)
        #expect(window.firstResponder !== armed)
        for (characters, code) in [(" ", UInt16(49)), ("\r", 36)] {
            let event = try key(characters, code, in: window)
            armed.keyDown(with: event)
            #expect(!armed.performKeyEquivalent(with: event))
            #expect(!window.performKeyEquivalent(with: event))
            window.sendEvent(event)
        }
        armed.keyEquivalent = "\r"
        #expect(!window.performKeyEquivalent(with: try key("\r", 36, in: window)), "even given Return, it ignores it")
        #expect(recorder.fired.isEmpty)
        plain.keyEquivalent = "\r"
        #expect(window.performKeyEquivalent(with: try key("\r", 36, in: window)))
        #expect(recorder.fired == ["Plain"], "a plain button answers the key: the test can see one")
        recorder.fired = []
        #expect(!armed.accessibilityPerformPress())
        #expect(recorder.fired.isEmpty, "a press before arming does nothing")
        armed.armed = true
        _ = armed.accessibilityPerformPress()
        #expect(recorder.fired == ["Allow Once"])
    }

    /// SP2. Inside a modal session, as while the app waits for a sheet, the panel is still answered: its button's
    /// action runs from the modal loop. Whether a real click reaches a panel with `worksWhenModal` is the window server's
    /// routing, which an offscreen panel cannot show: a hand trial.
    @Test func allowOnceAnswersInsideAModal() throws {
        let recorder = Recorder()
        let button = ArmedButton(title: "Allow Once", target: recorder, action: #selector(Recorder.act))
        button.armed = true
        let panel = NSPanel(contentRect: NSRect(x: -21_000, y: -21_000, width: 300, height: 80), styleMask: [.titled, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        (panel.worksWhenModal, panel.alphaValue, panel.isReleasedWhenClosed) = (true, 0, false)
        panel.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        panel.contentView?.addSubview(button)
        // A modal session the test turns by hand: no timer and no stopModal, which, ended from a timer, leaves a block
        // that later stops the main run loop, and the test process with it.
        let modal = titled(NSView(), width: 200, height: 100)
        defer { panel.close(); modal.close() }
        let session = NSApp.beginModalSession(for: modal)
        var inModal = false
        for _ in 0..<20 where recorder.fired.isEmpty {
            _ = NSApp.runModalSession(session)
            inModal = NSApp.modalWindow === modal
            _ = button.accessibilityPerformPress()
        }
        NSApp.endModalSession(session)
        #expect(inModal)
        #expect(recorder.fired == ["Allow Once"])
        #expect(!NSApp.isActive && !panel.isVisible, "nothing was shown, the app never became active")
    }

    /// SP3. The menu's keys (⌘P, ⌘I, ⌘1, ⌘/) offered to a window whose web view has the focus: WebKit takes every one
    /// to the page first, and gives back to the menu only those the page did not prevent. A local key monitor, which
    /// NSApp runs before any window, gives them to the menu first: the page never sees them.
    @Test(arguments: [true, false]) func theMenusKeysAndAPageThatPreventsThem(prevented: Bool) async throws {
        let web = try await loaded("""
            <!doctype html><body><input id="f"><script>window.keys = [];
            addEventListener('keydown', e => { window.keys.push(e.key); \(prevented ? "e.preventDefault();" : "") }, true);
            window.done = true</script></body>
            """)
        let window = titled(web)
        defer { window.close() }
        window.makeFirstResponder(web)
        let recorder = Recorder(), menu = NSMenu(), saved = NSApp.mainMenu, holder = NSMenuItem(title: "Space", action: nil, keyEquivalent: "")
        defer { NSApp.mainMenu = saved }
        holder.submenu = NSMenu(title: "Space")
        let keys: [(String, String, UInt16)] = [("Print", "p", 35), ("Info", "i", 34), ("First", "1", 18), ("Palette", "/", 44)]
        for (title, characters, _) in keys {
            let item = NSMenuItem(title: title, action: #selector(Recorder.act), keyEquivalent: characters)
            item.target = recorder
            holder.submenu?.addItem(item)
        }
        menu.addItem(holder)
        NSApp.mainMenu = menu
        for (_, characters, code) in keys {
            #expect(window.performKeyEquivalent(with: try key(characters, code, .command, in: window)), "the web view claims it")
        }
        for _ in 0..<100 where try await js(web, "return window.keys.length") as? Int != 4 { await wait(0.05) }
        await wait(1) { false }
        #expect(try await js(web, "return window.keys.join(' ')") as? String == "p i 1 /")
        #expect(recorder.fired == (prevented ? [] : ["Print", "Info", "First", "Palette"]))
        recorder.fired = []
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            event.modifierFlags.contains(.command) && NSApp.mainMenu?.performKeyEquivalent(with: event) == true ? nil : event
        }
        defer { monitor.map(NSEvent.removeMonitor) }
        NSApp.sendEvent(try key("p", 35, .command, in: window))
        await wait(1) { false }
        #expect(recorder.fired == ["Print"])
        #expect(try await js(web, "return window.keys.length") as? Int == 4, "the page never saw it")
    }

    /// SP3. ⌘Z (undo: along the responder chain) reaches the window's undo manager, which the web view shares: typing
    /// in a focused <input> is undone first, then the app's own action, even while the input keeps the focus.
    @Test func undoReachesTheWindowAfterTheInputsOwn() async throws {
        let web = try await loaded("<!doctype html><body><input id=\"f\"><script>window.done = true</script></body>")
        let window = titled(web)
        defer { window.close() }
        window.makeFirstResponder(web)
        #expect(web.undoManager === window.undoManager)
        #expect(!web.responds(to: Selector(("undo:"))) && window.responds(to: Selector(("undo:"))))
        final class Name { var value = "Morning" }
        let name = Name()
        window.undoManager?.registerUndo(withTarget: name) { $0.value = "Daily brief" }
        window.undoManager?.setActionName("Rename Space")
        _ = try await js(web, "document.getElementById('f').focus(); return 1")
        for (characters, code) in [("a", UInt16(0)), ("b", 11)] {
            web.keyDown(with: try key(characters, code, in: window))
            web.keyUp(with: try key(characters, code, in: window, up: true))
        }
        let value = "return document.getElementById('f').value"
        for _ in 0..<100 where try await js(web, value) as? String != "ab" { await wait(0.05) }
        #expect(try await js(web, value) as? String == "ab")
        #expect(window.undoManager?.undoActionName == "Typing")
        #expect(web.tryToPerform(Selector(("undo:")), with: nil))
        for _ in 0..<100 where try await js(web, value) as? String != "" { await wait(0.05) }
        #expect(try await js(web, value) as? String == "")
        #expect(name.value == "Morning" && window.undoManager?.undoActionName == "Rename Space")
        #expect(web.tryToPerform(Selector(("undo:")), with: nil))
        #expect(name.value == "Daily brief", "the second ⌘Z undoes the app's action, the input still focused")
    }
}
