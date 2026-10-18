// CodexReader over an invented ~/.codex built here: a state_5.sqlite whose threads table is the one Codex 0.162 and
// 0.163 create (column for column), rollouts in the shape real ones have (texts invented), writer
// locks, and fake snapshots whose codex processes hold some of them. SQLiteRO is proven here too.
import Darwin
import Foundation
import SQLite3
import Testing
@testable import SomethingAgents
import SomethingCore

/// Writes `sql` into a new SQLite database at `path`. Codex and OpenCode run in WAL mode and leave their `-wal` and
/// `-shm` files when they close, which a read-only open needs: `wal` does the same.
func makeDatabase(_ path: String, _ sql: String, wal: Bool = true) throws {
    var db: OpaquePointer?
    defer { sqlite3_close(db) }
    try #require(sqlite3_open(path, &db) == SQLITE_OK)
    if wal {
        var persist: Int32 = 1
        try #require(sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil) == SQLITE_OK)
        try #require(sqlite3_file_control(db, "main", SQLITE_FCNTL_PERSIST_WAL, &persist) == SQLITE_OK)
    }
    var message: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(db, sql, nil, nil, &message)
    #expect(result == SQLITE_OK, "\(message.map { String(cString: $0) } ?? "")")
    sqlite3_free(message)
}

final class CodexHome {
    static let shop = "019a2b3c-4d5e-7f60-8a1b-2c3d4e5f6a7b", blog = "019a2b3c-4d5e-7f60-8a1b-2c3d4e5f6a7c"
    static let old = "019a2b3c-4d5e-7f60-8a1b-2c3d4e5f6a7d", child = "019a2b3c-4d5e-7f60-8a1b-2c3d4e5f6a7e"
    static let review = "019a2b3c-4d5e-7f60-8a1b-2c3d4e5f6a7f", archived = "019a2b3c-4d5e-7f60-8a1b-2c3d4e5f6a80"
    static let stale = "019a2b3c-4d5e-7f60-8a1b-2c3d4e5f6a81", ours = "019a2b3c-4d5e-7f60-8a1b-2c3d4e5f6a82"

    /// The threads table as Codex creates it in state_5.sqlite.
    static let threads = """
        CREATE TABLE threads (
            id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
            source TEXT NOT NULL, model_provider TEXT NOT NULL, cwd TEXT NOT NULL, title TEXT NOT NULL, sandbox_policy TEXT NOT NULL,
            approval_mode TEXT NOT NULL, tokens_used INTEGER NOT NULL DEFAULT 0, has_user_event INTEGER NOT NULL DEFAULT 0,
            archived INTEGER NOT NULL DEFAULT 0, archived_at INTEGER, git_sha TEXT, git_branch TEXT, git_origin_url TEXT,
            cli_version TEXT NOT NULL DEFAULT '', first_user_message TEXT NOT NULL DEFAULT '', agent_nickname TEXT, agent_role TEXT,
            memory_mode TEXT NOT NULL DEFAULT 'enabled', model TEXT, reasoning_effort TEXT, agent_path TEXT, created_at_ms INTEGER,
            updated_at_ms INTEGER, thread_source TEXT, preview TEXT NOT NULL DEFAULT '', recency_at INTEGER NOT NULL DEFAULT 0,
            recency_at_ms INTEGER NOT NULL DEFAULT 0, history_mode TEXT NOT NULL DEFAULT 'legacy', name TEXT,
            is_pinned INTEGER NOT NULL DEFAULT 0, thread_section_id TEXT REFERENCES thread_sections(id) ON DELETE SET NULL,
            section_position INTEGER, section_entered_at_ms INTEGER, project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
            originator TEXT, daybreak_enabled BOOLEAN, creator_user_id TEXT, creator_account_id TEXT);
        CREATE TABLE _sqlx_migrations (version BIGINT PRIMARY KEY, description TEXT NOT NULL, installed_on TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            success BOOLEAN NOT NULL, checksum BLOB NOT NULL, execution_time BIGINT NOT NULL);
        """

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-home-\(UUID().uuidString)")
    var codex: URL { root.appendingPathComponent(".codex") }
    var locks: URL { codex.appendingPathComponent("thread-writer-locks") }
    let reader: CodexReader
    private(set) var opened: [String] = []
    let now = Date()

