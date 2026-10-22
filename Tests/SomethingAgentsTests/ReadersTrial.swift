// Trials of CodexReader and OpenCodeReader against the real programs and files. Each runs only when asked.
//
// T-2 and T-3, the reader's part: a REAL codex (`app-server`) and a REAL opencode (`acp`), each in the throwaway home
// of its driver's trial (CodexRun, OpenCodeRun: a fake model, deleted after), are read from their files and the
// process table only, as agents started elsewhere, with the evidence of their liveness:
//
//   SOMETHING_TRIAL_CODEX=/opt/homebrew/bin/codex swift test --filter ReadersTrial
//   SOMETHING_TRIAL_OPENCODE=/opt/homebrew/bin/opencode swift test --filter ReadersTrial
//
// T-10, each reader run once read-only on this Mac's own ~/.codex or OpenCode database. They print counts and
// timings only, never a name, a path, a title or a text:
//
//   SOMETHING_TRIAL_REAL_CODEX=1 SOMETHING_TRIAL_REAL_OPENCODE=1 swift test --filter ReadersTrial
//   SOMETHING_TRIAL_REAL_PI=1 SOMETHING_TRIAL_REAL_OMP=1 swift test --filter ReadersTrial
//
// The cost of the watch loop with every reader on this Mac's own homes, read-only: CPU time per tick and resident
// memory, a minute at each cadence (2 s and 10 s). Numbers only:
//
//   SOMETHING_TRIAL_COST=1 swift test --filter ReadersTrial
import Darwin
import Foundation
import Testing
@testable import SomethingAgents
@testable import AgentACP
@testable import AgentClaude
@testable import AgentCodex
@testable import AgentPi
import SomethingCore

@Suite(.serialized) @MainActor struct ReadersTrial {
    nonisolated static let environment = ProcessInfo.processInfo.environment

    @Test(.enabled(if: trialCodex != nil, "T-2 needs Codex: set SOMETHING_TRIAL_CODEX to its program's path."))
    func aCodexIsReadWithItsLock() async throws {
        let run = try CodexRun("reader-elsewhere")
        defer { run.cleanup() }
        let reader = CodexReader(environment: ["HOME": run.root.appendingPathComponent("home").path, "CODEX_HOME": run.home.path])
        let processes = Processes(known: reader.programs)
        func seen() -> Sighting? {
            reader.read(processes.snapshot(), discover: true, now: Date()).sightings.first { $0.key == run.state.thread }
        }
        try await run.until("the thread") { run.state.thread != nil }
        _ = try run.send("Please run-sleep for me.")
        try await run.until("the turn") { run.state.state == "working" && run.items.count >= 1 }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let working = try #require(seen(), "the index or the day folders give the thread")
        print("T-2 reader: working: alive \(String(describing: working.facts.alive)), evidence \(working.facts.evidence ?? "null"), turn open \(String(describing: working.facts.turnOpen))")
        #expect(working.facts.alive == true && working.facts.evidence == "lock" && working.pid.map { processes.snapshot()[$0]?.group } == Int32(run.spawn.pid))
        #expect(StateMap.map(working.facts, now: Date()).state == "working" && working.facts.waiting == .unknown)
        try await run.until("the end of the turn", seconds: 30) { run.turns == ["done"] && run.state.state == "idle" }
        try await Task.sleep(nanoseconds: 500_000_000)
        let idle = try #require(seen())
        #expect(idle.facts.alive == true && idle.facts.turnOpen == false && idle.turns.last?.state == "done")
        #expect(idle.turns.last?.items.first?.author == "person" && idle.model == "fake-model" && idle.folder.map(HeldFiles.real) == HeldFiles.real(run.work.path), "Codex names the folder by its real path")
        try await run.finish()
        let ended = try #require(seen())
        // The run's codex descends from this test, as something's own would: only another codex (the person's) leaves
        // the end unproven.
        let others = processes.snapshot().processes.values.filter { $0.name == "codex" && !processes.snapshot().descends($0.pid, from: getpid()) }
        print("T-2 reader: ended: alive \(String(describing: ended.facts.alive)), evidence \(ended.facts.evidence ?? "null"), other codex processes on this Mac \(others.count)")
        #expect(ended.facts.alive != true && ended.pid == nil)
        if others.isEmpty {
            #expect(ended.facts.alive == false && ended.facts.evidence == "process")
        } else {
            print("T-2 reader: the check of \"no codex process, so ended\" is skipped: another codex runs on this Mac.")
        }
    }

