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

    init(_ script: String, input: Bool = true) throws {
        spawn = Spawn(path: "/bin/sh", arguments: ["-c", script], folder: NSTemporaryDirectory(),
                      environment: ["PATH": "/usr/bin:/bin", "HOME": "/Users/example"], input: input)
        try spawn.start(lines: { [self] data in lock.withLock { said.append((String(decoding: data, as: UTF8.self), Date())) } },
                        ended: { [self] code in lock.withLock { status = code }; ended.signal() })
    }

    var lines: [String] { lock.withLock { said.map(\.line) } }
    func when(_ line: String) -> Date? { lock.withLock { said.first { $0.line == line }?.at } }

    /// Waits until `line` was written, at most `seconds`.
    func wait(for line: String, seconds: Double = 5) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline { if lines.contains(line) { return true }; usleep(10_000) }
        return false
    }

    /// Runs the ladder and returns how long it took.
    func stop(cap: TimeInterval = .infinity) -> TimeInterval {
        let start = Date(), done = DispatchSemaphore(value: 0)
        spawn.stop(cap: cap) { done.signal() }
        done.wait()
        return Date().timeIntervalSince(start)
    }
}

func processExists(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

@Suite struct SpawnTests {
    @Test func theProgramLeadsItsOwnGroup() throws {
        let fixture = try Fixture("echo ready; read line")
        #expect(fixture.wait(for: "ready"))
        #expect(getpgid(fixture.spawn.pid) == fixture.spawn.pid)
        #expect(getpgid(fixture.spawn.pid) != getpgrp())
        #expect(fixture.stop() < 2)
    }

    /// The program ignores the end of its input and SIGTERM: every step of the ladder runs, in order, on time.
    @Test func theLadderRunsInOrderAndOnTime() throws {
        let fixture = try Fixture("""
            trap 'echo term' TERM
            echo ready
            read line; echo "got $line"
            read line || echo eof
            while :; do sleep 0.05; done
            """)
        #expect(fixture.wait(for: "ready"))
        let start = Date()
        fixture.spawn.graceful = { try? fixture.spawn.write(Data("bye".utf8)) }
        let took = fixture.stop()
        #expect(fixture.ended.wait(timeout: .now() + 3) == .success)
        #expect(fixture.lines == ["ready", "got bye", "eof", "term"])
        let term = try #require(fixture.when("term")).timeIntervalSince(start)
        #expect(term > 2.8 && term < 4)
        #expect(took > 4.8 && took < 6.5)
        #expect(fixture.status == 128 + SIGKILL)
    }

    /// The shell ends at the end of its input; the child it left behind is reparented, and the group signal reaches it.
    @Test func aReparentedGrandchildIsKilled() throws {
        let fixture = try Fixture("sleep 60 & echo $!; read line; exit 0")
        let deadline = Date().addingTimeInterval(5)
        while fixture.lines.isEmpty && Date() < deadline { usleep(10_000) }
        let grandchild = try #require(pid_t(fixture.lines.first ?? ""))
        #expect(processExists(grandchild))
        let took = fixture.stop()
        #expect(fixture.status == 0)
        #expect(took > 2.8 && took < 4.5)
        #expect(getpgid(grandchild) == -1)
    }

    /// Lines come back whole, whatever they hold: U+2028 and U+2029 are not line ends, and 1 MB is one line.
    @Test func linesComeBackWhole() throws {
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
        #expect(fixture.ended.wait(timeout: .now() + 10) == .success)
        #expect(fixture.lines.count == sent.count)
        #expect(fixture.lines == sent)
    }

    @Test func aLineWithANewlineIsRefused() throws {
        let fixture = try Fixture("exec /bin/cat")
        #expect(throws: CodedError.self) { try fixture.spawn.write(Data("two\nlines".utf8)) }
        _ = fixture.stop()
        #expect(throws: CodedError.self) { try fixture.spawn.write(Data("late".utf8)) }
    }

    @Test func theLast64KBOfErrorsAreKept() throws {
        let fixture = try Fixture("i=0; while [ $i -lt 2000 ]; do printf '%099d\\n' $i >&2; i=$((i+1)); done; printf end >&2", input: false)
        #expect(fixture.ended.wait(timeout: .now() + 10) == .success)
        #expect(fixture.spawn.errorTail.utf8.count == Spawn.keptErrors)
        #expect(fixture.spawn.errorTail.hasSuffix("01999\nend"))
    }

    /// Only something holds a program's input: closing it ends that program even while another one runs, which is
    /// what happens to every child when something crashes.
    @Test func eachInputIsHeldOnlyBySomething() throws {
        let first = try Fixture("exec /bin/cat"), second = try Fixture("exec /bin/cat")
        first.spawn.closeInput()
        #expect(first.ended.wait(timeout: .now() + 2) == .success)
        #expect(second.spawn.running)
        #expect(second.stop() < 2)
    }

    @Test func atQuitEveryLadderRunsAtOnceWithinItsCap() throws {
        let stubborn = "trap '' TERM; echo ready; while :; do sleep 0.05; done"
        let fixtures = try [Fixture(stubborn), Fixture(stubborn), Fixture(stubborn)]
        for fixture in fixtures {
            #expect(fixture.wait(for: "ready"))
            fixture.spawn.graceful = { sleep(10) }   // a driver's step that never ends is cut by the cap
        }
        let start = Date(), done = DispatchSemaphore(value: 0)
        Spawn.stopAll(fixtures.map(\.spawn), cap: 1.5) { done.signal() }
        done.wait()
        let took = Date().timeIntervalSince(start)
        #expect(took > 1.4 && took < 3)
        for fixture in fixtures { #expect(!processExists(fixture.spawn.pid)) }
    }

    @Test func theExitCodeIsGiven() throws {
        let fixture = try Fixture("exit 3", input: false)
        #expect(fixture.ended.wait(timeout: .now() + 5) == .success)
        #expect(fixture.status == 3)
    }

    @Test func aSpawnNeverStartedStopsAtOnce() {
        let spawn = Spawn(path: "/bin/sh", arguments: [], folder: "/", environment: [:])
        let done = DispatchSemaphore(value: 0)
        spawn.stop { done.signal() }
        #expect(done.wait(timeout: .now() + 1) == .success)
    }

    @Test func aMissingFileIsNotInstalled() {
        let spawn = Spawn(path: "/Users/example/no-such-agent", arguments: [], folder: "/", environment: [:])
        #expect(throws: CodedError.self) { try spawn.start(lines: { _ in }, ended: { _ in }) }
        do { try spawn.start(lines: { _ in }, ended: { _ in }) } catch let error as CodedError {
            #expect(error.code == "NOT_INSTALLED")
        } catch {}
    }
}

@Suite struct HeldQueueTests {
    let at = "2026-10-17T09:00:00Z"
    func fresh() -> HeldQueue { HeldQueue(Fold(Agent(id: "a1", kind: "claude", origin: "launched"))) }

    @Test func nextWaitsForTheEndOfTheTurnAndNowSteers() throws {
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

    @Test func anInterruptEmptiesTheQueue() throws {
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

    @Test func aFailedTurnStillHandsTheNextOneOver() throws {
        var queue = fresh()
        _ = try queue.send("Hello.", when: "next", at: at)
        _ = try queue.send("Then the tests.", when: "next", at: at)
        let failed = AgentError(code: "AGENT_ERROR", message: "Invented failure.")
        #expect(queue.record(.turnEnded(.failed(failed)), at: at)?.text == "Then the tests.")
    }

    @Test func anEndedAgentTakesNothing() throws {
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
