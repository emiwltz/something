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
        let (agents, threads) = Watch.elsewhere(seen, groups: [], keys: [], now: Date())
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
        #expect(Watch.elsewhere(seen, groups: [41290], keys: [], now: Date()).agents.map(\.thread) == [ClaudeHome.shop])
        #expect(Watch.elsewhere(seen, groups: [], keys: [ClaudeHome.shop], now: Date()).agents.map(\.thread) == [ClaudeHome.blog])
        #expect(Watch.elsewhere(seen, groups: [41290], keys: [ClaudeHome.shop], now: Date()).threads.isEmpty)
    }

    @Test func aChangedShapeShowsTheProcessesOnly() throws {
        let home = try ClaudeHome(prefix: "watch-claude-")
        defer { home.remove() }
        try Data(#"{"pid":41500,"session":"renamed","kind":"interactive"}"#.utf8).write(to: home.sessions.appendingPathComponent("41500.json"))
        let seen = Watch(readers: [home.reader], snapshot: { ClaudeHome.snapshot() }).tick(now: Date())
        #expect(seen.kinds["claude"]?.health == "changed")
        let (agents, threads) = Watch.elsewhere(seen, groups: [], keys: [], now: Date())
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
        #expect(Watch.elsewhere(watch.tick(now: Date()), groups: [], keys: [], now: Date()).agents.allSatisfy { $0.alive == true })
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
        let shop = try #require(Watch.elsewhere(seen, groups: [], keys: [], now: home.now).agents.first { $0.thread == ClaudeHome.shop })
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
    #expect(Watch.continuable("claude", alive: true, pid: 41234) == (false, "Claude Code still runs this conversation (pid 41234). Quit it there first."))
    #expect(Watch.continuable("claude", alive: false, pid: nil) == (true, nil))
    #expect(Watch.continuable("codex", alive: nil, pid: nil) == (true, nil), "Codex refuses a second writer by itself")
    #expect(Watch.continuable("claude", alive: nil, pid: nil).0 == false)
    #expect(Watch.continuable("pi", alive: false, pid: nil) == (false, "something cannot continue pi conversations started elsewhere yet."))
}
