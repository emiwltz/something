// The welcome, at the first start and again from Help › Welcome: five beats in one window of 980 by 640, alone on the
// screen and centred, the main window out of sight until it ends (Shell.welcome). One picture holds them: each beat is
// one sentence and one schema (Schemas.swift), the detail of the part lit on the small Hero in its corner, and the last
// grows that Hero to its whole size. Return and → go on, ← goes back, Escape skips; the last beat has two doors, Make
// My First Space and Open an Example. The welcome starts no agent and is not shown again at the next start. While it
// is open it takes every key, so no shortcut of the main window runs, and the menus grey the main window's commands
// (App). The whole window is drawn at the mockup's size and scaled once to the interface size.
import AppKit
import SomethingAgents
import SwiftUI

enum Welcome {
    /// The mockup's window, which everything in it is placed against.
    static let base = NSSize(width: 980, height: 640)
    static var size: NSSize { NSSize(width: (base.width * Look.scale.size.factor).rounded(), height: (base.height * Look.scale.size.factor).rounded()) }

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

/// The welcome's content, which takes the keys: Return, Escape and the arrows reach the model through the text system's
/// commands (interpretKeyEvents), so a layout's own keys and an input method's are respected.
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
    override func cancelOperation(_ sender: Any?) { model.skip(assistant) }
    override func moveRight(_ sender: Any?) { model.go(1) }
    override func moveLeft(_ sender: Any?) { model.go(-1) }
    /// Tab and ⇧Tab still move the focus through the window's key loop.
    override func insertTab(_ sender: Any?) { window?.selectNextKeyView(sender) }
    override func insertBacktab(_ sender: Any?) { window?.selectPreviousKeyView(sender) }
    /// Any other command of the text system does nothing, without the beep.
    override func doCommand(by selector: Selector) { if responds(to: selector) { super.doCommand(by: selector) } }

    /// The close button leaves it as Make My First Space does, with nothing said, or as it was when Help opened it;
    /// whoever opened the window closes it.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.end(model.again ? .left : .made)
        return false
    }
}

struct WelcomeView: View {
    let model: WelcomeModel, assistant: AssistantModel, motion: Look.Motion
    private static let map: CGFloat = 0.3

