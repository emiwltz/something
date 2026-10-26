// The shortcut sheet (⌘/): a card on a scrim in the window layer (ScrimCard, WindowLayer.swift), "Keyboard Shortcuts"
// and ✕, Keys' lines in the two columns Settings › Shortcuts draws too, and a footer that says where the menu keys are
// changed. Esc, ✕, a click on the scrim or ⌘/ again closes it.
import AppKit
import SwiftUI

final class KeysSheet: ScrimCard {
    /// The card's distance below the window's middle: 9 points while it arrives, as the mockup's -48 % does.
    private var rise: NSLayoutConstraint?

    private init() {
        let host = NSHostingView(rootView: KeysCard())
        super.init(card: host, radius: KeysCard.radius, label: "Keyboard shortcuts")
        host.rootView = KeysCard { [weak self] in self?.close() }
        let rise = host.centerYAnchor.constraint(equalTo: centerYAnchor)
        NSLayoutConstraint.activate([rise, host.centerXAnchor.constraint(equalTo: centerXAnchor)])
        self.rise = rise
    }

    required init?(coder: NSCoder) { nil }

    /// Shows the sheet over all of `layer`, or closes it when it is up, as ⌘/ does; returns the sheet when it shows.
    /// It fades in and rises under Calm `motion`.
    @discardableResult
    static func toggle(in layer: WindowLayer, motion: Look.Motion = .calm) -> KeysSheet? {
        if close(in: layer) { return nil }
        let sheet = KeysSheet()
        sheet.present(in: layer)
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
