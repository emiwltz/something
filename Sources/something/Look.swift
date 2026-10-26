// The look of something's own windows, the identity "smt1" Emi kept (Encre on Lin, a monochrome night): its colours
// with their night twins, radii, rows, type scale, shadows, curves, and whether motion is calm or reduced. Views read
// these tokens instead of naming a colour or a size, so night, the person's Motion choice and the system's Reduce
// Motion reach every window the same way. The values are the mockup's, exactly; spaces keep their own colours.
import AppKit
import SwiftUI

enum Look {
    // MARK: Colours

    /// A colour of the identity, named as the mockup names its token (`--ink`, `--line2`…).
    enum Token: String, CaseIterable {
        case bg, bg2, side, sunk, ink, ink2, ink3, eyes = "e", mist, line, line2, hover, sel, act, actfg, ok, bad, glass, scrim

        /// The day value and its night twin, as 0xRRGGBB with an opacity, the way the mockup writes them.
        var tone: (day: UInt32, dayAlpha: CGFloat, night: UInt32, nightAlpha: CGFloat) {
            switch self {
            case .bg: (0xF4F4F1, 1, 0x15171C, 1)
            case .bg2: (0xFFFFFF, 1, 0x1F2126, 1)
            case .side: (0xECECE7, 1, 0x1A1C21, 1)
            case .sunk: (0xE9E9E4, 1, 0x111317, 1)
            case .ink: (0x121316, 1, 0xF1F1EE, 1)
            case .ink2: (0x5C5E66, 1, 0xA5A6AA, 1)
            case .ink3: (0x8A8C92, 1, 0x7C7E84, 1)
            case .eyes: (0x24262C, 1, 0xE4E4E0, 1)
            case .mist: (0xDADAD5, 1, 0x2E3036, 1)
            // Lines and fills are the ink at a low opacity, so they sit right on any of the backgrounds.
            case .line: (0x121316, 0.10, 0xF1F1EE, 0.11)
            case .line2: (0x121316, 0.17, 0xF1F1EE, 0.19)
            case .hover: (0x121316, 0.05, 0xF1F1EE, 0.06)
            case .sel: (0x121316, 0.075, 0xF1F1EE, 0.095)
            case .act: (0x24262C, 1, 0xF1F1EE, 1)
            case .actfg: (0xFFFFFF, 1, 0x121316, 1)
            case .ok: (0x2A7D57, 1, 0x7BC79B, 1)
            case .bad: (0xC23A35, 1, 0xF07A6E, 1)
            case .glass: (0xF4F4F1, 0.94, 0x1A1C21, 0.93)
            case .scrim: (0x121316, 0.18, 0x000000, 0.42)
            }
        }

        /// The colour, resolved by the appearance it is drawn in: the day value under aqua, the night twin under
        /// darkAqua (and their high-contrast variants).
        var color: NSColor {
            let tone = tone, name = "something." + rawValue
            return NSColor(name: NSColor.Name(name)) { appearance in
                Look.isDark(appearance) ? Look.srgb(tone.night, tone.nightAlpha) : Look.srgb(tone.day, tone.dayAlpha)
            }
        }
    }

