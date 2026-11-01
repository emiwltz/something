// The drawings that explain something: each a pure function of `t`, the seconds since it began, so it holds no state,
// plays only while `Schemas.playing` runs it, and draws its finished picture at t = ∞, which is what Reduced motion
// and Help show. The welcome's beats draw them on their dotted paper; `PowersMap` is also Settings › Permissions'. Colours
// are tokens, except the pages' own.
import SomethingAgents
import SwiftUI

enum Schemas {
    /// The paper's size, the mockup's: every drawing here is placed against it.
    static let paper = CGSize(width: 596, height: 532)
    /// The Week-end page's dusk and the brown of its notes, a page's colours, the same by day and by night.
    static let dusk = gradient([(0x26335E, 0), (0x5B4B83, 0.34), (0xB86A7E, 0.62), (0xEE9A72, 0.84), (0xF7C98B, 1)])
    static let brown = color(0x3A2418)

    static func color(_ hex: Int) -> Color { Color(red: Double(hex >> 16) / 255, green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255) }

    static func gradient(_ stops: [(Int, Double)]) -> LinearGradient {
        LinearGradient(stops: stops.map { .init(color: color($0), location: $1) }, startPoint: .top, endPoint: .bottom)
    }

    /// How far a move of `length` seconds beginning at `start` has come at `t`, from 0 to 1, easing out.
    static func ease(_ t: Double, _ start: Double, _ length: Double) -> Double {
        let done = min(max((t - start) / length, 0), 1)
        return 1 - pow(1 - done, 3)
    }

    /// Draws `schema` at each moment from `start` for `length` seconds, then still; finished at once under Reduced `motion`.
    @ViewBuilder static func playing<Schema: View>(from start: Date, for length: Double, motion: Look.Motion, @ViewBuilder _ schema: @escaping (Double) -> Schema) -> some View {
        if Look.motion(motion) == .calm {
            TimelineView(Frames(start: start, length: length)) { schema($0.date.timeIntervalSince(start)) }
        } else {
            schema(.infinity)
        }
    }

    /// Thirty frames a second for `length` seconds, then none: a schema that ended costs nothing.
    struct Frames: TimelineSchedule {
        let start: Date, length: Double

        func entries(from date: Date, mode: Mode) -> [Date] {
            [date] + stride(from: 0.0, through: length + 1 / 30, by: 1 / 30).map { start.addingTimeInterval($0) }.filter { $0 > date }
        }
    }
}

extension View {
    /// Rises `by` points into place and fades in, as `done` goes from 0 to 1.
    func rising(_ done: Double, by: CGFloat = 7) -> some View { opacity(done).offset(y: by * (1 - done)) }
}

/// The dotted paper a schema is drawn on.
struct Paper<Schema: View>: View {
    @ViewBuilder let schema: Schema

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        ZStack(alignment: .topLeading) {
            Dots(step: 16, radius: 1).fill(Look.Token.line.ui)
            schema
        }
        .frame(width: Schemas.paper.width, height: Schemas.paper.height, alignment: .topLeading)
        .boxed(shape, Look.Token.bg.ui, ring: Look.Token.line.ui)
        .clipShape(shape)
    }
}

