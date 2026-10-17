// The permission and question panels against a fake prompt source shaped like the Engine's: one panel at a time in
// the order the requests came, Allow once and Deny, Escape denies, never modal, closed when the agent withdraws its
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
    var requests: [Request] { prompts.map(\.request) }
    func prompt(_ request: String) -> Prompt? { prompts.first { $0.request.id == request } }
    func answer(_ request: String, _ answer: Answer) { answers.append((request, answer)) }

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
        panels.who = { _ in "Claude Code “shop”, working in /Users/example/code/shop" }
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
}
