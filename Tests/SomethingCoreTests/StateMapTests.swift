// StateMap: the full table of facts to state words, and the invariants that must hold for every combination.
import Foundation
import Testing
@testable import SomethingCore

@Suite struct StateMapTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    typealias Facts = StateMap.Facts

    /// Each row of the table, in the order of the guide: facts, then the state, waiting and evidence they give.
    var table: [(String, Facts, String, String?, String?)] {
        let recent = now.addingTimeInterval(-30), old = now.addingTimeInterval(-600)
        return [
            ("alive, turn open", Facts(alive: true, evidence: "child", turnOpen: true, waiting: .nothing), "working", "none", "child"),
            ("alive, turn closed", Facts(alive: true, evidence: "child", turnOpen: false, waiting: .nothing), "idle", "none", "child"),
            ("alive, no turn yet", Facts(alive: true, evidence: "child", waiting: .nothing), "idle", "none", "child"),
            ("alive, waits on a permission", Facts(alive: true, evidence: "child", turnOpen: true, waiting: .permission), "waiting", "permission", "child"),
            ("alive, waits on an answer", Facts(alive: true, evidence: "registry", turnOpen: true, waiting: .answer), "waiting", "answer", "registry"),
            ("alive, turn open, waiting unknown", Facts(alive: true, evidence: "lock", turnOpen: true), "working", nil, "lock"),
            ("alive, last turn failed", Facts(alive: true, evidence: "child", turnOpen: false, waiting: .nothing, failed: true), "error", "none", "child"),
            ("alive, last turn aborted", Facts(alive: true, evidence: "child", turnOpen: false, waiting: .nothing, aborted: true), "interrupted", "none", "child"),
            ("ended, end marker", Facts(alive: false, evidence: "process", ended: true), "done", "none", "process"),
            ("ended, end marker after an open turn", Facts(alive: false, evidence: "process", turnOpen: true, ended: true), "done", "none", "process"),
            ("ended, turn closed", Facts(alive: false, evidence: "process", turnOpen: false), "done", "none", "process"),
            ("ended, turn left open", Facts(alive: false, evidence: "process", turnOpen: true), "interrupted", "none", "process"),
            ("ended, aborted", Facts(alive: false, evidence: "child", turnOpen: false, aborted: true), "interrupted", "none", "child"),
            ("ended, failure", Facts(alive: false, evidence: "child", turnOpen: true, failed: true), "error", "none", "child"),
            ("unproven, open turn written 30 s ago", Facts(alive: nil, turnOpen: true, lastWrite: recent), "working", nil, "recent-write"),
            ("unproven, open turn written 10 min ago", Facts(alive: nil, turnOpen: true, lastWrite: old), "unknown", nil, nil),
            ("unproven, open turn, write time unknown", Facts(alive: nil, turnOpen: true), "unknown", nil, nil),
            ("unproven, turn closed", Facts(alive: nil, turnOpen: false, lastWrite: recent), "unknown", nil, nil),
            ("unproven, pi never waits", Facts(alive: nil, evidence: "cwd", turnOpen: false, waiting: .nothing), "unknown", "none", "cwd"),
            ("unproven, a wait without a holder", Facts(alive: nil, turnOpen: true, waiting: .permission, lastWrite: recent), "working", nil, "recent-write"),
            ("unproven, nothing at all", Facts(alive: nil), "unknown", nil, nil),
        ]
    }

    @Test func theTable() {
        for (name, facts, state, waiting, evidence) in table {
            let result = StateMap.map(facts, now: now)
            #expect(result == StateMap.Result(state: state, waiting: waiting, evidence: evidence), "\(name)")
        }
    }

    /// Every combination of facts: the words are the contract's, "waiting" goes with a wait and only with one,
    /// and nothing without a living holder is ever idle.
    @Test func theInvariantsHoldForEveryCombination() throws {
        let shape = try ContractFiles.object("shape.json")
        let agent = try #require((shape["types"] as? [String: [String: [String]]])?["Agent"])
        let words = Set(agent["state"]!.map { String($0.dropFirst()) })
        let waitings = Set(agent["waiting"]!.filter { $0.hasPrefix("=") }.map { String($0.dropFirst()) })
        var count = 0
        for alive in [true, false, nil] as [Bool?] {
            for turnOpen in [true, false, nil] as [Bool?] {
                for waiting in [StateMap.Waiting.permission, .answer, .nothing, .unknown] {
                    for (ended, failed, aborted) in [(false, false, false), (true, false, false), (false, true, false), (false, false, true)] {
                        for lastWrite in [nil, now.addingTimeInterval(-30), now.addingTimeInterval(-600)] {
                            let facts = Facts(alive: alive, evidence: "child", turnOpen: turnOpen, waiting: waiting,
                                              ended: ended, failed: failed, aborted: aborted, lastWrite: lastWrite)
                            let result = StateMap.map(facts, now: now)
                            count += 1
                            #expect(words.contains(result.state), "\(facts)")
                            #expect(result.waiting.map(waitings.contains) ?? true, "\(facts)")
                            #expect((result.state == "waiting") == ["permission", "answer"].contains(result.waiting), "\(facts)")
                            if alive != true { #expect(result.state != "idle", "\(facts)") }
                            if result.evidence == "recent-write" { #expect(alive == nil && result.state == "working") }
                        }
                    }
                }
            }
        }
        #expect(count == 3 * 3 * 4 * 4 * 3)
    }
}
