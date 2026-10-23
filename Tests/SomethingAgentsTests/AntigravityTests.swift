// Antigravity is seen by its CLI's process only: its kind, its folder, and nothing it does is guessed.
import Foundation
import Testing
@testable import AgentACP
@testable import SomethingAgents
import SomethingCore

@Suite struct AntigravityTests {
    @MainActor @Test func itsCLIIsSeenByItsProcess() throws {
        let started = Date(timeIntervalSince1970: 1_792_224_000)
        let snapshot = Snapshot([
            Running(pid: 55000, parent: 1, group: 55000, started: started, name: "agy", arguments: ["agy"], folder: "/Users/example/notes"),
            Running(pid: 55100, parent: 1, group: 55100, started: started, name: "agy-helper", arguments: ["agy-helper"], folder: "/Users/example/shop"),
        ])
        let reader = try #require(AgentDescriptor.antigravity.reader?([:]))
        let watch = Watch(readers: [reader], snapshot: { snapshot })
        let seen = watch.tick(now: started)
        let (agents, threads) = Watch.elsewhere(seen, registry: .described, groups: [], keys: [], now: started)
        #expect(agents.count == 1 && threads.isEmpty)
        let agy = try #require(agents.first)
        #expect(agy.id == "antigravity-agy-55000" && agy.kind == "antigravity" && agy.name == "notes" && agy.folder == "/Users/example/notes")
        #expect(agy.alive == true && agy.evidence == "process" && agy.state == "unknown" && agy.waiting == nil && agy.thread == nil)
        #expect(agy.can == Can() && agy.because == ["send": "something has no reader for this agent; it only sees its process."])
        // Nothing of its files is read: no reading of the kind is kept, and while agy is listed the state says none for
        // its reader (the guide says so) and why it is not launched.
        #expect(seen.kinds["antigravity"] == nil)
        let engine = Engine.throwaway(["HOME": "/Users/example", "PATH": "/nowhere"])
        engine.saw(seen)
        #expect(engine.state.agents.map(\.kind) == ["antigravity"])
        let kind = try #require(engine.state.kinds["antigravity"])
        #expect(kind.reader == "none" && kind.note == AgentDescriptor.antigravity.unavailable && kind.note != nil)
    }

    /// Known, never launched: no install sentence, no program looked for, no builder, and a launch is refused with the
    /// reason before anything starts.
    @MainActor @Test func itIsNotLaunched() throws {
        let antigravity = try #require(Registry.described.agent("antigravity"))
        #expect(antigravity.name == "Antigravity" && antigravity.install == nil && antigravity.driving == nil && antigravity.builder == nil)
        let reason = "Antigravity's ACP server needs a Google sign-in of its own first; something only sees agy for now."
        #expect(antigravity.unavailable == reason)
        #expect(throws: CodedError("NOT_SUPPORTED", reason)) {
            try Registry.described.checkLaunch("antigravity", model: nil, mode: nil, effort: nil)
        }
        let engine = Engine.throwaway(["HOME": "/Users/example", "PATH": "/nowhere"])
        let kind = try #require(engine.state.kinds["antigravity"])
        #expect(!kind.launch && kind.installed == nil && kind.tested == "none" && kind.reader == "none" && kind.note == reason)
    }
}
