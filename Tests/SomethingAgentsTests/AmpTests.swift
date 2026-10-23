// Amp over its stream-json channel: its driver played over its own recorded exchanges (Tests/Exchanges/amp, trial C6
// against the real amp 0.0.1792656060): every line something wrote goes out byte for byte as it did, and what Amp said
// folds as it showed. Amp never asks, takes a message during a turn, and cannot stop a turn; something's tools reach it
// over MCP, through its code_exec tool.
import Foundation
import Testing
@testable import SomethingAgents
@testable import AgentAmp
import SomethingCore

@Suite struct AmpTests {
    static func play(_ name: String) throws -> Replay { try Replay.play(name, kind: "amp") }

    @Test func itIsDrivenAndBuildsWithoutAsking() throws {
        let amp = try #require(Registry.described.agent("amp"))
        let driving = try Registry.described.driving("amp")
        let arguments = ["--execute", "--stream-json", "--stream-json-input", "--stream-json-thinking", "--no-ide"]
        #expect(driving.command(Launch(agent: "amp-1", folder: "/Users/example/shop")) == Command(arguments: arguments))
        #expect(!driving.picksThread && driving.modes.isEmpty && driving.limits.keys.sorted() == ["effort", "interrupt", "mode", "model"])
        #expect(amp.neverAsks && amp.builder?.lent.map(\.name) == LentTool.all.map(\.name) && amp.builder?.preAllowed == false)
        #expect(amp.resume == .never && amp.tools.isEmpty)
        // The assistant's launch gives Amp something's server by name, the shape Amp takes (not Claude Code's mcpServers).
        let config = try #require(driving.command(Self.assistantLaunch).arguments.last)
        let server = try #require(try JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: [String: Any]])
        #expect(server.keys.sorted() == ["something"] && server["something"]?["command"] as? String == "/Users/example/tools/something")
        #expect(server["something"]?["args"] as? [String] == ["mcp"] && server["something"]?["env"] as? [String: String] == ["SOMETHING_HOME": "/Users/example"])
    }

    static var assistantLaunch: Launch {
        var launch = Launch(agent: "amp-1", folder: "/Users/example/something/spaces")
        (launch.assistant, launch.lent) = (.building, Lent.own("/Users/example/tools/something", tools: LentTool.all,
                                                               environment: ["SOMETHING_HOME": "/Users/example"], refused: { _, _ in }))
        return launch
    }

    /// The thread is Amp's, named with the first message; a patch shows the file it adds; Amp's agent mode is its mode.
    @Test func aTurn() throws {
        let replay = try Self.play("turn")
        let agent = replay.fold.agent
        #expect(agent.kind == "amp" && agent.error == nil && agent.alive == false)
        #expect(agent.thread == "T-01a10000-0000-7000-8000-000000000001" && agent.mode == "medium" && agent.model == nil)
        #expect(replay.fold.turns.map(\.state) == ["done"])
        #expect(replay.items.map(\.kind) == ["message", "message", "tool", "tool", "tool", "message"])
        #expect(replay.items.compactMap(\.tool) == [Tool(name: "shell_command", status: "done"), Tool(name: "apply_patch", status: "done"),
                                                    Tool(name: "shell_command", status: "done")])
        #expect(replay.items[3].text == "/Users/example/shop/fruit.txt" && replay.items.last?.text == "done")
        #expect(replay.items.first?.author == "person")
    }

    /// A steer goes into the running turn and shows where Amp took it; a message held for the next turn starts it
    /// when the first ends. An interrupt at rest stops nothing.
    @Test func aSteerAndAHeldMessage() throws {
        let replay = try Self.play("steer-queue")
        #expect(replay.fold.turns.map(\.state) == ["done", "done"])
        let people = replay.fold.turns.map { $0.items.filter { $0.author == "person" }.map(\.text) }
        #expect(people == [["Run the shell command sleep 4 three times, one call at a time, then reply with the word finished.",
                            "Also create a file named plum.txt here containing the word plum."],
                           ["Then reply with the single word second."]])
        #expect(replay.lines().map { $0["steer"] as? Bool } == [nil, true, nil])
        #expect(replay.fold.agent.error == nil)
    }

    /// The person's assistant calls something's tools from code_exec (its way to an MCP server), shown with the code it
    /// ran; the check found no problem, and nothing asked the person.
    @Test func theAssistantBuildsWithSomethingsTools() throws {
        let replay = try Self.play("assistant-build")
        let code = replay.items.filter { $0.tool?.name == "code_exec" }
        #expect(code.map(\.text).allSatisfy { $0.contains(#"from "something""#) } && code.count == 3)
        #expect(["something_guide", "something_new", "something_check"].allSatisfy { name in code.contains { $0.text.contains(name) } })
        #expect(replay.items.compactMap(\.tool).allSatisfy { $0.status == "done" })
        #expect(replay.fold.requests.isEmpty && replay.fold.turns.map(\.state) == ["done"] && replay.fold.agent.error == nil)
    }

    /// Amp's errors, from its own documentation's shapes (none was seen in a trial): one during a turn fails it, the
    /// run's result repeats it and is said once, and a program that ends before any line could not start.
    @Test func errorsAreSaidOnce() throws {
        let replay = Replay.amp()
        _ = try replay.agent.send("Invented question.", when: "next")
        replay.feed(["type": "system", "subtype": "error_during_execution", "error": "Invented failure.", "session_id": "T-invented"])
        #expect(replay.fold.turns.last?.state == "error" && replay.fold.agent.error?.message == "Amp: Invented failure.")
        replay.feed(["type": "result", "subtype": "error_during_execution", "is_error": true, "error": "Invented failure.", "duration_ms": 1,
                     "num_turns": 1, "session_id": "T-invented"])
        #expect(replay.fold.turns.count == 1)
        let failed = Replay.amp()
        failed.agent.ended(code: 1, errors: "error: unknown option '--invented'\n", asked: false)
        #expect(failed.fold.agent.error == AgentError(code: "LAUNCH_FAILED", message: "Amp could not start: error: unknown option '--invented'"))
    }

    /// The channel takes only messages: an interrupt, a model, a mode or an effort is refused in words.
    @Test func whatTheChannelCannotDoIsRefused() throws {
        let replay = Replay.amp()
        #expect(throws: CodedError("NOT_SUPPORTED", AmpDriver.noInterrupt)) { try replay.agent.driver.interrupt() }
        #expect(throws: CodedError("NOT_SUPPORTED", AmpDriver.noSettings)) { try replay.agent.driver.set(model: "x", mode: nil, effort: nil) }
        #expect(!replay.fold.agent.can.interrupt && !replay.fold.agent.can.model && replay.fold.agent.can.steer)
    }
}
