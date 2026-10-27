// The look holds the mockup's identity exactly: every colour resolves to its hex by day and by night, the inks keep
// their contrast on the backgrounds they are read on, the sizes and curves are the mockup's, the bundled fonts register
// for the process alone and draw their exact weight, a missing font falls back to the system's, and motion is reduced
// by the person's choice or the system's setting. No window is shown.
import AppKit
import Testing
@testable import something

@MainActor @Suite struct LookTests {
    let day = NSAppearance(named: .aqua)!, night = NSAppearance(named: .darkAqua)!

    /// `color` as the appearance draws it, as 0xRRGGBB and an opacity rounded to three places.
    func resolved(_ color: NSColor, in appearance: NSAppearance) -> (hex: UInt32, alpha: Double) {
        var result: (UInt32, Double) = (0, 0)
        appearance.performAsCurrentDrawingAppearance {
            let c = color.usingColorSpace(.sRGB)!
            func byte(_ v: CGFloat) -> UInt32 { UInt32((v * 255).rounded()) }
            result = (byte(c.redComponent) << 16 | byte(c.greenComponent) << 8 | byte(c.blueComponent),
                      (Double(c.alphaComponent) * 1000).rounded() / 1000)
        }
        return result
    }

    /// The mockup's tokens.css, by day and by night: hex and opacity.
    let mockup: [String: (day: UInt32, dayAlpha: Double, night: UInt32, nightAlpha: Double)] = [
        "bg": (0xF4F4F1, 1, 0x15171C, 1), "bg2": (0xFFFFFF, 1, 0x1F2126, 1), "side": (0xECECE7, 1, 0x1A1C21, 1),
        "sunk": (0xE9E9E4, 1, 0x111317, 1), "ink": (0x121316, 1, 0xF1F1EE, 1), "ink2": (0x5C5E66, 1, 0xA5A6AA, 1),
        "ink3": (0x8A8C92, 1, 0x7C7E84, 1), "e": (0x24262C, 1, 0xE4E4E0, 1), "mist": (0xDADAD5, 1, 0x2E3036, 1),
        "line": (0x121316, 0.10, 0xF1F1EE, 0.11), "line2": (0x121316, 0.17, 0xF1F1EE, 0.19),
        "hover": (0x121316, 0.05, 0xF1F1EE, 0.06), "sel": (0x121316, 0.075, 0xF1F1EE, 0.095),
        "act": (0x24262C, 1, 0xF1F1EE, 1), "actfg": (0xFFFFFF, 1, 0x121316, 1), "ok": (0x2A7D57, 1, 0x7BC79B, 1),
        "bad": (0xC23A35, 1, 0xF07A6E, 1), "glass": (0xF4F4F1, 0.94, 0x1A1C21, 0.93), "scrim": (0x121316, 0.18, 0x000000, 0.42),
        // v6d.css's Needs You, kept by v6.2.
        "ad-y": (0xE0A21A, 1, 0xF2C14E, 1), "ad-yt": (0x7A5300, 1, 0xF2C14E, 1), "ad-ys": (0xE0A21A, 0.14, 0xF2C14E, 0.13),
    ]

    @Test func everyTokenResolvesToTheMockupsHexByDayAndByNight() {
        #expect(Set(Look.Token.allCases.map(\.rawValue)) == Set(mockup.keys))
        for token in Look.Token.allCases {
            let want = mockup[token.rawValue]!
            let d = resolved(token.color, in: day), n = resolved(token.color, in: night)
            #expect(d.hex == want.day && d.alpha == want.dayAlpha, "\(token) by day: \(String(d.hex, radix: 16)) \(d.alpha)")
            #expect(n.hex == want.night && n.alpha == want.nightAlpha, "\(token) by night: \(String(n.hex, radix: 16)) \(n.alpha)")
        }
        // The high-contrast appearances take the same twin as their plain one.
        #expect(resolved(Look.Token.ink.color, in: NSAppearance(named: .accessibilityHighContrastDarkAqua)!).hex == 0xF1F1EE)
        #expect(resolved(Look.Token.ink.color, in: NSAppearance(named: .accessibilityHighContrastAqua)!).hex == 0x121316)
    }

