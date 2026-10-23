// Conformance: every extension the app registers survives what a newer or broken agent may give it, rather than
// trapping, which would take the whole app down. Each driver is fed its recorded exchanges with one of the program's
// lines at a time truncated, retyped or dropped; each reader is fed its invented home with one file at a time turned to
// garbage, one field at a time removed, and every file garbage at once. A driver must not know a line cut in half (its
// kind's note then says so, Launched.foreign), and a line retyped below its top-level words is an error, or read for
// those words alone, or as nothing. A reader must return within 5 s and give a reading the contract takes, through the
// watch; a fresh one makes no conversation of garbage. What a reader says of damaged files beyond that (which health,
// which note) is its own tests' to prove: here it is survival. A new extension joins by its exchanges and its home below.
import Foundation
import SQLite3
import Testing
@testable import SomethingAgents
@testable import AgentACP
@testable import AgentAmp
@testable import AgentClaude
@testable import AgentCodex
@testable import AgentPi
import SomethingCore

/// One case at a time: side by side, its thousands of replays and damages took about seven cores for two seconds,
/// beside the suites bound by time (SpawnTests); one after another, about six seconds of one core.
@Suite(.serialized, .leavesNothing("conformance-")) struct ConformanceTests {
    static let launchable = Registry.described.agents.filter { $0.driving != nil }.map(\.kind)
    /// Those whose reader reads files: one that sees processes only (OtherReader) has none to damage.
    static let read = Registry.described.agents.filter { $0.reader.map { !($0([:]) is OtherReader) } ?? false }.map(\.kind)

    // MARK: Drivers

    /// What may become of one line of the program.
    enum Damage: CaseIterable { case truncated, retyped, retypedButWords, dropped }

    @Test(arguments: launchable) func aDriverSurvivesDamagedLines(kind: String) throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Exchanges/\(kind)")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".jsonl") }.sorted()
        #expect(!names.isEmpty, "\(kind) has no recorded exchange in Tests/Exchanges/\(kind)")
        var runs = 0
        for name in names {
            let rows = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8).split(separator: "\n").map { text in
                try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            }
            let lines = rows.indices.filter { rows[$0][kind] is [String: Any] }
            let whole = try play(rows, kind: kind, damaged: -1, .dropped, at: "\(name) whole")
            for line in lines {
                var outcomes: [Damage: Outcome] = [:]
                for damage in Damage.allCases {
                    outcomes[damage] = try play(rows, kind: kind, damaged: line, damage, at: "\(name):\(line + 1) \(damage)")
                    runs += 1
                }
                // A line retyped below its top-level words that its driver takes as known says an error, or is read
                // for those words alone (the conversation has the shape it has with the line whole), or as nothing
                // (the shape without it): never as another conversation. A text it could not read may be shown raw.
                if let retyped = outcomes[.retyped], retyped.known, let dropped = outcomes[.dropped] {
                    #expect(retyped.erred || [dropped, whole].contains { retyped.fits($0) },
                            "\(name):\(line + 1): a retyped line was taken as known, said no error, and made another conversation")
                }
            }
        }
        #expect(runs > 0)
    }

    /// What one damaged replay left: whether the driver knew the damaged line, whether it said an error for it, and
    /// the conversation at the end.
    struct Outcome {
        var known = false, erred = false
        var thread: AgentThread?

        /// Whether its conversation has the shape of `other`'s: the same turns, states, items and tools, whatever the
        /// items' texts (one it could not read may be shown raw), and a tool's outcome it left unknown fits any.
        func fits(_ other: Outcome) -> Bool {
            guard var mine = thread, var theirs = other.thread else { return thread == nil && other.thread == nil }
            for (turn, theirTurn) in zip(mine.turns.indices, theirs.turns.indices) {
                for (item, theirItem) in zip(mine.turns[turn].items.indices, theirs.turns[theirTurn].items.indices) {
                    (mine.turns[turn].items[item].text, mine.turns[turn].items[item].truncated) = ("", false)
                    (theirs.turns[theirTurn].items[theirItem].text, theirs.turns[theirTurn].items[theirItem].truncated) = ("", false)
                    if mine.turns[turn].items[item].tool?.status == nil { theirs.turns[theirTurn].items[theirItem].tool?.status = nil }
                }
            }
            return mine == theirs
        }
    }

    /// Plays `rows` as the replays do, but for the program's line `damaged`, and with every call of something allowed
    /// to fail: what is checked is that the driver lives, knows no line it cannot read, and leaves an agent the
    /// contract can encode.
    func play(_ rows: [[String: Any]], kind: String, damaged: Int, _ damage: Damage, at: String) throws -> Outcome {
        let first = rows.first ?? [:]
        let resume = first["resume"] as? String, model = first["model"] as? String, assistant = first["assistant"] as? Bool ?? false
        let replay: Replay
        switch kind {
        case "claude": replay = Replay(assistant: assistant)
        case "codex": replay = .codex(resume: resume, assistant: assistant)
        case "opencode": replay = .opencode(model: model, resume: resume)
        case "pi": replay = .pi(model: model, effort: first["effort"] as? String, resume: resume)
        case "omp": replay = .omp(assistant: assistant)
        case "amp": replay = .amp(assistant: assistant)
        default:
            Issue.record("\(kind) has a driver but no replay here: add it to ConformanceTests.play")
            return Outcome()
        }
        var outcome = Outcome()
        for (index, row) in rows.enumerated() {
            if let frame = row[kind] as? [String: Any] {
                if index != damaged {
                    replay.agent.receive(try JSONSerialization.data(withJSONObject: frame))
                } else if let line = try ConformanceTests.damaged(frame, damage) {
                    let before = replay.agent.agent.error
                    outcome.known = replay.agent.driver.receive(line)
                    outcome.erred = replay.agent.agent.error != before
                    if damage == .truncated { #expect(!outcome.known, "\(at): a line cut in half was taken as known") }
                }
            }
            if let text = row["send"] as? String { _ = try? replay.agent.send(text, when: row["when"] as? String ?? "next") }
            if row["interrupted"] != nil { _ = try? replay.agent.interrupt() }
            if let request = row["answer"] as? String {
                let with: Answer = row["with"] as? String == "once" ? .once : row["with"] as? String == "deny" ? .deny : .choice(row["with"] as? [[String]] ?? [])
                _ = try? replay.agent.answer(request, with)
            }
            if let set = row["set"] as? [String: String] { _ = try? replay.agent.driver.set(model: set["model"], mode: set["mode"], effort: set["effort"]) }
            if row["timeout"] != nil {
                let due = replay.scheduled
                replay.scheduled = []
                due.forEach { $0() }
            }
            if let code = row["ended"] as? Int { replay.agent.ended(code: Int32(code), errors: "", asked: row["stop"] != nil) }
        }
        do {
            _ = try State(at: "2026-10-17T09:00:00Z", kinds: [:], agents: [replay.agent.agent], threads: replay.agent.thread.map { [$0] } ?? [],
                          requests: replay.fold.requests).json()
        } catch { Issue.record("\(at): the state does not encode: \(error)") }
        outcome.thread = replay.agent.thread
        return outcome
    }

    /// The bytes of `frame` after `damage`; nil when it drops the line.
    static func damaged(_ frame: [String: Any], _ damage: Damage) throws -> Data? {
        let whole = try JSONSerialization.data(withJSONObject: frame)
        switch damage {
        case .truncated: return whole.prefix(whole.count / 2)
        case .retyped: return try JSONSerialization.data(withJSONObject: frame.mapValues { $0 is String ? $0 : retyped($0, words: true) })
        case .retypedButWords: return try JSONSerialization.data(withJSONObject: retyped(frame, words: false))
        case .dropped: return nil
        }
    }

    /// `value` with every value under it of another type: a string becomes its length (when `words`), a number or a
    /// bool a string, null an array, an array an object by index; an object keeps its keys. The top-level words of a
    /// line (its type, its method) are kept by `.retyped`, so the driver goes past them into what it reads inside.
    static func retyped(_ value: Any, words: Bool) -> Any {
        switch value {
        case let object as [String: Any]: return object.mapValues { retyped($0, words: words) }
        case let array as [Any]:
            return Dictionary(uniqueKeysWithValues: array.enumerated().map { ("\($0.offset)", retyped($0.element, words: words)) })
        case let text as String: return words ? text.count : text
        case is NSNull: return [Any]()
        default: return "\(value)"
        }
    }

    /// The count of unknown lines from a launch's start: twenty with none known make the program a version its driver
    /// does not understand; one known line first, and it never is.
    @Test func aLaunchThatSpeaksOnlyUnknownLinesIsForeign() throws {
        let unknown = Data(#"{"type":"invented_frame_of_a_newer_claude"}"#.utf8)
        let foreign = Replay()
        for _ in 1..<Launched.foreignAfter { foreign.agent.receive(unknown) }
        #expect(!foreign.agent.foreign)
        foreign.agent.receive(Data("not even JSON".utf8))
        #expect(foreign.agent.foreign)
        let known = Replay()
        known.agent.receive(Data(#"{"type":"system","subtype":"invented"}"#.utf8))
        for _ in 0..<50 { known.agent.receive(unknown) }
        #expect(!known.agent.foreign)
    }

    // MARK: Readers

    /// One reader's invented home, as its own tests build it: its folder, a fresh reader of it, its processes, its now.
    struct Home {
        var root: URL, now: Date, snapshot: Snapshot
        var reader: () -> Reader
    }

    static func home(_ kind: String) throws -> Home? {
        switch kind {
        case "claude":
            let home = try ClaudeHome(prefix: "conformance-")
            return Home(root: home.root, now: home.now, snapshot: ClaudeHome.snapshot()) { ClaudeReader(environment: ["HOME": home.root.path]) }
        case "codex":
            let home = try CodexHome(prefix: "conformance-")
            return Home(root: home.root, now: home.now, snapshot: home.snapshot()) { CodexReader(environment: ["HOME": home.root.path]) }
        case "opencode":
            let home = try OpenCodeHome(prefix: "conformance-")
            return Home(root: home.root, now: home.now, snapshot: home.snapshot()) {
                let reader = OpenCodeReader(environment: ["HOME": home.root.path, "XDG_DATA_HOME": home.root.appendingPathComponent("data").path])
                reader.own = OpenCodeHome.own
                return reader
            }
        case "pi", "omp":
            let home = try PiHome(prefix: "conformance-")
            let snapshot = Snapshot([PiHome.pi(41500, in: "/Users/example/shop", started: home.now.addingTimeInterval(-3600))], files: { _ in [] })
            return Home(root: home.root, now: home.now, snapshot: snapshot) {
                kind == "pi" ? PiReader(environment: ["HOME": home.root.path]) as Reader : OMPReader(environment: ["HOME": home.root.path])
            }
        default: return nil
        }
    }

    @Test(arguments: read) func aReaderSurvivesDamagedFiles(kind: String) throws {
        guard let home = try ConformanceTests.home(kind) else {
            Issue.record("\(kind) has a reader but no invented home here: add it to ConformanceTests.home")
            return
        }
        defer { try? FileManager.default.removeItem(at: home.root) }
        // Each file as the home made it, with its date, which the readers read too: put back before each damage.
        let names = (FileManager.default.enumerator(atPath: home.root.path)?.allObjects as? [String] ?? []).sorted()
        let files = try names.compactMap { name -> (name: String, bytes: Data, date: Date)? in
            let url = home.root.appendingPathComponent(name)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular, let date = attributes[.modificationDate] as? Date else { return nil }
            return (name: name, bytes: try Data(contentsOf: url), date: date)
        }
        #expect(!files.isEmpty)
        func restore() throws {
            for file in files {
                let url = home.root.appendingPathComponent(file.name)
                if (try? Data(contentsOf: url)) != file.bytes { try file.bytes.write(to: url) }
                try FileManager.default.setAttributes([.modificationDate: file.date], ofItemAtPath: url.path)
            }
        }

        var damages: [(name: String, damage: () throws -> Void)] = []
        for (file, bytes, _) in files {
            let path = home.root.appendingPathComponent(file).path
            damages.append(("\(file) garbage", { try ConformanceTests.garbage(bytes.count).write(to: URL(fileURLWithPath: path)) }))
            if bytes.starts(with: Data("SQLite format 3".utf8)) {
                for (table, columns) in try SQLiteRO(path, whitelist: [:]).tables() {
                    for column in columns.sorted() {
                        damages.append(("\(file) \(table).\(column) removed", { ConformanceTests.execute(path, "ALTER TABLE \(table) DROP COLUMN \(column);") }))
                    }
                }
            } else {
                for key in ConformanceTests.keys(bytes) {
                    damages.append(("\(file) \(key) removed", { try ConformanceTests.removing(key, from: bytes).write(to: URL(fileURLWithPath: path)) }))
                }
            }
        }
        damages.append(("every file garbage", {
            for file in files { try ConformanceTests.garbage(file.bytes.count).write(to: home.root.appendingPathComponent(file.name)) }
        }))

        for (name, damage) in damages {
            try restore()
            // A reader that read the home whole before, with its cursors, and one that meets the damage first. Each is
            // given 5 s, so that a reader caught in a loop on garbage fails here instead of holding the whole run.
            let warm = home.reader()
            let watch = Watch(readers: [warm], snapshot: { home.snapshot }, name: Registry.described.name(of:))
            _ = watch.tick(now: home.now, within: ConformanceTests.within)
            try damage()
            let fresh = Watch(readers: [home.reader()], snapshot: { home.snapshot }).tick(now: home.now, within: ConformanceTests.within)
            for seen in [watch.tick(now: home.now, within: ConformanceTests.within), fresh] {
                let reading = seen.kinds[kind] ?? Reading()
                #expect(["ok", "changed", "unreadable", "none"].contains(reading.health), "\(kind), \(name): health \(reading.health)")
                #expect(!(reading.note ?? "").contains("reading them takes too long") && !(reading.note ?? "").contains("still reading"),
                        "\(kind), \(name): the reader did not return within \(ConformanceTests.within) s")
                let (agents, threads) = Watch.elsewhere(seen, registry: .described, groups: [], keys: [], now: home.now)
                do { _ = try State(at: "2026-10-17T09:00:00Z", kinds: [:], agents: agents, threads: threads).json() } catch {
                    Issue.record("\(kind), \(name): the state does not encode: \(error)")
                }
                // A reader that never read the files finds no conversation in noise. One that read them whole may
                // keep what it knew of a file rewritten in place under it (its cursor is past the new bytes): the
                // suite does not ask more of it, nor that a fresh one say "changed" (Claude's says "ok", with nothing).
                if name == "every file garbage", seen == fresh {
                    #expect(seen.sightings.allSatisfy { $0.processOnly }, "\(kind): a conversation was made of garbage: \(seen.sightings.map(\.key))")
                }
            }
        }
    }

    /// How long a damaged reader may take to read its home.
    static let within: TimeInterval = 5

    /// `count` bytes (at least one) of noise, the same at every run, cut into lines that open an object and a string.
    static func garbage(_ count: Int) -> Data {
        var state: UInt32 = 2_463_534_242
        return Data((0..<max(count, 1)).map { index in
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            return index % 64 == 0 ? UInt8(ascii: "\n") : index % 64 == 1 ? UInt8(ascii: "{") : index % 64 == 2 ? UInt8(ascii: "\"") : UInt8(truncatingIfNeeded: state)
        })
    }

    /// The keys of a JSON file or of the objects of a JSONL file, to depth two ("message.content"), each once.
    static func keys(_ bytes: Data) -> [String] {
        var keys = Set<String>()
        for object in objects(bytes).compactMap({ $0 }) {
            for (key, value) in object {
                keys.insert(key)
                if let inner = value as? [String: Any] { keys.formUnion(inner.keys.map { "\(key).\($0)" }) }
            }
        }
        return keys.sorted()
    }

    /// Each line of `bytes` as an object, nil for a line that is none; the whole file as one when it is one object.
    static func objects(_ bytes: Data) -> [[String: Any]?] {
        if let whole = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] { return [whole] }
        return bytes.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false).map { (try? JSONSerialization.jsonObject(with: Data($0))) as? [String: Any] }
    }

    /// The file `bytes` with `key` ("a" or "a.b") removed from its object, or from each object line; other lines kept.
    static func removing(_ key: String, from bytes: Data) throws -> Data {
        let path = key.split(separator: ".").map(String.init)
        func cut(_ object: [String: Any]) -> [String: Any] {
            var object = object
            if path.count == 1 { object[path[0]] = nil } else if var inner = object[path[0]] as? [String: Any] {
                inner[path[1]] = nil
                object[path[0]] = inner
            }
            return object
        }
        if let whole = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] { return try JSONSerialization.data(withJSONObject: cut(whole)) }
        let lines = bytes.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        return try Data(zip(lines, objects(bytes)).map { line, object in
            try object.map { try JSONSerialization.data(withJSONObject: cut($0)) } ?? Data(line)
        }.joined(separator: Data("\n".utf8)))
    }

    /// Runs `sql` on the database at `path`; a refusal (a column SQLite cannot drop) leaves the file as it was.
    static func execute(_ path: String, _ sql: String) {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(path, &db) == SQLITE_OK else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }
}
