// The tour, the blank page and the launcher: the tour's screens with and without a builder, its end on the blank page
// with no agent started, the suggestions' whole sentences, the space the assistant made opened or said ready, the
// rights sheet's first line, and the launcher, made in the test home's Applications only under a Homebrew prefix,
// never twice, never registered.
import AppKit
import Foundation
import SomethingCore
import Testing
@testable import SomethingAgents
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-tour-")) struct TourTests {
    let assistants = AssistantTests()

    /// With no builder, the second screen is "No coding agent yet"; Continue Without an Agent ends the tour on the blank
    /// page, where the notice takes the input's place, and no agent was started.
    @Test func withoutABuilderTheTourEndsOnTheBlankPage() async throws {
        let (home, model) = try assistants.assistant([], prefix: "something-tour-")
        defer { home.remove() }
        let tour = Tour(places: home.places)
        var ended = false
        tour.finished = { ended = $0 == nil }
        #expect(tour.screen(model) == .welcome && !tour.offersLauncher)
        tour.step = 1
        #expect(tour.screen(model) == .looking, "nothing is said before the programs were looked for")
        model.engine.lookAgain()
        #expect(await wait(until: { model.noAgent }))
        #expect(tour.screen(model) == .none)
        tour.end()
        #expect(ended && Library.WindowFile.read(home.places)?.toured == true && Library.WindowFile.read(home.places)?.launcherOffered == nil)
        let (shell, _, _) = window(home, model)
        shell.show(nil)
        #expect(shell.window.title == "New Space" && model.place == .blank && model.noAgent)
        #expect(model.engine.state.agents.isEmpty && model.engine.assistants.isEmpty)
    }

    /// With builders, the second screen lists them; choosing one and continuing starts nothing.
    @Test func theTourStartsNoAgent() async throws {
        let (home, model) = try assistants.assistant(["claude", "pi"], prefix: "something-tour-")
        defer { home.remove() }
        let tour = Tour(places: home.places)
        tour.step = 1
        model.engine.lookAgain()
        #expect(await wait(until: { model.entries.count == 2 }))
        #expect(tour.screen(model) == .builders && model.kind == "claude")
        model.choose("pi")
        #expect(model.kind == "pi" && model.firstLines[0].hasPrefix("pi works in ~/something/spaces. pi never asks"))
        tour.end()
        try await Task.sleep(for: .milliseconds(500))
        #expect(model.engine.state.agents.isEmpty && model.engine.assistants.isEmpty && model.id == nil)
        #expect(Library.WindowFile.read(home.places)?.assistant == "pi")
    }

    /// A suggestion sends its whole sentence, from the blank page, with the conversation open; the space that then
    /// appears opens by itself and its rights sheet says the agent made it. One that appears while the person is on
    /// another space is said ready, and has its dot until it is opened.
    @Test func theSuggestionsSendTheirSentences() async throws {
        #expect(BlankView.chips.map(\.0) == ["Who is waiting for me", "A morning brief of my agents", "A small game for my breaks"])
        let (home, model) = try assistants.assistant(prefix: "something-tour-")
        defer { home.remove() }
        model.engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        let sentence = BlankView.chips[0].1
        #expect(sentence == "Make me a space that shows which of my agents are waiting for me, and lets me answer the ones I can.")
        model.draft = sentence
        model.send()
        #expect(model.building && model.drawer)
        #expect(await wait(until: { model.rows.contains(.mine(caption: "on the blank page", text: sentence)) }))
        try home.space("waiting", page(#"{"contract": 1, "title": "Who waits"}"#, ""))
        let library = Library(places: home.places, ask: FakeAsk())
        library.relist()
        #expect(model.appeared(library.entries, open: nil) == "waiting" && !model.building && model.made == ["waiting"])

        model.draft = "A second one."
        model.send()
        try home.space("second", page(#"{"contract": 1, "title": "Second"}"#, ""))
        library.relist()
        #expect(model.appeared(library.entries, open: "waiting") == nil)
        #expect(await wait(until: { model.rows.filter { $0 == .reply("Invented reply.") }.count == 2 && model.light == .ready }))
        #expect(model.ready?.id == "second" && model.status == "“Second” is ready. Open" && model.made.contains("second"))
        await assistants.finish(home, model)

        let question = RightsQuestion(space: "Second", description: "Invented.", rights: ["store"], scope: nil, missing: [], folder: nil, made: true)
        #expect(Ask.rights(question).alert.informativeText == "Your agent made this space.\n\nInvented.")
    }

    /// Under a Homebrew prefix, the tour offers the launcher once and makes it in the home's Applications: a bundle of
    /// its own, never shown in the Dock, read by Spotlight's importer, never registered with LaunchServices.
    @Test func theLauncherIsMadeOnceUnderHomebrew() async throws {
        let home = Home(prefix: "something-tour-")
        defer { home.remove() }
        #expect(Launcher.prefix(of: URL(fileURLWithPath: "/opt/homebrew/Cellar/something/HEAD-0a1b2c3/something.app")) == "/opt/homebrew")
        #expect(Launcher.prefix(of: URL(fileURLWithPath: "/Users/example/code/something/.build/debug/something")) == nil)
        #expect(!Tour(places: home.places, app: URL(fileURLWithPath: "/Users/example/code/something/.build/debug")).offersLauncher)

        let brew = home.root.appendingPathComponent("brew/Cellar/something/0.2.0/something.app")
        let tour = Tour(places: home.places, app: brew)
        #expect(tour.offersLauncher && tour.addLauncher)
        var problem: String?
        tour.finished = { problem = $0 }
        tour.end()
        let launcher = Launcher.place(home.places)
        defer { _ = try? PackagingTests.runBlocking(PackagingTests.lsregister, ["-u", launcher.path], quiet: true) }
        #expect(problem == nil)
        let info = try #require(try PropertyListSerialization.propertyList(
            from: Data(contentsOf: launcher.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any])
        #expect(info["CFBundleIdentifier"] as? String == "io.github.emiwltz.something.launcher" && info["LSUIElement"] as? Bool == true)
        let script = try String(contentsOf: launcher.appendingPathComponent("Contents/MacOS/something"), encoding: .utf8)
        #expect(script.contains("exec /usr/bin/open '\(home.root.path)/brew/opt/something/something.app'"))
        #expect(FileManager.default.isExecutableFile(atPath: launcher.appendingPathComponent("Contents/MacOS/something").path))

        // Never offered twice, never made twice.
        #expect(!Tour(places: home.places, app: brew).offersLauncher)
        try "kept".write(to: launcher.appendingPathComponent("Contents/kept"), atomically: true, encoding: .utf8)
        try Launcher.make(prefix: home.root.appendingPathComponent("brew").path, places: home.places, icon: nil)
        #expect(FileManager.default.fileExists(atPath: launcher.appendingPathComponent("Contents/kept").path))

        // Spotlight's importer reads it (-t: test mode, nothing is stored).
        let imported = try await offMain { try PackagingTests.runBlocking("/usr/bin/mdimport", ["-t", "-d1", launcher.path], quiet: true) }
        #expect(imported.status == 0)
        _ = try PackagingTests.runBlocking(PackagingTests.lsregister, ["-u", launcher.path], quiet: true)
        let known = try await offMain { try PackagingTests.registered() }
        #expect(!known.contains { $0.contains(home.root.path) || $0.contains(home.root.resolvingSymlinksInPath().path) })
    }

    /// The window of `home`, never shown, with `model` as its assistant.
    func window(_ home: Home, _ model: AssistantModel) -> (Shell, Library, Info) {
        let library = Library(places: home.places, ask: FakeAsk()), info = Info(places: home.places, ask: FakeAsk())
        return (Shell(library: library, info: info, assistant: model, autosave: false), library, info)
    }
}
