// The shortcut sheet (⌘/): a card on a scrim in the window layer (ScrimCard, WindowLayer.swift), "Keyboard Shortcuts"
// and ✕, Keys' lines in two columns (ShortcutColumns), and a footer that says where the menu keys are changed. Esc, ✕,
// a click on the scrim or ⌘/ again closes it; Settings › Advanced's Show Shortcuts opens it too.
import AppKit
import SwiftUI

final class KeysSheet: ScrimCard {
    private init() {
        let host = NSHostingView(rootView: KeysCard())
        super.init(card: host, radius: KeysCard.radius, label: "Keyboard shortcuts")
        host.rootView = KeysCard { [weak self] in self?.close() }
        let rise = host.centerYAnchor.constraint(equalTo: centerYAnchor)
        NSLayoutConstraint.activate([rise, host.centerXAnchor.constraint(equalTo: centerXAnchor)])
        // It rises 9 points to the window's middle while it arrives, as the mockup's -48 % does.
        arrival = (rise, 9, 0.26)
    }

    required init?(coder: NSCoder) { nil }

    /// Shows the sheet over all of `layer`, or closes it when it is up, as ⌘/ does; returns the sheet when it shows.
    @discardableResult
    static func toggle(in layer: WindowLayer, motion: Look.Motion = .calm) -> KeysSheet? { KeysSheet.toggle(in: layer, motion: motion, KeysSheet.init) }
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

/// The shortcut list in two columns, Spaces and Show on the left, Assistant and Window on the right, read from Keys.
struct ShortcutColumns: View {
    /// What a key reads as: a keycap, or a word between them ("hold", "to").
    enum Cap: Equatable { case key(String), word(String) }

    static let columns: [[Keys.Command.Area]] = [[.spaces, .show], [.assistant, .window]]

    /// The commands the sheet lists in `area`, in Keys' order.
    static func lines(_ area: Keys.Command.Area) -> [Keys.Command] { Keys.commands.filter { $0.area == area && $0.line != nil } }

    /// "⇧⌘T" as one keycap per symbol; "esc" one keycap; "hold ⌥" the word, then ⌥; "⌘1 … ⌘9" ⌘ 1 to ⌘ 9.
    static func caps(_ shown: String) -> [Cap] {
        if shown == "esc" { return [.key(shown)] }
        return shown.split(separator: " ").flatMap { part -> [Cap] in
            if part == "…" { return [.word("to")] }
            if part.allSatisfy(\.isLowercase) { return [.word(String(part))] }
            return part.map { .key(String($0)) }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            ForEach(Self.columns, id: \.self) { areas in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(areas, id: \.self) { area in
                        Text(area.rawValue.uppercased()).font(Look.font(.ui, size: 11, weight: .semibold).ui).tracking(0.44)
                            .foregroundStyle(Look.Token.ink3.ui).padding(.top, area == areas[0] ? 0 : 10).padding(.bottom, 4)
                        ForEach(Array(Self.lines(area).enumerated()), id: \.element.id) { index, command in
                            if index > 0 { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }
                            HStack(spacing: 12) {
                                Text(command.line ?? command.title).font(Look.medium.font.ui).foregroundStyle(Look.Token.ink.ui)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                KeyCaps(caps: Self.caps(command.shown))
                            }
                            .frame(minHeight: 27)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Keycaps: each a small rounded square ringed in line2, with a line under it; words between them in ink3.
struct KeyCaps: View {
    let caps: [ShortcutColumns.Cap]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                switch cap {
                case .word(let word): Text(word).font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui).padding(.horizontal, 3)
                case .key(let key):
                    let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
                    // One stack, back to front: the line under the cap, the cap, its ring, its symbol.
                    ZStack {
                        shape.fill(Look.Token.line2.ui).offset(y: 1)
                        shape.fill(Look.Token.bg2.ui)
                        shape.strokeBorder(Look.Token.line2.ui)
                        Text(key).font(Look.font(.ui, size: 11.5, weight: .medium).ui).foregroundStyle(Look.Token.ink.ui).padding(.horizontal, 5)
                    }
                    .frame(minWidth: 21, minHeight: 21).fixedSize()
                }
            }
        }
        .fixedSize()
    }
}
