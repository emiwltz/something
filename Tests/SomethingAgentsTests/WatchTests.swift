// The watch loop, the dedupe and the kinds, over the invented ~/.claude of ClaudeReaderTests and fake snapshots, then
// through the Engine, with a fake `claude` it launched (EngineTests' script) beside the sessions seen elsewhere.
import Foundation
import Testing
@testable import SomethingAgents
import SomethingCore

@MainActor @Suite(.leavesNothing("watch-")) struct WatchTests {
    @Test func aTickGivesRecentSightingsWithTheirGroups() throws {
        let home = try ClaudeHome(prefix: "watch-claude-")
        defer { home.remove() }
        let watch = Watch(readers: [home.reader], snapshot: { ClaudeHome.snapshot() })
        let seen = watch.tick(now: Date())
        #expect(Set(seen.sightings.map(\.key)) == [ClaudeHome.shop, ClaudeHome.blog])
        #expect(seen.sightings.first { $0.key == ClaudeHome.blog }?.group == 41290)
        #expect(seen.kinds["claude"] == Reading(version: "2.1.299", health: "ok"), "the sightings are moved out of the kinds")
    }

    @Test func elsewhereAgentsAreShapedAsTheContractSays() throws {
        let home = try ClaudeHome(prefix: "watch-claude-")
        defer { home.remove() }
        let seen = Watch(readers: [home.reader], snapshot: { ClaudeHome.snapshot() }).tick(now: Date())
        let (agents, threads) = Watch.elsewhere(seen, registry: .described, groups: [], keys: [], now: Date())
        let shop = try #require(agents.first { $0.thread == ClaudeHome.shop })
        #expect(shop.id == "claude-\(ClaudeHome.shop)" && shop.kind == "claude" && shop.origin == "elsewhere")
        #expect(shop.name == "Dark mode for the cart" && shop.folder == "/Users/example/shop" && shop.pid == 41234)
        #expect(shop.alive == true && shop.evidence == "registry" && shop.state == "waiting" && shop.waiting == "permission")
        #expect(shop.can == Can() && shop.because["send"] == "This agent was started outside something; something only reads it.")
        #expect(shop.because["resume"] == "Claude Code still runs this conversation (pid 41234). Quit it there first.")
        #expect(shop.queue.isEmpty && shop.options == Options() && shop.model == "claude-example-model")
        #expect(shop.started == "2026-10-17T08:55:00Z")
        let blog = try #require(agents.first { $0.thread == ClaudeHome.blog })
        #expect(blog.state == "working" && blog.waiting == "none" && blog.name == "Blog typo")
        let thread = try #require(threads.first { $0.id == ClaudeHome.shop })
        #expect(thread.agent == shop.id && thread.title == shop.name && thread.complete && thread.turns.count == 1)
        #expect(try State(at: "2026-10-17T09:00:04Z", kinds: [:], agents: agents, threads: threads).json().count > 0)
    }

    @Test func whatSomethingLaunchedIsDropped() throws {
        let home = try ClaudeHome(prefix: "watch-claude-")
        defer { home.remove() }
        let seen = Watch(readers: [home.reader], snapshot: { ClaudeHome.snapshot() }).tick(now: Date())
        // The blog's Claude runs in the group of one of something's children; the shop's conversation is one a driver reported.
        #expect(Watch.elsewhere(seen, registry: .described, groups: [41290], keys: [], now: Date()).agents.map(\.thread) == [ClaudeHome.shop])
        #expect(Watch.elsewhere(seen, registry: .described, groups: [], keys: [ClaudeHome.shop], now: Date()).agents.map(\.thread) == [ClaudeHome.blog])
        #expect(Watch.elsewhere(seen, registry: .described, groups: [41290], keys: [ClaudeHome.shop], now: Date()).threads.isEmpty)
    }

    @Test func aChangedShapeShowsTheProcessesOnly() throws {
        let home = try ClaudeHome(prefix: "watch-claude-")
        defer { home.remove() }
        try Data(#"{"pid":41500,"session":"renamed","kind":"interactive"}"#.utf8).write(to: home.sessions.appendingPathComponent("41500.json"))
        let seen = Watch(readers: [home.reader], snapshot: { ClaudeHome.snapshot() }).tick(now: Date())
        #expect(seen.kinds["claude"]?.health == "changed")
        let (agents, threads) = Watch.elsewhere(seen, registry: .described, groups: [], keys: [], now: Date())
        #expect(Set(agents.compactMap(\.pid)) == [41234, 41300], "every claude process, and no other")
        #expect(agents.allSatisfy { $0.alive == true && $0.evidence == "process" && $0.state == "unknown" && $0.waiting == nil && $0.thread == nil })
        #expect(threads.isEmpty)
    }

    /// A snapshot the system did not give in full proves nobody gone: the last tick stands.
    @Test func aSnapshotNotWholeEndsNothing() throws {
        let home = try ClaudeHome(prefix: "watch-claude-")
        defer { home.remove() }
        var snapshot = ClaudeHome.snapshot()
        let watch = Watch(readers: [home.reader], snapshot: { snapshot })
        let good = watch.tick(now: Date())
        snapshot = Snapshot([], whole: false)
        #expect(watch.tick(now: Date()) == good)
        #expect(Watch.elsewhere(watch.tick(now: Date()), registry: .described, groups: [], keys: [], now: Date()).agents.allSatisfy { $0.alive == true })
        // This Mac's own snapshot holds this process, and is whole.
        let own = Processes(known: []).snapshot()
        #expect(own.whole && own[getpid()] != nil)
    }

    /// An agent seen elsewhere that ended has no pid: the number may already be another program's.
    @Test func anEndedAgentHasNoPid() throws {
        let home = try ClaudeHome(prefix: "watch-claude-")
        defer { home.remove() }
        var snapshot = ClaudeHome.snapshot()
        let watch = Watch(readers: [home.reader], snapshot: { snapshot })
        _ = watch.tick(now: home.now)
        try FileManager.default.removeItem(at: home.sessions.appendingPathComponent("41234.json"))
        snapshot = ClaudeHome.snapshot(shop: false)
        let seen = watch.tick(now: home.now)
        let shop = try #require(Watch.elsewhere(seen, registry: .described, groups: [], keys: [], now: home.now).agents.first { $0.thread == ClaudeHome.shop })
        #expect(shop.alive == false && shop.pid == nil)
        #expect(shop.can.resume && shop.because["send"] == "This agent was started outside something; something only reads it. Continue it here to write to it.")
    }

    @Test func theTimerTicksAndChangesItsCadence() async throws {
        let home = try ClaudeHome(prefix: "watch-claude-")
        defer { home.remove() }
        let watch = Watch(readers: [home.reader], snapshot: { ClaudeHome.snapshot() })
        var ticks = 0
        watch.start(every: 0.05) { _ in ticks += 1 }
        watch.start(every: 0.05) { _ in Issue.record("the same cadence keeps the first timer") }
        let end = Date().addingTimeInterval(30)
        while ticks < 3, Date() < end { try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(ticks >= 3)
        watch.start(every: 3600) { _ in }
    }

    /// Decision 3 of 0.3: while no window shows, the watch does not tick at all; the moment one shows, it ticks and
    /// walks, then keeps the cadence of the moment. On a fake clock, which moves only when the test says.
    @Test func theWatchSleepsWhileNoWindowShows() async throws {
        let place = try EngineTests.Place(prefix: "watch-engine-")
        defer { place.remove() }
        let engine = Engine.throwaway(place.environment), clock = FakeClock(), reader = Walks()
        var ticks = 0
        engine.watch = Watch(readers: [reader], snapshot: {
            ticks += 1
            return ClaudeHome.snapshot()
        })
        engine.watch.repeating = clock.repeating
        engine.start(often: true)
        #expect(ticks == 1, "the first tick is at once")
        clock.advance(4)
        #expect(ticks == 3, "then every 2 s while a space is open")
        engine.start(often: true, visible: false)
        clock.advance(600)
        engine.start(often: false, visible: false)
        clock.advance(600)
        #expect(ticks == 3, "no tick while no window shows, whatever the cadence")
        engine.start(often: false, visible: true)
        #expect(ticks == 4, "a tick the moment the window shows")
        #expect(reader.walks == [true, false, false, true], "and that tick walks, whatever changed while hidden")
        clock.advance(9)
        #expect(ticks == 4)
        clock.advance(1)
        #expect(ticks == 5, "then every 10 s with no space open")
    }

    /// A reader that throws is said "unreadable", in a sentence with its name; the conversations it read last stay one
    /// tick, then its program's processes stand in for them, and the next good read is shown again. Its neighbour, read
    /// in the same ticks, is not touched.
    @Test func aReaderThatThrowsIsUnreadable() throws {
        let home = try ClaudeHome(prefix: "watch-claude-")
        defer { home.remove() }
        let flaky = Scripted(), process = Running(pid: 52000, parent: 1, group: 52000, started: home.now, name: "scripted")
        let watch = Watch(readers: [flaky, home.reader], snapshot: { Snapshot(Array(ClaudeHome.snapshot().processes.values) + [process]) },
                          name: { $0 == "scripted" ? "Scripted Agent" : Registry.described.name(of: $0) })
        let good = Reading(sightings: [Sighting(kind: "scripted", key: "invented-conversation", facts: StateMap.Facts(alive: true, evidence: "registry"))],
                           version: "1.0.0", health: "ok")
        flaky.script = [.success(good), .failure(Unreadable("its invented folder is gone.")), .failure(CocoaError(.fileReadNoPermission)), .success(good)]
        #expect(watch.tick(now: home.now).sightings.filter { $0.kind == "scripted" }.map(\.key) == ["invented-conversation"])

        let first = watch.tick(now: home.now)
        #expect(first.kinds["scripted"] == Reading(version: "1.0.0", health: "unreadable",
                                                   note: "something could not read Scripted Agent's files: its invented folder is gone."))
        #expect(first.sightings.filter { $0.kind == "scripted" }.map(\.key) == ["invented-conversation"], "the last good sightings stay one tick")
        #expect(first.kinds["claude"]?.health == "ok" && first.sightings.filter { $0.kind == "claude" }.count == 2, "its neighbour is read")

        let second = watch.tick(now: home.now)
        #expect(second.kinds["scripted"]?.health == "unreadable" && second.kinds["scripted"]?.version == nil)
        #expect(second.kinds["scripted"]?.note?.hasPrefix("something could not read Scripted Agent's files: ") == true, "any error is said")
        #expect(second.sightings.filter { $0.kind == "scripted" }.map { "\($0.key) \($0.processOnly)" } == ["pid-52000 true"], "then its processes")

        let again = watch.tick(now: home.now)
        #expect(again.kinds["scripted"] == Reading(version: "1.0.0", health: "ok"))
        #expect(again.sightings.filter { $0.kind == "scripted" }.map(\.key) == ["invented-conversation"])
    }

    /// A reader slower than its tick's deadline is not waited for: its last reading stands, said late, and it is not
    /// asked again before it returns; a walk asked meanwhile comes with its next read. The others are read on time.
    @Test func aLateReaderKeepsItsLastReading() throws {
        let home = try ClaudeHome(prefix: "watch-claude-")
        defer { home.remove() }
        let slow = Scripted()
        let watch = Watch(readers: [slow, home.reader], snapshot: { ClaudeHome.snapshot() }, name: { $0 == "scripted" ? "Scripted Agent" : $0 })
        slow.script = [.success(Reading(version: "1.0.0", health: "ok"))]
        // Ticks 1 to 14, the first of which walks; tick 15 is held, and tick 16, a walk, comes while it is.
        for _ in 1...14 { _ = watch.tick(now: home.now) }
        #expect(slow.walks.first == true && slow.walks.dropFirst().allSatisfy { !$0 } && slow.walks.count == 14)
        slow.holding = true
        let late = watch.tick(now: home.now, within: 0.05)
        #expect(slow.started.wait(timeout: .now() + 30) == .success)
        #expect(late.kinds["scripted"] == Reading(version: "1.0.0", health: "ok",
                                                  note: "something is still reading Scripted Agent's files; what they say may be late."))
        #expect(late.kinds["claude"]?.health == "ok" && late.sightings.count == 2, "the others are read on time")
        _ = watch.tick(now: home.now, within: 0.05)
        #expect(slow.walks.count == 15, "not asked again while it reads")
        let next = slow.release(watch, now: home.now)
        #expect(next.kinds["scripted"] == Reading(version: "1.0.0", health: "ok"), "on time again, no note")
        #expect(slow.walks.count == 16 && slow.walks.last == true, "the walk of tick 16 is owed to the next read")
    }

    /// A late reading stands only so long: past `Lane.patience` ticks, or when the reader never returned, what it said
    /// may no longer be true (an agent ended meanwhile), so its files are said unreadable and its program's processes
    /// stand in; never "none", which would say there is nothing of its kind here. A late reader whose last health was
    /// not "ok" keeps its own sentence.
    @Test func aReaderLatePastItsPatienceIsUnreadable() throws {
        let now = Date(timeIntervalSince1970: 1_792_227_600)
        let slow = Scripted(), process = Running(pid: 52000, parent: 1, group: 52000, started: now, name: "scripted")
        let watch = Watch(readers: [slow], snapshot: { Snapshot([process]) }, name: { _ in "Scripted Agent" })
        let tooLong = Reading(health: "unreadable", note: "something could not read Scripted Agent's files: reading them takes too long.")
        let good = Reading(sightings: [Sighting(kind: "scripted", key: "invented-conversation", facts: StateMap.Facts(alive: true, evidence: "registry"))],
                           version: "1.0.0", health: "ok")
        slow.script = [.success(good)]
        slow.holding = true
        let cold = watch.tick(now: now, within: 0.01)
        #expect(cold.kinds["scripted"] == tooLong, "a first read that never returned")
        #expect(cold.sightings.map { "\($0.key) \($0.processOnly)" } == ["pid-52000 true"])
        #expect(slow.release(watch, now: now).sightings.map(\.key) == ["invented-conversation"])

        slow.holding = true
        for tick in 1...Lane.patience {
            let late = watch.tick(now: now, within: 0.01)
            #expect(late.kinds["scripted"]?.note == "something is still reading Scripted Agent's files; what they say may be late.", "late tick \(tick)")
            #expect(late.sightings.map(\.key) == ["invented-conversation"], "late tick \(tick)")
        }
        let past = watch.tick(now: now, within: 0.01)
        #expect(past.kinds["scripted"] == tooLong)
        #expect(past.sightings.map(\.key) == ["pid-52000"], "its processes, not what it said last")

        slow.script = [.failure(Unreadable("its invented folder is gone.")), .success(good)]
        _ = slow.release(watch, now: now)
        slow.holding = true
        let unread = watch.tick(now: now, within: 0.01)
        #expect(unread.kinds["scripted"]?.note == "something could not read Scripted Agent's files: its invented folder is gone.")
        _ = slow.release(watch, now: now)
    }

    /// A reader that gives what it is told, in turn, and keeps the last; it can be held in its read until released.
    /// Its fields are written on its lane's queue and read on the test's: behind a lock.
    final class Scripted: Reader, @unchecked Sendable {
        let kind = "scripted", programs: Set<String> = ["scripted"]
        let started = DispatchSemaphore(value: 0), hold = DispatchSemaphore(value: 0), returned = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var steps: [Result<Reading, any Error>] = [], asked: [Bool] = [], held = false
        var script: [Result<Reading, any Error>] {
            get { lock.withLock { steps } }
            set { lock.withLock { steps = newValue } }
        }
        var holding: Bool {
            get { lock.withLock { held } }
            set { lock.withLock { held = newValue } }
        }
        var walks: [Bool] { lock.withLock { asked } }

        func read(_ snapshot: Snapshot, discover: Bool, now: Date) throws -> Reading {
            let (holds, next) = lock.withLock { () -> (Bool, Result<Reading, any Error>) in
                asked.append(discover)
                return (held, steps.count > 1 ? steps.removeFirst() : steps.first ?? .success(Reading()))
            }
            defer { if holds { returned.signal() } }
            if holds {
                started.signal()
                hold.wait()
            }
            return try next.get()
        }

        /// Lets a held read return, then ticks `watch` until it reads again, the return taken: what that tick saw.
        func release(_ watch: Watch, now: Date) -> Seen {
            holding = false
            hold.signal()
            #expect(returned.wait(timeout: .now() + 30) == .success)
            let before = walks.count
            var seen = watch.tick(now: now)
            // The lane records the return a moment after the read ends; until then a tick does not ask it again.
            for _ in 0..<10_000 where walks.count == before {
                Thread.sleep(forTimeInterval: 0.001)
                seen = watch.tick(now: now)
            }
            return seen
        }
    }

    /// A reader that finds nothing and remembers, tick by tick, whether it was asked to walk.
    final class Walks: Reader {
        let kind = "walks", programs: Set<String> = []
        var walks: [Bool] = []
        func read(_ snapshot: Snapshot, discover: Bool, now: Date) -> Reading {
            walks.append(discover)
            return Reading()
        }
    }

    @Test func theEngineMergesLaunchedAndSeenAgents() async throws {
        let place = try EngineTests.Place(prefix: "watch-engine-")
        defer { place.remove() }
        let home = try ClaudeHome(prefix: "watch-claude-")
        defer { home.remove() }
        let engine = Engine.throwaway(place.environment)
        var snapshot = ClaudeHome.snapshot()
        engine.watch = Watch(readers: [home.reader], snapshot: { snapshot })
        var changes = 0
        engine.changed = { changes += 1 }
        let id = try engine.launch("claude", folder: place.work.path, model: nil, mode: nil, effort: nil)
        let launched = try #require(engine.state.agents.first { $0.id == id })
        changes = 0
        engine.saw(engine.watch.tick(now: Date()))
        #expect(changes == 1)
        let state = engine.state
        #expect(state.agents.map(\.origin) == ["launched", "elsewhere", "elsewhere"])
        #expect(state.threads.count == 3)
        #expect(state.kinds["claude"]?.reader == "ok" && state.kinds["claude"]?.seen == "2.1.299" && state.kinds["claude"]?.note == nil)
        #expect(state.kinds["codex"]?.reader == "none")
        engine.saw(engine.watch.tick(now: Date()))
        #expect(changes == 1, "nothing changed, nothing is said")

        // The launched Claude's own record, seen through its group or its --session-id, is not listed twice.
        let pid = Int32(try #require(launched.pid))
        let record = home.sessions.appendingPathComponent("\(pid).json")
        try Data(#"{"pid":\#(pid),"sessionId":"\#(launched.thread!)","cwd":"\#(place.work.path)","procStart":"Sat Oct 17 08:55:00 2026","kind":"interactive","status":"idle"}"#.utf8).write(to: record)
        snapshot = Snapshot(Array(snapshot.processes.values) + [Running(pid: pid, parent: getpid(), group: pid, started: Date(timeIntervalSince1970: 1_792_227_300), name: "claude")])
        engine.saw(engine.watch.tick(now: Date()))
        #expect(engine.state.agents.count == 3 && engine.state.agents.filter { $0.thread == launched.thread }.map(\.origin) == ["launched"])
        try FileManager.default.removeItem(at: record)
        let done = Stopped()
        engine.stopAll(within: 3) { done.done = true }
        let end = Date().addingTimeInterval(30)
        while !done.done, Date() < end { try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(done.done)

        // Once that child ended, a Claude started by hand whose group has the child's old pid is listed.
        snapshot = Snapshot(ClaudeHome.snapshot().processes.values.map { process in
            var process = process
            if process.pid == 41300 { process.group = pid }
            return process
        })
        engine.saw(engine.watch.tick(now: Date()))
        #expect(engine.state.agents.contains { $0.thread == ClaudeHome.blog && $0.origin == "elsewhere" })
    }
}

/// Continue here: a conversation no process holds, for the kinds whose drivers resume one.
@Test func continueHereFollowsTheHolder() {
    #expect(Registry.described.continuable("claude", alive: true, pid: 41234) == (false, "Claude Code still runs this conversation (pid 41234). Quit it there first."))
    #expect(Registry.described.continuable("claude", alive: false, pid: nil) == (true, nil))
    #expect(Registry.described.continuable("codex", alive: nil, pid: nil) == (true, nil), "Codex refuses a second writer by itself")
    #expect(Registry.described.continuable("claude", alive: nil, pid: nil).0 == false)
    #expect(Registry.described.continuable("pi", alive: false, pid: nil) == (false, "something cannot continue pi conversations started elsewhere yet."))
}

/// A clock for `Watch.repeating` that moves only when `advance` is called, firing each timer at each of its times
/// passed, on its queue, before `advance` returns.
final class FakeClock {
    private var now: TimeInterval = 0, made = 0
    private var timers: [Int: (every: TimeInterval, next: TimeInterval, fire: () -> Void)] = [:]

    func repeating(_ seconds: TimeInterval, _ queue: DispatchQueue, _ fire: @escaping () -> Void) -> () -> Void {
        made += 1
        let id = made
        timers[id] = (seconds, now, { queue.sync(execute: fire) })
        advance(0)
        return { [weak self] in self?.timers[id] = nil }
    }

    func advance(_ seconds: TimeInterval) {
        let end = now + seconds
        while let (id, timer) = timers.filter({ $0.value.next <= end }).min(by: { $0.value.next < $1.value.next }) {
            now = timer.next
            timers[id]?.next += timer.every
            timer.fire()
        }
        now = end
    }
}
