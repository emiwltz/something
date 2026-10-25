// What a Quick Change leaves over the space's page once point mode closed: the sign's corners around each part it
// works on, the top-right corner become its assistant's eyes ("Working", then "Done" when the part changed), and under
// the first part the chip that says who works ("Quick session · Claude Code · Opus 5.5"), then "Quick session ended".
// It takes no click: the page under it is the person's again. While it shows, it asks the page where its parts are a
// few times a second (from something's world, Pointing), so the frames follow a scroll the page does not tell about.
// It leaves when the Quick Change does. Drawn in draw(_:), so a picture of the window shows it as the screen does.
import AppKit
import Observation

final class QuickFrame: NSView {
    let quick: AssistantModel.Quick
    private weak var space: SpaceView?
    /// Where the parts are now, in the page's viewport; a part the page lost keeps its last place.
    private(set) var rects: [CGRect]
    private var timer: Timer?, asking = false

    /// The chip: 24 high, rounded 12, 8 points before its symbol and 10 after its words; centred on the part's bottom edge.
    static let chipHeight: CGFloat = 24

    init(_ quick: AssistantModel.Quick, over space: SpaceView) {
        (self.quick, self.space, rects) = (quick, space, quick.parts.map(\.rect))
        super.init(frame: space.web.frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        watch()
    }
    required init?(coder: NSCoder) { nil }

    /// Puts a frame for `quick` over `space`'s page, in place of one there; it leaves with the Quick Change.
    @discardableResult static func show(_ quick: AssistantModel.Quick, over space: SpaceView) -> QuickFrame {
        space.area.subviews.compactMap { $0 as? QuickFrame }.forEach { $0.removeFromSuperview() }
        let frame = QuickFrame(quick, over: space)
        frame.autoresizingMask = [.width, .height]
        space.area.addSubview(frame, positioned: .above, relativeTo: space.web)
        frame.follow()
        return frame
    }

    override var isFlipped: Bool { true }
    /// Every click passes to the page.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// What the chip says now.
    var chip: String { quick.phase == .ended ? "Quick session ended" : quick.chip }
    /// What the frame's eyes say, nil once it ended.
    var badge: String? {
        switch quick.phase {
        case .working: "Working"
        case .done: "Done"
        case .ended, .gone: nil
        }
    }

    /// Draws again at each change of the Quick Change, and leaves once the assistant no longer holds it.
    private func watch() {
        let phase = withObservationTracking { quick.phase } onChange: { [weak self] in
            DispatchQueue.main.async { self?.watch() }
        }
        if phase == .gone { return removeFromSuperview() }
        setAccessibilityLabel(chip)
        setAccessibilityValue(badge ?? "")
        needsDisplay = true
        // The frames follow the page while they show; at rest nothing is asked.
        if phase == .ended {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
                // A space closed with its frame takes it along: the timer stops with it. Off screen, nothing is asked.
                guard let self, superview != nil else { return timer.invalidate() }
                guard window != nil else { return }
                follow()
            }
        }
    }

    /// Asks the page where the parts are now, one question at a time.
    func follow() {
        guard !asking, quick.phase != .ended, let space, let frame = space.frame else { return }
        asking = true
        Task { @MainActor in
            let found = await Pointing.rects(quick.parts.map(\.path), in: space.web, frame: frame)
            asking = false
            guard found.count == rects.count else { return }
            let moved = zip(rects, found).map { $1 ?? $0 }
            if moved != rects {
                rects = moved
                needsDisplay = true
            }
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let pad = PointOverlay.pad, frames = rects.map { $0.insetBy(dx: -pad, dy: -pad) }
        if let words = badge {
            for r in frames {
                let badge = badgeBox(words, for: r), inside = badge.minY > r.minY
                // The eyes take the top-right corner's place; moved inside, they leave it drawn.
                PointOverlay.corners(r, ink: .ink, skipping: inside ? nil : 1)
                drawBadge(words, in: badge)
            }
        }
        if let first = frames.first { drawChip(under: first) }
    }

    private var badgeFace: [NSAttributedString.Key: Any] {
        [.font: Look.font(.ui, size: 11, weight: .semibold), .foregroundColor: Look.Token.actfg.color]
    }

    /// The badge on the frame `r`'s top-right corner, centred on it; inside the corner, 8 points in, when the page's
    /// edge would cut it.
    func badgeBox(_ words: String, for r: CGRect) -> CGRect {
        let width = 7 + 13 + 6 + ceil(NSAttributedString(string: words, attributes: badgeFace).size().width) + 9
        let out = CGRect(x: r.maxX - width / 2, y: r.minY - 12, width: width, height: 24)
        return out.maxX > bounds.width - 6 || out.minY < 4 ? CGRect(x: r.maxX - 8 - width, y: r.minY + 8, width: width, height: 24) : out
    }

    private func drawBadge(_ words: String, in box: CGRect) {
        Look.Token.act.color.setFill()
        NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()
        PointOverlay.draw(Sign.miniEyes(quick.phase == .done ? .done : .think), Look.Token.actfg.color,
                          in: CGRect(x: box.minX + 7, y: box.midY - 4, width: 13, height: 8))
        let text = NSAttributedString(string: words, attributes: badgeFace)
        text.draw(at: CGPoint(x: box.minX + 7 + 13 + 6, y: box.midY - text.size().height / 2))
    }

    /// Where the chip goes on the frame `r`, as the mockup pins it: centred on the frame's bottom edge, 10 points off
    /// the page's sides and 34 off its bottom.
    func chipBox(under r: CGRect) -> CGRect {
        let text = NSAttributedString(string: chip, attributes: [.font: Look.font(.ui, size: 11.5, weight: .medium)])
        let width = 8 + 12 + 6 + ceil(text.size().width) + 10
        return CGRect(x: max(10, min(bounds.width - width - 10, r.midX - width / 2)),
                      y: min(bounds.height - 34, r.maxY - Self.chipHeight / 2), width: width, height: Self.chipHeight)
    }

    private func drawChip(under r: CGRect) {
        let box = chipBox(under: r), ended = quick.phase == .ended
        if ended {
            Look.Token.bg2.color.setFill()
            NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()
            Look.Token.line.color.setStroke()
            let ring = NSBezierPath(roundedRect: box.insetBy(dx: -0.5, dy: -0.5), xRadius: 12.5, yRadius: 12.5)
            ring.stroke()
        } else {
            Look.drawFloat(box, radius: 12, fill: .bg2, ring: true, appearance: effectiveAppearance)
        }
        PointOverlay.draw(PointOverlay.symbol(ended ? "checkmark" : "bolt", 10, .semibold), (ended ? Look.Token.ink3 : Look.Token.ink2).color,
                          in: CGRect(x: box.minX + 8, y: box.midY - 6, width: 12, height: 12))
        let text = NSAttributedString(string: chip, attributes: [.font: Look.font(.ui, size: 11.5, weight: .medium),
                                                                 .foregroundColor: (ended ? Look.Token.ink3 : Look.Token.ink).color])
        text.draw(at: CGPoint(x: box.minX + 8 + 12 + 6, y: box.midY - text.size().height / 2))
    }

    override func removeFromSuperview() {
        timer?.invalidate()
        timer = nil
        super.removeFromSuperview()
    }
}
