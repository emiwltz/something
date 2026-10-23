// PiReader and OMPReader against an invented home (Tests/Fixtures/pi-home) of the exact shapes pi 1.0.0 and OMP 18.8.6
// write (texts invented): pi logs in two shop conversations, a blog one with a custom entry
// whose data comes before its id, and a flat one in a second agent folder; OMP logs with their 256-byte title slot, a
// branch left behind, a sub-agent's log, a session that exited and the leases left on disk. Fake snapshots give the
// processes; each case copies the home into a throwaway folder and dates its files.
import Foundation
import Testing
@testable import SomethingAgents
@testable import AgentPi
import SomethingCore

final class PiHome {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/pi-home")
    static let shopA = "01a14a3c-0000-7000-8000-00000000000a", shopB = "01a14a3c-0000-7000-8000-00000000000b"
    static let blog = "01a14a3c-0000-7000-8000-00000000000c", notes = "01a14a3c-0000-7000-8000-00000000000d"
    static let ompShop = "01a14bbb-0000-7000-8000-000000000001", ompBlog = "01a14bbb-0000-7000-8000-000000000002"

    let root: URL
    let now: Date
    let pi: PiReader, omp: OMPReader
    private(set) var opened: [String] = []

    /// `prefix` names the folder in $TMPDIR, as ClaudeHome's does.
    init(now: Date = Date(), prefix: String = "pi-home-") throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)\(UUID().uuidString)")
        self.now = now
        try FileManager.default.copyItem(at: PiHome.fixture, to: root)
        // The secrets pi and OMP keep beside their sessions, made here: the readers must never open them.
        try Data(#"{"example-provider":{"key":"invented"}}"#.utf8).write(to: root.appendingPathComponent(".pi/agent/auth.json"))
        try Data("invented".utf8).write(to: root.appendingPathComponent(".omp/agent/agent.db"))
        pi = PiReader(environment: ["HOME": root.path])
        omp = OMPReader(environment: ["HOME": root.path])
        pi.opened = { [unowned self] in opened.append($0) }
        omp.opened = { [unowned self] in opened.append($0) }
        // The shop's second log was written last; every log within the hour.
        for (log, age) in [(log(PiHome.shopA), 600.0), (log(PiHome.shopB), 30), (log(PiHome.blog), 1200), (log(PiHome.notes), 900),
                           (ompLog(PiHome.ompShop), 60), (ompLog(PiHome.ompBlog), 1800)] {
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: log)
        }
    }

    /// Called with defer where the home is made: a deinit does not always run before the test process ends.
    func remove() { try? FileManager.default.removeItem(at: root) }

    func find(_ folder: String, _ id: String) -> String {
        let paths = (FileManager.default.enumerator(atPath: root.appendingPathComponent(folder).path)?.allObjects as? [String]) ?? []
        return root.appendingPathComponent(folder).appendingPathComponent(paths.first { $0.hasSuffix("_\(id).jsonl") }!).path
    }

    func log(_ id: String) -> String { find(".pi", id) }
    func ompLog(_ id: String) -> String { find(".omp/agent/sessions", id) }

    /// A pi process as libproc gives it: named node, its first argument renamed pi, in `folder`.
    static func pi(_ pid: Int32, in folder: String, started: Date, parent: Int32 = 1) -> Running {
        Running(pid: pid, parent: parent, group: pid, started: started, name: "node", arguments: ["pi"], folder: folder)
    }

    func read(_ processes: [Running], discover: Bool = true) -> [String: Sighting] {
        Dictionary(uniqueKeysWithValues: pi.read(Snapshot(processes), discover: discover, now: now).sightings.map { ($0.key, $0) })
    }

    func readOMP(_ processes: [Running] = [], discover: Bool = true, files: @escaping (Int32) -> [String]? = { _ in [] }) -> [String: Sighting] {
        Dictionary(uniqueKeysWithValues: omp.read(Snapshot(processes, files: files), discover: discover, now: now).sightings.map { ($0.key, $0) })
    }

    /// Replaces `path` by a new file with `text`, through a rename, as OMP and a rewrite of pi do: a new inode.
    static func replace(_ path: String, with text: String) throws {
        let next = path + ".tmp"
        try Data(text.utf8).write(to: URL(fileURLWithPath: next))
        #expect(rename(next, path) == 0)
    }

    /// The state, waiting and evidence words of `facts`, in one string.
    static func words(_ facts: StateMap.Facts, _ now: Date) -> String {
        let result = StateMap.map(facts, now: now)
        return "\(result.state) \(result.waiting ?? "nil") \(result.evidence ?? "nil")"
    }

    /// Rewrites the first 256 bytes of `path` in place with a title slot naming `title`, as OMP does.
    static func retitle(_ path: String, _ title: String) throws {
        var line = #"{"type":"title","v":1,"title":"\#(title)","source":"user","updatedAt":"2026-10-17T09:05:00.000Z","pad":""#
        line += String(repeating: " ", count: 255 - line.utf8.count - 2) + "\"}\n"
        let handle = try #require(FileHandle(forUpdatingAtPath: path))
        try handle.write(contentsOf: Data(line.utf8))
        try handle.close()
    }
}

