// Events: what a driver says folds into the agent, its thread and its requests, with state words from StateMap,
// and the held queue hands a message over at the end of a turn and empties on an interrupt.
import Foundation
import Testing
@testable import SomethingCore

struct EventsTests {
    func launched() -> Fold {
        var agent = Agent(id: "a1", kind: "claude", origin: "launched")
        agent.folder = "/Users/example/code/shop"
        agent.can.send = true
        return Fold(agent)
    }

    func item(_ id: String, _ text: String, author: String = "agent") -> Item {
        Item(id: id, kind: "message", author: author, text: text, at: "2026-10-17T09:00:01Z")
    }

    @Test func beforeAnyEventNothingIsKnown() {
        let fold = launched()
        #expect(fold.agent.state == "unknown" && fold.agent.alive == nil && fold.thread == nil)
    }

    @Test func aTurnFromStartToEnd() throws {
        var fold = launched()
        fold.apply(.started(pid: 50123, thread: "th1"), at: "2026-10-17T09:00:00Z")
        #expect(fold.agent.state == "idle" && fold.agent.waiting == "none" && fold.agent.alive == true && fold.agent.evidence == "child")
        #expect(fold.agent.pid == 50123 && fold.agent.started == "2026-10-17T09:00:00Z")
        fold.apply(.reported(model: "claude-example-model", mode: "default", effort: nil), at: "2026-10-17T09:00:00Z")
        fold.apply(.reported(model: nil, mode: "plan", effort: nil), at: "2026-10-17T09:00:00Z")
        #expect(fold.agent.model == "claude-example-model" && fold.agent.mode == "plan" && fold.agent.effort == nil)
        fold.apply(.turnStarted(id: nil), at: "2026-10-17T09:00:01Z")
        fold.apply(.itemAppended(item("i1", "Add a dark mode.", author: "person")), at: "2026-10-17T09:00:01Z")
        fold.apply(.itemAppended(Item(id: "i2", kind: "tool", author: "agent", text: "npm test", at: "2026-10-17T09:00:02Z", tool: Tool(name: "Bash", status: "running"))), at: "2026-10-17T09:00:02Z")
        #expect(fold.agent.state == "working")
        fold.apply(.requestOpened(Request(id: "r1", agent: "a1", kind: "permission", tool: "Bash", about: "npm test", at: "2026-10-17T09:00:02Z")), at: "2026-10-17T09:00:02Z")
        #expect(fold.agent.state == "waiting" && fold.agent.waiting == "permission" && fold.requests.count == 1)
        fold.apply(.requestClosed(id: "r1"), at: "2026-10-17T09:00:03Z")
        fold.apply(.itemUpdated(Item(id: "i2", kind: "tool", author: "agent", text: "npm test", at: "2026-10-17T09:00:02Z", tool: Tool(name: "Bash", status: "done"))), at: "2026-10-17T09:00:04Z")
        #expect(fold.agent.state == "working" && fold.requests.isEmpty)
        fold.apply(.turnEnded(.done), at: "2026-10-17T09:00:05Z")
        let thread = try #require(fold.thread)
        #expect(thread.id == "th1" && thread.agent == "a1" && thread.complete)
        #expect(thread.turns.map(\.id) == ["th1#1"] && thread.turns[0].state == "done" && thread.turns[0].ended == "2026-10-17T09:00:05Z")
        #expect(thread.turns[0].items.map(\.id) == ["i1", "i2"] && thread.turns[0].items[1].tool?.status == "done")
        #expect(fold.agent.state == "idle" && fold.agent.updated == "2026-10-17T09:00:05Z")
    }

    @Test func aQuestionIsWaitingForAnAnswerAndAPermissionOutweighsIt() {
        var fold = launched()
        fold.apply(.started(pid: nil, thread: "th1"), at: "2026-10-17T09:00:00Z")
        fold.apply(.requestOpened(Request(id: "q1", agent: "a1", kind: "question", tool: nil, about: "Which colour?", at: "2026-10-17T09:00:01Z")), at: "2026-10-17T09:00:01Z")
        #expect(fold.agent.state == "waiting" && fold.agent.waiting == "answer")
        fold.apply(.requestOpened(Request(id: "r1", agent: "a1", kind: "permission", tool: "Write", about: nil, at: "2026-10-17T09:00:02Z")), at: "2026-10-17T09:00:02Z")
        #expect(fold.agent.waiting == "permission")
        fold.apply(.requestClosed(id: "r1"), at: "2026-10-17T09:00:03Z")
        #expect(fold.agent.waiting == "answer")
    }