    /// Whether `appearance` is a night one.
    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// `hex` (0xRRGGBB) at `alpha`, in sRGB, the space the mockup's CSS colours are in.
    static func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        func part(_ shift: UInt32) -> CGFloat { CGFloat((hex >> shift) & 0xFF) / 255 }
        return NSColor(srgbRed: part(16), green: part(8), blue: part(0), alpha: alpha)
    }

    // MARK: Sizes

    /// Corner radii: cards and panels, controls, windows.
    static let card: CGFloat = 10, control: CGFloat = 7, window: CGFloat = 12
    /// A list row in Emi's compact density, and the factor the mockup applies to a menu item's padding with it.
    static let row: CGFloat = 25, density: CGFloat = 0.75

    // MARK: Type

    /// The four voices: titles (Fraunces), the interface (Onest), the agent (Young Serif), and code.
    enum Face {
        case title, ui, voice, code

        /// The bundled family it asks for first; code uses the system's monospaced font.
        var family: String? {
            switch self {
            case .title: "Fraunces"
            case .ui: "Onest"
            case .voice: "Young Serif"
            case .code: nil
            }
        }
    }

    /// One step of the mockup's type scale: a face, a size in points, a weight and a line height (a multiple).
    struct Style {
        let face: Face, size: CGFloat, weight: NSFont.Weight, leading: CGFloat

        /// The font of this step: the bundled family when it is registered, else the system's closest.
        var font: NSFont { Look.font(face, size: size, weight: weight) }
    }

    static let xs = Style(face: .ui, size: 10.5, weight: .regular, leading: 1.45)
    static let small = Style(face: .ui, size: 11.5, weight: .regular, leading: 1.45)
    static let medium = Style(face: .ui, size: 12.5, weight: .regular, leading: 1.45)
    static let body = Style(face: .ui, size: 13, weight: .regular, leading: 1.45)
    static let large = Style(face: .ui, size: 15, weight: .regular, leading: 1.45)
    static let titleS = Style(face: .title, size: 17, weight: .semibold, leading: 1.2)
    static let titleM = Style(face: .title, size: 22, weight: .semibold, leading: 1.15)
    static let titleL = Style(face: .title, size: 34, weight: .semibold, leading: 1.06)
    static let titleXL = Style(face: .title, size: 44, weight: .semibold, leading: 1.04)

    /// Registers the font files of `folder` (share/fonts) for this process only, so nothing is installed on the Mac.
    /// Returns the files that did not register; one already registered counts as registered.
    @discardableResult
    static func register(fonts folder: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "ttf" }.filter { file in
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(file as CFURL, .process, &error) { return false }
            return CFErrorGetCode(error?.takeRetainedValue()) != CTFontManagerError.alreadyRegistered.rawValue
        }
    }

    /// The CSS weight of `weight` (400 regular, 600 semibold…), the value of a variable font's wght axis.
    static func css(_ weight: NSFont.Weight) -> CGFloat {
        [.thin: 100, .ultraLight: 200, .light: 300, .medium: 500, .semibold: 600, .bold: 700, .heavy: 800, .black: 900][weight] ?? 400
    }

    /// `font` slanted as a browser draws a synthetic italic: the bundled Onest has no italic face, and the mockup sets
    /// a few words in italic all the same.
    static func oblique(_ font: NSFont) -> NSFont {
        let slant = AffineTransform(m11: 1, m12: 0, m21: 0.2, m22: 1, tX: 0, tY: 0)
        return NSFont(descriptor: font.fontDescriptor.withMatrix(slant), size: font.pointSize) ?? font
    }

    /// The font of `face` at `size` and `weight`. The bundled families are variable: the weight is set on their wght
    /// axis exactly, and Fraunces's optical size follows the size as the mockup's `font-optical-sizing: auto` does.
    /// When a family is not registered it is the system's: New York for titles and the agent's voice (the mockup falls
    /// back to a serif), San Francisco for the interface, SF Mono for code.
    static func font(_ face: Face, size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if let family = face.family {
            let wght = 0x7767_6874, opsz = 0x6F70_737A   // the axes' four-letter tags
            let axes: [Int: CGFloat] = face == .title ? [wght: css(weight), opsz: size] : [wght: css(weight)]
            let variation = NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
            let wanted = NSFontDescriptor(fontAttributes: [.family: family, variation: axes])
            // AppKit answers a missing family with a substitute: only the family asked for counts.
            if let font = NSFont(descriptor: wanted, size: size), font.familyName == family { return font }
        }
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        switch face {
        case .ui: return system
        case .code: return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        case .title, .voice:
            return system.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? system
        }
    }

    // MARK: Shadows

    /// One layer of a shadow, in the mockup's terms: y grows downward, and spread grows (or, negative, shrinks) the
    /// shape before the blur.
    struct Shade: Equatable {
        let color: NSColor, y: CGFloat, blur: CGFloat, spread: CGFloat
    }

    /// The soft shadow of floating things (menus, sheets, panels, the palette), two layers, plus a 1 pt ring of
    /// `line2` around the shape. Night darkens it with black, as the mockup does. The hard offset shadow ("portée")
    /// belongs only to what a person grabs; the sign draws it (F6).
    static func float(_ appearance: NSAppearance) -> [Shade] {
        isDark(appearance)
            ? [Shade(color: srgb(0x000000, 0.35), y: 1, blur: 2, spread: 0), Shade(color: srgb(0x000000, 0.75), y: 18, blur: 44, spread: -14)]
            : [Shade(color: srgb(0x121316, 0.06), y: 1, blur: 2, spread: 0), Shade(color: srgb(0x121316, 0.30), y: 14, blur: 36, spread: -14)]
    }

    /// The ring that goes with the float shadow.
    static let floatRing = (token: Token.line2, width: CGFloat(1))

    /// The float shadow under a card of `box` in `appearance`, cast by a shape of `fill`, with its ring when `ring`.
    static func drawFloat(_ box: CGRect, radius: CGFloat, fill: Token, ring: Bool, appearance: NSAppearance) {
        for shade in float(appearance) {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            (shadow.shadowColor, shadow.shadowBlurRadius, shadow.shadowOffset) = (shade.color, shade.blur / 2, NSSize(width: 0, height: -shade.y))
            shadow.set()
            fill.color.setFill()
            NSBezierPath(roundedRect: box.insetBy(dx: -shade.spread, dy: -shade.spread), xRadius: radius, yRadius: radius).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        guard ring else { return }
        floatRing.token.color.setStroke()
        let ring = NSBezierPath(roundedRect: box.insetBy(dx: -0.5, dy: -0.5), xRadius: radius + 0.5, yRadius: radius + 0.5)
        ring.lineWidth = floatRing.width
        ring.stroke()
    }

    // MARK: Motion

    /// A cubic Bézier curve, by its two control points.
    struct Curve: Equatable {
        let x1: Float, y1: Float, x2: Float, y2: Float
        var timing: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: x1, y1, x2, y2) }

        /// The curve as SwiftUI's keyframes take it.
        var unit: UnitCurve {
            .bezier(startControlPoint: UnitPoint(x: CGFloat(x1), y: CGFloat(y1)), endControlPoint: UnitPoint(x: CGFloat(x2), y: CGFloat(y2)))
        }

        /// The curve's height where it is `x` across, both from 0 to 1: its parameter found by bisection, which this
        /// monotonic curve allows.
        func value(at x: Double) -> Double {
            func bezier(_ t: Double, _ a: Float, _ b: Float) -> Double {
                let u = 1 - t
                return 3 * u * u * t * Double(a) + 3 * u * t * t * Double(b) + t * t * t
            }
            guard x > 0 else { return 0 }
            guard x < 1 else { return 1 }
            var (low, high) = (0.0, 1.0)
            for _ in 0..<40 {
                let mid = (low + high) / 2
                if bezier(mid, x1, x2) < x { low = mid } else { high = mid }
            }
            return bezier((low + high) / 2, y1, y2)
        }
    }

    /// "Douce", for what moves in place, and "out", for what arrives: calm, no bounce.
    static let douce = Curve(x1: 0.45, y1: 0, x2: 0.25, y2: 1)
    static let out = Curve(x1: 0.16, y1: 1, x2: 0.3, y2: 1)

    /// Calm (the default) or Reduced, as the person chooses in Settings.
    enum Motion: String, CaseIterable, Codable {
        case calm, reduced
    }

    /// The motion the person chose in Settings, as the app last applied it (Settings.apply): what a view with no
    /// preferences at hand plays, such as the request panel and a sheet's switch.
    static var chosen = Motion.calm

    /// The appearance the app draws in for the person's choice: nil follows the Mac's (Auto).
    static func appearance(_ choice: Preferences.Appearance) -> NSAppearance? {
        switch choice {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// The motion to play: Reduced when the person chose it or when the system's Reduce Motion is on.
    /// `systemReduces` is the seam tests replace.
    static func motion(_ chosen: Motion,
                       systemReduces: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) -> Motion {
        chosen == .reduced || systemReduces ? .reduced : .calm
    }

    /// How long a change that lasts `calm` seconds takes under `motion`: no time at all when it is reduced, so the
    /// view jumps to where it ends.
    static func duration(_ calm: TimeInterval, _ motion: Motion) -> TimeInterval {
        motion == .reduced ? 0 : calm
    }

    /// Plays `changes` (made through `animator()`) in `duration` on `curve`, then calls `done` once. AppKit moves a
    /// view's frame and alpha on the display's refresh, which stops while the display sleeps or the window is hidden:
    /// a quarter second after the end, whatever has not landed lands at once, so no state waits for a screen.
    /// `settle` are the views whose stalled animations are taken off when it lands that way.
    static func animate(_ duration: TimeInterval, _ curve: Curve, implicit: Bool = false, settle: [NSView] = [],
                        _ changes: @escaping () -> Void, done: (() -> Void)? = nil) {
        final class Once { var over = false }
        let once = Once()
        let finish = {
            guard !once.over else { return }
            once.over = true
            done?()
        }
        NSAnimationContext.runAnimationGroup({ context in
            (context.duration, context.timingFunction, context.allowsImplicitAnimation) = (duration, curve.timing, implicit)
            changes()
        }, completionHandler: finish)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.25) {
            guard !once.over else { return }
            settle.forEach { $0.layer?.removeAllAnimations() }
            NSAnimationContext.runAnimationGroup { context in
                (context.duration, context.allowsImplicitAnimation) = (0, false)
                changes()
            }
            finish()
        }
    }
}

