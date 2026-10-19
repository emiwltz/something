// ClaudeReader against an invented ~/.claude (Tests/Fixtures/claude-home) of the exact shapes Claude Code 2.1.296 to
// 2.1.299 writes, with fake snapshots: two live sessions in two projects, a record whose pid was reused, a record whose
// process is gone, and the secret `.key` files beside them, which the reader must never open. Each case copies the
// home into a throwaway folder, so it can change files, dates and permissions, and dates its conversations from its
// own `now`: no case depends on the day it runs.
import Foundation
import Testing
@testable import SomethingAgents
import SomethingCore

final class ClaudeHome {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/claude-home")
    static let shop = "0f1e2d3c-4b5a-4678-8901-234567890abc", blog = "6a7b8c9d-0e1f-4a2b-8c3d-4e5f6a7b8c9d"
    static let notes = "11111111-2222-4333-8444-555555555555"

    let root: URL
    var claude: URL { root.appendingPathComponent(".claude") }
    var sessions: URL { claude.appendingPathComponent("sessions") }
    let reader: ClaudeReader
    let now: Date
    private(set) var opened: [String] = []

    /// `prefix` names the folder in $TMPDIR: the default is ClaudeReaderTests' own, and another suite passes its own,
    /// so that each suite's `.leavesNothing` counts only the folders it made. Each conversation was last written as
    /// long before `now` as its last line is before the shop's moment (17 October 2026, 09:00:10): the shop's 8
    /// seconds, the blog's 80 minutes, the notes' eleven days.
    init(prefix: String = "claude-home-", now: Date = Date()) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)\(UUID().uuidString)")
        reader = ClaudeReader(environment: ["HOME": root.path])
        self.now = now
        try FileManager.default.copyItem(at: ClaudeHome.fixture, to: root)
        for (folder, id, age) in [("-Users-example-shop", ClaudeHome.shop, 8.0), ("-Users-example-blog-v2", ClaudeHome.blog, 4800),
                                  ("-Users-example-notes", ClaudeHome.notes, 11 * 86_400)] {
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: transcript(folder, id).path)
        }
        // The secrets Claude keeps beside its records. Never in the repository: a file named *.key would be one there.
        for pid in [41234, 41300, 40001] {
            try Data("{\"peerToken\":\"invented\"}".utf8).write(to: sessions.appendingPathComponent("\(pid).\(String(repeating: "ab", count: 32)).key"))
        }
        reader.opened = { [unowned self] in opened.append($0) }
    }

    /// Called with defer where the home is made: a deinit does not always run before the test process ends.
    func remove() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sessions.path)
        try? FileManager.default.removeItem(at: root)
    }

    /// Claude's processes as libproc would give them: the shop's and the blog's at their record's start, and a
    /// process that reuses the notes record's pid, started later.
    static func snapshot(shop: Bool = true, blog: Bool = true) -> Snapshot {
        var processes = [Running(pid: 40001, parent: 1, group: 40001, started: Date(timeIntervalSince1970: 1_792_220_000), name: "zsh")]
        if shop { processes.append(Running(pid: 41234, parent: 41200, group: 41234, started: Date(timeIntervalSince1970: 1_792_227_300.4), name: "claude")) }
        if blog { processes.append(Running(pid: 41300, parent: 41290, group: 41290, started: Date(timeIntervalSince1970: 1_792_222_200.9), name: "claude")) }
        return Snapshot(processes)
    }

    /// What the reader gives at `now`, the home's own when nil.
    func read(_ snapshot: Snapshot = ClaudeHome.snapshot(), discover: Bool = false, now: Date? = nil) -> Reading {
        reader.read(snapshot, discover: discover, now: now ?? self.now)
    }

    func transcript(_ folder: String, _ id: String) -> URL { claude.appendingPathComponent("projects/\(folder)/\(id).jsonl") }
}

/// No time bomb: a reader test reads an invented home dated from its own `now`, never from the day the fixture was
/// written. `states` reads a home made at `now`; the same home three days later must give the same state words,
/// by conversation, and some.
func sameThreeDaysLater(_ states: (Date) throws -> [String: String]) throws {
    let today = try states(Date())
    #expect(!today.isEmpty)
    #expect(try states(Date().addingTimeInterval(3 * 86_400)) == today)
}

