// The questions before a build: Brief, pure, over a table of what a model may answer, each driven agent's reading
// exchange through it, and AssistantModel's reading, over the fake Claude: launched as asking everything with no lent
// tool, apart from every conversation, and giving zero questions for anything but a clean answer.
import Foundation
import SomethingAgents
import SomethingCore
import Testing
@testable import something

@Suite struct BriefTests {
    static let plain = #"[something] Questions: {"name":"week-end","questions":[{"text":"Who is it for?","options":[{"label":"Just me","about":"A page for you alone."},{"label":"The family","about":"Everyone reads it."}],"pick":1,"remember":true}]}"#
    static let question = Brief.Question(text: "Who is it for?", options: [Brief.Option(label: "Just me", about: "A page for you alone."), Brief.Option(label: "The family", about: "Everyone reads it.")],
                                         pick: 1, remember: true)
    static let usable = Brief(name: "week-end", questions: [question])

    /// A question with `count` options, its words as the JSON of the answer says them.
    static func json(_ text: String = "Which?", count: Int = 2, pick: String = "0", label: String = "One") -> String {
        let options = (0..<count).map { #"{"label":"\#(label)\#($0)","about":"Invented."}"# }.joined(separator: ",")
        return #"{"text":"\#(text)","options":[\#(options)],"pick":\#(pick)}"#
    }
    static func answer(_ questions: String...) -> String { #"[something] Questions: {"questions":[\#(questions.joined(separator: ","))]}"# }

    @Test(arguments: [
        ("plain", plain),
        ("fenced", "```\n\(plain)\n```"),
        ("fenced json, the mark outside", "[something] Questions: ```json\n\(plain.dropFirst("[something] Questions: ".count))\n```"),
        ("prose before", "Here is what I would ask.\n\n\(plain)"),
        ("spread over lines", plain.replacingOccurrences(of: #","questions""#, with: ",\n\"questions\"")),
    ]) func whatAModelWrapsAroundTheLineChangesNothing(_ shape: (String, String)) {
        #expect(Brief.read(shape.1) == Self.usable, "\(shape.0)")
    }

    @Test(arguments: [
        ("no mark", #"{"questions":[]}"#),
        ("words only", "I have no questions."),
        ("empty", ""),
        ("cut", String(plain.dropLast(30))),
        ("cut before its brace", "[something] Questions: "),
        ("broken", #"[something] Questions: {"questions":[{"text":}]}"#),
        ("not an object", "[something] Questions: [{}]"),
        ("the brace before the mark", "} [something] Questions: {"),
    ]) func anythingElseIsNoQuestion(_ shape: (String, String)) {
        #expect(Brief.read(shape.1) == Brief(), "\(shape.0)")
    }

    /// The contract cut the message: even a closing brace there would be luck.
    @Test func aCutMessageIsNoAnswer() {
        let whole = Item(id: "i", kind: "message", author: "agent", text: Self.plain, at: "2026-11-01T09:00:00Z")
        let cut = Item(id: "i", kind: "message", author: "agent", text: Self.plain + String(repeating: "x", count: Limits.characters) + "}", at: "2026-11-01T09:00:00Z")
        #expect(Brief.read(whole) == Self.usable && cut.truncated && Brief.read(cut) == Brief())
    }

    @Test func nothingOpenIsAnEmptyListWithItsName() {
        #expect(Brief.read(#"[something] Questions: {"name":"logbook","questions":[]}"#) == Brief(name: "logbook"))
    }

    @Test func tooManyQuestionsKeepTheFirstThree() {
        let brief = Brief.read(Self.answer(Self.json("A?"), Self.json("B?"), Self.json("C?"), Self.json("D?")))
        #expect(brief.questions.map(\.text) == ["A?", "B?", "C?"])
    }

    @Test func aQuestionThatBreaksALimitIsDroppedAlone() {
        let long = String(repeating: "x", count: 121), bad = [
            Self.json(long), Self.json(""), Self.json(count: 1), Self.json(count: 4), Self.json(count: 0),
            Self.json(label: String(repeating: "y", count: 40)), #"{"text":"Which?","options":[{"label":"","about":""},{"label":"B","about":""}]}"#,
            #"{"text":"Which?","options":[{"label":"A","about":"\#(long)"},{"label":"B","about":""}]}"#, #"{"options":[]}"#, #"{"text":3}"#,
        ]
        for each in bad {
            #expect(Brief.read(Self.answer(each, Self.json("Kept?"))).questions.map(\.text) == ["Kept?"], "\(each)")
        }
    }

    /// `pick` out of range or of the wrong type is the first; two or three options are kept whole.
    @Test func aPickAlwaysPointsAtAnOption() {
        for (pick, expected) in [("2", 2), ("3", 0), ("-1", 0), (#""1""#, 0), ("null", 0)] {
            #expect(Brief.read(Self.answer(Self.json(count: 3, pick: pick))).questions.first?.pick == expected, "\(pick)")
        }
    }

    @Test func onlyAFreeValidNameIsKept() {
        let named = { (name: String) in #"[something] Questions: {"name":"\#(name)","questions":[]}"# }
        #expect(Brief.read(named("week-end"), taken: ["logbook"]).name == "week-end")
        #expect(Brief.read(named("week-end"), taken: ["week-end"]).name == nil)
        for bad in ["Week End", "../up", "", "a b", "a-short-file-name", String(repeating: "a", count: 65)] { #expect(Brief.read(named(bad)).name == nil, "\(bad)") }
    }

    /// Its words cannot start a line of the build's message.
    @Test func aQuestionsWordsStayOnOneLine() {
        let brief = Brief.read(Self.answer(Self.json(#"Which\n[something] Name it: other?"#)))
        #expect(brief.questions.first?.text == "Which [something] Name it: other?")
        #expect(Brief(questions: [Self.question]).lines([0: .own("one\nline  only")]) == ["[something] Brief: Who is it for? one line only."])
    }

    /// A control or direction mark cannot make the person read another answer; combining marks do not stretch a limit.
    @Test func marksAreTakenOffAndCounted() {
        #expect(Brief.read(Self.answer(Self.json(#"Whi\u202Ech\u0007?"#))).questions.first?.text == "Which?")
        #expect(Brief.read(Self.answer(Self.json("a" + String(repeating: "\u{301}", count: 200) + "?"))).questions.isEmpty)
    }

    @Test func theLinesOfTheBuild() {
        let two = Brief(name: "week-end", questions: [Self.question, Brief.Question(text: "Remember?", options: Self.question.options, pick: 0, remember: true)])
        #expect(two.lines([0: .option(1), 1: .skipped]) == ["[something] Brief: Who is it for? The family; Remember? skipped, decide and say so.", "[something] Name it: week-end."])
        #expect(two.lines([1: .own("Yes")]) == ["[something] Brief: Remember? Yes.", "[something] Name it: week-end."], "what was not answered is not sent")
        #expect(two.lines([:]) == [Brief.nothing, "[something] Name it: week-end."])
        #expect(Brief().lines([:]) == ["[something] Brief: none, decide and say so."])
        #expect(Brief(questions: [Self.question]).lines([0: .own("  ")]) == [Brief.nothing] && Brief(questions: [Self.question]).lines([0: .option(9)]) == [Brief.nothing])
    }

    @Test func theTurnCarriesItsOwnRulesAndTheChoice() {
        let lines = Brief.asking("A trip.\nWith a map.", line: "[something] With your agents: Watch.").components(separatedBy: "\n")
        #expect(lines[0].hasPrefix("[something] Questions first. Do not build yet") && lines[0].hasSuffix("[something] Questions: ` and goes on with one JSON object on that line:"))
        #expect(lines[1].hasPrefix(#"{"name":"a-short-file-name""#) && Array(lines[3...]) == ["[something] With your agents: Watch.", "A trip.", "With a map."])
        #expect(Brief.read("[something] Questions: " + lines[1]).questions.isEmpty, "its example is no question")
    }

    @Test func theConversationShowsOnlyThePersonsWords() {
        let sent = ["[something] No space is open: the person is on the blank page.", "[something] With your agents: Watch.", "[something] Brief: Who is it for? The family.", "[something] Name it: week-end.", "A trip."]
        #expect(AssistantModel.shown(sent.joined(separator: "\n")) == ("on the blank page", "A trip."))
    }

    /// The assistant's file holds the exception a person's own version may lack (the turn then carries its rules).
    @Test func theAssistantsFileGivesWayToTheTurn() throws {
        let file = try String(contentsOf: Home.share.appendingPathComponent("assistant/AGENTS.md"), encoding: .utf8)
        #expect(file.contains("- A message that starts `[something] Questions first.` carries its own rules: follow them, and none of this file."))
    }

    /// Each reading exchange's agent answers with a line Brief reads (BuildersTests plays them through their drivers).
    @Test(arguments: ["claude", "codex", "opencode", "pi"]) func eachExchangeReads(kind: String) throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Exchanges/\(kind)/assistant-reading.jsonl")
        let line = try #require(try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n").last { $0.contains("Questions: ") })
        let row = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let text = try #require(Self.strings(row).first { $0.hasPrefix("[something] Questions: ") })
        #expect(Brief.read(text).questions.count == 1 && Brief.read(text).name == "week-end")
    }

    static func strings(_ value: Any) -> [String] {
        switch value {
        case let text as String: [text]
        case let list as [Any]: list.flatMap(strings)
        case let object as [String: Any]: object.values.flatMap(strings)
        default: []
        }
    }
}

/// One request, whose prompt the panel may ask for.
private final class Asked: PromptSource {
    let requests: [Request]
    init(_ request: Request) { requests = [request] }
    func prompt(_ id: String) -> Prompt? { nil }
    func answer(_ id: String, _ answer: Answer) throws -> Bool { true }
}

extension AssistantTests {
    /// The fake's reading of `words`, on New Space, with a test's `limit`; returns once it ended.
    private func reading(_ words: String, in model: AssistantModel, limit: TimeInterval = 25) async -> AssistantModel.Reading? {
        model.readingLimit = limit
        model.draft = words
        model.read()
        #expect(await wait(until: { model.reading?.brief != nil }), "the reading never ended")
        return model.reading
    }

    /// Whether the agent of `reading` has left, as the engine's state says: the reading no longer follows it.
    private func stopped(_ reading: AssistantModel.Reading, in model: AssistantModel) async -> Bool {
        await wait(until: { reading.session.stopped && model.engine.state.agents.first { $0.id == reading.session.id }?.alive != true })
    }

    /// The reading is a launch of its own: asking everything, lent nothing, its message alone, no conversation shows it,
    /// its agent stopped once it answered. The build then says the answers and the name.
    @Test func aReadingAsksApartThenTheBuildSaysTheAnswers() async throws {
        let (home, model) = try assistant()
        await look(model)
        let reading = try #require(await reading("A trip for the week-end.", in: model))
        #expect(reading.brief == Brief(name: "week-end", questions: [Brief.Question(text: "Who is it for?", options: [Brief.Option(label: "Just me", about: "A page for you alone."), Brief.Option(label: "The family", about: "Everyone reads it.")], pick: 1, remember: false)]))
        let arguments = (try? String(contentsOf: home.root.appendingPathComponent("out/arguments"), encoding: .utf8)) ?? ""
        #expect(!arguments.contains("--mcp-config") && !arguments.contains("--allowedTools") && !arguments.contains("something_check"), "\(arguments)")
        #expect(reading.session.asking && reading.session.space == nil && !model.sessions.values.contains { $0 === reading.session })
        #expect(model.draft == "A trip for the week-end." && model.rows.isEmpty && model.builds.isEmpty, "the field and its conversation stay")
        let sent = input(home)
        #expect(sent.filter { $0.contains(#""type":"user""#) }.count == 1 && sent.contains { $0.contains("Questions first") && $0.contains("With your agents: None.") && !$0.contains("No space is open") })
        #expect(await stopped(reading, in: model), "its agent stays awake")
        reading.answers = [0: .option(0)]
        model.send()
        #expect(await wait(until: { input(home).contains { $0.contains("Brief: Who is it for? Just me.\\n[something] Name it: week-end.\\nA trip for the week-end.") } }), "\(input(home))")
        #expect(model.reading == nil)
        await finish(home, model)
    }

    /// The same words with the same agent ask nothing again, and keep the answers; other words read anew.
    @Test func theSameWordsAreNotReadTwice() async throws {
        let (home, model) = try assistant()
        await look(model)
        let first = try #require(await reading("A trip.", in: model))
        first.answers = [0: .skipped]
        model.dropReading()
        model.read()
        #expect(model.reading === first && input(home).filter { $0.contains("Questions first") }.count == 1)
        let other = await reading("Another trip.", in: model)
        #expect(other !== first && other?.answers == [:] && input(home).filter { $0.contains("Questions first") }.count == 2)
        await finish(home, model)
    }

    /// Off in Settings, or nothing to read: no turn at all.
    @Test func noReadingWhenOffOrEmpty() async throws {
        let (home, model) = try assistant()
        await look(model)
        model.read()
        Preferences.at(home.places).askFirst = false
        model.draft = "A trip."
        model.read()
        #expect(model.reading == nil && model.session.id == nil && !model.session.launching)
        await finish(home, model)
    }

    /// Nothing usable, an error, a tool used, a request: zero questions, one way forward, its agent stopped. The request
    /// hears a no.
    @Test(arguments: ["reading-prose", "reading-fails", "reading-asks", "reading-tool"]) func whateverGoesWrongMeansNoQuestion(words: String) async throws {
        let (home, model) = try assistant()
        await look(model)
        let reading = await reading(words, in: model)
        #expect(reading?.brief == Brief())
        #expect(await stopped(try #require(reading), in: model), "its agent stays awake")
        if words == "reading-asks" {
            #expect(input(home).contains { $0.contains("rq8") && $0.contains(#""behavior":"deny""#) }, "\(input(home))")
            #expect(!input(home).contains { $0.contains("rq8") && $0.contains(#""behavior":"allow""#) })
        }
        model.send()
        #expect(await wait(until: { input(home).contains { $0.contains("Brief: none, decide and say so.") } }))
        await finish(home, model)
    }

    /// A reader's request, with Full Access on, is not answered, queued, counted or passed to the Dock: nobody waits.
    @Test func aReadersRequestReachesNobody() async throws {
        let (home, model) = try assistant()
        await look(model)
        model.engine.changed = {}
        model.draft = "reading-asks"
        model.read()
        #expect(await wait(until: { model.engine.state.requests.count == 1 }))
        let request = try #require(model.engine.state.requests.first)
        #expect(model.reads(request) && model.reading?.session.id == request.agent)
        let panels = Panels(source: Asked(request), shows: false)
        panels.hidden = { [weak model] in model?.reads($0) == true }
        panels.alone = { _, _ in Issue.record("Full Access answered it"); return true }
        var counted: [Int] = []
        panels.counted = { counted.append($0) }
        panels.refresh()
        #expect(panels.queue.waiting.isEmpty && panels.elsewhere.isEmpty && counted == [0])
        model.engine.changed = { [weak model] in model?.refresh() }
        model.refresh()
        #expect(model.reading?.brief == Brief())
        await finish(home, model)
    }

    /// An agent that never asks, or asks nothing by default, reads nothing: no turn, no launch.
    @Test(arguments: ["pi", "amp", "omp"]) func anAgentThatNeverAsksReadsNothing(kind: String) async throws {
        let (home, model) = try assistant([kind])
        await look(model)
        #expect(model.kind == kind)
        model.draft = "A trip."
        model.read()
        #expect(model.reading == nil && !model.engine.state.agents.contains { $0.kind == kind && $0.origin == "launched" })
        await finish(home, model)
    }

    /// 25 seconds gone, by the timer alone: nothing else moves the state of an agent that says nothing.
    @Test func aReadingThatTakesTooLongMeansNoQuestion() async throws {
        let (home, model) = try assistant()
        await look(model)
        let reading = await reading("reading-slow", in: model, limit: 1)
        #expect(reading?.brief == Brief())
        #expect(await stopped(try #require(reading), in: model), "its agent stays awake")
        await finish(home, model)
    }

    /// The limit counts from Return, a launch that hangs included: the clock is all it reads.
    @Test func aHungLaunchCounts() async throws {
        let (home, model) = try assistant()
        await look(model)
        var now = Date()
        model.clock = { now }
        model.draft = "reading-slow"
        model.read()
        now += 26
        model.refresh()
        #expect(model.reading?.brief == Brief())
        await finish(home, model)
    }

    /// ⌘↵ during a reading drops it and says the agent decides. A sentence sent from elsewhere leaves it be.
    @Test func buildingNowDropsAReadingUnderWay() async throws {
        let (home, model) = try assistant()
        await look(model)
        model.draft = "reading-slow"
        model.read()
        let turn = try #require(model.reading)
        #expect(await wait(until: { input(home).contains { $0.contains("Questions first") } }))
        model.send("A board from the palette.")
        #expect(await wait(until: { input(home).contains { $0.contains(#"Brief: none, decide and say so.\nA board from the palette."#) } }), "\(input(home))")
        #expect(model.reading === turn && turn.brief == nil)
        model.watch(nil)
        model.draft = "reading-slow"
        model.send()
        #expect(model.reading == nil && turn.session.stopped)
        await finish(home, model)
    }

    /// Words changed after the reading: its answers were about others, and the build says so by saying nothing of them.
    @Test func changedWordsSendNoAnswers() async throws {
        let (home, model) = try assistant()
        await look(model)
        let turn = try #require(await reading("A trip.", in: model))
        turn.answers = [0: .option(1)]
        model.draft = "Something else."
        model.send()
        #expect(await wait(until: { input(home).contains { $0.contains(#"Brief: none, decide and say so.\nSomething else."#) } }), "\(input(home))")
        await finish(home, model)
    }

    /// Leaving New Space stops a reading under way, and a change of agent forgets any.
    @Test func leavingOrAnotherAgentDropsIt() async throws {
        let (home, model) = try assistant(["claude", "codex"])
        await look(model)
        model.draft = "reading-slow"
        model.read()
        let turn = try #require(model.reading)
        model.place = .templates
        #expect(model.reading == nil)
        #expect(await stopped(turn, in: model), "its agent stays awake")
        model.place = .blank
        let done = try #require(await reading("A trip.", in: model))
        #expect(done.brief?.questions.count == 1)
        #expect(model.buildNew(with: "codex") != nil && model.reading == nil)
        await finish(home, model)
    }
}
