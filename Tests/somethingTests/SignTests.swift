// The sign is the mockup's: its corners and eyes sit where the mockup's CSS puts them at 44 pt and scale with the
// side, each state draws its own face (unknown never as listen), Reduced motion holds it at rest, the mini eyes are a
// 16x10 template, the hard shadow falls down and right, and VoiceOver reads each state's word. No window is shown.
// With SOMETHING_GALLERY, the seven states are drawn side by side, by day and by night, to compare with the mockup.
import AppKit
import Testing
@testable import something

@MainActor @Suite struct SignTests {
    let day = NSAppearance(named: .aqua)!, night = NSAppearance(named: .darkAqua)!

    /// What `draw` paints on a `size` point canvas at 2x under `appearance`, on a transparent ground.
    func render(_ size: NSSize, _ appearance: NSAppearance? = nil, _ draw: () -> Void) throws -> NSBitmapImageRep {
        let rep = try Picture.bitmap(size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        (appearance ?? day).performAsCurrentDrawingAppearance(draw)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Whether the pixel under the point (`x`, `y`), counted from the top-left, is mostly covered.
    func inked(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) -> Bool {
        (rep.colorAt(x: Int(x * 2), y: Int(y * 2))?.alphaComponent ?? 0) > 0.5
    }

    func sign(_ state: Sign.State, side: CGFloat = 44, motion pose: Sign.Pose = .rest) throws -> NSBitmapImageRep {
        try render(NSSize(width: side, height: side)) {
            Sign.draw(state, pose: pose, in: CGRect(x: 0, y: 0, width: side, height: side), flipped: false)
        }
    }

    @Test func at44PointsTheCornersAndEyesAreTheMockups() throws {
        let g = Sign.Geometry()
        #expect((g.arm, g.stroke, g.eye) == (0.31, 35, 0.125))
        // tokens.css: inset 6%, arm = side x .31; the eyes .88 by 1.56 eye units, 1.4 apart, .45 below the middle.
        let near = { (a: CGRect, b: CGRect) in
            [a.minX - b.minX, a.minY - b.minY, a.width - b.width, a.height - b.height].allSatisfy { abs($0) < 0.01 }
        }
        #expect(near(g.cornerRect(0, side: 44), CGRect(x: 2.64, y: 2.64, width: 13.64, height: 13.64)))
        #expect(near(g.cornerRect(2, side: 44), CGRect(x: 27.72, y: 27.72, width: 13.64, height: 13.64)))
        let eyes = g.eyes(.listen, side: 44)
        #expect(near(eyes[0], CGRect(x: 13.31, y: 20.185, width: 4.84, height: 8.58)))
        #expect(near(eyes[1], CGRect(x: 25.85, y: 20.185, width: 4.84, height: 8.58)))
        // At any side, it is the same sign scaled.
        #expect(near(g.cornerRect(1, side: 88), CGRect(x: 55.44, y: 5.28, width: 27.28, height: 27.28)))
        #expect(near(g.eyes(.think, side: 88)[1], g.eyes(.think, side: 44)[1].applying(CGAffineTransform(scaleX: 2, y: 2))))
        // A sign may widen its joy eyes.
        var big = Sign.Geometry()
        big.joy = 1.5
        #expect(abs(big.eyes(.done, side: 118)[0].width - 1.5 * 14.75) < 0.01)
    }

    @Test func theDrawingFollowsTheMockupsPathWithinHalfAPoint() throws {
        let rep = try sign(.listen)
        // The top-left corner's upright stroke, x = 2.64 + 13 x .1364, is 35 units wide in a 100-unit corner: 4.77 pt.
        let x = 2.64 + 13 * 0.1364, half = 35 * 0.1364 / 2, y = 2.64 + 75 * 0.1364
        #expect(inked(rep, x - half + 0.5, y) && inked(rep, x + half - 0.5, y))
        #expect(!inked(rep, x - half - 0.5, y) && !inked(rep, x + half + 0.5, y))
        // The bottom-right corner is the same turned half round; the eyes are inked at their centres only.
        #expect(inked(rep, 44 - x, 44 - y) && !inked(rep, 44 - x - half - 0.5, 44 - y))
        #expect(inked(rep, 15.73, 24.475) && inked(rep, 28.27, 24.475) && !inked(rep, 22, 24.475) && !inked(rep, 15.73, 19.5))
    }

    @Test func eachStateDrawsItsOwnFaceAndUnknownIsNeverListen() throws {
        let pictures = try Sign.State.allCases.map { try sign($0).tiffRepresentation }
        #expect(Set(pictures).count == Sign.State.allCases.count)
        // Unknown is hollow: listen's eye is inked at its centre, unknown's is not.
        let unknown = try sign(.unknown), listen = try sign(.listen)
        #expect(inked(listen, 15.73, 24.475) && !inked(unknown, 15.73, 24.475))
        // Stopped eyes are red, by day and by night.
        for appearance in [day, night] {
            let rep = try render(NSSize(width: 44, height: 44), appearance) { Sign.draw(.limit, in: CGRect(x: 0, y: 0, width: 44, height: 44), flipped: false) }
            let eye = try #require(rep.colorAt(x: Int(15.73 * 2), y: Int((24.475 + 2.75) * 2))?.usingColorSpace(.sRGB))
            #expect(eye.redComponent > 0.7 && eye.greenComponent < 0.55, "\(appearance.name.rawValue): \(eye)")
        }
        #expect(Sign.image(.done, side: 30).accessibilityDescription == "Idle")
        // A smile is an expression, not a state: the state is still said, never as Done.
        let smiling = SignView(.listen)
        (smiling.name, smiling.joy) = ("something", true)
        #expect(smiling.accessibilityLabel() == "something, Idle, smiling" && Sign.miniEyes(.listen, joy: true).accessibilityDescription == "Idle, smiling")
    }

    @Test func calmMotionMovesAndReducedHoldsItAtRest() throws {
        #expect(Sign.pose(.listen, at: 3, motion: .calm).scale > 1.02)
        #expect(Sign.pose(.listen, at: 6.755, motion: .calm).open < 0.15)
        #expect(Sign.pose(.think, at: 0.8, motion: .calm).look > 0.2)
        #expect(Sign.pose(.done, at: 0.28, motion: .calm).lift < -0.05 && Sign.pose(.done, at: 2, motion: .calm).lift == 0)
        #expect(Sign.pose(.limit, at: 3, motion: .calm) == .rest && Sign.pose(.unknown, at: 3, motion: .calm) == .rest)
        for state in Sign.State.allCases {
            for t in [0.5, 3, 6.72] { #expect(Sign.pose(state, at: t, arrived: 0.2, motion: .reduced) == .rest) }
        }
        // While it arrives the corners are not there yet; the picture differs from the sign at rest.
        #expect(try sign(.listen, motion: Sign.Pose(arrived: 0.1)).tiffRepresentation != sign(.listen).tiffRepresentation)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = SignView(.listen)
        view.systemReduces = { false }
        #expect(!view.animating)
        window.contentView?.addSubview(view)
        #expect(view.animating)
        // A resting breath asks few frames; a turn asks more.
        #expect(view.rate == 12)
        view.state = .think
        #expect(view.rate == 30)
        view.state = .sleep
        #expect(view.rate == 12)
        view.state = .unknown
        #expect(!view.animating)
        view.state = .think
        view.systemReduces = { true }
        #expect(!view.animating && view.pose == .rest)
        view.systemReduces = { false }
        view.motion = .reduced
        #expect(!view.animating && view.pose == .rest)
        view.arrive()
        #expect(!view.animating && view.pose == .rest)
        view.removeFromSuperview()
    }

    @Test func theMiniEyesAreAStillTemplateWithTheStatesWord() throws {
        var pictures = Set<Data?>()
        for state in Sign.State.allCases {
            let image = Sign.miniEyes(state)
            #expect(image.isTemplate && image.size == NSSize(width: 16, height: 10))
            #expect(image.accessibilityDescription == state.word)
            pictures.insert(try render(image.size) { image.draw(in: NSRect(origin: .zero, size: image.size)) }.tiffRepresentation)
        }
        #expect(pictures.count == Sign.State.allCases.count)
        #expect(Sign.State.allCases.map(\.word) == ["Idle", "Working", "Waiting for You", "Idle", "Asleep", "Ended", "Can’t Tell"])
        #expect(!Sign.miniEyes(.limit, template: false).isTemplate)
    }

    @Test func theViewSaysItsStateToVoiceOver() {
        let view = SignView(.wait)
        #expect(view.accessibilityRole() == .image && view.isAccessibilityElement())
        #expect(view.accessibilityLabel() == "Waiting for You")
        view.name = "Your assistant"
        view.state = .sleep
        #expect(view.accessibilityLabel() == "Your assistant, Asleep")
        view.name = ""
        #expect(!view.isAccessibilityElement())
    }

    @Test func theViewPicturesItselfThroughCacheDisplay() throws {
        let view = SignView(.listen)
        view.motion = .reduced
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        #expect((rep.colorAt(x: Int(4.41 * scale), y: Int(12.87 * scale))?.alphaComponent ?? 0) > 0.5)
        #expect((rep.colorAt(x: Int(22 * scale), y: Int(22 * scale))?.alphaComponent ?? 1) < 0.5)
    }

    @Test func theHardShadowFallsDownAndRightOnlyAroundTheSurface() throws {
        for (appearance, ink) in [(day, 0x121316), (night, 0xF1F1EE)] {
            let rep = try render(NSSize(width: 60, height: 60), appearance) { Sign.grab(CGRect(x: 10, y: 10, width: 40, height: 40), radius: 16) }
            func hex(_ x: CGFloat, _ y: CGFloat) -> Int? {
                guard let c = rep.colorAt(x: Int(x * 2), y: Int(y * 2))?.usingColorSpace(.sRGB), c.alphaComponent > 0.5 else { return nil }
                return Int((c.redComponent * 255).rounded()) << 16 | Int((c.greenComponent * 255).rounded()) << 8 | Int((c.blueComponent * 255).rounded())
            }
            // Below and right of the surface, the copy (bitmap y counts from the top, the drawing's from the bottom).
            let drop = try #require(hex(30, 51.5), "\(appearance.name.rawValue)")
            #expect([16, 8, 0].allSatisfy { abs((drop >> $0 & 0xFF) - (ink >> $0 & 0xFF)) < 12 }, "\(String(drop, radix: 16))")
            #expect(hex(51.5, 30) != nil && hex(30, 8.8) != nil && hex(7.6, 30) == nil && hex(30, 7.6) == nil)
            #expect(hex(30, 30) == (appearance == day ? 0xFFFFFF : 0x1F2126))
        }
        #expect(Sign.Lift.held.rawValue == 5 && Sign.Lift.rest.rawValue == 3 && Sign.Lift.small.rawValue == 2)
    }

    /// The seven states side by side as the mockup's strip shows them (34 pt, 60 pt apart, on bg2), by day and night.
    @Test func theSevenStatesArePictured() throws {
        guard let gallery else { return }
        try FileManager.default.createDirectory(at: gallery, withIntermediateDirectories: true)
        for (appearance, suffix) in [(day, ""), (night, "-dark")] {
            let size = NSSize(width: 60 * 7 + 20, height: 54)
            let rep = try render(size, appearance) {
                Look.Token.bg2.color.setFill()
                NSRect(origin: .zero, size: size).fill()
                for (index, state) in Sign.State.allCases.enumerated() {
                    Sign.draw(state, in: CGRect(x: 10 + 60 * CGFloat(index) + 13, y: 10, width: 34, height: 34), flipped: false)
                }
            }
            try #require(rep.representation(using: .png, properties: [:])).write(to: gallery.appendingPathComponent("sign-states\(suffix).png"))
            let minis = try render(NSSize(width: 7 * 26, height: 14), appearance) {
                for (index, state) in Sign.State.allCases.enumerated() {
                    Sign.miniEyes(state, template: false).draw(in: NSRect(x: 26 * CGFloat(index) + 5, y: 2, width: 16, height: 10))
                }
            }
            try #require(minis.representation(using: .png, properties: [:])).write(to: gallery.appendingPathComponent("sign-mini\(suffix).png"))
        }
    }
}