/// *A space*: a blank page fills itself, Export is a real arrow out to one file, and the Mac's edge is drawn with the
/// lock sitting on it.
struct PageSchema: View {
    static let length = 4.6
    static let label = "A blank page fills itself, in a file called week-end.html. Export makes one file. All of it stays on this Mac."
    let t: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14).strokeBorder(Look.Token.line2.ui, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: 556, height: 472).offset(x: 20, y: 20)
            Text("This Mac").font(Look.fixed(.ui, size: 11, weight: .semibold)).foregroundStyle(Look.Token.ink3.ui)
                .padding(.horizontal, 6).background(Look.Token.bg.ui).offset(x: 34, y: 13)
            document.offset(x: 52, y: 52)
            Line(path: "M356 428 C 424 428 464 400 464 318", arrow: true).trim(from: 0, to: Schemas.ease(t, 3, 0.8))
                .stroke(Look.Token.ink2.ui, style: StrokeStyle(lineWidth: 1.8, lineCap: .round)).frame(width: 596, height: 532)
            file.frame(width: 96).rising(Schemas.ease(t, 3.65, 0.5), by: 8).offset(x: 416, y: 150)
            HStack(spacing: 7) {
                Image(systemName: "lock").font(.system(size: 10.5))
                Text("Nothing leaves your Mac.")
            }
            .font(Look.fixed(.ui, size: 12.5, weight: .semibold)).padding(.horizontal, 13).frame(height: 28)
            .boxed(RoundedRectangle(cornerRadius: 13, style: .continuous), Look.Token.bg2.ui, ring: Look.Token.ink.ui, width: 1.5)
            .frame(width: Schemas.paper.width).offset(y: 478).opacity(Schemas.ease(t, 4, 0.5))
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(Self.label).accessibilityAddTraits(.isImage)
    }

    private var document: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<3) { _ in Circle().fill(Look.Token.mist.ui).frame(width: 6, height: 6) }
                Text("week-end.html").font(Look.fixed(.code, size: 11)).foregroundStyle(Look.Token.ink3.ui).padding(.leading, 6)
            }
            .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            page
            HStack(spacing: 8) {
                Text("~/something/spaces").font(Look.fixed(.code, size: 11.5, weight: .medium)).padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Look.Token.sunk.ui, in: RoundedRectangle(cornerRadius: 4))
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 10.5, weight: .medium))
                    Text("Export")
                }
                .font(Look.fixed(.ui, size: 12, weight: .semibold)).foregroundStyle(Look.Token.actfg.ui).padding(.horizontal, 10).frame(height: 26)
                .background(Look.Token.act.ui, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .padding(.leading, 12).padding(.trailing, 8).frame(height: 42)
            .overlay(alignment: .top) { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }
        }
        .frame(width: 304, height: 404)
        .background(Look.Token.bg2.ui, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        // The sun rises over the page and its foot, under the page's words.
        .overlay(alignment: .bottom) { sun.offset(y: -2) }
        .overlay { words.padding(.top, 26).padding(.bottom, 42) }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Look.Token.ink.ui, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }

    /// The page itself, the Week-end page's own colours: white paper, then its dusk.
    private var page: some View {
        ZStack {
            Color(red: 1, green: 254 / 255, blue: 252 / 255)
            Schemas.gradient([(0x26335E, 0), (0x5B4B83, 0.3), (0xB86A7E, 0.58), (0xEE9A72, 0.8), (0xF7C98B, 1)]).opacity(Schemas.ease(t, 0.8, 0.9))
        }
    }

    /// What fills the page, one row after another.
    private var words: some View {
        func row(_ k: Double) -> Double { Schemas.ease(t, 1.3 + k * 0.2, 0.55) }
        return VStack(alignment: .leading, spacing: 12) {
            Text("UNTIL THE WEEKEND").font(Look.fixed(.ui, size: 11, weight: .semibold)).kerning(0.77).opacity(0.7).rising(row(0))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                ForEach([("1", "day"), ("05", "hours"), ("40", "min")], id: \.0) { number, unit in
                    Text(number).font(Look.fixed(.title, size: 44, weight: .semibold)).kerning(-1.1)
                    Text(unit).font(Look.fixed(.ui, size: 13)).opacity(0.7).padding(.trailing, 10)
                }
            }
            .rising(row(1))
            Text("Saturday 24 October.").font(Look.fixed(.title, size: 17, weight: .semibold)).rising(row(2))
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                Text("SATURDAY PLANS").font(Look.fixed(.ui, size: 10.5, weight: .semibold)).kerning(0.95).foregroundStyle(Schemas.color(0x7A5A68))
                Text("Market at nine. Call Léa about the bikes.").font(Look.fixed(.title, size: 14, weight: .semibold)).lineSpacing(2).foregroundStyle(Schemas.color(0x2A2238))
                    .fixedSize(horizontal: false, vertical: true).rising(row(4))
            }
            .padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Schemas.color(0xFFFAF6).opacity(0.94), in: RoundedRectangle(cornerRadius: 10)).rising(row(3))
        }
        .padding(EdgeInsets(top: 20, leading: 20, bottom: 16, trailing: 20)).foregroundStyle(.white)
    }

    /// CSS's farthest corner: on its 150 box the gradient's radius is 106.
    private var sun: some View {
        Circle().fill(RadialGradient(stops: [.init(color: Schemas.color(0xFFE2A0).opacity(0.95), location: 0), .init(color: Schemas.color(0xFFD68C).opacity(0.32), location: 0.62),
                                             .init(color: Schemas.color(0xFFD68C).opacity(0), location: 0.72)], center: .center, startRadius: 0, endRadius: 106))
            .frame(width: 150, height: 150).rising(Schemas.ease(t, 1.5, 1.3), by: 46)
    }

    private var file: some View {
        VStack(spacing: 7) {
            ZStack {
                Line(path: "M9 1 H 42 L 63 21 V 70 Q 63 79 54 79 H 9 Q 0 79 0 70 V 10 Q 0 1 9 1").fill(Look.Token.bg2.ui)
                Line(path: "M9 1 H 42 L 63 21 V 70 Q 63 79 54 79 H 9 Q 0 79 0 70 V 10 Q 0 1 9 1 M42 1 V 21 H 63").stroke(Look.Token.ink.ui, lineWidth: 1.5)
                Text("html").font(Look.fixed(.code, size: 13, weight: .semibold)).foregroundStyle(Look.Token.ink2.ui).offset(y: 14)
            }
            .frame(width: 64, height: 80)
            Text("week-end.html").font(Look.fixed(.ui, size: 12.5, weight: .semibold)).fixedSize()
            Text("One file, yours").font(Look.fixed(.ui, size: 11.5)).foregroundStyle(Look.Token.ink3.ui).fixedSize().padding(.top, -4)
        }
    }
}

