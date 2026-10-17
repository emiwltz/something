// The command: every word it knows, every wrong use, and the status each one exits with. LaunchServices is played
// by a door that records what it was asked, so no app starts.
import Foundation
import SomethingCore
import Testing
@testable import something

/// Records what the command asked of the app and answers as told.
final class FakeDoor: Door {
    var started = 0, delivered: [URL] = [], problem: String?
    func start() -> String? { started += 1; return problem }
    func deliver(_ space: URL) -> String? { delivered.append(space); return problem }
}

/// One run of the command in a throwaway home: its status and what it printed, on standard output and error.
@MainActor struct Ran {
    var status: Int32, out = "", err = ""
    init(_ words: [String], _ home: Home, _ door: FakeDoor = FakeDoor()) {
        var out = "", err = ""
        status = Command.parse(words).run(places: home.places, share: Home.share, door: door) { text, problem in
            if problem { err += text + "\n" } else { out += text + "\n" }
        }
        (self.out, self.err) = (out, err)
    }
}

@MainActor @Suite struct CommandTests {
    @Test func theWordsAreRead() {
        let cases: [([String], Command)] = [
            ([], .start),
            (["open", "morning-review"], .open("morning-review")),
            (["open", "/Users/example/board/index.html"], .open("/Users/example/board/index.html")),
            (["new", "garden"], .new("garden", folder: false)),
            (["new", "garden", "--folder"], .new("garden", folder: true)),
            (["new", "--folder", "garden"], .new("garden", folder: true)),
            (["guide"], .guide(print: false)),
            (["guide", "--print"], .guide(print: true)),
            (["--version"], .version),
            (["--help"], .help), (["-h"], .help), (["help"], .help),
            (["check", "board"], .check(Check(space: "board"))),
            (["check", "--json", "board", "--refuse", "send", "--refuse", "launch:codex", "--state", "state.json", "--journal"],
             .check(Check(space: "board", json: true, journal: true, refuse: ["send", "launch:codex"], state: "state.json"))),
            (["hook", "permission", "--spool", "/Users/example/spool"], .hook(["hook", "permission", "--spool", "/Users/example/spool"])),
            (["try", "claude", "--record", "out.jsonl"], .trial(["try", "claude", "--record", "out.jsonl"])),
        ]
        for (words, command) in cases { #expect(Command.parse(words) == command, "\(words)") }
    }

    @Test func wrongUsesAreNamed() {
        let wrong: [[String]] = [
            ["open"], ["open", "a", "b"], ["open", "--folder"],
            ["new"], ["new", "a", "b"], ["new", "--folder"], ["new", "a", "--folder", "--folder"], ["new", "-x"],
            ["guide", "--json"], ["--version", "now"], ["hook"], ["hook", "other"], ["start"], ["morning-review"],
            ["check"], ["check", "a", "b"], ["check", "a", "--refuse"], ["check", "a", "--state"],
            ["check", "a", "--refuse", "--json"], ["check", "a", "--fast"],
        ]
        #expect(Command.parse(["morning-review"]) == .wrong(
            "something does not know \"morning-review\": to open the space morning-review, type something open morning-review, and type something --help to see what it does."))
        for words in wrong {
            guard case .wrong(let sentence) = Command.parse(words) else {
                Issue.record("\(words) was not refused")
                continue
            }
            // One sentence that says what to type next.
            let next = sentence.lowercased().contains("type something ") || sentence.contains("for example: something ")
            #expect(next && !sentence.contains("\n"), "\(words): \(sentence)")
        }
    }

    @Test func theAppIsTheAppOnlyWhenLaunchServicesOrLaunchdStartsIt() {
        #expect(Command.isApp(["--app"], parent: 4_242))
        #expect(Command.isApp([], parent: 1))
        #expect(!Command.isApp([], parent: 4_242))
        #expect(!Command.isApp(["open", "--app"], parent: 4_242))
        #expect(!Command.isApp(["hook", "permission"], parent: 1))
    }

    @Test func eachCommandExitsWithItsStatus() throws {
        let home = Home()
        defer { home.remove() }
        try home.space("board", page(nil, "<p>Invented.</p>"))
        let version = Ran(["--version"], home)
        #expect(version.status == 0 && version.out.hasPrefix("something ") && version.err.isEmpty)
        #expect(Ran(["--help"], home).out.hasPrefix("Usage:"))
        let wrong = Ran(["open"], home)
        #expect(wrong.status == 2 && wrong.out.isEmpty && wrong.err.contains("Usage:"))
        // check runs a window of its own, through the program itself: CheckTests.swift.
        // Routed to SomethingAgents: wrong words only, so that no agent is ever launched (NoRealAgentTests).
        #expect(Ran(["hook", "permission"], home).status == 2)
        #expect(Ran(["try", "nope"], home).status == 2)
        #expect(Ran(["try", "claude", "--bogus"], home).status == 2)
    }

    /// The program swift test built routes `hook permission`, as Claude's plan-B hook runs it (Engine.hookCommand):
    /// wrong words are a usage error; right ones read the request and print a decision, here a deny that says why,
    /// since no app keeps the spool alive.
    @Test func theBuiltProgramAnswersHookPermission() throws {
        let home = Home()
        defer { home.remove() }
        let spool = home.root.appendingPathComponent("spool")
        try FileManager.default.createDirectory(at: spool, withIntermediateDirectories: true)
        func hook(_ words: [String]) throws -> (status: Int32, out: String, err: String) {
            let process = Process(), input = Pipe(), out = Pipe(), err = Pipe()
            process.executableURL = Bundle(for: FakeDoor.self).bundleURL.deletingLastPathComponent().appendingPathComponent("something")
            process.arguments = words
            process.environment = ["HOME": home.root.path, "PATH": "/usr/bin:/bin"]
            (process.standardInput, process.standardOutput, process.standardError) = (input, out, err)
            try process.run()
            input.fileHandleForWriting.write(Data(#"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"}}"#.utf8))
            try input.fileHandleForWriting.close()
            let deadline = DispatchWorkItem { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: deadline)
            let printed = out.fileHandleForReading.readDataToEndOfFile(), errors = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            deadline.cancel()
            return (process.terminationStatus, String(decoding: printed, as: UTF8.self), String(decoding: errors, as: UTF8.self))
        }
        for wrong in [["hook", "permission"], ["hook", "permission", "--spool"], ["hook", "permission", "--spool", spool.path, "--bogus"]] {
            let ran = try hook(wrong)
            #expect(ran.status == 2 && ran.out.isEmpty && ran.err.contains("usage: something hook permission"), "\(wrong): \(ran)")
        }
        let ran = try hook(["hook", "permission", "--spool", spool.path])
        #expect(ran.status == 0, "\(ran)")
        let printed = try JSONSerialization.jsonObject(with: Data(ran.out.utf8)) as? [String: Any]
        let decision = (printed?["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        #expect(decision?["behavior"] as? String == "deny" && (decision?["message"] as? String)?.contains("something is not running") == true, "\(ran.out)")
    }

    /// The version is the bundle's; a bundle without one, as under `swift run`, is "dev".
    @Test func theVersionIsTheBundles() throws {
        let home = Home()
        defer { home.remove() }
        let bare = home.root.appendingPathComponent("bare.app")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        #expect(Resources.version(of: try #require(Bundle(path: bare.path))) == "dev")
        let packaged = home.root.appendingPathComponent("example.app")
        try FileManager.default.createDirectory(at: packaged.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": "9.8.7"], format: .xml, options: 0)
            .write(to: packaged.appendingPathComponent("Contents/Info.plist"))
        #expect(Resources.version(of: try #require(Bundle(path: packaged.path))) == "9.8.7")
    }

    /// The app passes on the terminal's settings, not the markers of the agent or the terminal it was started in.
    @Test func theAppGetsTheTerminalsEnvironmentWithoutItsMarkers() {
        let terminal = ["PATH": "/Users/example/bin:/usr/bin", "HOME": "/Users/example", "CODEX_HOME": "/Users/example/.codex-work",
                        "CLAUDECODE": "1", "CLAUDE_CODE_ENTRYPOINT": "cli", "TMUX_PANE": "%3", "TERM_SESSION_ID": "w0t0p0:EXAMPLE"]
        #expect(LaunchServices.inherited(terminal) == ["PATH": "/Users/example/bin:/usr/bin", "HOME": "/Users/example",
                                                       "CODEX_HOME": "/Users/example/.codex-work"])
    }

    /// A space handed by its path is the one already open by its name: the window is fronted, not reopened.
    @Test func aSpaceIsTheSameHoweverItsPathIsWritten() throws {
        let home = Home()
        defer { home.remove() }
        try FileManager.default.createDirectory(at: home.places.spaces, withIntermediateDirectories: true)
        let spaces = Spaces(root: home.places.spaces)
        let board = try spaces.new("board", from: Home.share.appendingPathComponent("template.html"), folder: true)
        let link = home.root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: home.places.spaces)
        for written in [board.location.path + "/", link.appendingPathComponent("board").path] {
            let byPath = try #require(spaces.locate(written), "\(written)")
            #expect(App.same(board, byPath), "\(written)")
        }
        let other = try home.space("garden", page(nil, "<p>Invented.</p>"))
        #expect(!App.same(board, other))
    }

    @Test func startAndOpenGoThroughTheDoor() throws {
        let home = Home()
        defer { home.remove() }
        let board = try home.space("board", page(nil, "<p>Invented.</p>"))
        let door = FakeDoor()
        #expect(Ran([], home, door).status == 0 && door.started == 1)
        #expect(Ran(["open", "board"], home, door).status == 0)
        #expect(Ran(["open", board.location.path], home, door).status == 0)
        #expect(door.delivered == [board.location, board.location.standardizedFileURL])

        let missing = Ran(["open", "garden"], home, door)
        #expect(missing.status == 1 && missing.err.contains("something new garden"))
        let nowhere = Ran(["open", "/Users/example/nowhere.html"], home, door)
        #expect(nowhere.status == 1 && nowhere.err.contains("There is no space at /Users/example/nowhere.html"))
        #expect(door.delivered.count == 2)

        // An export goes to the app, which imports it; a missing one is said here.
        let export = home.root.appendingPathComponent("garden.something")
        try Data("{}".utf8).write(to: export)
        #expect(Ran(["open", export.path], home, door).status == 0 && door.delivered.last == export.standardizedFileURL)
        let none = Ran(["open", home.root.appendingPathComponent("nothing.something").path], home, door)
        #expect(none.status == 1 && none.err.contains("give the path of an export") && door.delivered.count == 3)

        door.problem = "something could not be started: invented. Try again."
        let refused = Ran([], home, door)
        #expect(refused.status == 1 && refused.err == "something could not be started: invented. Try again.\n")
    }

    @Test func newMakesASpaceThatInheritsNoAnswers() throws {
        let home = Home()
        defer { home.remove() }
        // Answers left by a deleted space of the same name.
        var file = AppFile()
        var declaration = Declaration(name: "garden")
        declaration.rights = ["state"]
        file.spaces["garden"] = Grant(declared: Asked(declaration), at: "2026-10-17T09:00:00Z")
        try FileManager.default.createDirectory(at: home.places.support, withIntermediateDirectories: true)
        try file.write(home.places.grants)

        let made = Ran(["new", "garden"], home)
        #expect(made.status == 0 && made.out.contains("something open garden"))
        let space = try #require(Spaces(root: home.places.spaces).named("garden"))
        #expect(try Data(contentsOf: space.page) == Data(contentsOf: Home.share.appendingPathComponent("template.html")))
        #expect(try AppFile.read(home.places.grants).spaces["garden"] == nil)

        let taken = Ran(["new", "garden", "--folder"], home)
        #expect(taken.status == 1 && taken.err.contains("already exists"))
        #expect(Ran(["new", "Garden"], home).status == 1)
        #expect(Ran(["new", "plot", "--folder"], home).status == 0)
        #expect(Spaces(root: home.places.spaces).named("plot")?.form == .folder)
    }

    @Test func aNewSpaceIsUndoneWhenTheGrantsCannotBeRead() throws {
        let home = Home()
        defer { home.remove() }
        try FileManager.default.createDirectory(at: home.places.support, withIntermediateDirectories: true)
        try "not json".write(to: home.places.grants, atomically: true, encoding: .utf8)
        let ran = Ran(["new", "garden"], home)
        #expect(ran.status == 1 && ran.err.contains("cannot be read"))
        #expect(Spaces(root: home.places.spaces).named("garden") == nil)
    }

    @Test func theGuideIsGivenByItsPathOrPrinted() throws {
        let home = Home()
        defer { home.remove() }
        let path = Ran(["guide"], home)
        #expect(path.status == 0 && path.out.contains(Home.share.appendingPathComponent("guide.md").path))
        let printed = Ran(["guide", "--print"], home)
        #expect(printed.out == (try String(contentsOf: Home.share.appendingPathComponent("guide.md"), encoding: .utf8)) + "\n")
    }

    /// An invented Homebrew prefix: the guide's path goes through opt/, which survives upgrades, when it is there.
    @Test func theGuidesPathSurvivesUpgrades() throws {
        let home = Home()
        defer { home.remove() }
        let guide = home.root.appendingPathComponent("Cellar/something/1.2.3/something.app/Contents/Resources/share/guide.md")
        #expect(Command.stable(guide) == guide)
        try FileManager.default.createDirectory(at: home.root.appendingPathComponent("opt"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: guide.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "invented".write(to: guide, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: home.root.appendingPathComponent("opt/something"),
                                                   withDestinationURL: home.root.appendingPathComponent("Cellar/something/1.2.3"))
        #expect(Command.stable(guide).path == home.root.appendingPathComponent("opt/something/something.app/Contents/Resources/share/guide.md").path)
        let elsewhere = URL(fileURLWithPath: "/Users/example/something/share/guide.md")
        #expect(Command.stable(elsewhere) == elsewhere)
    }
}
