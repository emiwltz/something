// The first-launch film, before the welcome: over the whole window, on the page's paper, the sign lands corner by
// corner, then "something" and "A blank page. Your world." rise under it. At 2.7 s the words go, the sign's frame (the
// arrival's, Arrival.swift) grows to the window's edges, 12 points in, and the paper fades from under it onto New Space;
// the frame fades as New Space's own sign lands, and the welcome opens. Under Reduced motion there is no film. It
// plays in a window of its own laid over the whole window, toolbar and lights included, as the welcome's veil is:
// that window takes the clicks and the keys while it plays, so nothing under it is pressed unseen, and the menus grey
// the window's commands (App). It is drawn in draw(_:) and its subviews, so cacheDisplay pictures it.
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
    /// The borderless window it plays in, over the whole of the shell's.
    let cover: NSWindow
    private weak var shell: Shell?
    private let motion: Look.Motion
    private var left = false

    /// Plays the film over `shell`'s window, on New Space, and calls `then` when the welcome should open. Under Reduced
    /// motion there is none: `then` is called at once and it returns nil. A film already playing ends first.
    /// `onScreen` false leaves its window off the screen, as a test's are.
    @discardableResult
    static func play(in shell: Shell, library: Library, pace: Double = 1, onScreen: Bool = true, then: @escaping () -> Void) -> Film? {
        shell.film?.leave()
        let motion = library.preferences.motion
        guard Look.motion(motion) == .calm else {
            then()
            return nil
        }
        library.select(.newSpace)
        let film = Film(over: shell, motion: motion)
        film.pace = pace
        if onScreen {
            shell.window.addChildWindow(film.cover, ordered: .above)
            film.cover.makeKeyAndOrderFront(nil)
        }
        film.run(then)
        return film
    }

    /// A film in its own window over all of `shell`'s, kept as its film, not shown yet.
    init(over shell: Shell, motion: Look.Motion) {
        (self.shell, self.motion) = (shell, motion)
        cover = Cover(over: shell.window.frame, keys: true)
        super.init(frame: NSRect(origin: .zero, size: shell.window.frame.size))
        cover.contentView = self
        shell.film = self
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

    /// While it plays, what is under it never takes a click, nor a key.
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {}
    override func mouseDown(with event: NSEvent) {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The sign, then the name 18 points under it and the line 14 under that, all centred in the window.
    override func layout() {
        super.layout()
        paper.frame = bounds
        let words = [word, sentence].map(\.intrinsicContentSize), height = Film.side + 18 + words[0].height + 14 + words[1].height
        var y = ((bounds.height - height) / 2).rounded()
        sign.frame = CGRect(x: ((bounds.width - Film.side) / 2).rounded(), y: y, width: Film.side, height: Film.side)
        y += Film.side + 18
        for (field, size) in zip([word, sentence], words) {
            // A line still hidden waits 8 points lower, and rises as it shows.
            field.frame = CGRect(x: ((bounds.width - size.width) / 2).rounded(), y: y + (field.alphaValue > 0 ? 0 : 8),
                                 width: size.width, height: size.height)
            y += size.height + 14
        }
        grown?.frame = bounds
    }

    private func after(_ seconds: TimeInterval, _ step: @escaping (Film) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds * pace) { [weak self] in
            if let self, !self.left { step(self) }
        }
    }

    private func animate(_ seconds: TimeInterval, _ curve: Look.Curve, _ changes: @escaping () -> Void) {
        Look.animate(seconds * pace, curve, implicit: true, { [weak self] in
            changes()
            self?.layoutSubtreeIfNeeded()
        })
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
            // The words go and the frame grows from the sign to the window's edges; New Space's sign waits under the paper.
            film.place().grow {}
            film.after(Film.uncovers) { film in film.animate(0.6, Look.douce) { film.paper.alphaValue = 0 } }
            film.after(Film.lets) { film in
                if let hero = film.hero {
                    hero.isHidden = false
                    hero.arrive()
                }
                film.grown?.fade(0.45 * film.pace) {}
            }
            film.after(Film.opens) { film in
                // The welcome opens under the film's last, faded instant: the clicks go to it.
                film.cover.ignoresMouseEvents = true
                then()
            }
            film.after(Film.ends) { $0.leave() }
        }
    }

    /// Puts the sign's frame in the sign's place, the words going, and returns it.
    private func place() -> Arrival {
        animate(0.35, Look.douce) { [word, sentence] in (word.alphaValue, sentence.alphaValue) = (0, 0) }
        hero?.isHidden = true
        let g = sign.geometry, box = sign.frame.insetBy(dx: g.inset * Film.side, dy: g.inset * Film.side)
        let frame = Arrival(start: Arrival.Start(rect: box, arm: g.arm * Film.side, stroke: g.stroke, face: true), still: nil, stillRect: .zero)
        (frame.reach, frame.holds, frame.frame, frame.span) = ((bounds, Film.inset), true, bounds, Arrival.grows * pace)
        sign.isHidden = true
        addSubview(frame)
        grown = frame
        return frame
    }

    /// New Space's sign, which the film's frame lands on at the end.
    private var hero: SignView? { shell.flatMap { Arrival.sign(in: $0.center) } }

    /// The film's last moment, still: the frame at the window's edges, the paper gone, New Space's sign landed (a1).
    func hold() {
        place().progress = 1
        paper.alphaValue = 0
        hero?.isHidden = false
    }

    /// Takes it and its window away, New Space's sign shown again and the keys back to the window or the welcome.
    func leave() {
        guard !left else { return }
        left = true
        hero?.isHidden = false
        cover.parent?.removeChildWindow(cover)
        cover.orderOut(nil)
        cover.contentView = nil
        guard let shell, shell.film === self else { return }
        shell.film = nil
        if shell.welcoming == nil, shell.window.isVisible { shell.window.makeKey() }
    }
}
