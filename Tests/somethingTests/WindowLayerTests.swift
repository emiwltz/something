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
            let items = try #require(shell.window.toolbar?.items)
            #expect(items.map(\.itemIdentifier) == [.flexibleSpace, Shell.sidebar, .sidebarTrackingSeparator, Shell.title, .flexibleSpace,
                                                    Shell.chip, Shell.point, Shell.reload, Shell.info, Shell.full])
            @MainActor func item(_ id: NSToolbarItem.Identifier) -> NSToolbarItem? { items.first { $0.itemIdentifier == id } }
            // Without a space, what acts on one is greyed, never hidden; the chip's slot is hidden while empty.
            for id in Shell.onSpace {
                let control = (item(id)?.view as? NSControl) ?? item(id)?.view?.subviews.first as? NSControl
                #expect(item(id)?.isHidden == false && item(id)?.isEnabled == false && control?.isEnabled == false, "\(id)")
            }
            #expect(item(Shell.chip)?.isHidden == true && item(Shell.full)?.isEnabled == true)
            #expect(item(Shell.reload)?.view?.toolTip == "Reload (⌘R)" && item(Shell.full)?.view?.toolTip == "Full Screen (⌃⌘F)")
            #expect(shell.window.title == "New Space" && shell.window.titleVisibility == .hidden)
            // Window › Zoom acts on this window.
            let zoom = NSMenuItem(title: "Zoom", action: Keys.command("zoom")?.action, keyEquivalent: "")
            #expect(shell.window.validateUserInterfaceItem(zoom))
        }
    }

    @Test func theLayerTakesOnlyWhatItHolds() throws {
        try window { shell in
            let layer = shell.layer!, root = try #require(shell.window.contentView?.superview)
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
}
