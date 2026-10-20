// The live trial of the assistant (plan S5): the app's own model, library and engine, with the REAL claude program
// talking to FakeMessagesAPI instead of a model. It runs only when asked, since it needs Claude Code on this Mac:
//
//   SOMETHING_TRIAL_CLAUDE=/opt/homebrew/bin/claude swift test --filter AssistantTrial
//
// Everything is in a throwaway HOME under $TMPDIR, deleted after: no login is there, so the made-up key "test-key" is
// the only credential Claude has, and ANTHROPIC_BASE_URL sends every request to the fake. The `something` the
// assistant runs is AssistantBuild's invented one, given as something's own program, so its folder comes first in
// the assistant's PATH as the app's does.
import Foundation
import SomethingCore
import Testing
@testable import SomethingAgents
@testable import something

let trialClaude = ProcessInfo.processInfo.environment["SOMETHING_TRIAL_CLAUDE"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }

@MainActor @Suite(.serialized, .enabled(if: trialClaude != nil, "The assistant's trial needs Claude Code: set SOMETHING_TRIAL_CLAUDE to its program's path."))
struct AssistantTrial {
    /// The person asks from the blank page; the fake model plays the standard build (A.2 #6); the new space appears
    /// and opens by itself; the drawer shows the tools; at most one permission window was asked for.
    @Test func theFirstSpaceIsBuiltFromTheBlankPage() async throws {
        let api = try FakeMessagesAPI()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("something-trial-\(UUID().uuidString)")
        defer {
            api.stop()
            try? FileManager.default.removeItem(at: root)
        }
        // The home by its real path, as ~/something/spaces is: $TMPDIR itself is behind a link.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let home = AssistantBuild.real(root).appendingPathComponent("home"), program = try #require(trialClaude)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        // Every launch removes ANTHROPIC_API_KEY (ClaudeDriver.credentials): the throwaway settings hand the made-up key
        // through Claude's own apiKeyHelper instead.
        let key = root.appendingPathComponent("key.sh")
        try "#!/bin/sh\necho test-key\n".write(to: key, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: key.path)
        try #"{"apiKeyHelper": "\#(key.path)"}"#.write(to: home.appendingPathComponent(".claude/settings.json"), atomically: true, encoding: .utf8)
        let tools = try AssistantBuild.tools(in: root)
        let engine = Engine(environment: ["HOME": home.path, "CLAUDE_CONFIG_DIR": home.appendingPathComponent(".claude").path,
                                          "PATH": "\((program as NSString).deletingLastPathComponent):/usr/bin:/bin", "TMPDIR": root.path,
                                          "SHELL": "/bin/sh", "ANTHROPIC_BASE_URL": api.url,
                                          "DISABLE_AUTOUPDATER": "1", "DISABLE_TELEMETRY": "1", "DISABLE_ERROR_REPORTING": "1",
                                          "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"])
        engine.programs.systemFolders = []
        engine.hookCommand = [tools + "/something", "hook", "permission"]
        let places = Places(home: home)
        engine.assistantFolder = places.spaces.path
        try Library.prepare(places)
        try AssistantModel.writeKnowledge(places, share: Home.share)
        let library = Library(places: places, ask: FakeAsk()), model = AssistantModel(engine: engine, places: places)
        defer { library.stop() }
        var opened: [String?] = []
        library.opened = { opened.append($0) }
        model.ended = {
            library.relist()
            if let new = model.appeared(library.entries, open: library.selection) { library.select(new) }
        }
        library.watch()
        engine.changed = { model.refresh() }
        engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))

        api.build = AssistantBuild.steps(places.spaces.path)
        model.draft = "Please run-build a board of my agents."
        model.send()
        var asked: [String] = []
        let built = await wait(120) {
            for request in engine.state.requests where !asked.contains(request.id) {
                asked.append(request.id)
                try? engine.answer(request.id, .once)
            }
            return model.light == .ready && model.rows.contains { if case .reply(let text) = $0 { text.contains("the board is ready") } else { false } }
        }
        #expect(built, "rows: \(model.rows); problem: \(model.problem ?? "none")")
        #expect(asked.count <= 1, "asked: \(asked)")
        print("AssistantTrial: the standard build asked \(asked.count) permission window(s).")
        #expect(await wait(5) { opened.contains("agents-board") }, "the new space opens by itself: \(opened)")
        #expect(library.selection == "agents-board")
        #expect(model.rows.first == .mine(caption: "on the blank page", text: "Please run-build a board of my agents."))
        #expect(model.rows.contains(.tool(symbol: "book", words: "Read guide", command: nil)))
        #expect(model.rows.filter { $0 == .tool(symbol: "pencil", words: "Edited agents-board.html", command: nil) }.count == 3)
        #expect(model.rows.contains(.tool(symbol: "terminal", words: "", command: "something check agents-board")))

        var stopped = false
        engine.stopAll(within: 8) { stopped = true }
        #expect(await wait(15) { stopped })
    }
}
