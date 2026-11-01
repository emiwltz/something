// A build's own page, what New Space shows of the build it follows: the sign, the title (the space's once it is named,
// the person's words until then), who builds and with which model, Stop; on the left their words and the sentence they
// chose, or the question the agent asks, and the ladder's steps with their real lines (Ladder.swift); on the right where
// the space will show; at the foot where it is built and that leaving stops nothing, its row bringing it back. An agent
// stuck, or waiting in a window of the Mac, is said as it is, with its notice and actions: never "Building". Esc never
// throws a build away: the foot says, for a moment, how to stop instead.
import AppKit
import SwiftUI

struct BuildView: View {
    let build: AssistantModel.Build
    @Bindable var model: AssistantModel
    let library: Library

    /// The page's widest, and the width of its content under which it takes one column, as the mockup's.
    private static let widest: CGFloat = 1080, narrow: CGFloat = 720

    var body: some View {
        GeometryReader { window in
            let inset: CGFloat = 44, wide = window.size.width - inset * 2 >= BuildView.narrow
            // The mockup's columns, 1 and 1.05 of the width left by their gap.
            let right = (min(window.size.width, BuildView.widest) - inset * 2 - 24) * 1.05 / 2.05
            let ladder = model.ladder(build), name = model.space(of: build).flatMap { library.entry($0)?.title }
            ScrollView {
                VStack(alignment: .leading, spacing: wide ? 22 : 18) {
                    head(ladder, name: name, wide: wide)
                    if wide {
                        HStack(alignment: .top, spacing: 24) {
                            left(ladder.titled(name))
                            BuildSkeleton(motion: library.preferences.motion).frame(width: right)
                        }
                        // As tall as they are: the foot takes what the page has left, never the choices.
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Group {
                            left(ladder.titled(name))
                            BuildSkeleton(motion: library.preferences.motion)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    foot(wide: wide)
                }
                .padding(wide ? EdgeInsets(top: 40, leading: inset, bottom: 32, trailing: inset) : EdgeInsets(top: 28, leading: 24, bottom: 24, trailing: 24))
                .frame(maxWidth: BuildView.widest, minHeight: window.size.height)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// The sign, the title, how the build stands and Stop. A title that is still the person's words is paler than the
    /// name the build gave it.
    private func head(_ ladder: Ladder, name: String?, wide: Bool) -> some View {
        let presence = model.presence, held = ladder.eyes != .wait && (presence.stuck != nil || presence.state == .wait)
        let state = held ? presence.state : ladder.eyes == .wait ? .listen : Sign.State.think
        return HStack(spacing: 16) {
            PageSign(state: state, side: 44, lands: false, motion: library.preferences.motion)
            VStack(alignment: .leading, spacing: 6) {
                Text(name ?? AssistantModel.provisional(build.sentence))
                    .font(Look.font(.title, size: wide ? 30 : 24, weight: .semibold).ui).kerning(wide ? -0.75 : -0.6)
                    .foregroundStyle((name == nil ? Look.Token.ink2 : .ink).ui).lineLimit(1).truncationMode(.tail)
                    .accessibilityAddTraits(.isHeader)
                // Checked, not Ready: the lent tool ends as done on a page with problems, and the turn still runs.
                let status = held ? presence.word : (ladder.eyes == .wait ? "Waits for your answer · " : ladder.done ? "Checked · " : "Building · ") + model.whoBuilds
                HStack(spacing: 8) {
                    Monogram(name: model.name)
                    Text(status).font(Look.font(.ui, size: 12.5).ui).foregroundStyle(Look.Token.ink2.ui).lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(status)
            }
            Spacer(minLength: 8)
            stop
        }
    }

    private var stop: some View {
        Button { model.stop() } label: {
            HStack(spacing: 6) { Image(systemName: "stop").font(.system(size: 9)).accessibilityHidden(true); Text("Stop"); Key(Keys.shown("stop")) }
                .font(Look.font(.ui, size: 12, weight: .medium).ui)
        }
        .buttonStyle(Secondary(height: 28, leading: 9, trailing: 10))
        .overlay(RoundedRectangle(cornerRadius: Look.control + 1, style: .continuous).strokeBorder(Look.Token.ink.ui, lineWidth: 1.5)
            .opacity(model.nudged ? 1 : 0).allowsHitTesting(false))
        .help(model.presence.stopHelp)
        .accessibilityLabel("Stop")
    }

    /// What was asked for, or the question the agent asks in its place, the steps, and what holds the agent up.
    private func left(_ ladder: Ladder) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let question = ladder.say { asked(question, ladder) } else { words }
            TimelineView(.animation(minimumInterval: 0.1, paused: !ladder.steps.contains { $0.mark == .now })) { _ in
                steps(ladder, now: model.clock())
            }
            if let notice = model.notice { NoticeView(notice: notice) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Your words").textCase(.uppercase).font(Look.font(.ui, size: 10.5, weight: .semibold).ui).kerning(0.5)
                .foregroundStyle(Look.Token.ink3.ui)
            Group {
                Text(build.sentence)
                Text(build.choice.said(home: library.places.home.path))
            }
            .font(Look.font(.ui, size: 14).ui).lineSpacing(3).foregroundStyle(Look.Token.ink.ui).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your words: \(build.sentence). \(build.choice.said(home: library.places.home.path))")
    }

    /// The agent's question in its voice, in a card with its choices when it lists them.
    @ViewBuilder private func asked(_ question: String, _ ladder: Ladder) -> some View {
        if ladder.choices.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                Image(nsImage: Sign.miniEyes(ladder.eyes)).renderingMode(.template)
                    .foregroundStyle(Look.Token.eyes.ui).frame(width: 16, height: 10)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(AssistantCard.markdown(question)).font(Look.font(.voice, size: 16.5).ui).lineSpacing(1).foregroundStyle(Look.Token.ink.ui)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your assistant: \(question)")
        } else {
            choices(question, ladder)
        }
    }

    /// The question in the agent's voice with Skip, each answer with what it means, and the person's own. Its answers
    /// take a click or their number once they have armed, which fills them from the left as Allow Once fills
    /// (PanelButton.progress).
    private func choices(_ question: String, _ ladder: Ladder) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(AssistantCard.markdown(question)).font(Look.font(.voice, size: 16.5).ui).foregroundStyle(Look.Token.ink.ui)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore).accessibilityLabel("Your assistant: \(question)")
                Button { model.skip() } label: { HStack(spacing: 6) { Text("Skip"); Key("⇥") } }
                    .buttonStyle(.plain).font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink2.ui).accessibilityLabel("Skip")
            }
            .padding(.bottom, 4)
            TimelineView(.animation(minimumInterval: 0.05, paused: model.arming(now: model.clock()) >= 1)) { _ in
                let arming = model.arming(now: model.clock())
                VStack(spacing: 8) {
                    ForEach(ladder.choices.indices, id: \.self) {
                        choice(ladder.choices[$0], ladder.details.indices.contains($0) ? ladder.details[$0] : nil, $0, arming: arming)
                    }
                }
            }
            HStack(spacing: 6) {
                TextField("", text: $model.ownAnswer, prompt: Text("Or type your answer").foregroundStyle(Look.Token.ink3.ui))
                    .textFieldStyle(.plain).font(Look.font(.ui, size: 13).ui).onSubmit { model.answerOwn() }
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(Look.Token.hover.ui, in: RoundedRectangle(cornerRadius: Look.control))
                    .accessibilityLabel("Or type your answer")
                Button("Answer") { model.answerOwn() }.buttonStyle(Secondary())
                    .disabled(model.ownAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .boxed(RoundedRectangle(cornerRadius: Look.card, style: .continuous), Look.Token.bg2.ui, ring: Look.Token.line.ui)
    }

    /// The answer `label`, what it means under it, number `index`, shown, taken by a click or that key once `arming`
    /// reaches 1.
    private func choice(_ label: String, _ detail: String?, _ index: Int, arming: Double) -> some View {
        Button { model.answer(index) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(Look.font(.ui, size: 13, weight: .semibold).ui).foregroundStyle(Look.Token.ink.ui)
                    if let detail { Text(detail).font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink2.ui) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Key("\(index + 1)")
            }
            .padding(EdgeInsets(top: 9, leading: 13, bottom: 9, trailing: 12))
            .boxed(RoundedRectangle(cornerRadius: Look.card, style: .continuous), Look.Token.bg2.ui, ring: Look.Token.line2.ui)
            .overlay(alignment: .leading) {
                if arming < 1 {
                    GeometryReader { box in Rectangle().fill(Look.Token.line.ui.opacity(0.5)).frame(width: box.size.width * arming) }
                        .clipShape(RoundedRectangle(cornerRadius: Look.card, style: .continuous)).allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(arming < 1)
        .accessibilityLabel([label, detail, "\(index + 1)"].compactMap { $0 }.joined(separator: ", "))
    }

    private func steps(_ ladder: Ladder, now: Date) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(ladder.steps.enumerated()), id: \.offset) { index, step in
                if index > 0 { Rectangle().fill(Look.Token.line.ui).frame(height: 1).padding(.horizontal, 16) }
                row(step, now: now)
            }
        }
        .padding(.vertical, 4)
        .boxed(RoundedRectangle(cornerRadius: Look.card, style: .continuous), Look.Token.bg2.ui, ring: Look.Token.line.ui)
    }

    /// A step: its mark, its name, what it did or, not done yet, what it is for, and its time. A step done with no line
    /// says nothing: nobody saw what it did.
    private func row(_ step: Ladder.Step, now: Date) -> some View {
        let lit = step.mark != .later, time = Ladder.took(step, now: now), said = step.lines.isEmpty ? step.mark == .done ? [] : [step.note] : step.lines.map(\.text)
        return HStack(alignment: .top, spacing: 12) {
            dot(step.mark, now: now).frame(width: 16, height: 16).padding(.top, 1).frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.name).font(Look.font(.ui, size: 13, weight: .semibold).ui).foregroundStyle((lit ? Look.Token.ink : .ink3).ui)
                if step.lines.isEmpty, step.mark != .done {
                    Text(step.note).font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink3.ui)
                } else {
                    VStack(alignment: .leading, spacing: 3) { ForEach(step.lines, id: \.text, content: line) }.padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(time ?? "").font(Look.font(.ui, size: 11.5).ui).monospacedDigit()
                .foregroundStyle((step.mark == .failed ? Look.Token.bad : step.mark == .now ? .ink2 : .ink3).ui)
                .frame(minWidth: 42, alignment: .trailing).padding(.top, 1)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([step.name, Self.word(step.mark)] + said + [time].compactMap { $0 }).joined(separator: ", "))
    }

    /// A line: a tick once done, the eyes while under way, a cross when it failed. A long plan keeps to three lines.
    private func line(_ line: Ladder.Line) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Group {
                switch line.mark {
                case .done: Image(systemName: "checkmark").font(.system(size: 8.5, weight: .medium)).foregroundStyle(Look.Token.ink3.ui)
                case .failed: Image(systemName: "xmark").font(.system(size: 8.5, weight: .medium)).foregroundStyle(Look.Token.bad.ui)
                default:
                    Image(nsImage: Sign.miniEyes(.think)).renderingMode(.template).foregroundStyle(Look.Token.eyes.ui)
                        .frame(width: 14, height: 9).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                }
            }
            .frame(width: 13)
            Text(BuildView.shown(line)).font(Look.font(.ui, size: 12).ui).lineLimit(3)
                .foregroundStyle((line.mark == .failed ? Look.Token.bad : line.mark == .done ? .ink2 : .ink).ui)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The step's mark: a ring to come, an arc turning smoothly once each 0.9 s now, a filled tick done, a dot
    /// pulsing while it waits, "!" failed. Reduced motion keeps the arc on top and the dot still.
    @ViewBuilder private func dot(_ mark: Ladder.Mark, now: Date) -> some View {
        let moves = Look.motion(library.preferences.motion) == .calm
        switch mark {
        case .later: Circle().strokeBorder(Look.Token.line2.ui, lineWidth: 1.5)
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

    /// `line` as drawn: only the agent's own words are Markdown, and a link in them takes nobody anywhere.
    private static func shown(_ line: Ladder.Line) -> AttributedString {
        guard line.spoken else { return AttributedString(line.text) }
        var words = AssistantCard.markdown(line.text)
        for run in words.runs where run.link != nil { words[run.range].link = nil }
        return words
    }

    private static func word(_ mark: Ladder.Mark) -> String {
        switch mark {
        case .later: "to come"
        case .now: "now"
        case .done: "done"
        case .waits: "waits for you"
        case .failed: "found problems"
        }
    }

    /// Where it is built, and that the person may leave; Esc's nudge in their place for a moment.
    private func foot(wide: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: model.nudged ? "info.circle" : "lock").font(.system(size: 10)).accessibilityHidden(true)
            Text(model.nudged ? "Still building. To stop, press \(Keys.shown("stop")) or Stop." : "Built on this Mac, in \(model.folder)")
                .foregroundStyle((model.nudged ? Look.Token.ink : .ink3).ui)
            Spacer(minLength: 8)
            // Leaving stops nothing: the row in the sidebar brings it back.
            if wide, !model.nudged { Text("You can leave: it keeps building, its row shows how far it is.").lineLimit(1) }
        }
        .font(Look.font(.ui, size: 11.5).ui).foregroundStyle(Look.Token.ink3.ui)
        .padding(.horizontal, 2)
    }
}

/// Where the space will show, in the mockup's proportions: a skeleton under a caption, never a guess at what the page
/// holds. It shimmers while building; reduced motion keeps it still.
struct BuildSkeleton: View {
    let motion: Look.Motion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "eye").font(.system(size: 10)).accessibilityHidden(true)
                Text("Your space shows here as soon as it exists")
            }
            .font(Look.font(.ui, size: 11.5).ui).foregroundStyle(Look.Token.ink3.ui).padding(.horizontal, 2)
            GeometryReader { box in
                let inner = box.size.width - 44
                VStack(alignment: .leading, spacing: 12) {
                    bar(inner * 0.34).frame(height: 14)
                    bar(inner * 0.72).frame(height: 40)
                    bar(inner * 0.46).frame(height: 12)
                    bar(inner)
                }
                .padding(22)
            }
            .aspectRatio(1040.0 / 650.0, contentMode: .fit)
            .boxed(RoundedRectangle(cornerRadius: Look.card, style: .continuous), Look.Token.bg2.ui, ring: Look.Token.line.ui)
            .accessibilityHidden(true)
        }
    }

    private func bar(_ width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Look.Token.sunk.ui).frame(width: max(0, width))
            .overlay {
                if Look.motion(motion) == .calm {
                    LinearGradient(colors: [.clear, Look.Token.hover.ui, .clear], startPoint: .leading, endPoint: .trailing)
                        .keyframeAnimator(initialValue: -1.0, repeating: true) { shine, at in shine.offset(x: at * width) } keyframes: { _ in
                            LinearKeyframe(1.0, duration: 1.6, timingCurve: .easeInOut)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

extension AssistantModel {
    /// Who works on the build shown: the agent, then its model once that has a name.
    var whoBuilds: String { ownModel || (session.model ?? agent?.model) == nil ? name : "\(name) · \(modelWords.model)" }
}