extension Look.Token {
    /// The token as a SwiftUI colour, resolved by the appearance it is drawn in.
    var ui: Color { Color(nsColor: color) }
}

extension Look.Curve {
    /// The curve as a SwiftUI animation lasting `duration` seconds.
    func animation(_ duration: TimeInterval) -> Animation { .timingCurve(Double(x1), Double(y1), Double(x2), Double(y2), duration: duration) }
}

extension View {
    /// The view on `fill` in `shape`, ringed in `ring` `width` points wide inside the shape's edge.
    func boxed<S: InsettableShape>(_ shape: S, _ fill: Color, ring: Color, width: CGFloat = 1) -> some View {
        background(fill, in: shape).overlay(shape.strokeBorder(ring, lineWidth: width))
    }
}

extension NSFont {
    /// The font as SwiftUI draws it.
    var ui: Font { Font(self as CTFont) }
}

extension NSImage {
    /// The system symbol `name` at `size` points and `weight`; an empty image when the system has none.
    static func symbol(_ name: String, _ size: CGFloat, _ weight: NSFont.Weight) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size, weight: weight)) ?? NSImage()
    }

    /// The image filled with `color` wherever it draws: a symbol's template image takes no tint when drawn by hand.
    func tinted(_ color: NSColor) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    /// Draws the image in `color` into `box` of a flipped view.
    func draw(_ color: NSColor, flippedIn box: CGRect) {
        tinted(color).draw(in: box, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

extension NSImageView {
    /// A view of the system symbol `name` at `size` points and `weight`, in `tint`.
    static func symbol(_ name: String, _ size: CGFloat, _ weight: NSFont.Weight, tint: Look.Token) -> NSImageView {
        let view = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage())
        (view.symbolConfiguration, view.contentTintColor) = (NSImage.SymbolConfiguration(pointSize: size, weight: weight), tint.color)
        return view
    }
}

extension Timer {
    /// A timer on the main run loop that calls `step` every `interval` seconds until `step` returns false. It runs in
    /// every mode, a sheet's modal loop or an open menu included, unless `common` is false.
    static func frames(_ interval: TimeInterval, common: Bool = true, _ step: @escaping () -> Bool) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { timer in
            if !step() { timer.invalidate() }
        }
        RunLoop.main.add(timer, forMode: common ? .common : .default)
        return timer
    }
}
