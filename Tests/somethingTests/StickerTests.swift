// The glass and the sticker, in a window never shown with Daily brief open: the glass takes the mouse only on the
// sticker and the card, so a click beside them reaches the page; the badge counts only this space's requests and shows
// the request; a click, Return or ⌘K grows the card from the sticker's corner, ⌘\, Esc or Reduce shrinks it back, the
// focus leaving the card for the page; the label says what the assistant does on hover or focus; the sticker is only
// over a space; a drag moves it to the nearest side and keeps its place for every space, a press that moves less than 4
// points is a click. Cursor, the key view loop and what VoiceOver reads are hand trials.
import AppKit
import SomethingCore
import Testing
@testable import SomethingAgents
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-sticker-"))
struct StickerTests {
    /// A window with Daily brief open, its assistant the sticker as a space opens; `body` gets the shell and the page.
    func brief(motion: Look.Motion = .reduced, _ body: (Shell, SpaceView) async throws -> Void) async throws {
        try await brief(motion: motion) { shell, brief, _ in try await body(shell, brief) }
    }

    /// The same, `body` also getting the stage, to open another space.
    func brief(motion: Look.Motion = .reduced, _ body: (Shell, SpaceView, Stage) async throws -> Void) async throws {
        let stage = try Stage("sticker")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        defer { shell.window.close() }
        shell.glass.motion = { motion }
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        #expect(await wait(5) { shell.glass.grown == false && !shell.glass.morphing && shell.glass.stickerShown })
        try await body(shell, brief, stage)
    }

