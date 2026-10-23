// Spawn against /bin/sh fixtures (its group, the stop ladder, whole lines, the kept error output), and HeldQueue's
// rules without any process.
import Darwin
import Foundation
import Testing
@testable import SomethingAgents
import SomethingCore

/// A program that runs `script` in /bin/sh, with what it writes collected.
final class Fixture: @unchecked Sendable {
    let spawn: Spawn
    private let lock = NSLock()
    private var said: [(line: String, at: Date)] = []
    private(set) var status: Int32?
    let ended = DispatchSemaphore(value: 0)

    private(set) var endedAt: Date?

    init(_ script: String, input: Bool = true) throws {
        spawn = Spawn(path: "/bin/sh", arguments: ["-c", script], folder: NSTemporaryDirectory(),
                      environment: ["PATH": "/usr/bin:/bin", "HOME": "/Users/example"], input: input)
        try spawn.start(lines: { [self] data in lock.withLock { said.append((String(decoding: data, as: UTF8.self), Date())) } },
                        ended: { [self] code in
            lock.withLock {
                status = code
                endedAt = Date()
            }
            ended.signal()
        })
    }

    var lines: [String] { lock.withLock { said.map(\.line) } }
    func when(_ line: String) -> Date? { lock.withLock { said.first { $0.line == line }?.at } }
    var lastLineAt: Date? { lock.withLock { said.last?.at } }

    /// Waits until `line` was written, at most `seconds`; whether it was.
    func wait(for line: String, seconds: Double = 30) async -> Bool {
        await waitUntil(seconds) { lines.contains(line) }
    }

    /// Waits until the program ended, at most `seconds`; whether it did.
    func end(within seconds: Double) async throws -> Bool {
        try await waitOffPool(ended, seconds)
    }

    /// Runs the ladder and returns how long it took.
    func stop(cap: TimeInterval = .infinity) async throws -> TimeInterval {
        let start = Date(), done = DispatchSemaphore(value: 0)
        spawn.stop(cap: cap) { done.signal() }
        _ = try await waitOffPool(done, .infinity)
        return Date().timeIntervalSince(start)
    }
}

/// Waits for `semaphore` on a thread of its own, at most `seconds`; whether it was signalled. A test that blocks
/// waits for seconds on one of the few threads of Swift's shared pool (about three on a 3-core runner), and delays
/// every other test that needs one.
func waitOffPool(_ semaphore: DispatchSemaphore, _ seconds: Double) async throws -> Bool {
    try await offMain {
        semaphore.wait(timeout: seconds.isFinite ? .now() + seconds : .distantFuture) == .success
    }
}

