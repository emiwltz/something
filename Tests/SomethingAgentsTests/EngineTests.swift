// Engine for launched agents, end to end, with a fake `claude`, a fake `codex` and a fake `opencode`: /bin/sh scripts in a throwaway
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

    /// A fake `opencode acp`: answers each call by its id, as 2.0.20 does (Tests/Exchanges/opencode), text invented.
    /// A message holding "wait" is answered only when something cancels it.
    static let fakeOpenCode = #"""
    #!/bin/sh
    printf '%s\n' "$@" > "$FAKE_OUT/arguments"
    session='"sessionId":"ses_invented0000000000000001"'
    options='"configOptions":[{"id":"model","category":"model","currentValue":"fake/fake-model","options":[{"value":"fake/fake-model","name":"fake/Fake Model"}]}]'
    while IFS= read -r line; do
      id=$(printf '%s' "$line" | sed -n 's/^{"id":\([0-9]*\),.*/\1/p')
      case "$line" in
        *'"method":"initialize"'*) echo "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{\"protocolVersion\":1}}" ;;
        *'"method":"session/new"'*) echo "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{$session,$options}}" ;;
        *'"method":"session/prompt"'*'wait'*) waiting=$id ;;
        *'"method":"session/prompt"'*)
          echo "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{$session,\"update\":{\"sessionUpdate\":\"agent_message_chunk\",\"messageId\":\"m$id\",\"content\":{\"type\":\"text\",\"text\":\"Invented reply.\"}}}}"
          echo "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{\"stopReason\":\"end_turn\"}}" ;;
        *'"method":"session/cancel"'*)
          echo cancel >> "$FAKE_OUT/cancels"
          echo "{\"jsonrpc\":\"2.0\",\"id\":$waiting,\"result\":{\"stopReason\":\"cancelled\"}}" ;;
      esac
    done
    echo closed > "$FAKE_OUT/closed"
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
            let opencode = bin.appendingPathComponent("opencode")
            try EngineTests.fakeOpenCode.write(to: opencode, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: opencode.path)
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
        let engine = Engine.throwaway(place.environment)
        var changes = 0
        engine.changed = { changes += 1 }
        let id = try engine.launch("claude", folder: place.work.path, model: nil, mode: "plan", effort: nil)
        #expect(engine.state.agents.map(\.id) == [id])
        #expect(engine.state.kinds["claude"]?.launch == true)
        #expect(engine.state.kinds["claude"]?.tested == ClaudeDriver.tested)
        #expect(engine.state.kinds["codex"]?.launch == true)
        #expect(engine.state.kinds["opencode"]?.launch == true)
        #expect(engine.state.kinds["pi"]?.launch == true)
        #expect(engine.state.kinds["omp"]?.launch == false)
        #expect(Engine.limits == ["opencode": ["steer"], "pi": ["mode"]], "Claude and Codex have no limit left")
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
        let engine = Engine.throwaway(place.environment)
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

    /// OpenCode through the engine: a turn, then a stop during a turn: the ladder cancels it, then closes the input,
    /// and OpenCode ends without a signal.
    @Test func aLaunchedOpenCodeTalksAndStopsByCancelling() async throws {
        let place = try Place()
        #expect(try Programs(environment: place.environment).find("opencode").path == place.bin.appendingPathComponent("opencode").path)
        let engine = Engine.throwaway(place.environment)
        let id = try engine.launch("opencode", folder: place.work.path, model: nil, mode: nil, effort: nil)
        #expect(id == "opencode-1")
        try await until("the session") { engine.state.agents.first?.thread == "ses_invented0000000000000001" }
        #expect(engine.state.agents.first?.model == "fake/fake-model")
        #expect(try engine.deliver("Hello.", to: id, when: "next") == "started")
        try await until("the reply") { engine.state.threads.first?.turns.first?.state == "done" }
        #expect(engine.state.threads.first?.turns.first?.items.map(\.text) == ["Hello.", "Invented reply."])
        #expect(try engine.deliver("Please wait.", to: id, when: "next") == "started")
        #expect(throws: CodedError("NOT_SUPPORTED", ACPDriver.limits["steer"]!)) { try engine.deliver("Now.", to: id, when: "now") }
        #expect(try String(contentsOf: place.out.appendingPathComponent("arguments"), encoding: .utf8) == "acp\n")
        var stopped = false
        let begun = Date()
        engine.stopAll(within: 6) { stopped = true }
        #expect(throws: CodedError("AGENT_STOPPED", "The agent is stopping; launch or resume it to go on."), "no turn opens after the stop's cancel") {
            try engine.deliver("Too late.", to: id, when: "next")
        }
        try await until("the stop") { stopped }
        // Spawn gives the graceful step 3 s: ending under that shows the cancel's answer ended it, not the cap. The
        // answer reaches the main queue, which the window suites keep busy while the whole suite runs (2.7 s seen).
        #expect(Date().timeIntervalSince(begun) < 3, "the cancel's answer ends the first step before Spawn's cap")
        #expect(FileManager.default.fileExists(atPath: place.out.appendingPathComponent("cancels").path))
        #expect(FileManager.default.fileExists(atPath: place.out.appendingPathComponent("closed").path), "its input was closed: no signal")
        #expect(engine.state.agents.first?.state == "interrupted")
        #expect(engine.state.agents.first?.error == nil, "this home has no OpenCode database: no claim is said")
    }

    /// The modes that make an agent ask less are confirmed by the person; an unknown OpenCode agent is too. A mode
    /// Claude or Codex is never given here is refused before any window.
    @Test func whichModesLowerAsking() throws {
        for mode in ["acceptEdits", "auto", "dontAsk"] { #expect(try Engine.lowersAsking(mode: mode, kind: "claude")) }
        for mode in ["default", "plan"] { #expect(try !Engine.lowersAsking(mode: mode, kind: "claude")) }
        #expect(try Engine.lowersAsking(mode: "never", kind: "codex") && !Engine.lowersAsking(mode: "on-request", kind: "codex"))
        #expect(try !Engine.lowersAsking(mode: "untrusted", kind: "codex"))
        #expect(try Engine.lowersAsking(mode: "default", kind: "pi"), "pi takes no mode: one asked for is confirmed, never guessed")
        #expect(try !Engine.lowersAsking(mode: "build", kind: "opencode") && !Engine.lowersAsking(mode: "plan", kind: "opencode"))
        #expect(try Engine.lowersAsking(mode: "invented-agent", kind: "opencode"))
        #expect(try Engine.lowersAsking(mode: "anything", kind: "other"))
        for (mode, kind) in [("bypassPermissions", "claude"), ("manual", "claude"), ("acceptedits", "claude"), ("granular", "codex")] {
            #expect(throws: CodedError.self, "\(mode)") { try Engine.lowersAsking(mode: mode, kind: kind) }
        }
    }

    /// start(often:) again changes the cadence only: the programs are looked for once.
    @Test func startIsCalledAgain() async throws {
        let place = try Place()
        let engine = Engine.throwaway(place.environment)
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
        let engine = Engine.throwaway(place.environment)
        #expect(throws: CodedError("NOT_SUPPORTED", "something cannot launch omp yet.")) {
            try engine.launch("omp", folder: place.work.path, model: nil, mode: nil, effort: nil)
        }
        #expect(throws: CodedError("NOT_SUPPORTED", PiDriver.limits["mode"]!)) {
            try engine.launch("pi", folder: place.work.path, model: nil, mode: "plan", effort: nil)
        }
        // pi given a missing file would start an empty conversation there: the file is checked before pi is looked for.
        // Nor is a file that is not a pi conversation (its first line is no session header).
        let other = place.work.appendingPathComponent("notes.jsonl"), empty = place.work.appendingPathComponent("empty.jsonl")
        try Data(#"{"type":"message","cwd":"/Users/example/shop"}"#.utf8).write(to: other)
        try Data().write(to: empty)
        for missing in ["/Users/example/.pi/agent/sessions/--Users-example-shop--/missing.jsonl", "relative.jsonl", place.work.path, other.path, empty.path] {
            #expect(throws: CodedError("THREAD_NOT_FOUND", "pi has no saved conversation with this id on this Mac.")) {
                try engine.launch(PiDriver.self, folder: place.work.path, model: nil, mode: nil, effort: nil, planB: false, resume: missing)
            }
        }
        #expect(throws: CodedError("VALUE_NOT_OFFERED", "auto is not a mode something offers for opencode; pick one of build, plan.")) {
            try engine.launch("opencode", folder: place.work.path, model: nil, mode: "auto", effort: nil)
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
