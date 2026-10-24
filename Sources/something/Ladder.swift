// The build ladder on New Space: what the assistant does with the sentence sent there, read from its build's turn as
// three steps, Plan · Write · Check, each with its time. The words stay true to what agents report, tools and their
// end, never what a page holds: Write begins with the first file written, Check with the first `something check`; a
// check followed by a write found problems, which the writes after it fix; a check passed only when its command says
// so (the lent tool reports a page with problems as done, so it says "Checked"). Above the steps, the agent's last
// words in its own voice, or the question it asks while it builds, answered here (keys 1 to 9 while no text is edited, Ladder.choice) while its permissions
// still go to the panel (AssistantModel.inlineQuestion). Below, where it is built and Stop (⌘.), which says what stays
// on disk. The times are when something saw each step: agents stamp theirs to the second.
import AppKit
import SomethingAgents
import SomethingCore
import SwiftUI

struct Ladder: Equatable {
    enum Mark { case later, now, done, waits, failed, off }

    struct Step: Equatable {
        let name: String
        var mark = Mark.later, from: Date?, to: Date?
        var note: String, file: String? = nil
    }

    var steps: [Step]
    /// The agent's last words, the question it asks, or what the stop left; nil until it says something.
    var say: String?
    var eyes: Sign.State
    /// The labels of the question asked, in its order.
    var choices: [String] = []
    /// The page written, by its file's name; and whether it ran a command, which may have written anything.
    var wrote: String?, ran = false
    var stopped = false

    var done: Bool { steps.allSatisfy { $0.mark == .done } }