extension Schemas {
    /// The programs that act without asking, the only exception to "only you answer".
    static var neverAsk: [String] { Registry.app.agents.filter { $0.neverAsks || $0.asksNothingByDefault }.map(\.name) }

    /// A real folder's outline, `tab` wide at its top left: the drawing is the word.
    static func folder(_ width: CGFloat, _ height: CGFloat, tab: CGFloat = 62) -> Line {
        Line(path: "M10 1 H \(tab + 10) Q \(tab + 16) 1 \(tab + 19) 5 L \(tab + 22) 9 H \(width - 11) Q \(width - 1) 9 \(width - 1) 19 V \(height - 11) Q \(width - 1) \(height - 1) \(width - 11) \(height - 1) "
            + "H 11 Q 1 \(height - 1) 1 \(height - 11) V 11 Q 1 1 10 1")
    }

    /// A word on a line of a drawing, on the paper, in a hairline.
    static func label(_ words: String, symbol: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9)) }
            Text(words)
        }
        .font(Look.fixed(.ui, size: 11, weight: .medium)).foregroundStyle(Look.Token.ink2.ui).padding(.horizontal, 7).frame(height: 20)
        .boxed(RoundedRectangle(cornerRadius: 6), Look.Token.bg.ui, ring: Look.Token.line2.ui)
    }

    /// The place tag: In something, In iTerm.
    static func tag(_ words: String) -> some View {
        Text(words).font(Look.fixed(.ui, size: 10, weight: .medium)).foregroundStyle(Look.Token.ink2.ui).padding(.horizontal, 5).padding(.vertical, 1)
            .background(Look.Token.sunk.ui, in: RoundedRectangle(cornerRadius: 5))
    }

    /// A monogram in ink: the program a drawing is about.
    static func mark(_ name: String, side: CGFloat) -> some View {
        Text(Monogram.letters(name)).font(Look.fixed(.ui, size: side * 0.42, weight: .semibold)).foregroundStyle(Look.Token.bg2.ui).frame(width: side, height: side)
            .background(Look.Token.ink.ui, in: RoundedRectangle(cornerRadius: side * 0.28))
    }

    /// The arrow of a plain line, with its word above it, pointing left or right.
    static func arrow(_ word: String, width: CGFloat, left: Bool = false) -> some View {
        Line(path: left ? "M\(width) 7 H 1" : "M0 7 H \(width - 1)", arrow: true).stroke(Look.Token.ink3.ui, lineWidth: 1.5).frame(width: width, height: 14)
            .overlay(alignment: .bottom) { Text(word).font(Look.fixed(.ui, size: 10.5, weight: .medium)).foregroundStyle(Look.Token.ink3.ui).fixedSize().offset(y: -11) }
    }
}

/// *An agent*: the conversation, the program, the two folders it touches, and something reading from the side. With no
/// `program`, the same drawing in dashes.
struct AgentSchema: View {
    /// What the drawing says of one program: where it is, what it keeps, the folders it was seen in.
    struct Program { let name: String, path: String, home: String, folders: [String] }
    static let length = 2.6
    let program: Program?, t: Double

    private var label: String {
        (program.map { "An agent is one conversation, here in iTerm, with \($0.name): the program at \($0.path), its home folder \($0.home), your project folders." } ?? "No program yet.")
            + " something sees them all and changes nothing."
    }

