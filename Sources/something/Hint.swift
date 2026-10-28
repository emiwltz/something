// The hints, each said once, one at a time: a bubble in the window layer beside what it is about, a title, a sentence
// with its key, and Got It; no number, no Skip. Your assistant's, by the sticker, when the first space a build made
// opens; then, at later openings of a space, Info's under the title and Point's under its button. A hint counts as
// seen once shown (Preferences.hinted). It goes with Got It, once its gesture is made (the card opens, Info opens,
// pointing starts), or when the window shows something else. Someone who never builds a space is never hinted.
import AppKit
import SwiftUI

enum Hint: String, CaseIterable {
    case ask, info, point

    var title: String {
        switch self {
        case .ask: "Your assistant"
        case .info: "Everything about this space"
        case .point: "Point at a part"
        }
    }

    /// The sentence and its key, as the mockup says them.
    var words: (before: String, key: String, after: String) {
        switch self {
        case .ask: ("It built this space, and changes it when you ask. Press ", Keys.shown("ask"), ", or click it.")
        case .info: ("Its file and Export, what it may do with your agents, and who builds it. Click its title, or press ", Keys.shown("insp"), ".")
        case .point: ("To change one part, point at it, then say what should change there. ", Keys.shown("pointpart"), "")
        }
    }
}

extension Shell {
    /// After the space `name` showed: the next hint not seen yet, 1.3 s later if that space is still shown. Your
    /// assistant's comes first, and only on the opening of a space a build just made (`made`).
    func hintLater(_ name: String) {
        let made = self.made == name, seen = library.preferences.hinted
        if made { self.made = nil }
        guard let next = Hint.allCases.first(where: { !seen.contains($0.rawValue) }), next != .ask || made else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            guard let self, space?.space.name == name, window.isVisible else { return }
            hint(next)
        }
    }

    /// Shows `kind` now, and keeps it as seen; nil when what it points at is not there (the sticker under its card, the
    /// toolbar away in Page Full Screen, a page that cannot be pointed at).
    @discardableResult
    func hint(_ kind: Hint) -> HintBubble? {
        let sticker = glass.sticker
        guard let space, !pageFull, !assistant.cardShown, kind != .point || space.pointable, kind != .ask || !sticker.isHiddenOrHasHiddenAncestor,
              let anchor = kind == .ask ? sticker : kind == .info ? titleLine : controls[Shell.point], anchor.window != nil else { return nil }
        library.preferences.hinted.append(kind.rawValue)
        HintBubble.close(in: layer)
        let bubble = HintBubble(kind, assistant: assistant)
        layer.hold(bubble)
        bubble.place(by: layer.convert(anchor.convert(anchor.bounds, to: nil), from: nil), in: layer.bounds)
        layer.announce("\(kind.title). \(kind.words.before)\(kind.words.key)\(kind.words.after)")
        return bubble
    }
}

/// The bubble, its arrow toward what it is about: left of the sticker, under the title or Point.
final class HintBubble: NSView {
    static let width: CGFloat = 268, gap: CGFloat = 4
    let kind: Hint
    private let assistant: AssistantModel

    init(_ kind: Hint, assistant: AssistantModel) {
        (self.kind, self.assistant) = (kind, assistant)
        super.init(frame: .zero)
        let host = NSHostingView(rootView: HintView(kind: kind, arrow: kind == .ask ? .trailing : kind == .info ? .leading : .center) { [weak self] in
            self?.removeFromSuperview()
        })
        frame.size = host.fittingSize
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        // One group for VoiceOver, said as a whole: its title and sentence, Got It inside it.
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("\(kind.title). \(kind.words.before)\(kind.words.key)\(kind.words.after)")
        watch()
    }

    required init?(coder: NSCoder) { nil }

    /// The hint `layer` shows, if any.
    static func shown(in layer: NSView) -> HintBubble? { layer.subviews.lazy.compactMap { $0 as? HintBubble }.first }
    static func close(in layer: NSView) { shown(in: layer)?.removeFromSuperview() }

    /// Lays it beside `anchor`, in the layer's coordinates (`room`), inside the room by 8 points: the assistant's left
    /// of the sticker, at its foot, its arrow level with the sticker's middle; the others under their control.
    func place(by anchor: NSRect, in room: NSRect) {
        var origin: NSPoint
        switch kind {
        case .ask: origin = NSPoint(x: anchor.minX - HintBubble.gap - frame.width, y: anchor.minY)
        case .info: origin = NSPoint(x: anchor.minX, y: anchor.minY - HintBubble.gap - frame.height)
        case .point: origin = NSPoint(x: anchor.midX - frame.width / 2, y: anchor.minY - HintBubble.gap - frame.height)
        }
        origin.x = min(max(origin.x, room.minX + 8), room.maxX - frame.width - 8)
        origin.y = min(max(origin.y, room.minY + 8), room.maxY - frame.height - 8)
        setFrameOrigin(origin)
        autoresizingMask = kind == .ask ? [.minXMargin, .maxYMargin] : kind == .info ? [.maxXMargin, .minYMargin] : [.minXMargin, .minYMargin]
    }

    /// Goes once its gesture is made: the card opens. Info's goes as Info opens (Shell.showInfo), Point's as pointing
    /// starts (Shell.pressPoint).
    private func watch() {
        guard kind == .ask else { return }
        withObservationTracking { _ = assistant.cardShown } onChange: { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, superview != nil else { return }
                if assistant.cardShown { removeFromSuperview() } else { watch() }
            }
        }
    }
}

struct HintView: View {
    enum Arrow { case leading, center, trailing }
    let kind: Hint, arrow: Arrow, gotIt: () -> Void

    var body: some View {
        let words = kind.words
        var key = AttributedString(words.key)
        (key.font, key.backgroundColor) = (Look.font(.ui, size: 11, weight: .semibold).ui, Look.Token.sunk.ui)
        let shape = RoundedRectangle(cornerRadius: Look.card, style: .continuous)
        return VStack(alignment: .leading, spacing: 4) {
            Text(kind.title).font(Look.font(.title, size: 16, weight: .semibold).ui).accessibilityLabel(kind.title).accessibilityAddTraits(.isHeader)
            Text(AttributedString(words.before) + key + AttributedString(words.after))
                .font(Look.font(.ui, size: 12.5).ui).lineSpacing(3).foregroundStyle(Look.Token.ink2.ui).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(words.before + words.key + words.after)
            Button("Got It", action: gotIt).font(Look.font(.ui, size: 12, weight: .semibold).ui).buttonStyle(Primary(height: 26, padding: 10)).accessibilityLabel("Got It")
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 6)
        }
        .foregroundStyle(Look.Token.ink.ui)
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(width: HintBubble.width, alignment: .leading)
        .background(shape.fill(Look.Token.bg2.ui).shadow(color: .black.opacity(0.14), radius: 12, y: 4))
        .overlay(shape.strokeBorder(Look.Token.line2.ui))
        .overlay(alignment: arrow == .trailing ? .bottomTrailing : arrow == .leading ? .topLeading : .top) {
            // A small square turned, half out of the bubble, toward what it is about: by the sticker, 34 points up from
            // the bubble's foot, the middle of the sticker's place.
            Rectangle().fill(Look.Token.bg2.ui).frame(width: 10, height: 10).rotationEffect(.degrees(45))
                .offset(x: arrow == .trailing ? 5 : arrow == .leading ? 22 : 0, y: arrow == .trailing ? -23 : -5)
        }
        .padding(6)
        .accessibilityElement(children: .contain)
    }
}
