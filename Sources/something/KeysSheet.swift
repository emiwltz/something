// The shortcut sheet (⌘/): a card on a scrim in the window layer, "Keyboard Shortcuts" and ✕, Keys' lines in the two
// columns Settings › Shortcuts draws too, and a footer that says where the menu keys are changed. Esc, ✕, a click on
// the scrim or ⌘/ again closes it. It takes the focus while it is up, so no key reaches the page under it, and gives
// it back to where it was.
import AppKit
import SwiftUI

final class KeysSheet: NSView {
    private let card: NSHostingView<KeysCard>
    /// The card's distance below the window's middle: 9 points while it arrives, as the mockup's -48 % does.
    private var rise: NSLayoutConstraint?
    /// What had the focus before the sheet took it.
    private weak var before: NSResponder?

    private init() {
        card = NSHostingView(rootView: KeysCard())
        super.init(frame: .zero)
        card.rootView = KeysCard { [weak self] in self?.close() }
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        let rise = card.centerYAnchor.constraint(equalTo: centerYAnchor)
        NSLayoutConstraint.activate([rise, card.centerXAnchor.constraint(equalTo: centerXAnchor)])
        self.rise = rise
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityRoleDescription("dialog")
        setAccessibilityLabel("Keyboard shortcuts")
    }

    required init?(coder: NSCoder) { nil }

    /// The sheet `layer` holds, nil while none is up.
    static func shown(in layer: WindowLayer) -> KeysSheet? { layer.subviews.lazy.compactMap { $0 as? KeysSheet }.first }

    /// Shows the sheet over all of `layer`, or closes it when it is up, as ⌘/ does; returns the sheet when it shows.
    /// It fades in and rises under Calm `motion`.
    @discardableResult
    static func toggle(in layer: WindowLayer, motion: Look.Motion = .calm) -> KeysSheet? {
        if let sheet = shown(in: layer) {
            sheet.close()
            return nil
        }
        let sheet = KeysSheet()
        sheet.frame = layer.bounds
        sheet.autoresizingMask = [.width, .height]
        layer.hold(sheet)
        sheet.before = layer.window?.firstResponder
        layer.window?.makeFirstResponder(sheet)
        let calm = Look.duration(0.26, Look.motion(motion))
        guard calm > 0, let rise = sheet.rise else { return sheet }
        (sheet.alphaValue, rise.constant) = (0, 9)
        layer.layoutSubtreeIfNeeded()
        Look.animate(calm, Look.out, settle: [sheet]) {
            sheet.animator().alphaValue = 1
            rise.animator().constant = 0
        }
        return sheet
    }

    /// Closes the sheet `layer` holds; false when none is up, so Esc goes on to what else it closes.
    static func close(in layer: WindowLayer) -> Bool {
        guard let sheet = shown(in: layer) else { return false }
        sheet.close()
        return true
    }

    /// Takes the sheet away at once, the focus back where it was when that is still in the window.
    func close() {
        let window = window
        let focused = window?.firstResponder
        removeFromSuperview()
        guard let window, focused === self || (focused as? NSView)?.isDescendant(of: self) == true else { return }
        // A view that left the window since cannot take it back: the window's content does.
        let back = (before as? NSView)?.window === window || before is NSWindow ? before : nil
        window.makeFirstResponder(back ?? window.contentView)
    }

    override var acceptsFirstResponder: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
    override func keyDown(with event: NSEvent) { event.keyCode == 53 ? close() : super.keyDown(with: event) }
    /// A click on the scrim closes it; a click on the card is the card's.
    override func mouseDown(with event: NSEvent) { close() }
    /// The scrim takes the wheel too: the page under it stays where it is.
    override func scrollWheel(with event: NSEvent) {}

    /// The scrim, then the card's float shadow and ring; drawn here so a picture made with cacheDisplay shows them.
    override func draw(_ dirtyRect: NSRect) {
        Look.Token.scrim.color.setFill()
        bounds.fill()
        Look.drawFloat(card.frame, radius: KeysCard.radius, fill: .bg2, ring: true, appearance: effectiveAppearance)
    }
}

/// The card: its title and ✕, the two columns of Keys' lines, and the footer.
struct KeysCard: View {
    static let radius: CGFloat = 14
    var close: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts").font(Look.font(.title, size: 19, weight: .semibold).ui).kerning(-0.38)
                    .foregroundStyle(Look.Token.ink.ui).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Look.Token.ink2.ui)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(Keys.tooltip("keys", "Close")).accessibilityLabel("Close")
            }
            .padding(EdgeInsets(top: 16, leading: 22, bottom: 10, trailing: 16))
            ShortcutColumns().padding(EdgeInsets(top: 6, leading: 22, bottom: 18, trailing: 22))
            HStack(spacing: 12) {
                Text("Menu keys can be changed in System Settings › Keyboard › App Shortcuts.").frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    Text("esc").font(Look.font(.ui, size: 10.5, weight: .medium).ui).padding(.horizontal, 5).padding(.vertical, 3)
                        .background(Look.Token.hover.ui, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Text("Close")
                }
            }
            .font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui)
            .padding(.leading, 22).padding(.trailing, 16).frame(height: 40)
            .background(Look.Token.bg.ui)
            .overlay(alignment: .top) { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }
        }
        .frame(width: 680)
        .background(Look.Token.bg2.ui)
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
    }
}

extension App {
    /// ⌘/: shows the shortcut sheet over the window, or closes it.
    @objc func showKeys(_ sender: Any?) {
        shell.front()
        KeysSheet.toggle(in: shell.layer, motion: library.preferences.motion)
    }
}
