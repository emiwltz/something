// The welcome window, 720 by 480, done by keyboard: Welcome ("Ready to build something today?"), Choose your
// assistant (the builders found, the agents only seen and why, those not on this Mac), A few comforts (each off until
// turned on), Meet your assistant (the sticker, ⌘K, its hello), and Ready; with no builder found, the install commands
// and Look Again. The footer says where the person is and what the keys do: Escape skips, ⌘[ goes back, Return goes on.
// While it is open the window takes every key, so no shortcut of the window behind it runs. Tour.swift holds its model.
import AppKit
import SomethingAgents
import SwiftUI

enum Welcome {
    static let size = NSSize(width: 720, height: 480)

    /// The welcome's own window, never released when closed, its content taking the keys.
    static func window(_ tour: Tour, assistant: AssistantModel, motion: Look.Motion) -> NSWindow {
        let keys = WelcomeKeys(tour: tour, assistant: assistant, motion: motion)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        (window.titlebarAppearsTransparent, window.titleVisibility, window.isReleasedWhenClosed) = (true, .hidden, false)
        window.title = "Welcome to something"
        window.backgroundColor = Look.Token.bg.color
        window.contentView = keys
        window.initialFirstResponder = keys
        window.makeFirstResponder(keys)
        return window
    }
}

/// The welcome's content, which takes the keys: Return, Escape, ⌘[, the arrows, Space and ⌘K go to the tour through
/// the text system's commands (interpretKeyEvents), so a layout's own keys and an input method's are respected.
final class WelcomeKeys: NSView {
    let tour: Tour, assistant: AssistantModel

    init(tour: Tour, assistant: AssistantModel, motion: Look.Motion) {
        (self.tour, self.assistant) = (tour, assistant)
        super.init(frame: NSRect(origin: .zero, size: Welcome.size))
        let host = NSHostingView(rootView: WelcomeView(tour: tour, assistant: assistant, motion: motion))
        host.sizingOptions = []
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) { interpretKeyEvents([event]) }

    /// ⌘[ goes back and ⌘K says hello; any other key equivalent is left to the menus.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "[": tour.back(assistant)
        case "k": tour.meet()
        default: return false
        }
        return true
    }

    override func insertNewline(_ sender: Any?) { tour.next(assistant) }
    override func cancelOperation(_ sender: Any?) { tour.skip() }
    override func moveUp(_ sender: Any?) { tour.arrow(0, -1, assistant) }
    override func moveDown(_ sender: Any?) { tour.arrow(0, 1, assistant) }
    override func moveLeft(_ sender: Any?) { tour.arrow(-1, 0, assistant) }
    override func moveRight(_ sender: Any?) { tour.arrow(1, 0, assistant) }
    override func insertText(_ insertString: Any) { if insertString as? String == " " { tour.toggle() } }
    /// Any other command of the text system does nothing, without the beep.
    override func doCommand(by selector: Selector) { if responds(to: selector) { super.doCommand(by: selector) } }
}

struct WelcomeView: View {
    @Bindable var tour: Tour
    let assistant: AssistantModel, motion: Look.Motion

