// Engine for launched agents, end to end, with a fake `claude`, a fake `codex` and a fake `opencode`: /bin/sh scripts in a throwaway
// folder that speak the lines of the real ones (keys as recorded in Tests/Exchanges, text invented) and write the
// arguments (and environment) they were given to a file, so the launch line can be checked.
import Foundation
import Testing
@testable import SomethingAgents
import SomethingCore

@MainActor @Suite(.leavesNothing("engine-")) struct EngineTests {
    nonisolated static let fake = #"""
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
    nonisolated static let fakeCodex = #"""
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
    /// A message holding "wait" is answered only when something cancels it; a model it is given is taken.
    nonisolated static let fakeOpenCode = #"""
    #!/bin/sh
    trap 'echo TERM > "$FAKE_OUT/signalled"; exit 143' TERM
    printf '%s\n' "$@" > "$FAKE_OUT/arguments"
    session='"sessionId":"ses_invented0000000000000001"'
    options() { echo '"configOptions":[{"id":"model","category":"model","currentValue":"'"$1"'","options":[{"value":"fake/fake-model","name":"fake/Fake Model"},{"value":"fake/other-model","name":"fake/Other Model"}]}]'; }
    while IFS= read -r line; do
      id=$(printf '%s' "$line" | sed -n 's/^{"id":\([0-9]*\),.*/\1/p')
      case "$line" in
        *'"method":"initialize"'*) echo "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{\"protocolVersion\":1}}" ;;
        *'"method":"session/new"'*) echo "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{$session,$(options fake/fake-model)}}" ;;
        *'"method":"session/set_config_option"'*)
          value=$(printf '%s' "$line" | sed -n 's/.*"value":"\([^"]*\)".*/\1/p')
          echo "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{$(options "$value")}}" ;;
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

    /// A throwaway home with fake programs. `prefix` names its folder in $TMPDIR; the default is EngineTests' own, and
    /// another suite passes its own, so that each suite's `.leavesNothing` counts only the folders it made.
    final class Place {
        let root: URL
        var bin: URL { root.appendingPathComponent("bin") }
        var work: URL { root.appendingPathComponent("work/shop") }
        var out: URL { root.appendingPathComponent("out") }
        var environment: [String: String] {
            ["HOME": root.path, "PATH": "\(bin.path):/usr/bin:/bin", "FAKE_OUT": out.path, "SHELL": "/bin/sh",
             "ANTHROPIC_API_KEY": "test-key", "ANTHROPIC_AUTH_TOKEN": "test-token"]
        }

        init(prefix: String = "engine-") throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)\(UUID().uuidString)")
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

        // Called with defer in each test: a deinit does not always run before the test process ends.
        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    func until(_ what: String, seconds: Double = 30, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < end else { Issue.record("timed out waiting for \(what)"); throw CancellationError() }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @Test func aLaunchedClaudeTalksStopsAndIsShown() async throws {
        let place = try Place()
        defer { place.remove() }
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

    /// The person's assistant: the app's launch carries the rules of E-1, on its folder's real path, and a space's launch
    /// never does; a space with every right, seeing every agent, finds the assistant listed but can write to it in no
    /// way (Bridge.visible). No conversation in its folder is shown as seen elsewhere, however its path is written:
    /// neither its own once the state forgot it, nor one of an earlier run; another agent's is.
    @Test func theAssistantIsTheAppsAloneAndNoSpaceWritesToIt() async throws {
        let place = try Place()
        defer { place.remove() }
        let engine = Engine.throwaway(place.environment)
        var now = Date()
        engine.clock = { now }
        func arguments() -> [String] {
            ((try? String(contentsOf: place.out.appendingPathComponent("arguments"), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        }
        // The spaces folder, given through a link, as a home behind one is.
        let spaces = place.work.appendingPathComponent("spaces"), link = place.work.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: spaces, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: spaces)
        engine.assistantFolder = link.path
        // something's own program, whose folder comes first in the assistant's PATH only.
        engine.hookCommand = ["/Users/example/tools/something", "hook", "permission"]
        func path() -> String? {
            ((try? String(contentsOf: place.out.appendingPathComponent("environment"), encoding: .utf8)) ?? "")
                .split(separator: "\n").first { $0.hasPrefix("PATH=") }.map { String($0.dropFirst(5)) }
        }
        let id = try engine.launchAssistant("claude", folder: link.path, askEverything: false)
        #expect(engine.assistants == [id])
        // The fake writes its arguments, then its environment: both are waited for.
        try await until("the assistant's launch") { arguments().contains("--session-id") && path() != nil }
        #expect(path()?.hasPrefix("/Users/example/tools:\(place.bin.path):") == true, "\(path() ?? "no PATH")")
        #expect(Array(arguments().drop { $0 != "--allowedTools" }) == ["--allowedTools"] + ClaudeDriver.building(HeldFiles.real(spaces.path)))
        try await until("the models") { engine.state.agents.first?.options.model != nil }

        let host = EngineHost(engine, folder: place.work.path)
        host.granted.rights = ["state", "send", "launch", "store"]
        for (method, params) in [("send", ["agent": id, "text": "Invented."]), ("interrupt", ["agent": id]), ("set", ["agent": id, "model": "sonnet"])] {
            let answer = Bridge.answer(["method": method, "params": params], host: host)
            #expect((answer["error"] as? [String: Any])?["code"] as? String == "READ_ONLY_AGENT", "\(method)")
        }
        #expect(Bridge.visible(host).agents.first { $0.id == id }?.can == Can())
        #expect(engine.state.threads.first { $0.agent == id }?.turns.isEmpty == true, "nothing was delivered to it")
        try FileManager.default.removeItem(at: place.out.appendingPathComponent("arguments"))
        let launched = Bridge.answer(["method": "launch", "params": ["kind": "claude"]], host: host)
        let other = try #require(launched["result"] as? String)
        #expect(other != id && engine.assistants == [id])
        try await until("the space's launch") { arguments().contains("--session-id") }
        #expect(!arguments().contains("--allowedTools"), "a space's launch is never the assistant's")
        try await until("the space's environment") { path()?.hasPrefix(place.bin.path + ":") == true }

        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        try await until("the stop") { stopped }
        try await until("the ends") { engine.state.agents.allSatisfy { $0.alive == false } }
        let threads = try [id, other].map { agent in try #require(engine.state.agents.first { $0.id == agent }?.thread) }
        now += Engine.endedKept
        engine.update()
        #expect(engine.state.agents.isEmpty)
        func sighting(_ key: String, _ folder: URL) -> Sighting {
            Sighting(kind: "claude", key: key, facts: StateMap.Facts(alive: false, evidence: "registry", turnOpen: false, waiting: .nothing),
                     folder: folder.path, updated: Date())
        }
        let earlier = "c0ffee00-0000-4000-8000-0000000000ea"
        engine.saw(Seen(sightings: [sighting(threads[0], spaces), sighting(threads[1], place.work), sighting(earlier, link)]))
        #expect(engine.state.agents.map(\.thread) == [threads[1]])
    }

    /// One agent stops alone (the assistant's New Conversation), and its end is no failure; the others run on.
    @Test func oneAgentStopsAlone() async throws {
        let place = try Place()
        defer { place.remove() }
        let engine = Engine.throwaway(place.environment)
        let ids = try (0..<2).map { _ in try engine.launch("claude", folder: place.work.path, model: nil, mode: nil, effort: nil) }
        try await until("both running") { engine.state.agents.filter { $0.alive == true }.count == 2 }
        var stopped = false
        engine.stopAll(within: 6, only: ids[0]) { stopped = true }
        try await until("the stop") { stopped && engine.state.agents.first { $0.id == ids[0] }?.alive == false }
        #expect(engine.state.agents.first { $0.id == ids[0] }?.error == nil)
        #expect(engine.state.agents.first { $0.id == ids[1] }?.alive == true)
        engine.stopAll(within: 6) { stopped = true }
        try await until("the end") { engine.state.agents.allSatisfy { $0.alive == false } }
    }

    /// Look for Agents Again finds a program installed after the first look.
    @Test func lookingAgainFindsANewProgram() async throws {
        let place = try Place()
        defer { place.remove() }
        try FileManager.default.removeItem(at: place.bin.appendingPathComponent("opencode"))
        let engine = Engine.throwaway(place.environment)
        engine.start(often: false)
        try await until("the first look") { engine.state.kinds["opencode"]?.installed == false }
        try EngineTests.fakeOpenCode.write(to: place.bin.appendingPathComponent("opencode"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: place.bin.appendingPathComponent("opencode").path)
        engine.lookAgain()
        try await until("the second look") { engine.state.kinds["opencode"]?.installed == true }
    }

    /// Ended launched agents leave the state: beyond the last 20 at once, and every one ten minutes after its end, so
    /// that an app open all day does not push every agent it ever launched. The clock is the engine's, moved here.
    @Test func endedAgentsLeaveTheState() async throws {
        let place = try Place()
        defer { place.remove() }
        let engine = Engine.throwaway(place.environment)
        var now = Date()
        engine.clock = { now }
        let ids = try (0..<21).map { _ in try engine.launch("claude", folder: place.work.path, model: nil, mode: nil, effort: nil) }
        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        try await until("the stop") { stopped }
        try await until("the ends") { engine.state.agents.allSatisfy { $0.alive == false } }
        #expect(engine.state.agents.count == 20, "the first ended agent beyond the last 20 left")
        now += Engine.endedKept - 1
        engine.update()
        #expect(engine.state.agents.count == 20)
        now += 1
        engine.update()
        #expect(engine.state.agents.isEmpty && engine.state.threads.isEmpty)
        #expect(throws: CodedError.self) { try engine.deliver("Late.", to: ids[0], when: "next") }
    }

    /// The state is made once at each change, but its `at` is the time of each read: a page tells how long ago an agent
    /// was updated by it, and a quiet engine must not make an old change look recent.
    @Test func theStateIsDatedAtEachRead() async throws {
        let engine = Engine.throwaway(["HOME": "/Users/example", "PATH": "/usr/bin:/bin"])
        let first = try #require(iso8601.date(from: engine.state.at))
        try await Task.sleep(nanoseconds: 1_100_000_000)
        let second = try #require(iso8601.date(from: engine.state.at))
        #expect(second > first)
    }

    /// An answer the agent can no longer read is said, never lost in silence: the panel shows this sentence. The fake
    /// asks a permission, then closes its input and stays; the next line written to it finds the input closed.
    @Test func anAnswerThatCannotBeWrittenIsSaid() async throws {
        let place = try Place()
        defer { place.remove() }
        try #"""
            #!/bin/sh
            while IFS= read -r line; do
              case "$line" in
                *'"subtype":"initialize"'*)
                  echo '{"type":"control_response","response":{"subtype":"success","request_id":"something-1","response":{"current_permission_mode":"default","models":[]}}}' ;;
                *'"type":"user"'*)
                  echo '{"type":"system","subtype":"init","cwd":"/Users/example/shop","session_id":"s1","model":"claude-example","permissionMode":"default"}'
                  echo '{"type":"control_request","request_id":"r-1","request":{"subtype":"can_use_tool","tool_name":"Bash","display_name":"Bash","input":{"command":"touch invented.txt"},"tool_use_id":"toolu_1"}}'
                  exec 0<&-
                  sleep 30
                  exit 0 ;;
              esac
            done
            """#.write(to: place.bin.appendingPathComponent("claude"), atomically: true, encoding: .utf8)
        let engine = Engine.throwaway(place.environment)
        let id = try engine.launch("claude", folder: place.work.path, model: nil, mode: nil, effort: nil)
        #expect(try engine.deliver("Hello.", to: id, when: "next") == "started")
        try await until("the request") { !engine.state.requests.isEmpty }
        let request = engine.state.requests[0].id
        // An answer that does not fit is the driver's own error, said as it is: the agent did not stop.
        #expect(throws: CodedError("BAD_PARAMS", "Answer each of the 0 questions, in their order.")) {
            try engine.answer(request, .choice([["Invented."]]))
        }
        // A line written now finds the input closed, and the next write throws: the answer cannot be written.
        try await until("the input found closed") { (try? engine.deliver("Invented steer.", to: id, when: "now")) == nil }
        #expect(engine.state.requests.map(\.id) == [request], "the request is still open")
        #expect(throws: CodedError("AGENT_STOPPED", "Claude Code did not receive your answer: it stopped listening.")) {
            try engine.answer(request, .once)
        }
        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        try await until("the stop") { stopped }
    }

    /// Codex through the engine: launched with its mode, a turn, its input closed at the stop, which ends it cleanly.
    @Test func aLaunchedCodexTalksAndStops() async throws {
        let place = try Place()
        defer { place.remove() }
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
        defer { place.remove() }
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
        // Only a guard against a hang: the cancel's answer reaches the main queue, which the window suites keep busy
        // while the whole suite runs (2.7 s seen), so a time near Spawn's 3 s cap cannot tell the answer from the cap.
        // What shows the ladder is the fake's own record: it got the cancel, then its input closed, and no signal.
        #expect(Date().timeIntervalSince(begun) < 6, "the stop ends within its cap")
        #expect(FileManager.default.fileExists(atPath: place.out.appendingPathComponent("cancels").path))
        #expect(FileManager.default.fileExists(atPath: place.out.appendingPathComponent("closed").path), "its input was closed")
        #expect(!FileManager.default.fileExists(atPath: place.out.appendingPathComponent("signalled").path), "no signal was needed")
        #expect(engine.state.agents.first?.state == "interrupted")
        #expect(engine.state.agents.first?.error == nil, "this home has no OpenCode database: no claim is said")
    }

    /// Over ACP OpenCode picks a model of its own: the assistant starts with OpenCode's own last model instead, read
    /// from its state file in the launch's home, before its first message.
    @Test func anOpenCodeAssistantStartsWithOpenCodesLastModel() async throws {
        let place = try Place()
        defer { place.remove() }
        let state = place.root.appendingPathComponent(".local/state/opencode")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        try ACPDriverTests.modelFile.write(to: state.appendingPathComponent("model.json"), atomically: true, encoding: .utf8)
        let engine = Engine.throwaway(place.environment)
        let id = try engine.launchAssistant("opencode", folder: place.work.path, askEverything: false)
        try await until("the model") { engine.state.agents.first?.model == "fake/other-model" }
        #expect(try engine.deliver("Hello.", to: id, when: "next") == "started")
        try await until("the reply") { engine.state.threads.first?.turns.first?.state == "done" }
        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        try await until("the stop") { stopped }
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

    /// A launch's values are checked as one, OpenCode's mode included: an agent the person wrote can be chosen with
    /// `set` once OpenCode lists it, never at launch, so no window asks about a launch that would then fail.
    @Test func aLaunchIsCheckedBeforeAnyWindow() throws {
        func code(_ kind: String, model: String? = nil, mode: String? = nil, effort: String? = nil) -> String? {
            do { try Engine.checkLaunch(kind, model: model, mode: mode, effort: effort); return nil } catch { return (error as? CodedError)?.code }
        }
        #expect(code("opencode", mode: "my-agent") == "VALUE_NOT_OFFERED")
        #expect(code("opencode", mode: "plan") == nil && code("claude", mode: "acceptEdits") == nil)
        #expect(code("claude", mode: "bypassPermissions") == "VALUE_NOT_OFFERED")
        #expect(code("codex", model: "-c") == "BAD_PARAMS" && code("claude", effort: "") == "BAD_PARAMS")
        #expect(code("pi", mode: "default") == "NOT_SUPPORTED" && code("omp") == "NOT_SUPPORTED")
    }

    /// start(often:) again changes the cadence only: the programs are looked for once.
    @Test func startIsCalledAgain() async throws {
        let place = try Place()
        defer { place.remove() }
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

    /// Opened from the Finder, the app reads the login shell's PATH: a shell that takes 2 s never holds the main queue,
    /// a first launch waits for the first look off it, and the login shell is not read again by later launches.
    @Test func theFirstLaunchLeavesTheMainQueueFree() async throws {
        let place = try Place()
        defer { place.remove() }
        let shell = place.root.appendingPathComponent("slow-shell")
        try """
            #!/bin/sh
            echo "$*" >> "$FAKE_OUT/shell-runs"
            touch "$FAKE_OUT/shell-sleeps"
            sleep 2
            rm -f "$FAKE_OUT/shell-sleeps"
            PATH='\(place.bin.path):/usr/bin:/bin'; export PATH
            for last; do :; done
            eval "$last"
            """.write(to: shell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)
        let engine = Engine.throwaway(place.environment.merging(["PATH": "/usr/bin:/bin", "SHELL": shell.path]) { _, finder in finder })
        // The main queue ticks while the shell sleeps; one held by the shell could never. Counting ticks instead would
        // fail on a busy runner, where the other suites' main-actor tests hold the main queue too.
        final class Ticks { var duringShell = 0 }
        let ticks = Ticks(), sleeping = place.out.appendingPathComponent("shell-sleeps").path
        let ticker = Task { @MainActor in
            while !Task.isCancelled {
                if FileManager.default.fileExists(atPath: sleeping) { ticks.duringShell += 1 }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        let begun = Date()
        engine.start(often: false)
        var id: String?
        engine.lookFor("claude") { id = try? engine.launch("claude", folder: place.work.path, model: nil, mode: nil, effort: nil) }
        try await until("the launch") { id != nil }
        ticker.cancel()
        let waited = Date().timeIntervalSince(begun)
        #expect(waited >= 1.8, "the launch waited for the shell")
        #expect(ticks.duringShell >= 1, "the main queue ran while the login shell was read")
        // A second launch, as one that waited for the person's answer, uses what was found and reads no shell.
        let second = try engine.launch("claude", folder: place.work.path, model: nil, mode: nil, effort: nil)
        #expect(second != id)
        let runs = try String(contentsOf: place.out.appendingPathComponent("shell-runs"), encoding: .utf8)
        // The first look reads the login shell once (and the interactive one once, for pi and omp, missing here).
        #expect(runs.components(separatedBy: "\n").filter { $0.hasPrefix("-l -c ") }.count == 1)
        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        try await until("the stop") { stopped }
    }

    /// Plan B's spools are in the person's Application Support, never in $TMPDIR, which a sandboxed agent may write.
    @Test func theSpoolsAreNotInTheTemporaryFolder() {
        #expect(Spool.root.hasSuffix("/Library/Application Support/something/spool"))
        #expect(!Spool.root.hasPrefix(NSTemporaryDirectory()))
    }

    @Test func whatALaunchRefuses() throws {
        let place = try Place()
        defer { place.remove() }
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