    var body: some View {
        let beat = model.beat, whole = beat == .whole, calm = Look.motion(motion) == .calm
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                HStack(spacing: 8) {
                    PageSign(state: .listen, side: 16, lands: false, motion: motion).frame(width: 16, height: 16)
                    Text("Welcome to something")
                }
                .font(Look.fixed(.ui, size: 12, weight: .semibold)).foregroundStyle(Look.Token.ink2.ui).offset(x: 40, y: 40)
                .accessibilityElement(children: .ignore).accessibilityLabel("Welcome to something").accessibilitySortPriority(2)
                words(beat, whole).accessibilitySortPriority(1)
                if !whole { paper(beat).id(beat).transition(arrival(beat)).offset(x: 344, y: 24) }
                Text("You are here").font(Look.fixed(.ui, size: 11, weight: .semibold)).foregroundStyle(Look.Token.ink3.ui)
                    .offset(x: 41, y: 410).opacity(whole ? 0 : 1).accessibilityHidden(true)
                smallMap(beat, whole)
            }
            .frame(width: Welcome.base.width, height: 579, alignment: .topLeading)
            Rectangle().fill(Look.Token.line.ui).frame(height: 1)
            footer(beat)
        }
        .animation(calm ? Look.out.animation(0.62) : nil, value: beat)
        .font(Look.fixed(.ui, size: 13)).foregroundStyle(Look.Token.ink.ui)
        .frame(width: Welcome.base.width, height: Welcome.base.height, alignment: .topLeading)
        .scaleEffect(Look.scale.size.factor, anchor: .topLeading)
        .frame(width: Welcome.size.width, height: Welcome.size.height, alignment: .topLeading)
        .background(Look.Token.bg.ui)
        .ignoresSafeArea()
    }

    /// The picture's builder: none named before one is found.
    private var builder: String { assistant.kind == nil ? "A coding agent you install" : "\(assistant.name) · \(assistant.modelWords.model)" }

    /// The beat's title and sentence: at the left, above the whole picture on the last beat.
    private func words(_ beat: WelcomeModel.Beat, _ whole: Bool) -> some View {
        VStack(alignment: whole ? .center : .leading, spacing: whole ? 8 : 12) {
            Text(beat.title).font(Look.fixed(.title, size: 30, weight: .semibold)).kerning(-0.78).accessibilityAddTraits(.isHeader)
            Text(beat.sentence).font(Look.fixed(.ui, size: 14)).lineSpacing(4).foregroundStyle(Look.Token.ink2.ui)
        }
        .multilineTextAlignment(whole ? .center : .leading).fixedSize(horizontal: false, vertical: true)
        .frame(width: whole ? 720 : 280, alignment: whole ? .top : .topLeading)
        .id(beat).transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: model.forward ? 14 : -14)), removal: .opacity.animation(Look.douce.animation(0.3))))
        .offset(x: whole ? 130 : 40, y: whole ? 40 : 72)
    }

    /// The dotted paper of a beat, with its schema.
    private func paper(_ beat: WelcomeModel.Beat) -> some View {
        Paper {
            switch beat {
            case .page: Schemas.playing(from: model.since, for: PageSchema.length, motion: motion) { PageSchema(t: $0) }
            case .agent where assistant.kind == nil: install.padding(24)
            default: EmptyView()
            }
        }
    }

    /// A schema opens out of the part lit on the map, so the zoom says what it is the detail of.
    private func arrival(_ beat: WelcomeModel.Beat) -> AnyTransition {
        guard let part = beat.lit?.first.map(Hero.place) else { return .opacity }
        let zoom = part.width * Self.map / Schemas.paper.width
        return .asymmetric(insertion: AnyTransition.scale(scale: zoom, anchor: .topLeading)
            .combined(with: .offset(x: 40 + part.minX * Self.map - 344, y: 430 + part.minY * Self.map - 24)).combined(with: .opacity), removal: .opacity.animation(Look.douce.animation(0.22)))
    }

    /// The Hero, small with a lens on each part lit; on the last beat it grows to its whole size and speaks.
    private func smallMap(_ beat: WelcomeModel.Beat, _ whole: Bool) -> some View {
        Hero(lit: beat.lit, builder: builder, motion: motion)
            .scaleEffect(whole ? 1 : Self.map, anchor: .topLeading)
            .animation(Look.motion(motion) == .calm ? Look.douce.animation(0.7) : nil, value: whole)
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 9).strokeBorder(Look.Token.line.ui).frame(width: 216, height: 126)
                    // By position, so a lens glides from one part to the next.
                    ForEach(Array((beat.lit ?? []).enumerated()), id: \.offset) { _, piece in
                        let part = Hero.place(piece)
                        RoundedRectangle(cornerRadius: 8).strokeBorder(Look.Token.ink.ui, lineWidth: 1.5)
                            .frame(width: part.width * Self.map + 2, height: part.height * Self.map + 2)
                            .offset(x: part.minX * Self.map - 1, y: part.minY * Self.map - 1)
                    }
                }
                .opacity(whole ? 0 : 1)
            }
            .offset(x: whole ? 130 : 40, y: whole ? 146 : 430)
            .accessibilityHidden(!whole)
    }

    /// No program on this Mac: the install commands of the first two.
    private var install: some View {
        VStack(spacing: 8) {
            ForEach(Array(InstallList.builders.prefix(2)), id: \.name) { row in
                HStack(spacing: 10) {
                    Text(row.command).font(Look.fixed(.code, size: 11)).lineLimit(1).truncationMode(.tail)
                        .accessibilityElement(children: .ignore).accessibilityLabel("\(row.name): \(row.command)")
                        .padding(.horizontal, 9).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .background(Look.Token.sunk.ui, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Button { model.copy(row.command, with: assistant.copy) } label: {
                        let done = model.copied == row.command
                        Text(done ? "Copied" : "Copy").font(Look.fixed(.ui, size: 12.5, weight: .semibold)).foregroundStyle((done ? Look.Token.ok : .ink).ui).frame(minWidth: 52)
                    }
                    .buttonStyle(Secondary())
                    .accessibilityLabel("Copy the command that installs \(row.name)")
                }
            }
        }
    }

    private func footer(_ beat: WelcomeModel.Beat) -> some View {
        let last = beat == .whole, none = assistant.kind == nil, searching = none && model.searching(assistant)
        let primary = !last ? "Continue" : !none ? "Make My First Space" : searching ? "Looking…" : "Look Again"
        let ghost = Look.fixed(.ui, size: 13, weight: .semibold)
        return HStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(WelcomeModel.Beat.allCases, id: \.self) { dot in
                    Capsule().fill((dot == beat ? Look.Token.ink : dot.rawValue < beat.rawValue ? .ink3 : .mist).ui).frame(width: dot == beat ? 18 : 6, height: 6)
                }
            }
            .accessibilityHidden(true)
            let count = "\(beat.rawValue + 1) of \(WelcomeModel.Beat.allCases.count)"
            Text(count).font(Look.fixed(.ui, size: 12).monospacedDigit()).foregroundStyle(Look.Token.ink3.ui).padding(.leading, 6)
            Button { model.skip(assistant) } label: { HStack(spacing: 8) { Cap("esc"); Text("Skip") }.font(ghost).foregroundStyle(Look.Token.ink2.ui) }
                .buttonStyle(.plain).padding(.leading, 16).accessibilityLabel("Skip")
            Spacer()
            if beat != .page {
                Button { model.go(-1) } label: {
                    HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)); Text("Back") }.font(ghost).foregroundStyle(Look.Token.ink2.ui)
                }
                .buttonStyle(.plain).padding(.trailing, 12).accessibilityLabel("Back")
            }
            if last {
                Text("No agent starts, nothing is spent.").font(Look.fixed(.ui, size: 12)).foregroundStyle(Look.Token.ink3.ui).padding(.trailing, 6)
                Button { model.example() } label: {
                    Text("Open an Example").font(ghost).padding(.horizontal, 14).frame(height: 34)
                        .boxed(RoundedRectangle(cornerRadius: 9, style: .continuous), Look.Token.bg2.ui, ring: Look.Token.line2.ui).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button { model.next(assistant) } label: {
                HStack(spacing: 8) { Cap("↵", primary: true); Text(primary).padding(.trailing, 5) }.font(ghost).frame(minWidth: 102, alignment: .leading)
            }
            .buttonStyle(Primary(height: 34, padding: 8)).disabled(searching).opacity(searching ? 0.5 : 1)
            .accessibilityLabel(primary)
        }
        .padding(.leading, 26).padding(.trailing, 16).frame(height: 60)
    }
}