    var body: some View {
        let line = Look.Token.ink2.ui, none = program == nil
        ZStack(alignment: .topLeading) {
            Group {
                Line(path: "M168 42 H 188", arrow: true).stroke(Look.Token.ink3.ui, lineWidth: 1.5)
                Line(path: "M252 100 C 252 128 146 118 146 146", arrow: true).stroke(line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                Line(path: "M344 100 C 344 128 450 118 450 146", arrow: true).stroke(line, lineWidth: 1.8)
                if !none {
                    Line(path: "M146 322 V 272", arrow: true).stroke(Look.Token.ink3.ui, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.5, 5]))
                    Line(path: "M450 268 V 296").stroke(Look.Token.ink3.ui, style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                }
            }
            .frame(width: Schemas.paper.width, height: 400).opacity(Schemas.ease(t, 0.7, 0.5))
            sentence.rising(Schemas.ease(t, 0.25, 0.5))
            if !none {
                Text("An agent").font(Look.fixed(.ui, size: 11, weight: .semibold)).foregroundStyle(Look.Token.ink3.ui).offset(x: 26, y: 1).rising(Schemas.ease(t, 0.25, 0.5))
                Schemas.tag("In iTerm").offset(x: 24, y: 72).rising(Schemas.ease(t, 0.25, 0.5))
            }
            programCard.offset(x: 190, y: 6).rising(Schemas.ease(t, 0.5, 0.5))
            folder("Its home folder") { homeFacts }.offset(x: 24, y: 146).rising(Schemas.ease(t, 0.95, 0.5))
            folder("Your project folders") { folders }.offset(x: 328, y: 146).rising(Schemas.ease(t, 1.15, 0.5))
            Schemas.label("keeps").offset(x: 164, y: 106).opacity(Schemas.ease(t, 1, 0.5))
            Schemas.label("works in").offset(x: 388, y: 106).opacity(Schemas.ease(t, 1, 0.5))
            if !none {
                Schemas.label("reads", symbol: "eye").offset(x: 156, y: 286).opacity(Schemas.ease(t, 1.45, 0.5))
                something.offset(x: 24, y: 322).rising(Schemas.ease(t, 1.45, 0.5))
                terminal.offset(x: 328, y: 296).rising(Schemas.ease(t, 1.6, 0.5))
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityAddTraits(.isImage)
    }

    private var sentence: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.fill").font(.system(size: 10)).foregroundStyle(Look.Token.actfg.ui).frame(width: 24, height: 24).background(Look.Token.act.ui, in: Circle())
            Text("“Add a search field”").font(Look.fixed(.ui, size: 12.5, weight: .medium)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 8).padding(.trailing, 10).frame(width: 144, height: 48, alignment: .leading)
        .boxed(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 3, bottomTrailingRadius: 12, topTrailingRadius: 12), Look.Token.bg2.ui, ring: Look.Token.line2.ui)
        .offset(x: 24, y: 18)
    }

    private var programCard: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return HStack(spacing: 10) {
            if let program { Schemas.mark(program.name, side: 32) } else { Monogram(name: "?", side: 32, fixed: true) }
            VStack(alignment: .leading, spacing: 3) {
                Text("The program").font(Look.fixed(.ui, size: 11, weight: .semibold)).foregroundStyle(Look.Token.ink3.ui)
                Text(program?.name ?? "No program yet").font(Look.fixed(.title, size: 15, weight: .semibold)).foregroundStyle((program == nil ? Look.Token.ink2 : .ink).ui)
                Text(program?.path ?? "Not installed yet").font(Look.fixed(.code, size: 10)).foregroundStyle((program == nil ? Look.Token.ink3 : .ink2).ui).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.horizontal, 12).frame(width: 216, height: 94, alignment: .leading)
        .background(program == nil ? Color.clear : Look.Token.bg2.ui, in: shape)
        .overlay(shape.strokeBorder(program == nil ? Look.Token.line2.ui : Look.Token.ink.ui, style: StrokeStyle(lineWidth: 1.5, dash: program == nil ? [5, 4] : [])))
    }

