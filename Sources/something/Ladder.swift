// The build's ladder: what the assistant does with the words sent from New Space, read from its build's turn as three
// steps, Plan · Write · Check, each with its time and its real lines. The words stay true to what agents report, tools
// and their end, never what a page holds or what they might be doing: "Read the guide" is its tool, "Named it" the first
// page written, "Planned" the agent's own first words before writing, "Wrote" a write that ended and the file's size on
// disk. Write begins with the first file written, Check with the first `something check`; a check followed by a write
// found problems, which the writes after it fix; a check passed only when its command says so (the lent tool reports a
// page with problems as done, so it says "Checked"). A question the agent asks while it builds is answered on the
// build's page (keys 1 to 9 while no text is edited, Ladder.choice), while its permissions still go to the panel
// (AssistantModel.inlineQuestion). The times are when something saw each step: agents stamp theirs to the second. Its
// progress fills the ring of the building space's row in the sidebar.
import AppKit
import SomethingAgents
import SomethingCore
import SwiftUI

struct Ladder: Equatable {
    enum Mark { case later, now, done, waits, failed }

    /// One thing observed in a step: under way, done or failed.
    struct Line: Equatable {
        var text: String, mark = Mark.done
    }

    struct Step: Equatable {
        let name: String
        var mark = Mark.later, from: Date?, to: Date?
        /// What the step is for, said until it has lines.
        var note: String, lines: [Line] = []
    }

    var steps: [Step]
    /// The question the agent asks; nil while it asks none.
    var say: String?
    var eyes: Sign.State
    /// The labels of the question asked, in its order.
    var choices: [String] = []
    /// The page written, by its file's name; and whether it ran a command, which may have written anything.
    var wrote: String?, ran = false

    var done: Bool { steps.allSatisfy { $0.mark == .done } }

    /// How far the build is, for its row's ring: a third per step done, half of one for the step under way.
    var progress: Double {
        let done = steps.filter { $0.mark == .done }.count, under = steps.contains { [.now, .waits].contains($0.mark) }
        return min(1, (Double(done) + (under ? 0.5 : 0)) / Double(steps.count))
    }