    /// The WCAG contrast ratio of two opaque colours.
    func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ hex: UInt32) -> Double {
            func channel(_ shift: UInt32) -> Double {
                let v = Double((hex >> shift) & 0xFF) / 255
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    @Test func theInksKeepTheirContrastOnTheBackgrounds() {
        for appearance in [day, night] {
            for background in [Look.Token.bg, .bg2] {
                let ground = resolved(background.color, in: appearance).hex
                for (ink, least) in [(Look.Token.ink, 7.0), (.ink2, 4.5), (.ink3, 3.0)] {
                    let ratio = contrast(resolved(ink.color, in: appearance).hex, ground)
                    #expect(ratio >= least, "\(ink) on \(background) in \(appearance.name.rawValue): \(ratio)")
                }
            }
            // The primary button's words on its fill read as body text does.
            #expect(contrast(resolved(Look.Token.actfg.color, in: appearance).hex, resolved(Look.Token.act.color, in: appearance).hex) >= 7)
            // Needs You's words on the sidebar read as a label does.
            let side = resolved(Look.Token.side.color, in: appearance).hex
            #expect(contrast(resolved(Look.Token.needInk.color, in: appearance).hex, side) >= 4.5, "\(appearance.name.rawValue)")
        }
        // The rail's letters, white, on each tile colour, at 3:1: the mockup's palette (its amber, pink and teal fall
        // between 3.7 and 4.1), kept because each tile is a single letter read as a glyph, its name said in full by
        // the tooltip and VoiceOver, never a word to read.
        for tone in Look.tiles { #expect(contrast(0xFFFFFF, tone) >= 3, "\(String(tone, radix: 16))") }
    }

    @Test func theSizesAndTheScaleAreTheMockups() {
        #expect((Look.card, Look.control, Look.window) == (10, 7, 12))
        #expect((Look.row, Look.density) == (25, 0.75))
        let scale = [Look.xs, Look.small, Look.medium, Look.body, Look.large].map(\.size)
        #expect(scale == [10.5, 11.5, 12.5, 13, 15])
        let titles = [Look.titleS, Look.titleM, Look.titleL, Look.titleXL]
        #expect(titles.map(\.size) == [17, 22, 34, 44] && titles.map(\.leading) == [1.2, 1.15, 1.06, 1.04])
        #expect(titles.allSatisfy { $0.face == .title && $0.weight == .semibold })
    }

    @Test func aFontFallsBackToTheSystemsClosest() {
        #expect(Look.Face.title.family == "Fraunces" && Look.Face.ui.family == "Onest" && Look.Face.voice.family == "Young Serif")
        for face in [Look.Face.title, .ui, .voice, .code] {
            let font = Look.font(face, size: 13)
            #expect(font.pointSize == 13)
            // Bundled or not, a title is never the interface's sans serif, and code is always monospaced.
            if face == .code { #expect(font.isFixedPitch) }
            if face == .title || face == .voice {
                #expect(font.familyName != NSFont.systemFont(ofSize: 13).familyName, "\(face): \(font.familyName ?? "")")
            }
        }
        #expect(Look.titleXL.font.pointSize == 44)
    }

    /// The value of each axis of `font`, by its four-letter tag; an axis at its default is left out by CoreText.
    func axes(_ font: NSFont) -> [String: Double] {
        var variation = CTFontCopyVariation(font) as? [Int: Double] ?? [:]
        for axis in CTFontCopyVariationAxes(font) as? [[String: Any]] ?? [] {
            if let tag = axis[kCTFontVariationAxisIdentifierKey as String] as? Int, variation[tag] == nil {
                variation[tag] = axis[kCTFontVariationAxisDefaultValueKey as String] as? Double
            }
        }
        return Dictionary(uniqueKeysWithValues: variation.map { tag, value in
            (String(decoding: (0..<4).map { UInt8(truncatingIfNeeded: tag >> (24 - 8 * $0)) }, as: UTF8.self), value)
        })
    }

    @Test func theBundledFontsRegisterForThisProcessAndDrawTheirWeight() {
        let fonts = Home.share.appendingPathComponent("fonts")
        #expect(Look.register(fonts: fonts).isEmpty)
        #expect(Look.register(fonts: fonts).isEmpty, "registering twice is harmless")
        for (file, license) in [("Fraunces", "OFL-Fraunces"), ("Onest", "OFL-Onest"), ("YoungSerif-Regular", "OFL-YoungSerif")] {
            #expect(FileManager.default.fileExists(atPath: fonts.appendingPathComponent(license + ".txt").path), "\(file) has its licence")
        }
        for name in ["Fraunces", "Onest", "Young Serif"] { #expect(NSFont(name: name, size: 13) != nil, "\(name)") }
        for face in [Look.Face.title, .ui, .voice] { #expect(Look.font(face, size: 13).familyName == face.family) }
        // The weight is the wght axis exactly, and it draws: semibold is wider than regular.
        let words = "Ready to build something today?"
        for face in [Look.Face.title, .ui] {
            let regular = Look.font(face, size: 22), semibold = Look.font(face, size: 22, weight: .semibold)
            #expect(axes(regular)["wght"] == 400 && axes(semibold)["wght"] == 600, "\(face)")
            func width(_ font: NSFont) -> CGFloat { (words as NSString).size(withAttributes: [.font: font]).width }
            #expect(width(semibold) > width(regular), "\(face): \(width(semibold)) against \(width(regular))")
        }
        // Fraunces's optical size follows the size, as font-optical-sizing: auto does.
        #expect(axes(Look.titleXL.font)["opsz"] == 44 && axes(Look.titleS.font)["opsz"] == 17)
        #expect(Look.css(.medium) == 500 && Look.css(.bold) == 700)
    }

    @Test func theFloatShadowAndTheCurvesAreTheMockups() {
        let soft = Look.float(day), dark = Look.float(night)
        #expect(soft.map(\.y) == [1, 14] && soft.map(\.blur) == [2, 36] && soft.map(\.spread) == [0, -14])
        #expect(dark.map(\.y) == [1, 18] && dark.map(\.blur) == [2, 44] && dark.map(\.spread) == [0, -14])
        #expect(soft.map { resolved($0.color, in: day).alpha } == [0.06, 0.3] && dark.map { resolved($0.color, in: night).alpha } == [0.35, 0.75])
        #expect(Look.floatRing.token == .line2 && Look.floatRing.width == 1)
        #expect(Look.douce == Look.Curve(x1: 0.45, y1: 0, x2: 0.25, y2: 1))
        #expect(Look.out == Look.Curve(x1: 0.16, y1: 1, x2: 0.3, y2: 1))
        var point: [Float] = [0, 0]
        Look.douce.timing.getControlPoint(at: 1, values: &point)
        #expect(point == [0.45, 0])
    }

    @Test func motionIsReducedByTheChoiceOrTheSystem() {
        #expect(Look.motion(.calm, systemReduces: false) == .calm)
        #expect(Look.motion(.calm, systemReduces: true) == .reduced)
        #expect(Look.motion(.reduced, systemReduces: false) == .reduced)
        #expect(Look.motion(.reduced, systemReduces: true) == .reduced)
        #expect(Look.duration(0.3, .calm) == 0.3 && Look.duration(0.3, .reduced) == 0)
    }
}
