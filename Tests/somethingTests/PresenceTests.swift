// An assistant's presence, word for word, from invented agents and turns at a fixed moment: the state table (unknown
// never becomes listen, a dead agent with an error crashed, a retry toward the model cannotReachModel), the
// present-tense line per tool and status, "Still working · Stop" once 10 s went by, "Changed brief.html" for 3.6 s,
// the stuck notices and the sticker's label. No window, no clock.
import Foundation
import SomethingCore
import Testing
@testable import something

@MainActor @Suite struct PresenceTests {
    let now = Date(timeIntervalSince1970: 1_792_779_600)  // 23 Oct 2026 18:20 UTC
    let facts = Presence.Facts(name: "Claude Code", installed: true)

    /// `seconds` before now, as the state writes a moment: to the second.
    func at(_ seconds: TimeInterval) -> String { iso8601.string(from: now.addingTimeInterval(-seconds)) }

    func agent(_ state: String, alive: Bool? = true, error: Bool = false, retry: Bool = false) -> Agent {
        var agent = Agent(id: "a1", kind: "claude", origin: "launched")
        (agent.state, agent.alive, agent.model, agent.updated) = (state, alive, "Opus 4.7", at(4 * 60 + 5))
        agent.can.interrupt = true
        if error { agent.error = AgentError(code: "AGENT_ERROR", message: "It ended.") }
        if retry { agent.detail["apiRetry"] = .object(["attempt": .number(2)]) }
        return agent
    }

    func tool(_ name: String, _ text: String, _ status: String = "done") -> Item {
        Item(id: UUID().uuidString, kind: "tool", author: "agent", text: text, at: at(1), tool: Tool(name: name, status: status))
    }

    func turn(_ state: String = "working", started: TimeInterval = 2, ended: TimeInterval? = nil, _ items: [Item] = []) -> Turn {
        Turn(id: "t1", state: state, started: at(started), ended: ended.map(at), items: items)
    }

    func of(_ agent: Agent?, _ turn: Turn? = nil) -> Presence { of(facts, agent, turn) }

    func of(_ facts: Presence.Facts, _ agent: Agent?, _ turn: Turn? = nil) -> Presence {
        Presence(facts, agent: agent, turn: turn, now: now)
    }

    @Test func theStateTableNeverGuesses() {
        let table: [(Presence, Sign.State, Presence.Stuck?)] = [
            (of(agent("unknown")), .unknown, .unknown),
            (of(agent("idle", alive: nil)), .unknown, .unknown),
            (of(agent("interrupted", alive: nil)), .unknown, .unknown),
            (of(agent("idle")), .listen, nil),
            (of(agent("interrupted")), .listen, nil),
            (of(agent("working")), .think, nil),
            (of(agent("waiting")), .wait, nil),
            (of(agent("working", retry: true)), .limit, .cannotReachModel),
            (of(agent("error")), .limit, .cannotReachModel),
            (of(agent("error", alive: false, error: true)), .limit, .crashed),
            (of(agent("interrupted", alive: false)), .limit, .crashed),
            (of(agent("done", alive: false)), .sleep, nil),
            (of(agent("done")), .sleep, nil),
            (of(nil), .sleep, nil),
            (of(Presence.Facts(name: "Claude Code", stopped: true), agent("idle")), .sleep, nil),
            (of(Presence.Facts(name: "Claude Code", waking: true), nil), .sleep, nil),
            (of(Presence.Facts(name: "Codex", installed: false), agent("idle")), .limit, .missing),
            (of(Presence.Facts(name: "Claude Code", failure: "Claude Code failed: the program stopped at once."), nil), .limit, .crashed),
        ]
        for (presence, state, stuck) in table {
            #expect((presence.state, presence.stuck) == (state, stuck), "\(presence.word)")
        }
    }

    @Test func theLineSaysTheRunningToolInThePresentTense() {
        let lines: [(Item?, String)] = [
            (tool("Read", "/Users/example/something/spaces/brief.html", "running"), "Reading brief.html…"),
            (tool("Edit", "/Users/example/something/spaces/brief.html", "running"), "Editing brief.html…"),
            (tool("apply_patch", "brief.html\nagents.html", "running"), "Changing files…"),
            (tool("Bash", "something check brief", "running"), "Checking the page…"),
            (tool("mcp__something__something_check", "something check brief", "running"), "Checking the page…"),
            (tool("Bash", "something guide --print", "running"), "Reading the guide…"),
            (tool("Bash", "ls", "running"), "Running a command…"),
            (tool("WebSearch", "weather", "running"), "Working…"),
            (tool("Edit", "/Users/example/something/spaces/brief.html", "done"), "Working…"),
            (nil, "Working…"),
        ]
        for (item, words) in lines {
            let presence = of(agent("working"), turn(started: 2, item.map { [$0] } ?? []))
            #expect(presence.now == .working(words, late: false))
            #expect(presence.word == words)
            #expect(presence.header == "Working", "the line already says what it does")
        }
    }