    /// The ladder of a build begun at `start` whose turn holds `items`, the times taken from `seen` (when something
    /// saw an item, or `<id>/<status>` its tool's end) or else the item's own; `asked` is the question waiting since
    /// `askedAt`.
    static func read(_ items: [Item], seen: [String: Date], from start: Date, asked: Question? = nil, askedAt: Date? = nil) -> Ladder {
        func at(_ item: Item, _ status: String? = nil) -> Date? {
            seen[status.map { "\(item.id)/\($0)" } ?? item.id] ?? seen[item.id] ?? iso8601.date(from: item.at)
        }
        let tools = items.filter { $0.kind == "tool" && $0.decision?.outcome != "denied" }
        let writes = tools.indices.filter { writing(tools[$0]) }
        let checks = tools.indices.filter { Presence.Step.of(tools[$0]) == .check && $0 > (writes.first ?? -1) }
        let files = writes.compactMap { file(tools[$0]) }
        var plan = Step(name: "Plan", from: start, note: "Reads what it needs, then plans the page")
        var write = Step(name: "Write", note: "Writes the page in your spaces folder", file: files.first { $0.hasSuffix(".html") } ?? files.first)
        var check = Step(name: "Check", note: "Opens it, reads it, looks for errors")
        plan.to = (writes.first ?? checks.first).flatMap { at(tools[$0]) } ?? askedAt
        plan.mark = plan.to == nil ? .now : .done
        if let first = writes.first {
            (write.from, write.mark) = (at(tools[first]), .now)
            if let begun = checks.first { (write.to, write.mark) = (at(tools[begun]), .done) }
        }
        if let first = checks.first, let last = checks.last {
            let item = tools[last], fixes = writes.filter { $0 > first }.count
            let after = "after \(fixes) fix\(fixes == 1 ? "" : "es")"
            let passed = item.tool?.name.hasSuffix("something_check") == true
                ? (fixes > 0 ? "Checked again \(after)" : "Checked") : (fixes > 0 ? "Passed \(after)" : "Passed, no errors")
            check.from = at(tools[first])
            switch item.tool?.status {
            case _ where writes.contains(where: { $0 > last }): (check.mark, check.note) = (.now, "Found problems · Fixing them…")
            case "failed": (check.mark, check.note) = (.failed, "Found problems")
            case "done": (check.mark, check.to, check.note) = (.done, at(item, "done"), passed)
            default: (check.mark, check.note) = (.now, fixes > 0 ? "Checking again…" : check.note)
            }
        }
        var ladder = Ladder(steps: [plan, write, check], eyes: .think, wrote: write.file)
        ladder.ran = tools.contains { Presence.Step.of($0) == .command && !writing($0) }
        ladder.say = items.last { $0.kind == "message" && $0.author == "agent" }
            .flatMap { $0.text.components(separatedBy: "\n\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        if let asked, let waiting = ladder.steps.firstIndex(where: { $0.mark != .done }) {
            (ladder.steps[waiting].mark, ladder.steps[waiting].note, ladder.steps[waiting].file) = (.waits, "Waits for your answer", nil)
            (ladder.say, ladder.choices, ladder.eyes) = (asked.text, asked.options, .wait)
        } else if ladder.done {
            ladder.eyes = .done
        }
        return ladder
    }

    /// Whether `item` writes the page: an edit, or `something new`, which makes it from a template.
    static func writing(_ item: Item) -> Bool {
        Presence.Step.of(item) == .edit || item.tool?.name.hasSuffix("something_new") == true || item.text.hasPrefix("something new ")
    }

    /// The file `item` writes, by its name: `something new waiting-room` makes waiting-room.html.
    static func file(_ item: Item) -> String? {
        guard !item.text.contains(where: \.isNewline), !item.text.isEmpty else { return nil }
        if item.text.hasPrefix("something new ") {
            return item.text.dropFirst("something new ".count).split(separator: " ").first.map { "\($0).html" }
        }
        return (item.text as NSString).lastPathComponent
    }

    /// The ladder as Stop left it: what was not done is off, and it says what stays on disk.
    func halted() -> Ladder {
        var ladder = self
        for index in ladder.steps.indices where ladder.steps[index].mark != .done { ladder.steps[index].mark = .off }
        let checked = steps[2].mark == .done
        ladder.say = wrote.map { "Stopped. \($0) stays in your spaces folder\(checked ? "" : ", unchecked")." }
            ?? (ran ? "Stopped. What it changed stays in your spaces folder." : "Stopped before writing. Nothing was saved.")
        (ladder.choices, ladder.eyes, ladder.stopped) = ([], .sleep, true)
        return ladder
    }

    /// The toast when leaving New Space stopped the build.
    var left: String {
        wrote.map { "Stopped building · \($0) stays unchecked" } ?? (ran ? "Stopped building · what it changed stays" : "Stopped building · nothing was saved")
    }

    /// The choice a key answers: a digit from 1 to 9 typed with no modifier while no text is edited, which keeps a
    /// digit typed in Go to or a sheet's field from answering the agent; nil otherwise.
    static func choice(_ characters: String?, modifiers: NSEvent.ModifierFlags, editing: Bool) -> Int? {
        guard !editing, modifiers.isDisjoint(with: [.command, .control, .option]), let digit = characters.flatMap(Int.init),
              (1...9).contains(digit) else { return nil }
        return digit - 1
    }

    /// The time a step took, or has taken by `now` while it runs; nil when it has none to say.
    static func took(_ step: Step, now: Date) -> String? {
        guard let from = step.from, [.now, .done, .failed].contains(step.mark) else { return nil }
        return String(format: "%.1f s", max(0, (step.to ?? now).timeIntervalSince(from)))
    }
}

/// The ladder as the mockup draws it under New Space's field: the agent's words, the question's choices, the three
/// steps in a card, and the foot with Stop, or Build Again once stopped.
struct LadderView: View {
    let ladder: Ladder
    @Bindable var model: AssistantModel
    let motion: Look.Motion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let say = ladder.say ?? model.presence.now.flatMap({ if case .working(let step, _) = $0 { step } else { nil } }) {
                HStack(alignment: .firstTextBaseline, spacing: 11) {
                    Image(nsImage: Sign.miniEyes(ladder.eyes, joy: ladder.eyes == .done)).renderingMode(.template)
                        .foregroundStyle(Look.Token.eyes.ui).frame(width: 16, height: 10)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    Text(AssistantCard.markdown(say)).font(Look.font(.voice, size: 17).ui).lineSpacing(5).foregroundStyle(Look.Token.ink.ui)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your assistant: \(say)")
            }
            if !ladder.choices.isEmpty { choices }
            if ladder.steps.contains(where: { $0.mark == .now }) {
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in steps(now: model.clock()) }
            } else {
                steps(now: model.clock())
            }
            foot
        }
    }

    /// The question's labels, two to a row, each answered by a click or its number.
    private var choices: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(Array(stride(from: 0, to: ladder.choices.count, by: 2)), id: \.self) { row in
                GridRow {
                    ForEach(row..<min(row + 2, ladder.choices.count), id: \.self) { choice($0) }
                }
            }
        }
    }

    /// The label `index`, its number shown, answered by a click or that key.
    private func choice(_ index: Int) -> some View {
        let label = ladder.choices[index]
        return Button { model.answer(index) } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(label).font(Look.font(.ui, size: 13, weight: .semibold).ui).foregroundStyle(Look.Token.ink.ui)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Key("\(index + 1)")
            }
            .padding(EdgeInsets(top: 11, leading: 13, bottom: 11, trailing: 12))
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Look.Token.bg2.ui, in: RoundedRectangle(cornerRadius: Look.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Look.card, style: .continuous).strokeBorder(Look.Token.line2.ui))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(index + 1)")
    }

    private func steps(now: Date) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(ladder.steps.enumerated()), id: \.offset) { index, step in
                if index > 0 { Rectangle().fill(Look.Token.line.ui).frame(height: 1).padding(.horizontal, 16) }
                row(step, now: now)
            }
        }
        .padding(.vertical, 4)
        .background(Look.Token.bg2.ui, in: RoundedRectangle(cornerRadius: Look.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Look.card, style: .continuous).strokeBorder(Look.Token.line.ui))
    }

    private func row(_ step: Ladder.Step, now: Date) -> some View {
        let lit = ![.later, .off].contains(step.mark), time = Ladder.took(step, now: now)
        return HStack(alignment: .top, spacing: 12) {
            dot(step.mark, now: now).frame(width: 16, height: 16).padding(.top, 1).frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.name).font(Look.font(.ui, size: 13, weight: .semibold).ui).foregroundStyle((lit ? Look.Token.ink : .ink3).ui)
                if let file = step.file {
                    Text(file).font(Look.font(.code, size: 11.5).ui).foregroundStyle(Look.Token.ink.ui)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Look.Token.hover.ui, in: RoundedRectangle(cornerRadius: 5))
                } else {
                    Text(step.note).font(Look.font(.ui, size: 12).ui)
                        .foregroundStyle((step.mark == .failed ? Look.Token.bad : [.now, .waits].contains(step.mark) ? .ink2 : .ink3).ui)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(time ?? "").font(Look.font(.ui, size: 11.5).ui).monospacedDigit()
                .foregroundStyle((step.mark == .failed ? Look.Token.bad : step.mark == .now ? .ink2 : .ink3).ui)
                .frame(minWidth: 42, alignment: .trailing).padding(.top, 1)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .opacity(step.mark == .off ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([step.name, Self.word(step.mark), step.file ?? step.note, time].compactMap { $0 }.joined(separator: ", "))
    }

    /// The step's mark: a ring to come, an arc turning smoothly once each 0.9 s now, a filled tick done, a dot
    /// pulsing while it waits, "!" failed. Reduced motion keeps the arc on top and the dot still.
    @ViewBuilder private func dot(_ mark: Ladder.Mark, now: Date) -> some View {
        let moves = motion != .reduced
        switch mark {
        case .later, .off: Circle().strokeBorder((mark == .off ? Look.Token.line : .line2).ui, lineWidth: 1.5)
        case .now:
            ZStack {
                Circle().strokeBorder(Look.Token.line2.ui, lineWidth: 1.5)
                Circle().inset(by: 0.75).trim(from: 0, to: 0.25).stroke(Look.Token.ink.ui, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .keyframeAnimator(initialValue: -135.0, repeating: moves) { arc, angle in arc.rotationEffect(.degrees(angle)) } keyframes: { _ in
                        LinearKeyframe(225.0, duration: 0.9)
                    }
            }
        case .done:
            Circle().fill(Look.Token.ink.ui)
                .overlay(Image(systemName: "checkmark").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(Look.Token.bg2.ui))
        case .waits:
            Circle().strokeBorder(Look.Token.ink.ui, lineWidth: 1.5).overlay(
                Circle().fill(Look.Token.ink.ui).frame(width: 6, height: 6)
                    .keyframeAnimator(initialValue: 1.0, repeating: moves) { inner, alpha in inner.opacity(alpha) } keyframes: { _ in
                        CubicKeyframe(0.35, duration: 0.8)
                        CubicKeyframe(1.0, duration: 0.8)
                    })
        case .failed:
            Circle().fill(Look.Token.bad.ui)
                .overlay(Text("!").font(Look.font(.ui, size: 10.5, weight: .bold).ui).foregroundStyle(.white))
        }
    }

    static func word(_ mark: Ladder.Mark) -> String {
        switch mark {
        case .later: "to come"
        case .now: "now"
        case .done: "done"
        case .waits: "waits for you"
        case .failed: "found problems"
        case .off: "stopped"
        }
    }

    /// Where it is built and Stop; once stopped, what to do next and Build Again. Nothing once all is done. Esc never
    /// throws a build away: it says here, for a moment, how to stop instead.
    private var foot: some View {
        let nudged = model.nudged && !ladder.stopped && !ladder.done
        return HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: ladder.stopped || nudged ? "info.circle" : "lock").font(.system(size: 10)).accessibilityHidden(true)
                Text(ladder.stopped ? "Change your words, or build again as it is."
                     : nudged ? "Still building. To stop, press \(Keys.shown("stop")) or Stop." : "Built on this Mac, in \(model.folder)")
                    .foregroundStyle((nudged ? Look.Token.ink : .ink3).ui)
            }
            Spacer(minLength: 0)
            if ladder.stopped {
                Button { model.send() } label: {
                    HStack(spacing: 6) { Text("Build Again"); Key("↵") }.font(Look.font(.ui, size: 12, weight: .medium).ui)
                }
                .buttonStyle(Secondary())
                .disabled(!model.canSend)
                .accessibilityLabel("Build Again")
            } else if !ladder.done {
                Button { model.stop() } label: {
                    HStack(spacing: 6) { Image(systemName: "stop").font(.system(size: 9)).accessibilityHidden(true); Text("Stop"); Key(Keys.shown("stop")) }
                        .font(Look.font(.ui, size: 12, weight: .medium).ui)
                }
                .buttonStyle(Secondary())
                .overlay(RoundedRectangle(cornerRadius: Look.control + 1, style: .continuous).strokeBorder(Look.Token.ink.ui, lineWidth: 1.5)
                    .opacity(nudged ? 1 : 0).allowsHitTesting(false))
                .help(model.presence.stopHelp)
                .accessibilityLabel("Stop")
            }
        }
        .font(Look.font(.ui, size: 11.5).ui).foregroundStyle(Look.Token.ink3.ui)
        .padding(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 2))
    }
}