    @Test func failuresInterruptionsAndEnds() {
        var fold = launched()
        fold.apply(.started(pid: nil, thread: nil), at: "2026-10-17T09:00:00Z")
        fold.apply(.turnStarted(id: "t1"), at: "2026-10-17T09:00:01Z")
        let error = AgentError(code: "AGENT_ERROR", message: "The model refused the request.")
        fold.apply(.turnEnded(.failed(error)), at: "2026-10-17T09:00:02Z")
        #expect(fold.agent.state == "error" && fold.agent.error == error && fold.turns.last?.state == "error")
        fold.apply(.turnStarted(id: "t2"), at: "2026-10-17T09:00:03Z")
        #expect(fold.agent.state == "working")
        fold.apply(.turnEnded(.interrupted), at: "2026-10-17T09:00:04Z")
        #expect(fold.agent.state == "interrupted" && fold.turns.last?.state == "interrupted")
        fold.apply(.turnStarted(id: "t3"), at: "2026-10-17T09:00:05Z")
        fold.apply(.stopped(nil), at: "2026-10-17T09:00:06Z")
        #expect(fold.agent.state == "interrupted", "a process gone mid-turn did not end normally")
        #expect(fold.turns.last?.state == "interrupted" && fold.agent.alive == false && fold.agent.can == Can())
        #expect(fold.thread == nil, "a thread nobody named cannot be shown")
    }

    @Test func aCleanStopIsDoneAndAFailedOneIsAnError() {
        var fold = launched()
        fold.apply(.started(pid: nil, thread: "th1"), at: "2026-10-17T09:00:00Z")
        fold.apply(.stopped(nil), at: "2026-10-17T09:00:01Z")
        #expect(fold.agent.state == "done" && fold.agent.waiting == "none")
        var failed = launched()
        failed.apply(.started(pid: nil, thread: "th1"), at: "2026-10-17T09:00:00Z")
        failed.apply(.requestOpened(Request(id: "r1", agent: "a1", kind: "permission", tool: "Bash", about: nil, at: "2026-10-17T09:00:00Z")), at: "2026-10-17T09:00:00Z")
        failed.apply(.stopped(AgentError(code: "AGENT_ERROR", message: "The program crashed.")), at: "2026-10-17T09:00:01Z")
        #expect(failed.agent.state == "error" && failed.requests.isEmpty)
    }

    @Test func theThreadKeepsItsLastTurnsAndSaysSo() throws {
        var fold = launched()
        fold.apply(.started(pid: nil, thread: "th1"), at: "2026-10-17T09:00:00Z")
        for _ in 1...12 {
            fold.apply(.turnStarted(id: nil), at: "2026-10-17T09:00:00Z")
            fold.apply(.turnEnded(.done), at: "2026-10-17T09:00:00Z")
        }
        let thread = try #require(fold.thread)
        #expect(thread.turns.count == Limits.turns && !thread.complete && thread.turns.first?.id == "th1#3")
        for n in 1...60 { fold.apply(.itemAppended(item("i\(n)", "Invented.")), at: "2026-10-17T09:00:00Z") }
        #expect(fold.turns.last?.items.count == Limits.items && fold.turns.last?.items.first?.id == "i11")
    }

    @Test func anItemBeforeAnyTurnGoesInATurnNobodySawStart() {
        var fold = launched()
        fold.apply(.started(pid: nil, thread: "th1"), at: "2026-10-17T09:00:00Z")
        fold.apply(.itemAppended(item("i1", "Earlier words.")), at: "2026-10-17T09:00:00Z")
        #expect(fold.turns.map(\.state) == ["unknown"] && fold.agent.state == "idle")
    }

    @Test func theQueueHandsOverAtTheEndOfATurnAndEmptiesOnAnInterrupt() {
        var fold = launched()
        fold.apply(.started(pid: nil, thread: "th1"), at: "2026-10-17T09:00:00Z")
        fold.apply(.turnStarted(id: nil), at: "2026-10-17T09:00:01Z")
        let first = Queued(id: "q1", text: "Then run the tests.", at: "2026-10-17T09:00:02Z")
        let second = Queued(id: "q2", text: "Then check the footer.", at: "2026-10-17T09:00:03Z")
        fold.hold(first); fold.hold(second)
        #expect(fold.agent.queue == [first, second])
        #expect(fold.apply(.turnEnded(.done), at: "2026-10-17T09:00:04Z") == first)
        #expect(fold.agent.queue == [second])
        fold.apply(.turnStarted(id: nil), at: "2026-10-17T09:00:05Z")
        #expect(fold.apply(.turnEnded(.failed(AgentError(code: "AGENT_ERROR", message: "Invented."))), at: "2026-10-17T09:00:06Z") == second)
        #expect(fold.apply(.turnEnded(.done), at: "2026-10-17T09:00:07Z") == nil, "an empty queue hands nothing over")
        fold.hold(first)
        fold.apply(.turnStarted(id: nil), at: "2026-10-17T09:00:08Z")
        #expect(fold.apply(.turnEnded(.interrupted), at: "2026-10-17T09:00:09Z") == nil && fold.agent.queue.isEmpty)
        fold.hold(first)
        fold.emptyQueue()
        #expect(fold.agent.queue.isEmpty)
    }

    @Test func theFoldedStateKeepsTheWaitingInvariant() {
        var fold = launched()
        let events: [AgentEvent] = [.started(pid: nil, thread: "th1"), .turnStarted(id: nil),
            .requestOpened(Request(id: "r1", agent: "a1", kind: "permission", tool: nil, about: nil, at: "2026-10-17T09:00:00Z")),
            .requestClosed(id: "r1"), .turnEnded(.done), .stopped(nil)]
        for event in events {
            fold.apply(event, at: "2026-10-17T09:00:00Z")
            #expect((fold.agent.state == "waiting") == ["permission", "answer"].contains(fold.agent.waiting ?? ""))
        }
    }
}
