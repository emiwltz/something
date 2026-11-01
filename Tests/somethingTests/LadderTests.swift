// The build ladder: Plan · Write · Check read from crafted items, Claude Code's (something's lent tools) and pi's
// (`something check` in its shell), a check that fails then passes, the question it asks and what Stop leaves; then,
// through the fake claude, Stop mid-Write and leaving New Space keeping the words, and the build's question answered
// on the page while its permission, and any space's question, still go to the panel (SP8), and never once stopped.
import Foundation
import SomethingAgents
import SomethingCore
import Testing
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-ladder-")) struct LadderTests {
    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static let room = "/Users/example/something/spaces/waiting-room.html"

    /// A tool item `id` of `name` running `text`, with its status; when something saw it begin and end is given by `seen`.
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
        #expect(ladder.say == nil && ladder.wrote == "waiting-room.html" && ladder.ran)
        #expect(ladder.steps[0].lines.map(\.text) == ["Read the guide", "Named it waiting-room", "Planned: I’ll make “Waiting room”: one card per agent."])
        #expect(ladder.titled("Waiting room").steps[0].lines[1].text == "Named it Waiting room")
        #expect(Ladder.took(ladder.steps[0], now: Self.start + 9) == "0.9 s" && Ladder.took(ladder.steps[1], now: Self.start + 6.4) == "5.5 s")
        #expect(Ladder.took(ladder.steps[2], now: Self.start + 9) == nil && ladder.steps[1].lines == [.init(text: "Writing waiting-room.html", mark: .now)])

        // The lent check reports a page with problems as done: it says only that it checked.
        items[3].tool?.status = "done"
        items.append(tool("c", "something_check", "something check waiting-room"))
        times.merge(seen(["c": 2.5, "c/done": 3.3])) { $1 }
        ladder = Ladder.read(items, seen: times, from: Self.start)
        #expect(ladder.steps.map(\.mark) == [.done, .done, .done] && ladder.done)
        #expect(ladder.steps[2].lines.last?.text == "Checked" && Ladder.took(ladder.steps[1], now: Self.start) == "1.6 s")
        #expect(Ladder.took(ladder.steps[2], now: Self.start + 30) == "0.8 s")

        // An edit after the check fixes what it found; a second check, then its end.
        items.append(tool("e", "Edit", Self.room))
        ladder = Ladder.read(items, seen: times, from: Self.start)
        #expect(ladder.steps[2].mark == .now && ladder.steps[2].lines.last?.text == "Found problems · Fixing them…")
        items.append(tool("c2", "something_check", "something check waiting-room", "running"))
        #expect(Ladder.read(items, seen: times, from: Self.start).steps[2].lines.last?.text == "Checking again…")
        items[items.count - 1].tool?.status = "done"
        times.merge(seen(["c2/done": 5.9])) { $1 }
        ladder = Ladder.read(items, seen: times, from: Self.start)
        #expect(ladder.steps[2].mark == .done && ladder.steps[2].lines.last?.text == "Checked again after 1 fix")
        #expect(Ladder.took(ladder.steps[2], now: Self.start) == "3.4 s")
    }

    /// pi runs `something check` in its shell: its exit code says whether the page passed.
    @Test func piWithTheCheckInItsShell() {
        var items = [tool("g", "bash", "something guide --print"), tool("w", "write", Self.room), tool("c", "bash", "something check waiting-room", "failed")]
        let times = seen(["w": 0.9, "c": 2.5, "f": 4, "c2": 5, "c2/done": 5.9])
        var ladder = Ladder.read(items, seen: times, from: Self.start)
        #expect(ladder.steps.map(\.mark) == [.done, .done, .failed] && ladder.steps[2].lines.last?.text == "Found problems")
        items.append(tool("f", "edit", Self.room, "running"))
        #expect(Ladder.read(items, seen: times, from: Self.start).steps[2].lines.last?.text == "Found problems · Fixing them…")
        items[3].tool?.status = "done"
        items.append(tool("c2", "bash", "something check waiting-room", "running"))
        ladder = Ladder.read(items, seen: times, from: Self.start)
        #expect(ladder.steps[2].mark == .now && ladder.steps[2].lines.last?.text == "Checking again…")
        items[4].tool?.status = "done"
        ladder = Ladder.read(items, seen: times, from: Self.start)
        #expect(ladder.steps[2].mark == .done && ladder.steps[2].lines.last?.text == "Passed after 1 fix" && Ladder.took(ladder.steps[2], now: Self.start) == "3.4 s")
        // A check with no fix before it passed at once; a chained command is no check, and may have written anything.
        let once = Ladder.read([tool("w", "write", Self.room), tool("c", "bash", "something check waiting-room")], seen: times, from: Self.start)
        #expect(once.steps[2].lines.last?.text == "Passed, no errors")
        let chained = Ladder.read([tool("x", "bash", "something check waiting-room && rm -rf x")], seen: [:], from: Self.start)
        #expect(chained.steps.map(\.mark) == [.now, .later, .later] && chained.ran)
    }

    /// The question waits on the first step not done, says what the agent asks, and offers its labels.
    @Test func aQuestionWaitsOnTheStepItInterrupts() {
        let question = Question(header: "Layout", text: "Before I write it: which way should it read?", options: ["One card per agent", "A single list, oldest first"], multiple: false)
        let ladder = Ladder.read([tool("g", "bash", "something guide --print")], seen: [:], from: Self.start, asked: question, askedAt: Self.start + 0.9)
        #expect(ladder.steps.map(\.mark) == [.done, .waits, .later] && ladder.steps[1].lines.last?.text == "Waits for your answer")
        #expect(ladder.say == question.text && ladder.choices == question.options && ladder.eyes == .wait)
        #expect(Ladder.took(ladder.steps[0], now: Self.start + 5) == "0.9 s" && Ladder.took(ladder.steps[1], now: Self.start + 5) == nil)
    }

    /// Stop says what stays on disk: the page unchecked, what a command changed, or nothing.
    @Test func stopSaysWhatStaysOnDisk() {
        let writing = Ladder.read([tool("w", "Write", Self.room, "running")], seen: seen(["w": 1]), from: Self.start)
        #expect(writing.stoppedWords { $0 == "waiting-room.html" } == "Stopped · waiting-room.html stays in your spaces folder, unchecked")
        #expect(writing.stoppedWords { _ in false } == "Stopped · what it changed stays in your spaces folder", "the write never reached the disk")
        let ran = Ladder.read([tool("b", "Bash", "npm install")], seen: [:], from: Self.start)
        #expect(ran.stoppedWords { _ in true } == "Stopped · what it changed stays in your spaces folder")
        let patch = Ladder.read([tool("p", "apply_patch", "one.html\ntwo.html")], seen: [:], from: Self.start)
        #expect(patch.wrote == nil && patch.stoppedWords { _ in true } == "Stopped · what it changed stays in your spaces folder", "a patch names no file")
        let nothing = "Stopped before writing · nothing was saved · your words are back"
        #expect(Ladder.read([], seen: [:], from: Self.start).stoppedWords { _ in true } == nothing)
        #expect(Ladder.read([tool("w", "Write", Self.room, "failed")], seen: [:], from: Self.start).stoppedWords { _ in false } == nothing, "a failed write left nothing")
        #expect(Ladder.read([tool("r", "Read", Self.room)], seen: [:], from: Self.start).stoppedWords { _ in true } == nothing)
    }

    /// Only what is observed: a step says what it is for until an item shows it at work; a guide under way, a write under
    /// way, the size only when the file gives one, a failed write nothing, one line per file however many edits, the
    /// fixes after a check no line of Write's, and words after the first write no plan.
    @Test func linesAreWhatWasObserved() {
        var ladder = Ladder.read([], seen: [:], from: Self.start)
        #expect(ladder.steps.allSatisfy(\.lines.isEmpty) && ladder.steps.map(\.note) == ["Reads the guide, then plans the space", "Writes the space", "Opens it, reads it, looks for errors"])
        ladder = Ladder.read([tool("g", "something_guide", "something guide", "running")], seen: [:], from: Self.start)
        #expect(ladder.steps[0].lines == [.init(text: "Reading the guide", mark: .now)])
        #expect(Ladder.read([tool("g", "something_guide", "something guide", "failed")], seen: [:], from: Self.start).steps[0].lines.isEmpty)
        let late = Item(id: "m", kind: "message", author: "agent", text: "Written.", at: "2026-10-23T16:20:00Z")
        let items = [tool("a", "Write", Self.room), tool("b", "Edit", Self.room, "running"), tool("c", "Write", "/Users/example/something/spaces/notes.md"),
                     tool("d", "Write", "/Users/example/something/spaces/gone.md", "failed"), late]
        ladder = Ladder.read(items, seen: [:], from: Self.start) { $0.hasSuffix("/notes.md") ? 14_000 : nil }
        #expect(ladder.steps[0].lines.map(\.text) == ["Named it waiting-room"])
        #expect(ladder.steps[1].lines == [.init(text: "Writing waiting-room.html", mark: .now), .init(text: "Wrote notes.md · 14 KB")])
        // A name is said of a new page whose write ended, not of one under way, failed, or there before.
        #expect(Ladder.read([tool("a", "Write", Self.room, "running")], seen: [:], from: Self.start).steps[0].lines.isEmpty)
        #expect(Ladder.read([tool("a", "Write", Self.room, "failed")], seen: [:], from: Self.start).steps[0].lines.isEmpty)
        #expect(Ladder.read([tool("a", "Write", Self.room)], seen: [:], from: Self.start, spaces: ["waiting-room"]).steps[0].lines.isEmpty)
        // The plan is what the agent last said before Plan ended, never words still arriving.
        func said(_ id: String, _ text: String) -> Item { Item(id: id, kind: "message", author: "agent", text: text, at: "2026-10-23T16:20:00Z") }
        #expect(Ladder.read([said("x", "I’ll ma")], seen: [:], from: Self.start).steps[0].lines.isEmpty)
        let plan = Ladder.read([said("x", "I’ll read the guide."), said("y", "A list by state.\n\nMore."), tool("a", "Write", Self.room, "running"), late], seen: [:], from: Self.start)
        #expect(plan.steps[0].lines == [.init(text: "Planned: A list by state.", spoken: true)])
        ladder = Ladder.read([tool("a", "Write", Self.room), tool("k", "Bash", "something check waiting-room", "running")], seen: [:], from: Self.start)
        #expect(ladder.steps[2].lines == [.init(text: "Checking, locked off the network", mark: .now)])
    }

    // MARK: Through the fake claude

    func assistant(_ mode: String = "") async throws -> (Home, AssistantModel) {
        let (home, model) = try AssistantTests().assistant(prefix: "something-ladder-")
        try FileManager.default.createDirectory(at: home.root.appendingPathComponent("out"), withIntermediateDirectories: true)
        try mode.write(to: home.root.appendingPathComponent("out/ladder"), atomically: true, encoding: .utf8)
        await AssistantTests().look(model)
        return (home, model)
    }

    /// Stop mid-Write: the turn is interrupted, a toast says what stays on disk, the field has the sentence back, what
    /// the agent had said stays away from it, and Return sends it again.
    @Test func stopMidWriteKeepsTheWords() async throws {
        let (home, model) = try await assistant()
        var noted: [String] = []
        model.noted = { noted.append($0) }
        model.send("Who is waiting for me")
        #expect(await wait(until: { model.ladder?.steps[1].mark == .now }))
        #expect(model.ladder?.steps[0].lines.last?.text == "Planned: I’ll make “Waiting room”: one card per agent that waits for you, oldest first." && model.draft.isEmpty)
        model.nudge()
        #expect(model.nudged && model.building, "Esc only says how to stop")
        model.stop()
        #expect(!model.building && !model.nudged && model.draft == "Who is waiting for me" && model.ladder == nil && model.halted === model.session && model.wantsFocus)
        #expect(noted == ["Stopped · what it changed stays in your spaces folder"], "the fake writes nothing to disk: the toast names no file")
        #expect(await wait(until: { !model.working && AssistantTests().input(home).contains { $0.contains("\"subtype\":\"interrupt\"") } }))
        #expect(BlankView.reply(in: model, since: 0) == nil, "the field comes back alone")
        model.place = .space(title: "My agents", name: "agents", page: "/Users/example/something/spaces/agents.html")
        model.place = .blank
        #expect(model.draft == "Who is waiting for me" && BlankView.reply(in: model, since: 0) == nil, "leaving and coming back keeps both")
        model.send()
        #expect(model.building && model.halted == nil && model.draft.isEmpty)
        await AssistantTests().finish(home, model)
    }

    /// Stop one build while another runs. Watching the other and coming back leaves what was stopped away from the field;
    /// when the other ends with no space, its conversation becomes New Space's and its reply shows: no reply is lost.
    @Test func aStopHidesOnlyWhatWasStopped() async throws {
        let (home, model) = try await assistant()
        model.ended = { _ = model.appeared([]) }
        model.send("Page of two: alpha")
        #expect(await wait(until: { model.builds.count == 1 && model.space(of: model.builds[0]) == "alpha" }))
        let alpha = try #require(model.watched)
        model.watch(nil)
        model.send("Page of two: beta")
        #expect(await wait(until: { model.builds.count == 2 && model.space(of: model.builds[1]) == "beta" }))
        let beta = try #require(model.watched)
        model.watch(alpha)
        model.stop()
        #expect(model.builds.map(\.id) == [beta])
        #expect(await wait(until: { !model.working }))
        let stopped = try #require(model.halted)
        model.watch(beta)
        model.watch(nil)
        #expect(model.session === stopped && BlankView.reply(in: model, since: 0) == nil)
        try Data().write(to: home.root.appendingPathComponent("out/finish-beta"))
        #expect(await wait(until: { model.builds.isEmpty && BlankView.reply(in: model, since: 0) == "beta is ready." }))
        await AssistantTests().finish(home, model)
    }

    /// `said`, the sentence as a page shows it, in each of its shapes.
    @Test func theSentenceInPlainWords() {
        let home = "/Users/example", shop = "/Users/example/code/shop"
        func said(_ level: Grant.Level, scope: Scope? = nil, start: Grant.Start? = nil, folder: LevelChoice.Folder = .none) -> String {
            LevelChoice(level: level, scope: scope, start: start, folder: folder).said(home: home)
        }
        #expect(said(.none) == "This space may not see your agents.")
        #expect(said(.watch) == "This space may watch all your agents.")
        #expect(said(.talk, scope: .folders([shop])) == "This space may talk to the agents in ~/code/shop.")
        #expect(said(.run, folder: .path(shop)) == "This space may start any agent in ~/code/shop.")
        #expect(said(.run, folder: .blank) == "This space may start any agent in a blank folder of its own.")
    }

    /// Leaving New Space mid-build stops nothing: it goes on, told nowhere, New Space shows its own field again (what
    /// was half written there kept), and the build's row brings its ladder back. A second build runs beside it, each
    /// with its own agent, and neither sleeps however low the cap of awake assistants is.
    @Test func leavingNewSpaceKeepsBuilding() async throws {
        let (home, model) = try await assistant()
        var told: [String] = []
        model.told = { told.append($0) }
        model.draft = "Half written"
        model.send("Who is waiting for me")
        #expect(await wait(until: { model.ladder?.steps[1].mark == .now }))
        let first = try #require(model.watched)
        #expect(model.building && model.sessions[.new]?.draft == "Half written" && model.space(of: model.builds[0]) == "waiting-room")
        model.place = .space(title: "My agents", name: "agents", page: "/Users/example/something/spaces/agents.html")
        #expect(!model.building && model.builds.map(\.id) == [first] && told.isEmpty && model.watched == nil)
        model.place = .blank
        #expect(model.ladder == nil && model.draft == "Half written" && !model.building)
        model.watch(first)
        #expect(model.building && model.ladder?.steps[1].mark == .now && model.ladder?.steps[0].lines.last?.text.hasPrefix("Planned: I’ll make") == true)
        // A second build, from New Space's field, while the first goes on.
        model.watch(nil)
        Preferences.at(home.places).awakeAtMost = 1
        model.send("Who is waiting for me")
        #expect(await wait(until: { model.builds.count == 2 && model.engine.assistants.count == 2 }))
        #expect(model.watched == model.builds[1].id && model.builds.map(\.session.asleep) == [false, false])
        model.tick()
        #expect(model.builds.allSatisfy { $0.session.agent?.alive != false && !$0.session.asleep }, "a building assistant never sleeps")
        await AssistantTests().finish(home, model)
    }

    /// A build that fails while the person is elsewhere: its words are back in New Space's field, the toast says so,
    /// and New Space says why, with its notice.
    @Test func aFailedBuildKeepsTheWords() async throws {
        let (home, model) = try await assistant()
        var told: [String] = []
        model.told = { told.append($0) }
        model.send("sign-in-please, a page of my plans")
        model.place = .space(title: "My agents", name: "agents", page: "/Users/example/something/spaces/agents.html")
        #expect(await wait(until: { model.builds.isEmpty }))
        #expect(told == ["Your new space didn’t build · your words are back"])
        model.place = .blank
        #expect(model.draft == "sign-in-please, a page of my plans" && !model.building && model.notice != nil)
        await AssistantTests().finish(home, model)
    }

    /// A build that ends while the person is in another space or on Templates: its space, there before (a rebuild), is
    /// found by the page it wrote, takes the build's conversation and is said ready, not opened; one that ends while
    /// New Space shows it opens, its card to open on the reply.
    @Test(arguments: ["blank", "templates", "space"]) func aBuildEndsWhereverThePersonIs(where place: String) async throws {
        let away = place != "blank"
        let (home, model) = try await assistant("fail")
        let library = Library(places: home.places, ask: FakeAsk(), share: Home.share)
        _ = try home.space("waiting-room", page(#"{"contract": 1, "title": "Waiting room", "rights": ["state", "store"]}"#, ""))
        library.relist()
        var arrived: [String] = [], opened: String?
        model.arrived = { arrived.append("\($0) · \($1)") }
        model.ended = {
            library.relist()
            opened = model.appeared(library.entries)
        }
        model.send("Who is waiting for me")
        #expect(await wait(until: { model.ladder?.done == true }))
        if place == "space" { model.place = .space(title: "My agents", name: "agents", page: "/Users/example/something/spaces/agents.html") }
        if place == "templates" { model.place = .templates }
        try Data().write(to: home.root.appendingPathComponent("out/finish"))
        #expect(await wait(until: { model.builds.isEmpty }))
        #expect(opened == (away ? nil : "waiting-room") && arrived == (away ? ["waiting-room · Waiting room"] : []))
        #expect(model.ready == (away ? ["waiting-room"] : []) && model.revealing == (away ? nil : "waiting-room"))
        let room = AssistantModel.Place.space(title: "Waiting room", name: "waiting-room", page: home.places.spaces.appendingPathComponent("waiting-room.html").path)
        #expect(model.session(for: room).rows.contains(.mine(caption: "on the blank page", text: "Who is waiting for me")))
        model.place = room
        #expect(away || (model.open && model.threadShown))
        await AssistantTests().finish(home, model)
    }

    /// Builds that end without a page, while the person is elsewhere, each give their conversation back to New Space
    /// and no reply is lost: the first takes New Space's empty one; the next takes over an idle one, its turns kept
    /// above; one ending while New Space's own still works is kept above it, which goes on. Each says so truthfully.
    @Test func buildsWithoutAPageKeepEveryReply() async throws {
        let (home, model) = try await assistant()
        var told: [String] = []
        model.told = { told.append($0) }
        model.ended = { _ = model.appeared([]) }
        for name in ["alpha", "beta", "delta"] {
            model.watch(nil)
            model.send("Page of two: \(name)")
            #expect(await wait(until: { model.builds.last.flatMap(model.space(of:)) == name }))
        }
        model.place = .space(title: "My agents", name: "agents", page: "/Users/example/something/spaces/agents.html")
        let replies = { Set((model.sessions[.new]?.rows ?? []).compactMap(\.reply)) }
        try Data().write(to: home.root.appendingPathComponent("out/finish-alpha"))
        #expect(await wait(until: { model.builds.count == 2 && replies() == ["alpha is ready."] }))
        try Data().write(to: home.root.appendingPathComponent("out/finish-beta"))
        #expect(await wait(until: { model.builds.count == 1 && replies() == ["alpha is ready.", "beta is ready."] }))
        let beta = try #require(model.sessions[.new])
        // New Space's own conversation works when the last build ends: it goes on, the build's turns kept above.
        model.place = .templates
        model.send("Page of two: gamma")
        #expect(await wait(until: { beta.agent?.state == "working" }))
        try Data().write(to: home.root.appendingPathComponent("out/finish-delta"))
        #expect(await wait(until: { model.builds.isEmpty }))
        #expect(model.sessions[.new] === beta && beta.agent?.state == "working")
        #expect(await wait(until: { replies().isSuperset(of: ["alpha is ready.", "beta is ready.", "delta is ready."]) }))
        for name in ["alpha", "beta", "delta"] {
            #expect(beta.rows.contains(.mine(caption: "on the blank page", text: "Page of two: \(name)")))
        }
        #expect(told == Array(repeating: "Your assistant answered on New Space", count: 3))
        try Data().write(to: home.root.appendingPathComponent("out/finish-gamma"))
        await AssistantTests().finish(home, model)
    }

    /// Two builds at once, each writing its own page, the second ending first, while the person is elsewhere: each is
    /// handed its own page, its grant at its own level, and its own conversation; neither ends the other's.
    @Test func twoBuildsEndInReverseOrder() async throws {
        let (home, model) = try await assistant()
        let library = Library(places: home.places, ask: FakeAsk(), share: Home.share)
        var arrived: [String] = []
        model.arrived = { name, _ in arrived.append(name) }
        model.ended = {
            library.relist()
            _ = model.appeared(library.entries)
        }
        model.chosenLevel = .watch
        model.send("Page of two: first-room")
        #expect(await wait(until: { model.builds.count == 1 && model.space(of: model.builds[0]) == "first-room" }))
        model.watch(nil)
        model.chosenLevel = .talk
        model.send("Page of two: second-room")
        #expect(await wait(until: { model.builds.count == 2 && model.space(of: model.builds[1]) == "second-room" }))
        let (first, second) = (model.builds[0].session, model.builds[1].session)
        // Both pages appear after both builds began: each is new to both.
        for (name, title) in [("first-room", "First room"), ("second-room", "Second room")] {
            _ = try home.space(name, page(#"{"contract": 1, "title": "\#(title)"}"#, ""))
        }
        model.place = .space(title: "My agents", name: "agents", page: "/Users/example/something/spaces/agents.html")
        try Data().write(to: home.root.appendingPathComponent("out/finish-second-room"))
        #expect(await wait(until: { model.builds.count == 1 }))
        #expect(arrived == ["second-room"] && model.sessions[.space("second-room")] === second && model.made == ["second-room"])
        try Data().write(to: home.root.appendingPathComponent("out/finish-first-room"))
        #expect(await wait(until: { model.builds.isEmpty }))
        #expect(arrived == ["second-room", "first-room"] && model.ready == ["first-room", "second-room"])
        #expect(model.sessions[.space("first-room")] === first && model.sessions[.space("second-room")] === second)
        let grants = try AppFile.read(home.places.grants).spaces
        #expect(grants["first-room"]?.level == .watch && grants["second-room"]?.level == .talk)
        #expect(!AssistantTests().input(home).contains { $0.contains("end_session") }, "neither build's agent was ended")
        await AssistantTests().finish(home, model)
    }

    /// A finished build said short: one line of what was made, the reply's first paragraph, the steps and the rest
    /// under Details; nothing folds while its turn goes on, nor a reply that does not answer a build.
    @Test func aBuildsReplyFoldsItsDetails() {
        let rows: [AssistantModel.Row] = [.mine(caption: "on the blank page", text: "A countdown"), .reply("Week-end is ready. Try: write your plans.\n\nIt reads the state.")]
        #expect(AssistantModel.built(rows, at: 1, ended: true) == .init(steps: 1..<1, made: nil, short: "Week-end is ready. Try: write your plans.", rest: "It reads the state."))
        #expect(AssistantModel.built(rows, at: 1, ended: false) == nil)
        #expect(AssistantModel.built([.mine(caption: "about Week-end", text: "Bigger"), rows[1]], at: 1, ended: true) == nil)
        #expect(AssistantModel.built([rows[0], .reply("One paragraph.")], at: 1, ended: true) == nil)
        let steps: [AssistantModel.Row] = [
            rows[0], .reply("I’ll make it."), .tool(failed: false, words: "Edited week-end.html", command: nil),
            .tool(failed: true, words: " · failed", command: "something check week-end"), .reply("Check found 2 problems."),
            .tool(failed: false, words: "Edited week-end.html · checked", command: nil), .reply("Week-end is ready."),
        ]
        #expect(AssistantModel.built(steps, at: 6, ended: true) == .init(steps: 1..<6, made: "Made week-end.html · checked, 0 errors", short: "Week-end is ready.", rest: nil))
        #expect(AssistantModel.built(steps, at: 4, ended: true) == nil, "an interim reply is a step")
        #expect(AssistantModel.made(steps[1..<4]) == "Made week-end.html · check found errors")
        #expect(AssistantModel.made(steps[1..<3]) == "Made week-end.html · unchecked")
    }

    /// The row's name until the page has one, and the ring's progress.
    @Test func aBuildingRowIsNamedFromItsWords() {
        #expect(AssistantModel.provisional("A countdown to Saturday, with what my agents still have to finish.") == "A countdown to Saturday…")
        #expect(AssistantModel.provisional("Who is waiting for me") == "Who is waiting for me")
        let writing = Ladder.read([tool("w", "Write", Self.room, "running")], seen: seen(["w": 1]), from: Self.start)
        #expect(writing.progress == 0.5 && Ladder.read([], seen: [:], from: Self.start).progress == 1.0 / 6)
        #expect(SidebarView.building("Week-end", 0.5) == "Week-end, building, 50 %")
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
        // A click or a digit before the choices have armed (RequestPanel.arming) answers nothing.
        let shown = try #require(model.askedShown)
        model.clock = { shown + RequestPanel.arming / 2 }
        model.answer(0)
        #expect(model.asked != nil && model.engine.state.requests.count == 1 && model.arming(now: model.clock()) == 0.5)
        model.clock = { Date() + RequestPanel.arming }
        model.answer(0)
        #expect(await wait(until: { model.ladder?.steps[1].mark == .now && model.ladder?.say == nil }))
        #expect(AssistantTests().input(home).contains { $0.contains("\"answers\"") && $0.contains("One card per agent") })
        #expect(panels.panel == nil && model.engine.state.requests.isEmpty)
        await AssistantTests().finish(home, model)
    }

    /// Stopping while the build asks: the question it withdraws later never reaches the panel. Leaving New Space stops
    /// nothing: away, the question goes to the panel.
    @Test(arguments: [false, true]) func aStoppedBuildsQuestionNeverReachesThePanel(leaving: Bool) async throws {
        let (home, model) = try await assistant("ask")
        let panels = Panels(source: model.engine, shows: false)
        panels.inline = { [weak model] in model?.answersInline($0) == true }
        var opened = false
        model.engine.changed = { [weak model] in
            panels.refresh()
            model?.refresh()
            opened = opened || panels.panel != nil
        }
        model.send("Who is waiting for me")
        #expect(await wait(until: { model.asked != nil }))
        if leaving {
            model.place = .space(title: "My agents", name: "agents", page: "/Users/example/something/spaces/agents.html")
            panels.refresh()
            #expect(model.asked == nil && panels.queue.waiting.map(\.kind) == ["question"] && model.builds.count == 1)
            return await AssistantTests().finish(home, model)
        }
        model.stop()
        panels.refresh()
        #expect(model.engine.state.requests.count == 1 && panels.queue.waiting.isEmpty && panels.panel == nil)
        #expect(await wait(until: { model.engine.state.requests.isEmpty }))
        #expect(!opened && panels.panel == nil)
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

extension AssistantModel {
    /// The ladder of the build New Space shows; nil when it shows none.
    var ladder: Ladder? { before.map(ladder) }
}