    /// The ladder of a build begun at `start` whose turn holds `items`, the times taken from `seen` (when something
    /// saw an item, or `<id>/<status>` its tool's end) or else the item's own; `asked` is the question waiting since
    /// `askedAt`; `size` gives the bytes of a file written, by its name, when it can be read.
    static func read(_ items: [Item], seen: [String: Date], from start: Date, asked: Question? = nil, askedAt: Date? = nil,
                     size: (String) -> Int? = { _ in nil }) -> Ladder {
        func at(_ item: Item, _ status: String? = nil) -> Date? {
            seen[status.map { "\(item.id)/\($0)" } ?? item.id] ?? seen[item.id] ?? iso8601.date(from: item.at)
        }
        let tools = items.filter { $0.kind == "tool" && $0.decision?.outcome != "denied" }
        let writes = tools.indices.filter { writing(tools[$0]) }
        let checks = tools.indices.filter { Presence.Step.of(tools[$0]) == .check && $0 > (writes.first ?? -1) }
        let files = writes.compactMap { file(tools[$0]) }
        let page = files.first { $0.hasSuffix(".html") } ?? files.first
        var plan = Step(name: "Plan", from: start, note: "Reads the guide, then plans the space")
        var write = Step(name: "Write", note: "Writes the space")
        var check = Step(name: "Check", note: "Opens it, reads it, looks for errors")
        plan.lines = planned(items, tools, page: page)
        write.lines = written(tools, before: checks.first ?? tools.endIndex, size: size)
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
            default: (check.mark, check.note) = (.now, fixes > 0 ? "Checking again…" : "Checking, locked off the network")
            }
            check.lines = [Line(text: check.note, mark: check.mark)]
        }
        var ladder = Ladder(steps: [plan, write, check], eyes: .think, wrote: page)
        ladder.ran = tools.contains { Presence.Step.of($0) == .command && !writing($0) }
        if let asked, let waiting = ladder.steps.firstIndex(where: { $0.mark != .done }) {
            (ladder.steps[waiting].mark, ladder.steps[waiting].note) = (.waits, "Waits for your answer")
            ladder.steps[waiting].lines.append(Line(text: "Waits for your answer", mark: .waits))
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

    /// Plan's lines: the guide read, the page named, and the agent's first words before it wrote anything.
    private static func planned(_ items: [Item], _ tools: [Item], page: String?) -> [Line] {
        var lines: [Line] = []
        switch tools.first(where: { Presence.Step.of($0) == .guide })?.tool?.status {
        case "running": lines.append(Line(text: "Reading the guide", mark: .now))
        case "done": lines.append(Line(text: "Read the guide"))
        default: break
        }
        if let page, page.hasSuffix(".html") { lines.append(Line(text: "Named it \(page.dropLast(5))")) }
        let before = items.prefix { !($0.kind == "tool" && writing($0)) }
        if let words = before.first(where: { $0.kind == "message" && $0.author == "agent" })?.text.components(separatedBy: "\n\n").first?
            .trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty {
            lines.append(Line(text: "Planned: \(words)"))
        }
        return lines
    }

    /// Write's lines: one per file written before the check `before`, by what its last write says; a failed write or a
    /// status no agent told says nothing.
    private static func written(_ tools: [Item], before: Int, size: (String) -> Int?) -> [Line] {
        var files: [String] = [], status: [String: String] = [:]
        for tool in tools[..<before] where writing(tool) {
            guard let name = file(tool) else { continue }
            if status[name] == nil { files.append(name) }
            status[name] = tool.tool?.status
        }
        return files.compactMap { name in
            switch status[name] {
            case "running": Line(text: "Writing \(name)", mark: .now)
            case "done": Line(text: "Wrote \(name)" + (size(name).map { " · \(max(1, ($0 + 512) / 1024)) KB" } ?? ""))
            default: nil
            }
        }
    }

    /// This ladder with its page's `title`, once the space is listed, in place of its file's name.
    func titled(_ title: String?) -> Ladder {
        guard let title, let page = wrote, page.hasSuffix(".html") else { return self }
        var ladder = self
        ladder.steps[0].lines = steps[0].lines.map { $0.text == "Named it \(page.dropLast(5))" ? Line(text: "Named it \(title)") : $0 }
        return ladder
    }

    /// What a Stop leaves, as the toast says it.
    var stoppedWords: String {
        if let wrote { return "Stopped · \(wrote) stays in your spaces folder\(steps[2].mark == .done ? "" : ", unchecked")" }
        return ran ? "Stopped · what it changed stays in your spaces folder" : "Stopped before writing · nothing was saved · your words are back"
    }

    /// The choice a key answers: a digit from 1 to 9 typed with no modifier while no text is edited, which keeps a
    /// digit typed in Go to or a sheet's field from answering the agent; nil otherwise.
    static func choice(_ characters: String?, modifiers: NSEvent.ModifierFlags, editing: Bool) -> Int? {
        guard !editing, modifiers.isDisjoint(with: [.command, .control, .option]), let digit = characters.flatMap(Int.init),
              (1...9).contains(digit) else { return nil }
        return digit - 1
    }

    /// The time a step took, or has taken by `now` while it runs; nil when it has none to say, as a step just begun.
    /// Under a tenth of a second, a step done says so rather than "0.0 s".
    static func took(_ step: Step, now: Date) -> String? {
        guard let from = step.from, [.now, .done, .failed].contains(step.mark) else { return nil }
        let seconds = max(0, (step.to ?? now).timeIntervalSince(from))
        if seconds < 0.05 { return step.mark == .now ? nil : "<0.1 s" }
        return String(format: "%.1f s", seconds)
    }
}

/// The ring a building space's row shows in place of nothing: a circle of line2 that fills with ink as the build goes.
struct BuildRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            // A closed dark ring, as the mockup's: ink over a track of ink, never a system spinner's pale one.
            Circle().stroke(Look.Token.ink.ui.opacity(0.28), lineWidth: 1.6)
            Circle().trim(from: 0, to: max(0.04, progress)).stroke(Look.Token.ink.ui.opacity(0.78), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(-90)).animation(.easeOut(duration: 0.4), value: progress)
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}