    private func folder<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        let outline = Schemas.folder(244, 122)
        return ZStack(alignment: .topLeading) {
            outline.fill(program == nil ? Color.clear : Look.Token.bg2.ui)
            outline.stroke(Look.Token.line2.ui, style: StrokeStyle(lineWidth: 1.5, dash: program == nil ? [5, 4] : []))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Look.fixed(.ui, size: 11, weight: .semibold)).foregroundStyle(Look.Token.ink3.ui)
                content()
            }
            .padding(EdgeInsets(top: 18, leading: 14, bottom: 10, trailing: 12))
        }
        .frame(width: 244, height: 122)
    }

    private var homeFacts: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(program?.home ?? Registry.app.agents.compactMap(\.home).prefix(2).joined(separator: ", ") + "…").font(Look.fixed(.code, size: 12, weight: .medium)).padding(.horizontal, 5).padding(.vertical, 2)
                .background(Look.Token.sunk.ui, in: RoundedRectangle(cornerRadius: 4)).padding(.bottom, 2)
            if let program {
                ForEach([("gearshape", "Settings"), ("message", "Its conversations stay with \(program.name)")], id: \.0) { symbol, words in
                    HStack(spacing: 6) {
                        Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(Look.Token.ink3.ui)
                        Text(words).font(Look.fixed(.ui, size: 12.5)).foregroundStyle(Look.Token.ink2.ui).lineLimit(2)
                    }
                }
            }
        }
    }

    @ViewBuilder private var folders: some View {
        if let found = program?.folders, !found.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(found.prefix(3), id: \.self) { path in
                    HStack(spacing: 6) {
                        Image(systemName: "folder").font(.system(size: 10)).foregroundStyle(Look.Token.ink3.ui)
                        Text(path).font(Look.fixed(.code, size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
        } else {
            Text("Wherever you ask it to work").font(Look.fixed(.ui, size: 12.5)).foregroundStyle(Look.Token.ink2.ui)
        }
    }

    private var something: some View {
        HStack(spacing: 11) {
            PageSign(state: .listen, side: 28, lands: false, motion: .reduced).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("something").font(Look.fixed(.ui, size: 13, weight: .semibold))
                Text("Sees them all. Changes nothing.").font(Look.fixed(.ui, size: 12)).foregroundStyle(Look.Token.ink2.ui).fixedSize()
            }
        }
        .padding(.horizontal, 14).frame(width: 244, height: 60, alignment: .leading)
        .boxed(RoundedRectangle(cornerRadius: 10, style: .continuous), Look.Token.bg2.ui, ring: Look.Token.line2.ui)
    }

    /// A terminal, dark by day and by night.
    private var terminal: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(["read login.js", "edit login.js", "npm test"].enumerated()), id: \.offset) { index, command in
                (Text("$ ").foregroundColor(Schemas.color(0x7C7E84)) + Text(command)).opacity(Schemas.ease(t, 1.9 + Double(index) * 0.3, 0.3))
            }
            Text("✓ 12 passed").foregroundStyle(Schemas.color(0x7BC79B)).opacity(Schemas.ease(t, 2.8, 0.3))
        }
        .font(Look.fixed(.code, size: 11, weight: .medium)).lineSpacing(1).foregroundStyle(Schemas.color(0xC9CAC6)).padding(.horizontal, 12)
        .frame(width: 244, height: 86, alignment: .leading).background(Schemas.color(0x17181C), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// *Two roles*: two cards joined by ≠, each role drawn in its own folder, three short lines under it; under them the
/// chips of the assistant, which the window gives, then the one line about folders.
struct RolesSchema<Chips: View>: View {
    let none: Bool
    @ViewBuilder let chips: Chips

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                card(sign: AnyView(PageSign(state: .listen, side: 40, lands: false, motion: .reduced).frame(width: 40, height: 40)), verb: "builds", path: "~/something/spaces",
                     inside: AnyView(ForEach(0..<3) { _ in page(24, 30, Look.Token.line2.ui, 1) }),
                     title: "Your assistant", line: none ? "An agent you install, with a job: it builds a space. Each space has its own." : "An agent with a job: it builds a space. Each space has its own.") {
                    row("folder", "Works in this folder")
                    row("pencil", "May change your spaces and run something’s own commands")
                    row("hand.raised", "Anything else asks you")
                }
                Spacer(minLength: 0)
                card(sign: AnyView(page(38, 46, Look.Token.ink.ui, 1.5)), verb: "shows", path: "~/code/shop",
                     inside: AnyView(ForEach(Registry.app.agents.prefix(3).map(\.name), id: \.self) { Monogram(name: $0, side: 24, fixed: true) }),
                     title: "Agents a space shows", line: "They live on your Mac. A space only shows them.") {
                    row("folder", "Work in your project folders")
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "eye").font(.system(size: 11)).foregroundStyle(Look.Token.ink3.ui).frame(width: 14)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) { Text("This space may"); word("watch") }
                            HStack(spacing: 0) { word("these agents"); Text(".") }
                            Text("You choose, for each space").font(Look.fixed(.ui, size: 12)).foregroundStyle(Look.Token.ink2.ui)
                        }
                    }
                    row("gearshape", "They keep their own settings")
                }
            }
            .frame(width: 564, height: 362).offset(x: 16, y: 14)
            Text("≠").font(Look.fixed(.ui, size: 18, weight: .semibold)).frame(width: 34, height: 34).boxed(Circle(), Look.Token.bg2.ui, ring: Look.Token.ink.ui, width: 1.5)
                .accessibilityLabel("is not the same as").offset(x: 281, y: 178)
            HStack(spacing: 8) { chips }.frame(width: Schemas.paper.width, height: 40).offset(y: 392)
            Text("Your assistant’s folder gives a space nothing.").font(Look.fixed(.ui, size: 12.5, weight: .semibold)).padding(.horizontal, 13).frame(height: 28)
                .boxed(RoundedRectangle(cornerRadius: 13, style: .continuous), Look.Token.bg2.ui, ring: Look.Token.ink.ui, width: 1.5).frame(width: Schemas.paper.width).offset(y: 458)
        }
    }

    private func page(_ width: CGFloat, _ height: CGFloat, _ ring: Color, _ line: CGFloat) -> some View {
        Image(systemName: "doc").font(.system(size: width > 30 ? 15 : 11)).foregroundStyle(Look.Token.ink3.ui).frame(width: width, height: height)
            .boxed(RoundedRectangle(cornerRadius: width > 30 ? 7 : 5), Look.Token.bg.ui, ring: ring, width: line)
    }

    private func word(_ words: String) -> some View {
        Text(words).fontWeight(.semibold).padding(.horizontal, 5).padding(.vertical, 1).background(Look.Token.hover.ui, in: RoundedRectangle(cornerRadius: 5)).fixedSize()
    }

    private func row(_ symbol: String, _ words: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Look.Token.ink3.ui).frame(width: 14)
            Text(words).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func card<Rows: View>(sign: AnyView, verb: String, path: String, inside: AnyView, title: String, line: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                sign
                Schemas.arrow(verb, width: 46)
                ZStack(alignment: .top) {
                    Schemas.folder(136, 104, tab: 36).fill(Look.Token.bg2.ui)
                    Schemas.folder(136, 104, tab: 36).stroke(Look.Token.line2.ui, lineWidth: 1.5)
                    HStack(spacing: 5) { inside }.padding(.top, 24)
                    Text(path).font(Look.fixed(.code, size: 10.5, weight: .medium)).foregroundStyle(Look.Token.ink2.ui).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 12)
                }
                .frame(width: 136, height: 104)
            }
            .frame(height: 106).padding(.bottom, 12)
            Text(title).font(Look.fixed(.title, size: 20, weight: .semibold)).kerning(-0.24)
            Text(line).font(Look.fixed(.ui, size: 12)).foregroundStyle(Look.Token.ink3.ui).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
            Rectangle().fill(Look.Token.line.ui).frame(height: 1).padding(.vertical, 12)
            VStack(alignment: .leading, spacing: 11) { rows() }.font(Look.fixed(.ui, size: 13))
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16)).frame(width: 266, height: 362, alignment: .topLeading)
        .boxed(RoundedRectangle(cornerRadius: 13, style: .continuous), Look.Token.bg2.ui, ring: Look.Token.line2.ui)
    }
}

