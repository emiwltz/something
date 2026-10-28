// something in one picture, drawn here rather than shipped as an image: a page in the middle, three of your agents on
// its left joined to it by the three kinds of line a level allows (Watch dotted, Talk dashed, Run plain with an arrow),
// your assistant on its right building it, and under it the small panel where whatever an agent asks waits and only
// you answer. One part may be lit, the others faded: the page, your agents (with the panel their requests reach), or
// your assistant (with the panel too); the page stays half lit, since everything is about it. The welcome shows it
// beside its three rows, and Help › How something Works in a window of its own, with a button per part and Replay.
// The agents shown are the first three the app knows, the folders and the request invented, so no line names an agent.
import AppKit
import SomethingAgents
import SwiftUI

struct Hero: View {
    enum Part: CaseIterable { case page, agents, assistant }
    static let size = CGSize(width: 720, height: 420)
    static let label = "something in one picture: a page in the middle; your agents around it, which the page may watch, talk to or run; "
        + "your assistant building the page; and the panel where only you answer."

    let light: HeroLight
    /// The assistant's line: its agent and model.
    let builder: String
    var motion = Look.Motion.calm
    let agents = Array(Registry.app.agents.prefix(3).map(\.name))

    /// The picture's pieces: what each part lights.
    private enum Piece { case page, agents, assistant, panel }

