// Engine for launched agents, end to end, with a fake `claude` and a fake `codex`: /bin/sh scripts in a throwaway
// folder that speak the lines of the real ones (keys as recorded in Tests/Exchanges, text invented) and write the
// arguments (and environment) they were given to a file, so the launch line can be checked.
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

    /// A fake `codex app-server`: answers each call by its id, as 0.163.0 does (Tests/Exchanges/codex), text invented.
    static let fakeCodex = #"""
    #!/bin/sh
    printf '%s\n' "$@" > "$FAKE_OUT/arguments"
    thread='"threadId":"01a14bae-0000-7000-8000-000000000001"'
    while IFS= read -r line; do
      id=$(printf '%s' "$line" | sed -n 's/^{"id":\([0-9]*\),.*/\1/p')
      case "$line" in
        *'"method":"initialize"'*) echo "{\"id\":$id,\"result\":{\"userAgent\":\"something/0.163.0\"}}" ;;
        *'"method":"thread/start"'*)
          # Codex reports the policy it was given, or its own default.
          policy=$(printf '%s' "$line" | sed -n 's/.*"approvalPolicy":"\([a-z-]*\)".*/\1/p')
          echo "{\"id\":$id,\"result\":{\"thread\":{\"id\":\"01a14bae-0000-7000-8000-000000000001\"},\"model\":\"fake-model\",\"approvalPolicy\":\"${policy:-on-request}\",\"reasoningEffort\":null}}" ;;
        *'"method":"model/list"'*) echo "{\"id\":$id,\"result\":{\"data\":[{\"id\":\"fake-model\",\"model\":\"fake-model\",\"displayName\":\"Fake\",\"hidden\":false,\"supportedReasoningEfforts\":[{\"reasoningEffort\":\"low\",\"description\":\"Invented.\"}]}]}}" ;;
        *'"method":"turn/start"'*)
          echo "{\"id\":$id,\"result\":{\"turn\":{\"id\":\"t1\",\"status\":\"inProgress\",\"items\":[]}}}"
          echo "{\"method\":\"thread/status/changed\",\"params\":{$thread,\"status\":{\"type\":\"active\",\"activeFlags\":[]}}}"
          echo "{\"method\":\"turn/started\",\"params\":{$thread,\"turn\":{\"id\":\"t1\",\"status\":\"inProgress\"}}}"
          echo "{\"method\":\"item/completed\",\"params\":{$thread,\"item\":{\"type\":\"userMessage\",\"id\":\"u1\",\"content\":[{\"type\":\"text\",\"text\":\"Hello.\"}]}}}"
          echo "{\"method\":\"item/completed\",\"params\":{$thread,\"item\":{\"type\":\"agentMessage\",\"id\":\"m1\",\"text\":\"Invented reply.\",\"phase\":null}}}"
          echo "{\"method\":\"thread/status/changed\",\"params\":{$thread,\"status\":{\"type\":\"idle\"}}}"
          echo "{\"method\":\"turn/completed\",\"params\":{$thread,\"turn\":{\"id\":\"t1\",\"status\":\"completed\"}}}" ;;
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
            let codex = bin.appendingPathComponent("codex")
            try EngineTests.fakeCodex.write(to: codex, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)
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
        #expect(engine.state.kinds["codex"]?.launch == true)
        #expect(engine.state.kinds["opencode"]?.launch == false)
        #expect(engine.limits["claude"] == nil && engine.limits["codex"] == nil, "Claude and Codex have no limit left")
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

    /// Codex through the engine: launched with its mode, a turn, its input closed at the stop, which ends it cleanly.
    @Test func aLaunchedCodexTalksAndStops() async throws {
        let place = try Place()
        #expect(try Programs(environment: place.environment).find("codex").path == place.bin.appendingPathComponent("codex").path)
        let engine = Engine(environment: place.environment)
        let id = try engine.launch("codex", folder: place.work.path, model: nil, mode: "untrusted", effort: nil)
        #expect(id == "codex-1")
        try await until("the thread") { engine.state.agents.first?.thread != nil && engine.state.agents.first?.options.model != nil }
        #expect(engine.state.agents.first?.mode == "untrusted")
        #expect(engine.state.agents.first?.options.effort?.map(\.value) == ["low"])
        #expect(try engine.deliver("Hello.", to: id, when: "next") == "started")
        try await until("the reply") { engine.state.threads.first?.turns.first?.state == "done" }
        #expect(engine.state.threads.first?.turns.first?.items.map(\.text) == ["Hello.", "Invented reply."])
        #expect(try engine.set(id, model: nil, mode: "on-request", effort: nil) == "next-turn")
        let arguments = try String(contentsOf: place.out.appendingPathComponent("arguments"), encoding: .utf8)
        #expect(arguments == "app-server\n")
        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        try await until("the stop") { stopped }
        #expect(engine.state.agents.first?.state == "done")
        #expect(engine.state.agents.first?.error == nil)
    }

    /// The modes that make an agent ask less are confirmed by the person; an unknown mode is too.
    @Test func whichModesLowerAsking() {
        let engine = Engine(environment: [:])
        for mode in ["acceptEdits", "auto", "dontAsk", "bypassPermissions"] { #expect(engine.lowersAsking(mode: mode, kind: "claude")) }
        for mode in ["default", "manual", "plan"] { #expect(!engine.lowersAsking(mode: mode, kind: "claude")) }
        #expect(engine.lowersAsking(mode: "never", kind: "codex") && !engine.lowersAsking(mode: "on-request", kind: "codex"))
        #expect(!engine.lowersAsking(mode: "untrusted", kind: "codex"))
        #expect(engine.lowersAsking(mode: "default", kind: "pi"), "pi takes no mode: one asked for is confirmed, never guessed")
        #expect(!engine.lowersAsking(mode: "build", kind: "opencode") && !engine.lowersAsking(mode: "plan", kind: "opencode"))
        #expect(engine.lowersAsking(mode: "invented-agent", kind: "opencode"))
        #expect(engine.lowersAsking(mode: "anything", kind: "other"))
    }

    /// start(often:) again changes the cadence only: the programs are looked for once.
    @Test func startIsCalledAgain() async throws {
        let place = try Place()
        let engine = Engine(environment: place.environment)
        var changes = 0
        engine.changed = { changes += 1 }
        engine.start(often: false)
        engine.start(often: true)
        #expect(engine.often)
        try await until("the programs") { engine.state.kinds["claude"]?.installed == true }
        engine.start(often: true)
        engine.start(often: false)
        #expect(!engine.often)
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(changes == 1)
        #expect(engine.state.kinds["omp"]?.installed != nil, "omp's file is looked for")
    }

    /// Plan B's spools are in the person's Application Support, never in $TMPDIR, which a sandboxed agent may write.
    @Test func theSpoolsAreNotInTheTemporaryFolder() {
        #expect(Spool.root.hasSuffix("/Library/Application Support/something/spool"))
        #expect(!Spool.root.hasPrefix(NSTemporaryDirectory()))
    }

    @Test func whatALaunchRefuses() throws {
        let place = try Place()
        let engine = Engine(environment: place.environment)
        #expect(throws: CodedError("NOT_SUPPORTED", "something cannot launch opencode yet.")) {
            try engine.launch("opencode", folder: place.work.path, model: nil, mode: nil, effort: nil)
        }
        #expect(throws: CodedError("VALUE_NOT_OFFERED", "bypassPermissions is not a mode something offers for claude; pick one of default, acceptEdits, plan, auto, dontAsk.")) {
            try engine.launch("claude", folder: place.work.path, model: nil, mode: "bypassPermissions", effort: nil)
        }
        #expect(throws: CodedError("BAD_PARAMS", "effort is a level's name, such as one of the agent's options.effort.")) {
            try engine.launch("claude", folder: place.work.path, model: nil, mode: nil, effort: "")
        }
        #expect(throws: CodedError("BAD_PARAMS", "model is a model's name, such as one of the agent's options.model.")) {
            try engine.launch("claude", folder: place.work.path, model: "--dangerously-skip-permissions", mode: nil, effort: nil)
        }
        #expect(throws: CodedError("AGENT_NOT_FOUND", "No agent claude-9 was launched by something; use an id from the latest state.")) {
            try engine.interrupt("claude-9")
        }
        #expect(engine.state.agents.isEmpty)
    }
}
