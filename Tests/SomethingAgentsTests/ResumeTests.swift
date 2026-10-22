// Continue here, through the Engine: a Claude Code conversation and Codex ones started elsewhere, seen by
// their readers in a throwaway home (a registry record, rollouts in a day folder), then continued by fake programs
// (EngineTests' fake claude, and a fake codex app-server that answers thread/resume, or refuses it as 0.163.0 does
// when another writer holds the thread, Tests/Exchanges/codex/held.jsonl, until the test frees it). A retry goes
// through the Bridge, as a space's does.
import Foundation
import Testing
@testable import SomethingAgents
@testable import AgentClaude
@testable import AgentCodex
import SomethingCore

@MainActor @Suite(.leavesNothing("resume-")) struct ResumeTests {
    nonisolated static let fakeCodex = #"""
    #!/bin/sh
    printf '%s\n' "$@" > "$FAKE_OUT/arguments"
    while IFS= read -r line; do
      printf '%s\n' "$line" >> "$FAKE_OUT/lines"
      id=$(printf '%s' "$line" | sed -n 's/^{"id":\([0-9]*\),.*/\1/p')
      thread=$(printf '%s' "$line" | sed -n 's/.*"threadId":"\([^"]*\)".*/\1/p')
      case "$line" in
        *'"method":"initialize"'*) echo "{\"id\":$id,\"result\":{\"userAgent\":\"something/0.163.0\"}}" ;;
        *'"method":"thread/resume"'*)
          case "$line" in *held*) [ -e "$FAKE_OUT/freed" ] || { echo "{\"error\":{\"code\":-32600,\"message\":\"thread $thread already has an active writer\"},\"id\":$id}"; continue; } ;; esac
          echo "{\"id\":$id,\"result\":{\"thread\":{\"id\":\"$thread\"},\"model\":\"fake-model\",\"approvalPolicy\":\"on-request\",\"reasoningEffort\":null}}" ;;
        *'"method":"model/list"'*) echo "{\"id\":$id,\"result\":{\"data\":[]}}" ;;
      esac
    done
    """#

    nonisolated static let claude = "c1a0de00-0000-4000-8000-000000000001"
    nonisolated static let codex = "019a2b3c-4d5e-7f60-8a1b-2c3d4e5f0001", held = "019a2b3c-4d5e-7f60-8a1b-2c3d4e5f0held"

    /// A throwaway home with a Claude record whose process is `running`, and two Codex rollouts, all in the place's work folder.
    final class Home {
        let place: EngineTests.Place
        var processes: [Running] = []
        /// The files each process holds open.
        var files: [Int32: [String]] = [:]
        var claudeRunning: Running { Running(pid: 47000, parent: 1, group: 47000, started: Date(timeIntervalSince1970: 1_792_227_300), name: "claude") }

        init() throws {
            place = try EngineTests.Place(prefix: "resume-")
            let codex = place.bin.appendingPathComponent("codex")
            try ResumeTests.fakeCodex.write(to: codex, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)
            let sessions = place.root.appendingPathComponent(".claude/sessions")
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            try Data(#"{"pid":47000,"sessionId":"\#(ResumeTests.claude)","cwd":"\#(place.work.path)","procStart":"Sat Oct 17 08:55:00 2026","kind":"interactive","status":"idle","updatedAt":\#(Date().timeIntervalSince1970 * 1000)}"#.utf8)
                .write(to: sessions.appendingPathComponent("47000.json"))
            let day = place.root.appendingPathComponent(".codex/sessions/2026/10/17")
            try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
            for id in [ResumeTests.codex, ResumeTests.held] {
                let lines = String(decoding: CodexHome.lines(id, open: false), as: UTF8.self).replacingOccurrences(of: "/Users/example/shop", with: place.work.path)
                try Data(lines.utf8).write(to: day.appendingPathComponent("rollout-2026-10-17T10-55-00-\(id).jsonl"))
            }
        }

        func engine() -> Engine {
            let engine = Engine.throwaway(place.environment)
            let environment = ["HOME": place.root.path]
            engine.watch = Watch(readers: [ClaudeReader(environment: environment), CodexReader(environment: environment)], snapshot: { [unowned self] in Snapshot(processes) { self.files[$0] ?? [] } })
            return engine
        }

        func arguments() -> [String] {
            ((try? String(contentsOf: place.out.appendingPathComponent("arguments"), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        }
    }

    func stop(_ engine: Engine) async throws {
        var done = false
        engine.stopAll(within: 3) { done = true }
        try await EngineTests().until("the stop") { done }
    }

    @Test func aClaudeConversationIsContinuedOnceItsProcessEnded() async throws {
        let home = try Home()
        defer { home.place.remove() }
        let engine = home.engine()
        let id = "claude-\(ResumeTests.claude)"
        home.processes = [home.claudeRunning]
        engine.saw(engine.watch.tick(now: Date()))
        let running = try #require(engine.state.agents.first { $0.id == id })
        #expect(running.alive == true && !running.can.resume)
        #expect(running.because["resume"] == "Claude Code still runs this conversation (pid 47000). Quit it there first.")
        #expect(throws: CodedError("STILL_RUNNING", running.because["resume"]!)) { try engine.resume("claude", thread: ResumeTests.claude, of: id) }

        home.processes = []
        engine.saw(engine.watch.tick(now: Date()))
        let ended = try #require(engine.state.agents.first { $0.id == id })
        #expect(ended.alive == false && ended.can.resume && ended.because["resume"] == nil)
        #expect(throws: CodedError.self) { try engine.resume("claude", thread: "c1a0de00-0000-4000-8000-00000000ffff", of: id) }
        let launched = try engine.resume("claude", thread: ResumeTests.claude, of: id)
        try await EngineTests().until("the fake's arguments") { home.arguments().contains("--resume") }
        let arguments = home.arguments()
        #expect(arguments.firstIndex(of: "--resume").map { arguments[$0 + 1] } == ResumeTests.claude && !arguments.contains("--session-id"))
        // From now on the conversation is listed once, as the agent something launched, in the conversation's folder.
        engine.saw(engine.watch.tick(now: Date()))
        let listed = engine.state.agents.filter { $0.thread == ResumeTests.claude }
        #expect(listed.map(\.id) == [launched] && listed.first?.origin == "launched" && listed.first?.folder == home.place.work.path)
        try await stop(engine)
    }

    @Test func aCodexConversationIsContinuedUnlessItsServiceHoldsIt() async throws {
        let home = try Home()
        defer { home.place.remove() }
        let engine = home.engine()
        // A codex runs that holds neither rollout: whether it holds them is unknown, and Codex refuses a second writer itself.
        home.processes = [Running(pid: 48000, parent: 1, group: 48000, started: Date(), name: "codex")]
        engine.saw(engine.watch.tick(now: Date()))
        let seen = try #require(engine.state.agents.first { $0.thread == ResumeTests.codex })
        #expect(seen.alive == nil && seen.can.resume)
        let launched = try engine.resume("codex", thread: ResumeTests.codex, of: seen.id)
        func lines() -> String { (try? String(contentsOf: home.place.out.appendingPathComponent("lines"), encoding: .utf8)) ?? "" }
        try await EngineTests().until("the resumed thread") { lines().contains("model/list") && engine.state.agents.first { $0.id == launched }?.model == "fake-model" }
        let lines = lines()
        #expect(lines.contains(#""method":"thread/resume""#) && lines.contains(ResumeTests.codex) && lines.contains(home.place.work.path))
        #expect(engine.state.agents.filter { $0.thread == ResumeTests.codex }.map(\.origin) == ["launched"])

        // The background service holds the other one: the agent ends with HELD_ELSEWHERE, and the conversation is still
        // seen elsewhere, once, as the one to continue.
        let other = try #require(engine.state.agents.first { $0.thread == ResumeTests.held })
        let refused = try engine.resume("codex", thread: ResumeTests.held, of: other.id)
        try await EngineTests().until("the refusal") { engine.state.agents.first { $0.id == refused }?.error != nil }
        let error = try #require(engine.state.agents.first { $0.id == refused }?.error)
        #expect(error == AgentError(code: "HELD_ELSEWHERE", message: "Codex's background service holds this conversation; run `codex app-server daemon stop` in a terminal, then try again."))
        #expect(engine.state.agents.filter { $0.thread == ResumeTests.held }.map(\.origin) == ["elsewhere"])
        #expect(engine.state.threads.filter { $0.id == ResumeTests.held }.count == 1)

        // The person stops the service, as the sentence says, and the space tries again.
        FileManager.default.createFile(atPath: home.place.out.appendingPathComponent("freed").path, contents: nil)
        let host = EngineHost(engine, folder: home.place.root.path)
        let answer = Bridge.answer(["contract": 1, "id": 1, "method": "resume", "params": ["kind": "codex", "thread": ResumeTests.held]], host: host)
        let again = try #require(answer["result"] as? String, "\(answer)")
        try await EngineTests().until("the second resume") { engine.state.agents.first { $0.id == again }?.model == "fake-model" }
        #expect(engine.state.agents.filter { $0.thread == ResumeTests.held }.map(\.id) == [again])
        try await stop(engine)
    }

    @Test func aConversationCodexsServiceHoldsSaysHowToFreeIt() throws {
        let home = try Home()
        defer { home.place.remove() }
        let engine = home.engine()
        let lock = home.place.root.appendingPathComponent(".codex/thread-writer-locks/\(ResumeTests.codex).lock").path
        home.processes = [Running(pid: 48100, parent: 1, group: 48100, started: Date(), name: "codex",
                                  arguments: ["codex", "app-server", "--listen", "unix://", "--managed-daemon"])]
        home.files = [48100: [lock]]
        engine.saw(engine.watch.tick(now: Date()))
        let seen = try #require(engine.state.agents.first { $0.thread == ResumeTests.codex })
        #expect(seen.alive == true && !seen.can.resume && seen.because["resume"] == CodexDriver.heldByService)
    }

    @Test func aClaudeThatRefusesPlanAResumesTheSameConversationWithPlanB() async throws {
        let home = try Home()
        defer { home.place.remove() }
        // An older Claude: it does not know the prompt tool and ends at its first line, naming the flag.
        let older = EngineTests.fake.replacingOccurrences(of: "#!/bin/sh\n", with: #"""
            #!/bin/sh
            printf '%s\n' run "$@" >> "$FAKE_OUT/runs"
            case " $* " in *" --permission-prompt-tool "*) IFS= read -r line; echo "error: unknown option '--permission-prompt-tool'" >&2; exit 1 ;; esac

            """#)
        try older.write(to: home.place.bin.appendingPathComponent("claude"), atomically: true, encoding: .utf8)
        let engine = home.engine()
        engine.hookCommand = ["/usr/bin/true", "hook", "permission"]
        engine.spools = home.place.root.appendingPathComponent("spools").path
        let id = "claude-\(ResumeTests.claude)"
        home.processes = [home.claudeRunning]
        engine.saw(engine.watch.tick(now: Date()))
        home.processes = []
        engine.saw(engine.watch.tick(now: Date()))
        let launched = try engine.resume("claude", thread: ResumeTests.claude, of: id)
        func runs() -> [[String]] {
            let text = (try? String(contentsOf: home.place.out.appendingPathComponent("runs"), encoding: .utf8)) ?? ""
            return text.components(separatedBy: "run\n").dropFirst().map { $0.split(separator: "\n").map(String.init) }
        }
        try await EngineTests().until("plan B") { runs().count == 2 && engine.state.agents.first { $0.id == launched }?.alive == true }
        for run in runs() { #expect(run.firstIndex(of: "--resume").map { run[$0 + 1] } == ResumeTests.claude && !run.contains("--session-id")) }
        #expect(runs()[1].contains("--settings") && !runs()[1].contains("--permission-prompt-tool"))
        #expect(engine.state.agents.filter { $0.thread == ResumeTests.claude }.map(\.id) == [launched])
        try await stop(engine)
    }
}

/// The bridge's host over an engine, as the app's is, for a space granted the state and launches of Codex under `folder`.
final class EngineHost: BridgeHost {
    let engine: Engine
    var granted = Granted()
    var launched: Set<String> = []
    var state: State { engine.state }
    var assistants: Set<String> { engine.assistants }
    var memory: Memory? { nil }

    init(_ engine: Engine, folder: String) {
        self.engine = engine
        granted.rights = ["state", "launch:codex"]
        granted.agents = .all
        granted.folder = folder
    }

    func journal(_ line: JournalLine) {}
    func deliver(_ text: String, to agent: Agent, when: String) throws -> String { try engine.deliver(text, to: agent.id, when: when) }
    func interrupt(_ agent: Agent) throws -> Bool { try engine.interrupt(agent.id) }
    func set(_ agent: Agent, model: String?, mode: String?, effort: String?) throws -> String { try engine.set(agent.id, model: model, mode: mode, effort: effort) }
    func launch(_ kind: String, folder: String, model: String?, mode: String?, effort: String?) throws -> String {
        try engine.launch(kind, folder: folder, model: model, mode: mode, effort: effort)
    }
    func resume(_ kind: String, thread: String, of agent: Agent) throws -> String {
        let id = try engine.resume(kind, thread: thread, of: agent.id)
        launched.insert(id)
        return id
    }
    func open(_ url: URL) throws -> Bool { false }
    func confirms(mode: String, kind: String, folder: String?) throws -> Bool { true }
    func checkLaunch(_ kind: String, model: String?, mode: String?, effort: String?) throws {
        try Registry.described.checkLaunch(kind, model: model, mode: mode, effort: effort)
    }
}
