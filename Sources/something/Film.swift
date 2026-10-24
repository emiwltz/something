// The first-launch film, before the welcome: over the whole window, on the page's paper, the sign lands corner by
// corner, then "something" and "A blank page. Your world." rise under it. At 2.7 s the words go, the sign's frame (the
// arrival's, Arrival.swift) grows to the window's edges, 12 points in, and the paper fades from under it onto New Space;
// the frame fades as New Space's own sign lands, and the welcome opens. Under Reduced motion there is no film. It
// lives in the window layer, takes the clicks while it plays so nothing under it is pressed unseen, and is drawn in
// draw(_:) and its subviews, so cacheDisplay pictures it.
import AppKit

final class Film: NSView {
    /// When the frame starts to grow; then, from that moment, when the paper starts to fade, when the frame fades and
    /// New Space's sign lands, when the welcome opens, and when the film is gone. The mockup's times, in seconds.
    static let lands: TimeInterval = 2.7, uncovers: TimeInterval = 0.38, lets: TimeInterval = 0.95, opens: TimeInterval = 1.35,
               ends: TimeInterval = 1.5
    /// The sign's side, and how far in from the window's edges the frame grows.
    static let side: CGFloat = 84, inset: CGFloat = 12
    static let line = "A blank page. Your world."

    /// The page's paper, the sign and the two lines over it.
    let paper = NSBox(), sign = SignView(.listen, side: Film.side)
    let word = NSTextField(labelWithString: ""), sentence = NSTextField(labelWithString: "")
    /// The sign's frame, once it grows.
    private(set) var grown: Arrival?
    /// Every time scaled by this; a seam for tests.
    var pace: Double = 1
    private let center: NSView, motion: Look.Motion

    /// Plays the film over `shell`'s window, on New Space, and calls `then` when the welcome should open. Under Reduced
    /// motion there is none: `then` is called at once and it returns nil. A film already playing ends first.
    @discardableResult
    static func play(in shell: Shell, library: Library, pace: Double = 1, then: @escaping () -> Void) -> Film? {
        Film.end(in: shell)
        let motion = library.preferences.motion
        guard Look.motion(motion) == .calm else {
            then()
            return nil
        }
        library.select(.newSpace)
        let film = Film(center: shell.center, motion: motion)
        film.pace = pace
        shell.layer.hold(film)
        film.frame = film.superview?.bounds ?? .zero
        film.run(then)
        return film
    }

    /// Ends any film over `shell`'s window, New Space's sign shown again.
    static func end(in shell: Shell) {
        shell.layer.subviews.compactMap { $0 as? Film }.forEach { $0.leave() }
    }

    init(center: NSView, motion: Look.Motion) {
        (self.center, self.motion) = (center, motion)
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
        (paper.boxType, paper.borderWidth, paper.fillColor, paper.autoresizingMask) = (.custom, 0, Look.Token.bg.color, [.width, .height])
        sign.name = "something"
        sign.motion = motion
        word.attributedStringValue = NSAttributedString(string: "something", attributes: [
            .font: Look.font(.title, size: 46, weight: .bold), .foregroundColor: Look.Token.ink.color, .kern: -1.15])
        sentence.attributedStringValue = NSAttributedString(string: Film.line, attributes: [
            .font: Look.font(.voice, size: 16), .foregroundColor: Look.Token.ink2.color])
        for view in [paper, sign, word, sentence] as [NSView] {
            view.wantsLayer = true
            addSubview(view)
        }
        (word.alphaValue, sentence.alphaValue) = (0, 0)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    /// While it plays, what is under it never takes a click.
    override func hitTest(_ point: NSPoint) -> NSView? { superview.map { bounds.contains(convert(point, from: $0)) } == true ? self : nil }

    /// The sign, then the name 18 points under it and the line 14 under that, all centred in the window.
    override func layout() {
        super.layout()
        paper.frame = bounds
        let words = [word, sentence].map(\.intrinsicContentSize), height = Film.side + 18 + words[0].height + 14 + words[1].height
        var y = ((bounds.height - height) / 2).rounded()
        sign.frame = CGRect(x: ((bounds.width - Film.side) / 2).rounded(), y: y, width: Film.side, height: Film.side)
        y += Film.side + 18
        for (field, size) in zip([word, sentence], words) {
            field.frame = CGRect(x: ((bounds.width - size.width) / 2).rounded(), y: y + rise(field), width: size.width, height: size.height)
            y += size.height + 14
        }
        grown?.frame = bounds
    }

    /// How far down a line still is as it rises, 8 points while hidden.
    private func rise(_ field: NSTextField) -> CGFloat { field.alphaValue > 0 ? 0 : 8 }

    private func after(_ seconds: TimeInterval, _ step: @escaping (Film) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds * pace) { [weak self] in
            if let self, self.superview != nil { step(self) }
        }
    }

    private func animate(_ seconds: TimeInterval, _ curve: Look.Curve, _ changes: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            (context.duration, context.timingFunction, context.allowsImplicitAnimation) = (seconds * pace, curve.timing, true)
            changes()
            layoutSubtreeIfNeeded()
        }
    }

    /// The whole film: the sign lands, the lines rise, then the frame grows and the window shows through.
    private func run(_ then: @escaping () -> Void) {
        layoutSubtreeIfNeeded()
        sign.arrive()
        for (field, delay) in [(word, 1.05), (sentence, 1.45)] {
            after(delay) { film in
                film.animate(0.8, Look.out) {
                    field.alphaValue = 1
                    film.needsLayout = true
                }
            }
        }
        after(Film.lands) { film in
            film.grow()
            film.after(Film.uncovers) { film in film.animate(0.6, Look.douce) { film.paper.alphaValue = 0 } }
            film.after(Film.lets) { film in
                film.land()
                film.grown?.fade(0.45 * film.pace) {}
            }
            film.after(Film.opens) { _ in then() }
            film.after(Film.ends) { $0.leave() }
        }
    }

    /// The words go and the frame grows from the sign to the window's edges; New Space's sign waits under the paper.
    private func grow() { place().grow {} }

    /// Puts the sign's frame in the sign's place, the words going, and returns it.
    private func place() -> Arrival {
        animate(0.35, Look.douce) { [word, sentence] in (word.alphaValue, sentence.alphaValue) = (0, 0) }
        hero?.isHidden = true
        let g = sign.geometry, box = sign.frame.insetBy(dx: g.inset * Film.side, dy: g.inset * Film.side)
        let frame = Arrival(start: Arrival.Start(rect: box, arm: g.arm * Film.side, stroke: g.stroke, face: true), still: nil, stillRect: .zero)
        (frame.reach, frame.holds, frame.frame) = ((bounds, Film.inset), true, bounds)
        sign.isHidden = true
        addSubview(frame)
        grown = frame
        return frame
    }

    /// New Space's sign, which the film's frame lands on at the end.
    private var hero: SignView? { Arrival.sign(in: center) }

    private func land() {
        guard let hero else { return }
        hero.isHidden = false
        hero.arrive()
    }

    /// The film's last moment, still: the frame at the window's edges, the paper gone, New Space's sign landed (a1).
    func hold() {
        place().progress = 1
        paper.alphaValue = 0
        hero?.isHidden = false
    }

    /// Takes it away, New Space's sign shown again.
    func leave() {
        hero?.isHidden = false
        removeFromSuperview()
    }
}