    @Test(.enabled(if: trialOpenCode != nil, "T-3 needs OpenCode: set SOMETHING_TRIAL_OPENCODE to its program's path."))
    func anOpenCodeIsReadWithItsClaim() async throws {
        let run = try OpenCodeRun("reader-elsewhere")
        defer { run.cleanup() }
        let reader = OpenCodeReader(environment: ["HOME": run.root.appendingPathComponent("home").path, "XDG_DATA_HOME": run.root.appendingPathComponent("data").path])
        let processes = Processes(known: reader.programs)
        func seen(as own: Int32) -> Sighting? {
            reader.own = own
            return reader.read(processes.snapshot(), discover: false, now: Date()).sightings.first { $0.key == run.state.thread }
        }
        _ = try run.send("Please run-sleep for me.")
        try await run.until("the turn") { run.opencode.prompting && run.items.count == 2 }
        try await Task.sleep(nanoseconds: 500_000_000)
        let snapshot = processes.snapshot()
        func descends(_ process: Running) -> Bool {
            var current: Running? = process
            for _ in 0..<16 { if current?.pid == Int32(run.spawn.pid) { return true }; current = current.flatMap { snapshot[$0.parent] } }
            return false
        }
        // Seen by another something (a pid no process has), this OpenCode is someone else's: it holds the claim it took.
        let held = try #require(seen(as: Int32.max))
        print("T-3 reader: held: alive \(String(describing: held.facts.alive)), evidence \(held.facts.evidence ?? "null"), holder descends from the run \(held.pid.flatMap { snapshot[$0] }.map(descends) ?? false)")
        #expect(held.facts.alive == true && held.facts.evidence == "claim" && StateMap.map(held.facts, now: Date()).state == "working")
        // Seen by the something that started it, its own server holds no claim of an agent seen elsewhere.
        let others = snapshot.processes.values.filter { $0.name == "opencode" && !descends($0) }
        let own = try #require(seen(as: getpid()))
        print("T-3 reader: as its launcher: alive \(String(describing: own.facts.alive)), other OpenCode processes on this Mac \(others.count)")
        if others.isEmpty { #expect(own.facts.alive == false && own.because["resume"] == OpenCodeReader.mayResume) }
        try await run.finish()
        let ended = try #require(seen(as: Int32.max))
        print("T-3 reader: ended: alive \(String(describing: ended.facts.alive)), state \(StateMap.map(ended.facts, now: Date()).state)")
        #expect(ended.facts.alive != true && ended.facts.turnOpen == false && ended.because.isEmpty)
    }

    /// T-10 for Codex: the reader once on this Mac's own ~/.codex, read-only. Counts and timings only.
    @Test(.enabled(if: environment["SOMETHING_TRIAL_REAL_CODEX"] == "1", "T-10 reads this Mac's own sessions: set SOMETHING_TRIAL_REAL_CODEX=1."))
    func theCodexReaderOnThisMacsOwnSessions() {
        let reader = CodexReader(environment: ReadersTrial.environment)
        var opened = 0
        reader.opened = { _ in opened += 1 }
        ReadersTrial.report("codex", reader) { opened }
    }

    /// T-10 for OpenCode: the reader once on this Mac's own database, read-only. Counts and timings only.
    @Test(.enabled(if: environment["SOMETHING_TRIAL_REAL_OPENCODE"] == "1", "T-10 reads this Mac's own sessions: set SOMETHING_TRIAL_REAL_OPENCODE=1."))
    func theOpenCodeReaderOnThisMacsOwnSessions() {
        let reader = OpenCodeReader(environment: ReadersTrial.environment)
        var opened = 0
        reader.opened = { _ in opened += 1 }
        ReadersTrial.report(reader.kind, reader) { opened }
    }

    /// T-10 for pi and OMP: each reader once on this Mac's own ~/.pi or ~/.omp, read-only, then the fold of the five
    /// logs written last, however old, since a log idle for a day is not listed. Counts only.
    @Test(.enabled(if: environment["SOMETHING_TRIAL_REAL_PI"] == "1", "T-10 reads this Mac's own sessions: set SOMETHING_TRIAL_REAL_PI=1."))
    func thePiReaderOnThisMacsOwnSessions() throws {
        let reader = PiReader(environment: ReadersTrial.environment)
        var opened: [String] = []
        reader.opened = { opened.append($0) }
        ReadersTrial.report("pi", reader) { opened.count }
        let root = try #require(reader.folder)
        let roots = ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []).map { "\(root)/\($0)/sessions" }.filter(ClaudeReader.isFolder)
        ReadersTrial.fold("pi", PiLog.logs(in: roots), line: 0, skip: 0)
        #expect(opened.allSatisfy { $0.hasSuffix(".jsonl") })
    }

