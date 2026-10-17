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
struct Ran {
    var status: Int32, out = "", err = ""
    init(_ words: [String], _ home: Home, _ door: FakeDoor = FakeDoor()) {
        var out = "", err = ""
        status = Command.parse(words).run(places: home.places, share: Home.share, door: door) { text, problem in
            if problem { err += text + "\n" } else { out += text + "\n" }
        }
        (self.out, self.err) = (out, err)
    }
}

@Suite struct CommandTests {
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
        for words in wrong {
            guard case .wrong(let sentence) = Command.parse(words) else {
                Issue.record("\(words) was not refused")
                continue
            }
            // One sentence that says what to type next.
            #expect(sentence.contains("something") && !sentence.contains("\n"), "\(words): \(sentence)")
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
        #expect(version.status == 0 && version.out == "something \(Resources.version)\n" && version.err.isEmpty)
        #expect(Ran(["--help"], home).out.hasPrefix("Usage:"))
        let wrong = Ran(["open"], home)
        #expect(wrong.status == 2 && wrong.out.isEmpty && wrong.err.contains("Usage:"))
        let check = Ran(["check", "board"], home)
        #expect(check.status == 1 && check.err.contains("not in this version yet"))
        // Routed to SomethingAgents, which has no hook and no trial yet: their own statuses come back.
        #expect(Ran(["hook", "permission"], home).status == 2)
        #expect(Ran(["try", "claude"], home).status == 2)
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