/// The map of who answers, one drawing for Settings › Permissions and the beat *Who answers*, 470 points wide and scaled
/// by whoever shows it: a space, its assistant and its agents, and you. While `full` Full Access is on, the assistant's
/// tag says so and its line to you fades.
struct PowersMap: View {
    static let size = CGSize(width: 470, height: 102)
    static let label = "A space shows your agents, as its sentence says. Its assistant builds it, and no space can write to its assistant. "
        + "An agent does what On Its Own says, in something or in another app. Everything else comes to you, in a window of your Mac: Allow Once or Deny."
    var full = false
    static let orange = Color(nsColor: Rules.orange)

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach([("Its sentence", 0.0, 84.0), ("On Its Own", 126, 212), ("The window", 372, 98)], id: \.0) { caption, x, width in
                Text(caption).font(Look.fixed(.ui, size: 10.5, weight: .semibold)).foregroundStyle(Look.Token.ink3.ui).frame(width: width, height: 14).offset(x: x)
            }
            VStack(spacing: 3) {
                Image(systemName: "doc").font(.system(size: 10)).foregroundStyle(Look.Token.ink2.ui).frame(width: 20, height: 20).background(Look.Token.sunk.ui, in: RoundedRectangle(cornerRadius: 5))
                Text("A space").font(Look.fixed(.ui, size: 12, weight: .semibold))
            }
            .frame(width: 84, height: 82).boxed(RoundedRectangle(cornerRadius: 9, style: .continuous), Look.Token.bg2.ui, ring: Look.Token.line2.ui).offset(y: 20)
            Schemas.arrow("builds", width: 36, left: true).offset(x: 87, y: 26)
            Schemas.arrow("shows", width: 36).offset(x: 87, y: 70)
            Schemas.arrow("asks", width: 28).offset(x: 341, y: 26).opacity(full ? 0.3 : 1)
            Schemas.arrow("ask", width: 28).offset(x: 341, y: 70)
            stack([(nil, "Its assistant", full ? "" : "In something")]).overlay(alignment: .trailing) { if full { fullTag } }.frame(height: 26).offset(x: 126, y: 20)
            let name = Registry.app.agents.first?.name ?? ""
            stack([(name, "Login form", "In something"), (name, "Fix the cart total", "In iTerm")]).frame(height: 50).offset(x: 126, y: 52)
            VStack(spacing: 2) {
                Image(systemName: "person").font(.system(size: 10)).foregroundStyle(Look.Token.ink2.ui).frame(width: 22, height: 22).background(Look.Token.sunk.ui, in: Circle())
                Text("You").font(Look.fixed(.ui, size: 12, weight: .semibold))
                Text("Allow Once · Deny").font(Look.fixed(.ui, size: 10.5)).foregroundStyle(Look.Token.ink3.ui).fixedSize()
            }
            .frame(width: 98, height: 82).boxed(RoundedRectangle(cornerRadius: 9, style: .continuous), Look.Token.bg2.ui, ring: Look.Token.ink.ui, width: 1.5).offset(x: 372, y: 20)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .accessibilityElement(children: .ignore).accessibilityLabel(Self.label + (full ? " While Full Access is on, something answers for your assistants." : "")).accessibilityAddTraits(.isImage)
    }

    private var fullTag: some View {
        HStack(spacing: 2) {
            Image(systemName: "bolt.fill").font(.system(size: 8))
            Text("Full Access")
        }
        .font(Look.fixed(.ui, size: 10, weight: .semibold)).foregroundStyle(Self.orange).padding(.horizontal, 5).padding(.vertical, 1)
        .background(Self.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 5)).padding(.trailing, 8)
    }

    /// Rows of an agent and its place, one above another in one card; no monogram: the assistant's sign.
    private func stack(_ rows: [(mono: String?, name: String, tag: String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 6) {
                    if let mono = row.mono { Monogram(name: mono, side: 16, fixed: true) } else { PageSign(state: .listen, side: 14, lands: false, motion: .reduced).frame(width: 14, height: 14) }
                    Text(row.name).font(Look.fixed(.ui, size: 11.5, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 4)
                    if !row.tag.isEmpty { Schemas.tag(row.tag) }
                }
                .frame(height: 24).overlay(alignment: .top) { if index > 0 { Rectangle().fill(Look.Token.line.ui).frame(height: 1) } }
            }
        }
        .padding(.horizontal, 8).frame(width: 212).frame(maxHeight: .infinity)
        .boxed(RoundedRectangle(cornerRadius: 9, style: .continuous), Look.Token.bg2.ui, ring: Look.Token.line2.ui)
    }
}

