// OpenCodeReader over an invented OpenCode data folder built here: an opencode.db whose tables are those OpenCode
// 2.0.20 creates (column for column), messages in the shape real ones have (texts invented), and
// fake snapshots for the claim-and-holder rule: a live claim, a stale claim with only something's own server alive,
// a claim older than every process. A legacy-only database, as OpenCode desktop 1.x leaves, is read as changed.
import Darwin
import Foundation
import Testing
@testable import SomethingAgents
@testable import AgentACP
import SomethingCore

final class OpenCodeHome {
    static let shop = "ses_0a1b2c3d4e5fInventedShop1", blog = "ses_0a1b2c3d4e5fInventedBlog1", late = "ses_0a1b2c3d4e5fInventedLate1"
    static let done = "ses_0a1b2c3d4e5fInventedDone1", child = "ses_0a1b2c3d4e5fInventedKid01", old = "ses_0a1b2c3d4e5fInventedOld01"
    static let archived = "ses_0a1b2c3d4e5fInventedGone1"
    static let migration = "20260923013825_project_time_active"
    /// something's own pid in the snapshots: its child server's group is its own.
    static let own: Int32 = 50000

    /// The tables of OpenCode 2.0.20's opencode.db that the reader touches, and the legacy `session` beside them.
    static let tables = """
        CREATE TABLE `session_v2` (`id` text PRIMARY KEY, `project_id` text NOT NULL, `workspace_id` text, `parent_id` text,
          `fork_session_id` text, `fork_boundary` text, `slug` text NOT NULL, `directory` text NOT NULL, `path` text, `title` text,
          `version` text NOT NULL, `share_url` text, `summary_additions` integer, `summary_deletions` integer, `summary_files` integer,
          `summary_diffs` text, `metadata` text, `cost` real DEFAULT 0 NOT NULL, `tokens_input` integer DEFAULT 0 NOT NULL,
          `tokens_output` integer DEFAULT 0 NOT NULL, `tokens_reasoning` integer DEFAULT 0 NOT NULL, `tokens_cache_read` integer DEFAULT 0 NOT NULL,
          `tokens_cache_write` integer DEFAULT 0 NOT NULL, `revert` text, `permission` text, `agent` text, `model` text,
          `time_created` integer NOT NULL, `time_updated` integer NOT NULL, `time_compacting` integer, `time_archived` integer,
          `time_suspended` integer, `resume_attempts` integer DEFAULT 0 NOT NULL, `time_idle` integer, `time_viewed` integer, `idle_outcome` text,
          CONSTRAINT `fk_session_v2_project_id_project_id_fk` FOREIGN KEY (`project_id`) REFERENCES `project`(`id`) ON DELETE CASCADE);
        CREATE TABLE "session_message" (`id` text PRIMARY KEY, `session_id` text NOT NULL, `type` text NOT NULL, `seq` integer NOT NULL,
          `time_created` integer NOT NULL, `time_updated` integer NOT NULL, `data` text NOT NULL,
          CONSTRAINT `fk_session_message_session_id_session_v2_id_fk` FOREIGN KEY (`session_id`) REFERENCES `session_v2`(`id`) ON DELETE CASCADE);
        CREATE TABLE "migration" (id TEXT PRIMARY KEY, time_completed INTEGER NOT NULL);
        """ + OpenCodeHome.legacy
    /// The 1.x tables, which 2.x leaves frozen and OpenCode desktop 1.x still writes.
    static let legacy = """
        CREATE TABLE `session` (`id` text PRIMARY KEY, `project_id` text NOT NULL, `parent_id` text, `slug` text NOT NULL,
          `directory` text NOT NULL, `title` text NOT NULL, `version` text NOT NULL, `share_url` text, `summary_additions` integer,
          `summary_deletions` integer, `summary_files` integer, `summary_diffs` text, `revert` text, `permission` text,
          `time_created` integer NOT NULL, `time_updated` integer NOT NULL, `time_compacting` integer, `time_archived` integer);
        CREATE TABLE `message` (`id` text PRIMARY KEY, `session_id` text NOT NULL, `time_created` integer NOT NULL, `time_updated` integer NOT NULL, `data` text NOT NULL);
        CREATE TABLE `part` (`id` text PRIMARY KEY, `message_id` text NOT NULL, `session_id` text NOT NULL, `time_created` integer NOT NULL,
          `time_updated` integer NOT NULL, `data` text NOT NULL);
        """

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("opencode-home-\(UUID().uuidString)")
    var database: String { root.appendingPathComponent("data/opencode/opencode.db").path }
    let reader: OpenCodeReader
    private(set) var opened: [String] = []
    let now: Date
    /// Unix milliseconds, `seconds` before now.
    func ago(_ seconds: Double) -> Int64 { Int64((now.timeIntervalSince1970 - seconds) * 1000) }

