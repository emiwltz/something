// The drawings that explain something: each a pure function of `t`, the seconds since it began, so it holds no state,
// plays only while `Schemas.playing` runs it, and draws its finished picture at t = ∞, which is what Reduced motion
// and Help show. The welcome's beats draw them on their dotted paper. Colours are tokens, except the Week-end page's own.
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
    private struct Frames: TimelineSchedule {
        let start: Date, length: Double

        func entries(from date: Date, mode: Mode) -> [Date] {
            stride(from: 0.0, through: length + 1 / 30, by: 1 / 30).map { start.addingTimeInterval($0) }.filter { $0 >= date } + [date]
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
            .boxed(RoundedRectangle(cornerRadius: 14), Look.Token.bg2.ui, ring: Look.Token.ink.ui, width: 1.5)
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
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Look.Token.ink.ui, lineWidth: 1.5))
    }

    /// The page itself, the Week-end page's own colours: white paper, then its dusk and sun, then its words.
    private var page: some View {
        func row(_ k: Double) -> Double { Schemas.ease(t, 1.3 + k * 0.2, 0.55) }
        return ZStack(alignment: .topLeading) {
            Color(red: 1, green: 254 / 255, blue: 252 / 255)
            Schemas.gradient([(0x26335E, 0), (0x5B4B83, 0.3), (0xB86A7E, 0.58), (0xEE9A72, 0.8), (0xF7C98B, 1)]).opacity(Schemas.ease(t, 0.8, 0.9))
            Circle().fill(RadialGradient(stops: [.init(color: Schemas.color(0xFFE2A0).opacity(0.95), location: 0), .init(color: Schemas.color(0xFFD68C).opacity(0.32), location: 0.62),
                                                 .init(color: Schemas.color(0xFFD68C).opacity(0), location: 0.72)], center: .center, startRadius: 0, endRadius: 75))
                .frame(width: 150, height: 150).rising(Schemas.ease(t, 1.5, 1.3), by: 46).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).offset(y: 40)
            VStack(alignment: .leading, spacing: 12) {
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
        .clipped()
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
