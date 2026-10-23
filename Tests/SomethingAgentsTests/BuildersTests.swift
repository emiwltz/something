// Every agent something drives is also a space builder. For each kind with a driver, its
// recorded build (Tests/Exchanges/<kind>/assistant-build.jsonl, a trial of the real program as the person's
// assistant) is played through its driver, and must make and check a space, every tool done, nothing asked of the
// person, no error. An agent without a passing build is not offered as driven: it stays seen, with the reason in its
// descriptor's `unavailable`. The driven kinds are those of Tests/Exchanges/driven.txt, the one list both test targets
// hold their registry to: DescriptorsTests holds the tests' copy to it, somethingTests' ExtensionsTests the app's own.
import Foundation
import Testing
@testable import SomethingAgents
import SomethingCore

@Suite struct BuildersTests {
    static let exchanges = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Exchanges")
    /// The kinds the app drives, one per line of Tests/Exchanges/driven.txt.
    static let driven = ((try? String(contentsOf: exchanges.appendingPathComponent("driven.txt"), encoding: .utf8)) ?? "")
        .split(separator: "\n").map(String.init)

    @Test(arguments: BuildersTests.driven)
    func everyDrivenAgentBuilds(_ kind: String) throws {
        let name = Registry.described.name(of: kind)
        #expect(Registry.described.agent(kind)?.builder != nil, "\(name) is driven but not offered as a builder")
        let file = Self.exchanges.appendingPathComponent("\(kind)/assistant-build.jsonl")
        try #require(FileManager.default.fileExists(atPath: file.path), "\(name) is driven without a recorded build: \(file.lastPathComponent)")
        let first = try JSONSerialization.jsonObject(with: Data(try String(contentsOf: file, encoding: .utf8).prefix { $0 != "\n" }.utf8))
        #expect((first as? [String: Any])?["assistant"] as? Bool == true, "\(name)'s build was recorded as the person's assistant")
        let replay = try Replay.play("assistant-build", kind: kind)
        let tools = replay.items.filter { $0.kind == "tool" }
        // A step ran as the lent tool itself, as a shell command that starts with it (pi), or as a call in Amp's code
        // tool; a command that only mentions it does not count. An agent's own step may fail on the way (OMP reads a
        // file that is not there) without failing the build.
        for step in ["new", "check"] {
            let ran = tools.filter { $0.tool?.name == "something_\(step)" || $0.text.hasPrefix("something \(step) ") || $0.text.contains("await something_\(step)(") }
            #expect(!ran.isEmpty && ran.allSatisfy { $0.tool?.status == "done" }, "\(name)'s `something \(step)`: \(ran.map { $0.tool?.status ?? "-" })")
        }
        #expect(!tools.contains { $0.decision?.by == "person" } && replay.fold.requests.isEmpty, "\(name) asked the person")
        #expect(replay.fold.turns.map(\.state).allSatisfy { $0 == "done" } && !replay.fold.turns.isEmpty && replay.fold.agent.error == nil)
        #expect(replay.refusals.isEmpty, "\(name) refused something's tools: \(replay.refusals)")
    }
}