    var body: some View {
        let ink2 = Look.Token.ink2.ui
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Look.card).fill(Look.Token.bg.ui)
            Dots().fill(Look.Token.line2.ui)
            RoundedRectangle(cornerRadius: Look.card).strokeBorder(Look.Token.line.ui)
            Group {
                Line(path: "M180 97 C 226 97 224 118 270 118").stroke(ink2, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [0.5, 6]))
                Line(path: "M180 197 C 226 197 224 186 270 186").stroke(ink2, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 4]))
                Line(path: "M270 254 C 224 254 226 297 180 297", arrow: true).stroke(ink2, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                ForEach(Array(agents.enumerated()), id: \.offset) { index, name in
                    agent(name, ["~/code/pacman", "~/notes", "~/code/shop"][index], dot: [Look.Token.ok.ui, Look.Token.mist.ui, Look.Token.ink.ui][index])
                        .offset(x: 20, y: 70 + CGFloat(index) * 100)
                }
                tag("eye", "Watch").offset(x: 184, y: 74)
                tag("bubble.left", "Talk").offset(x: 190, y: 166)
                tag("play", "Run").offset(x: 196, y: 302)
            }
            .opacity(shown(.agents)).saturation(shown(.agents) < 1 ? 0 : 1)
            Group {
                Line(path: "M100 324 V 394 Q 100 402 108 402 H 500 Q 508 402 508 394 V 281 Q 508 273 516 273", arrow: true)
                    .stroke(Look.Token.ink3.ui, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 4]))
                tag(nil, "Whatever an agent asks waits here").offset(x: 200, y: 393)
                panel.offset(x: 516, y: 214)
                you.offset(x: 516, y: 342)
            }
            .opacity(shown(.panel)).saturation(shown(.panel) < 1 ? 0 : 1)
            Group {
                Line(path: "M530 112 H 482", arrow: true).stroke(ink2, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                Line(path: "M615 190 V 214", arrow: true).stroke(Look.Token.ink3.ui, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 4]))
                tag(nil, "Builds").offset(x: 486, y: 88)
                assistant.offset(x: 530, y: 40)
            }
            .opacity(shown(.assistant)).saturation(shown(.assistant) < 1 ? 0 : 1)
            Group {
                page.offset(x: 270, y: 48)
                HStack(spacing: 5) {
                    Text("A page").fontWeight(.semibold).foregroundStyle(Look.Token.ink.ui)
                    Text("· one file, yours")
                    tag("square.and.arrow.up", "Export")
                }
                .font(Look.font(.ui, size: 11.5).ui).foregroundStyle(ink2).frame(width: 212).offset(x: 270, y: 332)
            }
            .opacity(shown(.page)).saturation(shown(.page) < 1 ? 0 : 1)
        }
        .frame(width: Hero.size.width, height: Hero.size.height, alignment: .topLeading)
        .animation(Look.motion(motion) == .reduced ? nil : Look.douce.animation(0.45), value: light.lit)
        .accessibilityElement(children: .ignore).accessibilityLabel(Hero.label).accessibilityAddTraits(.isImage)
    }

    /// How much of `piece` shows: all of it with nothing lit or when its part is lit; the page half; the rest faintly.
    private func shown(_ piece: Piece) -> Double {
        switch (light.lit, piece) {
        case (nil, _), (.page, .page), (.agents, .agents), (.agents, .panel), (.assistant, .assistant), (.assistant, .panel): 1
        case (_, .page): 0.5
        default: 0.14
        }
    }

    // MARK: The pieces, at the mockup's sizes

    private func card<Content: View>(_ width: CGFloat, _ height: CGFloat?, @ViewBuilder _ content: () -> Content) -> some View {
        content().frame(width: width, height: height).boxed(RoundedRectangle(cornerRadius: 10, style: .continuous), Look.Token.bg2.ui, ring: Look.Token.line2.ui)
    }

    private func code(_ words: String) -> some View {
        Text(words).font(Look.font(.code, size: 10.5, weight: .medium).ui).foregroundStyle(Look.Token.ink2.ui)
            .padding(.horizontal, 5).padding(.vertical, 2).background(Look.Token.sunk.ui, in: RoundedRectangle(cornerRadius: 4))
    }

    private func agent(_ name: String, _ folder: String, dot: Color) -> some View {
        card(160, 54) {
            HStack(spacing: 9) {
                Monogram(name: name).scaleEffect(26 / 18).frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(Look.font(.ui, size: 12.5, weight: .semibold).ui).foregroundStyle(Look.Token.ink.ui)
                    Text(folder).font(Look.font(.code, size: 9.5).ui).foregroundStyle(Look.Token.ink3.ui).lineLimit(1)
                }
                Spacer(minLength: 0)
                Circle().fill(dot).frame(width: 7, height: 7)
            }
            .padding(.horizontal, 10)
        }
    }

    /// A line's label: a symbol and a word on the background, in a hairline.
    private func tag(_ symbol: String?, _ words: String) -> some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9)) }
            Text(words)
        }
        .font(Look.font(.ui, size: 10.5, weight: .medium).ui).foregroundStyle(Look.Token.ink2.ui)
        .padding(.horizontal, 7).frame(height: 20)
        .boxed(RoundedRectangle(cornerRadius: 6), Look.Token.bg.ui, ring: Look.Token.line2.ui)
    }

    /// The page, in its own colours (a page's, not the app's), the same by day and by night.
    private var page: some View {
        let brown = Color(red: 0x3A / 255, green: 0x24 / 255, blue: 0x18 / 255), note = Color.white.opacity(0.62)
        func lines(_ widths: [CGFloat]) -> some View {
            VStack(alignment: .leading, spacing: 6) { ForEach(widths, id: \.self) { Capsule().fill(brown.opacity(0.22)).frame(width: 160 * $0, height: 4) } }
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<3) { _ in Circle().fill(Look.Token.mist.ui).frame(width: 6, height: 6) }
                Text("week-end.html").font(Look.font(.code, size: 9.5).ui).foregroundStyle(Look.Token.ink3.ui).padding(.leading, 4)
            }
            .padding(.horizontal, 9).frame(maxWidth: .infinity, minHeight: 22, alignment: .leading).background(Look.Token.bg2.ui)
            VStack(alignment: .leading, spacing: 9) {
                Text("UNTIL SATURDAY, 9:00").font(Look.font(.ui, size: 9.5, weight: .semibold).ui).kerning(0.7).opacity(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    ForEach([("1", "day"), ("14", "h"), ("40", "min")], id: \.0) { number, unit in
                        Text(number).font(Look.font(.title, size: 28, weight: .semibold).ui)
                        Text(unit).font(Look.font(.ui, size: 10).ui).opacity(0.7).padding(.trailing, 7)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Saturday plans").font(Look.font(.ui, size: 10.5, weight: .semibold).ui)
                    lines([0.78, 0.56])
                }
                .padding(9).frame(maxWidth: .infinity, alignment: .leading).background(note, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Before the weekend").font(Look.font(.ui, size: 10.5, weight: .semibold).ui)
                    ForEach(Array(agents.enumerated()), id: \.offset) { index, name in
                        HStack(spacing: 6) {
                            Text(Monogram.letters(name)).font(Look.font(.ui, size: 6.5, weight: .semibold).ui).frame(width: 13, height: 13)
                                .background(brown.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                            Capsule().fill(brown.opacity(0.22)).frame(width: index == 1 ? 70 : 100, height: 4)
                            Spacer(minLength: 0)
                            Circle().fill([Look.Token.ok.ui, brown.opacity(0.25), brown][index]).frame(width: 7, height: 7)
                        }
                    }
                }
                .padding(9).frame(maxWidth: .infinity, alignment: .leading).background(note, in: RoundedRectangle(cornerRadius: 8))
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 14, leading: 14, bottom: 12, trailing: 14))
            .foregroundStyle(brown)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(LinearGradient(stops: [.init(color: Color(red: 0.984, green: 0.902, blue: 0.8), location: 0),
                                               .init(color: Color(red: 0.973, green: 0.812, blue: 0.682), location: 0.55),
                                               .init(color: Color(red: 0.949, green: 0.718, blue: 0.612), location: 1)], startPoint: .top, endPoint: .bottom))
        }
        .frame(width: 212, height: 272)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Look.Token.ink.ui, lineWidth: 1.5))
    }

    private var assistant: some View {
        card(170, 150) {
            VStack(spacing: 6) {
                PageSign(state: .listen, side: 48, lands: false, motion: .reduced).frame(width: 48, height: 48)
                Text("Your assistant").font(Look.font(.ui, size: 12.5, weight: .semibold).ui).foregroundStyle(Look.Token.ink.ui)
                Text(builder).font(Look.font(.ui, size: 10.5).ui).foregroundStyle(Look.Token.ink2.ui).lineLimit(1).minimumScaleFactor(0.8)
                code("~/something/spaces")
            }
            .padding(.horizontal, 8)
        }
    }

    private var panel: some View {
        card(184, 118) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    ForEach(0..<3) { _ in Circle().fill(Look.Token.mist.ui).frame(width: 5, height: 5) }
                    Text("something · Permission").font(Look.font(.ui, size: 9.5).ui).foregroundStyle(Look.Token.ink3.ui).padding(.leading, 4)
                }
                Text("\(agents.last ?? "An agent") wants to run a command").font(Look.font(.ui, size: 11.5, weight: .semibold).ui)
                    .foregroundStyle(Look.Token.ink.ui).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) { code("npm test"); Text("in ~/code/shop") }.font(Look.font(.ui, size: 10).ui).foregroundStyle(Look.Token.ink2.ui)
                HStack(spacing: 6) {
                    Spacer()
                    Text("Deny").padding(.horizontal, 8).frame(height: 20).boxed(RoundedRectangle(cornerRadius: 5), Look.Token.bg2.ui, ring: Look.Token.line2.ui)
                    Text("Allow Once").foregroundStyle(Look.Token.actfg.ui).padding(.horizontal, 8).frame(height: 20)
                        .background(Look.Token.act.ui, in: RoundedRectangle(cornerRadius: 5))
                }
                .font(Look.font(.ui, size: 10.5, weight: .medium).ui)
            }
            .padding(EdgeInsets(top: 8, leading: 10, bottom: 9, trailing: 10))
        }
    }

    private var you: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "person.fill").font(.system(size: 9)).foregroundStyle(Look.Token.actfg.ui).frame(width: 20, height: 20)
                .background(Look.Token.act.ui, in: Circle())
            Text("Only you answer, in a window of your Mac.").font(Look.font(.ui, size: 10.5).ui).foregroundStyle(Look.Token.ink2.ui)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 184, alignment: .leading)
    }
}