    init(legacyOnly: Bool = false, now: Date = Date()) throws {
        self.now = now
        try FileManager.default.createDirectory(at: root.appendingPathComponent("data/opencode"), withIntermediateDirectories: true)
        reader = OpenCodeReader(environment: ["HOME": root.path, "XDG_DATA_HOME": root.appendingPathComponent("data").path])
        reader.own = OpenCodeHome.own
        reader.opened = { [unowned self] in opened.append($0) }
        if legacyOnly {
            try makeDatabase(database, OpenCodeHome.legacy + """
                INSERT INTO session VALUES ('ses_legacy', 'global', NULL, 'invented', '/Users/example/shop', 'Invented title', '1.18.30',
                  NULL, NULL, NULL, NULL, NULL, NULL, NULL, \(ago(60)), \(ago(60)), NULL, NULL);
                """)
            return
        }
        func session(_ id: String, title: String = "NULL", parent: String = "NULL", suspended: Int64? = nil, idle: Int64? = nil,
                     outcome: String? = nil, updated: Int64, archived: Int64? = nil, version: String = "2.0.20") -> String {
            func value(_ number: Int64?) -> String { number.map(String.init) ?? "NULL" }
            return """
                INSERT INTO session_v2 (id, project_id, parent_id, slug, directory, title, version, agent, model, time_created, time_updated,
                  time_archived, time_suspended, time_idle, idle_outcome)
                VALUES ('\(id)', 'global', \(parent), 'invented-slug', '/Users/example/shop', \(title), '\(version)', 'build',
                  '{"providerID":"fake","id":"fake-model","variant":"high"}', \(updated - 60_000), \(updated), \(value(archived)),
                  \(value(suspended)), \(value(idle)), \(outcome.map { "'\($0)'" } ?? "NULL"));
                """
        }
        var seq = 0
        func message(_ session: String, _ type: String, _ data: String, at: Int64) -> String {
            seq += 1
            return "INSERT INTO session_message VALUES ('msg_\(seq)', '\(session)', '\(type)', \(seq), \(at), \(at), '\(data)');"
        }
        let tool = #"{"type":"tool","id":"call_1","name":"bash","state":{"status":"completed","input":{"command":"rg cart","description":"Search"},"content":[{"type":"text","text":"INVENTED-OUTPUT-NEVER-SHOWN"}]},"time":{"created":1}}"#
        let assistant = #"{"agent":"build","model":{"id":"fake-model","providerID":"fake","variant":"high"},"content":[{"type":"reasoning","text":"Looking at the invented cart.","state":"INVENTED-STATE"},"#
            + #"{"type":"text","text":"Invented reply."},\#(tool),{"type":"tool","id":"call_2","name":"task","state":{"status":"running","input":{"description":"Invented helper","prompt":"Invented."}}}],"#
            + #""cost":0,"tokens":{"input":10,"output":5,"reasoning":0,"cache":{"read":0,"write":0}},"finish":"tool-calls","time":{"created":1,"completed":2}}"#
        try makeDatabase(database, OpenCodeHome.tables + [
            "INSERT INTO migration VALUES ('20260101000000_older', 1), ('\(OpenCodeHome.migration)', 2);",
            // The shop runs now, held by the person's OpenCode; its first turn ended.
            session(OpenCodeHome.shop, title: "'Blue cart button'", suspended: ago(30), idle: ago(300), outcome: "succeeded", updated: ago(400)),
            message(OpenCodeHome.shop, "user", #"{"text":"Make the cart button blue.","time":{"created":1}}"#, at: ago(400)),
            message(OpenCodeHome.shop, "assistant", #"{"agent":"build","content":[{"type":"text","text":"Done before."}],"finish":"stop","time":{"created":1,"completed":2}}"#, at: ago(390)),
            message(OpenCodeHome.shop, "idle", #"{"outcome":"succeeded","time":{"created":1}}"#, at: ago(300)),
            message(OpenCodeHome.shop, "synthetic", #"{"text":"Invented injected text.","time":{"created":1}}"#, at: ago(40)),
            message(OpenCodeHome.shop, "user", #"{"text":"Now the footer.","time":{"created":1}}"#, at: ago(30)),
            message(OpenCodeHome.shop, "assistant", assistant, at: ago(20)),
            // The blog's run was cut by a kill an hour ago; only something's own OpenCode server runs now.
            session(OpenCodeHome.blog, suspended: ago(3600), updated: ago(3700)),
            message(OpenCodeHome.blog, "user", #"{"text":"Fix the invented typo.","time":{"created":1}}"#, at: ago(3600)),
            message(OpenCodeHome.blog, "assistant", #"{"agent":"build","content":[],"finish":"error","error":{"type":"aborted","message":"Invented abort."},"time":{"created":1}}"#, at: ago(3590)),
            // Claimed twenty minutes ago: the person's OpenCode, started since, cannot hold it.
            session(OpenCodeHome.late, suspended: ago(1200), updated: ago(1300)),
            session(OpenCodeHome.done, idle: ago(100), outcome: "succeeded", updated: ago(200)),
            message(OpenCodeHome.done, "user", #"{"text":"Say hello.","time":{"created":1}}"#, at: ago(200)),
            message(OpenCodeHome.done, "assistant", #"{"agent":"build","content":[{"type":"text","text":"Hello."}],"finish":"stop","time":{"created":1,"completed":2}}"#, at: ago(150)),
            message(OpenCodeHome.done, "idle", #"{"outcome":"succeeded","time":{"created":1}}"#, at: ago(100)),
            session(OpenCodeHome.child, parent: "'\(OpenCodeHome.shop)'", suspended: ago(20), updated: ago(20), version: "2.0.21"),
            session(OpenCodeHome.old, idle: ago(3 * 86_400), outcome: "succeeded", updated: ago(3 * 86_400), version: "2.0.19"),
            session(OpenCodeHome.archived, updated: ago(60), archived: ago(50)),
        ].joined(separator: "\n"))
    }

    /// Called with defer where the home is made: a deinit does not always run before the test process ends.
    func remove() { try? FileManager.default.removeItem(at: root) }

    /// `person`: the person's OpenCode (its background service), started 15 minutes ago, outside something's groups.
    /// `ours`: something's own `opencode acp` and the server it starts, in the group of something's child.
    func snapshot(person: Bool = true, ours: Bool = true) -> Snapshot {
        var processes = [Running(pid: OpenCodeHome.own, parent: 1, group: OpenCodeHome.own, started: now.addingTimeInterval(-7200), name: "something")]
        if person { processes.append(Running(pid: 52000, parent: 1, group: 52000, started: now.addingTimeInterval(-900), name: "opencode")) }
        if ours {
            processes.append(Running(pid: 52100, parent: OpenCodeHome.own, group: 52100, started: now.addingTimeInterval(-7000), name: "opencode"))
            processes.append(Running(pid: 52101, parent: 52100, group: 52100, started: now.addingTimeInterval(-7000), name: "opencode"))
            // The server `opencode acp` starts, in a group of its own.
            processes.append(Running(pid: 52102, parent: 52100, group: 52102, started: now.addingTimeInterval(-7000), name: "opencode"))
        }
        return Snapshot(processes)
    }

    func read(_ snapshot: Snapshot? = nil) -> Reading { reader.read(snapshot ?? self.snapshot(), discover: false, now: now) }
}

@Suite(.leavesNothing("opencode-home-")) struct OpenCodeReaderTests {
    @Test func threeDaysLaterTheSameIsRead() throws {
        try sameThreeDaysLater { now in
            let home = try OpenCodeHome(now: now)
            defer { home.remove() }
            return stateWords(home.read().sightings, at: now)
        }
    }

    @Test func theRecentRootSessionsWithTheirTurns() throws {
        let home = try OpenCodeHome()
        defer { home.remove() }
        let reading = home.read()
        #expect(reading.health == "ok" && reading.version == "2.0.21" && reading.note == nil, "the newest session's program")
        // Not the sub-agent, the archived one or the one idle for three days.
        #expect(Set(reading.sightings.map(\.key)) == [OpenCodeHome.shop, OpenCodeHome.blog, OpenCodeHome.late, OpenCodeHome.done])
        let shop = try #require(reading.sightings.first { $0.key == OpenCodeHome.shop })
        #expect(shop.title == "Blue cart button" && shop.folder == "/Users/example/shop" && shop.model == "fake-model" && shop.effort == "high" && shop.mode == "build")
        #expect(shop.updated == OpenCodeReader.date(home.ago(20)) && shop.started == OpenCodeReader.date(home.ago(460)))
        #expect(shop.turns.map(\.state) == ["done", "working"] && shop.complete)
        let items = shop.turns[1].items
        #expect(items.map(\.kind) == ["message", "thought", "message", "tool", "subagent"])
        #expect(items[0].text == "Now the footer." && items[0].author == "person")
        #expect(items[3].text == "rg cart" && items[3].tool == Tool(name: "bash", status: "done"))
        #expect(items[4].text == "Invented helper" && items[4].tool == Tool(name: "task", status: "running"))
        let all = reading.sightings.flatMap(\.turns).flatMap(\.items).map(\.text).joined()
        #expect(!all.contains("NEVER-SHOWN") && !all.contains("INVENTED-STATE") && !all.contains("injected"))
        let done = try #require(reading.sightings.first { $0.key == OpenCodeHome.done })
        #expect(done.turns.map(\.state) == ["done"] && done.turns[0].items.map(\.text) == ["Say hello.", "Hello."])
    }

    /// A claim is held only by a live OpenCode process started at or before it, outside something's groups.
    @Test func theClaimAndHolderRule() throws {
        let home = try OpenCodeHome()
        defer { home.remove() }
        func words(_ reading: Reading) -> [String: (alive: Bool?, evidence: String?, state: String, pid: Int32?)] {
            Dictionary(uniqueKeysWithValues: reading.sightings.map { sighting in
                (sighting.key, (sighting.facts.alive, sighting.facts.evidence, StateMap.map(sighting.facts, now: home.now).state, sighting.pid))
            })
        }
        let both = words(home.read())
        #expect(both[OpenCodeHome.shop]! == (true, "claim", "working", 52000), "the person's OpenCode, started before the claim, holds it")
        #expect(both[OpenCodeHome.blog]! == (false, "claim", "interrupted", nil), "only our own server runs: nobody holds it")
        #expect(both[OpenCodeHome.late]! == (false, "claim", "interrupted", nil), "the person's OpenCode started after the claim")
        #expect(both[OpenCodeHome.done]! == (nil, nil, "unknown", nil), "an OpenCode runs: it may hold the idle session, or not")
        let reading = home.read()
        let blog = try #require(reading.sightings.first { $0.key == OpenCodeHome.blog })
        #expect(blog.because["resume"] == OpenCodeReader.mayResume && blog.facts.waiting == .unknown)
        #expect(blog.turns.last?.state == "interrupted" && blog.error == AgentError(code: "AGENT_ERROR", message: "Invented abort."))
        #expect(reading.sightings.first { $0.key == OpenCodeHome.shop }?.because.isEmpty == true)

        // Only something's own OpenCode: every claim is stale, every idle session done.
        let ours = words(home.read(home.snapshot(person: false)))
        #expect(ours[OpenCodeHome.shop]!.alive == false && ours[OpenCodeHome.shop]!.state == "interrupted")
        #expect(ours[OpenCodeHome.done]! == (false, "process", "done", nil))

        // Through the watch and the dedupe: the stale claim says why it may come back.
        let seen = Watch(readers: [home.reader], snapshot: { home.snapshot() }).tick(now: home.now)
        let (agents, threads) = Watch.elsewhere(seen, registry: .described, groups: [52100], keys: [OpenCodeHome.done], now: home.now)
        #expect(Set(agents.compactMap(\.thread)) == [OpenCodeHome.shop, OpenCodeHome.blog, OpenCodeHome.late], "a session something launched is left out by its id")
        let agent = try #require(agents.first { $0.thread == OpenCodeHome.blog })
        #expect(agent.because["resume"] == "something cannot continue OpenCode conversations started elsewhere yet. \(OpenCodeReader.mayResume)" && agent.because["send"] != nil && agent.pid == nil && agent.waiting == "none")
        #expect(agents.first { $0.thread == OpenCodeHome.shop }?.waiting == nil, "nobody can say what a running OpenCode waits on")
        #expect(threads.first { $0.id == OpenCodeHome.shop }?.turns.last?.state == "working")
    }

    @Test func theDatabaseIsQueriedOnlyWhenItMoves() throws {
        let home = try OpenCodeHome()
        defer { home.remove() }
        let before = home.read()
        #expect(home.opened == [home.database])
        // The person's OpenCode ends: the facts follow the processes without a query.
        let after = home.read(home.snapshot(person: false))
        #expect(home.opened.count == 1 && after.sightings.first { $0.key == OpenCodeHome.shop }?.facts.alive == false)
        #expect(before.sightings.first { $0.key == OpenCodeHome.shop }?.facts.alive == true)

        // The shop's run ends: its row and an idle mark are written, and the next tick reads them.
        try makeDatabase(home.database, """
            UPDATE session_v2 SET time_suspended = NULL, time_idle = \(home.ago(5)), idle_outcome = 'failed' WHERE id = '\(OpenCodeHome.shop)';
            INSERT INTO session_message VALUES ('msg_end', '\(OpenCodeHome.shop)', 'idle', 100, \(home.ago(5)), \(home.ago(5)), '{"outcome":"failed","time":{"created":1}}');
            """)
        let ended = try #require(home.read().sightings.first { $0.key == OpenCodeHome.shop })
        #expect(home.opened.count == 2 && ended.turns.map(\.state) == ["done", "error"] && ended.facts.failed && ended.facts.turnOpen == false)
    }

    /// No session names its program: the schema's last migration is all that is known.
    @Test func withoutASessionVersionTheMigrationIsSeen() throws {
        let home = try OpenCodeHome()
        defer { home.remove() }
        try makeDatabase(home.database, "UPDATE session_v2 SET version = '';")
        #expect(home.read().version == OpenCodeHome.migration)
    }

    @Test func aLegacyOnlyDatabaseIsChanged() throws {
        let home = try OpenCodeHome(legacyOnly: true)
        defer { home.remove() }
        let reading = home.read()
        #expect(reading.health == "changed" && reading.sightings.isEmpty)
        #expect(reading.note?.contains("OpenCode desktop 1.x") == true)
        let watch = Watch(readers: [home.reader], snapshot: { home.snapshot() })
        watch.own = OpenCodeHome.own
        let seen = watch.tick(now: home.now)
        #expect(seen.kinds["opencode"]?.health == "changed")
        // something's own `opencode acp`, and the server it starts in a group of its own, are not agents seen elsewhere.
        #expect(seen.sightings.compactMap(\.pid) == [52000] && seen.sightings.allSatisfy(\.processOnly))
        #expect(Watch.elsewhere(seen, registry: .described, groups: [52100], keys: [], now: home.now).agents.map(\.pid) == [52000])
    }

    /// OpenCode desktop 1.x keeps writing the 1.x tables of a database OpenCode 2 has moved on from.
    @Test func aDesktopStillWritingThe1xTablesIsSaid() throws {
        let home = try OpenCodeHome()
        defer { home.remove() }
        try makeDatabase(home.database, """
            INSERT INTO session VALUES ('ses_legacy', 'global', NULL, 'invented', '/Users/example/shop', 'Invented title', '1.18.30',
              NULL, NULL, NULL, NULL, NULL, NULL, NULL, \(home.ago(600)), \(home.ago(60)), NULL, NULL);
            """)
        let reading = home.read()
        #expect(reading.health == "ok" && reading.note == OpenCodeReader.desktop && reading.sightings.count == 4)
    }

    /// A refusal may pass: the next tick asks again, though the database did not move.
    @Test func anUnreadableDatabaseIsAskedAgain() throws {
        let home = try OpenCodeHome()
        defer { home.remove() }
        let before = try FileManager.default.attributesOfItem(atPath: home.database)[.modificationDate] as? Date
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: home.database)
        let refused = home.read()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: home.database)
        #expect(refused.health == "unreadable" && refused.sightings.isEmpty)
        let again = home.read()
        #expect(again.health == "ok" && again.sightings.count == 4 && home.opened.count == 2)
        #expect(try FileManager.default.attributesOfItem(atPath: home.database)[.modificationDate] as? Date == before)
    }

    @Test func aNewTurnClearsAnEarlierError() {
        var fold = OpenCodeTurns(session: "s")
        fold.add(["id": "m1", "type": "user", "text": "Invented."], blocks: [])
        fold.add(["id": "m2", "type": "assistant", "finish": "error", "failure": "Invented failure."], blocks: [])
        #expect(fold.error?.message == "Invented failure.")
        fold.add(["id": "m3", "type": "user", "text": "Invented again."], blocks: [])
        fold.add(["id": "m4", "type": "idle", "outcome": "succeeded"], blocks: [])
        #expect(fold.error == nil && fold.turns.map(\.state) == ["unknown", "done"])
    }

    @Test func aChangedShapeAMissingDatabaseAndNoHome() throws {
        #expect(OpenCodeReader(environment: [:]).read(Snapshot([]), discover: true, now: Date()) == Reading())
        #expect(OpenCodeReader(environment: ["HOME": "/Users/example/nowhere"]).read(Snapshot([]), discover: true, now: Date()) == Reading())
        let home = try OpenCodeHome(legacyOnly: true)
        defer { home.remove() }
        for suffix in ["", "-wal", "-shm"] { try FileManager.default.removeItem(atPath: home.database + suffix) }
        try makeDatabase(home.database, OpenCodeHome.tables.replacingOccurrences(of: "`time_suspended` integer, ", with: ""))
        let reading = home.read()
        #expect(reading.health == "changed" && reading.note == "OpenCode's database changed shape; its agents are shown as processes only.")
        #expect(OpenCodeReader(environment: ["OPENCODE_DB": home.database]).database == home.database)
    }
}
