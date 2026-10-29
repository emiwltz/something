// The welcome, at the first start and again from Help › Welcome: one window of 900 by 560, alone on the screen and
// centred, the main window out of sight until it ends (Shell.welcome). On the left, "Welcome to something", what it is
// in three numbered rows (a space, your agents, your assistant), each lighting its part of the picture beside them
// (Hero.swift) in turn as it opens and under the pointer; then who builds, already chosen and changed in New Space's
// own chip ("Built by"). In the footer, the promise and one button, Make My First Space: Return presses it, and so do
// Escape and the close button, since there is nothing to skip. The main window then arrives on New Space, its field
// ready. With no builder found, the rows give way to the install commands and Look Again (Return). The welcome starts
// no agent and is not shown again at the next start. While it is open it takes every key, so no shortcut of the main
// window runs, and the menus grey the main window's commands (App).
import AppKit
import SomethingAgents
import SwiftUI

enum Welcome {
    static let size = NSSize(width: 900, height: 560)

    /// Where the welcome stands: centred on the visible part of `screen`.
    static func place(on screen: NSScreen?) -> NSRect {
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        return NSRect(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded(), width: size.width, height: size.height)
    }

    /// The welcome's own window, never released when closed, its content taking the keys.
    static func window(_ model: WelcomeModel, assistant: AssistantModel, motion: Look.Motion) -> NSWindow {
        let keys = WelcomeKeys(model: model, assistant: assistant, motion: motion)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        (window.titlebarAppearsTransparent, window.titleVisibility, window.isReleasedWhenClosed) = (true, .hidden, false)
        window.title = "Welcome to something"
        window.backgroundColor = Look.Token.bg.color
        window.contentView = keys
        window.delegate = keys
        window.initialFirstResponder = keys
        window.makeFirstResponder(keys)
        return window
    }
}

/// The welcome's content, which takes the keys: Return and Escape reach the model through the text system's commands
/// (interpretKeyEvents), so a layout's own keys and an input method's are respected.
final class WelcomeKeys: NSView, NSWindowDelegate {
    let model: WelcomeModel, assistant: AssistantModel

    init(model: WelcomeModel, assistant: AssistantModel, motion: Look.Motion) {
        (self.model, self.assistant) = (model, assistant)
        super.init(frame: NSRect(origin: .zero, size: Welcome.size))
        let host = Shell.hosted(WelcomeView(model: model, assistant: assistant, motion: motion))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { interpretKeyEvents([event]) }
    override func insertNewline(_ sender: Any?) { model.next(assistant) }
    override func cancelOperation(_ sender: Any?) { model.end() }
    /// Tab and ⇧Tab still move the focus, to the Built by chip and back.
    override func insertTab(_ sender: Any?) { window?.selectNextKeyView(sender) }
    override func insertBacktab(_ sender: Any?) { window?.selectPreviousKeyView(sender) }
    /// Any other command of the text system does nothing, without the beep.
    override func doCommand(by selector: Selector) { if responds(to: selector) { super.doCommand(by: selector) } }

    /// The close button ends it as the button does; whoever opened the window closes it.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.end()
        return false
    }
}

struct WelcomeView: View {
    let model: WelcomeModel, assistant: AssistantModel, motion: Look.Motion
    static let rows: [(Hero.Part, String, String)] = [
        (.page, "A space, a page of your own", "One HTML file on your Mac, blank at first. Export it in one click."),
        (.agents, "Your agents", "The coding agents on this Mac. A space can watch them, talk to them or run them, if you say so."),
        (.assistant, "Your assistant", ""),
    ]

