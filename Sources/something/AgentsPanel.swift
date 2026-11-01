// The panel's Agents tab, its default: the sentence that says what this page may do, the space's assistant, what the page
// sees, and the others on this Mac, by folder. It is calm at rest: one row drawing for all, title and state over program
// and tag, and only an opened row says more, without repeating its line. Rows read an agent; what acts on one joins
// them with its slice. The panel reads the state as it is, so an opened row may show what no page gets, as an error's words.
import AppKit
import SomethingAgents
import SomethingCore
import SwiftUI

/// Eyes alone, in the ink of the view's scheme: a row's and ⌘P's.
struct MiniEyes: View {
    let state: Sign.State
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let image = Sign.miniEyes(state, template: false), appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        Image(nsImage: NSImage(size: image.size, flipped: false) { rect in
            if let appearance { appearance.performAsCurrentDrawingAppearance { image.draw(in: rect) } } else { image.draw(in: rect) }
            return true
        })
    }
}

struct AgentsPanel: View {
    @Bindable var info: Info
    let assistant: AssistantModel
    /// The space's title, and how its eyes move.
    let title: String, motion: Look.Motion

    private var home: String { info.places.home.path }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section(top: 10) { sentence }
                    if assistant.place.space == info.space?.name { section { assistantRow } }
                    section { sees }
                    section { others }
                }
            }
            // What Look Again found may stand below the fold, and its halo with it.
            .onChange(of: info.fresh) { if let first = info.fresh.first { withAnimation { scroller.scrollTo(first) } } }
        }
    }

    /// The sentence, the same as New Space's, or why it cannot be said.
    @ViewBuilder private var sentence: some View {
        if let problem = info.problem {
            Text(problem).foot()
        } else if info.level != nil {
            Sentence("This space", choice: Binding(get: { info.choice }, set: info.say), folders: info.folders, home: home, warning: info.warning,
                     agents: info.kinds.isEmpty ? nil : info.kinds, space: info.space?.name, anyAgent: info.kinds.count != 1, size: 13.5)
        } else {
            Text("It can’t be shown now, so it shows no agent.").foot()
        }
    }

    /// Its assistant: an agent with a job, on the same row. Stuck or waking, it says so in the card's words. Asleep or
    /// gone it has no tag: it runs nowhere.
    private var assistantRow: some View {
        let presence = assistant.presence
        return AgentRow(info: info, id: "assistant", title: Words.possessive(title) + " assistant", word: presence.rowWord,
                        under: "\(assistant.name) · \(Words.path(info.places.spaces.path, home: home))", tag: presence.runs ? "In something" : nil) {
            PageSign(state: presence.state, side: 20, lands: false, motion: motion).frame(width: 20, height: 20).accessibilityHidden(true)
        } details: {
            VStack(alignment: .leading, spacing: 9) {
                AgentChips(model: assistant, compact: true)
                OpenedAgent(lines: [assistant.agent?.error.map { .plain($0.message) }, resting(presence).map { .plain($0) }].compactMap { $0 })
            }
        }
    }

    /// What a stopped assistant's next step is: why it is stuck, or what the next message does.
    private func resting(_ presence: Presence) -> String? {
        if let notice = presence.notice { return notice.text }
        guard presence.state == .sleep else { return nil }
        if assistant.resumes { return "It wakes on your next message." }
        return assistant.agentResumes ? "Your next message starts a new conversation." : "\(assistant.name) can’t resume. Your next message starts a new conversation."
    }

    /// This Space Sees: exactly the page's list, and a quiet line for the assistants it holds, which have their own row
    /// and only their state there.
    private var sees: some View {
        let assistants = info.seenAssistants, also = "\(assistants) assistant\(assistants == 1 ? ", its" : "s, their") state only"
        return VStack(alignment: .leading, spacing: 7) {
            Heading(words: "This Space Sees", count: info.level == Grant.Level.none ? nil : info.shown.count + assistants).padding(.horizontal, 4)
                .frame(minHeight: 24)
            if !info.shown.isEmpty {
                VStack(spacing: 1) { ForEach(info.shown, id: \.id) { row($0, out: false) } }
            }
            if assistants > 0 {
                Text(info.shown.isEmpty ? also + "." : "and " + also + ".").font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink2.ui).padding(.horizontal, 4)
            } else if info.shown.isEmpty {
                Text("This space sees no agent.").font(Look.font(.ui, size: 12.5).ui).foregroundStyle(Look.Token.ink2.ui).padding(.horizontal, 4)
            }
        }
    }

    /// Others on This Mac: folded when long, Look Again always there; one line when there are none.
    private var others: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                if info.others.isEmpty {
                    Heading(words: "Others on This Mac", count: 0).padding(.horizontal, 4)
                } else {
                    Button { info.othersOpen = info.othersFolded } label: {
                        HStack(spacing: 4) {
                            Heading(words: "Others on This Mac", count: info.others.count).padding(.leading, 4)
                            Image(systemName: info.othersFolded ? "chevron.right" : "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Look.Token.ink3.ui)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore).accessibilityLabel("Others on This Mac, \(info.others.count)")
                    .accessibilityValue(info.othersFolded ? "Folded" : "Open")
                }
                Spacer(minLength: 0)
                Button(info.looking ? "Looking…" : "Look Again", action: info.lookAgain).buttonStyle(.plain).disabled(info.looking)
                    .font(Look.font(.ui, size: 12, weight: .medium).ui).foregroundStyle((info.looking ? Look.Token.ink3 : .ink2).ui).padding(.trailing, 6)
            }
            .frame(minHeight: 24)
            if let said = info.said {
                Text(said).font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink2.ui).padding(.horizontal, 4).padding(.top, -2)
            }
            if !info.others.isEmpty, !info.othersFolded {
                ForEach(info.groups, id: \.folder) { group in
                    Text(group.folder.map { Words.path($0, home: home) } ?? "Folder not known").font(Look.font(.code, size: 11, weight: .medium).ui)
                        .foregroundStyle(Look.Token.ink2.ui).lineLimit(1).truncationMode(.head).padding(EdgeInsets(top: 4, leading: 4, bottom: 1, trailing: 4))
                    VStack(spacing: 1) { ForEach(group.rows, id: \.id) { row($0, out: true) } }
                }
                Text("something reads them. It never changes them.").font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui).padding(.horizontal, 4)
            }
        }
    }

    /// An agent's row. Its program goes under its title when it has a title of its own; its folder, but under Others,
    /// whose heading says it. One only seen says nothing it cannot prove.
    private func row(_ reading: AgentReading, out: Bool) -> some View {
        let folder = out ? nil : reading.folder.map { Words.path($0, home: home) }
        let under = [reading.named ? reading.program : nil, folder].compactMap { $0 }.joined(separator: " · ")
        let helpers = reading.agent.subagents?.filter { $0.status == "running" }.count ?? 0
        return AgentRow(info: info, id: reading.id, title: reading.title, helpers: helpers, word: reading.word, under: under, tag: reading.tag,
                        ended: reading.phase == .ended, fresh: info.fresh.contains(reading.key), motion: motion) {
            MiniEyes(state: reading.eyes).frame(width: 18, height: 18).accessibilityHidden(true)
        } details: {
            controlled(reading)
        }
        .id(reading.key)
    }

    /// What an opened row says, and what the person can change of an agent something launched: the chips, which say what
    /// its facts would, its own commands, and Continue in Terminal.
    @ViewBuilder private func controlled(_ reading: AgentReading) -> some View {
        let agent = reading.agent, live = agent.origin == "launched" && agent.alive != false && agent.can.send
        VStack(alignment: .leading, spacing: 9) {
            OpenedAgent(lines: live ? reading.opened.filter { if case .fact = $0 { false } else { true } } : reading.opened)
            if live {
                RowChips(agent: { [info] in info.shown.first { $0.id == agent.id }?.agent ?? agent }) { info.set(agent, model: $0, mode: $1, effort: $2) }
                commands(agent)
            }
            if info.terminalWords(reading) != nil {
                let busy = agent.alive != false && ["working", "waiting"].contains(agent.state), moving = info.moving.contains(agent.id)
                Button { info.continueInTerminal(reading) } label: {
                    Label("Continue in Terminal", systemImage: "terminal").font(Look.font(.ui, size: 12.5, weight: .medium).ui).frame(maxWidth: .infinity)
                }
                .buttonStyle(Secondary(height: 30)).disabled(busy || moving)
                .help(moving ? "It is moving to Terminal." : busy ? "It can continue in Terminal once this turn ends." : "something stops this agent, and Terminal continues its conversation.")
            }
        }
    }

    /// The agent's own commands, as it lists them.
    @ViewBuilder private func commands(_ agent: Agent) -> some View {
        if let list = agent.commands, !list.isEmpty {
            HStack(spacing: 8) {
                Text("Command").font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink2.ui)
                Spacer(minLength: 0)
                Menu("Choose…") { ForEach(list, id: \.value) { option in Button(option.label) { info.command(option.value, to: agent) } } }
                    .menuStyle(.borderlessButton).fixedSize().font(Look.font(.ui, size: 12).ui).accessibilityLabel("Command")
            }
        }
    }

    /// A part of the tab, above a line.
    private func section(top: CGFloat = 13, @ViewBuilder _ content: () -> some View) -> some View {
        content().padding(EdgeInsets(top: top, leading: 12, bottom: 13, trailing: 12)).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }
    }
}

