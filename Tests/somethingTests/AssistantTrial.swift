// The live trial of the assistant: the app's own model, library and engine, with the REAL claude program
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
    /// A throwaway home whose Claude Code talks to `api`, the app's model and library on it, the assistant found.
    struct Trial {
        let root: URL, engine: Engine, places: Places, library: Library, model: AssistantModel, ask = FakeAsk()
        private let settings: URL, helper: String

        /// Hands Claude Code the made-up key, as signing in once in Terminal would.
        func signIn() throws { try helper.write(to: settings, atomically: true, encoding: .utf8) }

        /// `signedIn` false: Claude Code has no key until `signIn()`, as on a Mac where it was never signed in.
        init(_ api: FakeMessagesAPI, signedIn: Bool = true) async throws {
            root = FileManager.default.scratch("something-trial-")
            // The home by its real path, as ~/something/spaces is: $TMPDIR itself is behind a link.
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            do {
                let home = AssistantBuild.real(root).appendingPathComponent("home"), program = try #require(trialClaude)
                try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
                // Every launch removes ANTHROPIC_API_KEY (ClaudeDriver.credentials): the throwaway settings hand the
                // made-up key through Claude's own apiKeyHelper instead.
                let key = root.appendingPathComponent("key.sh")
                try "#!/bin/sh\necho test-key\n".write(to: key, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: key.path)
                settings = home.appendingPathComponent(".claude/settings.json")
                helper = #"{"apiKeyHelper": "\#(key.path)"}"#
                if signedIn { try helper.write(to: settings, atomically: true, encoding: .utf8) }
                let tools = try AssistantBuild.tools(in: root)
                engine = Engine(environment: ["HOME": home.path, "CLAUDE_CONFIG_DIR": home.appendingPathComponent(".claude").path,
                                              "PATH": "\((program as NSString).deletingLastPathComponent):/usr/bin:/bin", "TMPDIR": root.path,
                                              "SHELL": "/bin/sh", "ANTHROPIC_BASE_URL": api.url,
                                              "DISABLE_AUTOUPDATER": "1", "DISABLE_TELEMETRY": "1", "DISABLE_ERROR_REPORTING": "1",
                                              "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"], registry: .app)
                engine.programs.systemFolders = []
                engine.hookCommand = [tools + "/something", "hook", "permission"]
                places = Places(home: home)
                engine.spools = places.spools.path
                engine.assistantFolder = places.spaces.path
                try Library.prepare(places)
                try AssistantModel.writeKnowledge(places, share: Home.share)
            } catch {
                // Nothing of the trial stays in $TMPDIR when it cannot start.
                try? FileManager.default.removeItem(at: root)
                throw error
            }
            library = Library(places: places, ask: ask, share: Home.share)
            model = AssistantModel(engine: engine, places: places)
            // This process is the test runner, never something's program: nothing is lent unless a case places one.
            model.program = nil
            let (engine, model) = (engine, model)
            engine.changed = { model.refresh() }
            engine.lookAgain()
            #expect(await wait(until: { model.kind == "claude" }))
        }

        /// Runs `body`, then stops every agent and removes the home, whether `body` threw or not.
        func run(_ body: () async throws -> Void) async throws {
            do { try await body() } catch {
                await end()
                throw error
            }
            await end()
        }

        private func end() async {
            library.stop()
            var stopped = false
            engine.stopAll(within: 8) { stopped = true }
            #expect(await wait(15) { stopped })
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// The person asks from the blank page; the fake model plays the standard build (A.2 #6); the new space appears
    /// and opens by itself; the drawer shows the tools; at most one permission window was asked for.
    @Test func theFirstSpaceIsBuiltFromTheBlankPage() async throws {
        let api = try FakeMessagesAPI()
        defer { api.stop() }
        let trial = try await Trial(api)
        try await trial.run {
            let (engine, places, library, model) = (trial.engine, trial.places, trial.library, trial.model)
            var opened: [String?] = []
            library.opened = { opened.append($0) }
            model.ended = {
                library.relist()
                if let new = model.appeared(library.entries, open: library.selection) { library.select(new) }
            }
            library.watch()
            // The tools are lent as the app lends them, by this clone's real program (AssistantBuild.placeProgram).
            let program = try AssistantBuild.placeProgram()
            trial.model.program = program
            defer { AssistantBuild.removeProgram(program) }

            api.build = AssistantBuild.lentSteps(places.spaces.path)
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
            #expect(model.rows.filter { $0 == .tool(symbol: "pencil", words: "Edited agents-board.html", command: nil) }.count == 4, "a write, then three edits")
            #expect(model.rows.contains(.tool(symbol: "terminal", words: "", command: "something check agents-board")))
        }
    }

    /// Plan S11: a Claude Code never signed in fails at the first message, and the drawer's red row says what it said;
    /// signed in with a key the model's server refuses (401), it fails at once too, where Claude Code alone retries
    /// for about four minutes; a busy model server (529) is said in the status line at each retry (S12), until
    /// Claude Code gives up and the red row says so; once the server is free, Try Again gets an answer; after 30
    /// idle minutes the agent is stopped, the drawer says so, and the next message starts a new one.
    @Test func signedOutThenRefusedThenTryAgainThenTheIdleStop() async throws {
        let api = try FakeMessagesAPI()
        defer { api.stop() }
        let trial = try await Trial(api, signedIn: false)
        try await trial.run {
            let model = trial.model
            model.draft = "Make the counters bigger."
            model.send()
            #expect(await wait(60) { model.problem != nil }, "rows: \(model.rows)")
            #expect(model.light == .error && model.drawer && model.signedOut, "the same sign-in row as a refused key")
            #expect(model.problem?.contains("/login") == true, "the red row says what Claude Code said: \(model.problem ?? "nothing")")

            try trial.signIn()
            api.refusing = true
            let asked = Date()
            model.tryAgain()
            let refused = "The model's server refused Claude Code's sign-in (error 401)."
            #expect(await wait(60) { model.problem == refused }, "problem: \(model.problem ?? "none"); rows: \(model.rows)")
            #expect(Date().timeIntervalSince(asked) < 30, "the refusal shows at the first retry")
            #expect(model.light == .error && model.status == nil && model.signedOut)
            print("AssistantTrial: a refused key showed after \(Int(Date().timeIntervalSince(asked))) s.")

            // S12: a busy model server (529) is retried by Claude Code, and the status line says each retry.
            (api.refusing, api.overloading) = (false, 3)
            let busy = Date()
            model.tryAgain()
            #expect(await wait(30) { model.status?.hasPrefix("Claude Code can't reach its model (attempt ") == true }, "status: \(model.status ?? "none")")
            #expect(Date().timeIntervalSince(busy) < 10, "the status line changes within a few seconds")
            print("AssistantTrial: \(model.status ?? "") showed after \(Int(Date().timeIntervalSince(busy))) s.")
            // Claude Code gives up after three 529s in a row (measured): the red row says what it said.
            #expect(await wait(60) { model.problem != nil }, "status: \(model.status ?? "none")")
            #expect(model.light == .error && model.status == nil && !model.signedOut)
            #expect(model.problem?.contains("529") == true, "problem: \(model.problem ?? "none")")

            model.tryAgain()
            let answered = { model.light == .ready && model.rows.contains { if case .reply(let text) = $0 { text.hasPrefix("Invented reply") } else { false } } }
            #expect(await wait(90, until: answered), "rows: \(model.rows); problem: \(model.problem ?? "none")")
            #expect(model.problem == nil && model.status == nil)
            let first = try #require(model.id)

            model.clock = { Date().addingTimeInterval(AssistantModel.idleLimit + 60) }
            model.checkIdle()
            #expect(await wait(15) { trial.engine.state.agents.first { $0.id == first }?.alive == false })
            #expect(model.light == .off && model.firstLines.last == "Claude Code was stopped to save memory. Your next message starts it again.")
            model.clock = Date.init
            model.draft = "And the clock too."
            model.send()
            #expect(await wait(90) { model.id != nil && model.id != first && model.light == .ready }, "rows: \(model.rows)")
        }
    }

    /// Plan S11: Use Template makes a space and opens it; its rights are asked once, as a space the person chose; the
    /// drawer offers to make it theirs; the agent edits it and the open space reloads with the edit; Info shows the
    /// rights as answered. Then Quit asks, says the assistant is running, and stops it.
    @Test func aTemplateIsMadeYoursThenQuitStopsTheAssistant() async throws {
        let api = try FakeMessagesAPI()
        defer { api.stop() }
        let trial = try await Trial(api)
        try await trial.run {
            let (engine, places, library, model, ask) = (trial.engine, trial.places, trial.library, trial.model, trial.ask)
            library.used = { model.fromTemplate = $0 }
            let template = try #require(Template.all(Home.share).first { $0.id == "pet" && !$0.follows })
            library.use(template)
            let space = try #require(Spaces(root: places.spaces).named("pet"))
            let window = try SpaceView(space: space, places: places, engine: engine, ask: ask, share: Home.share,
                                       rules: try await Lockdown.ruleList(), launches: Launches())
            defer { window.close() }
            window.open()
            #expect(ask.questions.map(\.rights) == [template.rights] && ask.questions.first?.made == false)
            #expect(await wait(until: { !window.web.isLoading && window.frame != nil }))
            model.place = AssistantModel.place(window)
            #expect(model.placeholder == "Ask Claude Code to make it yours: colors, sections, anything.")

            let page = space.location.path
            api.build = [("Read", ["file_path": page]),
                         ("Edit", ["file_path": page, "old_string": "<title>Pebble</title>", "new_string": "<title>Invented Pebble</title>"])]
            model.draft = "Please run-build: make it warmer."
            model.send()
            #expect(model.fromTemplate == nil)
            let done = await wait(120) {
                for request in engine.state.requests { try? engine.answer(request.id, .once) }
                return model.light == .ready && model.rows.contains { if case .reply(let text) = $0 { text.contains("the board is ready") } else { false } }
            }
            #expect(done, "rows: \(model.rows); problem: \(model.problem ?? "none")")
            var reloaded = false
            for _ in 0..<300 where !reloaded {
                reloaded = try await run(window, "return document.title") as? String == "Invented Pebble"
                if !reloaded { await wait(0.05) }
            }
            #expect(reloaded, "the open space shows the agent's edit")
            #expect(ask.questions.count == 1, "the edit asks nothing again")
            let info = Info(places: places, ask: ask)
            info.show(space)
            #expect(info.rights.map(\.right) == template.rights && info.rights.allSatisfy { $0.standing == .allowed })
            #expect(info.problem == nil)

            let assistant = try #require(model.id)
            var confirmed: (count: Int, assistant: Bool)?, replied: Bool?
            App.quit(engine, confirm: { count, isAssistant, answer in
                confirmed = (count, isAssistant)
                answer(true)
            }, reply: { replied = $0 })
            #expect(confirmed?.count == 1 && confirmed?.assistant == true)
            #expect(await wait(15) { replied != nil })
            #expect(replied == true && engine.state.agents.first { $0.id == assistant }?.alive == false)
        }
    }
}
