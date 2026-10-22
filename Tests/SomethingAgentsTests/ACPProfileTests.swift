// ACPProfile: an agent over the Agent Client Protocol is a profile and a descriptor, nothing more. An invented one,
// written here as a new agent would be, is driven over OpenCode's recorded exchanges (Tests/Exchanges/opencode): the
// protocol's lines go out byte for byte as they did for OpenCode, what is said names the invented agent, and what
// OpenCode does its own way (its question tool, its sub-agents' key, its claim, its last model) does not follow.
import Foundation
import Testing
@testable import SomethingAgents
@testable import AgentACP
import SomethingCore

extension ACPProfile {
    /// An invented agent, started by `invented --acp`, that names its effort "reasoning_effort".
    static let invented = ACPProfile(kind: "invented", name: "Invented Agent", tested: "1.0.0", arguments: ["--acp"],
                                     environment: ["INVENTED_NO_UPDATE": "1"], signIn: "invented login",
                                     modes: [Option(value: "build", label: "Build")], effortCategory: "reasoning_effort")
}

extension AgentDescriptor {
    static let invented = AgentDescriptor(kind: "invented", name: "Invented Agent", install: "brew install invented",
                                          asksAsMuch: ["build"], driving: ACPProfile.invented.driving, tools: ACPProfile.tools)
}

@Suite struct ACPProfileTests {
    static func play(_ name: String, database: String? = nil) throws -> Replay {
        try Replay.play(name, kind: "opencode", database: database, driving: ACPProfile.invented.driving)
    }

    @Test func aProfileIsAllANewAgentNeeds() throws {
        let driving = try Registry([.invented]).driving("invented")
        #expect(driving.command(Launch(agent: "invented-1", folder: "/Users/example/shop"))
            == Command(arguments: ["--acp"], adding: ["INVENTED_NO_UPDATE": "1"]))
        #expect(driving.tested == "1.0.0")
        #expect(driving.limits == ["steer": "Invented Agent cannot take a message during a turn; send it with when: \"next\"."])
        #expect(!driving.picksThread && driving.effortOnlyWhenOffered && !driving.listsMoreModes)
        #expect(String(describing: type(of: Replay.opencode(driving: driving).agent.driver)) == "ACPDriver")
    }

    /// The effort is read under the profile's own category: OpenCode's "thought_level" is not this agent's effort.
    @Test func aTurn() throws {
        let replay = try Self.play("turn")
        let agent = replay.fold.agent
        #expect(agent.kind == "invented")
        #expect(replay.items.map(\.author) == ["person", "agent"])
        #expect((agent.model, agent.mode, agent.effort) == ("fake/fake-model", "build", nil))
        #expect(agent.options.effort == nil)
        #expect(replay.agent.agent.can.effort == false)
        #expect(agent.state == "done")
    }

    @Test func whatIsSaidNamesTheAgent() throws {
        #expect(try Self.play("deny").fold.agent.error?.message
            == "Invented Agent stopped its turn because its request “touch invented.txt” was refused. Tell it what to do instead in a new message.")
        #expect(ACPProfile.invented.failure(["code": -32000], "Authentication required", "Hello.", model: "fake/fake-model", picked: false)
            == "Invented Agent's model fake/fake-model needs a sign-in to fake, which Invented Agent does not have. Sign in to fake in Invented Agent (`invented login` in a terminal) and send the message again.")
        #expect(try Self.play("resume-missing").fold.agent.error?.code == "THREAD_NOT_FOUND", "the protocol's default words")
    }

    /// Without a question tool in its profile, a question that failed is a tool like any other: the turn the agent
    /// cancelled after it ends without a reason given.
    @Test func noQuestionToolIsNoQuirk() throws {
        let replay = try Self.play("question")
        #expect(replay.items.first { $0.kind == "tool" }?.tool == Tool(name: "question", status: "failed"))
        #expect(replay.fold.agent.error == AgentError(code: "AGENT_ERROR", message: "Invented Agent stopped its turn before the end without saying why."))
    }

    /// OpenCode's claim is OpenCode's: the same database, marking the session as running, says nothing of this agent.
    @Test func noClaimWithoutItsQuirk() throws {
        let folder = try ACPDriverTests.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let replay = try Self.play("killed", database: try ACPDriverTests.database(claimed: "ses_eb42d0ee4ffeck9Fs9cn1jngw7", in: folder))
        #expect(replay.fold.agent.error == AgentError(code: "AGENT_ERROR", message: "Invented Agent ended (code 137)."))
    }

    /// Without a key for its sub-agents, nothing in `_meta` makes an update a sub-agent's.
    @Test func noChildKeyIsNoSubAgent() throws {
        let replay = Replay.opencode(driving: ACPProfile.invented.driving)
        replay.feed(["jsonrpc": "2.0", "id": 1, "result": ["protocolVersion": 1]])
        replay.feed(["jsonrpc": "2.0", "id": 2, "result": ["sessionId": ACPDriverTests.session, "configOptions": []]])
        _ = try replay.agent.send("Hello.", when: "next")
        replay.feed(ACPDriverTests.update(["sessionUpdate": "agent_message_chunk", "messageId": "c1", "content": ["type": "text", "text": "Child."],
                                           "_meta": ["opencode/child-session": ["id": "ses_child"]]]))
        #expect(replay.items.map(\.kind) == ["message", "message"])
    }
}
