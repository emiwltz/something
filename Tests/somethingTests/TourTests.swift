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
        let (shell, _, _) = window(home, model)
        shell.show(tour)
        // What App's finished does: the blank page in the tour's place.
        tour.finished = { problem in
            ended = problem == nil
            shell.show(nil, endingTour: true)
        }
        tour.end()
        #expect(ended && Library.WindowFile.read(home.places)?.toured == true && Library.WindowFile.read(home.places)?.launcherOffered == nil)
        #expect(shell.touring == nil && shell.window.title == "New Space" && model.place == .blank && model.noAgent)
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

    /// A suggestion sends its whole sentence, from the blank page, with the conversation open, and leaves the draft as
    /// it was; once the turn ended, the space the agent made opens by itself and its rights sheet says the agent made
    /// it. A turn that made no space ends the build too. One made while the person is on another space is said ready,
    /// and has its dot until it is opened.
    @Test func theSuggestionsSendTheirSentences() async throws {
        #expect(BlankView.chips.map(\.0) == ["Who is waiting for me", "A morning brief of my agents", "A small game for my breaks"])
        let (home, model) = try assistants.assistant(prefix: "something-tour-")
        defer { home.remove() }
        model.engine.lookAgain()
        #expect(await wait(until: { model.kind == "claude" }))
        // What App does when a build ends, with the space the agent made written just before.
        let library = Library(places: home.places, ask: FakeAsk(), share: Home.share)
        var making: (name: String, title: String)?, open: String?, opened: [String?] = [], answers: [Int] = []
        model.ended = {
            // Never before the agent answered: a build ends with its turn, not with its launch.
            answers.append(model.rows.filter { $0 == .reply("Invented reply.") }.count)
            if let making { _ = try? home.space(making.name, page(#"{"contract": 1, "title": "\#(making.title)"}"#, "")) }
            library.relist()
            opened.append(model.appeared(library.entries, open: open))
        }
        let sentence = BlankView.chips[0].1
        #expect(sentence == "Make me a space that shows which of my agents are waiting for me, and lets me answer the ones I can.")
        making = ("waiting", "Who waits")
        model.draft = "Half written"
        model.send(sentence)
        #expect(model.building && model.drawer && model.draft == "Half written")
        #expect(await wait(until: { model.rows.contains(.mine(caption: "on the blank page", text: sentence)) }))
        #expect(await wait(until: { !model.building }))
        #expect(opened == ["waiting"] && model.made == ["waiting"] && model.ready == nil)

        // A question makes no space: the build ends with its answer all the same.
        making = nil
        model.send("What can you do?")
        #expect(model.building)
        #expect(await wait(until: { !model.building }))
        #expect(opened == ["waiting", nil] && model.ready == nil && model.light == .ready)

        // Made while the person was on another space: said ready, never opened.
        (making, open) = (("second", "Second"), "waiting")
        model.send("A second one.")
        #expect(await wait(until: { !model.building }))
        #expect(opened == ["waiting", nil, nil] && model.ready?.id == "second" && model.made.contains("second"))
        #expect(answers == [1, 2, 3])
        #expect(model.status == "“Second” is ready. Open")
        await assistants.finish(home, model)

        let question = RightsQuestion(space: "Second", description: "Invented.", rights: ["store"], scope: nil, missing: [], folder: nil, made: true)
        #expect(Ask.rights(question).alert.informativeText == "Your agent made this space.\n\nInvented.")
    }

    /// Under a Homebrew prefix, the tour offers the launcher once and makes it in the home's Applications: a bundle of
    /// its own, never shown in the Dock, never registered with LaunchServices.
    @Test func theLauncherIsMadeOnceUnderHomebrew() async throws {
        let home = Home(prefix: "something-tour-")
        defer { home.remove() }
        #expect(Launcher.prefix(of: URL(fileURLWithPath: "/opt/homebrew/Cellar/something/HEAD-0a1b2c3/something.app")) == "/opt/homebrew")
        #expect(Launcher.prefix(of: URL(fileURLWithPath: "/Users/example/code/something/.build/debug/something")) == nil)
        // The launcher's script quotes the path: a quote in it would break the script.
        #expect(Launcher.prefix(of: URL(fileURLWithPath: "/Users/example/it's/Cellar/something/0.2.0/something.app")) == nil)
        #expect(!Tour(places: home.places, app: URL(fileURLWithPath: "/Users/example/code/something/.build/debug")).offersLauncher)

        let brew = home.root.appendingPathComponent("brew/Cellar/something/0.2.0/something.app")
        let tour = Tour(places: home.places, app: brew)
        #expect(tour.offersLauncher && tour.addLauncher)
        var problem: String?
        tour.finished = { problem = $0 }
        tour.end()
        let launcher = Launcher.place(home.places)
        #expect(problem == nil)
        let info = try #require(try PropertyListSerialization.propertyList(
            from: Data(contentsOf: launcher.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any])
        #expect(info["CFBundleIdentifier"] as? String == "io.github.emiwltz.something.launcher" && info["LSUIElement"] as? Bool == true)
        // What Spotlight shows of an app: its name, its kind and its icon.
        #expect(info["CFBundleName"] as? String == "something" && info["CFBundlePackageType"] as? String == "APPL" && info["CFBundleIconFile"] as? String == "something")
        let script = try String(contentsOf: launcher.appendingPathComponent("Contents/MacOS/something"), encoding: .utf8)
        #expect(script.contains("exec /usr/bin/open '\(home.root.path)/brew/opt/something/something.app'"))
        #expect(FileManager.default.isExecutableFile(atPath: launcher.appendingPathComponent("Contents/MacOS/something").path))

        // Never offered twice, never made twice.
        #expect(!Tour(places: home.places, app: brew).offersLauncher)
        try "kept".write(to: launcher.appendingPathComponent("Contents/kept"), atomically: true, encoding: .utf8)
        try Launcher.make(prefix: home.root.appendingPathComponent("brew").path, places: home.places, icon: nil)
        #expect(FileManager.default.fileExists(atPath: launcher.appendingPathComponent("Contents/kept").path))

        // Nothing registered it with LaunchServices. (Spotlight's importer, mdimport, would: a test never runs it.)
        let known = try await offMain { try PackagingTests.registered() }
        #expect(!known.contains { $0.contains(home.root.path) || $0.contains(home.root.resolvingSymlinksInPath().path) })
    }

    /// Help › Welcome Tour while a space is open: the space closes on the next turn of the main queue, which must not
    /// put the blank page in the tour's place.
    @Test func theTourStaysWhenTheOpenSpaceCloses() async throws {
        let (home, model) = try assistants.assistant([], prefix: "something-tour-")
        defer { home.remove() }
        let (shell, library, _) = window(home, model)
        library.opened = { _ in shell.show(nil) }
        library.select("invented")
        // What App.showTour does.
        library.select(nil)
        let tour = Tour(places: home.places)
        shell.show(tour)
        try await Task.sleep(for: .milliseconds(100))
        #expect(shell.touring === tour && shell.window.title == "something" && shell.floating?.isHidden == true)
        #expect(shell.split.splitViewItems[0].isCollapsed)
        shell.show(nil, endingTour: true)
        #expect(shell.touring == nil && shell.window.title == "New Space" && shell.floating?.isHidden == false)
    }

    /// The window of `home`, never shown, with `model` as its assistant.
    func window(_ home: Home, _ model: AssistantModel) -> (Shell, Library, Info) {
        let library = Library(places: home.places, ask: FakeAsk(), share: Home.share), info = Info(places: home.places, ask: FakeAsk())
        return (Shell(library: library, info: info, assistant: model, autosave: false), library, info)
    }
}