    var body: some View {
        let screen = tour.screen(assistant)
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                page(screen).id(screen).transition(slide).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            Rectangle().fill(Look.Token.line.ui).frame(height: 1)
            footer(screen).frame(height: 59)
        }
        .animation(motion == .reduced ? nil : Look.douce.animation(0.45), value: screen)
        .font(Look.font(.ui, size: 13).ui).foregroundStyle(Look.Token.ink.ui)
        .background(Look.Token.bg.ui)
        .ignoresSafeArea()
    }

    /// A step comes in from the side it goes toward, 32 points, and fades.
    private var slide: AnyTransition {
        let by: CGFloat = tour.forward ? 32 : -32
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: by)), removal: .opacity.combined(with: .offset(x: -by)))
    }

    @ViewBuilder private func page(_ screen: Tour.Screen) -> some View {
        switch screen {
        case .welcome: welcome
        case .assistant: choose.padding(EdgeInsets(top: 42, leading: 64, bottom: 0, trailing: 64))
        case .none: none.padding(EdgeInsets(top: 48, leading: 64, bottom: 0, trailing: 64))
        case .comforts: comforts.padding(EdgeInsets(top: 58, leading: 64, bottom: 0, trailing: 64))
        case .meet: meet
        case .ready: ready.padding(EdgeInsets(top: 34, leading: 64, bottom: 0, trailing: 64))
        }
    }

    // MARK: The steps

    private var welcome: some View {
        VStack(spacing: 0) {
            WelcomeSign(state: .listen, side: 96, lands: true, motion: motion)
            Text("something").font(Look.font(.title, size: 62, weight: .semibold).ui).kerning(-2.17).padding(.top, 14)
            Text("Ready to build something today?").font(Look.font(.ui, size: 17).ui).foregroundStyle(Look.Token.ink2.ui).padding(.top, 10)
        }
        .accessibilityElement(children: .combine).accessibilityLabel("something. Ready to build something today?")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 18)
    }

    private var choose: some View {
        let found = assistant.entries.filter(\.enabled), grid = found.count > 2
        let kinds = assistant.engine.state.kinds, agents = Registry.app.agents
        // Seen only: an agent something reads but does not build with (unless it is known to be missing: something
        // does not look for the programs of those it only sees), or a builder that refused what it is lent.
        let seen = agents.filter { $0.builder == nil && kinds[$0.kind]?.installed != false }.map { ($0.name, $0.unavailable) }
            + assistant.entries.filter { !$0.enabled }.map { (Registry.app.name(of: $0.id), $0.note) }
        let missing = agents.filter { kinds[$0.kind]?.installed == false }.map(\.name)
        return VStack(alignment: .leading, spacing: 0) {
            heading("Choose your assistant")
            lead("It builds your spaces and changes them when you ask.")
            HStack(spacing: 6) {
                Circle().fill(Look.Token.ok.ui).frame(width: 7, height: 7)
                Text("Found on this Mac · \(found.count)")
                Spacer()
                Text("Where each one lives: Settings › Agents")
            }
            .font(Look.font(.ui, size: 11.5).ui).foregroundStyle(Look.Token.ink3.ui).padding(.top, 16)
            // Rows of plain stacks, not a lazy grid: a lazy grid gives VoiceOver none of its radios.
            let columns = grid ? 2 : 1
            VStack(spacing: 6) {
                ForEach(Array(stride(from: 0, to: found.count, by: columns)), id: \.self) { start in
                    HStack(spacing: 8) {
                        ForEach(start..<start + columns, id: \.self) { index in
                            if index < found.count { builder(found[index], compact: grid) } else { Color.clear.frame(maxWidth: .infinity, maxHeight: 0) }
                        }
                    }
                }
            }
            .padding(.top, 8)
            if !seen.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "eye").font(.system(size: 10.5)).padding(.top, 2).accessibilityHidden(true)
                    (Text("Seen only: \(Self.list(seen.map(\.0), "and")). ").fontWeight(.semibold).foregroundColor(Look.Token.ink2.ui)
                        + Text(Self.why(seen.compactMap(\.1))))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(Look.font(.ui, size: 12).ui).lineSpacing(2.5).foregroundStyle(Look.Token.ink3.ui).padding(.top, 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Seen only: \(Self.list(seen.map(\.0), "and")). \(Self.why(seen.compactMap(\.1)))")
            }
            if !missing.isEmpty {
                Text("Not on this Mac: \(missing.joined(separator: ", ")).").font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink3.ui)
                    .padding(.top, seen.isEmpty ? 12 : 6)
            }
            later(Text("You can change it any time in Settings."))
        }
    }

    /// One builder found, a radio: its name, then its model and effort as far as they are known before it ever ran.
    private func builder(_ entry: AssistantModel.Entry, compact: Bool) -> some View {
        let on = entry.checked, shape = RoundedRectangle(cornerRadius: Look.card, style: .continuous)
        return Button { assistant.choose(entry.id) } label: {
            HStack(spacing: compact ? 11 : 13) {
                ZStack {
                    Circle().strokeBorder(Look.Token.line2.ui, lineWidth: 1.5).opacity(on ? 0 : 1)
                    Circle().fill(Look.Token.ink.ui).opacity(on ? 1 : 0)
                    Circle().fill(Look.Token.bg2.ui).frame(width: 6, height: 6).opacity(on ? 1 : 0)
                }
                .frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: compact ? 0 : 2) {
                    Text(Registry.app.name(of: entry.id)).font(Look.font(.ui, size: 14, weight: .semibold).ui)
                    Text(Self.words(assistant.modelWords(of: entry.id))).font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink2.ui)
                }
                Spacer(minLength: 0)
            }
            .padding(compact ? EdgeInsets(top: 6, leading: 11, bottom: 6, trailing: 12) : EdgeInsets(top: 9, leading: 13, bottom: 9, trailing: 14))
            .frame(minHeight: compact ? 44 : 52)
            .background(Look.Token.bg2.ui, in: shape)
            .overlay(shape.strokeBorder(on ? Look.Token.ink.ui : Look.Token.line.ui, lineWidth: on ? 1.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(Registry.app.name(of: entry.id)), \(Self.words(assistant.modelWords(of: entry.id)))")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    /// `names` as a sentence says them: "A, B and C".
    static func list(_ names: [String], _ last: String) -> String {
        names.count > 1 ? names.dropLast().joined(separator: ", ") + " \(last) " + (names.last ?? "") : names.first ?? ""
    }

    /// Why the agents seen only are not offered, in one sentence when their reasons end alike ("A, and B, so something
    /// shows them but doesn't build with them."), else their sentences one after the other.
    static func why(_ reasons: [String]) -> String {
        let tail = ", so something shows it but doesn't build with it."
        guard reasons.count > 1, reasons.allSatisfy({ $0.hasSuffix(tail) }) else { return reasons.joined(separator: " ") }
        let heads = reasons.map { String($0.dropLast(tail.count)) }
        return heads.dropLast().joined(separator: ", ") + ", and " + (heads.last ?? "") + ", so something shows them but doesn't build with them."
    }

    /// "Model · Effort", the effort only when known.
    static func words(_ words: (model: String, effort: String?)) -> String { ([words.model] + [words.effort].compactMap { $0 }).joined(separator: " · ") }

    private var none: some View {
        let searching = tour.searching(assistant), rows = Array(InstallList.builders.prefix(2))
        return VStack(alignment: .leading, spacing: 0) {
            WelcomeSign(state: searching ? .think : .listen, side: 52, lands: false, motion: motion).padding(.leading, -6).padding(.bottom, 16)
            heading(searching ? "Looking for a coding agent" : "No coding agent found")
            lead("something builds your spaces with a coding agent you install yourself. Install one in Terminal, then look again.")
            VStack(spacing: 8) {
                ForEach(rows, id: \.name) { row in
                    HStack(spacing: 12) {
                        Text(row.name).font(Look.font(.ui, size: 13.5, weight: .semibold).ui).frame(width: 96, alignment: .leading).accessibilityHidden(true)
                        Text(row.command).font(Look.font(.code, size: 11.5).ui).lineLimit(1).truncationMode(.tail)
                            .accessibilityElement(children: .ignore).accessibilityLabel("\(row.name): \(row.command)")
                            .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                            .background(Look.Token.sunk.ui, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Button { tour.copy(row.command, with: assistant.copy) } label: {
                            let done = tour.copied == row.command
                            HStack(spacing: 7) { Image(systemName: done ? "checkmark" : "doc.on.doc").font(.system(size: 11)); Text(done ? "Copied" : "Copy Command") }
                                .font(Look.font(.ui, size: 12.5, weight: .semibold).ui).foregroundStyle((done ? Look.Token.ok : .ink).ui).frame(minWidth: 98)
                        }
                        .buttonStyle(Secondary())
                        .accessibilityLabel("Copy the command that installs \(row.name)")
                    }
                    .padding(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 8))
                    .background(Look.Token.bg2.ui, in: RoundedRectangle(cornerRadius: Look.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Look.card, style: .continuous).strokeBorder(Look.Token.line.ui))
                }
            }
            .padding(.top, 20)
            Button { tour.explained.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle").font(.system(size: 12))
                    Text("What is a coding agent?")
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).rotationEffect(.degrees(tour.explained ? 90 : 0))
                }
                .font(Look.font(.ui, size: 12.5, weight: .medium).ui).foregroundStyle(Look.Token.ink2.ui).contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.top, 14).padding(.leading, 2)
            if tour.explained {
                let names = InstallList.builders.prefix(2).map(\.name)
                Text("A program that reads and writes code in a folder when you ask it in plain words, like \(Self.list(names, "or")). It runs on your Mac, with your own account. something never installs one for you.")
                    .font(Look.font(.ui, size: 12.5).ui).lineSpacing(3).foregroundStyle(Look.Token.ink2.ui).frame(maxWidth: 540, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
        }
    }

    private var comforts: some View {
        let one = tour.comforts.count == 1
        return VStack(alignment: .leading, spacing: 0) {
            heading("A few comforts")
            lead(one ? "It stays off until you turn it on. You'll find it again in Settings." : "Each one stays off until you turn it on. You'll find both again in Settings.")
            VStack(spacing: 0) {
                ForEach(Array(tour.comforts.enumerated()), id: \.offset) { index, comfort in
                    if index > 0 { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }
                    self.comfort(comfort, current: index == tour.cursor)
                }
            }
            .background(Look.Token.bg2.ui, in: RoundedRectangle(cornerRadius: Look.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Look.card, style: .continuous).strokeBorder(Look.Token.line.ui))
            .padding(.top, 24)
        }
    }

    private func comfort(_ comfort: Tour.Comfort, current: Bool) -> some View {
        let (icon, title, why) = comfort == .launcher
            ? ("folder", "Add something to Applications", "So Spotlight finds it: a small launcher in your Applications folder opens something. Nothing else on your Mac changes.")
            : ("bell", "Tell me when an agent waits for me", "A notification when an agent needs your answer. macOS asks you once to allow it.")
        let on = tour.isOn(comfort)
        return Button { tour.toggle(comfort) } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 13.5)).frame(width: 34, height: 34)
                    .background(Look.Token.sunk.ui, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Look.font(.ui, size: 14, weight: .semibold).ui)
                    Text(why).font(Look.font(.ui, size: 12.5).ui).lineSpacing(3).foregroundStyle(Look.Token.ink2.ui).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Switch(on: on)
            }
            .padding(EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16))
            .overlay(RoundedRectangle(cornerRadius: Look.card - 3, style: .continuous).strokeBorder(Look.Token.ink3.ui, lineWidth: 1.5).padding(3).opacity(current ? 1 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(on ? "On" : "Off")
    }

    private var meet: some View {
        HStack(spacing: 30) {
            BigSticker(joy: tour.met, motion: motion).frame(width: 230, height: 300)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Image(nsImage: Sign.miniEyes(.listen, joy: tour.met)).renderingMode(.template).frame(width: 16, height: 10)
                    Text("\(assistant.name) · \(assistant.modelWords.model)")
                }
                .font(Look.font(.ui, size: 12, weight: .medium).ui).foregroundStyle(Look.Token.ink2.ui)
                .padding(.leading, 8).padding(.trailing, 10).frame(height: 26)
                .background(Look.Token.hover.ui, in: Capsule())
                .padding(.bottom, 14)
                heading("Meet your assistant")
                lead("It waits in a corner of every space. Its eyes tell you what it is doing.")
                if tour.met {
                    Text("Hi. Tell me what you'd like to make, and I'll build it with you.")
                        .font(Look.font(.voice, size: 17).ui).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 17).padding(.vertical, 12).frame(maxWidth: 360, alignment: .leading)
                        .background(Look.Token.bg2.ui, in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6, bottomTrailingRadius: 20, topTrailingRadius: 20))
                        .overlay(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6, bottomTrailingRadius: 20, topTrailingRadius: 20).strokeBorder(Look.Token.line.ui))
                        .padding(.top, 24)
                        .accessibilityLabel("Your assistant: Hi. Tell me what you'd like to make, and I'll build it with you.")
                    Text("That's all it takes, in any space: \(Keys.shown("ask")), then your words.").font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink3.ui)
                        .padding(.top, 10)
                } else {
                    HStack(spacing: 12) {
                        BigCap(key: "⌘")
                        BigCap(key: "K")
                        Text("Press \(Keys.shown("ask")) to talk to it").font(Look.font(.ui, size: 12.5).ui).foregroundStyle(Look.Token.ink3.ui).padding(.leading, 6)
                        HStack(spacing: 3) { ForEach(0..<3) { _ in Circle().fill(Look.Token.ink3.ui).frame(width: 4, height: 4) } }
                    }
                    .accessibilityElement(children: .ignore).accessibilityLabel("Press \(Keys.shown("ask")) to talk to it")
                    .padding(.top, 26)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EdgeInsets(top: 0, leading: 48, bottom: 0, trailing: 56))
        .frame(maxHeight: .infinity)
        .padding(.top, 46)
    }

    private var ready: some View {
        let folder = Words.path(assistant.places.spaces.path, home: assistant.places.home.path)
        var code = AttributedString(folder)
        code.font = Look.font(.code, size: 11.5).ui
        return VStack(alignment: .leading, spacing: 0) {
            WelcomeSign(state: .listen, joy: true, side: 52, lands: false, motion: motion).padding(.leading, -6).padding(.bottom, 12)
            heading("Make your first space")
            Text(AttributedString("Describe a page in a few words. \(assistant.name) builds it in ") + code + AttributedString(", and nothing leaves your Mac."))
                .font(Look.font(.ui, size: 14.5).ui).lineSpacing(5).foregroundStyle(Look.Token.ink2.ui).frame(maxWidth: 520, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            Grid(alignment: .topLeading, horizontalSpacing: 28, verticalSpacing: 9) {
                let who = "\(assistant.name) · \(Self.words(assistant.modelWords))"
                GridRow {
                    Text("Assistant").foregroundStyle(Look.Token.ink3.ui).accessibilityHidden(true)
                    HStack(spacing: 7) {
                        Image(nsImage: Sign.miniEyes(.listen)).renderingMode(.template).frame(width: 16, height: 10)
                        Text(who)
                    }
                    .fontWeight(.medium)
                    .accessibilityElement(children: .ignore).accessibilityLabel("Assistant: \(who)")
                }
                if tour.offersLauncher { summary("Applications", tour.addLauncher ? "Added" : "Not added", on: tour.addLauncher) }
                summary("Notifications", tour.notify ? "On" : "Off", on: tour.notify)
                let promise = "When an agent asks for something, a small window of your Mac asks you. Only you answer."
                GridRow {
                    Text("Requests").foregroundStyle(Look.Token.ink3.ui).accessibilityHidden(true)
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "checkmark.shield").font(.system(size: 11)).foregroundStyle(Look.Token.ink.ui).padding(.top, 2).accessibilityHidden(true)
                        Text(promise).lineSpacing(2.5).foregroundStyle(Look.Token.ink2.ui).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore).accessibilityLabel("Requests: \(promise)")
                }
            }
            .font(Look.font(.ui, size: 13).ui)
            .padding(EdgeInsets(top: 15, leading: 18, bottom: 15, trailing: 18)).frame(maxWidth: .infinity, alignment: .leading)
            .background(Look.Token.bg2.ui, in: RoundedRectangle(cornerRadius: Look.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Look.card, style: .continuous).strokeBorder(Look.Token.line.ui))
            .padding(.top, 16)
            later(Text("All of this lives in Settings"), keys: ["⌘", ","])
        }
    }

    private func summary(_ term: String, _ value: String, on: Bool) -> some View {
        // The term is said with its value, in one label: a row reads as "Notifications: Off".
        GridRow {
            Text(term).foregroundStyle(Look.Token.ink3.ui).accessibilityHidden(true)
            HStack(spacing: 7) {
                if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)) }
                Text(value)
            }
            .fontWeight(on ? .medium : .regular).foregroundStyle((on ? Look.Token.ink : .ink2).ui)
            .accessibilityElement(children: .ignore).accessibilityLabel("\(term): \(value)")
        }
    }

    // MARK: Pieces

    private func heading(_ text: String) -> some View {
        Text(text).font(Look.titleL.font.ui).kerning(-0.95).padding(.vertical, -3).accessibilityAddTraits(.isHeader)
    }

    private func lead(_ text: String) -> some View {
        Text(text).font(Look.font(.ui, size: 14.5).ui).lineSpacing(5).foregroundStyle(Look.Token.ink2.ui)
            .frame(maxWidth: 520, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
    }

    /// Where it all lives later: a gear, `text` and its keys.
    private func later(_ text: Text, keys: [String] = []) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "gearshape").font(.system(size: 10.5)).accessibilityHidden(true)
            text
            ForEach(keys, id: \.self) { Cap($0, small: true) }
        }
        .font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink3.ui).padding(.top, 8)
    }

    // MARK: The footer

    private func footer(_ screen: Tour.Screen) -> some View {
        let step = tour.step.rawValue, count = Tour.Step.allCases.count, searching = screen == .none && tour.searching(assistant)
        let primary = screen == .none ? (searching ? "Looking…" : "Look Again") : screen == .ready ? "Make Your First Space" : "Continue"
        return HStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule().fill((index == step ? Look.Token.ink : index < step ? .ink3 : .mist).ui).frame(width: index == step ? 18 : 6, height: 6)
                }
            }
            .accessibilityHidden(true)
            Text("\(step + 1) of \(count)").font(Look.font(.ui, size: 12).ui).monospacedDigit().foregroundStyle(Look.Token.ink3.ui).padding(.leading, 6)
            if screen != .ready {
                Button { tour.skip() } label: { HStack(spacing: 8) { Cap("esc"); Text("Skip Tour") } }.buttonStyle(Ghost()).padding(.leading, 8)
                    .accessibilityLabel("Skip Tour")
            }
            Spacer()
            if let hint = hint(screen) {
                HStack(spacing: 6) { ForEach(hint.keys, id: \.self) { Cap($0) }; Text(hint.words) }
                    .font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink3.ui).padding(.trailing, 6)
                    .accessibilityElement(children: .ignore).accessibilityLabel(hint.words)
            }
            if step > 0 {
                Button { tour.back(assistant) } label: {
                    HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 10.5, weight: .semibold)).frame(width: 15); Text("Back") }
                }
                .buttonStyle(Ghost(leading: 6, trailing: 12)).disabled(searching)
                .accessibilityLabel("Back")
            }
            Button { tour.next(assistant) } label: {
                HStack(spacing: 8) { Cap("↵", on: true); Text(primary) }
                    .font(Look.font(.ui, size: 13, weight: .semibold).ui).foregroundStyle(Look.Token.actfg.ui)
                    .padding(.leading, 8).padding(.trailing, 13).frame(minWidth: 118, minHeight: 34, alignment: .leading)
                    .background(Look.Token.act.ui, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(searching).opacity(searching ? 0.5 : 1)
            .accessibilityLabel(primary)
        }
        .padding(.leading, 26).padding(.trailing, 16)
    }

    /// What the arrows or Space do at this step, when they do anything.
    private func hint(_ screen: Tour.Screen) -> (keys: [String], words: String)? {
        switch screen {
        case .assistant where assistant.entries.filter(\.enabled).count > 1: (["↑", "↓"], "Choose")
        case .comforts: (["space"], "Turn On or Off")
        default: nil
        }
    }
}