@Suite(.leavesNothing("pi-home-")) struct PiReaderTests {
    @Test func threeDaysLaterTheSameIsRead() throws {
        try sameThreeDaysLater { now in
            let home = try PiHome(now: now)
            defer { home.remove() }
            let pi = home.read([PiHome.pi(52001, in: "/Users/example/shop", started: now.addingTimeInterval(-3600))])
            return stateWords(Array(pi.values) + Array(home.readOMP().values), at: now)
        }
    }

    @Test func twoPiInOneFolderAreNotToldApart() throws {
        let home = try PiHome()
        defer { home.remove() }
        let started = home.now.addingTimeInterval(-3600)
        let seen = home.read([PiHome.pi(52001, in: "/Users/example/shop", started: started), PiHome.pi(52002, in: "/Users/example/shop", started: started)])
        #expect(Set(seen.keys) == Set([PiHome.shopA, PiHome.shopB, PiHome.blog, PiHome.notes].map(home.log)), "no process is shown without its log")
        let a = try #require(seen[home.log(PiHome.shopA)]), b = try #require(seen[home.log(PiHome.shopB)])
        #expect(a.facts.alive == nil && b.facts.alive == nil && a.pid == nil && b.pid == nil && a.facts.evidence == nil)
        #expect(StateMap.map(a.facts, now: home.now).state == "unknown", "a closed turn without a holder is never idle")
        #expect(PiHome.words(b.facts, home.now) == "working none recent-write")
        #expect(a.folder == "/Users/example/shop" && a.model == "example-model" && a.effort == "high" && a.complete)
        #expect(a.started == PiReader.date("2026-10-17T08:00:00.000Z"))
        let turn = try #require(a.turns.last)
        #expect(a.turns.count == 1 && turn.state == "done" && turn.ended == "2026-10-17T08:00:40.000Z")
        #expect(turn.items.map(\.kind) == ["message", "thought", "message", "tool", "message"])
        #expect(turn.items[0].text == "Add a dark mode to the cart page." && turn.items[0].author == "person")
        #expect(turn.items[3].text == "npm test" && turn.items[3].tool == Tool(name: "bash", status: "done"))
        #expect(b.turns.last?.items.last?.text == "/Users/example/shop/checkout.css" && b.turns.last?.items.last?.tool?.status == "running")
        // Its log says it ended, as no pi runs in its folder.
        let blog = try #require(seen[home.log(PiHome.blog)])
        #expect(blog.facts.alive == false && blog.facts.evidence == "process" && blog.title == "Blog typo" && blog.complete,
                "the branch runs through a custom entry whose id comes after its data")
        #expect(StateMap.map(blog.facts, now: home.now).state == "done" && blog.turns.first?.items.map(\.author) == ["person", "agent"])
        // The flat sessions folder of a second agent folder is read too.
        let notes = try #require(seen[home.log(PiHome.notes)])
        #expect(notes.folder == "/Users/example/notes" && StateMap.map(notes.facts, now: home.now).state == "error")
        #expect(notes.error?.message == "The example provider is overloaded.")
        #expect(!home.opened.contains { $0.hasSuffix("auth.json") || $0.hasSuffix("agent.db") })
    }

    @Test func onePiHoldsTheNewestLogOfItsFolderWrittenSinceItStarted() throws {
        let home = try PiHome()
        defer { home.remove() }
        var seen = home.read([PiHome.pi(52001, in: "/Users/example/shop", started: home.now.addingTimeInterval(-3600))])
        let b = try #require(seen[home.log(PiHome.shopB)])
        #expect(b.facts.alive == true && b.facts.evidence == "cwd" && b.pid == 52001)
        #expect(PiHome.words(b.facts, home.now) == "working none cwd")
        #expect(seen[home.log(PiHome.shopA)]?.facts.alive == false)
        // A pi started after the last write has not written its log yet: it is seen from its process.
        seen = home.read([PiHome.pi(52004, in: "/Users/example/shop", started: home.now.addingTimeInterval(-10))])
        #expect(seen[home.log(PiHome.shopB)]?.facts.alive == false)
        let fresh = try #require(seen["pid-52004"])
        #expect(fresh.processOnly && fresh.facts.alive == true && fresh.folder == "/Users/example/shop")
        let agent = try #require(Watch.elsewhere(Seen(sightings: [fresh]), registry: .described, groups: [], keys: [], now: home.now).agents.first)
        #expect(agent.kind == "pi" && agent.state == "unknown" && agent.evidence == "process" && agent.thread == nil && !agent.can.resume)
    }

    /// A log too old to list is looked at again at the next walk (every 15th tick), not at each tick: written again
    /// where no process holds it, it is listed then. In a folder where a pi runs, every log is looked at each tick.
    @Test func anOldLogIsLookedAtAgainAtTheWalk() throws {
        let home = try PiHome()
        defer { home.remove() }
        let blog = home.log(PiHome.blog), ompBlog = home.ompLog(PiHome.ompBlog)
        func date(_ seconds: TimeInterval, _ paths: [String]) throws {
            for path in paths { try FileManager.default.setAttributes([.modificationDate: home.now.addingTimeInterval(seconds)], ofItemAtPath: path) }
        }
        try date(-3 * 86_400, [blog, ompBlog])
        #expect(home.read([])[blog] == nil && home.readOMP()[PiHome.ompBlog] == nil)
        try date(0, [blog, ompBlog])
        #expect(home.read([], discover: false)[blog] == nil && home.readOMP(discover: false)[PiHome.ompBlog] == nil)
        #expect(home.read([])[blog] != nil && home.readOMP()[PiHome.ompBlog] != nil, "seen at the walk")

        let pi = PiHome.pi(52005, in: "/Users/example/blog", started: home.now.addingTimeInterval(-60))
        try date(-3 * 86_400, [blog])
        #expect(home.read([pi])[blog] == nil)
        try date(0, [blog])
        #expect(home.read([pi], discover: false)[blog]?.facts.alive == true, "the pi in its folder writes it again")
    }

    @Test func aPiSomethingLaunchedStillCountsInItsFolder() throws {
        let home = try PiHome()
        defer { home.remove() }
        // something's own pi (pid 52003, under something's pid 999999) and the person's, in one folder: the newest
        // log may be either one's, so neither log is claimed, and the own pi is not shown.
        let watch = Watch(readers: [home.pi], snapshot: {
            Snapshot([Running(pid: 999_999, parent: 1, group: 999_999, started: home.now.addingTimeInterval(-7200), name: "something"),
                      PiHome.pi(52001, in: "/Users/example/shop", started: home.now.addingTimeInterval(-3600)),
                      PiHome.pi(52003, in: "/Users/example/shop", started: home.now.addingTimeInterval(-900), parent: 999_999)])
        })
        watch.own = 999_999
        let seen = Dictionary(uniqueKeysWithValues: watch.tick(now: home.now).sightings.map { ($0.key, $0) })
        #expect(seen[home.log(PiHome.shopB)]?.facts.alive == nil && seen[home.log(PiHome.shopB)]?.pid == nil)
        #expect(seen[home.log(PiHome.shopA)]?.facts.alive == nil && !seen.keys.contains { $0.hasPrefix("pid-") })
    }

    @Test func piThatRunForDaysAreSeenFromTheirProcess() throws {
        let home = try PiHome()
        defer { home.remove() }
        for (id, days) in [(PiHome.shopA, 2.5), (PiHome.shopB, 2)] {
            try FileManager.default.setAttributes([.modificationDate: home.now.addingTimeInterval(-days * 86_400)], ofItemAtPath: home.log(id))
        }
        let started = home.now.addingTimeInterval(-3 * 86_400)
        // Two pi in the shop since three days, their logs written two days ago and more: neither log is listed, both pi are.
        var seen = home.read([PiHome.pi(52001, in: "/Users/example/shop", started: started), PiHome.pi(52002, in: "/Users/example/shop", started: started)])
        #expect(seen[home.log(PiHome.shopA)] == nil && seen[home.log(PiHome.shopB)] == nil)
        #expect(seen["pid-52001"]?.processOnly == true && seen["pid-52002"]?.processOnly == true)
        // One of them alone holds its log, however old.
        seen = home.read([PiHome.pi(52001, in: "/Users/example/shop", started: started)])
        #expect(seen[home.log(PiHome.shopB)]?.facts.alive == true && seen["pid-52001"] == nil)
    }

    @Test func aPiIsKnownBeforeItRenamesItself() throws {
        let home = try PiHome()
        defer { home.remove() }
        // Its first milliseconds: node runs pi's script, and the snapshot keeps those arguments for the process's life.
        let early = Running(pid: 52005, parent: 1, group: 52005, started: home.now.addingTimeInterval(-3600), name: "node",
                            arguments: ["node", "/opt/example/lib/node_modules/.bin/pi"], folder: "/Users/example/shop")
        #expect(home.pi.owns(early) && !home.pi.owns(Running(pid: 1, parent: 0, group: 1, started: home.now, name: "node", arguments: ["node", "server.js"])))
        #expect(home.read([early])[home.log(PiHome.shopB)]?.pid == 52005)
    }

    @Test func logsReplacedBetweenWalksAreReadAgain() throws {
        let home = try PiHome()
        defer { home.remove() }
        let pi = PiHome.pi(52001, in: "/Users/example/shop", started: home.now.addingTimeInterval(-3600))
        let omp = Running(pid: 53000, parent: 1, group: 53000, started: home.now.addingTimeInterval(-7200), name: "omp")
        _ = home.read([pi])
        _ = home.readOMP([omp])
        // The same processes, no walk: each reader keeps the files it listed and finds the new inode by its stat.
        try PiHome.replace(home.log(PiHome.shopB), with: """
            {"type":"session","version":3,"id":"\(PiHome.shopB)","timestamp":"2026-10-17T08:30:00.000Z","cwd":"/Users/example/shop","parentSession":null}
            {"type":"message","id":"b2000001","parentId":null,"timestamp":"2026-10-17T08:30:05.000Z","message":{"role":"user","content":"Make the checkout blue.","timestamp":1792225800000}}

            """)
        let ompPath = home.ompLog(PiHome.ompShop)
        let slot = try String(contentsOfFile: ompPath, encoding: .utf8).prefix(OMPReader.titleSlot)
        try PiHome.replace(ompPath, with: slot + """
            {"type":"session","version":3,"id":"\(PiHome.ompShop)","timestamp":"2026-10-17T09:00:00.000Z","cwd":"/Users/example/shop"}
            {"type":"message","id":"f0000001","parentId":null,"timestamp":"2026-10-17T09:10:00.000Z","message":{"role":"user","content":[{"type":"text","text":"Start over with a red total."}],"attribution":"user","timestamp":1792226400000}}

            """)
        let b = try #require(home.read([pi], discover: false)[home.log(PiHome.shopB)])
        #expect(b.facts.alive == true && b.turns.map { $0.items.map(\.text) } == [["Make the checkout blue."]])
        let shop = try #require(home.readOMP([omp], discover: false)[PiHome.ompShop])
        #expect(shop.turns.map { $0.items.map(\.text) } == [["Start over with a red total."]] && shop.title == "Fix the cart total")
    }

    @Test func aRewrittenPiLogIsReadAgain() throws {
        let home = try PiHome()
        defer { home.remove() }
        let path = home.log(PiHome.shopA)
        _ = home.read([])
        let inode = Stamp(path)?.inode
        // pi rewrites an older version's file in place, on the same inode, shorter or longer.
        let handle = try #require(FileHandle(forUpdatingAtPath: path))
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("""
            {"type":"session","version":3,"id":"\(PiHome.shopA)","timestamp":"2026-10-17T08:00:00.000Z","cwd":"/Users/example/shop","parentSession":null}
            {"type":"message","id":"a1000001","parentId":null,"timestamp":"2026-10-17T08:00:05.000Z","message":{"role":"user","content":"Rename the shop.","timestamp":1792224000000}}

            """.utf8))
        try handle.close()
        #expect(Stamp(path)?.inode == inode)
        let a = try #require(home.read([])[path])
        #expect(a.turns.count == 1 && a.turns[0].items.map(\.text) == ["Rename the shop."] && a.turns[0].state == "working")
    }

    @Test func anOMPLogShowsItsCurrentBranch() throws {
        let home = try PiHome()
        defer { home.remove() }
        let seen = home.readOMP()
        #expect(Set(seen.keys) == [PiHome.ompShop, PiHome.ompBlog], "a sub-agent's log, the lock leftovers and the leases are no conversations")
        let shop = try #require(seen[PiHome.ompShop])
        #expect(shop.title == "Fix the cart total" && shop.folder == "/Users/example/shop" && shop.model == "example-model" && shop.effort == "medium")
        #expect(shop.facts.alive == false && shop.facts.evidence == "process" && shop.facts.waiting == .unknown, "no omp runs: the leases left on disk hold nothing")
        let turn = try #require(shop.turns.last)
        #expect(shop.turns.count == 1 && shop.complete && turn.state == "done", "the first message, edited, is a branch left behind")
        #expect(turn.items.map(\.text) == ["Make the cart total green instead.", "npm test", "The cart total is green."], "the program's own message is left out")
        #expect(turn.items[1].tool == Tool(name: "bash", status: "done"))
        let blog = try #require(seen[PiHome.ompBlog])
        #expect(blog.title == nil && blog.facts.ended && StateMap.map(blog.facts, now: home.now).state == "done")
        #expect(!home.opened.contains { $0.contains("Scout") || $0.hasSuffix("agent.db") })
    }

    @Test func anOMPHolderMakesItAlive() throws {
        let home = try PiHome()
        defer { home.remove() }
        let omp = Running(pid: 53000, parent: 1, group: 53000, started: home.now.addingTimeInterval(-7200), name: "omp")
        let leases = home.root.appendingPathComponent(".omp/run/session-owners").path
        // The shop's log held open, the blog's lease held: both say a living holder.
        var seen = home.readOMP([omp]) { _ in [HeldFiles.real(home.ompLog(PiHome.ompShop)), HeldFiles.real(leases) + "/\(PiHome.ompBlog).lock"] }
        #expect(seen[PiHome.ompShop]?.facts.alive == true && seen[PiHome.ompShop]?.facts.evidence == "open-file" && seen[PiHome.ompShop]?.pid == 53000)
        #expect(seen[PiHome.ompBlog]?.facts.alive == true)
        #expect(PiHome.words(seen[PiHome.ompShop]!.facts, home.now) == "idle nil open-file")
        // An omp that holds neither, its files read in full: both closed. One whose files are not given: unknown.
        seen = OMPReaderAgain(home).read([omp]) { _ in ["/dev/null"] }
        #expect(seen[PiHome.ompShop]?.facts.alive == false && seen[PiHome.ompShop]?.facts.evidence == "open-file")
        seen = OMPReaderAgain(home).read([omp]) { _ in nil }
        #expect(seen[PiHome.ompShop]?.facts.alive == nil && seen[PiHome.ompShop]?.facts.evidence == nil)
        // A held log is listed however long it has been idle.
        try FileManager.default.setAttributes([.modificationDate: home.now.addingTimeInterval(-3 * 86_400)], ofItemAtPath: home.ompLog(PiHome.ompShop))
        #expect(OMPReaderAgain(home).read([omp]) { _ in [] }[PiHome.ompShop] == nil)
        #expect(OMPReaderAgain(home).read([omp]) { _ in [home.ompLog(PiHome.ompShop)] }[PiHome.ompShop]?.facts.alive == true)
    }

    @Test func anOMPTitleRewriteKeepsTheCursor() throws {
        let home = try PiHome()
        defer { home.remove() }
        let path = home.ompLog(PiHome.ompShop)
        let first = try #require(Tail.read(path, after: nil, containing: [PiLog.typed], skippingHead: OMPReader.titleSlot))
        let plain = try #require(Tail.read(path, after: nil, containing: [PiLog.typed]))
        _ = home.readOMP()
        try PiHome.retitle(path, "Green cart total")
        let handle = try #require(FileHandle(forWritingAtPath: path))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"type":"message","id":"e0000011","parentId":"e0000010","timestamp":"2026-10-17T09:06:00.000Z","message":{"role":"user","content":[{"type":"text","text":"Now make it bold."}],"attribution":"user","timestamp":1792224000000}}"#.utf8 + [10]))
        try handle.close()
        // The slot is no rewrite of the file: only the new line is read.
        let next = try #require(Tail.read(path, after: first.cursor, containing: [PiLog.typed], skippingHead: OMPReader.titleSlot))
        #expect(!next.fresh && next.lines.count == 1)
        #expect(Tail.read(path, after: plain.cursor, containing: [PiLog.typed])?.fresh == true, "without the skip, the slot's change reads as a rewrite")
        let shop = try #require(home.readOMP()[PiHome.ompShop])
        #expect(shop.title == "Green cart total" && shop.turns.map(\.state) == ["done", "working"])
    }

    @Test func otherAgentsAreSeenFromTheirProcess() throws {
        let started = Date(timeIntervalSince1970: 1_792_224_000)
        let snapshot = Snapshot([
            Running(pid: 54000, parent: 1, group: 54000, started: started, name: "node", arguments: ["node", "/opt/example/bin/gemini"], folder: "/Users/example/notes"),
            // Gemini CLI starts itself again with more memory: the same agent.
            Running(pid: 54001, parent: 54000, group: 54000, started: started, name: "node", arguments: ["node", "--max-old-space-size=8192", "/opt/example/bin/gemini"]),
            Running(pid: 54100, parent: 1, group: 54100, started: started, name: "goose", arguments: ["goose"], folder: "/Users/example/blog"),
            Running(pid: 54200, parent: 1, group: 54200, started: started, name: "node", arguments: ["node", "server.js"], folder: "/Users/example/shop"),
            Running(pid: 54300, parent: 1, group: 54300, started: started, name: "qwen", arguments: ["qwen"]),
        ])
        let watch = Watch(readers: [OtherReader(names: Registry.described.others)], snapshot: { snapshot })
        let (agents, threads) = Watch.elsewhere(watch.tick(now: started), registry: .described, groups: [], keys: [], now: started)
        // Named by their folder, else by their program.
        #expect(agents.map(\.name) == ["notes", "blog", "qwen"] && threads.isEmpty, "oldest first, then by key")
        let gemini = try #require(agents.first { $0.id == "other-gemini-54000" })
        #expect(gemini.kind == "other" && gemini.alive == true && gemini.evidence == "process" && gemini.state == "unknown" && gemini.waiting == nil)
        #expect(gemini.folder == "/Users/example/notes" && gemini.pid == 54000 && gemini.thread == nil && gemini.can == Can())
        #expect(gemini.because == ["send": "something has no reader for this agent; it only sees its process."])
    }

    @Test func ompIsSeen() throws {
        let place = try EngineTests.Place(prefix: "pi-home-engine-")
        defer { place.remove() }
        let home = try PiHome()
        defer { home.remove() }
        let engine = Engine.throwaway(place.environment)
        engine.watch = Watch(readers: [home.pi, home.omp], snapshot: { Snapshot([]) })
        engine.saw(engine.watch.tick(now: home.now))
        let state = engine.state
        #expect(state.kinds["omp"]?.launch == true && state.kinds["omp"]?.reader == "ok" && state.kinds["pi"]?.reader == "ok")
        #expect(state.agents.filter { $0.kind == "omp" }.count == 2 && state.agents.filter { $0.kind == "pi" }.count == 4)
        let omp = try #require(state.agents.first { $0.kind == "omp" })
        #expect(!omp.can.resume && omp.because["resume"] == "something cannot continue OMP conversations started elsewhere yet.")
    }
}

/// A fresh OMPReader over the same home, so that no files read earlier are reused.
struct OMPReaderAgain {
    let home: PiHome
    init(_ home: PiHome) { self.home = home }
    func read(_ processes: [Running], files: @escaping (Int32) -> [String]?) -> [String: Sighting] {
        let reader = OMPReader(environment: ["HOME": home.root.path])
        return Dictionary(uniqueKeysWithValues: reader.read(Snapshot(processes, files: files), discover: true, now: home.now).sightings.map { ($0.key, $0) })
    }
}