/// The state word of each sighting at `now`, by the last part of its key (a pi or OMP key is the log's path).
func stateWords(_ sightings: [Sighting], at now: Date) -> [String: String] {
    Dictionary(uniqueKeysWithValues: sightings.map { (($0.key as NSString).lastPathComponent, StateMap.map($0.facts, now: now).state) })
}

@Suite(.leavesNothing("claude-home-")) struct ClaudeReaderTests {
    @Test func threeDaysLaterTheSameIsRead() throws {
        try sameThreeDaysLater { now in
            let home = try ClaudeHome(now: now)
            defer { home.remove() }
            return stateWords(home.read().sightings, at: now)
        }
    }

    @Test func twoLiveSessionsAreReadAndTheStaleOnesIgnored() throws {
        let home = try ClaudeHome()
        defer { home.remove() }
        let reading = home.read()
        #expect(reading.health == "ok" && reading.note == nil)
        #expect(reading.version == "2.1.299", "the newest version of a live record")
        let sightings = Dictionary(uniqueKeysWithValues: reading.sightings.map { ($0.key, $0) })
        #expect(Set(sightings.keys) == [ClaudeHome.shop, ClaudeHome.blog], "a reused pid and a gone process are stale")

        let shop = try #require(sightings[ClaudeHome.shop])
        #expect(shop.pid == 41234 && shop.folder == "/Users/example/shop" && shop.title == "Dark mode for the cart")
        #expect(shop.facts.alive == true && shop.facts.evidence == "registry" && shop.facts.waiting == .permission && shop.facts.turnOpen == true)
        let words = StateMap.map(shop.facts, now: Date())
        #expect(words.state == "waiting" && words.waiting == "permission" && words.evidence == "registry")
        #expect(shop.model == "claude-example-model" && shop.effort == "high" && shop.mode == "default")
        #expect(shop.started == Date(timeIntervalSince1970: 1_792_227_300.4))
        let turn = try #require(shop.turns.last)
        #expect(shop.turns.count == 1 && turn.state == "working" && turn.started == "2026-10-17T08:59:50.000Z")
        #expect(turn.items.map(\.kind) == ["message", "thought", "message", "tool"], "no meta line, no attachment, no sidechain")
        #expect(turn.items.map(\.author) == ["person", "agent", "agent", "agent"])
        #expect(turn.items[0].text == "Add a dark mode to the cart page.")
        #expect(turn.items[3].text == "npm test" && turn.items[3].tool == Tool(name: "Bash", status: "running") && turn.items[3].decision == nil)

        let blog = try #require(sightings[ClaudeHome.blog])
        #expect(blog.title == "Blog typo", "the person's title wins over Claude's")
        #expect(blog.facts.turnOpen == true && blog.facts.waiting == .nothing)
        #expect(blog.turns.map(\.state) == ["done", "working"])
        // Its last reply is two lines, a thought and a text, each saying end_turn: one turn holds both.
        #expect(blog.turns[0].items.map(\.text) == ["Fix the typo in the about page.", "/Users/example/blog_v2/about.md",
                                                    "Invented: one word was misspelled.", "Invented: the typo is fixed."])
        #expect(blog.turns[0].items.map(\.kind) == ["message", "tool", "thought", "message"])
        #expect(blog.turns[0].items[1].tool == Tool(name: "Edit", status: "done"))
        #expect(blog.turns[0].ended == "2026-10-17T07:31:09.000Z")
        #expect(blog.turns[1].items.map(\.kind) == ["message", "subagent", "message"], "a helper's notice is not the person's")
        #expect(blog.turns[1].items.map(\.text) == ["Now check the links.", "Check the links", "Also the footer."])

        // Only the four records and the two live transcripts were opened: never a secret, never a stale transcript.
        #expect(!home.opened.contains { $0.hasSuffix(".key") })
        #expect(Set(home.opened.map { ($0 as NSString).lastPathComponent }) == ["41234.json", "41300.json", "40001.json", "39999.json",
                                                                                "\(ClaudeHome.shop).jsonl", "\(ClaudeHome.blog).jsonl"])
        // Nothing is deleted, the stale records included.
        #expect(try FileManager.default.contentsOfDirectory(atPath: home.sessions.path).count == 7)
    }

    @Test func aSecondTickReadsOnlyWhatChanged() throws {
        let home = try ClaudeHome()
        defer { home.remove() }
        _ = home.read()
        let before = home.opened.count
        #expect(home.read().sightings.count == 2)
        #expect(home.opened.count == before, "nothing changed, nothing is opened")
        // The blog's turn ends, and its record says idle.
        let blog = home.transcript("-Users-example-blog-v2", ClaudeHome.blog)
        let end = #"{"parentUuid":null,"isSidechain":false,"type":"assistant","message":{"id":"msg_b4invented","role":"assistant","model":"claude-example-model","content":[{"type":"text","text":"Invented: the links are fine."}],"stop_reason":"end_turn"},"uuid":"b0000000-0000-4000-8000-000000000011","timestamp":"2026-10-17T07:41:00.000Z"}"#
        let handle = try FileHandle(forWritingTo: blog)
        handle.seekToEndOfFile()
        handle.write(Data((end + "\n").utf8))
        try handle.close()
        let record = home.sessions.appendingPathComponent("41300.json")
        try String(decoding: try Data(contentsOf: record), as: UTF8.self).replacingOccurrences(of: #""status":"busy""#, with: #""status":"idle""#)
            .write(to: record, atomically: true, encoding: .utf8)
        let sighting = try #require(home.read().sightings.first { $0.key == ClaudeHome.blog })
        #expect(sighting.turns.map(\.state) == ["done", "done"])
        #expect(sighting.turns[1].items.last?.text == "Invented: the links are fine.")
        #expect(StateMap.map(sighting.facts, now: Date()).state == "idle")
        #expect(home.opened.count == before + 2, "the changed record and the changed transcript")
    }

    @Test func anEndIsShownAndAnOldOneLeavesTheList() throws {
        let home = try ClaudeHome()
        defer { home.remove() }
        _ = home.read()
        // The shop's Claude exits normally (its record goes); the blog's dies (its record stays behind).
        try FileManager.default.removeItem(at: home.sessions.appendingPathComponent("41234.json"))
        let reading = home.read(ClaudeHome.snapshot(shop: false, blog: false))
        let sightings = Dictionary(uniqueKeysWithValues: reading.sightings.map { ($0.key, $0) })
        let shop = try #require(sightings[ClaudeHome.shop]), blog = try #require(sightings[ClaudeHome.blog])
        #expect(shop.facts.alive == false && shop.facts.ended && StateMap.map(shop.facts, now: Date()).state == "done")
        #expect(blog.facts.alive == false && !blog.facts.ended && StateMap.map(blog.facts, now: Date()).state == "interrupted",
                "gone mid-turn, its record left behind")
        #expect(FileManager.default.fileExists(atPath: home.sessions.appendingPathComponent("41300.json").path), "never deleted")
        // A day after its last write, an ended conversation is no longer listed.
        #expect(home.read(ClaudeHome.snapshot(shop: false, blog: false), now: home.now.addingTimeInterval(Watch.recent + 60)).sightings.isEmpty)
    }

    /// Claude rewrites a record whole: one caught mid-write (or too big) keeps the session as it was.
    @Test func aTornRecordEndsNothing() throws {
        let home = try ClaudeHome()
        defer { home.remove() }
        _ = home.read()
        let record = home.sessions.appendingPathComponent("41300.json")
        try Data(#"{"pid":41300,"sessionId":"6a7b"#.utf8).write(to: record)
        let torn = try #require(home.read().sightings.first { $0.key == ClaudeHome.blog })
        #expect(torn.facts.alive == true && !torn.facts.ended && torn.facts.turnOpen == true)
        // A record never read yet, torn on its first sighting, is not taken for an end either.
        let fresh = try ClaudeHome()
        defer { fresh.remove() }
        try Data(#"{"pid":41300,"sessionId":"6a7b"#.utf8).write(to: fresh.sessions.appendingPathComponent("41300.json"))
        #expect(Set(fresh.read().sightings.map(\.key)) == [ClaudeHome.shop])
    }

    /// A long transcript read from its end says that its first turns are missing, and so does one that grew by more
    /// than 4 MB between two ticks, whose turns are kept.
    @Test func turnsNotReadMakeTheThreadIncomplete() throws {
        let home = try ClaudeHome()
        defer { home.remove() }
        let blog = home.transcript("-Users-example-blog-v2", ClaudeHome.blog)
        #expect(home.read().sightings.first { $0.key == ClaudeHome.blog }?.complete == true, "read from its first byte")
        let filler = String(repeating: #"{"type":"progress","data":"Invented filler."}"# + "\n", count: 120_000)
        let append = { (text: String) in
            let handle = try FileHandle(forWritingTo: blog)
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try handle.close()
        }
        let end = #"{"isSidechain":false,"type":"assistant","message":{"id":"msg_b5invented","role":"assistant","model":"claude-example-model","content":[{"type":"text","text":"Invented: the links are fine."}],"stop_reason":"end_turn"},"uuid":"b0000000-0000-4000-8000-000000000014","timestamp":"2026-10-17T07:50:00.000Z"}"#
        try append(filler + end + "\n")
        let gap = try #require(home.read().sightings.first { $0.key == ClaudeHome.blog })
        #expect(!gap.complete && gap.turns.map(\.state) == ["done", "done"], "the turns before the gap are kept")
        #expect(gap.turns[1].items.last?.text == "Invented: the links are fine.")

        let long = try ClaudeHome(), longBlog = long.transcript("-Users-example-blog-v2", ClaudeHome.blog)
        defer { long.remove() }
        try (Data(filler.utf8) + Data(contentsOf: longBlog)).write(to: longBlog)
        let tail = try #require(long.read().sightings.first { $0.key == ClaudeHome.blog })
        #expect(!tail.complete && tail.turns.count == 2)
    }

    @Test func aTranscriptOutsideItsFolderIsFoundByTheWalk() throws {
        let home = try ClaudeHome()
        defer { home.remove() }
        // A start folder Claude named another way (a long path, a worktree): the file is elsewhere under projects/.
        let moved = home.claude.appendingPathComponent("projects/-Users-example-shop-long")
        try FileManager.default.createDirectory(at: moved, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: home.transcript("-Users-example-shop", ClaudeHome.shop), to: moved.appendingPathComponent("\(ClaudeHome.shop).jsonl"))
        let first = home.read()
        #expect(first.sightings.first { $0.key == ClaudeHome.shop }?.turns.count == 1, "the first sighting walks once")
    }

    @Test func aNewTranscriptWaitsForTheWalk() throws {
        let home = try ClaudeHome()
        defer { home.remove() }
        let original = home.transcript("-Users-example-shop", ClaudeHome.shop)
        let kept = home.root.appendingPathComponent("kept.jsonl")
        try FileManager.default.moveItem(at: original, to: kept)
        #expect(home.read().sightings.first { $0.key == ClaudeHome.shop }?.turns.isEmpty == true, "no transcript yet")
        let other = home.claude.appendingPathComponent("projects/-Users-example-shop-other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: kept, to: other.appendingPathComponent("\(ClaudeHome.shop).jsonl"))
        #expect(home.read().sightings.first { $0.key == ClaudeHome.shop }?.turns.isEmpty == true, "walked only every 15th tick")
        #expect(home.read(discover: true).sightings.first { $0.key == ClaudeHome.shop }?.turns.count == 1)
    }

    @Test func theRegistryWordsMapAsTheDesignSays() throws {
        let home = try ClaudeHome()
        defer { home.remove() }
        let record = home.sessions.appendingPathComponent("41234.json")
        let original = String(decoding: try Data(contentsOf: record), as: UTF8.self)
        let cases: [(String, StateMap.Waiting, Bool?, String?)] = [
            (#""status":"waiting","waitingFor":"permission prompt""#, .permission, true, nil),
            (#""status":"waiting","waitingFor":"sandbox request""#, .permission, true, nil),
            (#""status":"waiting","waitingFor":"input needed""#, .answer, true, "input needed"),
            (#""status":"waiting","waitingFor":"goal proposal""#, .answer, true, "goal proposal"),
            (#""status":"shell""#, .nothing, false, nil),
            (#""status":"idle""#, .nothing, false, nil),
        ]
        for (words, waiting, open, raw) in cases {
            let text = original.replacingOccurrences(of: #""status":"waiting","waitingFor":"permission prompt""#, with: words)
            try text.write(to: record, atomically: true, encoding: .utf8)
            let shop = try #require(home.read().sightings.first { $0.key == ClaudeHome.shop })
            #expect(shop.facts.waiting == waiting && shop.facts.turnOpen == open, "\(words)")
            #expect(shop.detail["waitingFor"] == raw.map(JSONValue.string), "\(words)")
            #expect(shop.stateKnown && (shop.detail["backgroundShell"] != nil) == words.contains("shell"), "\(words)")
        }

        // A session idle while its background shell runs: a closed turn, said in the detail.
        try original.replacingOccurrences(of: #""status":"waiting","waitingFor":"permission prompt""#, with: #""status":"shell""#)
            .write(to: record, atomically: true, encoding: .utf8)
        var agent = try #require(Watch.elsewhere(Seen(sightings: home.read().sightings), groups: [], keys: [], now: Date()).agents.first { $0.thread == ClaudeHome.shop })
        #expect(agent.state == "idle" && agent.waiting == "none" && agent.detail["backgroundShell"] == .bool(true))

        // A status word the reader does not know: the holder is alive, what it does is unknown, never idle.
        try original.replacingOccurrences(of: #""status":"waiting","waitingFor":"permission prompt""#, with: #""status":"pondering""#)
            .write(to: record, atomically: true, encoding: .utf8)
        let shop = try #require(home.read().sightings.first { $0.key == ClaudeHome.shop })
        #expect(!shop.stateKnown && shop.detail["status"] == .string("pondering"))
        agent = try #require(Watch.elsewhere(Seen(sightings: [shop]), groups: [], keys: [], now: Date()).agents.first)
        #expect(agent.alive == true && agent.evidence == "registry" && agent.state == "unknown" && agent.waiting == nil)
    }

    @Test func theHealthOfTheReader() throws {
        #expect(ClaudeReader(environment: [:]).read(ClaudeHome.snapshot(), discover: true, now: Date()) == Reading(), "no home: none")
        #expect(ClaudeReader(environment: ["HOME": "/Users/example/nowhere"]).read(ClaudeHome.snapshot(), discover: true, now: Date()).health == "none")
        let home = try ClaudeHome()
        defer { home.remove() }
        #expect(ClaudeReader(environment: ["HOME": "/Users/example/nowhere", "CLAUDE_CONFIG_DIR": home.claude.path])
            .read(ClaudeHome.snapshot(), discover: true, now: Date()).sightings.count == 2, "CLAUDE_CONFIG_DIR moves everything")

        // A record without the keys the reader needs: Claude's files changed shape.
        try Data(#"{"pid":41500,"session":"renamed","kind":"interactive"}"#.utf8).write(to: home.sessions.appendingPathComponent("41500.json"))
        let changed = home.read()
        #expect(changed.health == "changed" && changed.sightings.isEmpty)
        #expect(changed.note == "Claude Code's session files changed shape; its agents are shown as processes only.")
        try FileManager.default.removeItem(at: home.sessions.appendingPathComponent("41500.json"))

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: home.sessions.path)
        #expect(home.read().health == "unreadable")
    }

    @Test func aRecordOfAnotherSystemCannotBeChecked() throws {
        let home = try ClaudeHome()
        defer { home.remove() }
        let record = home.sessions.appendingPathComponent("41234.json")
        try String(decoding: try Data(contentsOf: record), as: UTF8.self).replacingOccurrences(of: #""pidDomain":"darwin""#, with: #""pidDomain":"linux:invented""#)
            .write(to: record, atomically: true, encoding: .utf8)
        let shop = try #require(home.read(ClaudeHome.snapshot(shop: false)).sightings.first { $0.key == ClaudeHome.shop })
        #expect(shop.facts.alive == nil && shop.facts.evidence == nil)
    }

    @Test func theStartTimeAndTheFolderName() {
        #expect(ClaudeReader.processStart("Tue Oct  6 07:30:00 2026") == Date(timeIntervalSince1970: 1_791_271_800))
        #expect(ClaudeReader.processStart("Sat Oct 17 08:55:00 2026") == Date(timeIntervalSince1970: 1_792_227_300))
        #expect(ClaudeReader.processStart("17/10/2026") == nil)
        #expect(ClaudeReader.folderName("/Users/example/my_shop.v2") == "-Users-example-my-shop-v2")
        #expect(ClaudeReader.folderName("/Users/example/café 1") == "-Users-example-caf--1")
    }
}