/// A heading in small capitals, its count after it: the tab's sections and Info's parts.
struct Heading: View {
    let words: String
    var count: Int? = nil

    var body: some View {
        Text(words.uppercased() + (count.map { " · \($0)" } ?? "")).font(Look.font(.ui, size: 10.5, weight: .semibold).ui).kerning(0.525)
            .foregroundStyle(Look.Token.ink3.ui).accessibilityAddTraits(.isHeader)
            .accessibilityLabel(words + (count.map { ", \($0)" } ?? ""))
    }
}

/// One row, in every section: eyes, title and state word, under them its program and its tag. A click opens it in place,
/// one at a time; found by Look Again, it glows softly for a moment.
private struct AgentRow<Mark: View, Details: View>: View {
    @Bindable var info: Info
    let id: String, title: String
    var helpers = 0
    let word: String, under: String, tag: String?
    var ended = false, fresh = false, motion = Look.Motion.calm
    @ViewBuilder let mark: Mark
    @ViewBuilder let details: Details

    var body: some View {
        let opened = info.opened == id, shape = RoundedRectangle(cornerRadius: 10)
        VStack(alignment: .leading, spacing: 0) {
            Button { info.opened = opened ? nil : id } label: { head(opened) }
                .buttonStyle(.plain)
                .onHover { info.hovered = $0 ? id : info.hovered == id ? nil : info.hovered }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(([title, word, under, tag].compactMap { $0 }.filter { !$0.isEmpty } + (helpers > 0 ? [helpersWords] : [])).joined(separator: ", "))
                .accessibilityValue(opened ? "Opened" : "Closed")
            if opened {
                Rectangle().fill(Look.Token.line.ui).frame(height: 1)
                details.padding(EdgeInsets(top: 7, leading: 8, bottom: 9, trailing: 8)).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background { shape.fill((opened ? Look.Token.bg2 : fresh ? .sel : .bg).ui.opacity(opened || fresh ? 1 : 0)) }
        .overlay { if opened { shape.strokeBorder(Look.Token.line.ui) } }
        .animation(fresh || Look.motion(motion) == .reduced ? nil : .easeOut(duration: 1.8), value: fresh)
    }

    private var helpersWords: String { "+\(helpers) helper\(helpers == 1 ? "" : "s")" }

    private func head(_ opened: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            mark.frame(width: 22, height: 20).opacity(ended ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(title).font(Look.font(.ui, size: 13, weight: .semibold).ui).foregroundStyle(Look.Token.ink.ui).lineLimit(2)
                        if helpers > 0 { Text(helpersWords).font(Look.font(.ui, size: 11).ui).foregroundStyle(Look.Token.ink3.ui).fixedSize() }
                    }
                    Spacer(minLength: 0)
                    Text(word).font(Look.font(.ui, size: 11.5).ui).foregroundStyle(Look.Token.ink2.ui).fixedSize()
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(under).font(Look.font(.ui, size: 11).ui).foregroundStyle(Look.Token.ink3.ui).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    if let tag { Text(tag).font(Look.font(.ui, size: 11).ui).foregroundStyle(Look.Token.ink2.ui).fixedSize() }
                }
            }
        }
        .padding(EdgeInsets(top: 6, leading: 2, bottom: 7, trailing: 6)).contentShape(Rectangle())
        .background { if info.hovered == id, !opened { RoundedRectangle(cornerRadius: 9).fill(Look.Token.hover.ui) } }
    }
}