/// *Who answers*: the map, larger, over a space, with the request window half outside it, drawn since a window cannot
/// sit in a drawing; a request travels to it; then the two powers.
struct AnswerSchema: View {
    static let length = 3.2
    static let label = "A space shows your agents, as its sentence says. An agent does what On Its Own says. Everything else comes to you, in a window of your Mac: Deny or Allow Once."
    let t: Double

    var body: some View {
        let who = Registry.app.agents.first?.name ?? "An agent"
        ZStack(alignment: .topLeading) {
            PowersMap().scaleEffect(1.2, anchor: .topLeading).offset(x: 14, y: 14)
            Line(path: "M519 138 V 170", arrow: true).stroke(Look.Token.ink3.ui, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])).frame(width: 596, height: 200)
            ForEach([(CGPoint(x: 115, y: 106), CGPoint(x: 165, y: 106), 0.7), (CGPoint(x: 420, y: 106), CGPoint(x: 460, y: 106), 1.5), (CGPoint(x: 519, y: 137), CGPoint(x: 519, y: 172), 2.3)], id: \.2) { from, to, start in
                let done = min(max((t - start) / 0.6, 0), 1)
                Circle().fill(Look.Token.ink.ui).frame(width: 9, height: 9).padding(2).background(Look.Token.bg.ui, in: Circle()).opacity(done > 0 && done < 1 ? 1 : 0)
                    .position(x: from.x + (to.x - from.x) * done, y: from.y + (to.y - from.y) * done)
            }
            space.offset(x: 28, y: 200).opacity(Schemas.ease(t, 0.5, 0.5) * 0.9)
            window(who).offset(x: 232, y: 172).rising(Schemas.ease(t, 2.7, 0.5))
            HStack(spacing: 10) {
                power("What may a space do?") { Text("This space may"); word("watch"); word("these agents"); Text(".") }
                power("What may an agent do on its own?") { Text("On Its Own"); word("Accepts Edits") }
            }
            .frame(width: 568).offset(x: 14, y: 422)
            VStack(alignment: .leading, spacing: 2) {
                quiet("bolt.fill", PowersMap.orange, "Full Access lets your assistants stop asking. It’s off until you turn it on, beside your assistant.")
                quiet("exclamationmark.triangle", Look.Token.ink2.ui, "\(Schemas.neverAsk.joined(separator: ", ")): Never asks, by design. A space that may talk to them acts without you.")
            }
            .offset(x: 16, y: 482)
        }
        .frame(width: Schemas.paper.width, height: Schemas.paper.height, alignment: .topLeading)
        .accessibilityElement(children: .ignore).accessibilityLabel(Self.label).accessibilityAddTraits(.isImage)
    }

    private func word(_ words: String) -> some View {
        Text(words).fontWeight(.semibold).foregroundStyle(Look.Token.ink.ui).padding(.horizontal, 5).padding(.vertical, 1).background(Look.Token.hover.ui, in: RoundedRectangle(cornerRadius: 5))
    }

    private func power<Line: View>(_ question: String, @ViewBuilder _ line: () -> Line) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question).font(Look.fixed(.title, size: 13.5, weight: .semibold))
            HStack(spacing: 4) { line() }.font(Look.fixed(.ui, size: 12.5)).foregroundStyle(Look.Token.ink2.ui)
        }
        .padding(EdgeInsets(top: 9, leading: 12, bottom: 10, trailing: 12)).frame(maxWidth: .infinity, alignment: .leading)
        .boxed(RoundedRectangle(cornerRadius: 10, style: .continuous), Look.Token.bg2.ui, ring: Look.Token.line2.ui)
    }

    private func quiet(_ symbol: String, _ color: Color, _ words: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(color).padding(.top, 2)
            Text(words).font(Look.fixed(.ui, size: 12)).foregroundStyle(Look.Token.ink2.ui)
        }
    }

    /// A space behind the window, in a page's own colours.
    private var space: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<3) { _ in Circle().fill(Look.Token.mist.ui).frame(width: 6, height: 6) }
                Text("my-agents.html").font(Look.fixed(.code, size: 10)).foregroundStyle(Look.Token.ink3.ui).padding(.leading, 6)
            }
            .padding(.horizontal, 8).frame(height: 22).frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 10) {
                Text("My agents").font(Look.fixed(.title, size: 18, weight: .semibold)).foregroundStyle(Schemas.brown)
                ForEach([0.7, 0.54, 0.7], id: \.self) { Capsule().fill(Schemas.brown.opacity(0.2)).frame(width: 268 * $0, height: 8) }
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 0, trailing: 16)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Schemas.gradient([(0xFBE6CC, 0), (0xF2B79C, 1)]))
        }
        .frame(width: 300, height: 190).background(Look.Token.bg2.ui)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Look.Token.line2.ui))
    }

    private func window(_ who: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ForEach([Color.red.opacity(0.75), Look.Token.mist.ui, Look.Token.mist.ui], id: \.self) { Circle().fill($0).frame(width: 12, height: 12) }
                Spacer()
                PageSign(state: .listen, side: 13, lands: false, motion: .reduced).frame(width: 13, height: 13)
                Text("something").fontWeight(.semibold)
                Text("·  Permission").foregroundStyle(Look.Token.ink2.ui)
                Spacer()
            }
            .font(Look.fixed(.ui, size: 11.5)).padding(.horizontal, 14).frame(height: 32).background(Look.Token.sunk.ui)
            HStack(alignment: .top, spacing: 12) {
                PageSign(state: .listen, side: 36, lands: false, motion: .reduced).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(who) wants to run a command").font(Look.fixed(.title, size: 16.5, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text("My agents · in ~/code/shop · just now").font(Look.fixed(.ui, size: 11.5)).foregroundStyle(Look.Token.ink2.ui)
                }
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14))
            VStack(alignment: .leading, spacing: 6) {
                Text("The exact command · 1 line").font(Look.fixed(.ui, size: 10.5)).foregroundStyle(Look.Token.ink2.ui)
                Text("npm test").font(Look.fixed(.code, size: 11.5, weight: .medium))
            }
            .padding(EdgeInsets(top: 4, leading: 10, bottom: 8, trailing: 10)).frame(maxWidth: .infinity, alignment: .leading)
            .background(Look.Token.sunk.ui, in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 14)
            HStack(spacing: 6) {
                Image(systemName: "lock").font(.system(size: 10))
                Text("No space can see or click this window.")
            }
            .font(Look.fixed(.ui, size: 11.5)).foregroundStyle(Look.Token.ink2.ui).padding(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 14))
            HStack(spacing: 8) {
                Spacer()
                Text("Deny").frame(width: 86, height: 28).boxed(RoundedRectangle(cornerRadius: 8), Look.Token.bg2.ui, ring: Look.Token.line2.ui)
                Text("Allow Once").foregroundStyle(Look.Token.actfg.ui).frame(width: 112, height: 28).background(Look.Token.act.ui, in: RoundedRectangle(cornerRadius: 8))
            }
            .font(Look.fixed(.ui, size: 12.5, weight: .semibold)).padding(EdgeInsets(top: 10, leading: 14, bottom: 12, trailing: 14))
        }
        .frame(width: 340).background(Look.Token.bg2.ui, in: shape).clipShape(shape).overlay(shape.strokeBorder(Look.Token.ink.ui.opacity(0.5)))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }
}
