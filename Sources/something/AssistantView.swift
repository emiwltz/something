// The assistant in the window (plan B.3), floating at the bottom of the center: the capsule with the agent menu, the
// input and the send or stop button; the status line above it; the drawer with the conversation; the open space's
// error banner; and, when no coding agent is found, a notice in the capsule's place. Its state is AssistantModel's;
// the view keeps only the input's focus.
import SwiftUI

struct AssistantView: View {
    @Bindable var model: AssistantModel
    @FocusState private var typing: Bool
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        VStack(spacing: 6) {
            if !model.hidden {
                if model.drawer { drawer }
                if let fault = model.fault { banner(fault) }
                if let status = model.status { statusLine(status) }
                if model.noAgent { notice } else { capsule }
            }
        }
        .frame(maxWidth: 640)
        .padding(AssistantView.margin)
        .onChange(of: model.focusing) { typing = true }
    }

    /// Room around the assistant for its shadows: the window lets the clicks there through (Floater).
    static let margin: CGFloat = 16

    // MARK: The capsule

    private var capsule: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                dot
                Menu { menu } label: { Text(model.name) }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
            }
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
            TextField(model.placeholder, text: $model.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .lineLimit(1...5)
                .focused($typing)
                .onKeyPress(.return, phases: .down) { press in
                    if !press.modifiers.contains(.shift) {
                        model.send()
                    } else if !NSApp.sendAction(#selector(NSTextView.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil) {
                        model.draft += "\n"
                    }
                    return .handled
                }
            Button { model.drawer.toggle() } label: { Image(systemName: model.drawer ? "chevron.down" : "chevron.up") }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
                .help(model.drawer ? "Hide Conversation (⌘J)" : "Show Conversation (⌘J)")
            sendButton
        }
        .padding(.leading, 7).padding(.trailing, 7).padding(.vertical, 7)
        .frame(minHeight: 44)
        .modifier(Floating(radius: 22))
    }

    private var working: Bool { model.light == .working || model.light == .waiting }

    private var sendButton: some View {
        let empty = model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    /// The agent menu, in the capsule and in the drawer's header.
    @ViewBuilder private var menu: some View {
        Section("Build With") {
            ForEach(model.entries) { entry in
                Toggle(entry.title, isOn: Binding(get: { entry.checked }, set: { _ in model.choose(entry.id) }))
                    .disabled(!entry.enabled)
                    .help(entry.note ?? "")
            }
        }
        Divider()
        Button("New Conversation") { model.newConversation() }
        Button("Stop") { model.stop() }.disabled(!working)
        if model.canAskEverything {
            Toggle("Ask Before Every Change", isOn: Binding(get: { model.askEverything }, set: { _ in model.toggleAsking() }))
        }
        Divider()
        Button("Look for Agents Again") { model.engine.lookAgain() }
    }

    /// In the capsule's place when no installed agent can build spaces.
    private var notice: some View {
        HStack(spacing: 8) {
            Text(model.notice).font(.system(size: 13.5))
            Spacer()
            Button("How to Get One") { model.howTo() }
            Button("Look Again") { model.engine.lookAgain() }.buttonStyle(.borderedProminent)
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .modifier(Floating(radius: 22))
    }

    private func statusLine(_ status: String) -> some View {
        Text(status)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .modifier(Floating(radius: 10))
            .onTapGesture { if model.light == .waiting { model.showRequest() } }
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
        .modifier(Floating(radius: 14))
    }

    // MARK: The drawer

    private var drawer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Assistant · \(model.name)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Menu { menu } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
            }
            // The whole conversation when it fits, else the end of it, which stays in view while at the bottom.
            ViewThatFits(in: .vertical) {
                conversation
                ScrollView { conversation }
                    .defaultScrollAnchor(.bottom)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08)], startPoint: .top, endPoint: .bottom))
            }
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16))
        .frame(maxHeight: 560)
        .modifier(Floating(radius: 16))
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
                if let caption { Text(caption).font(.system(size: 10.5)).foregroundStyle(.tertiary) }
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

/// Material, a hairline and a soft shadow: the assistant floats over the space.
struct Floating: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // The ground's shadow alone: on the content, every text and bubble would cast its own.
        content
            .background(.regularMaterial.shadow(.drop(color: .black.opacity(0.15), radius: 10, y: 4)), in: shape)
            .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
    }
}

/// How to Get One's list: each agent, the command that installs it, and a button that copies that command.
struct InstallList: View {
    let rows: [(name: String, command: String)], copy: (String) -> Void

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