extension Presence {
    /// An assistant's word on a row: its state's, but while it is stuck or waking, where the card's says more.
    var rowWord: String { stuck == nil && now != .waking ? state.word : word }
    /// Whether it runs in something: not asleep, gone or quit.
    var runs: Bool { state != .sleep && ![.missing, .crashed].contains(stuck) }
}

extension AgentReading {
    /// A line of an opened row: one fact, or a sentence.
    enum Line: Hashable { case fact(String, String), plain(String) }

    /// What an opened row adds, by where the agent stands, dropping what its line says: why it stopped when it says, then
    /// what it runs with or where to find it. What acts on an agent is AgentsPanel's.
    var opened: [Line] {
        let error = [agent.error.map { Line.plain($0.message) }].compactMap { $0 }
        let program = Registry.app.agent(agent.kind)
        let never = program?.neverAsks == true ? "Never asks, by design." : program?.asksNothingByDefault == true ? "Never asks by default." : nil
        func said(_ value: String?, _ list: [Option]?) -> String? { list?.first { $0.value == value }?.label ?? value }
        switch phase {
        case .here:
            let model = [said(agent.model, agent.options.model), said(agent.effort, agent.options.effort)].compactMap { $0 }.joined(separator: " · ")
            return error + (model.isEmpty ? [] : [.fact("Model", model)]) + [.fact("On Its Own", never ?? said(agent.mode, agent.options.mode) ?? "Its own settings")]
        case .away:
            return error + [.fact("On Its Own", never ?? "Its own settings"), .plain("It runs \(tag.map { "in " + $0.dropFirst(3) } ?? "outside something"). Answer it there.")]
        case .asleep: return error + [.plain("Its conversation is closed.")]
        // The state holds the proven reason: something may not be able to continue what the program itself could.
        case .ended: return error + [.plain(agent.because["resume"] ?? "\(self.program) can’t resume this conversation.")]
        // Only a process proves it runs: a conversation whose holder is unknown may have ended.
        case .seen: return error + [.plain(agent.thread == nil ? "something sees it running, not what it does. It doesn’t guess." : "something can’t tell whether it still runs. It doesn’t guess.")]
        }
    }
}

/// The lines of an opened row: a sentence, or a fact with its name in a narrow column.
private struct OpenedAgent: View {
    let lines: [AgentReading.Line]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(lines, id: \.self) { line in
                switch line {
                case .plain(let words):
                    Text(words).font(Look.font(.ui, size: 12).ui).lineSpacing(2).foregroundStyle(Look.Token.ink2.ui).fixedSize(horizontal: false, vertical: true)
                case .fact(let key, let value):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(key).font(Look.font(.ui, size: 11.5).ui).foregroundStyle(Look.Token.ink3.ui).frame(width: 64, alignment: .leading)
                        Text(value).font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink.ui).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