    var body: some View {
        let none = assistant.kind == nil
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        PageSign(state: .listen, side: 16, lands: false, motion: motion).frame(width: 16, height: 16)
                        Text("Welcome to something")
                    }
                    .font(Look.font(.ui, size: 13, weight: .medium).ui).foregroundStyle(Look.Token.ink2.ui)
                    .accessibilityElement(children: .ignore).accessibilityLabel("Welcome to something")
                    if none { self.none } else { rows }
                }
                .frame(width: 348, alignment: .leading)
                // The picture at 420 points wide, in its own proportions.
                let k = 420 / Hero.size.width
                Hero(light: model.light, builder: builder, motion: motion).scaleEffect(k, anchor: .topLeading)
                    .frame(width: 420, height: Hero.size.height * k, alignment: .topLeading).padding(.top, 94)
            }
            .padding(EdgeInsets(top: 48, leading: 52, bottom: 0, trailing: 40))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Rectangle().fill(Look.Token.line.ui).frame(height: 1)
            footer(none)
        }
        .font(Look.font(.ui, size: 13).ui).foregroundStyle(Look.Token.ink.ui)
        .background(Look.Token.bg.ui)
        .ignoresSafeArea()
        .onAppear { model.light.cycle(motion) }
    }

    /// The picture's builder: none named before one is found.
    private var builder: String { assistant.kind == nil ? "A coding agent you install" : "\(assistant.name) · \(assistant.modelWords.model)" }

    private func title(_ words: String) -> some View {
        Text(words).font(Look.font(.title, size: 30, weight: .semibold).ui).kerning(-0.6).lineSpacing(-2)
            .fixedSize(horizontal: false, vertical: true).padding(.top, 12).accessibilityAddTraits(.isHeader)
    }

    /// The three rows, then who builds.
    private var rows: some View {
        let found = assistant.entries.filter(\.enabled).count
        return VStack(alignment: .leading, spacing: 0) {
            title("Pages of your own, that work with your agents.")
            VStack(alignment: .leading, spacing: 24) {
                ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                    let text = row.0 == .assistant ? "One of your agents, \(assistant.name), builds the space and changes it when you ask." : row.2
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(index + 1)").font(Look.font(.ui, size: 11, weight: .semibold).ui).foregroundStyle((model.light.lit == row.0 ? Look.Token.actfg : .ink2).ui)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill((model.light.lit == row.0 ? Look.Token.act : .bg).ui)).overlay(Circle().strokeBorder(Look.Token.line2.ui))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.1).font(Look.font(.ui, size: 14, weight: .semibold).ui)
                            Text(text).font(Look.font(.ui, size: 12.5).ui).lineSpacing(2.5).foregroundStyle(Look.Token.ink2.ui).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .contentShape(Rectangle())
                    .onHover { model.light.light($0 ? row.0 : nil) }
                    .accessibilityElement(children: .ignore).accessibilityLabel("\(index + 1). \(row.1). \(text)")
                }
            }
            .padding(.top, 30)
            HStack(spacing: 8) {
                Text("Built by").font(Look.font(.ui, size: 12.5, weight: .medium).ui).foregroundStyle(Look.Token.ink3.ui)
                AgentModelChip(model: assistant).boxed(RoundedRectangle(cornerRadius: Look.control + 1), Look.Token.bg2.ui, ring: Look.Token.line2.ui)
            }
            .padding(.top, 30)
            // Said of the builder found and chosen for the person; once they pick another, it is their choice. Its line
            // stays laid out, so the footer does not move.
            let chosen = assistant.kind == assistant.entries.first(where: \.enabled)?.id
            Text(found > 1 ? "Found on this Mac. \(found - 1) more to choose from." : "Found on this Mac.").font(Look.font(.ui, size: 11.5).ui).foregroundStyle(Look.Token.ink3.ui).padding(.top, 9)
                .opacity(chosen ? 1 : 0).accessibilityHidden(!chosen)
        }
    }

    /// No builder on this Mac: the install commands of the first two, and what a coding agent is.
    private var none: some View {
        let searching = model.searching(assistant), rows = Array(InstallList.builders.prefix(2))
        return VStack(alignment: .leading, spacing: 0) {
            title(searching ? "Looking for a coding agent" : "No coding agent found")
            Text("something builds your spaces with a coding agent you install yourself. Install one in Terminal, then look again.")
                .font(Look.font(.ui, size: 13.5).ui).lineSpacing(4).foregroundStyle(Look.Token.ink2.ui).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            VStack(spacing: 8) {
                ForEach(rows, id: \.name) { row in
                    HStack(spacing: 10) {
                        Text(row.command).font(Look.font(.code, size: 11).ui).lineLimit(1).truncationMode(.tail)
                            .accessibilityElement(children: .ignore).accessibilityLabel("\(row.name): \(row.command)")
                            .padding(.horizontal, 9).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                            .background(Look.Token.sunk.ui, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Button { model.copy(row.command, with: assistant.copy) } label: {
                            let done = model.copied == row.command
                            Text(done ? "Copied" : "Copy").font(Look.font(.ui, size: 12.5, weight: .semibold).ui).foregroundStyle((done ? Look.Token.ok : .ink).ui).frame(minWidth: 52)
                        }
                        .buttonStyle(Secondary())
                        .accessibilityLabel("Copy the command that installs \(row.name)")
                    }
                }
            }
            .padding(.top, 20)
            Button { model.explained.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle").font(.system(size: 12))
                    Text("What is a coding agent?")
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).rotationEffect(.degrees(model.explained ? 90 : 0))
                }
                .font(Look.font(.ui, size: 12.5, weight: .medium).ui).foregroundStyle(Look.Token.ink2.ui).contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.top, 14)
            if model.explained {
                Text("A program that reads and writes code in a folder when you ask it in plain words, like \(Words.list(rows.map(\.name), "or")). It runs on your Mac, with your own account. something never installs one for you.")
                    .font(Look.font(.ui, size: 12.5).ui).lineSpacing(3).foregroundStyle(Look.Token.ink2.ui).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
        }
    }

    private func footer(_ none: Bool) -> some View {
        let searching = none && model.searching(assistant), primary = none ? (searching ? "Looking…" : "Look Again") : "Make My First Space"
        return HStack(spacing: 7) {
            Image(systemName: "lock").font(.system(size: 10.5)).accessibilityHidden(true)
            Text("Nothing leaves your Mac.")
            Spacer()
            Button { model.next(assistant) } label: {
                HStack(spacing: 9) { Cap("↵"); Text(primary) }.font(Look.font(.ui, size: 13, weight: .semibold).ui)
            }
            .buttonStyle(Primary(height: 34, padding: 9)).disabled(searching).opacity(searching ? 0.5 : 1)
            .accessibilityLabel(primary)
        }
        .font(Look.font(.ui, size: 12.5).ui).foregroundStyle(Look.Token.ink3.ui)
        .padding(.leading, 52).padding(.trailing, 16).frame(height: 59)
    }
}

