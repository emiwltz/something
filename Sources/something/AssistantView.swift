// The assistant in the window (plan B.3), floating at the bottom of the center: the capsule with the agent menu, the
// input and the send or stop button (Composer, which the blank page shows bigger); the status line above it; the
// drawer with the conversation; the open space's error banner; and, when no coding agent is found, a notice in the
// capsule's place. Its state is AssistantModel's; the views keep only the input's focus.
import SomethingAgents
import SwiftUI

struct AssistantView: View {
    @Bindable var model: AssistantModel

    var body: some View {
        VStack(spacing: 6) {
            if !model.hidden {
                if model.drawer { drawer }
                if let fault = model.fault { banner(fault) }
                if let status = model.status { statusLine(status) }
                // The blank page has its own, bigger input.
                if model.place != .blank {
                    if model.noAgent { NoAgent(model: model) } else { Composer(model: model, big: false) }
                }
            }
        }
        // The window sizes the assistant by its ideal size, measured at its ideal width: without one, every line
        // would be measured unwrapped, and the conversation, wrapped at 640 points, would not fit what it asked for.
        .frame(idealWidth: 640, maxWidth: 640)
        .padding(AssistantView.margin)
        .coordinateSpace(.named(Drawn.space))
        .onPreferenceChange(Drawn.self) { model.drawn = $0 }
    }

    /// Room around the assistant for its shadows. The window lets through the clicks there, and anywhere else nothing
    /// is drawn (Floater).
    static let margin: CGFloat = 16

    /// The agent menu, in the capsule and in the drawer's header.
    @ViewBuilder static func menu(_ model: AssistantModel) -> some View {
        Section("Build With") {
            ForEach(model.entries) { entry in
                Toggle(entry.title, isOn: Binding(get: { entry.checked }, set: { _ in model.choose(entry.id) }))
                    .disabled(!entry.enabled)
                    .help(entry.note ?? "")
            }
        }
        Divider()
        Button("New Conversation") { model.newConversation() }
        Button("Stop") { model.stop() }.disabled(!model.working)
        if model.canAskEverything {
            Toggle("Ask Before Every Change", isOn: Binding(get: { model.askEverything }, set: { _ in model.toggleAsking() }))
        }
        Divider()
        Button("Look for Agents Again") { model.engine.lookAgain() }
    }

    private func statusLine(_ status: String) -> some View {
        // "“Pebble” is ready. Open": Open reads as the link it is. The line says it only when nothing more pressing.
        let ready = model.failure == nil && !model.working ? model.ready : nil
        return (ready.map { Text("“\($0.title)” is ready. ") + Text("Open").foregroundColor(.accentColor) } ?? Text(status))
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .modifier(Floating(shape: Capsule(style: .circular)))
            .onTapGesture { if let ready { model.openReady(ready.id) } else if model.light == .waiting { model.showRequest() } }
    }

