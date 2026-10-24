// The build ladder: Plan · Write · Check read from crafted items, Claude Code's (something's lent tools) and pi's
// (`something check` in its shell), a check that fails then passes, the question it asks and what Stop leaves; then,
// through the fake claude, Stop mid-Write and leaving New Space keeping the words, and the build's question answered
// on the page while its permission, and any space's question, still go to the panel (SP8).
import Foundation
import SomethingAgents
import SomethingCore
import Testing
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-ladder-")) struct LadderTests {
    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static let room = "/Users/example/something/spaces/waiting-room.html"

    /// A tool item `id` of `name` running `text`, and when something saw it begin (and end, at `ended`).
    func tool(_ id: String, _ name: String, _ text: String, _ status: String = "done") -> Item {
        Item(id: id, kind: "tool", author: "agent", text: text, at: "2026-10-23T16:20:00Z", tool: Tool(name: name, status: status))
    }

    func seen(_ times: [String: TimeInterval]) -> [String: Date] { times.mapValues { LadderTests.start + $0 } }

    @Test func claudeWithTheLentTools() {
        let say = Item(id: "m", kind: "message", author: "agent", text: "I’ll make “Waiting room”: one card per agent.\n\nMore.", at: "2026-10-23T16:20:00Z")
        var items = [tool("g", "something_guide", "something guide"), say, tool("n", "something_new", "something new waiting-room"),
                     tool("w", "Write", Self.room, "running")]
        var times = seen(["g": 0.2, "m": 0.4, "n": 0.9, "w": 1.0])
        var ladder = Ladder.read(items, seen: times, from: Self.start)
        #expect(ladder.steps.map(\.mark) == [.done, .now, .later] && ladder.eyes == .think)
        #expect(ladder.say == "I’ll make “Waiting room”: one card per agent." && ladder.wrote == "waiting-room.html" && !ladder.ran)
        #expect(Ladder.took(ladder.steps[0], now: Self.start + 9) == "0.9 s" && Ladder.took(ladder.steps[1], now: Self.start + 6.4) == "5.5 s")
        #expect(Ladder.took(ladder.steps[2], now: Self.start + 9) == nil && ladder.steps[1].file == "waiting-room.html")

        // The lent check reports a page with problems as done: it says only that it checked.
        items[3].tool?.status = "done"
        items.append(tool("c", "something_check", "something check waiting-room"))
        times.merge(seen(["c": 2.5, "c/done": 3.3])) { $1 }
        ladder = Ladder.read(items, seen: times, from: Self.start)
        #expect(ladder.steps.map(\.mark) == [.done, .done, .done] && ladder.eyes == .done && ladder.done)
        #expect(ladder.steps[2].note == "Checked" && Ladder.took(ladder.steps[1], now: Self.start) == "1.6 s")
        #expect(Ladder.took(ladder.steps[2], now: Self.start + 30) == "0.8 s")

        // An edit after the check fixes what it found; a second check, then its end.
        items.append(tool("e", "Edit", Self.room))
        ladder = Ladder.read(items, seen: times, from: Self.start)
        #expect(ladder.steps[2].mark == .now && ladder.steps[2].note == "Found problems · Fixing them…")
        items.append(tool("c2", "something_check", "something check waiting-room", "running"))
        #expect(Ladder.read(items, seen: times, from: Self.start).steps[2].note == "Checking again…")
        items[items.count - 1].tool?.status = "done"
        times.merge(seen(["c2/done": 5.9])) { $1 }
        ladder = Ladder.read(items, seen: times, from: Self.start)
        #expect(ladder.steps[2].mark == .done && ladder.steps[2].note == "Checked again after 1 fix")
        #expect(Ladder.took(ladder.steps[2], now: Self.start) == "3.4 s")
    }

    /// pi runs `something check` in its shell: its exit code says whether the page passed.
    @Test func piWithTheCheckInItsShell() {
        var items = [tool("g", "bash", "something guide --print"), tool("w", "write", Self.room), tool("c", "bash", "something check waiting-room", "failed")]
        let times = seen(["w": 0.9, "c": 2.5, "f": 4, "c2": 5, "c2/done": 5.9])
        var ladder = Ladder.read(items, seen: times, from: Self.start)
        #expect(ladder.steps.map(\.mark) == [.done, .done, .failed] && ladder.steps[2].note == "Found problems")
        items.append(tool("f", "edit", Self.room, "running"))
        #expect(Ladder.read(items, seen: times, from: Self.start).steps[2].note == "Found problems · Fixing them…")
        items[3].tool?.status = "done"
        items.append(tool("c2", "bash", "something check waiting-room", "running"))
        ladder = Ladder.read(items, seen: times, from: Self.start)
        #expect(ladder.steps[2].mark == .now && ladder.steps[2].note == "Checking again…")
        items[4].tool?.status = "done"
        ladder = Ladder.read(items, seen: times, from: Self.start)
        #expect(ladder.steps[2].mark == .done && ladder.steps[2].note == "Passed after 1 fix" && Ladder.took(ladder.steps[2], now: Self.start) == "3.4 s")
        // A check with no fix before it passed at once; a chained command is no check, and may have written anything.
        let once = Ladder.read([tool("w", "write", Self.room), tool("c", "bash", "something check waiting-room")], seen: times, from: Self.start)
        #expect(once.steps[2].note == "Passed, no errors")
        let chained = Ladder.read([tool("x", "bash", "something check waiting-room && rm -rf x")], seen: [:], from: Self.start)
        #expect(chained.steps.map(\.mark) == [.now, .later, .later] && chained.ran)
    }

    /// The question waits on the first step not done, says what the agent asks, and offers its labels.
    @Test func aQuestionWaitsOnTheStepItInterrupts() {
        let question = Question(header: "Layout", text: "Before I write it: which way should it read?", options: ["One card per agent", "A single list, oldest first"], multiple: false)
        let ladder = Ladder.read([tool("g", "bash", "something guide --print")], seen: [:], from: Self.start, asked: question, askedAt: Self.start + 0.9)
        #expect(ladder.steps.map(\.mark) == [.done, .waits, .later] && ladder.steps[1].note == "Waits for your answer")
        #expect(ladder.say == question.text && ladder.choices == question.options && ladder.eyes == .wait)
        #expect(Ladder.took(ladder.steps[0], now: Self.start + 5) == "0.9 s" && Ladder.took(ladder.steps[1], now: Self.start + 5) == nil)
    }

    /// Stop says what stays on disk: the page unchecked, what a command changed, or nothing.
    @Test func stopSaysWhatStaysOnDisk() {
        let writing = Ladder.read([tool("w", "Write", Self.room, "running")], seen: seen(["w": 1]), from: Self.start).halted()
        #expect(writing.steps.map(\.mark) == [.done, .off, .off] && writing.stopped && writing.eyes == .sleep)
        #expect(writing.say == "Stopped. waiting-room.html stays in your spaces folder, unchecked." && writing.left == "Stopped building · waiting-room.html stays unchecked")
        let ran = Ladder.read([tool("b", "Bash", "npm install")], seen: [:], from: Self.start).halted()
        #expect(ran.say == "Stopped. What it changed stays in your spaces folder." && ran.steps.map(\.mark) == [.off, .off, .off])
        let nothing = Ladder.read([], seen: [:], from: Self.start).halted()
        #expect(nothing.say == "Stopped before writing. Nothing was saved." && nothing.left == "Stopped building · nothing was saved")
    }

    // MARK: Through the fake claude

    func assistant(_ mode: String = "") async throws -> (Home, AssistantModel) {
        let (home, model) = try AssistantTests().assistant(prefix: "something-ladder-")
        try FileManager.default.createDirectory(at: home.root.appendingPathComponent("out"), withIntermediateDirectories: true)
        try mode.write(to: home.root.appendingPathComponent("out/ladder"), atomically: true, encoding: .utf8)
        await AssistantTests().look(model)
        return (home, model)
    }

    /// Stop mid-Write: the turn is interrupted, the ladder stays saying what stays on disk, the sentence is back in the
    /// field, and Build Again sends it.
    @Test func stopMidWriteKeepsTheWords() async throws {
        let (home, model) = try await assistant()
        model.send("Who is waiting for me")
        #expect(await wait(until: { model.ladder?.steps[1].mark == .now }))
        #expect(model.ladder?.say == "I’ll make “Waiting room”: one card per agent that waits for you, oldest first." && model.draft.isEmpty)
        model.nudge()
        #expect(model.nudged && model.building, "Esc only says how to stop")
        model.stop()
        #expect(!model.building && !model.nudged && model.draft == "Who is waiting for me" && model.halted?.stopped == true)
        #expect(model.ladder?.say == "Stopped. waiting-room.html stays in your spaces folder, unchecked.")
        #expect(await wait(until: { !model.working && AssistantTests().input(home).contains { $0.contains("\"subtype\":\"interrupt\"") } }))
        #expect(model.ladder?.stopped == true, "the stopped ladder stays")
        model.place = .space(title: "My agents", name: "agents", page: "/Users/example/something/spaces/agents.html")
        model.place = .blank
        #expect(model.ladder == nil && model.draft == "Who is waiting for me", "leaving puts the stopped ladder away, not the words")
        model.send()
        #expect(model.building && model.halted == nil && model.ladder?.stopped == false && model.draft.isEmpty)
        await AssistantTests().finish(home, model)
    }

    /// Leaving New Space mid-build stops it, keeps the words in its field and says so; no ladder waits on return.
    @Test func leavingNewSpaceStopsTheBuild() async throws {
        let (home, model) = try await assistant()
        var told: [String] = []
        model.told = { told.append($0) }
        model.draft = "Half written"
        model.send("Who is waiting for me")
        #expect(await wait(until: { model.ladder?.steps[1].mark == .now }))
        model.place = .space(title: "My agents", name: "agents", page: "/Users/example/something/spaces/agents.html")
        #expect(!model.building && told == ["Stopped building · waiting-room.html stays unchecked"])
        model.place = .blank
        #expect(model.ladder == nil && model.draft == "Who is waiting for me\nHalf written")
        await AssistantTests().finish(home, model)
    }

    /// SP8: the build's question is answered on the page and never queued for the panel; the answer reaches the agent,
    /// which goes on writing.
    @Test func theBuildsQuestionIsAnsweredInline() async throws {
        let (home, model) = try await assistant("ask")
        let panels = Panels(source: model.engine, shows: false), dock = FakeDock(), chip = Counter()
        panels.inline = { [weak model] in model?.answersInline($0) == true }
        panels.attention = Attention(dock: dock, notifier: FakeNotifier())
        panels.counted = { chip.value = $0 }
        model.engine.changed = { [weak model] in
            panels.refresh()
            model?.refresh()
        }
        model.send("Who is waiting for me")
        #expect(await wait(until: { model.asked != nil }))
        panels.refresh()
        #expect(model.engine.state.requests.count == 1 && panels.queue.waiting.isEmpty && panels.panel == nil)
        // In another app the blocked build still bounces the Dock once, and the badge and the chip count it.
        #expect(dock.badge == "1" && dock.bounces == 1 && chip.value == 1)
        #expect(model.ladder?.choices == ["One card per agent", "A single list, oldest first"] && model.ladder?.steps[1].mark == .waits)
        model.answer(0)
        #expect(await wait(until: { model.ladder?.steps[1].mark == .now && model.ladder?.say == "One card per agent. Writing it now." }))
        #expect(AssistantTests().input(home).contains { $0.contains("\"answers\"") && $0.contains("One card per agent") })
        #expect(panels.panel == nil && model.engine.state.requests.isEmpty)
        await AssistantTests().finish(home, model)
    }

    /// The negatives: a permission of the same build still opens the panel, and so does a question asked in a space,
    /// which never shows on New Space.
    @Test func permissionsAndOtherQuestionsStillGoToThePanel() async throws {
        let (home, model) = try await assistant("ask permission")
        let panels = Panels(source: model.engine, shows: false)
        panels.inline = { [weak model] in model?.answersInline($0) == true }
        model.send("Who is waiting for me")
        #expect(await wait(until: { model.engine.state.requests.count == 2 && model.asked != nil }))
        panels.refresh()
        #expect(panels.queue.waiting.map(\.kind) == ["permission"] && panels.panel?.request?.tool == "Bash")
        await AssistantTests().finish(home, model)

        let (other, inSpace) = try await assistant("ask")
        let others = Panels(source: inSpace.engine, shows: false)
        others.inline = { [weak inSpace] in inSpace?.answersInline($0) == true }
        inSpace.place = .space(title: "My agents", name: "agents", page: "/Users/example/something/spaces/agents.html")
        inSpace.send("Who is waiting for me")
        #expect(await wait(until: { inSpace.engine.state.requests.count == 1 }))
        others.refresh()
        #expect(inSpace.asked == nil && !inSpace.building && others.queue.waiting.map(\.kind) == ["question"] && others.panel != nil)
        await AssistantTests().finish(other, inSpace)
    }

    /// A digit answers the build's question only when typed alone while no text is edited.
    @Test func onlyABareDigitOutsideTheFieldsAnswers() {
        #expect(Ladder.choice("1", modifiers: [], editing: false) == 0 && Ladder.choice("9", modifiers: [.shift], editing: false) == 8)
        #expect(Ladder.choice("1", modifiers: [], editing: true) == nil, "a digit typed in Go to stays there")
        #expect(Ladder.choice("1", modifiers: [.command], editing: false) == nil && Ladder.choice("0", modifiers: [], editing: false) == nil)
        #expect(Ladder.choice("a", modifiers: [], editing: false) == nil && Ladder.choice(nil, modifiers: [], editing: false) == nil)
    }
}

/// What the toolbar's chip was last told.
final class Counter { var value = 0 }