/// The picture fitted to `width`, at its own proportions.
struct FittedHero: View {
    let hero: Hero, width: CGFloat

    var body: some View {
        let k = width / Hero.size.width
        hero.scaleEffect(k, anchor: .topLeading).frame(width: width, height: Hero.size.height * k, alignment: .topLeading)
    }
}

/// Which part is lit, and the cycle that lights each in turn as the picture opens.
@Observable final class HeroLight {
    var lit: Hero.Part?
    @ObservationIgnored private var cycles = 0

    /// Lights the three parts once, in turn, then the whole picture, as the mockup's welcome does; nothing moves under
    /// Reduced `motion`. A new cycle, or a part lit by hand, ends the one playing.
    func cycle(_ motion: Look.Motion) {
        cycles += 1
        let cycle = cycles
        lit = nil
        guard Look.motion(motion) == .calm else { return }
        for (part, at) in [(Hero.Part?.some(.page), 0.5), (.agents, 1.7), (.assistant, 2.9), (nil, 4.3)] {
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
                if self?.cycles == cycle { self?.lit = part }
            }
        }
    }

    /// Lights `part` (nil: all), ending the cycle.
    func light(_ part: Hero.Part?) {
        cycles += 1
        lit = part
    }
}

/// A path of the mockup's SVG, in its own coordinates: moves, lines, cubic and quadratic curves, with an arrow head at
/// its end when `arrow`.
private struct Line: Shape {
    let path: String
    var arrow = false

