// The look of something's own windows, the identity "smt1" Emi kept (Encre on Lin, a monochrome night): its colours
// with their night twins, radii, rows, type scale, shadows, curves, and whether motion is calm or reduced. Views read
// these tokens instead of naming a colour or a size, so night, the person's Motion choice and the system's Reduce
// Motion reach every window the same way. The values are the mockup's, exactly; spaces keep their own colours.
import AppKit

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

    /// The font of `face` at `size` and `weight`. Until the fonts are bundled, or when one fails to register, it is
    /// the system's: New York for titles and the agent's voice (the mockup falls back to a serif), San Francisco for
    /// the interface, SF Mono for code.
    static func font(_ face: Face, size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if let family = face.family {
            let wanted = NSFontDescriptor(fontAttributes: [.family: family, .traits: [NSFontDescriptor.TraitKey.weight: weight]])
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

    // MARK: Motion

    /// A cubic Bézier curve, by its two control points.
    struct Curve: Equatable {
        let x1: Float, y1: Float, x2: Float, y2: Float
        var timing: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: x1, y1, x2, y2) }
    }

    /// "Douce", for what moves in place, and "out", for what arrives: calm, no bounce.
    static let douce = Curve(x1: 0.45, y1: 0, x2: 0.25, y2: 1)
    static let out = Curve(x1: 0.16, y1: 1, x2: 0.3, y2: 1)

    /// Calm (the default) or Reduced, as the person chooses in Settings.
    enum Motion: String, CaseIterable, Codable {
        case calm, reduced
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
}
