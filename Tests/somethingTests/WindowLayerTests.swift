// The window's frame: its sizes, the toolbar's items and their state without a space, the window layer that takes the
// mouse only on what it holds, and the toast in it. Offscreen: cursor, focus return and what VoiceOver reads over the
// layer are hand trials.
import AppKit
import SomethingCore
import Testing
@testable import SomethingAgents
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-frame-")) struct WindowLayerTests {
    /// A window of an empty home, never shown, nothing open; `body` gets its shell.
    func window(_ body: (Shell) throws -> Void) throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let home = Home(prefix: "something-frame-")
        defer { home.remove() }
        let library = Library(places: home.places, ask: FakeAsk(), share: Home.share), info = Info(places: home.places, ask: FakeAsk())
        let shell = Shell(library: library, info: info, assistant: AssistantModel(engine: home.engine(), places: home.places), autosave: false)
        defer { shell.window.close() }
        try body(shell)
    }

    @Test func theFrameHasTheMockupsSizesAndToolbar() throws {
        try window { shell in
            #expect(shell.window.contentView?.frame.size == NSSize(width: 1200, height: 760))
            #expect(shell.window.contentMinSize == NSSize(width: 640, height: 480))
            #expect(shell.inspector.minimumThickness == 320 && shell.inspector.maximumThickness == 320 && shell.inspector.isCollapsed)
            #expect(shell.split.splitView.arrangedSubviews[0].frame.width == 236)
            #expect(shell.window.toolbar?.items.map(\.itemIdentifier) == [.flexibleSpace, Shell.sidebar, .sidebarTrackingSeparator, Shell.title,
                                                                           .flexibleSpace, Shell.chip, Shell.tools])
            let items = shell.toolbarItems
            #expect(items.suffix(4).map(\.itemIdentifier) == [Shell.point, Shell.reload, Shell.info, Shell.full])
            @MainActor func item(_ id: NSToolbarItem.Identifier) -> NSToolbarItem? { items.first { $0.itemIdentifier == id } }
            // Without a space, what acts on one is greyed, never hidden; the chip's slot is hidden while empty.
            for id in Shell.onSpace {
                let control = shell.controls[id]
                #expect(item(id)?.isHidden == false && item(id)?.isEnabled == false && control?.isEnabled == false, "\(id)")
            }
            #expect(item(Shell.chip)?.isHidden == true && item(Shell.full)?.isEnabled == true)
            #expect(shell.controls[Shell.reload]?.toolTip == "Reload (⌘R)" && shell.controls[Shell.full]?.toolTip == "Full Screen (⌃⌘F)")
            #expect(shell.window.title == "New Space" && shell.window.titleVisibility == .hidden)
            // Window › Zoom acts on this window.
            let zoom = NSMenuItem(title: "Zoom", action: Keys.command("zoom")?.action, keyEquivalent: "")
            #expect(shell.window.validateUserInterfaceItem(zoom))
        }
    }

    @Test func theLayerTakesOnlyWhatItHolds() throws {
        try window { shell in
            let layer = shell.layer, root = try #require(shell.window.contentView?.superview)
            #expect(layer.isHidden && layer.frame.size == NSSize(width: 1200, height: 760))
            let held = NSView(frame: NSRect(x: 500, y: 300, width: 200, height: 100))
            layer.hold(held)
            #expect(!layer.isHidden && layer.superview?.subviews.last === layer)
            #expect(shell.split.splitView.arrangedSubviews.count == 3, "the layer is no pane")
            #expect(root.hitTest(NSPoint(x: 550, y: 350)) === held)
            let beside = try #require(root.hitTest(NSPoint(x: 100, y: 100)))
            #expect(beside !== layer && !beside.isDescendant(of: layer))
            held.removeFromSuperview()
            #expect(layer.isHidden)
        }
    }

    @Test func oneToastAtATimeItsActionOnceAndNeverTheFocus() throws {
        try window { shell in
            var said: [String] = [], undone = 0
            shell.layer.announce = { said.append($0) }
            let focus = shell.window.firstResponder
            let first = shell.toast("Pebble is in the Trash", action: Toast.Action(label: "Undo") { undone += 1 })
            let second = shell.toast("Pebble is back", quiet: true)
            #expect(shell.layer.subviews.compactMap { $0 as? Toast }.map(\.words) == ["Pebble is back"])
            #expect(!first.shown && second.shown && said == ["Pebble is in the Trash", "Pebble is back"])
            let third = shell.toast("Logbook is in the Trash", action: Toast.Action(label: "Undo") { undone += 1 })
            let undo = try #require(third.subviews.flatMap(\.subviews).compactMap { $0 as? NSButton }.first)
            #expect(!undo.acceptsFirstResponder)
            undo.performClick(nil)
            undo.performClick(nil)
            #expect(undone == 1 && !third.shown)
            #expect(shell.window.firstResponder === focus)
        }
    }

    /// The mockup's right-hand cluster: 28-point buttons 4 points apart, the line 8 points from Point and from Reload,
    /// Full Screen 10 points from the window's edge (the mockup's centres: 1176, 1144, 1112; the line at 1089).
    @Test func theToolsSitAsTheMockupsDo() throws {
        try window { shell in
            shell.window.contentView?.superview?.layoutSubtreeIfNeeded()
            @MainActor func frame(_ id: NSToolbarItem.Identifier) throws -> NSRect {
                let view = try #require(shell.controls[id])
                return view.superview?.convert(view.alignmentRect(forFrame: view.frame), to: nil) ?? .zero
            }
            let (point, reload, info, full) = (try frame(Shell.point), try frame(Shell.reload), try frame(Shell.info), try frame(Shell.full))
            #expect([reload, info, full].allSatisfy { $0.size == NSSize(width: 28, height: 28) }, "\(point) \(reload) \(info) \(full)")
            #expect(abs(full.midX - 1176) <= 2 && abs(info.midX - full.midX + 32) <= 0.5 && abs(reload.midX - info.midX + 32) <= 0.5, "\(reload) \(info) \(full)")
            #expect(abs(reload.minX - point.maxX - 17) <= 0.5, "\(point) \(reload)")
        }
    }

    /// A long title at the narrowest window gives way: the tools stay in the toolbar, none in its overflow menu.
    @Test func aLongTitleNeverPushesTheToolsOut() throws {
        try window { shell in
            shell.window.setContentSize(shell.window.contentMinSize)
            shell.heading("A morning brief with every feed I read before work", "a-morning-brief-with-every-feed.html", space: true)
            // The toolbar lays its items out again on a later turn of the run loop.
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
            shell.window.contentView?.superview?.layoutSubtreeIfNeeded()
            let full = try #require(shell.controls[Shell.full])
            #expect(full.window === shell.window && !full.isHiddenOrHasHiddenAncestor)
            #expect(full.convert(full.bounds, to: nil).maxX <= shell.window.frame.width, "\(full.convert(full.bounds, to: nil)) \(shell.window.frame)")
        }
    }

    @Test func underReducedMotionTheToastIsInPlaceAtOnce() throws {
        try window { shell in
            shell.library.preferences.motion = .reduced
            shell.layer.announce = { _ in }
            #expect(shell.toast("Pebble is back").bottom?.constant == -22)
        }
    }
}