    @Test func stopIsOfferedOnceTenSecondsWentBy() {
        #expect(of(agent("working"), turn(started: 9)).now == .working("Working…", late: false))
        #expect(of(agent("working"), turn(started: 10)).now == .working("Working…", late: true))
        #expect(of(agent("working"), Turn(id: "t1", state: "working", started: nil, ended: nil, items: [])).now == .working("Working…", late: false),
                "a start nobody gives is not late")
        #expect(of(agent("working")).stopHelp == Keys.tooltip("stop"))
        var stubborn = agent("working")
        stubborn.can.interrupt = false
        #expect(of(stubborn).stopHelp == "Stop ends Claude Code, which can't pause mid-task; your next message starts it again.")
    }

    @Test func aFinishedTurnSaysWhatItChangedForThreeSecondsAndAHalf() {
        let edits = [tool("Read", "/Users/example/something/spaces/brief.html"), tool("Edit", "/Users/example/something/spaces/brief.html"),
                     tool("Write", "/Users/example/something/spaces/notes.html", "failed")]
        let done = of(agent("idle"), turn("done", started: 20, ended: 3, edits))
        #expect((done.state, done.now, done.header) == (.done, .changed("brief.html"), "Done"))
        #expect(done.word == "Just finished · changed brief.html")
        let quiet = of(agent("idle"), turn("done", started: 20, ended: 1, [tool("Read", "brief.html")]))
        #expect((quiet.state, quiet.now, quiet.header) == (.done, nil, "Just finished"))
        let later = of(agent("idle"), turn("done", started: 20, ended: 4, edits))
        #expect((later.state, later.now, later.word) == (.listen, nil, "Listening"))
        #expect(of(agent("idle"), turn("interrupted", started: 20, ended: 1, edits)).state == .listen, "a stopped turn is not done")
    }

    @Test func eachStuckKindSaysWhatIsBrokenAndNothingMore() {
        let missing = of(Presence.Facts(name: "Codex", installed: false), nil)
        #expect(missing.word == "Codex isn't on this Mac")
        #expect(missing.notice?.text == "something launches the agent you already use. Install Codex, or choose another one for this space.")

        var crashed = agent("error", alive: false, error: true)
        let crash = iso8601.date(from: crashed.updated ?? "")!
        #expect(of(crashed).word == "Stopped unexpectedly")
        #expect(of(crashed).notice == .init(title: "The assistant stopped",
                                          text: "Claude Code quit unexpectedly at \(Presence.clock.string(from: crash)). Starting again begins a new conversation."))
        crashed.can.resume = true
        #expect(of(crashed).notice?.text.hasSuffix("Your conversation is kept; starting again picks it up.") == true)
        let failed = of(Presence.Facts(name: "Claude Code", failure: "Claude Code failed: the program stopped at once."), nil)
        #expect(failed.notice?.text == "Claude Code failed: the program stopped at once.")

        let retrying = of(agent("working", retry: true), turn())
        #expect(retrying.word == "Stopped · can't reach its model")
        #expect(retrying.now == nil)
        #expect(retrying.notice?.text == "Opus 4.7 did not answer; Claude Code keeps trying. Your last message is kept and nothing in the space changed.")
        #expect(of(agent("error"), turn("error", [tool("Edit", "brief.html")])).notice?.text == "Opus 4.7 did not answer. Your last message is kept.",
                "a turn that changed a file does not say nothing changed")

        let unknown = of(agent("unknown"))
        #expect(unknown.word == "State unknown · something cannot read it")
        #expect(unknown.notice?.text == "Claude Code gave no sign for 4 minutes. It may still be working; something will not guess.")
        var silent = agent("unknown")
        silent.updated = nil
        #expect(of(silent).notice?.text == "Claude Code gave no sign. It may still be working; something will not guess.")
    }

    @Test func theStickerSaysWhoseAssistantItIsAndItsState() {
        #expect(of(agent("idle")).label("Daily brief") == "Assistant of Daily brief, Listening. Open with ⌘K")
        #expect(of(nil).label("Logbook") == "Assistant of Logbook, Asleep · wakes on your next message. Open with ⌘K")
        let waking = of(Presence.Facts(name: "Claude Code", waking: true), nil)
        #expect((waking.now, waking.header) == (.waking, "Waking up…"))
        #expect(of(agent("waiting")).header == "Waiting for you")
    }
}