    func path(in rect: CGRect) -> Path {
        var path = Path(), numbers: [CGFloat] = [], command: Character = "M", last = CGPoint.zero, before = CGPoint.zero
        func point(_ i: Int) -> CGPoint { CGPoint(x: numbers[i], y: numbers[i + 1]) }
        func flush() {
            switch command {
            case "M": path.move(to: point(0)); last = point(0)
            case "C": path.addCurve(to: point(4), control1: point(0), control2: point(2)); (before, last) = (point(2), point(4))
            case "Q": path.addQuadCurve(to: point(2), control: point(0)); (before, last) = (point(0), point(2))
            case "H": before = last; last.x = numbers[0]; path.addLine(to: last)
            case "V": before = last; last.y = numbers[0]; path.addLine(to: last)
            default: break
            }
            numbers = []
        }
        // A command's letter may lead its first number ("M180 97").
        for token in self.path.split(separator: " ") {
            var token = token
            if let letter = token.first, letter.isLetter {
                if !numbers.isEmpty { flush() }
                (command, token) = (letter, token.dropFirst())
            }
            if let number = Double(token) { numbers.append(CGFloat(number)) }
        }
        flush()
        guard arrow else { return path }
        let angle = atan2(last.y - before.y, last.x - before.x)
        for side in [-1.0, 1.0] {
            path.move(to: last)
            path.addLine(to: CGPoint(x: last.x - 7 * cos(angle + side * 0.5), y: last.y - 7 * sin(angle + side * 0.5)))
        }
        return path
    }
}

/// The dotted grid under the picture, every 14 points.
private struct Dots: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for x in stride(from: 7, to: rect.width, by: 14) {
            for y in stride(from: 7, to: rect.height, by: 14) { path.addEllipse(in: CGRect(x: x - 0.7, y: y - 0.7, width: 1.4, height: 1.4)) }
        }
        return path
    }
}

// MARK: Help › How something Works

@MainActor extension App {
    @objc func showHowItWorks(_ sender: Any?) {
        HowItWorks.show(builder: "\(assistant.name) · \(assistant.modelWords.model)", motion: library.preferences.motion)
    }
}

/// Help › How something Works: the picture in a window of its own, a button per part that lights it (pressed again,
/// all of it), and Replay, which lights each part in turn again.
@MainActor
enum HowItWorks {
    static let size = NSSize(width: 860, height: 730)
    private static var window: NSWindow?
    static let light = HeroLight()