/// Polls `condition` without holding a thread, at most `seconds`; whether it holds.
@discardableResult
func waitUntil(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() {
        guard Date() < deadline else { return false }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return true
}

/// Polls `condition` on the main actor, at most `seconds`; records an issue naming `what` and throws when it never holds.
@MainActor
func until(_ what: String, seconds: Double = 30, _ condition: () -> Bool) async throws {
    let end = Date().addingTimeInterval(seconds)
    while !condition() {
        guard Date() < end else { Issue.record("timed out waiting for \(what)"); throw CancellationError() }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
}

/// Runs `work`, which blocks, on a thread of its own, and returns what it returns or throws.
func offMain<T>(_ work: @escaping () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        Thread.detachNewThread { continuation.resume(with: Result { try work() }) }
    }
}

func processExists(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

@Suite struct SpawnTests {
    @Test func theProgramLeadsItsOwnGroup() async throws {
        let fixture = try Fixture("echo ready; read line")
        #expect(await fixture.wait(for: "ready"))
        #expect(getpgid(fixture.spawn.pid) == fixture.spawn.pid)
        #expect(getpgid(fixture.spawn.pid) != getpgrp())
        _ = try await fixture.stop()
        // Ended by its closed input, the ladder's first step, not by a signal (timed, this was flaky on busy runners).
        #expect(try await fixture.end(within: 10) && fixture.status.map { $0 < 128 } == true, "\(String(describing: fixture.status))")
    }

    /// The program ignores the end of its input and SIGTERM: every step of the ladder runs, in order, each after its
    /// wait (3 s from the closed input to SIGTERM, 2 s from SIGTERM to SIGKILL). Only lower bounds: on a busy Mac a
    /// timer fires late, never early.
    @Test func theLadderRunsInOrderAndOnTime() async throws {
        let fixture = try Fixture("""
            trap 'echo term' TERM
            echo ready
            read line; echo "got $line"
            read line || echo eof
            while :; do sleep 0.05; done
            """)
        #expect(await fixture.wait(for: "ready"))
        let start = Date()
        fixture.spawn.graceful = { try? fixture.spawn.write(Data("bye".utf8)) }
        let took = try await fixture.stop()
        #expect(try await fixture.end(within: 30))
        #expect(fixture.lines == ["ready", "got bye", "eof", "term"])
        let term = try #require(fixture.when("term")).timeIntervalSince(start)
        #expect(term > 2.8, "SIGTERM came \(term) s after the stop began")
        #expect(took - term > 1.8, "SIGKILL came \(took - term) s after SIGTERM")
        #expect(fixture.status == 128 + SIGKILL)
    }

    /// The shell ends at the end of its input; the child it left behind is reparented, and the group signal reaches it.
    @Test func aReparentedGrandchildIsKilled() async throws {
        let fixture = try Fixture("sleep 60 & echo $!; read line; exit 0")
        await waitUntil(30) { !fixture.lines.isEmpty }
        let grandchild = try #require(pid_t(fixture.lines.first ?? ""))
        #expect(processExists(grandchild))
        let took = try await fixture.stop()
        #expect(fixture.status == 0)
        #expect(took > 1.8, "the grandchild was given its 2 s")
        #expect(getpgid(grandchild) == -1)
    }

    /// With nobody stopping it, a program that ended leaves nothing behind that holds its outputs, and no line comes
    /// after `ended`.
    @Test func whatHoldsTheOutputsAfterTheEndIsEnded() async throws {
        let fixture = try Fixture("(sleep 1; echo late; sleep 60) & echo $!; exit 0", input: false)
        #expect(try await fixture.end(within: 10))
        let grandchild = try #require(pid_t(fixture.lines.first ?? ""))
        await waitUntil(10) { getpgid(grandchild) == -1 }
        #expect(getpgid(grandchild) == -1)
        #expect(try #require(fixture.lastLineAt) <= (try #require(fixture.endedAt)))
        #expect(fixture.lines.contains("late"))   // written within the two seconds the outputs are given
    }

    @Test func aWriteAfterTheEndIsRefused() async throws {
        let fixture = try Fixture("exit 0")
        #expect(try await fixture.end(within: 30))
        #expect(code { try fixture.spawn.write(Data("late".utf8)) }?.code == "AGENT_STOPPED")
    }

    /// The program closed its input but runs on: the write that fails makes the next one throw.
    @Test func aFailedWriteIsSaid() async throws {
        let fixture = try Fixture("exec 0<&-; echo ready; sleep 60")
        #expect(await fixture.wait(for: "ready"))
        try fixture.spawn.write(Data("lost".utf8))
        let deadline = Date().addingTimeInterval(10)
        var refused: CodedError?
        while refused == nil && Date() < deadline {
            refused = code { try fixture.spawn.write(Data("again".utf8)) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(refused?.code == "AGENT_STOPPED")
        _ = try await fixture.stop()
    }

    /// A second stop joins the ladder that runs, and its smaller cap still holds.
    @Test func aSecondStopJoinsTheFirst() async throws {
        let fixture = try Fixture("trap '' TERM; echo ready; while :; do sleep 0.05; done")
        #expect(await fixture.wait(for: "ready"))
        let start = Date(), first = DispatchSemaphore(value: 0), second = DispatchSemaphore(value: 0)
        // The time is taken when the ladder calls back, not when this task resumes: on a busy runner the resumption
        // alone took seconds. The semaphore orders the write before the read.
        var ended = Date.distantFuture
        fixture.spawn.stop { first.signal() }
        fixture.spawn.stop(cap: 1) { ended = Date(); second.signal() }
        #expect(try await waitOffPool(first, 30))
        #expect(try await waitOffPool(second, 30))
        // Uncapped, the ladder would kill the program, which ignores SIGTERM, 3 s + 2 s after the stop began.
        #expect(ended.timeIntervalSince(start) < 5, "the cap of 1 s killed it before the uncapped ladder would")
        #expect(!processExists(fixture.spawn.pid))
    }

    /// Lines come back whole, whatever they hold: U+2028 and U+2029 are not line ends, and 1 MB is one line.
    @Test func linesComeBackWhole() async throws {
        let fixture = try Fixture("exec /bin/cat")
        var sent = ["{\"text\":\"one\u{2028}two\u{2029}three\"}", "carriage\rreturn", "é漢字🙂", String(repeating: "x", count: 1_048_576)]
        var random = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let count = Int.random(in: 0...3_000, using: &random)
            let scalars = (0..<count).compactMap { _ in Unicode.Scalar(UInt32.random(in: 0x20...0x2FFF, using: &random)) }
            sent.append(String(String.UnicodeScalarView(scalars)))
        }
        for line in sent { try fixture.spawn.write(Data(line.utf8)) }
        fixture.spawn.closeInput()
        #expect(try await fixture.end(within: 10))
        #expect(fixture.lines.count == sent.count)
        #expect(fixture.lines == sent)
    }

    @Test func aLineWithANewlineIsRefused() async throws {
        let fixture = try Fixture("exec /bin/cat")
        #expect(throws: CodedError.self) { try fixture.spawn.write(Data("two\nlines".utf8)) }
        _ = try await fixture.stop()
        #expect(throws: CodedError.self) { try fixture.spawn.write(Data("late".utf8)) }
    }

    @Test func theLast64KBOfErrorsAreKept() async throws {
        let fixture = try Fixture("i=0; while [ $i -lt 2000 ]; do printf '%099d\\n' $i >&2; i=$((i+1)); done; printf end >&2", input: false)
        #expect(try await fixture.end(within: 10))
        #expect(fixture.spawn.errorTail.utf8.count == Spawn.keptErrors)
        #expect(fixture.spawn.errorTail.hasSuffix("01999\nend"))
    }

    /// Only something holds a program's input: closing it ends that program even while another one runs, which is
    /// what happens to every child when something crashes.
    @Test func eachInputIsHeldOnlyBySomething() async throws {
        let first = try Fixture("exec /bin/cat"), second = try Fixture("exec /bin/cat")
        first.spawn.closeInput()
        #expect(try await first.end(within: 10))
        #expect(second.spawn.running)
        _ = try await second.stop()
        #expect(try await second.end(within: 10) && second.status == 0, "ended by its closed input, not by a signal")
    }

    /// At quit's own cap (6 s), three programs whose first step never ends and that ignore SIGTERM: every ladder
    /// begins before any program ends, each is killed near the cap and before an uncapped ladder would kill it, and
    /// the whole stop ends well before three ladders one after another would. These are relations, not times: on a busy
    /// 3-core Mac a thread can wait its turn for seconds, and a short cap could not tell that wait from a ladder run late.
    @Test func atQuitEveryLadderRunsAtOnceWithinItsCap() async throws {
        let stubborn = "trap '' TERM; echo ready; while :; do sleep 0.05; done"
        let fixtures = try [Fixture(stubborn), Fixture(stubborn), Fixture(stubborn)]
        let steps = NSLock()
        var stepsBegun: [Date] = []
        for fixture in fixtures {
            #expect(await fixture.wait(for: "ready"))
            fixture.spawn.graceful = {   // a driver's step that never ends is cut at 3 s, the ladder's own limit
                steps.withLock { stepsBegun.append(Date()) }
                sleep(10)
            }
        }
        let start = Date(), done = DispatchSemaphore(value: 0)
        Spawn.stopAll(fixtures.map(\.spawn)) { done.signal() }
        _ = try await waitOffPool(done, .infinity)
        let took = Date().timeIntervalSince(start), cap = 6.0, gracefulLimit = 3.0, closedToKill = 5.0
        let begun = steps.withLock { stepsBegun }, ended = fixtures.compactMap(\.endedAt)
        let timeline = "steps began at \(begun.map { $0.timeIntervalSince(start) }), programs ended at \(ended.map { $0.timeIntervalSince(start) }), done at \(took) s"
        #expect(begun.count == 3 && ended.count == 3, "\(timeline)")
        #expect(begun.max().map { last in ended.allSatisfy { last < $0 } } == true, "every ladder begins before any program ends: \(timeline)")
        // SIGKILL comes 0.25 s before the cap: no program ended before it, since none gave way earlier.
        #expect(ended.allSatisfy { $0.timeIntervalSince(start) > cap - 0.3 }, "\(timeline)")
        // Uncapped, SIGKILL would come 3 s (graceful) + 5 s (input closed to SIGKILL) after the stop began.
        #expect(ended.allSatisfy { $0.timeIntervalSince(start) < gracefulLimit + closedToKill }, "killed by the cap: \(timeline)")
        #expect(took < 3 * (cap - 0.25), "within the cap, far from three ladders one after another: \(timeline)")
        for fixture in fixtures { #expect(!processExists(fixture.spawn.pid)) }
    }

    @Test func theExitCodeIsGiven() async throws {
        let fixture = try Fixture("exit 3", input: false)
        #expect(try await fixture.end(within: 30))
        #expect(fixture.status == 3)
    }

    @Test func aSpawnNeverStartedStopsAtOnce() async throws {
        let spawn = Spawn(path: "/bin/sh", arguments: [], folder: "/", environment: [:])
        var done = false
        spawn.stop { done = true }
        #expect(done, "called before stop returns")
    }

    @Test func aMissingFileIsNotInstalled() {
        let spawn = Spawn(path: "/Users/example/no-such-agent", arguments: [], folder: "/", environment: [:])
        #expect(code { try spawn.start(lines: { _ in }, ended: { _ in }) }?.code == "NOT_INSTALLED")
    }

    /// posix_spawn answers ENOENT for a missing folder too: the program is fine, and is not said to be missing.
    @Test func aMissingFolderIsSaidAsSuch() {
        let spawn = Spawn(path: "/bin/sh", arguments: [], folder: "/Users/example/missing", environment: [:])
        #expect(code { try spawn.start(lines: { _ in }, ended: { _ in }) } ==
                CodedError("LAUNCH_FAILED", "The folder /Users/example/missing does not exist on this Mac."))
    }
}

@Suite struct HeldQueueTests {
    let at = "2026-10-17T09:00:00Z"
    func fresh() -> HeldQueue { HeldQueue(Fold(Agent(id: "a1", kind: "claude", origin: "launched"))) }

    @Test func nextWaitsForTheEndOfTheTurnAndNowSteers() async throws {
        var queue = fresh()
        #expect(try queue.send("Hello.", when: "next", at: at) == .started)
        #expect(queue.record(.turnStarted(id: "t1"), at: at) == nil)
        #expect(try queue.send("Then the tests.", when: "next", at: at) == .queued)
        #expect(try queue.send("And the docs.", when: "next", at: at) == .queued)
        #expect(try queue.send("Use the small one.", when: "now", at: at) == .steered)
        #expect(queue.fold.agent.queue.map(\.text) == ["Then the tests.", "And the docs."])
        // Each end of turn hands one message over; the turn it starts is open at once.
        #expect(queue.record(.turnEnded(.done), at: at)?.text == "Then the tests.")
        #expect(try queue.send("Last.", when: "next", at: at) == .queued)
        #expect(queue.record(.turnEnded(.done), at: at)?.text == "And the docs.")
        #expect(queue.record(.turnEnded(.done), at: at)?.text == "Last.")
        #expect(queue.record(.turnEnded(.done), at: at) == nil)
        #expect(try queue.send("Idle again.", when: "now", at: at) == .started)
    }

    @Test func anInterruptEmptiesTheQueue() async throws {
        var queue = fresh()
        #expect(queue.interrupt() == false)
        _ = try queue.send("Hello.", when: "next", at: at)
        _ = queue.record(.turnStarted(id: nil), at: at)
        _ = try queue.send("Then the tests.", when: "next", at: at)
        #expect(queue.interrupt() == true)
        #expect(queue.fold.agent.queue.isEmpty)
        #expect(queue.record(.turnEnded(.interrupted), at: at) == nil)
        #expect(try queue.send("Fresh.", when: "next", at: at) == .started)
    }

    /// What is sent between an interrupt and the end of the turn it stops was said to be queued: it is delivered.
    @Test func aMessageHeldAfterAnInterruptIsDelivered() async throws {
        var queue = fresh()
        _ = try queue.send("Hello.", when: "next", at: at)
        _ = queue.record(.turnStarted(id: nil), at: at)
        _ = try queue.send("Dropped by the interrupt.", when: "next", at: at)
        #expect(queue.interrupt() == true)
        #expect(try queue.send("After the interrupt.", when: "next", at: at) == .queued)
        #expect(try queue.send("And this one.", when: "next", at: at) == .queued)
        #expect(queue.record(.turnEnded(.interrupted), at: at)?.text == "After the interrupt.")
        #expect(queue.fold.agent.queue.map(\.text) == ["And this one."])
        #expect(queue.record(.turnEnded(.done), at: at)?.text == "And this one.")
    }

    @Test func aFailedTurnStillHandsTheNextOneOver() async throws {
        var queue = fresh()
        _ = try queue.send("Hello.", when: "next", at: at)
        _ = try queue.send("Then the tests.", when: "next", at: at)
        let failed = AgentError(code: "AGENT_ERROR", message: "Invented failure.")
        #expect(queue.record(.turnEnded(.failed(failed)), at: at)?.text == "Then the tests.")
    }

    @Test func anEndedAgentTakesNothing() async throws {
        var queue = fresh()
        _ = try queue.send("Hello.", when: "next", at: at)
        _ = try queue.send("Then the tests.", when: "next", at: at)
        _ = queue.record(.stopped(nil), at: at)
        #expect(queue.fold.agent.queue.isEmpty)
        #expect(throws: CodedError("AGENT_STOPPED", "The agent has ended; launch or resume it to go on.")) {
            try queue.send("Late.", when: "next", at: at)
        }
        var other = fresh()
        #expect(throws: CodedError.self) { try other.send("Soon.", when: "later", at: at) }
    }
}