/// A key as the welcome draws it: Onest 11 semibold in ink2 on bg2, a hairline and a step below; on the primary
/// button, actfg on its own faint fill. `small` is the one in a line of text.
private struct Cap: View {
    let key: String, on: Bool, small: Bool
    init(_ key: String, on: Bool = false, small: Bool = false) { (self.key, self.on, self.small) = (key, on, small) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous), side: CGFloat = small ? 18 : 20
        Text(key).font(Look.font(.ui, size: 11, weight: .semibold).ui).foregroundStyle((on ? Look.Token.actfg : .ink2).ui)
                .padding(.horizontal, 5).frame(minWidth: side, minHeight: side)
                .background(on ? Look.Token.actfg.ui.opacity(0.16) : Look.Token.bg2.ui, in: shape)
                .overlay(shape.strokeBorder(Look.Token.line2.ui).opacity(on ? 0 : 1))
                .background(shape.fill(Look.Token.line2.ui).offset(y: 1).opacity(on ? 0 : 1))
    }
}

/// ⌘ and K at the fourth step, 54 points: the keys to press.
private struct BigCap: View {
    let key: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Text(key).font(Look.font(.ui, size: 22, weight: .medium).ui).frame(width: 54, height: 54)
            .background(Look.Token.bg2.ui, in: shape)
            .overlay(shape.strokeBorder(Look.Token.line2.ui))
            .background(shape.fill(Look.Token.line2.ui).offset(y: 2))
    }
}