    func day(_ name: String) -> URL { codex.appendingPathComponent("sessions/\(name)") }
    func rollout(_ day: String, _ id: String) -> URL { self.day(day).appendingPathComponent("rollout-\(day.replacingOccurrences(of: "/", with: "-"))T10-55-00-\(id).jsonl") }
    func lock(_ id: String) -> String { locks.appendingPathComponent("\(id).lock").path }

    /// `index` false leaves the index out; `shape` replaces its CREATE TABLE.
    init(index: Bool = true, shape: String = CodexHome.threads) throws {
        reader = CodexReader(environment: ["HOME": root.path])
        for folder in ["2026/10/14", "2026/10/15", "2026/10/16", "2026/10/17"] {
            try FileManager.default.createDirectory(at: day(folder), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: locks, withIntermediateDirectories: true)
        // The lock Codex keeps for every writer, and the shop's writer lock.
        for name in [".coordination.lock", "\(CodexHome.shop).lock"] { try Data().write(to: locks.appendingPathComponent(name)) }
        try CodexHome.lines(CodexHome.shop, open: true).write(to: rollout("2026/10/17", CodexHome.shop))
        try CodexHome.lines(CodexHome.blog, open: false).write(to: rollout("2026/10/16", CodexHome.blog))
        try CodexHome.lines(CodexHome.ours, open: false, originator: "something").write(to: rollout("2026/10/16", CodexHome.ours))
        try CodexHome.lines(CodexHome.child, open: false, source: #"{"subagent":{"thread_spawn":{"parent_thread_id":"\#(CodexHome.shop)","depth":1}}}"#)
            .write(to: rollout("2026/10/17", CodexHome.child))
        // Compressed after a week idle: only the .zst is there, while the index still names the .jsonl.
        try Data([0x28, 0xb5, 0x2f, 0xfd]).write(to: URL(fileURLWithPath: rollout("2026/10/15", CodexHome.old).path + ".zst"))
        // A day folder older than the three newest: never walked.
        try CodexHome.lines(CodexHome.stale, open: false).write(to: rollout("2026/10/14", CodexHome.stale))
        reader.opened = { [unowned self] in opened.append($0) }
        guard index else { return }
        let recent = Int(now.timeIntervalSince1970) - 60, days = Int(now.timeIntervalSince1970) - 3 * 86_400
        func row(_ id: String, _ day: String, updated: Int, source: String = "vscode", threadSource: String = "user", archived: Int = 0,
                 originator: String = "codex-tui", name: String = "NULL") -> String {
            """
            INSERT INTO threads (id, rollout_path, created_at, updated_at, source, model_provider, cwd, title, sandbox_policy, approval_mode,
                archived, cli_version, model, reasoning_effort, thread_source, name, originator, history_mode)
            VALUES ('\(id)', '\(rollout(day, id).path)', \(updated - 600), \(updated), '\(source)', 'openai', '/Users/example/shop',
                'Invented first message', '{"type":"workspace-write"}', 'on-request', \(archived), '0.163.0', 'gpt-example', 'medium',
                '\(threadSource)', \(name), '\(originator)', 'paginated');
            """
        }
        // A changed shape gets no rows: they name the columns of the real one.
        try makeDatabase(codex.appendingPathComponent("state_5.sqlite").path, shape + (shape != CodexHome.threads ? [] : [
            row(CodexHome.shop, "2026/10/17", updated: recent, name: "'Blue cart button'"),
            row(CodexHome.blog, "2026/10/16", updated: recent),
            row(CodexHome.ours, "2026/10/16", updated: recent, originator: "something"),
            row(CodexHome.old, "2026/10/15", updated: recent),
            row(CodexHome.child, "2026/10/17", updated: recent, source: #"{"subagent":{"thread_spawn":{"depth":1}}}"#, threadSource: "subagent"),
            row(CodexHome.review, "2026/10/17", updated: recent, source: #"{"subagent":{"other":"guardian"}}"#, threadSource: "guardian_review"),
            row(CodexHome.archived, "2026/10/17", updated: recent, archived: 1),
            row(CodexHome.stale, "2026/10/14", updated: days),
        ]).joined(separator: "\n"))
        // An older index, which Codex leaves behind when it numbers a new one.
        try makeDatabase(codex.appendingPathComponent("state_4.sqlite").path, "CREATE TABLE threads (id TEXT PRIMARY KEY);")
    }

    /// Called with defer where the home is made: a deinit does not always run before the test process ends.
    func remove() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: codex.appendingPathComponent("state_5.sqlite").path)
        try? FileManager.default.removeItem(at: root)
    }

    /// A rollout as Codex writes it: line 0 a session_meta, then turns. The shop's second turn is still running.
    static func lines(_ id: String, open: Bool, originator: String = "codex-tui", source: String = #""vscode""#) -> Data {
        let meta = #"{"timestamp":"2026-10-17T08:55:00.000Z","ordinal":0,"type":"session_meta","payload":{"id":"\#(id)","session_id":"\#(id)","#
            + #""timestamp":"2026-10-17T08:55:00.000Z","cwd":"/Users/example/shop","originator":"\#(originator)","cli_version":"0.163.0","#
            + #""model_provider":"openai","source":\#(source),"thread_source":"user","history_mode":"paginated","#
            + #""base_instructions":{"provenance":{"type":"model","model":"gpt-example"},"text":"Invented instructions."}}}"#
        func turn(_ n: Int, _ asked: String, closed: String?) -> [String] {
            let at = "2026-10-17T09:0\(n):00.000Z"
            var lines = [
                #"{"timestamp":"\#(at)","ordinal":1,"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-\#(n)","started_at":1792227600,"model_context_window":258400,"collaboration_mode_kind":"default"}}"#,
                #"{"timestamp":"\#(at)","ordinal":2,"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Invented injected context."}]}}"#,
                #"{"timestamp":"\#(at)","ordinal":3,"type":"turn_context","payload":{"turn_id":"turn-\#(n)","cwd":"/Users/example/shop","model":"gpt-example","effort":"high","approval_policy":"on-request","summary":"auto"}}"#,
                #"{"timestamp":"\#(at)","ordinal":4,"type":"event_msg","payload":{"type":"item_completed","thread_id":"\#(id)","turn_id":"turn-\#(n)","started_at_ms":1792227600000,"completed_at_ms":1792227600001,"item":{"type":"UserMessage","id":"user-\#(n)","client_id":null,"content":[{"type":"text","text":"\#(asked)","text_elements":[]}]}}}"#,
                #"{"timestamp":"\#(at)","ordinal":5,"type":"event_msg","payload":{"type":"item_completed","thread_id":"\#(id)","turn_id":"turn-\#(n)","item":{"type":"Reasoning","id":"think-\#(n)","summary_text":["Looking at the invented cart."],"raw_content":[]}}}"#,
                #"{"timestamp":"\#(at)","ordinal":6,"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":1.0}}}}"#,
                #"{"timestamp":"\#(at)","ordinal":7,"type":"event_msg","payload":{"type":"item_completed","thread_id":"\#(id)","turn_id":"turn-\#(n)","item":{"type":"CommandExecution","id":"cmd-\#(n)","command":["/bin/zsh","-lc","rg cart"],"cwd":"/Users/example/shop","status":"completed","exit_code":0,"aggregated_output":"INVENTED-OUTPUT-NEVER-SHOWN"}}}"#,
                #"{"timestamp":"\#(at)","ordinal":8,"type":"event_msg","payload":{"type":"item_completed","thread_id":"\#(id)","turn_id":"turn-\#(n)","item":{"type":"FileChange","id":"patch-\#(n)","status":"completed","changes":{"/Users/example/shop/cart.css":{"type":"update","unified_diff":"INVENTED-DIFF-NEVER-SHOWN"}}}}}"#,
                #"{"timestamp":"\#(at)","ordinal":9,"type":"event_msg","payload":{"type":"item_completed","thread_id":"\#(id)","turn_id":"turn-\#(n)","item":{"type":"AgentMessage","id":"reply-\#(n)","phase":"final_answer","content":[{"type":"Text","text":"Invented reply \#(n)."}]}}}"#,
            ]
            if let closed {
                lines.append(#"{"timestamp":"\#(at)","ordinal":10,"type":"event_msg","payload":{"type":"\#(closed)","turn_id":"turn-\#(n)","started_at":1792227600,"completed_at":1792227660,"duration_ms":60000,"last_agent_message":null}}"#)
            }
            return lines
        }
        let all = [meta] + turn(1, "Make the cart button blue.", closed: "task_complete") + turn(2, "Now the footer.", closed: open ? nil : "task_complete")
        return Data((all.joined(separator: "\n") + "\n").utf8)
    }

    /// A codex process (Codex's background service, say) that holds the shop's writer lock, by its real path.
    func snapshot(holding: [String]? = nil, codex: Bool = true) -> Snapshot {
        var processes = [Running(pid: 40001, parent: 1, group: 40001, started: Date(timeIntervalSince1970: 1_792_220_000), name: "zsh")]
        if codex { processes.append(Running(pid: 51000, parent: 1, group: 51000, started: Date(timeIntervalSince1970: 1_792_220_100), name: "codex")) }
        let files = holding ?? [HeldFiles.real(lock(CodexHome.shop)), "/dev/null"]
        return Snapshot(processes, files: { $0 == 51000 ? files : nil })
    }

    func read(_ snapshot: Snapshot? = nil, discover: Bool = false) -> Reading {
        reader.read(snapshot ?? self.snapshot(), discover: discover, now: now)
    }
}

@Suite(.leavesNothing("codex-home-")) struct CodexReaderTests {
    @Test func theIndexGivesTheRecentConversationsOfPeople() throws {
        let home = try CodexHome()
        defer { home.remove() }
        let reading = home.read()
        #expect(reading.health == "ok" && reading.version == "0.163.0" && reading.note == nil)
        // Not the compressed one, the sub-agent, the review, the archived one or the one idle for three days.
        #expect(Set(reading.sightings.map(\.key)) == [CodexHome.shop, CodexHome.blog, CodexHome.ours])
        let shop = try #require(reading.sightings.first { $0.key == CodexHome.shop })
        #expect(shop.title == "Blue cart button" && shop.folder == "/Users/example/shop" && shop.detail["originator"] == .string("codex-tui"))
        #expect(shop.model == "gpt-example" && shop.effort == "high" && shop.mode == "on-request", "the rollout's last turn_context wins")
        #expect(shop.started == Date(timeIntervalSince1970: TimeInterval(Int(home.now.timeIntervalSince1970) - 660)))
        #expect(shop.turns.map(\.state) == ["done", "working"] && shop.complete)
        let items = shop.turns[1].items
        #expect(items.map(\.kind) == ["message", "thought", "tool", "tool", "message"])
        #expect(items[0].text == "Now the footer." && items[0].author == "person" && items[4].author == "agent")
        #expect(items[2].text == "/bin/zsh -lc rg cart" && items[2].tool == Tool(name: "shell", status: "done"))
        #expect(items[3].text == "/Users/example/shop/cart.css" && items[3].tool?.name == "apply_patch")
        #expect(!shop.turns.flatMap(\.items).contains { $0.text.contains("NEVER-SHOWN") || $0.text.contains("Invented injected context") })
        #expect(home.opened.contains(home.codex.appendingPathComponent("state_5.sqlite").path))
        #expect(!home.opened.contains { $0.hasSuffix("state_4.sqlite") || $0.hasSuffix(".zst") })
    }

    /// A long turn whose turn_context lies before the last 4 MB: the index gives the settings.
    @Test func theIndexGivesTheSettingsTheRolloutDoesNot() throws {
        let home = try CodexHome()
        defer { home.remove() }
        let marks = [#"{"timestamp":"2026-10-17T09:00:00.000Z","ordinal":900,"type":"event_msg","payload":{"type":"item_completed","turn_id":"t","item":{"type":"AgentMessage","id":"r","content":[{"type":"Text","text":"Invented."}]}}}"#,
                     #"{"timestamp":"2026-10-17T09:01:00.000Z","ordinal":901,"type":"event_msg","payload":{"type":"task_complete","turn_id":"t"}}"#]
        try Data((marks.joined(separator: "\n") + "\n").utf8).write(to: home.rollout("2026/10/16", CodexHome.blog))
        let blog = try #require(home.read().sightings.first { $0.key == CodexHome.blog })
        #expect(blog.model == "gpt-example" && blog.effort == "medium" && blog.mode == "on-request" && blog.turns.map(\.state) == ["done"])
    }

    @Test func theLockHolderSaysWhoIsAlive() throws {
        let home = try CodexHome()
        defer { home.remove() }
        let held = home.read()
        let shop = try #require(held.sightings.first { $0.key == CodexHome.shop })
        #expect(shop.facts.alive == true && shop.facts.evidence == "lock" && shop.pid == 51000 && shop.facts.turnOpen == true)
        #expect(shop.facts.waiting == .unknown, "Codex's files never say what it waits on")
        let words = StateMap.map(shop.facts, now: home.now)
        #expect(words.state == "working" && words.waiting == nil && words.evidence == "lock")
        // A codex process runs, but does not hold the blog: nobody can say.
        let blog = try #require(held.sightings.first { $0.key == CodexHome.blog })
        #expect(blog.facts.alive == nil && blog.pid == nil && StateMap.map(blog.facts, now: home.now).state == "unknown")

        // The rollout held open, not the lock, holds it too.
        let reader = try CodexHome()
        defer { reader.remove() }
        let open = reader.read(reader.snapshot(holding: [HeldFiles.real(reader.rollout("2026/10/16", CodexHome.blog).path)]))
        #expect(open.sightings.first { $0.key == CodexHome.blog }?.facts.alive == true)
        #expect(open.sightings.first { $0.key == CodexHome.shop }?.facts.alive == nil)

        // No codex process at all: every conversation has ended; one left mid-turn was interrupted.
        let fresh = try CodexHome()
        defer { fresh.remove() }
        let gone = fresh.read(home.snapshot(codex: false))
        #expect(gone.sightings.allSatisfy { $0.facts.alive == false && $0.facts.evidence == "process" && $0.pid == nil })
        let ended = gone.sightings.map { ($0.key, StateMap.map($0.facts, now: Date()).state) }
        #expect(Dictionary(uniqueKeysWithValues: ended) == [CodexHome.shop: "interrupted", CodexHome.blog: "done", CodexHome.ours: "done"])

        // A codex process whose open files the system does not give proves nothing.
        let hidden = try CodexHome()
        defer { hidden.remove() }
        let unknown = hidden.reader.read(Snapshot(hidden.snapshot().processes.values.map { $0 }, files: { _ in nil }), discover: false, now: hidden.now)
        #expect(unknown.sightings.allSatisfy { $0.facts.alive == nil })
    }

    @Test func theIndexIsQueriedOnlyWhenItMoves() throws {
        let home = try CodexHome()
        defer { home.remove() }
        _ = home.read()
        let index = home.codex.appendingPathComponent("state_5.sqlite").path
        let rollout = home.rollout("2026/10/17", CodexHome.shop).path
        #expect(home.opened.filter { $0 == index }.count == 1 && home.opened.filter { $0 == rollout }.count == 1)
        _ = home.read()
        #expect(home.opened.filter { $0 == index }.count == 1 && home.opened.filter { $0 == rollout }.count == 1, "nothing moved, nothing read")
        _ = home.read(discover: true)
        #expect(home.opened.filter { $0 == index }.count == 2, "the walk of every 15th tick queries it again, as the 24 hours move on")

        // The turn ends: only the new line is read, and the turn closes.
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: rollout))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((#"{"timestamp":"2026-10-17T09:03:00.000Z","ordinal":30,"type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted","turn_id":"turn-2"}}"# + "\n").utf8))
        try handle.close()
        let shop = try #require(home.read().sightings.first { $0.key == CodexHome.shop })
        #expect(shop.turns.map(\.state) == ["done", "interrupted"] && shop.turns[1].ended == "2026-10-17T09:03:00.000Z")
        #expect(shop.facts.aborted && shop.facts.turnOpen == false)
    }

    @Test func aChangedIndexFallsBackToTheLastThreeDays() throws {
        let home = try CodexHome(shape: CodexHome.threads.replacingOccurrences(of: "rollout_path TEXT NOT NULL", with: "path TEXT NOT NULL")
            .replacingOccurrences(of: "rollout_path", with: "path"))
        defer { home.remove() }
        let reading = home.read()
        #expect(reading.health == "changed" && reading.note == "Codex changed the format of its conversation list; something shows only the conversations of its last three days.")
        // The newest three day folders, without the sub-agent's rollout or the compressed one; the 14th is not read.
        #expect(Set(reading.sightings.map(\.key)) == [CodexHome.shop, CodexHome.blog, CodexHome.ours])
        let shop = try #require(reading.sightings.first { $0.key == CodexHome.shop })
        #expect(shop.folder == "/Users/example/shop" && shop.title == nil && shop.facts.alive == true && shop.turns.count == 2)
        #expect(!home.opened.contains { $0.contains(CodexHome.stale) })
        #expect(shop.model == "gpt-example", "the turn_context gives it without the index")

        // Through the watch, the readings stand: they are not replaced by processes.
        let seen = Watch(readers: [home.reader], snapshot: { home.snapshot() }).tick(now: home.now)
        #expect(seen.kinds["codex"]?.health == "changed" && seen.sightings.allSatisfy { !$0.processOnly } && seen.sightings.count == 3)
    }

    @Test func withoutAnIndexOrWithoutAHome() throws {
        #expect(CodexReader(environment: [:]).read(Snapshot([]), discover: true, now: Date()) == Reading())
        #expect(CodexReader(environment: ["HOME": "/Users/example/nowhere"]).read(Snapshot([]), discover: true, now: Date()) == Reading())
        let home = try CodexHome(index: false)
        defer { home.remove() }
        let reading = home.read()
        #expect(reading.health == "ok" && Set(reading.sightings.map(\.key)) == [CodexHome.shop, CodexHome.blog, CodexHome.ours])
        #expect(CodexReader(environment: ["HOME": "/Users/example/nowhere", "CODEX_HOME": home.codex.path]).read(home.snapshot(), discover: true, now: Date())
            .sightings.count == 3, "CODEX_HOME moves everything")

        let locked = try CodexHome()
        defer { locked.remove() }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.codex.appendingPathComponent("state_5.sqlite").path)
        let unreadable = locked.read()
        #expect(unreadable.health == "unreadable" && unreadable.sightings.count == 3 && unreadable.note?.contains("check its permissions") == true)
    }

    /// Listed while alive: a conversation idle for three days whose lock a codex process holds is read.
    @Test func aHeldConversationIdleForDaysIsListed() throws {
        let unheld = try CodexHome()
        defer { unheld.remove() }
        #expect(!unheld.read().sightings.contains { $0.key == CodexHome.stale })
        let home = try CodexHome()
        defer { home.remove() }
        try Data().write(to: URL(fileURLWithPath: home.lock(CodexHome.stale)))
        let held = home.read(home.snapshot(holding: [HeldFiles.real(home.lock(CodexHome.stale))]), discover: false)
        let stale = try #require(held.sightings.first { $0.key == CodexHome.stale }, "the held lock asks the index again")
        #expect(stale.facts.alive == true && stale.facts.evidence == "lock" && stale.pid == 51000)
        #expect(Watch(readers: [home.reader], snapshot: { home.snapshot(holding: [HeldFiles.real(home.lock(CodexHome.stale))]) })
            .tick(now: home.now).sightings.contains { $0.key == CodexHome.stale }, "the watch keeps what is alive")
    }

    /// A day folder may hold an "A_B" segment headed by A, and a second copy of A.
    @Test func theWalkKeepsOneFilePerConversation() throws {
        let home = try CodexHome(index: false)
        defer { home.remove() }
        let day = home.day("2026/10/17"), other = "019a2b3c-4d5e-7f60-8a1b-2c3d4e5f6a99"
        let segment = day.appendingPathComponent("rollout-2026-10-17T11-00-00-\(CodexHome.shop)_\(other).jsonl")
        let copy = day.appendingPathComponent("rollout-2026-10-17T09-00-00-\(CodexHome.shop).jsonl")
        try CodexHome.lines(CodexHome.shop, open: false).write(to: segment)
        try CodexHome.lines(CodexHome.shop, open: false).write(to: copy)
        try FileManager.default.setAttributes([.modificationDate: home.now.addingTimeInterval(-7200)], ofItemAtPath: copy.path)
        for _ in 0..<2 {
            let shops = home.read(discover: true).sightings.filter { $0.key == CodexHome.shop }
            #expect(shops.count == 1 && shops.first?.turns.map(\.state) == ["done", "working"], "the file named by its id, the newest of them")
        }
    }

    /// something's own codex holds only what it launched: with no other codex, what nobody holds has ended.
    @Test func ourOwnCodexProvesNothingOfTheOthers() throws {
        let home = try CodexHome()
        defer { home.remove() }
        home.reader.own = 1
        let reading = home.read()
        let blog = try #require(reading.sightings.first { $0.key == CodexHome.blog })
        #expect(blog.facts.alive == false && blog.facts.evidence == "process")
        #expect(reading.sightings.first { $0.key == CodexHome.shop }?.facts.alive == true, "it still holds what it launched, for the dedupe")
    }

    /// What something launched is dropped by its thread id; a thread something started in an earlier run is the
    /// person's now, seen elsewhere.
    @Test func dedupeByThreadAndOurOwnEarlierRuns() throws {
        let home = try CodexHome()
        defer { home.remove() }
        let seen = Watch(readers: [home.reader], snapshot: { home.snapshot() }).tick(now: home.now)
        let (agents, _) = Watch.elsewhere(seen, groups: [], keys: [CodexHome.shop], now: home.now)
        #expect(Set(agents.compactMap(\.thread)) == [CodexHome.blog, CodexHome.ours])
        let ours = try #require(agents.first { $0.thread == CodexHome.ours })
        #expect(ours.origin == "elsewhere" && ours.detail["originator"] == .string("something") && ours.id == "codex-\(CodexHome.ours)")
        #expect(Watch.elsewhere(seen, groups: [51000], keys: [], now: home.now).agents.allSatisfy { $0.thread != CodexHome.shop })
    }

    @Test func theTurnMarksMapAsTheDesignSays() {
        func fold(_ marks: [String]) -> CodexRollout {
            var rollout = CodexRollout(thread: "t")
            for (n, mark) in marks.enumerated() {
                rollout.add(Data(#"{"timestamp":"2026-10-17T09:00:0\#(n).000Z","ordinal":\#(n),"type":"event_msg","payload":\#(mark)}"#.utf8))
            }
            return rollout
        }
        let started = #"{"type":"task_started","turn_id":"a"}"#
        #expect(fold([started]).open == true)
        #expect(fold([started, #"{"type":"task_complete","turn_id":"a"}"#]).turns.map(\.state) == ["done"])
        #expect(fold([started, #"{"type":"turn_aborted","reason":"interrupted","turn_id":"a"}"#]).turns.map(\.state) == ["interrupted"])
        let failed = fold([started, #"{"type":"task_complete","turn_id":"a","error":{"message":"Invented failure.","codex_error_info":"other"}}"#])
        #expect(failed.turns.map(\.state) == ["error"] && failed.error == AgentError(code: "AGENT_ERROR", message: "Invented failure."))
        #expect(fold([started, started]).turns.map(\.state) == ["unknown", "working"], "a turn never closed is not called done")
        #expect(fold([]).open == nil)
        let recovered = fold([started, #"{"type":"task_complete","turn_id":"a","error":{"message":"Invented failure."}}"#, started, #"{"type":"task_complete","turn_id":"b"}"#])
        #expect(recovered.turns.map(\.state) == ["error", "done"] && recovered.error == nil, "a past failure is not the agent's last error")
        #expect(fold(Array(repeating: started, count: 12)).turns.count == Limits.turns && !fold(Array(repeating: started, count: 12)).complete)
    }
}

@Suite struct SQLiteROTests {
    @Test func readOnlyRowsAndTheWhitelist() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sqlite-ro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("odd ?#% name.db").path
        try makeDatabase(path, """
            CREATE TABLE notes (id TEXT, size INTEGER, weight REAL, body TEXT, secret TEXT);
            INSERT INTO notes VALUES ('a', 3, 1.5, '{"text":"Invented."}', 'invented-secret'), ('b', NULL, NULL, '{}', NULL);
            """)
        let db = try SQLiteRO(path, whitelist: ["notes": ["id", "size", "weight"]])
        #expect(try db.guarded() && !(try db.guarded(["notes": ["id", "colour"]])) && !(try db.guarded(["gone": ["id"]])))
        #expect(try db.tables()["notes"] == ["id", "size", "weight", "body", "secret"])
        let rows = try db.rows("SELECT id, size, weight, json_extract(body, '$.text') AS text FROM notes WHERE id >= ? ORDER BY id", ["a"])
        #expect(rows.count == 2 && rows[0]["id"] as? String == "a" && rows[0]["size"] as? Int64 == 3 && rows[0]["weight"] as? Double == 1.5)
        #expect(rows[0]["text"] as? String == "Invented." && rows[1]["size"] == nil && rows[1]["text"] == nil)
        for refused in ["SELECT body FROM notes", "SELECT * FROM notes", "SELECT id, secret AS fine FROM notes"] {
            #expect(throws: SQLiteRO.Failure.self, "\(refused)") { try db.rows(refused) }
        }
        #expect(throws: SQLiteRO.Failure.self) { try db.rows("DELETE FROM notes") }
        #expect(throws: SQLiteRO.Failure.self) { try db.rows("SELECT nothing FROM notes") }
        #expect(try SQLiteRO(path, whitelist: [:]).rows("SELECT count(*) AS n FROM notes").first?["n"] as? Int64 == 2, "an expression is the reader's choice")
        #expect(throws: SQLiteRO.Failure.self) { try SQLiteRO(folder.appendingPathComponent("missing.db").path, whitelist: [:]) }
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("missing.db").path), "never created")
    }
}