    @Test(.enabled(if: environment["SOMETHING_TRIAL_REAL_OMP"] == "1", "T-10 reads this Mac's own sessions: set SOMETHING_TRIAL_REAL_OMP=1."))
    func theOMPReaderOnThisMacsOwnSessions() throws {
        let reader = OMPReader(environment: ReadersTrial.environment)
        var opened: [String] = []
        reader.opened = { opened.append($0) }
        ReadersTrial.report("omp", reader) { opened.count }
        let root = try #require(reader.folder)
        let logs = PiLog.logs(in: ["\(root)/agent/sessions"].filter(ClaudeReader.isFolder)).filter { ($0 as NSString).lastPathComponent.contains("_") }
        ReadersTrial.fold("omp", logs, line: 1, skip: OMPReader.titleSlot)
        #expect(opened.allSatisfy { $0.hasSuffix(".jsonl") })
    }

    /// Folds the five logs of `paths` written last and prints what they give, in counts.
    static func fold(_ kind: String, _ paths: [String], line: Int, skip: Int) {
        let headers = paths.map { PiLog.header($0, line: line, opened: { _ in }) }
        let newest = zip(paths, headers).compactMap { path, header in header.flatMap { h in Stamp(path).map { (path, h, $0) } } }
            .sorted { $0.2.modified > $1.2.modified }.prefix(5)
        var turns = 0, items = 0, incomplete = 0, titled = 0, models = 0, efforts = 0, states: [String: Int] = [:], ms: [Double] = []
        for (path, header, stamp) in newest {
            let begin = Date()
            var file = PiFile(path: path, header: header, log: PiLog(name: kind))
            if skip > 0 { file.title = OMPReader.title(path, opened: { _ in }) }
            file.follow(stamp, skip: skip, opened: { _ in })
            ms.append(Date().timeIntervalSince(begin) * 1000)
            turns += file.log.turns.count
            items += file.log.turns.reduce(0) { $0 + $1.items.count }
            incomplete += file.log.complete ? 0 : 1
            titled += (file.title ?? file.log.title) == nil ? 0 : 1
            models += file.log.model == nil ? 0 : 1
            efforts += file.log.effort == nil ? 0 : 1
            for turn in file.log.turns { states[turn.state, default: 0] += 1 }
        }
        print("""
        T-10 \(kind) files: \(paths.count) logs found, \(headers.compactMap { $0 }.count) with a readable header; the \(newest.count) newest: \(turns) turns, \(items) items, \
        \(incomplete) incomplete, title \(titled), model \(models), effort \(efforts); turn states \(states.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")); \
        ms per first read: \(ms.map { String(format: "%.1f", $0) }.joined(separator: ", "))
        """)
    }

