// Trial T-6: a REAL claude started by hand, as a person does in a terminal (in a pseudo-terminal, through
// /usr/bin/script), read by ClaudeReader as an agent started elsewhere. It talks to FakeMessagesAPI, in a throwaway
// HOME and CLAUDE_CONFIG_DIR under $TMPDIR, deleted after. It runs only when asked, since it needs Claude Code:
//
//   SOMETHING_TRIAL_CLAUDE=/opt/homebrew/bin/claude swift test --filter ClaudeReaderTrial
//
// The keys typed are the trial's own, into the claude it started: nothing reaches a claude the person runs.
// T-10, the reader run once read-only on the person's own ~/.claude, is the second case. It prints counts only, never
// a name, a path, a title or a text:
//
//   SOMETHING_TRIAL_REAL_CLAUDE=1 swift test --filter ClaudeReaderTrial
import Darwin
import Foundation
import Testing
@testable import SomethingAgents
@testable import AgentClaude
import SomethingCore

@Suite(.serialized) struct ClaudeReaderTrial {
    @Test(.enabled(if: trialClaude != nil, "T-6 needs Claude Code: set SOMETHING_TRIAL_CLAUDE to its program's path."))
    func aClaudeStartedByHandIsReadElsewhere() async throws {
        let api = try FakeMessagesAPI()
        // The real path, as Claude sees its folder: resolvingSymlinksInPath would drop /private, and the folder would not be trusted.
        let temporary = try #require(realpath(NSTemporaryDirectory(), nil))
        defer { free(temporary) }
        let root = URL(fileURLWithPath: String(cString: temporary)).appendingPathComponent("claude-by-hand-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home"), config = home.appendingPathComponent(".claude")
        let work = root.appendingPathComponent("work/shop")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        // A first run would ask for a theme, the made-up key and trust in the folder: answered beforehand, here only.
        let settings: [String: Any] = ["hasCompletedOnboarding": true, "theme": "dark", "customApiKeyResponses": ["approved": ["test-key"], "rejected": []],
                                       "projects": [work.path: ["hasTrustDialogAccepted": true, "hasCompletedProjectOnboarding": true]]]
        try JSONSerialization.data(withJSONObject: settings).write(to: config.appendingPathComponent(".claude.json"))
        let environment = ["HOME": home.path, "CLAUDE_CONFIG_DIR": config.path, "TMPDIR": root.path, "TERM": "xterm-256color",
                           "PATH": "\((trialClaude! as NSString).deletingLastPathComponent):/usr/bin:/bin",
                           "ANTHROPIC_BASE_URL": api.url, "ANTHROPIC_API_KEY": "test-key", "DISABLE_AUTOUPDATER": "1",
                           "DISABLE_TELEMETRY": "1", "DISABLE_ERROR_REPORTING": "1", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"]
        let terminal = Process()
        terminal.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        // Auto mode, the default now, would run the command without asking: the trial asks for the mode that asks.
        terminal.arguments = ["-q", "/dev/null", trialClaude!, "--tools", "Bash", "--permission-mode", "default"]
        (terminal.currentDirectoryURL, terminal.environment) = (work, environment)
        let keys = Pipe(), screen = Pipe()
        (terminal.standardInput, terminal.standardOutput, terminal.standardError) = (keys, screen, screen)
        let shown = Screen()
        screen.fileHandleForReading.readabilityHandler = { shown.add($0.availableData) }
        try terminal.run()
        defer {
            if terminal.isRunning { terminal.terminate() }
            terminal.waitUntilExit()
            screen.fileHandleForReading.readabilityHandler = nil
            api.stop()
            try? FileManager.default.removeItem(at: root)
        }
        let reader = ClaudeReader(environment: ["HOME": home.path, "CLAUDE_CONFIG_DIR": config.path])
        let processes = Processes(known: reader.programs)
        var ticks = 0
        func sighting() -> Sighting? {
            ticks += 1
            return (try? reader.read(processes.snapshot(), discover: ticks % Watch.discoveryEvery == 0, now: Date()))?.sightings.first
        }
        func until(_ what: String, seconds: Double = 40, _ condition: (Sighting?) -> Bool) async throws -> Sighting? {
            let end = Date().addingTimeInterval(seconds)
            while true {
                let seen = sighting()
                if condition(seen) { return seen }
                guard Date() < end else {
                    Issue.record("timed out waiting for \(what); last facts \(String(describing: seen?.facts)); screen: \(shown.tail)")
                    throw CancellationError()
                }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        func type(_ text: String) {
            keys.fileHandleForWriting.write(Data(text.utf8))
        }
        func words(_ seen: Sighting?) -> StateMap.Result? { seen.map { StateMap.map($0.facts, now: Date()) } }

        let started = try #require(try await until("the registry record") { $0?.facts.alive == true && $0?.facts.turnOpen == false })
        #expect(started.facts.evidence == "registry" && words(started)?.state == "idle" && words(started)?.waiting == "none")
        #expect(started.folder == work.path)
        let record = try #require(try FileManager.default.contentsOfDirectory(atPath: config.appendingPathComponent("sessions").path).first { $0.hasSuffix(".json") })
        let fields = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: config.appendingPathComponent("sessions/\(record)"))) as? [String: Any])
        #expect(fields["entrypoint"] as? String == "cli" && fields["kind"] as? String == "interactive" && fields["pidDomain"] as? String == "darwin")

        // A turn: the person's words and the agent's reply, then idle again.
        try await Task.sleep(nanoseconds: 1_000_000_000)
        type("Hello there.")
        try await Task.sleep(nanoseconds: 300_000_000)
        type("\r")
        let replied = try #require(try await until("the reply") { seen in
            seen?.turns.last?.state == "done" && seen?.facts.turnOpen == false && seen?.turns.last?.items.contains { $0.author == "agent" } == true
        })
        #expect(replied.turns.last?.items.first?.text == "Hello there." && replied.turns.last?.items.first?.author == "person")
        #expect(replied.model != nil && words(replied)?.state == "idle")

        // A permission: Claude waits on the person, then the person refuses it (Escape).
        type("Please run-echo now.")
        try await Task.sleep(nanoseconds: 300_000_000)
        type("\r")
        let asking = try #require(try await until("the permission") { $0?.facts.waiting == .permission })
        #expect(words(asking)?.state == "waiting" && words(asking)?.waiting == "permission")
        #expect(asking.turns.last?.items.last?.tool?.name == "Bash")
        type("\u{1b}")
        let refused = try #require(try await until("the end of the refused turn") { $0?.facts.turnOpen == false })
        #expect(refused.facts.waiting == .nothing)

        // The person quits: the record goes, and the conversation shows as done.
        type("/exit")
        try await Task.sleep(nanoseconds: 300_000_000)
        type("\r")
        let ended = try #require(try await until("the end") { $0?.facts.alive == false })
        #expect(ended.facts.ended && words(ended)?.state == "done", "screen: \(shown.tail)")
    }

    /// T-10 for Claude: the reader once on this Mac's own ~/.claude, read-only. Counts only.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SOMETHING_TRIAL_REAL_CLAUDE"] == "1", "T-10 reads this Mac's own sessions: set SOMETHING_TRIAL_REAL_CLAUDE=1."))
    func theReaderOnThisMacsOwnSessions() {
        let reader = ClaudeReader(environment: ProcessInfo.processInfo.environment)
        var opened = 0, secrets = 0
        reader.opened = { path in opened += 1; if path.hasSuffix(".key") { secrets += 1 } }
        let watch = Watch(readers: [reader])
        var times: [Double] = []
        var seen = Seen()
        for _ in 0..<3 {
            let begin = Date()
            seen = watch.tick(now: Date())
            times.append(Date().timeIntervalSince(begin) * 1000)
        }
        let (agents, threads) = Watch.elsewhere(seen, registry: .described, groups: [], keys: [], now: Date())
        func count(_ values: [String?]) -> String {
            Dictionary(grouping: values.map { $0 ?? "null" }, by: { $0 }).mapValues(\.count).sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        }
        let missing: [(String, (Agent) -> Bool)] = [("name", { $0.name == nil }), ("folder", { $0.folder == nil }), ("pid", { $0.pid == nil }),
                                                    ("alive", { $0.alive == nil }), ("evidence", { $0.evidence == nil }), ("waiting", { $0.waiting == nil }),
                                                    ("thread", { $0.thread == nil }), ("model", { $0.model == nil }), ("mode", { $0.mode == nil }),
                                                    ("effort", { $0.effort == nil }), ("started", { $0.started == nil }), ("updated", { $0.updated == nil }),
                                                    ("error", { $0.error == nil })]
        let nulls = missing.map { key, isNull in "\(key) \(agents.filter(isNull).count)" }.joined(separator: ", ")
        print("""
        T-10 claude: reader \(seen.kinds["claude"]?.health ?? "none"), \(agents.count) agents, \(threads.reduce(0) { $0 + $1.turns.count }) turns, \
        \(threads.reduce(0) { $0 + $1.turns.reduce(0) { $0 + $1.items.count } }) items
        T-10 claude: states \(count(agents.map(\.state))); evidence \(count(agents.map(\.evidence))); waiting \(count(agents.map(\.waiting)))
        T-10 claude: alive \(count(agents.map { $0.alive.map(String.init) })); null keys: \(nulls)
        T-10 claude: files opened \(opened), secrets opened \(secrets); ms per tick: \(times.map { String(format: "%.1f", $0) }.joined(separator: ", "))
        """)
        #expect(secrets == 0)
    }
}

/// What the pseudo-terminal showed, kept for a failure's message only.
final class Screen: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func add(_ more: Data) { lock.withLock { data.append(more); if data.count > 200_000 { data = data.suffix(100_000) } } }
    /// The last characters shown, without the terminal's control sequences.
    var tail: String {
        let text = lock.withLock { String(decoding: data.suffix(20_000), as: UTF8.self) }
        let plain = text.replacingOccurrences(of: "\u{1b}(\\[[0-9;?>=]*[A-Za-z~]|\\][^\u{07}]*\u{07}|[78=>])", with: "", options: .regularExpression)
        return String(plain.split(whereSeparator: \.isWhitespace).joined(separator: " ").suffix(1500))
    }
}