/// A key on the primary button: actfg on its own faint fill.
private struct Cap: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key).font(Look.font(.ui, size: 11, weight: .semibold).ui).foregroundStyle(Look.Token.actfg.ui)
            .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20)
            .background(Look.Token.actfg.ui.opacity(0.16), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// The sign on a page (New Space, the welcome, Info), at `side` points, in `state`, smiling with `joy`; with `lands`,
/// it lands as the page opens.
struct PageSign: NSViewRepresentable {
    let state: Sign.State, joy: Bool, side: CGFloat, lands: Bool, motion: Look.Motion

    init(state: Sign.State, joy: Bool = false, side: CGFloat, lands: Bool, motion: Look.Motion) {
        (self.state, self.joy, self.side, self.lands, self.motion) = (state, joy, side, lands, motion)
    }

    func makeNSView(context: Context) -> SignView {
        let sign = SignView(state, side: side)
        (sign.name, sign.motion, sign.joy) = ("something", motion, joy)
        if lands { sign.arrive() }
        return sign
    }

    func updateNSView(_ sign: SignView, context: Context) {
        if sign.state != state { sign.state = state }
        if sign.motion != motion { sign.motion = motion }
        sign.joy = joy
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SignView, context: Context) -> CGSize? { CGSize(width: side, height: side) }
}

// MARK: The model

/// What the welcome does: Return makes the first space, or looks for the builders again when none was found; Escape
/// and the close button end it too. Its end is kept in the preferences, so it opens once.
@Observable final class WelcomeModel {
    let light = HeroLight()
    /// Whether Look Again is still looking, and whether "What is a coding agent?" is open.
    private(set) var looking = false
    var explained = false
    /// The install command just copied, for a moment.
    private(set) var copied: String?
    /// Called once it ended.
    @ObservationIgnored var finished: () -> Void = {}
    let places: Places

    init(places: Places) { self.places = places }

    /// Whether Look Again is busy: it was just clicked, or the builders were never looked for yet.
    func searching(_ assistant: AssistantModel) -> Bool { looking || (assistant.kind == nil && !assistant.noAgent) }

    /// Return: Look Again when no builder was found, else the end.
    func next(_ assistant: AssistantModel) {
        guard assistant.kind == nil else { return end() }
        guard !searching(assistant) else { return }
        looking = true
        assistant.lookAgain()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.looking = false
        }
    }

    /// Copies an install command with `copy`; its button says Copied for a moment.
    func copy(_ command: String, with copy: (String) -> Void) {
        copy(command)
        copied = command
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            if self?.copied == command { self?.copied = nil }
        }
    }

    /// Ends the welcome: it is not shown again at the next start.
    func end() {
        Preferences.at(places).toured = true
        finished()
    }
}
