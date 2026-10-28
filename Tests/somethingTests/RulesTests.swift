// What something answers by itself (Rules.swift): the rule "Always for this space" offers, when a rule or Full Access
// answers, and keeping, listing and revoking rules in the grants file.
import Foundation
import SomethingAgents
import SomethingCore
import Testing
@testable import something

struct RulesTests {
    func request(_ kind: String = "permission", tool: String? = "Bash") -> Request {
        Request(id: "r1", agent: "a1", kind: kind, tool: tool, about: nil, at: "2026-10-22T18:20:00Z")
    }

    var agent: Agent {
        var agent = Agent(id: "a1", kind: "claude", origin: "launched")
        agent.folder = "/Users/example/code/shop"
        return agent
    }

    let grant = Grant(declared: Asked(Declaration(name: "agents")), at: "2026-10-22T18:00:00Z")

    /// Offered only for a plain command of an agent a space started, whose folder is known, in a space with a grant.
    @Test func whatAlwaysOffers() {
        let at = "2026-10-22T18:20:00Z"
        #expect(Rules.offer(request(), input: "npm test", agent: agent, assistant: false, grant: grant, at: at)
                == Rule(kind: "claude", command: "npm test", folder: "/Users/example/code/shop", at: at))
        var nowhere = agent
        nowhere.folder = nil
        let refused: [(String, Request, String?, Agent?, Bool, Grant?)] = [
            ("a question", request("question"), "npm test", agent, false, grant), ("a file", request(tool: "Edit"), "npm test", agent, false, grant),
            ("a chain", request(), "npm test && rm -rf build", agent, false, grant), ("no command", request(), nil, agent, false, grant),
            ("the assistant", request(), "npm test", agent, true, grant), ("no grant", request(), "npm test", agent, false, nil),
            ("no folder", request(), "npm test", nowhere, false, grant), ("no agent", request(), "npm test", nil, false, grant)]
        for (why, request, input, agent, assistant, grant) in refused {
            #expect(Rules.offer(request, input: input, agent: agent, assistant: assistant, grant: grant, at: at) == nil, "\(why)")
        }
    }

    /// A rule answers exactly its command; Full Access answers the assistant's permissions only; a question always waits.
    @Test func whatSomethingAnswersByItself() {
        var kept = grant
        kept.rules = [Rule(kind: "claude", command: "npm test", folder: "/Users/example/code/shop", at: "2026-10-21T09:00:00Z")]
        #expect(Rules.alone(request(), input: "npm test", agent: agent, assistant: false, fullAccess: false, grant: kept))
        #expect(!Rules.alone(request(), input: "npm test -- --watch", agent: agent, assistant: false, fullAccess: true, grant: kept),
                "Full Access never covers an agent a space started")
        #expect(!Rules.alone(request("question"), input: "npm test", agent: agent, assistant: false, fullAccess: false, grant: kept))
        #expect(!Rules.alone(request(tool: "Edit"), input: "npm test", agent: agent, assistant: false, fullAccess: false, grant: kept),
                "a rule keeps a command, never another tool whose input reads the same")
        #expect(Rules.alone(request(), input: "rm -rf build", agent: agent, assistant: true, fullAccess: true, grant: nil))
        #expect(!Rules.alone(request(), input: "npm test", agent: agent, assistant: true, fullAccess: false, grant: kept),
                "a rule never covers the assistant")
        #expect(!Rules.alone(request("question"), input: nil, agent: agent, assistant: true, fullAccess: true, grant: nil))
    }

    /// A command the agent says runs in another folder (Codex's cwd) is neither kept nor answered by a rule of its own
    /// folder: the rule keeps the folder the command runs in.
    @Test func aRuleKeepsTheFolderTheCommandRunsIn() {
        var kept = grant
        kept.rules = [Rule(kind: "claude", command: "npm test", folder: "/Users/example/code/shop", at: "2026-10-21T09:00:00Z")]
        #expect(Rules.alone(request(), input: "npm test", runs: "/Users/example/code/shop", agent: agent, assistant: false, fullAccess: false, grant: kept))
        #expect(!Rules.alone(request(), input: "npm test", runs: "/Users/example/code/other", agent: agent, assistant: false, fullAccess: false, grant: kept))
        #expect(Rules.offer(request(), input: "npm test", runs: "/Users/example/code/other", agent: agent, assistant: false, grant: grant, at: "") == nil)
        #expect(Rules.offer(request(), input: "npm test", runs: "/Users/example/code/shop", agent: agent, assistant: false, grant: grant, at: "")?.folder
                == "/Users/example/code/shop")
    }

    /// An answer by a rule is written in the space's journal, action "allow", and said in a quiet note; Full Access's
    /// only in the note, the assistant having no space journal.
    @Test func whatAnAnswerBySomethingLeaves() throws {
        let home = Home(prefix: "something-rules-")
        defer { home.remove() }
        let journal = Journal(folder: home.places.journals)
        #expect(Rules.trace(request(), input: "npm test", kind: "claude", assistant: false, space: "agents", journal: journal, at: "2026-10-22T18:20:00Z")
                == "Allowed by your rule · npm test")
        #expect(try journal.last(5, space: "agents")
                == [JournalLine(at: "2026-10-22T18:20:00Z", action: "allow", agent: "a1", kind: "claude", text: "npm test", result: "ok")])
        #expect(Rules.trace(request(), input: "rm -rf build", kind: "claude", assistant: true, space: nil, journal: journal, at: "")
                == "Allowed by Full Access · rm -rf build")
        #expect(Rules.trace(request(), input: nil, kind: "claude", assistant: false, space: "agents", journal: journal, at: "") == nil)
        #expect(try journal.last(5, space: "agents").count == 1, "only the rule's answer is journaled")
    }

    /// Full Access's one confirmation: its words, Turn On then Cancel, and Cancel, the safe action, first in focus.
    @MainActor @Test(.enabled(if: windowServer, windowServerMissing)) func fullAccessAsksOnce() throws {
        let sheet = Rules.confirmation()
        #expect(sheet.title == "Turn On Full Access?" && sheet.isAlert)
        #expect(sheet.buttons.map(\.title) == ["Turn On Full Access", "Cancel"] && sheet.buttons.map(\.role) == [.destructive, .primary])
        #expect((sheet.initialFirstResponder as? SheetButton)?.title == "Cancel")
    }

    /// Kept once in the space's grant, listed with its space, said in Settings' words, revoked to nothing.
    @Test func keepListAndRevoke() throws {
        let home = Home(prefix: "something-rules-")
        defer { home.remove() }
        let grants = Grants(home.places.grants)
        let rule = Rule(kind: "claude", command: "git log --oneline -20", folder: "/Users/example/code/atelier", at: "2026-10-19T09:00:00Z")
        try Rules.keep(rule, in: "project", grants)
        #expect(try grants.read().spaces["project"] == nil, "a space with no grant keeps no rule")
        try grants.update { $0.spaces["project"] = grant }
        try Rules.keep(rule, in: "project", grants)
        try Rules.keep(rule, in: "project", grants)
        #expect(try grants.read().spaces["project"]?.rules == [rule], "kept once")
        let all = Rules.all(grants, spaces: [("agents", "My agents"), ("project", "Project watch")])
        #expect(all == [LastingRule(space: "project", title: "Project watch", rule: rule)])
        let now = try #require(iso8601.date(from: "2026-10-22T18:20:00Z"))
        #expect(Rules.line(rule, space: "Project watch", home: "/Users/example", now: now) == "Claude Code · in ~/code/atelier · for Project watch · since 19 Oct")
        try Rules.revoke(rule, in: "project", grants)
        #expect(try grants.read().spaces["project"]?.rules == nil && Rules.all(grants, spaces: [("project", "Project watch")]).isEmpty)
    }
}