    /// The watch loop with every reader, on this Mac's own homes: a minute at each cadence, a new watch for each.
    @Test(.enabled(if: environment["SOMETHING_TRIAL_COST"] == "1", "The cost trial reads this Mac's own sessions: set SOMETHING_TRIAL_COST=1."))
    func theCostOfTheWatchLoop() async throws {
        for cadence in [2.0, 10.0] {
            let watch = Watch(readers: Registry.described.readers(ReadersTrial.environment))
            var cpu: [Double] = [], wall: [Double] = [], resident: [Double] = [ReadersTrial.resident()]
            let start = Date()
            var seen = Seen()
            while Date().timeIntervalSince(start) < 60 {
                let (cpu0, wall0) = (clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID), Date())
                seen = watch.tick(now: Date())
                cpu.append(Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpu0) / 1e6)
                wall.append(Date().timeIntervalSince(wall0) * 1000)
                resident.append(ReadersTrial.resident())
                try await Task.sleep(nanoseconds: UInt64(cadence * 1e9))
            }
            let rest = cpu.dropFirst(), sorted = rest.sorted()
            func f(_ value: Double) -> String { String(format: "%.1f", value) }
            print("""
            Cost at \(Int(cadence)) s: \(cpu.count) ticks, \(seen.sightings.count) sightings; CPU ms first tick \(f(cpu[0])) (wall \(f(wall[0]))); \
            then mean \(f(rest.reduce(0, +) / Double(max(rest.count, 1)))), median \(f(sorted.isEmpty ? 0 : sorted[sorted.count / 2])), max \(f(sorted.last ?? 0)); \
            CPU ms in the minute \(f(cpu.reduce(0, +))); resident MB before \(f(resident[0])), after the first tick \(f(resident[1])), at the end \(f(resident.last!)), max \(f(resident.max()!))
            """)
        }
    }

    /// This process's resident memory, in MB.
    static func resident() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
    }

    /// Three ticks of a watch with `reader` alone, then counts of what the state would say.
    static func report(_ kind: String, _ reader: Reader, opened: () -> Int) {
        let watch = Watch(readers: [reader])
        var times: [Double] = [], seen = Seen()
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
                                                    ("model", { $0.model == nil }), ("mode", { $0.mode == nil }), ("effort", { $0.effort == nil }),
                                                    ("started", { $0.started == nil }), ("updated", { $0.updated == nil }), ("error", { $0.error == nil })]
        let nulls = missing.map { key, isNull in "\(key) \(agents.filter(isNull).count)" }.joined(separator: ", ")
        let reading = seen.kinds[kind]
        print("""
        T-10 \(kind): reader \(reading?.health ?? "none"), version found \(reading?.version != nil), note \(reading?.note != nil); \(agents.count) agents, \
        \(threads.reduce(0) { $0 + $1.turns.count }) turns, \(threads.reduce(0) { $0 + $1.turns.reduce(0) { $0 + $1.items.count } }) items, \
        \(threads.filter { !$0.complete }.count) threads incomplete
        T-10 \(kind): states \(count(agents.map(\.state))); evidence \(count(agents.map(\.evidence))); waiting \(count(agents.map(\.waiting)))
        T-10 \(kind): alive \(count(agents.map { $0.alive.map(String.init) })); turn states \(count(threads.flatMap(\.turns).map(\.state))); null keys: \(nulls)
        T-10 \(kind): files opened \(opened()); ms per tick: \(times.map { String(format: "%.1f", $0) }.joined(separator: ", "))
        """)
        #expect(reading?.health != "unreadable")
    }
}