    private func banner(_ fault: AssistantModel.Fault) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("This space has an error.")
            Button("Ask to Fix") { model.fix(fault) }.disabled(model.kind == nil)
            Button { model.fault = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Dismiss")
        }
        .font(.system(size: 12))
        .controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .modifier(Floating(shape: Capsule(style: .circular)))
    }

    // MARK: The drawer

    private var drawer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Assistant · \(model.name)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Menu { AssistantView.menu(model) } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
            }
            // The scroll view asks for the whole conversation's height, and the window gives it what is left under its
            // cap: all of it when it fits, else its end, which stays in view while at the bottom.
            ScrollView { conversation }
                .defaultScrollAnchor(.bottom)
                .scrollBounceBehavior(.basedOnSize)
                .contentMargins(.top, 16, for: .scrollContent)
                .mask {
                    // A line cut by the top edge fades out over 20 points, whatever the drawer's height.
                    VStack(spacing: 0) {
                        LinearGradient(stops: [.init(color: .clear, location: 0.25), .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 20)
                        Color.black
                    }
                }
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16))
        .frame(maxHeight: 560)
        .modifier(Floating(shape: RoundedRectangle(cornerRadius: 16, style: .continuous)))
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(model.firstLines, id: \.self) { Text($0).font(.system(size: 11.5)).foregroundStyle(.secondary) }
            ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in line(row) }
            if let problem = model.problem { failure(problem) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }

    @ViewBuilder private func line(_ row: AssistantModel.Row) -> some View {
        switch row {
        case .mine(let caption, let text):
            VStack(alignment: .trailing, spacing: 2) {
                if let caption { Text(caption).font(.system(size: 10.5)).foregroundStyle(.secondary) }
                Text(text)
                    .font(.system(size: 13))
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.2),
                                in: UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14, bottomTrailingRadius: 4, topTrailingRadius: 14))
            }
            .padding(.leading, 90)
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .reply(let text):
            Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
                .font(.system(size: 13))
                .padding(.trailing, 40)
        case .tool(let symbol, let words, let command):
            HStack(spacing: 7) {
                Image(systemName: symbol).foregroundStyle(.tertiary).frame(width: 14)
                if let command {
                    Text("Ran ") + Text(command).font(.system(size: 11.5, design: .monospaced)) + Text(words)
                } else {
                    Text(words)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .truncationMode(.middle)
        }
    }

    /// The red row: what the agent said went wrong, and how to sign it in.
    private func failure(_ problem: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(model.name) couldn't answer: \(problem)").fontWeight(.semibold)
            Text("If it isn't signed in, open Terminal, type \(model.kind ?? "claude") and sign in. Then click Try Again.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Copy Command") { model.copyCommand() }
                Button("Try Again") { model.tryAgain() }.buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .font(.system(size: 12))
        .padding(10)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// The input and what goes with it: the builder's dot and menu, the conversation's chevron and the send or stop
/// button. In the capsule it is one line that grows to five; on the blank page (`big`) it is a box of its own, the
/// input above, the rest below.
struct Composer: View {
    @Bindable var model: AssistantModel
    let big: Bool
    @FocusState private var typing: Bool
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        if big {
            VStack(alignment: .leading, spacing: 14) {
                field
                HStack(spacing: 8) { builder; Spacer(); chevron; send }
            }
            .padding(EdgeInsets(top: 16, leading: 18, bottom: 10, trailing: 12))
            // On the page itself, not floating over a space: an opaque ground.
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.1), radius: 18, y: 8)
        } else {
            HStack(spacing: 8) { builder; field; chevron; send }
                .padding(7)
                .frame(minHeight: 44)
                .modifier(Floating(shape: Capsule(style: .circular)))
        }
    }

    private var builder: some View {
        HStack(spacing: 6) {
            dot
            Menu { AssistantView.menu(model) } label: { Text(model.name) }
                .menuStyle(.borderlessButton)
                .fixedSize()
        }
        .font(.system(size: 12.5, weight: .medium))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }

    private var field: some View {
        TextField(model.placeholder, text: $model.draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: big ? 16 : 13.5))
            .lineLimit(big ? 2...8 : 1...5)
            .focused($typing)
            .onChange(of: model.focusing) { typing = true }
            .onAppear { if big { typing = true } }
            .onKeyPress(.return, phases: .down) { press in
                // Return first confirms what an input method composes (Japanese, Chinese, Korean).
                if (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true { return .ignored }
                if !press.modifiers.contains(.shift) {
                    model.send()
                } else if !NSApp.sendAction(#selector(NSTextView.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil) {
                    model.draft += "\n"
                }
                return .handled
            }
    }

    private var chevron: some View {
        Button { model.drawer.toggle() } label: { Image(systemName: model.drawer ? "chevron.down" : "chevron.up") }
            .buttonStyle(.borderless)
            .foregroundStyle(.tertiary)
            .help(model.drawer ? "Hide Conversation (⌘J)" : "Show Conversation (⌘J)")
    }

    private var send: some View {
        let empty = model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, working = model.working
        return Button { working ? model.stop() : model.send() } label: {
            Image(systemName: working ? "stop.fill" : "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(working ? Color(nsColor: .windowBackgroundColor) : .white)
                .frame(width: 30, height: 30)
                .background(working ? Color.primary : Color.accentColor.opacity(empty ? 0.45 : 1), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!working && (empty || model.kind == nil))
        .help(working ? "Stop (⌘.)" : "Send (Return)")
    }

    /// Gray not started, green ready, pulsing blue working, orange waiting for the person, red when it went wrong.
    private var dot: some View {
        let color: Color = switch model.light {
        case .off: .gray
        case .ready: .green
        case .working: .blue
        case .waiting: .orange
        case .error: .red
        }
        return Image(systemName: "circle.fill")
            .font(.system(size: 7))
            .foregroundStyle(color)
            .symbolEffect(.pulse, isActive: model.light == .working && !still)
            .accessibilityLabel(model.light.rawValue)
    }
}

/// In the input's place when no installed agent can build spaces.
struct NoAgent: View {
    let model: AssistantModel

    var body: some View {
        HStack(spacing: 8) {
            Text(model.notice).font(.system(size: 13.5))
            Spacer()
            Button("How to Get One") { model.howTo() }
            Button("Look Again") { model.engine.lookAgain() }.buttonStyle(.borderedProminent)
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .modifier(Floating(shape: Capsule(style: .circular)))
    }
}

/// Material, a hairline and a soft shadow: the assistant floats over the space. A pill is a circular `Capsule`: the
/// material of a continuous one ends in a point at each side.
struct Floating<Ground: InsettableShape>: ViewModifier {
    var shape: Ground

    func body(content: Content) -> some View {
        // The ground's shadow alone, cast by its shape: on the content, every text and bubble would cast its own.
        content
            .background { shape.fill(.regularMaterial).shadow(color: .black.opacity(0.15), radius: 10, y: 4) }
            .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
            .background { GeometryReader { Color.clear.preference(key: Drawn.self, value: [$0.frame(in: .named(Drawn.space))]) } }
    }
}

/// The frames of the floating pieces, in the assistant's own coordinate space.
struct Drawn: PreferenceKey {
    static let space = "assistant"
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

/// How to Get One's list: each agent, the command that installs it, and a button that copies that command.
struct InstallList: View {
    let rows: [(name: String, command: String)], copy: (String) -> Void

    /// The coding agents something builds with (none it refuses), each with its install command.
    static var builders: [(name: String, command: String)] {
        AssistantModel.builders.filter { AssistantModel.cannotBuild[$0] == nil }
            .compactMap { kind in Programs.install[kind].map { (Programs.name(of: kind), $0) } }
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            ForEach(rows, id: \.name) { row in
                GridRow {
                    Text(row.name).fontWeight(.medium)
                    Text(row.command).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Button("Copy") { copy(row.command) }.controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