    func event(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    func key(_ characters: String, _ code: UInt16, in window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: window.windowNumber, context: nil, characters: characters,
                                      charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }

    @Test func theGlassTakesOnlyTheStickerAndTheCard() async throws {
        try await brief { shell, brief in
            let glass = shell.glass, root = try #require(shell.window.contentView?.superview)
            #expect(glass.superview === shell.center && glass.frame == shell.center.bounds && !glass.isHidden)
            #expect(glass.corner == NSRect(x: shell.center.bounds.width - 60, y: 16, width: 44, height: 44))
            #expect(glass.stickerShown && glass.card.isHidden && glass.label.isHidden)
            let middle = glass.convert(NSPoint(x: glass.corner.midX, y: glass.corner.midY), to: root)
            #expect(root.hitTest(middle) === glass.sticker)
            // Beside the sticker, in its shadow's room, and where the card would be: the page.
            for x in [glass.corner.minX - 6, glass.corner.minX - 200] {
                let beside = try #require(root.hitTest(glass.convert(NSPoint(x: x, y: glass.corner.midY), to: root)))
                #expect(beside.isDescendant(of: brief.web) || beside === brief.web, "\(beside)")
            }
            // Open, the card takes its own clicks, its margin still the page's.
            shell.reduceAssistant(nil)
            #expect(await wait(5) { glass.grown == true && !glass.morphing })
            let card = glass.card.frame.insetBy(dx: AssistantCard.margin, dy: AssistantCard.margin)
            let inCard = try #require(root.hitTest(glass.convert(NSPoint(x: card.midX, y: card.midY), to: root)))
            #expect(inCard.isDescendant(of: glass.card))
            let margin = try #require(root.hitTest(glass.convert(NSPoint(x: card.minX - 8, y: card.midY), to: root)))
            #expect(margin.isDescendant(of: brief.web) || margin === brief.web)
        }
    }

    @Test func theBadgeCountsOnlyThisSpaceAndShowsTheRequest() async throws {
        try await brief { shell, _ in
            let badge = shell.glass.sticker.badge
            var shown = 0
            shell.assistant.showRequest = { shown += 1 }
            shell.waiting(3, mine: 0)
            #expect(badge.isHidden && shell.chip.count == 3, "My agents waits; Daily brief does not")
            shell.waiting(3, mine: 1)
            #expect(!badge.isHidden && badge.count == 1 && shell.chip.count == 3)
            #expect(badge.accessibilityLabel() == "1 request from this space waiting for your answer")
            let surface = shell.glass.sticker.surface
            #expect(badge.frame.maxX == surface.maxX + 8 && badge.frame.minY == surface.minY - 8 && badge.frame.height == 19)
            let root = try #require(shell.window.contentView?.superview)
            #expect(root.hitTest(badge.convert(NSPoint(x: badge.bounds.midX, y: badge.bounds.midY), to: root)) === badge)
            badge.performClick(nil)
            #expect(shown == 1 && !shell.assistant.open, "the badge shows the request and leaves the card closed")
            shell.waiting(0, mine: 0)
            #expect(badge.isHidden)
        }
    }

    @Test func aClickReturnOrCommandKGrowsTheCardAndEscReducesIt() async throws {
        try await brief { shell, brief in
            let glass = shell.glass, sticker = glass.sticker, model = shell.assistant, window = shell.window
            func grown() async -> Bool { await wait(5) { glass.grown == true && !glass.morphing && !glass.card.isHidden } }
            func shrunk() async -> Bool { await wait(5) { glass.grown == false && !glass.morphing && glass.card.isHidden } }
            // A click on the sticker.
            let at = sticker.convert(NSPoint(x: sticker.surface.midX, y: sticker.surface.midY), to: nil)
            sticker.mouseDown(with: try event(.leftMouseDown, at: at, in: window))
            sticker.mouseUp(with: try event(.leftMouseUp, at: at, in: window))
            #expect(await grown() && model.open && glass.sticker.alphaValue == 0)
            // Under the grown card the sticker is hidden: its badge takes no click, VoiceOver does not find it.
            #expect(sticker.isHidden && !glass.stickerShown)
            let card = glass.card.frame
            #expect(card.maxX == glass.bounds.width && card.minY == 0, "the card's corner is the sticker's: \(card)")
            #expect(card.width == AssistantCard.width + 2 * AssistantCard.margin && model.floating == card.height)
            // Esc in the card: it shrinks, and the focus goes back to the page.
            window.makeFirstResponder(glass.card)
            glass.card.cancelOperation(nil)
            #expect(await shrunk() && !model.open && sticker.alphaValue == 1 && model.floating == 0)
            #expect(window.firstResponder === brief.web, "\(String(describing: window.firstResponder))")
            // Return on the sticker.
            #expect(window.makeFirstResponder(sticker))
            sticker.keyDown(with: try key("\r", 36, in: window))
            #expect(await grown())
            // Reduce (⌘\), then ⌘K.
            shell.reduceAssistant(nil)
            #expect(await shrunk())
            model.focus()
            #expect(await grown())
            // The Reduce button of the card is the model's open, which ⌘\ toggles too.
            model.open = false
            #expect(await shrunk())
            #expect(sticker.accessibilityPerformPress())
            #expect(await grown())
        }
    }

    @Test func theCardGrowsFromTheStickersCornerUnderCalmMotion() async throws {
        try await brief(motion: .calm) { shell, _ in
            let glass = shell.glass, model = shell.assistant
            model.open = true
            #expect(await wait(1) { glass.morphing }, "it moves")
            #expect(glass.card.frame.maxX == glass.bounds.width && glass.card.frame.minY == 0, "from the sticker's corner")
            #expect(await wait(5) { !glass.morphing })
            let card = glass.card.frame
            #expect(card.maxX == glass.bounds.width && card.minY == 0 && card.width == AssistantCard.width + 2 * AssistantCard.margin)
            #expect(glass.card.alphaValue == 1 && glass.sticker.alphaValue == 0)
            model.open = false
            #expect(await wait(1) { model.folding }, "drawn while it shrinks")
            #expect(await wait(5) { !glass.morphing })
            #expect(glass.card.isHidden && !model.folding && glass.sticker.alphaValue == 1)
            #expect(glass.card.frame == glass.corner.insetBy(dx: -AssistantCard.margin, dy: -AssistantCard.margin))
            #expect(glass.card.layer?.animationKeys()?.isEmpty ?? true, "no animation remains")
        }
    }

    @Test func theLabelSaysWhatItDoesOnHoverOrFocus() async throws {
        try await brief { shell, _ in
            let glass = shell.glass, sticker = glass.sticker, window = shell.window
            let at = sticker.convert(NSPoint(x: sticker.surface.midX, y: sticker.surface.midY), to: nil)
            sticker.mouseEntered(with: try event(.mouseMoved, at: at, in: window))
            #expect(!glass.label.isHidden && glass.label.title == "Daily brief")
            #expect(glass.label.words == shell.assistant.presence.word)
            #expect(glass.label.frame.maxX == glass.corner.minX - 10 && glass.label.frame.midY == glass.corner.midY)
            #expect(sticker.accessibilityLabel() == shell.assistant.presence.label("Daily brief"))
            shell.waiting(1, mine: 1)
            #expect(glass.label.words == "A request waiting for your answer")
            #expect(Glass.words(shell.assistant.presence, mine: 2) == "2 requests waiting for your answer")
            sticker.mouseExited(with: try event(.mouseMoved, at: .zero, in: window))
            #expect(glass.label.isHidden)
            #expect(window.makeFirstResponder(sticker) && !glass.label.isHidden)
            window.makeFirstResponder(nil)
            #expect(glass.label.isHidden)
        }
    }

    @Test func theStickerIsOnlyOverASpace() async throws {
        try await brief { shell, _ in
            let glass = shell.glass
            #expect(glass.stickerShown)
            shell.show(nil)
            shell.assistant.place = .blank
            #expect(await wait(5) { glass.sticker.isHidden })
            shell.assistant.place = .templates
            #expect(await wait(5) { glass.sticker.isHidden })
            // Off a space there is no sticker to fold into: Esc leaves the card open.
            shell.assistant.open = true
            #expect(await wait(5) { glass.grown == true && !glass.morphing })
            glass.card.cancelOperation(nil)
            #expect(shell.assistant.cardShown && shell.assistant.open)
        }
    }

    @Test func aSpaceOpensAsTheSticker() async throws {
        try await brief { shell, brief in
            let glass = shell.glass, model = shell.assistant
            // New Space, the card open with its conversation; then the space opens: the assistant is the sticker.
            shell.show(nil)
            model.place = .blank
            (model.open, model.threadShown) = (true, true)
            #expect(await wait(5) { glass.grown == true && !glass.morphing })
            shell.show(brief)
            model.place = AssistantModel.place(brief)
            #expect(await wait(5) { glass.grown == false && !glass.morphing && glass.stickerShown })
            // ⌘K still grows the card, and a new title for the same space keeps it grown.
            model.focus()
            #expect(await wait(5) { glass.grown == true && !glass.morphing })
            model.place = .space(title: "Renamed", name: brief.space.name, page: brief.space.page.path)
            #expect(model.open)
        }
    }

    @Test(arguments: [
        // A room of 700 by 500: the surface's origin let go, and where it goes.
        (NSPoint(x: 500, y: 200), Preferences.StickerPlace(trailing: true, bottom: true, offset: 200)),
        (NSPoint(x: 100, y: 300), Preferences.StickerPlace(trailing: false, bottom: false, offset: 156)),
        (NSPoint(x: 327, y: 229), Preferences.StickerPlace(trailing: false, bottom: false, offset: 227)),
        (NSPoint(x: 328, y: 227), Preferences.StickerPlace(trailing: true, bottom: true, offset: 227)),
        // Within 44 points of the bottom or the top it clings there, 16 points in.
        (NSPoint(x: 20, y: 59), Preferences.StickerPlace(trailing: false, bottom: true, offset: 16)),
        (NSPoint(x: 20, y: 60), Preferences.StickerPlace(trailing: false, bottom: true, offset: 60)),
        (NSPoint(x: 680, y: 397), Preferences.StickerPlace(trailing: true, bottom: false, offset: 16)),
        (NSPoint(x: 680, y: 396), Preferences.StickerPlace(trailing: true, bottom: false, offset: 60)),
        // Outside the room it comes back in.
        (NSPoint(x: -40, y: -40), Preferences.StickerPlace(trailing: false, bottom: true, offset: 16)),
        (NSPoint(x: 900, y: 900), Preferences.StickerPlace(trailing: true, bottom: false, offset: 16)),
    ])
    func theMagnetTakesTheStickerToTheNearestSide(origin: NSPoint, place: Preferences.StickerPlace) {
        let room = NSSize(width: 700, height: 500), spot = Glass.magnet(origin, in: room)
        #expect(spot == place)
        let at = Glass.origin(of: spot, in: room)
        #expect(at.x == (place.trailing ? 640 : 16) && at.y >= 16 && at.y <= 440)
        #expect(Glass.magnet(at, in: room) == spot, "a place let go again stays")
        #expect(Glass.origin(of: Glass.first, in: room) == NSPoint(x: 640, y: 16))
        // Its edges hold it: the center grows, the sticker stays against the same side and edge.
        let wide = Glass.origin(of: spot, in: NSSize(width: 1000, height: 800))
        #expect(wide.x == (place.trailing ? 940 : 16) && (place.bottom ? wide.y == at.y : 800 - wide.y == 500 - at.y))
    }

    /// Presses the sticker at its middle and moves the pointer along `steps`, each from the press, in the window.
    func drag(_ sticker: Sticker, in window: NSWindow, _ steps: [CGSize], release: Bool = true) throws {
        let at = sticker.convert(NSPoint(x: sticker.surface.midX, y: sticker.surface.midY), to: nil)
        func moved(_ d: CGSize) -> NSPoint { NSPoint(x: at.x + d.width, y: at.y + d.height) }
        sticker.mouseDown(with: try event(.leftMouseDown, at: at, in: window))
        for step in steps { sticker.mouseDragged(with: try event(.leftMouseDragged, at: moved(step), in: window)) }
        if release { sticker.mouseUp(with: try event(.leftMouseUp, at: moved(steps.last ?? .zero), in: window)) }
    }

    @Test func aDragMovesTheStickerToASideAndKeepsItForEverySpace() async throws {
        try await brief { shell, _, stage in
            let glass = shell.glass, sticker = glass.sticker, preferences = shell.library.preferences
            let start = glass.corner, room = NSSize(width: glass.bounds.width, height: glass.bounds.height - shell.center.safeAreaInsets.top)
            #expect(preferences.sticker == nil)
            // Held, it follows the pointer, its eyes lean at most 3 points, and no label shows.
            try drag(sticker, in: shell.window, [CGSize(width: -100, height: 80), CGSize(width: -700, height: 200)], release: false)
            #expect(sticker.dragging && glass.held == NSPoint(x: start.minX - 700, y: start.minY + 200))
            #expect(sticker.sign.lean == CGSize(width: -3, height: -3) && glass.label.isHidden && !shell.assistant.open)
            sticker.mouseUp(with: try event(.leftMouseUp, at: .zero, in: shell.window))
            // Let go left of the middle: the leading side, 16 points in, the height it was let go at, kept.
            let spot = Glass.magnet(NSPoint(x: start.minX - 700, y: start.minY + 200), in: room)
            #expect(!spot.trailing && glass.spot == spot && preferences.sticker == spot && !shell.assistant.open)
            #expect(glass.corner == NSRect(origin: Glass.origin(of: spot, in: room), size: start.size) && glass.corner.minX == 16)
            #expect(sticker.frame == glass.corner.insetBy(dx: -Sticker.room, dy: -Sticker.room) && sticker.sign.lean == .zero)
            // Another space: the same place.
            let logbook = try await stage.open("logbook", in: shell, shell.library)
            defer { logbook.close() }
            #expect(await wait(5) { glass.stickerShown })
            #expect(glass.corner.origin == Glass.origin(of: spot, in: room))
            // The center resizes: the sticker stays against its side and the edge that holds it.
            shell.window.setContentSize(NSSize(width: 1000, height: 660))
            shell.window.layoutIfNeeded()
            let smaller = NSSize(width: glass.bounds.width, height: glass.bounds.height - shell.center.safeAreaInsets.top)
            #expect(glass.corner.origin == Glass.origin(of: spot, in: smaller) && glass.corner.minX == 16)
            // The card grows from the sticker's corner, inside the center.
            shell.assistant.focus()
            #expect(await wait(5) { glass.grown == true && !glass.morphing })
            #expect(glass.card.frame.minX == 0 && glass.card.frame.minY >= 0 && glass.card.frame.maxY <= smaller.height)
        }
    }

    @Test func aPressThatMovesLessThanFourPointsIsAClick() async throws {
        try await brief { shell, _ in
            let glass = shell.glass, start = glass.corner
            try drag(glass.sticker, in: shell.window, [CGSize(width: 1, height: 1), CGSize(width: 2, height: 0)])
            #expect(glass.corner == start && glass.held == nil && shell.library.preferences.sticker == nil)
            #expect(await wait(5) { glass.grown == true && shell.assistant.open })
        }
    }

    @Test func aStickerLetGoSnapsToItsSideUnderCalmMotion() async throws {
        try await brief(motion: .calm) { shell, _ in
            let glass = shell.glass
            try drag(glass.sticker, in: shell.window, [CGSize(width: -300, height: 100)])
            #expect(glass.snapping, "it moves to its side")
            #expect(await wait(5) { !glass.snapping })
            #expect(glass.sticker.frame == glass.corner.insetBy(dx: -Sticker.room, dy: -Sticker.room) && glass.spot?.trailing == true)
        }
    }

    @Test func aStickerGrabbedOnItsWayFollowsThePointer() async throws {
        try await brief(motion: .calm) { shell, _ in
            let glass = shell.glass, sticker = glass.sticker
            try drag(sticker, in: shell.window, [CGSize(width: -300, height: 100)])
            #expect(glass.snapping)
            try drag(sticker, in: shell.window, [CGSize(width: 0, height: 60)], release: false)
            let held = try #require(glass.held)
            #expect(!glass.snapping && sticker.frame == glass.corner.insetBy(dx: -Sticker.room, dy: -Sticker.room))
            #expect(glass.corner.origin == held, "the snap ended and the sticker is where the pointer holds it")
            sticker.mouseUp(with: try event(.leftMouseUp, at: .zero, in: shell.window))
            #expect(await wait(5) { !glass.snapping && glass.held == nil })
        }
    }

    @Test(arguments: [true, false])
    func theRememberedPlaceComesBackAndADragKeepsItOnlyWhenAsked(remember: Bool) async throws {
        let stage = try Stage("sticker")
        defer { stage.remove() }
        let ask = FakeAsk(), places = stage.home.places
        let library = Library(places: places, ask: ask, share: Home.share)
        library.relist()
        // Saved before the window opens, as at the next start.
        let saved = Preferences.StickerPlace(trailing: false, bottom: false, offset: 120)
        library.preferences.rememberSticker = remember
        library.preferences.sticker = saved
        let shell = Shell(library: library, info: Info(places: places, ask: ask),
                          assistant: AssistantModel(engine: stage.home.engine(), places: places), autosave: false)
        defer { shell.window.close() }
        shell.window.setContentSize(Stage.Size.main)
        shell.glass.motion = { .reduced }
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        let glass = shell.glass
        #expect(await wait(5) { glass.stickerShown })
        let room = NSSize(width: glass.bounds.width, height: glass.bounds.height - shell.center.safeAreaInsets.top)
        #expect(glass.spot == (remember ? saved : nil))
        #expect(glass.corner.origin == Glass.origin(of: remember ? saved : Glass.first, in: room))
        #expect(glass.corner.minX == (remember ? 16 : room.width - 60))
        // A drag moves it; Preferences keep the new place only when asked to remember it.
        let before = glass.spot
        try drag(glass.sticker, in: shell.window, [CGSize(width: remember ? 700 : -700, height: -150)])
        let spot = try #require(glass.spot)
        #expect(spot != before && spot.trailing == remember)
        #expect(library.preferences.sticker == (remember ? spot : saved))
    }

    @Test func theStickersEyesFollowThePersonsMotion() async throws {
        try await brief { shell, _ in
            let sign = shell.glass.sticker.sign
            sign.systemReduces = { false }
            sign.state = .think
            #expect(sign.motion == .reduced && !sign.animating, "Reduced: the eyes hold still")
            shell.glass.motion = { .calm }
            #expect(sign.motion == .calm && sign.animating)
            shell.glass.motion = { .reduced }
            #expect(!sign.animating)
            // The preference, changed in Preferences, reaches the eyes: the glass follows it.
            let preferences = shell.library.preferences
            shell.glass.motion = { preferences.motion }
            // A change of the model has the glass read the new source, as it does once a space opens in the app.
            shell.assistant.open = true
            #expect(await wait(5) { shell.glass.grown == true })
            shell.assistant.open = false
            #expect(await wait(5) { shell.glass.grown == false && shell.glass.stickerShown })
            preferences.motion = .calm
            #expect(await wait(5) { sign.animating })
            preferences.motion = .reduced
            #expect(await wait(5) { !sign.animating })
        }
    }
}