/// The footer's quiet buttons: ink2, the hover fill under the pointer.
private struct Ghost: ButtonStyle {
    var leading: CGFloat = 8, trailing: CGFloat = 13

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Look.font(.ui, size: 13, weight: .semibold).ui).foregroundStyle(Look.Token.ink2.ui)
            .padding(.leading, leading).padding(.trailing, trailing).frame(height: 34)
            .background(configuration.isPressed ? Look.Token.hover.ui : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// A switch as the mockup draws it, 30 by 18: ink when on, mist when off.
private struct Switch: View {
    let on: Bool

    var body: some View {
        Capsule().fill((on ? Look.Token.ink : .mist).ui).frame(width: 30, height: 18)
            .overlay(alignment: on ? .trailing : .leading) { Circle().fill(Look.Token.bg2.ui).frame(width: 14, height: 14).padding(2) }
            .accessibilityHidden(true)
    }
}

/// The sign in the welcome, at `side` points, in `state`, smiling with `joy`; with `lands`, it lands as the step opens.
private struct WelcomeSign: NSViewRepresentable {
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
        sign.joy = joy
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SignView, context: Context) -> CGSize? { CGSize(width: side, height: side) }
}

/// The sticker at the fourth step, 150 points: the sign of 118 on its surface with the hard shadow (it is the thing
/// the person will grab in every space), Ready. Its eyes smile once it said hello, wider and finer than the small
/// sign's smile, as the mockup's .ob-stk draws them.
private struct BigSticker: NSViewRepresentable {
    let joy: Bool, motion: Look.Motion

    final class Face: NSView {
        let sign = SignView(.listen, side: 118)
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            Sign.grab(NSRect(x: (bounds.width - 150) / 2, y: (bounds.height - 150) / 2, width: 150, height: 150), radius: 38)
        }
        override func layout() {
            super.layout()
            sign.frame = NSRect(x: (bounds.width - 118) / 2, y: (bounds.height - 118) / 2, width: 118, height: 118)
        }
    }

    func makeNSView(context: Context) -> Face {
        let face = Face()
        face.addSubview(face.sign)
        (face.sign.name, face.sign.motion, face.sign.joy) = ("Your assistant", motion, joy)
        (face.sign.geometry.joy, face.sign.geometry.joyStroke) = (1.5, 0.34)
        return face
    }

    func updateNSView(_ face: Face, context: Context) { face.sign.joy = joy }
}
