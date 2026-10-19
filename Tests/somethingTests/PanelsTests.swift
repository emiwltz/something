// The permission and question panels against a fake prompt source shaped like the Engine's: one panel at a time in
// the order the requests came, Allow Once and Deny, Escape denies, never modal, closed when the agent withdraws its
// request, and a question answered with the chosen and typed answers. No panel is shown.
import AppKit
import SomethingAgents
import SomethingCore
import Testing
@testable import something

/// The Engine's side of the panels, played by the test.
final class FakePrompts: PromptSource {
    var prompts: [Prompt] = []
    var answers: [(String, Answer)] = []
    /// What `answer` throws, as the Engine does when the agent stopped reading.
    var lost: CodedError?
    var requests: [Request] { prompts.map(\.request) }
    func prompt(_ request: String) -> Prompt? { prompts.first { $0.request.id == request } }
    func answer(_ request: String, _ answer: Answer) throws {
        answers.append((request, answer))
        if let lost { throw lost }
    }

    func permission(_ id: String, about: String) -> Prompt {
        Prompt(request: Request(id: id, agent: "a1", kind: "permission", tool: "Bash", about: about, at: "2026-10-17T09:00:01Z"),
               input: about)
    }
}

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing)) struct PanelsTests {
    init() { NSApplication.shared.setActivationPolicy(.prohibited) }

    @Test func permissionsAreQueuedAndAnswered() throws {
        let source = FakePrompts()
        let panels = Panels(source: source, shows: false)
        panels.who = { _ in Asker(program: "Claude Code", line: "“shop”, working in ~/code/shop") }
        source.prompts = [source.permission("r1", about: "npm test"), source.permission("r2", about: "rm -rf build")]
        panels.refresh()
        #expect(panels.waiting == ["r1", "r2"] && panels.panel?.request.id == "r1")
        panels.refresh()
        #expect(panels.panel?.request.id == "r1", "a refresh with nothing new changes nothing")

        let first = try #require(panels.panel)
        first.allow()
        #expect(first.dismissed)
        #expect(source.answers.map(\.0) == ["r1"] && source.answers[0].1 == .once)
        #expect(panels.panel?.request.id == "r2", "the next request has its panel")
        // The agent has not taken the answer yet: r1 stays in the state, and is not shown again.
        panels.refresh()
        #expect(panels.panel?.request.id == "r2" && panels.waiting == ["r2"])

        // Escape denies.
        try #require(panels.panel).cancelOperation(nil)
        #expect(source.answers.map(\.0) == ["r1", "r2"] && source.answers[1].1 == .deny)
        #expect(panels.panel == nil)
    }

    /// An answer the agent no longer reads is said in the panel, which stays, even once the request left the state,
    /// until the person puts it away; then the next request has its panel.
    @Test func aLostAnswerIsSaidInThePanel() throws {
        let source = FakePrompts()
        let panels = Panels(source: source, shows: false)
        source.prompts = [source.permission("r1", about: "npm test"), source.permission("r2", about: "git push")]
        source.lost = CodedError("AGENT_STOPPED", "Claude Code did not receive your answer: it stopped listening.")
        panels.refresh()
        let first = try #require(panels.panel)
        let top = first.frame.maxY
        first.allow()
        let texts = (first.contentView?.subviews ?? []).compactMap { ($0 as? NSTextField)?.stringValue }
        #expect(texts == ["An agent wants to run a command", "Claude Code did not receive your answer: it stopped listening."],
                "who asked stays above the sentence")
        #expect(first.frame.maxY == top, "the panel keeps its top")
        #expect(first.told && !first.dismissed && panels.panel === first)
        source.prompts.removeFirst()
        panels.refresh()
        #expect(panels.panel === first && !first.dismissed, "the sentence stays when the request leaves the state")
        first.cancelOperation(nil)
        #expect(first.dismissed && source.answers.count == 1, "putting it away answers nothing")
        #expect(panels.panel?.request.id == "r2")
    }

    @Test func aWithdrawnRequestClosesItsPanel() throws {
        let source = FakePrompts()
        let panels = Panels(source: source, shows: false)
        source.prompts = [source.permission("r1", about: "npm test"), source.permission("r2", about: "git push")]
        panels.refresh()
        let first = try #require(panels.panel)
        source.prompts.removeFirst()
        panels.refresh()
        #expect(first.dismissed && panels.panel !== first && panels.panel?.request.id == "r2")
        #expect(source.answers.isEmpty, "nothing is answered for the person")
        // A request whose details are already gone is passed over.
        source.prompts = [Prompt(request: Request(id: "r3", agent: "a1", kind: "permission", tool: nil, about: nil, at: "2026-10-17T09:00:02Z"))]
        panels.refresh()
        #expect(panels.panel?.request.id == "r3")
        source.prompts = []
        panels.refresh()
        #expect(panels.panel == nil && panels.waiting.isEmpty)
    }

    @Test func aQuestionIsAnsweredWithTheChoices() throws {
        let source = FakePrompts()
        let panels = Panels(source: source, shows: false)
        let request = Request(id: "q1", agent: "a1", kind: "question", tool: "AskUserQuestion", about: "Which color?", at: "2026-10-17T09:00:03Z")
        source.prompts = [Prompt(request: request, questions: [
            Question(header: "Color", text: "Which color for the cart page?", options: ["Blue", "Green"], multiple: false),
            Question(header: nil, text: "Which pages?", options: ["Cart", "Home", "Help"], multiple: true),
            Question(header: nil, text: "Anything else?", options: [], multiple: false),
        ])]
        panels.refresh()
        let panel = try #require(panels.panel)
        #expect(panel.boxes.map { $0.map(\.title) } == [["Blue", "Green"], ["Cart", "Home", "Help"], []])
        panel.boxes[0][1].state = .on
        panel.boxes[1][0].state = .on
        panel.boxes[1][2].state = .on
        panel.typed[2].stringValue = "An invented remark."
        panel.reply()
        #expect(source.answers.map(\.0) == ["q1"])
        #expect(source.answers[0].1 == .choice([["Green"], ["Cart", "Help"], ["An invented remark."]]))

        source.prompts = [Prompt(request: Request(id: "q2", agent: "a1", kind: "question", tool: nil, about: nil, at: "2026-10-17T09:00:04Z"),
                                 questions: [Question(header: nil, text: "Go on?", options: ["Yes"], multiple: false)])]
        panels.refresh()
        try #require(panels.panel).cancelOperation(nil)
        #expect(source.answers.last?.0 == "q2" && source.answers.last?.1 == .deny, "Escape leaves a question unanswered")
    }

    /// A long sentence of who asks and a long command wrap: the panel keeps its width instead of growing past the screen.
    @Test func aLongRequestKeepsThePanelsWidth() throws {
        let who = Asker(program: "Claude Code", line: "“an-invented-agent-name-that-goes-on”, started by “Morning review”, working in "
            + "~/code/clients/example-agency/" + String(repeating: "a-very-deep-folder/", count: 10) + "website")
        let input = "npm test -- " + String(repeating: "--an-invented-flag ", count: 20)
        let panel = PromptPanel(Prompt(request: Request(id: "r1", agent: "a1", kind: "permission", tool: "Bash", about: nil,
                                                        at: "2026-10-17T09:00:01Z"), input: input), who: who) { _ in }
        #expect(panel.frame.width <= PromptPanel.width)
    }

    /// The panel's title says what the agent wants, by its tool, and who asks: its name, the space that started it,
    /// and its folder, from the home folder.
    @Test func thePanelSaysWhatAndWho() throws {
        let cases: [(String?, String)] = [("Bash", "run a command"), ("commandExecution", "run a command"), ("execute", "run a command"),
                                          ("Edit", "change a file"), ("fileChange", "change a file"), ("permissions", "change its permissions"),
                                          ("WebFetch", "use WebFetch"), (nil, "do something that needs your permission")]
        for (tool, words) in cases { #expect(PromptPanel.action(tool) == words, "\(tool ?? "nil")") }
        var agent = Agent(id: "a1", kind: "claude", origin: "launched")
        (agent.name, agent.folder) = ("shop", "/Users/example/code/shop")
        #expect(App.who(agent, startedBy: "My agents", home: "/Users/example")
                == Asker(program: "Claude Code", line: "“shop”, started by “My agents”, working in ~/code/shop"))
        agent.name = nil
        #expect(App.who(agent, startedBy: nil, home: "/Users/example").line == "Working in ~/code/shop")
        #expect(App.who(nil, startedBy: nil, home: "/Users/example") == Asker(program: "An agent", line: ""))
        let question = PromptPanel(Prompt(request: Request(id: "q1", agent: "a1", kind: "question", tool: "AskUserQuestion", about: nil,
                                                           at: "2026-10-17T09:00:01Z")), who: Asker(program: "Codex", line: "")) { _ in }
        #expect((question.contentView?.subviews.first as? NSTextField)?.stringValue == "Codex asks you")
    }

    /// The quit sheet says how many agents stop, in the singular and the plural.
    @Test func theQuitSheetSaysWhoStops() {
        #expect(Ask.quit(1).informativeText == "An agent something started is still running. Quitting stops it.")
        #expect(Ask.quit(2).informativeText == "2 agents something started are still running. Quitting stops them.")
    }
}