/// A key: on the primary button, actfg on its own faint fill; elsewhere, a small key on bg2.
private struct Cap: View {
    let key: String, primary: Bool
    init(_ key: String, primary: Bool = false) { (self.key, self.primary) = (key, primary) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Text(key).font(Look.fixed(.ui, size: 11, weight: .semibold)).foregroundStyle((primary ? Look.Token.actfg : .ink2).ui)
            .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20)
            .boxed(shape, primary ? Look.Token.actfg.ui.opacity(0.16) : Look.Token.bg2.ui, ring: primary ? .clear : Look.Token.line2.ui)
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

/// Where the welcome stands and what it does: Return goes on, and at the last beat makes the first space, or looks for
/// the builders again when none was found. Escape skips, the close button ends it. Its end is kept in the preferences,
/// so it opens once.
@Observable final class WelcomeModel {
    /// A beat: one sentence, one schema, one part of the Hero lit (all of it on the last).
    enum Beat: Int, CaseIterable {
        case page, agent, roles, answer, whole

        var title: String {
            ["Pages of your own.", "What an agent is, and where it lives.", "The one that builds, and the ones you show.", "Only you answer.",
             "Ready to build something today?"][rawValue]
        }

        var sentence: String {
            ["Your agents live on your Mac. A space shows them your way: one HTML file, blank at first, locked off the network, yours to export.",
             "An agent is a conversation with a coding program on your Mac. You ask in plain words; it reads, writes and runs commands in a folder of yours.",
             "Both are agents of yours. They don’t get the same things.",
             "A space and an agent do what you allow, except pi, Amp and OMP, which never ask; everything else comes to you, in a window of your Mac no space can draw or answer.",
             "Say what you want in a sentence. You watch it being built, and you can leave while it works."][rawValue]
        }

        var lit: [Hero.Piece]? { [[.page], [.agents], [.assistant, .agents], [.panel], nil][rawValue] }
    }

    /// How it ended: what the window does next. `left` leaves the app as Help › Welcome found it.
    enum Ending { case made, skipped, example, skippedToExample, left }

    private(set) var beat = Beat.page
    /// When the beat arrived, which its schema plays from, and which way it came.
    private(set) var since = Date()
    private(set) var forward = true
    /// Whether Look Again is still looking.
    private(set) var looking = false
    /// The install command just copied, for a moment.
    private(set) var copied: String?
    /// Called once it ended, with how.
    @ObservationIgnored var finished: (Ending) -> Void = { _ in }
    /// Says a new beat to VoiceOver, since everything on the screen changed under the person.
    @ObservationIgnored var announce: (String) -> Void = { _ in }
    let places: Places
    /// Whether Help › Welcome opened it again, the app behind it, rather than a first start.
    let again: Bool

    init(places: Places, again: Bool = false) { (self.places, self.again) = (places, again) }

    /// Whether Look Again is busy: it was just clicked, or the builders were never looked for yet.
    func searching(_ assistant: AssistantModel) -> Bool { looking || (assistant.kind == nil && !assistant.noAgent) }

    /// Moves `step` beats, stopping at both ends.
    func go(_ step: Int) {
        guard let next = Beat(rawValue: beat.rawValue + step) else { return }
        (beat, since, forward) = (next, Date(), step > 0)
        announce("\(next.title) \(next.sentence)")
    }

    /// Return: the next beat. At the last, Look Again when no builder was found, else the end.
    func next(_ assistant: AssistantModel) {
        guard beat == .whole else { return go(1) }
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

    /// Escape: no more story. Once no builder was found New Space could not build, and the example needs none.
    func skip(_ assistant: AssistantModel) { end(again ? .left : assistant.noAgent ? .skippedToExample : .skipped) }

    /// The second door, which needs no agent.
    func example() { end(.example) }

    /// Ends the welcome: it is not shown again at the next start.
    func end(_ ending: Ending = .made) {
        Preferences.at(places).toured = true
        finished(ending)
    }
}
