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

@MainActor @Suite(.leavesNothing("something-command-")) struct CommandTests {
    @Test func theWordsAreRead() {
        let cases: [([String], Command)] = [
            ([], .start),
            (["open", "morning-review"], .open("morning-review")),
            (["open", "/Users/example/board/index.html"], .open("/Users/example/board/index.html")),
            (["new", "garden"], .new("garden", folder: false, from: nil)),
            (["new", "garden", "--folder"], .new("garden", folder: true, from: nil)),
            (["new", "--folder", "garden"], .new("garden", folder: true, from: nil)),
            (["new", "board", "--from", "agents"], .new("board", folder: false, from: "agents")),
            (["new", "--from", "brief", "paper"], .new("paper", folder: false, from: "brief")),
            (["guide"], .guide(print: false)),
            (["guide", "--print"], .guide(print: true)),
            (["--version"], .version),
            (["--help"], .help), (["-h"], .help), (["help"], .help),
            (["check", "board"], .check(Check(space: "board"))),
            (["check", "--json", "board", "--refuse", "send", "--refuse", "launch:codex", "--state", "state.json", "--journal"],
             .check(Check(space: "board", json: true, journal: true, refuse: ["send", "launch:codex"], state: "state.json"))),
            (["hook", "permission", "--spool", "/Users/example/spool"], .hook(["hook", "permission", "--spool", "/Users/example/spool"])),
            (["try", "claude", "--record", "out.jsonl"], .trial(["try", "claude", "--record", "out.jsonl"])),
            (["mcp"], .mcp),
        ]
        for (words, command) in cases { #expect(Command.parse(words) == command, "\(words)") }
    }

    @Test func wrongUsesAreNamed() {
        let wrong: [[String]] = [
            ["open"], ["open", "a", "b"], ["open", "--folder"],
            ["new"], ["new", "a", "b"], ["new", "--folder"], ["new", "a", "--folder", "--folder"], ["new", "-x"],
            ["new", "a", "--from"], ["new", "a", "--from", "--folder"], ["new", "a", "--from", "agents", "--folder"], ["new", "--from", "agents"],
            ["guide", "--json"], ["--version", "now"], ["hook"], ["hook", "other"], ["start"], ["morning-review"],
            ["check"], ["check", "a", "b"], ["check", "a", "--refuse"], ["check", "a", "--state"],
            ["check", "a", "--refuse", "--json"], ["check", "a", "--fast"], ["mcp", "--stdio"],
        ]
        #expect(Command.parse(["morning-review"]) == .wrong(
            "something does not know \"morning-review\". Type something --help to see what it does."))
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
        let home = Home(prefix: "something-command-")
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
    /// since no app keeps the spool alive. It also refuses a missing export without starting the app.
    @Test func theBuiltProgramAnswersHookPermission() async throws {
        let home = Home(prefix: "something-command-")
        defer { home.remove() }
        let spool = home.root.appendingPathComponent("spool")
        try FileManager.default.createDirectory(at: spool, withIntermediateDirectories: true)
        let program = Bundle(for: FakeDoor.self).bundleURL.deletingLastPathComponent().appendingPathComponent("something")
        for wrong in [["hook", "permission"], ["hook", "permission", "--spool"], ["hook", "permission", "--spool", spool.path, "--bogus"]] {
            let ran = try await runBuilt(program, wrong, home: home)
            #expect(ran.status == 2 && ran.out.isEmpty && ran.err.contains("usage: something hook permission"), "\(wrong): \(ran)")
        }
        let ran = try await runBuilt(program, ["hook", "permission", "--spool", spool.path], home: home)
        let decision = hookDecision(ran.out)
        #expect(ran.status == 0 && decision.behavior == "deny" && decision.message?.contains("something is not running") == true, "\(ran)")
        // Under swift run, an export that is not there is said in the terminal, before any app starts.
        let gone = try await runBuilt(program, ["open", "/Users/example/nothing.something"], home: home, input: "")
        #expect(gone.status == 1 && gone.err.contains("There is no file at /Users/example/nothing.something"), "\(gone)")
    }

    /// The program swift test built serves the lent tools over MCP, as an agent starts it (`something mcp`): it runs
    /// its own commands, in the folders SOMETHING_HOME names when set, and answers one line per request. No check
    /// runs here: only one test runs a check as a program (plan A.4).
    @Test func theBuiltProgramServesTheLentTools() async throws {
        let home = Home(prefix: "something-command-")
        defer { home.remove() }
        let program = Bundle(for: FakeDoor.self).bundleURL.deletingLastPathComponent().appendingPathComponent("something")
        let requests: [[String: Any]] = [
            ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "invented"]]],
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
            ["jsonrpc": "2.0", "id": 2, "method": "tools/list"],
            ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "something_guide", "arguments": [:]]],
            ["jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": ["name": "something_new", "arguments": ["name": "board", "from": "agents"]]],
            ["jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": ["name": "something_new", "arguments": ["name": "board"]]],
            ["jsonrpc": "2.0", "id": 6, "method": "tools/call", "params": ["name": "something_new", "arguments": ["name": "../board"]]],
        ]
        let input = try requests.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }.joined(separator: "\n") + "\n"
        let ran = try await runBuilt(program, ["mcp"], home: home, input: input,
                                     environment: ["HOME": home.root.appendingPathComponent("elsewhere").path, "SOMETHING_HOME": home.root.path])
        #expect(ran.status == 0 && ran.err.isEmpty, "\(ran)")
        let answers = ran.out.split(separator: "\n").map { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] ?? [:] }
        #expect(answers.map { $0["id"] as? Int } == [1, 2, 3, 4, 5, 6], "one answer per request, none to the notification")
        func result(_ index: Int) -> (text: String, error: Bool?) {
            let result = answers[index]["result"] as? [String: Any]
            return (((result?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? "", result?["isError"] as? Bool)
        }
        guard answers.count == 6 else { return }
        #expect(((answers[1]["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.count == 3)
        #expect(result(2) == (try String(contentsOf: Home.share.appendingPathComponent("guide.md"), encoding: .utf8) + "\n", false))
        #expect(result(3).error == false && result(3).text.hasPrefix("Made \(home.places.spaces.path)/board.html"), "\(result(3))")
        #expect(Spaces(root: home.places.spaces).named("board") != nil, "in SOMETHING_HOME's folders, not HOME's")
        #expect(result(4).error == true && result(4).text.contains("already exists"), "\(result(4))")
        #expect(result(5).error == true && result(5).text.hasPrefix("Wrong arguments for something_new"), "\(result(5))")
        #expect(!FileManager.default.fileExists(atPath: home.root.appendingPathComponent("elsewhere").path))
    }

    /// SOMETHING_HOME names the person's folders only as an absolute path: an empty or a relative one would name a
    /// different folder for the app, its MCP server and a shell, so HOME stands instead.
    @Test func somethingHomeIsTakenOnlyAsAnAbsolutePath() {
        let home = "/Users/example"
        #expect(Places.person(["HOME": home, "SOMETHING_HOME": "/Users/example/trial"]).home.path == "/Users/example/trial")
        for ignored in ["", "trial", "./trial", "~/trial"] {
            #expect(Places.person(["HOME": home, "SOMETHING_HOME": ignored]).home.path == home, "\(ignored)")
        }
        #expect(Places.person(["HOME": home]).home.path == home)
    }

    /// The version is the bundle's; a bundle without one, as under `swift run`, is "dev".
    @Test func theVersionIsTheBundles() throws {
        let home = Home(prefix: "something-command-")
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

    @Test func startAndOpenGoThroughTheDoor() throws {
        let home = Home(prefix: "something-command-")
        defer { home.remove() }
        let board = try home.space("board", page(nil, "<p>Invented.</p>"))
        let door = FakeDoor()
        #expect(Ran([], home, door).status == 0 && door.started == 1)
        #expect(Ran(["open", "board"], home, door).status == 0)
        #expect(door.delivered == [board.location])

        let missing = Ran(["open", "garden"], home, door)
        #expect(missing.status == 1 && missing.err.contains("something new garden"))
        // A page elsewhere is told where to go; one of the spaces folder, given by its path, opens.
        #expect(Ran(["open", board.location.path], home, door).status == 0 && door.delivered == [board.location, board.location])
        for path in ["/Users/example/Downloads/board.html", "/Users/example/My Board"] {
            let elsewhere = Ran(["open", path], home, door)
            #expect(elsewhere.status == 1 && elsewhere.err.hasPrefix("something opens spaces from ~/something/spaces. Copy it there, then run: something open "))
        }
        #expect(Ran(["open", "/Users/example/Downloads/board.html"], home, door).err.hasSuffix("something open board\n"))
        #expect(Ran(["open", "/Users/example/My Board"], home, door).err.hasSuffix("something open <name>\n"))
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
        let home = Home(prefix: "something-command-")
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

    @Test func newFromATemplateCopiesIt() throws {
        let home = Home(prefix: "something-command-")
        defer { home.remove() }
        let made = Ran(["new", "board", "--from", "agents"], home)
        #expect(made.status == 0 && made.out.contains("something open board"))
        let space = try #require(Spaces(root: home.places.spaces).named("board"))
        #expect(try Data(contentsOf: space.page) == Data(contentsOf: Home.share.appendingPathComponent("templates/agents.html")))
        let unknown = Ran(["new", "plot", "--from", "garden"], home)
        #expect(unknown.status == 1 && unknown.err.hasPrefix("There is no template garden. The templates are: agents, project, brief, logbook, stack, pet."))
        #expect(Command.usage(Home.share).contains("make a space from a template: agents, project, brief, logbook, stack, pet\n"), "the usage names only the templates there are")
        #expect(Ran(["new", "plot", "--from", "../template"], home).status == 1)
        #expect(Spaces(root: home.places.spaces).named("plot") == nil)
        let folder = Ran(["new", "plot", "--from", "agents", "--folder"], home)
        #expect(folder.status == 2 && folder.err.hasPrefix("A template is one file: leave out --folder"))
        #expect(!made.out.contains("placeholder"))
        // Project watch follows a folder this home does not have: the command says to write the real one.
        let project = Ran(["new", "watch", "--from", "project"], home)
        #expect(project.status == 0 && project.out.contains("It follows ~/code/your-project, a placeholder: write the project folder in its place, then run: something check watch"))
    }

    @Test func aNewSpaceIsUndoneWhenTheGrantsCannotBeRead() throws {
        let home = Home(prefix: "something-command-")
        defer { home.remove() }
        try FileManager.default.createDirectory(at: home.places.support, withIntermediateDirectories: true)
        try "not json".write(to: home.places.grants, atomically: true, encoding: .utf8)
        let ran = Ran(["new", "garden"], home)
        #expect(ran.status == 1 && ran.err.contains("cannot be read"))
        #expect(Spaces(root: home.places.spaces).named("garden") == nil)
    }

    @Test func theGuideIsGivenByItsPathOrPrinted() throws {
        let home = Home(prefix: "something-command-")
        defer { home.remove() }
        let path = Ran(["guide"], home)
        #expect(path.status == 0 && path.out.contains(Home.share.appendingPathComponent("guide.md").path))
        let skill = Home.share.appendingPathComponent("skill/SKILL.md")
        #expect(path.out.contains(skill.path) && FileManager.default.fileExists(atPath: skill.path), "\(path.out)")
        let printed = Ran(["guide", "--print"], home)
        #expect(printed.out == (try String(contentsOf: Home.share.appendingPathComponent("guide.md"), encoding: .utf8)) + "\n")
    }

    /// An invented Homebrew prefix: the guide's path goes through opt/, which survives upgrades, when it is there.
    @Test func theGuidesPathSurvivesUpgrades() throws {
        let home = Home(prefix: "something-command-")
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
