// Claude's plan B, end to end, with the real hook command: PermissionSpool.swift is built by itself into a program
// named `something` (in a folder whose name holds a space and a quote, as a person's may), and a fake `claude`, a
// /bin/sh script that speaks the stream-json lines of the real one (text invented), reads the hook's command from
// the `--settings` it was given and runs it through a shell for its one tool call, as Claude does. What the hook
// printed is kept in a file, so the decision Claude would read is checked too.
import Darwin
import Foundation
import Testing
@testable import SomethingAgents
import SomethingCore

@MainActor @Suite(.serialized, .leavesNothing("plan-b-")) struct PlanBTests {
    nonisolated static let fake = #"""
    #!/bin/sh
    printf '%s\n' "$@" > "$FAKE_OUT/arguments"
    hook="" previous=""
    for word in "$@"; do
      [ "$previous" = "--settings" ] && hook=$(printf '%s' "$word" | sed -e 's/.*"command":"\([^"]*\)".*/\1/' -e 's/\\\\/\\/g')
      if [ "$word" = "--permission-prompt-tool" ] && [ -n "$FAKE_NO_PROMPT_TOOL" ]; then
        echo "error: option '--permission-prompt-tool <tool>': unknown tool stdio" >&2
        exit 1
      fi
      previous="$word"
    done
    while IFS= read -r line; do
      case "$line" in
        *'"subtype":"initialize"'*)
          echo '{"type":"control_response","response":{"subtype":"success","request_id":"something-1","response":{"current_permission_mode":"default","models":[{"value":"default","displayName":"Default (recommended)"}]}}}' ;;
        *'"type":"user"'*)
          echo '{"type":"system","subtype":"session_state_changed","state":"running","uuid":"u1","session_id":"s1"}'
          echo '{"type":"assistant","message":{"id":"msg_1","model":"claude-example","role":"assistant","content":[{"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"touch invented.txt","description":"Make a file"}}]},"parent_tool_use_id":null,"uuid":"u2","session_id":"s1"}'
          asked='{"session_id":"s1","transcript_path":"/Users/example/.claude/projects/-Users-example-shop/s1.jsonl","cwd":"/Users/example/shop","permission_mode":"default","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"touch invented.txt","description":"Make a file"},"permission_suggestions":[]}'
          if [ -n "$FAKE_KILL_HOOK" ]; then
            # An interrupt: Claude kills the hook's shell while it waits.
            printf '%s' "$asked" | sh -c "$hook" > /dev/null &
            sleep 1
            kill $!
            decision=""
          else
            decision=$(printf '%s' "$asked" | sh -c "$hook")
          fi
          printf '%s\n' "$decision" > "$FAKE_OUT/decision"
          case "$decision" in *'"behavior":"allow"'*) failed=false ;; *) failed=true ;; esac
          if [ "$failed" = true ] && [ -n "$FAKE_DENIED_FRAME" ]; then
            echo '{"type":"system","subtype":"permission_denied","tool_name":"Bash","tool_use_id":"toolu_1","decision_reason_type":"hook","message":"Invented.","uuid":"u2d","session_id":"s1"}'
          fi
          echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_1","is_error":'$failed',"content":"Invented."}]},"parent_tool_use_id":null,"uuid":"u3","session_id":"s1"}'
          echo '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","result":"Invented.","session_id":"s1","uuid":"u4"}'
          echo '{"type":"system","subtype":"session_state_changed","state":"idle","uuid":"u5","session_id":"s1"}' ;;
        *'"subtype":"end_session"'*)
          echo '{"type":"control_response","response":{"subtype":"success","request_id":"something-end"}}'
          exit 0 ;;
      esac
    done
    """#

    final class Place {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plan-b-\(UUID().uuidString)")
        var bin: URL { root.appendingPathComponent("bin") }
        var work: URL { root.appendingPathComponent("work/shop") }
        var out: URL { root.appendingPathComponent("out") }
        var spools: URL { root.appendingPathComponent("spools") }
        var tools: URL { root.appendingPathComponent("plan b's tools") }
        var hook: String { tools.appendingPathComponent("something").path }
        var environment: [String: String] { ["HOME": root.path, "PATH": "\(bin.path):/usr/bin:/bin", "FAKE_OUT": out.path, "SHELL": "/bin/sh"] }

        init() async throws {
            for folder in [bin, work, out, tools] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
            let program = bin.appendingPathComponent("claude")
            try PlanBTests.fake.write(to: program, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
            try await PlanBTests.buildHook(hook, in: tools)
        }

        /// Called with defer in each test: a deinit does not always run before the test process ends.
        func remove() { try? FileManager.default.removeItem(at: root) }

        func engine(_ hook: [String] = ["hook", "permission"], extra: [String: String] = [:]) -> Engine {
            let engine = Engine.throwaway(environment.merging(extra) { _, new in new })
            engine.hookCommand = [self.hook] + hook
            engine.spools = spools.path
            return engine
        }

        var arguments: [String] { ((try? String(contentsOf: out.appendingPathComponent("arguments"), encoding: .utf8)) ?? "").components(separatedBy: "\n") }
        var decision: [String: Any]? {
            guard let data = try? Data(contentsOf: out.appendingPathComponent("decision")),
                  let printed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
            #expect((printed["hookSpecificOutput"] as? [String: Any])?["hookEventName"] as? String == "PermissionRequest")
            return (printed["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        }
    }

    /// Builds the hook command from PermissionSpool.swift alone, at `path`, with what `something hook permission`
    /// runs; `folder` holds its scraps. swiftc takes seconds on a slow Mac (5 s on a 3-core runner): it is waited for
    /// on a thread of its own, never on the main actor, which the engine's tests and WebKit's share.
    nonisolated static func buildHook(_ path: String, in folder: URL) async throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SomethingAgents/PermissionSpool.swift")
        let main = folder.appendingPathComponent("main.swift")
        try "import Foundation\nexit(SpoolHook.main(Array(CommandLine.arguments.dropFirst())))\n".write(to: main, atomically: true, encoding: .utf8)
        let swiftc = Process()
        swiftc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        swiftc.arguments = ["swiftc", "-module-cache-path", folder.appendingPathComponent("cache").path, "-o", path, source.path, main.path]
        try await PlanBTests.offMain {
            try swiftc.run()
            swiftc.waitUntilExit()
        }
        #expect(swiftc.terminationStatus == 0, "the hook command did not build")
    }

    /// Runs `work`, which waits for a child process, on a thread of its own, and returns what it returns or throws:
    /// the main actor is never held (Support.swift says why, for the app's tests).
    nonisolated static func offMain<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread { continuation.resume(with: Result { try work() }) }
        }
    }

    func until(_ what: String, seconds: Double = 30, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < end else { Issue.record("timed out waiting for \(what)"); throw CancellationError() }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    var tool: (Engine) -> Item? = { $0.state.threads.first?.turns.first?.items.first { $0.kind == "tool" } }

    /// How many times a window opened: a request the person answered must never open a second one.
    final class Openings {
        var count = 0, open = false
        func watch(_ engine: Engine) {
            engine.changed = { [unowned engine, self] in
                let now = !engine.state.requests.isEmpty
                if now && !open { count += 1 }
                open = now
            }
        }
    }

    /// Launches with plan B, sends the message that makes the fake ask, and waits for the request.
    func ask(_ place: Place, _ engine: Engine, _ openings: Openings = Openings()) async throws -> (agent: String, request: Request) {
        openings.watch(engine)
        let id = try engine.launch("claude", folder: place.work.path, model: nil, mode: nil, effort: nil, planB: true)
        #expect(try engine.deliver("Please run-echo now.", to: id, when: "next") == "started")
        try await until("the request") { !engine.state.requests.isEmpty }
        return (id, engine.state.requests[0])
    }

    func stop(_ engine: Engine) async throws {
        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        try await until("the stop") { stopped && engine.state.agents.first?.alive == false }
    }

    @Test func theLaunchLineCarriesTheHook() throws {
        let launch = Launch(agent: "claude-1", folder: "/Users/example/shop", thread: "5b2e0000-0000-4000-8000-000000000001")
        let arguments = ClaudeDriver.command(launch, hook: ["/Applications/My Apps/something", "hook", "permission", "--spool", "/tmp/s"]).arguments
        #expect(!arguments.contains("--permission-prompt-tool"))
        let index = try #require(arguments.firstIndex(of: "--settings"))
        let settings = try #require(try JSONSerialization.jsonObject(with: Data(arguments[index + 1].utf8)) as? [String: Any])
        let entry = try #require(((settings["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]])?.first)
        let hook = try #require((entry["hooks"] as? [[String: Any]])?.first)
        #expect(entry["matcher"] as? String == "*")
        #expect(hook["type"] as? String == "command" && hook["timeout"] as? Int == 3600)
        #expect(hook["command"] as? String == "'/Applications/My Apps/something' 'hook' 'permission' '--spool' '/tmp/s'")
        #expect(ClaudeDriver.command(launch).arguments.contains("--permission-prompt-tool"))
        #expect(Set(arguments).isSuperset(of: ["--include-hook-events", "--permission-mode", "--session-id"]))
    }

    @Test func allowOnce() async throws {
        let place = try await Place()
        defer { place.remove() }
        let engine = place.engine(), openings = Openings()
        let (_, request) = try await ask(place, engine, openings)
        #expect(place.arguments.contains("--settings") && !place.arguments.contains("--permission-prompt-tool"))
        #expect((request.kind, request.tool, request.about) == ("permission", "Bash", "touch invented.txt"))
        #expect(engine.prompt(request.id)?.input == "touch invented.txt")
        #expect(engine.state.agents.first?.waiting == "permission")
        let spool = try #require(try FileManager.default.contentsOfDirectory(atPath: place.spools.path).first)
        let folder = place.spools.appendingPathComponent(spool).path
        #expect((try FileManager.default.attributesOfItem(atPath: folder)[.posixPermissions] as? Int) == 0o700)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder).contains { $0.hasSuffix(".ask.json") })

        try engine.answer(request.id, .once)
        try await until("the tool to run") { tool(engine)?.tool?.status == "done" && engine.state.agents.first?.state == "idle" }
        #expect(tool(engine)?.decision == Decision(by: "person", outcome: "allowed"))
        #expect(place.decision?["behavior"] as? String == "allow")
        #expect((place.decision?["updatedInput"] as? [String: Any])?["command"] as? String == "touch invented.txt")
        try await Task.sleep(nanoseconds: 1_000_000_000)
        #expect(openings.count == 1 && engine.state.requests.isEmpty, "one window for one request")
        try await stop(engine)
        #expect(!FileManager.default.fileExists(atPath: folder), "the spool is removed with its agent")
    }

    /// Claude says a hook denied the tool: the deny is still the person's, who chose it.
    @Test func deny() async throws {
        let place = try await Place()
        defer { place.remove() }
        let engine = place.engine(extra: ["FAKE_DENIED_FRAME": "1"])
        let (_, request) = try await ask(place, engine)
        try engine.answer(request.id, .deny)
        try await until("the tool to fail") { tool(engine)?.tool?.status == "failed" && engine.state.agents.first?.state == "idle" }
        #expect(tool(engine)?.decision == Decision(by: "person", outcome: "denied"))
        #expect(place.decision?["behavior"] as? String == "deny")
        #expect(place.decision?["message"] as? String == "The person refused this in something.")
        #expect(engine.state.requests.isEmpty)
        try await stop(engine)
    }

    /// Nobody answers: the hook denies before Claude's own limit, and the window closes by itself.
    @Test func timeout() async throws {
        let place = try await Place()
        defer { place.remove() }
        let engine = place.engine(["hook", "permission", "--timeout", "1"])
        let (_, request) = try await ask(place, engine)
        try await until("the request to close") { engine.state.requests.isEmpty && tool(engine)?.tool?.status == "failed" }
        #expect(engine.prompt(request.id) == nil)
        #expect(place.decision?["behavior"] as? String == "deny")
        #expect(place.decision?["message"] as? String == "Nobody answered in something in time, so the request was refused.")
        #expect(tool(engine)?.decision == nil, "nobody decided")
        try await stop(engine)
    }

    /// Claude kills the hook while it waits (an interrupt): the window closes, and nobody decided.
    @Test func aKilledHookIsWithdrawn() async throws {
        let place = try await Place()
        defer { place.remove() }
        let engine = place.engine(extra: ["FAKE_KILL_HOOK": "1"]), openings = Openings()
        _ = try await ask(place, engine, openings)
        try await until("the window to close") { engine.state.requests.isEmpty && tool(engine)?.tool?.status == "failed" }
        #expect(openings.count == 1)
        #expect(tool(engine)?.decision == nil, "nobody decided")
        let spool = try #require(try FileManager.default.contentsOfDirectory(atPath: place.spools.path).first)
        #expect(try FileManager.default.contentsOfDirectory(atPath: place.spools.appendingPathComponent(spool).path) == ["heartbeat"])
        try await stop(engine)
    }

    /// An answer stays answered while the hook has not read it yet, and one that could not be written leaves the
    /// request open, to be answered again.
    @Test func anAnswerIsGivenOnce() async throws {
        let place = try await Place()
        defer { place.remove() }
        let spool = PermissionSpool(folder: place.spools.appendingPathComponent("claude-1-x").path)
        try spool.start()
        defer { spool.stop() }
        let uuid = "5b2e0000-0000-4000-8000-0000000000aa"
        let ask = try JSONSerialization.data(withJSONObject: ["pid": Int(getpid()), "request": ["tool_name": "Bash", "tool_input": ["command": "ls"]]])
        #expect(Spool.put(ask, (spool.folder as NSString).appendingPathComponent(uuid + Spool.ask)))
        var asked = 0
        spool.asked = { _, _ in asked += 1 }
        try await until("the ask") { asked == 1 }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: spool.folder)
        #expect(spool.answer(uuid, ["behavior": "allow"]) == .unwritten)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: spool.folder)
        #expect(spool.answer(uuid, ["behavior": "allow"]) == .written)
        #expect(spool.answer(uuid, ["behavior": "deny"]) == .gone)
        // The ask file is still there, as it is until the hook's next look.
        try await Task.sleep(nanoseconds: 800_000_000)
        #expect(asked == 1)
    }

    /// The heartbeat is too old, though its pid runs (something hangs): the hook denies at once.
    @Test func anOldHeartbeatIsGone() async throws {
        let place = try await Place()
        defer { place.remove() }
        let folder = place.spools.appendingPathComponent("claude-1-old")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let heartbeat = folder.appendingPathComponent("heartbeat").path
        FileManager.default.createFile(atPath: heartbeat, contents: Data("\(getpid())\n".utf8))
        #expect(Spool.alive(heartbeat))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: heartbeat)
        let decision = SpoolHook.decide(request: Data(#"{"tool_name":"Bash","tool_input":{"command":"ls"}}"#.utf8), folder: folder.path, timeout: 5)
        #expect(decision["message"] as? String == SpoolHook.gone["message"] as? String)
    }

    /// something is gone (it crashed and left its spool, whose heartbeat names a pid that ended): the hook denies at once.
    @Test func staleHeartbeat() async throws {
        let place = try await Place()
        defer { place.remove() }
        let folder = place.spools.appendingPathComponent("claude-1-gone")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ended = Process()
        ended.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try ended.run()
        ended.waitUntilExit()
        let heartbeat = folder.appendingPathComponent("heartbeat").path
        FileManager.default.createFile(atPath: heartbeat, contents: Data("\(ended.processIdentifier)\n".utf8))
        let launch = Launch(agent: "claude-1", folder: place.work.path)
        let command = ClaudeDriver.command(launch, hook: [place.hook, "hook", "permission", "--spool", folder.path])
        let spawn = Spawn(path: place.bin.appendingPathComponent("claude").path, arguments: command.arguments, folder: launch.folder, environment: place.environment)
        let agent = try Engine.start("claude", launch, spawn, asked: { _ in true })
        _ = try agent.send("Please run-echo now.", when: "next")
        try await until("the tool to fail") { agent.queue.fold.turns.first?.items.first { $0.kind == "tool" }?.tool?.status == "failed" }
        #expect(agent.queue.fold.requests.isEmpty, "no window: nobody is there to answer")
        #expect(place.decision?["message"] as? String == "something is not running, so nobody can answer; the request was refused.")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["heartbeat"], "the hook leaves no ask behind")
        spawn.stop()
        try await until("the end") { agent.agent.alive == false }
    }

    /// A spool left by a something that ended (its heartbeat names a pid gone) is removed at the next start, with the
    /// request it held; a live one and one still being made are kept.
    @Test func aLeftoverSpoolIsRemovedAtTheNextStart() async throws {
        let place = try await Place()
        defer { place.remove() }
        let ended = Process()
        ended.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try ended.run()
        ended.waitUntilExit()
        let manager = FileManager.default
        func spool(_ name: String, pid: pid_t?) throws -> String {
            let folder = place.spools.appendingPathComponent(name).path
            try manager.createDirectory(atPath: folder, withIntermediateDirectories: true)
            if let pid { manager.createFile(atPath: "\(folder)/heartbeat", contents: Data("\(pid)\n".utf8)) }
            return folder
        }
        let left = try spool("claude-1-left", pid: ended.processIdentifier)
        manager.createFile(atPath: "\(left)/5b2e0000-0000-4000-8000-0000000000bb.ask.json", contents: Data(#"{"pid":1,"request":{}}"#.utf8))
        let live = try spool("claude-1-live", pid: getpid())
        let making = try spool("claude-1-making", pid: nil)
        let spool = PermissionSpool(folder: place.spools.appendingPathComponent("claude-2-x").path)
        try spool.start()
        defer { spool.stop() }
        #expect(!manager.fileExists(atPath: left))
        #expect(manager.fileExists(atPath: live) && manager.fileExists(atPath: making))
    }

    /// The heartbeat stops while the hook waits: it denies within a moment, not at its timeout.
    @Test func heartbeatStopsWhileWaiting() async throws {
        let place = try await Place()
        defer { place.remove() }
        let spool = PermissionSpool(folder: place.spools.appendingPathComponent("claude-1-x").path)
        try spool.start()
        let hook = Process()
        hook.executableURL = URL(fileURLWithPath: place.hook)
        hook.arguments = ["hook", "permission", "--spool", spool.folder]
        let input = Pipe(), output = Pipe()
        (hook.standardInput, hook.standardOutput) = (input, output)
        try hook.run()
        input.fileHandleForWriting.write(Data(#"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"}}"#.utf8))
        try input.fileHandleForWriting.close()
        var asked: String?
        spool.asked = { uuid, _ in asked = uuid }
        try await until("the ask") { asked != nil }
        spool.stop()
        let begun = Date()
        try await PlanBTests.offMain { hook.waitUntilExit() }
        #expect(Date().timeIntervalSince(begun) < 2)
        let printed = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(printed.contains(#""behavior":"deny""#) && printed.contains("something is not running"))
    }

    /// A Claude that does not know the prompt tool is launched again with plan B, under the same agent id.
    @Test func aRefusedPromptToolFallsBackToPlanB() async throws {
        let place = try await Place()
        defer { place.remove() }
        let engine = place.engine(extra: ["FAKE_NO_PROMPT_TOOL": "1"])
        let id = try engine.launch("claude", folder: place.work.path, model: nil, mode: nil, effort: nil)
        try await until("plan B") { place.arguments.contains("--settings") && engine.state.agents.first?.options.model != nil }
        #expect(engine.state.agents.map(\.id) == [id])
        #expect(engine.state.agents.first?.error == nil)
        #expect(try engine.deliver("Please run-echo now.", to: id, when: "next") == "started")
        try await until("the request") { !engine.state.requests.isEmpty }
        try engine.answer(engine.state.requests[0].id, .once)
        try await until("the tool to run") { tool(engine)?.tool?.status == "done" }
        try await stop(engine)
    }

    @Test func wrongWords() {
        #expect(SpoolHook.main(["hook", "permission"]) == 2)
        #expect(SpoolHook.main(["hook", "permission", "--spool"]) == 2)
        #expect(DeveloperTrial.main(["try", "nope"]) == 2)
        #expect(DeveloperTrial.main(["try", "claude", "--bogus"]) == 2)
        #expect(DeveloperTrial.main(["claude", "--record"]) == 2, "the words begin with try")
        #expect(SpoolHook.main(["permission", "--spool", "/Users/example/spool"]) == 2, "the words begin with hook permission")
    }

    @Test func aRefusedInitializeFallsBackOnlyBeforeAnyMessage() throws {
        for sent in [false, true] {
            var fellBack = 0
            let replay = Replay()
            (replay.agent.driver as! ClaudeDriver).fallback = { fellBack += 1; return true }
            if sent { _ = try replay.agent.send("Hello.", when: "next") }
            replay.feed(["type": "control_response", "response": ["subtype": "error", "request_id": "something-1", "error": "unknown"]])
            #expect(fellBack == (sent ? 0 : 1))
            #expect((replay.fold.agent.error != nil) == sent)
        }
    }
}
