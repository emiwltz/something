// Engine for launched agents, end to end, with a fake `claude`: a /bin/sh script in a throwaway folder that speaks
// the stream-json lines of the real one (keys as recorded in Tests/Exchanges/claude, text invented) and writes the
// arguments and environment it was given to a file, so the launch line can be checked.
import Foundation
import Testing
@testable import SomethingAgents
import SomethingCore

@MainActor struct EngineTests {
    static let fake = #"""
    #!/bin/sh
    printf '%s\n' "$@" > "$FAKE_OUT/arguments"
    env > "$FAKE_OUT/environment"
    while IFS= read -r line; do
      case "$line" in
        *'"subtype":"initialize"'*)
          echo '{"type":"control_response","response":{"subtype":"success","request_id":"something-1","response":{"current_permission_mode":"default","models":[{"value":"default","displayName":"Default (recommended)"},{"value":"sonnet","displayName":"Sonnet"}]}}}' ;;
        *'"type":"user"'*)
          echo '{"type":"system","subtype":"session_state_changed","state":"running","uuid":"u1","session_id":"s1"}'
          echo '{"type":"system","subtype":"init","cwd":"/Users/example/shop","session_id":"s1","model":"claude-example","permissionMode":"default"}'
          echo '{"type":"assistant","message":{"id":"msg_1","model":"claude-example","role":"assistant","content":[{"type":"text","text":"Invented reply."}]},"parent_tool_use_id":null,"uuid":"u2","session_id":"s1"}'
          echo '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","result":"Invented reply.","session_id":"s1","uuid":"u3"}'
          echo '{"type":"system","subtype":"session_state_changed","state":"idle","uuid":"u4","session_id":"s1"}' ;;
        *'"subtype":"end_session"'*)
          echo '{"type":"control_response","response":{"subtype":"success","request_id":"something-end"}}'
          exit 0 ;;
      esac
    done
    """#

    final class Place {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("engine-\(UUID().uuidString)")
        var bin: URL { root.appendingPathComponent("bin") }
        var work: URL { root.appendingPathComponent("work/shop") }
        var out: URL { root.appendingPathComponent("out") }
        var environment: [String: String] {
            ["HOME": root.path, "PATH": "\(bin.path):/usr/bin:/bin", "FAKE_OUT": out.path, "SHELL": "/bin/sh",
             "ANTHROPIC_API_KEY": "test-key", "ANTHROPIC_AUTH_TOKEN": "test-token"]
        }

        init() throws {
            for folder in [bin, work, out] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
            let program = bin.appendingPathComponent("claude")
            try EngineTests.fake.write(to: program, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
        }

        deinit { try? FileManager.default.removeItem(at: root) }
    }

    func until(_ what: String, seconds: Double = 10, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < end else { Issue.record("timed out waiting for \(what)"); throw CancellationError() }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @Test func aLaunchedClaudeTalksStopsAndIsShown() async throws {
        let place = try Place()
        // The fake must be the program found, never the real one of this Mac.
        #expect(try Programs(environment: place.environment).find("claude").path == place.bin.appendingPathComponent("claude").path)
        let engine = Engine(environment: place.environment)
        var changes = 0
        engine.changed = { changes += 1 }
        let id = try engine.launch("claude", folder: place.work.path, model: nil, mode: "plan", effort: nil)
        #expect(engine.state.agents.map(\.id) == [id])
        #expect(engine.state.kinds["claude"]?.launch == true)
        #expect(engine.state.kinds["claude"]?.tested == ClaudeDriver.tested)
        #expect(engine.state.kinds["codex"]?.launch == false)
        #expect(engine.limits["claude"] == ["effort"])
        try await until("the models") { engine.state.agents.first?.options.model != nil }

        #expect(try engine.deliver("Hello.", to: id, when: "next") == "started")
        try await until("the reply") { engine.state.agents.first?.state == "idle" && engine.state.threads.first?.turns.first?.items.count == 2 }
        let agent = try #require(engine.state.agents.first)
        #expect((agent.origin, agent.alive, agent.evidence, agent.model) == ("launched", true, "child", "claude-example"))
        #expect(engine.state.threads.first?.turns.first?.items.map(\.text) == ["Hello.", "Invented reply."])
        #expect(changes > 0)

        let arguments = try String(contentsOf: place.out.appendingPathComponent("arguments"), encoding: .utf8).split(separator: "\n")
        #expect(Array(arguments.prefix(4)) == ["-p", "--input-format", "stream-json", "--output-format"])
        #expect(arguments.contains("--session-id") && arguments.contains("plan"))
        let environment = try String(contentsOf: place.out.appendingPathComponent("environment"), encoding: .utf8).split(separator: "\n")
        #expect(environment.contains("CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS=1"))
        #expect(!environment.contains { $0.hasPrefix("ANTHROPIC_API_KEY=") || $0.hasPrefix("ANTHROPIC_AUTH_TOKEN=") })

        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        try await until("the stop") { stopped }
        #expect(engine.state.agents.first?.state == "done")
        #expect(engine.state.agents.first?.error == nil)
        #expect(throws: CodedError("AGENT_STOPPED", "The agent has ended; launch or resume it to go on.")) {
            try engine.deliver("Late.", to: id, when: "next")
        }
    }

    @Test func whatALaunchRefuses() throws {
        let place = try Place()
        let engine = Engine(environment: place.environment)
        #expect(throws: CodedError.self) { try engine.launch("codex", folder: place.work.path, model: nil, mode: nil, effort: nil) }
        #expect(throws: CodedError("VALUE_NOT_OFFERED", "bypassPermissions is not a mode something offers for claude; pick one of default, acceptEdits, plan, auto, dontAsk.")) {
            try engine.launch("claude", folder: place.work.path, model: nil, mode: "bypassPermissions", effort: nil)
        }
        #expect(throws: CodedError("NOT_SUPPORTED", "something cannot change Claude Code's effort yet.")) {
            try engine.launch("claude", folder: place.work.path, model: nil, mode: nil, effort: "low")
        }
        #expect(throws: CodedError("AGENT_NOT_FOUND", "No agent claude-9 was launched by something; use an id from the latest state.")) {
            try engine.interrupt("claude-9")
        }
        #expect(engine.state.agents.isEmpty)
    }
}
