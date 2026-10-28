// The window's frame: its sizes, the calm toolbar's items and their state with and without a space, the window layer that takes the
// mouse only on what it holds, and the toast in it. Offscreen: cursor, focus return and what VoiceOver reads over the
// layer are hand trials.
import AppKit
import SomethingCore
import Testing
@testable import SomethingAgents
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-frame-")) struct WindowLayerTests {
    /// A window of an empty home, never shown, nothing open; `body` gets its shell. In Stage's drawing turn: the sizes
    /// read here are Default's, and a size test of another suite holds the whole app at Large or Larger a while.
    func window(_ body: (Shell) throws -> Void) async throws {
        try await Stage.alone { try made(body) }
    }

    private func made(_ body: (Shell) throws -> Void) throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let home = Home(prefix: "something-frame-")
        defer { home.remove() }
        let library = Library(places: home.places, ask: FakeAsk(), share: Home.share), info = Info(places: home.places, ask: FakeAsk())
        let shell = Shell(library: library, info: info, assistant: AssistantModel(engine: home.engine(), places: home.places), autosave: false)
        defer { shell.window.close() }
        try body(shell)
    }

    @Test func theFrameHasTheMockupsSizesAndToolbar() async throws {
        try await window { shell in
            #expect(shell.window.contentView?.frame.size == NSSize(width: 1200, height: 760))
            #expect(shell.window.contentMinSize == NSSize(width: 640, height: 480))
            #expect(shell.inspector.minimumThickness == 320 && shell.inspector.maximumThickness == 320 && shell.inspector.isCollapsed)
            #expect(shell.split.splitView.arrangedSubviews[0].frame.width == 236)
            #expect(shell.window.toolbar?.items.map(\.itemIdentifier) == [.flexibleSpace, Shell.sidebar, .sidebarTrackingSeparator, Shell.title,
                                                                           .flexibleSpace, Shell.tools])
            let items = shell.toolbarItems
            #expect(items.suffix(3).map(\.itemIdentifier) == [Shell.point, Shell.info, Shell.full], "no Reload, no waiting chip")
            @MainActor func item(_ id: NSToolbarItem.Identifier) -> NSToolbarItem? { items.first { $0.itemIdentifier == id } }
            // Without a space, the calm toolbar: what acts on one is hidden, Page Full Screen too; the name stays.
            for id in Shell.onSpace {
                let control = shell.controls[id]
                #expect(item(id)?.isEnabled == false && control?.isHidden == true, "\(id)")
            }
            #expect(item(Shell.full)?.isEnabled == false && shell.controls[Shell.full]?.isHidden == true)
            #expect(shell.controls[Shell.info]?.toolTip == "Info (⌘I)" && shell.controls[Shell.full]?.toolTip == "Page Full Screen (⇧⌘F)")
            #expect(shell.window.title == "New Space" && shell.window.titleVisibility == .hidden)
            #expect(shell.titleLine.accessibilityRole() == .staticText && shell.titleLine.toolTip == nil, "New Space's name opens nothing")
            // Over a space they show, and the name is a button that opens Info.
            shell.heading("Daily brief", "", space: true)
            #expect(Shell.onSpace.allSatisfy { shell.controls[$0]?.isHidden == false && item($0)?.isEnabled == true })
            #expect(item(Shell.full)?.isEnabled == true && shell.controls[Shell.full]?.isHidden == false)
            #expect(shell.titleLine.accessibilityRole() == .button && shell.titleLine.accessibilityLabel() == "Daily brief")
            #expect(shell.titleLine.toolTip == "Show Info (⌘I)" && shell.titleLine.line.string == "Daily brief")
            // Window › Zoom acts on this window.
            let zoom = NSMenuItem(title: "Zoom", action: Keys.command("zoom")?.action, keyEquivalent: "")
            #expect(shell.window.validateUserInterfaceItem(zoom))
        }
    }

    /// Full Access's orange mark sits before Point only while it is on; a click on it turns it off.
    @Test func theFullAccessMarkFollowsThePreference() async throws {
        try await window { shell in
            #expect(shell.fullMark.isHidden && shell.fullMark.superview != nil && shell.fullMark.action == #selector(App.turnOffFullAccess(_:)))
            shell.fullAccess(true)
            #expect(!shell.fullMark.isHidden && shell.library.preferences.fullAccess)
            shell.fullAccess(false)
            #expect(shell.fullMark.isHidden && !shell.library.preferences.fullAccess)
        }
    }

    @Test func theLayerTakesOnlyWhatItHolds() async throws {
        try await window { shell in
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

    @Test func oneToastAtATimeItsActionOnceAndNeverTheFocus() async throws {
        try await window { shell in
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

    /// The mockup's right-hand cluster (X9.1): Point, Info and Page Full Screen, 28-point buttons 4 points apart, Page
    /// Full Screen 10 points from the window's edge (the mockup's centres: 1176, 1143).
    @Test func theToolsSitAsTheMockupsDo() async throws {
        try await window { shell in
            shell.heading("Daily brief", "", space: true)
            shell.window.contentView?.superview?.layoutSubtreeIfNeeded()
            @MainActor func frame(_ id: NSToolbarItem.Identifier) throws -> NSRect {
                let view = try #require(shell.controls[id])
                return view.superview?.convert(view.alignmentRect(forFrame: view.frame), to: nil) ?? .zero
            }
            let (point, info, full) = (try frame(Shell.point), try frame(Shell.info), try frame(Shell.full))
            #expect([info, full].allSatisfy { $0.size == NSSize(width: 28, height: 28) }, "\(point) \(info) \(full)")
            #expect(abs(full.midX - 1176) <= 2 && abs(info.midX - full.midX + 32) <= 0.5, "\(info) \(full)")
            #expect(abs(info.minX - point.maxX - 4) <= 0.5, "\(point) \(info)")
        }
    }

    /// A long title at the narrowest window gives way: the window keeps its 640 points, the tools stay in the toolbar,
    /// none in its overflow menu, 10 points from the edge. Widened, the title gets its whole line back.
    @Test func aLongTitleNeverPushesTheToolsOut() async throws {
        try await window { shell in
            shell.window.setContentSize(shell.window.contentMinSize)
            shell.heading("A morning brief with every feed, newsletter and calendar I read before work starts", "", space: true)
            let whole = ceil(shell.titleLine.line.size().width) + TitleLine.indent + TitleLine.trail
            // The toolbar lays its items out again on a later turn of the run loop, later under load: turned until
            // `done`, at least 0.2 s; the minute only stops a hang.
            func settle(until done: () -> Bool) {
                let end = Date(timeIntervalSinceNow: 60)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
                shell.window.contentView?.superview?.layoutSubtreeIfNeeded()
                while !done(), Date() < end {
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
                    shell.window.contentView?.superview?.layoutSubtreeIfNeeded()
                }
            }
            let full = try #require(shell.controls[Shell.full])
            settle { full.window === shell.window && full.convert(full.bounds, to: nil).maxX <= 640 - 10 + 2 }
            #expect(shell.window.contentView?.frame.width == 640)
            #expect(full.window === shell.window && !full.isHiddenOrHasHiddenAncestor)
            #expect(full.convert(full.bounds, to: nil).maxX <= 640 - 10 + 2, "\(full.convert(full.bounds, to: nil))")
            #expect(shell.titleLine.intrinsicContentSize.width < whole)
            shell.window.setContentSize(NSSize(width: 1200, height: 760))
            settle { shell.titleLine.intrinsicContentSize.width == whole }
            #expect(shell.titleLine.intrinsicContentSize.width == whole)
        }
    }

    @Test func underReducedMotionTheToastIsInPlaceAtOnce() async throws {
        try await window { shell in
            shell.library.preferences.motion = .reduced
            shell.layer.announce = { _ in }
            #expect(shell.toast("Pebble is back").bottom?.constant == -22)
        }
    }
}