    /// Shows the window, made once and kept, with `lit` lit (nil: all of it).
    static func show(builder: String, motion: Look.Motion, lit: Hero.Part? = nil) {
        made(builder: builder, motion: motion, lit: lit).makeKeyAndOrderFront(nil)
    }

    /// The window, made once and kept, not shown yet, `lit` lit.
    static func made(builder: String, motion: Look.Motion, lit: Hero.Part? = nil) -> NSWindow {
        let made = window ?? NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        if window == nil {
            (made.isReleasedWhenClosed, made.title) = (false, "How something Works")
            made.center()
        }
        made.contentView = NSHostingView(rootView: HowItWorksView(light: light, builder: builder, motion: motion))
        window = made
        light.light(lit)
        return made
    }
}

struct HowItWorksView: View {
    let light: HeroLight, builder: String, motion: Look.Motion
    static let parts: [(Hero.Part, String, String)] = [
        (.page, "A page", "One HTML file in ~/something/spaces. Yours, exported in one click."),
        (.agents, "Your agents", "The coding agents on your Mac. A page may Watch them, Talk to them, or Run one in a folder you pick."),
        (.assistant, "Your assistant", "One of your agents, at work on the page, only in the pages folder. Anything else, it asks you."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("something in one picture").font(Look.font(.ui, size: 11.5, weight: .medium).ui).foregroundStyle(Look.Token.ink3.ui)
            Text("A page, your agents, your assistant").font(Look.font(.title, size: 24, weight: .semibold).ui).padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            Text("Three things, and how they meet. Everything stays on this Mac.").foregroundStyle(Look.Token.ink2.ui).padding(.top, 2)
            Hero(light: light, builder: builder, motion: motion).frame(maxWidth: .infinity).padding(.top, 22)
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(Self.parts.enumerated()), id: \.offset) { index, part in
                    let on = light.lit == part.0
                    Button { light.light(on ? nil : part.0) } label: {
                        HStack(alignment: .top, spacing: 9) {
                            Text("\(index + 1)").font(Look.font(.ui, size: 11, weight: .semibold).ui).foregroundStyle((on ? Look.Token.actfg : .ink2).ui)
                                .frame(width: 20, height: 20).boxed(RoundedRectangle(cornerRadius: 6), (on ? Look.Token.act : .bg2).ui, ring: Look.Token.line.ui)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(part.1).font(Look.font(.ui, size: 12.5, weight: .semibold).ui)
                                Text(part.2).font(Look.font(.ui, size: 11.5).ui).foregroundStyle(Look.Token.ink2.ui).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(EdgeInsets(top: 9, leading: 10, bottom: 10, trailing: 10)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .boxed(RoundedRectangle(cornerRadius: 8), (on ? Look.Token.sel : .bg2).ui, ring: (on ? Look.Token.ink2 : .line).ui, width: on ? 1.5 : 1)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(part.1): \(part.2)").accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
            .fixedSize(horizontal: false, vertical: true).padding(.top, 16)
            Rectangle().fill(Look.Token.line.ui).frame(height: 1).padding(.top, 16)
            HStack(spacing: 7) {
                Image(systemName: "lock").font(.system(size: 10.5)).accessibilityHidden(true)
                Text("Only you answer, in a window of your Mac. A page can’t see or answer it.")
                Button { light.cycle(motion) } label: {
                    HStack(spacing: 6) { Image(systemName: "arrow.clockwise").font(.system(size: 11)); Text("Replay") }
                        .font(Look.font(.ui, size: 12.5, weight: .semibold).ui)
                }
                .buttonStyle(Secondary()).padding(.leading, 12)
                Spacer()
            }
            .font(Look.font(.ui, size: 12.5).ui).foregroundStyle(Look.Token.ink2.ui).padding(.top, 14)
        }
        .font(Look.font(.ui, size: 13.5).ui).foregroundStyle(Look.Token.ink.ui)
        .padding(EdgeInsets(top: 26, leading: 40, bottom: 18, trailing: 40))
        .frame(width: HowItWorks.size.width, height: HowItWorks.size.height, alignment: .topLeading)
        .background(Look.Token.bg.ui)
    }
}
