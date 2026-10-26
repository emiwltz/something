// The arrival, in a window never shown: the frame's shape at the start, halfway in time and at the end; it starts on the
// template card Use pressed, once, and only for the space that card made; under Reduced motion it only fades, and it
// leaves nothing on the glass, the new space selected and its row ringed. The growth from New Space's sign, after a
// real build of the fake claude, is Acceptance d3.
import AppKit
import SwiftUI
import Testing
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-arrival-"))
struct ArrivalTests {
    static let start = Arrival.Start(rect: CGRect(x: 440, y: 120, width: 67, height: 67), arm: 23.56, stroke: 35, face: true)
    static let room = CGRect(x: 0, y: 52, width: 965, height: 708)

    @Test func theFrameStartsOnTheSignAndGrowsToTheEdges() {
        let first = Arrival.shape(Self.start, to: Self.room, progress: 0)
        #expect(first.rect == Self.start.rect && first.stroke == 35 && first.arm == 23.56 && first.eyes == 1)
        #expect(first.face == CGPoint(x: Self.start.rect.midX, y: Self.start.rect.midY))

        let last = Arrival.shape(Self.start, to: Self.room, progress: 1)
        #expect(last.rect == CGRect(x: 14, y: 66, width: 937, height: 680) && last.stroke == 16 && last.arm == 23.56 && last.eyes == 0)
        #expect(last.face == CGPoint(x: 14 + 46, y: 66 + 40))

        // Halfway in time, the douce curve is a little past halfway, the eyes already gone (0.35 s of 0.82).
        let half = Arrival.shape(Self.start, to: Self.room, progress: 0.5), e = Look.douce.value(at: 0.5)
        #expect(e > 0.5 && e < 0.75 && Look.douce.value(at: 0) == 0 && abs(Look.douce.value(at: 1) - 1) < 1e-9)
        #expect(abs(half.rect.minX - (440 + (14 - 440) * e)) < 0.01 && abs(half.rect.width - (67 + (937 - 67) * e)) < 0.01)
        #expect(half.stroke < 35 && half.stroke > 16 && half.eyes == 0)
        // Slow at both ends: a tenth of the time moves the frame less than a tenth of the way.
        #expect(Look.douce.value(at: 0.1) < 0.1 && Look.douce.value(at: 0.9) > 0.9)
    }

    /// Use on My agents' card: the arrival starts on that card, without a face; under Reduced motion it only fades, then
    /// nothing is left on the glass, the new space is selected and its row ringed. Once arrived, opening it again from
    /// the same page arrives from nowhere.
    @Test func useArrivesFromItsCardAndReducedOnlyFades() async throws {
        let stage = try Stage("arrival")
        defer { stage.remove() }
        let (shell, library, gallery, _) = try AcceptanceBuild.templates(stage)
        defer { shell.window.close() }
        #expect(await wait(until: { gallery.drawn["agents"] != nil }))
        let agents = try #require(library.templates.first { $0.id == "agents" })
        // The card's Use, as its button does (offscreen, SwiftUI's buttons cannot be pressed).
        gallery.used = "agents"
        library.use(agents)
        #expect(library.selection == .space("agents-2"))
        #expect(Arrival.made("project", in: shell) == nil)
        let arrival = try #require(Arrival.made("agents-2", in: shell))
        let card = try #require(gallery.drawn["agents"])
        #expect(!arrival.start.face && arrival.start.stroke == 22 && abs(arrival.start.rect.width - card.width) < 0.5
                && abs(arrival.start.arm - min(card.width, card.height) * 0.3) < 0.5)
        #expect(arrival.bounds.contains(arrival.start.rect) && arrival.start.rect.minY > arrival.room.minY, "\(arrival.start.rect)")
        #expect(arrival.superview === shell.glass && !shell.glass.isHidden && arrival.hitTest(NSPoint(x: 400, y: 400)) == nil)
        var arrived = false
        arrival.play("agents-2", library: library, motion: .reduced) { arrived = true }
        #expect(!arrival.playing && arrival.progress == 1)
        #expect(await wait(until: { arrived }))
        #expect(arrival.superview == nil && !shell.glass.subviews.contains { $0 is Arrival })
        #expect(library.selection == .space("agents-2") && library.fresh == "agents-2")
        #expect(await wait(until: { library.fresh == nil }), "then let go, so the next arrival rings it again")
        gallery.used = nil
        #expect(Arrival.made("agents-2", in: shell) == nil)
    }
}
