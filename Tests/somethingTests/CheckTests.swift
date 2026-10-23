// `something check`: one invented space per check code gives exactly that code, and a clean space none;
// --json has every key of share/contract/check-example.json; --refuse, --state, --journal and the three exit statuses.
// Every check runs in this process, in a throwaway home, and prints through the command's own Check.printed. Not as
// a program of its own: WebKit gives each program that loads it three folders in $TMPDIR, named by the program's
// build, that cannot be deleted, so each new build run that way would leave three more on the Mac. The three codes a
// page cannot be made to give on demand (no window server, a timeout, a web process that ends) run through the
// runner's settings. The whole command, main.swift and Check.main, runs on CI through the assembled program.
import AppKit
import Foundation
import SomethingAgents
import SomethingCore
import Testing
import WebKit
@testable import something

/// One `something check` in `home`, run and printed as the command does: its status, what it printed to the
/// standard output and to the standard error, and the output read as JSON when it is. The snapshots go to the spaces
/// folder's .check, or the home's tmp/ for a page elsewhere. Throws when `words` are not a check's.
struct Checked {
    let status: Int32, out: String, err: String
    var json: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] ?? [:] }
    var codes: [String] { (json["problems"] as? [[String: Any]] ?? []).compactMap { $0["code"] as? String } }

    @MainActor init(_ words: [String], _ home: Home) async throws {
        guard case .check(let check) = Check.parse(words) else { throw SpaceError("\(words) are not the words of a check.") }
        let runner = try CheckTests.runner(home)
        let outcome: Result<Report, SpaceError>
        do { outcome = .success(try await runner.run(check)) } catch { outcome = .failure(try #require(error as? SpaceError)) }
        var out = "", err = ""
        // One line per call, to the standard error when it is a problem, as main.swift prints it.
        status = check.printed(outcome, home: home.places.home.path) { text, problem in
            if problem { err += text + "\n" } else { out += text + "\n" }
        }
        (self.out, self.err) = (out, err)
    }
}

/// A page whose declaration is `{"contract": 1}` plus `keys`, and whose body is `body`.
func declared(_ keys: String, _ body: String) -> String {
    page("{\"contract\": 1\(keys.isEmpty ? "" : ", " + keys)}", body)
}

func declared(_ body: String) -> String { declared("", body) }

extension Home {
    /// Writes ~/something/spaces/<name>/ with these files (path: text) and returns its folder.
    @discardableResult
    func folder(_ name: String, _ files: [String: String]) throws -> URL {
        let folder = places.spaces.appendingPathComponent(name)
        for (path, text) in files {
            let file = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
        return folder
    }
}

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-check-")) struct CheckTests {
    init() {
        NSApplication.shared.setActivationPolicy(.prohibited)
    }

    /// Each fixture: the code it must give alone, how to make the space "x" in a home, and the words after its name.
    nonisolated(unsafe) static let fixtures: [(code: String, make: (Home) throws -> Void, words: [String])] = [
        ("DECLARATION_UNREADABLE", { try $0.space("x", page("{\"contract\": 1,", "<p>Invented.</p>")) }, []),
        ("CONTRACT_TOO_NEW", { try $0.space("x", page("{\"contract\": 2}", "<p>Invented.</p>")) }, []),
        ("SCRIPT_ERROR", { try $0.space("x", declared("<script>agnets.length;</script>")) }, []),
        ("PROMISE_REJECTED", { try $0.space("x", declared("<script>Promise.reject(new Error(\"Invented failure.\"));</script>")) }, []),
        ("RESOURCE_MISSING", { try $0.space("x", declared("<img src=\"logo.png\">")) }, []),
        ("LOAD_FAILED", { home in
            // A page that is a link to a file outside its folder: the space's scheme serves nothing outside the space.
            let outside = home.root.appendingPathComponent("outside.html")
            try FileManager.default.createDirectory(at: home.root, withIntermediateDirectories: true)
            try declared("<p>Invented.</p>").write(to: outside, atomically: true, encoding: .utf8)
            try FileManager.default.createDirectory(at: home.places.spaces.appendingPathComponent("x"), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: home.places.spaces.appendingPathComponent("x/index.html"), withDestinationURL: outside)
        }, []),
        ("DECLARATION_MISSING", { try $0.space("x", page(nil, "<p>Invented.</p>")) }, []),
        ("DECLARATION_TWICE", { try $0.folder("x", ["index.html": declared("<p>Invented.</p>"), "something.json": "{\"contract\": 1}"]) }, []),
        ("CONTRACT_MISSING", { try $0.space("x", page("{\"title\": \"Invented\"}", "<p>Invented.</p>")) }, []),
        ("SCOPE_INVALID", { try $0.space("x", declared("\"agents\": {\"see\": \"some\"}", "<p>Invented.</p>")) }, []),
        ("UNKNOWN_RIGHT", { try $0.space("x", declared("\"rights\": [\"sendd\"]", "<p>Invented.</p>")) }, []),
        ("RIGHT_NOT_DECLARED", { try $0.space("x", declared("<script>something.send(\"a1\", \"Hello.\").catch(() => {});</script>")) }, []),
        ("RIGHT_REFUSED", { try $0.space("x", declared("\"agents\": {\"see\": \"all\"}, \"rights\": [\"state\", \"send\"]",
                                                        "<script>something.send(\"a1\", \"Hello.\");</script>")) }, ["--refuse", "send"]),
        ("RESOURCE_BLOCKED", { try $0.space("x", declared("<img src=\"https://example.com/logo.png\">")) }, []),
        // Code from a string breaks the space's policy, which WebKit reports only to the app's page.
        ("RESOURCE_BLOCKED", { try $0.space("x", declared("<script>try { eval(\"1\"); } catch (error) {}</script>")) }, []),
        // An error after the snapshot is still heard.
        ("SCRIPT_ERROR", { try $0.space("x", declared("<script>setTimeout(() => { throw new Error(\"Invented late failure.\"); }, 50);</script>")) }, []),
        ("NAVIGATION_BLOCKED", { try $0.space("x", declared("<script>location.href = \"https://example.com/\";</script>")) }, []),
        ("BRIDGE_ERROR", { try $0.space("x", declared("\"agents\": {\"see\": \"all\"}, \"rights\": [\"state\", \"send\"]",
                                                       "<script>something.send(\"zz\", \"Hello.\").catch(() => {});</script>")) }, []),
        ("CONSOLE_ERROR", { try $0.space("x", declared("<script>console.error(\"Invented problem.\");</script>")) }, []),
        ("FOLDER_MISSING", { try $0.space("x", declared("\"folder\": \"/Users/example/nowhere\"", "<p>Invented.</p>")) }, []),
        ("TOO_HEAVY", { try $0.folder("x", ["index.html": declared("<p>Invented.</p>"), "photo.txt": String(repeating: "x", count: 5_100_000)]) }, []),
        ("UNKNOWN_KEY", { try $0.space("x", declared("\"colour\": \"blue\"", "<p>Invented.</p>")) }, []),
        ("SPACE_NOT_FOUND", { _ in }, []),
        ("STATE_FILE_UNREADABLE", { home in
            try home.space("x", declared("<p>Invented.</p>"))
            try "{\"contract\": 1}".write(to: home.root.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
        }, ["--state", "STATE"]),
    ]

    @Test(arguments: fixtures.indices)
    func eachSpaceGivesExactlyItsCode(_ index: Int) async throws {
        let fixture = CheckTests.fixtures[index], home = Home(prefix: "something-check-")
        defer { home.remove() }
        try fixture.make(home)
        let words = fixture.words.map { $0 == "STATE" ? home.root.appendingPathComponent("state.json").path : $0 }
        let checked = try await Checked(["x", "--json"] + words, home)
        #expect(checked.codes == [fixture.code], "\(fixture.code): \(checked.out)")
        let level = try #require(Codes.all[fixture.code]).level
        #expect(checked.status == (level == .fatal ? 2 : level == .error ? 1 : 0), "\(fixture.code) exits with \(checked.status)")
    }

    /// The fixtures and the three run in this process cover every code check gives, but RIGHT_UNAVAILABLE: every kind
    /// this build knows is launchable since OMP is (DeclarationTests gives the code with a kind registered read-only).
    @Test func everyCheckCodeHasItsFixture() {
        let check = Set(Codes.all.filter { $0.value.from == "check" }.keys)
        #expect(Registry.app.kinds.readOnly.isEmpty)
        #expect(Set(CheckTests.fixtures.map(\.code)).union(["NO_WINDOW_SERVER", "LOAD_TIMEOUT", "PAGE_CRASHED", "RIGHT_UNAVAILABLE"]) == check)
    }

    /// The template the command starts a space from is a clean space: no problem, a snapshot, every call answered.
    @Test func aCleanSpaceGivesNone() async throws {
        let home = Home(prefix: "something-check-")
        defer { home.remove() }
        try home.space("board", try String(contentsOf: Home.share.appendingPathComponent("template.html"), encoding: .utf8))
        let checked = try await Checked(["board", "--json"], home)
        #expect(checked.status == 0 && checked.codes.isEmpty, "\(checked.out)")
        let snapshot = try #require(checked.json["snapshot"] as? String)
        #expect(snapshot == home.places.spaces.appendingPathComponent(".check/board.png").path, "in the folder the agent works in")
        #expect(try Data(contentsOf: URL(fileURLWithPath: snapshot)).prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        let calls = checked.json["calls"] as? [[String: Any]] ?? []
        #expect(calls.contains { $0["method"] as? String == "state" && ($0["answer"] as? [String: Any])?["agents"] as? [String] == ["a1", "e1", "p1"] })
        #expect(checked.json["received"] as? NSDictionary == ["source": "invented", "agents": 3, "states": ["waiting": 1, "done": 1, "unknown": 1],
                                                               "requests": 1, "nullKeys": ["effort", "error", "mode", "model", "pid", "thread", "updated", "waiting"]])
        let human = try await Checked(["board"], home)
        #expect(human.status == 0 && human.out.hasPrefix("something check board\n  space     "), "\(human.out)")
        #expect(human.out.contains("\n  received  3 agents (1 waiting, 1 done, 1 unknown), 1 request · invented state\n"))
        #expect(human.out.hasSuffix("\n  0 errors, 0 warnings.\n"))
    }

    /// --json has the keys of share/contract/check-example.json, at every level the example shows.
    @Test func theJsonMatchesTheContractKeyForKey() async throws {
        let home = Home(prefix: "something-check-")
        defer { home.remove() }
        try home.space("x", declared("\"agents\": {\"see\": \"all\"}, \"rights\": [\"state\", \"send:claude\", \"sendd\"]", """
            <script>agnets;</script><script>console.warn("No agent yet."); something.send("a1", "Hello", { when: "next" });</script>
            """))
        let checked = try await Checked(["x", "--json"], home)
        let example = try JSONSerialization.jsonObject(with: Data(contentsOf: Home.share.appendingPathComponent("contract/check-example.json")))
        func keys(_ a: Any?, _ b: Any?, _ at: String) {
            if let a = a as? [String: Any], let b = b as? [String: Any] {
                #expect(Set(a.keys) == Set(b.keys), "\(at): \(a.keys.sorted()) against \(b.keys.sorted())")
                // states counts words and nullKeys lists them: their keys are the page's, not the contract's.
                for key in a.keys where key != "states" { keys(a[key], b[key], at + "." + key) }
            } else if let a = a as? [Any], let b = b as? [Any], let first = a.first, let other = b.first {
                keys(first, other, at + "[0]")
            }
        }
        keys(checked.json, example, "")
        #expect(checked.codes == ["SCRIPT_ERROR", "UNKNOWN_RIGHT"] && checked.status == 1, "\(checked.out)")
        #expect((checked.json["calls"] as? [[String: Any]])?.first as NSDictionary? == ["method": "send", "params": ["agent": "a1", "text": "Hello", "when": "next"],
                                                                                         "answer": ["delivery": "queued"]])
        #expect(checked.json["console"] as? [NSDictionary] == [["level": "warn", "text": "No agent yet."]])
        // The example's received is what the invented state gives, and its rights what this declaration gives.
        #expect(checked.json["received"] as? NSDictionary == (example as? [String: Any])?["received"] as? NSDictionary)
        #expect(checked.json["rights"] as? NSDictionary == (example as? [String: Any])?["rights"] as? NSDictionary)
    }

    /// --refuse takes a right from the declared ones; a page that reads granted and hides it is clean.
    @Test func refuseTakesARight() async throws {
        let home = Home(prefix: "something-check-")
        defer { home.remove() }
        try home.space("board", try String(contentsOf: Home.share.appendingPathComponent("template.html"), encoding: .utf8))
        let checked = try await Checked(["board", "--json", "--refuse", "send"], home)
        #expect(checked.status == 0 && checked.codes.isEmpty, "\(checked.out)")
        #expect((checked.json["rights"] as? [String: Any])?["granted"] as? [String] == ["state", "launch"])
        #expect((checked.json["rights"] as? [String: Any])?["refused"] as? [String] == ["send"])
    }

    /// RIGHT_REFUSED is only for the rejection of a refused call: a caught refused call and an uncaught undeclared
    /// one give the undeclared one's codes, and the check fails.
    @Test func onlyARefusedCallIsRightRefused() async throws {
        let home = Home(prefix: "something-check-")
        defer { home.remove() }
        try home.space("x", declared("\"agents\": {\"see\": \"all\"}, \"rights\": [\"state\", \"send\"]",
                                     "<script>something.send(\"a1\", \"Hello.\").catch(() => {}); something.launch(\"pi\");</script>"))
        let checked = try await Checked(["x", "--json", "--refuse", "send"], home)
        #expect(checked.codes == ["PROMISE_REJECTED", "RIGHT_NOT_DECLARED"] && checked.status == 1, "\(checked.out)")
    }

    /// A launch the app refuses is refused by the check too: a mode something does not offer for Codex, and a model
    /// that reads as a flag, which only Registry.app.checkLaunch refuses (the BridgeHost default both hosts share). Codex,
    /// not OpenCode: the invented state has no OpenCode installed, which is refused first.
    @Test func aLaunchTheAppRefusesIsABridgeError() async throws {
        let home = Home(prefix: "something-check-")
        defer { home.remove() }
        try home.space("x", declared("\"rights\": [\"launch:codex\"]", """
            <script>
            something.launch("codex", {mode: "granular"}).catch(() => {});
            something.launch("codex", {model: "--yolo"}).catch(() => {});
            </script>
            """))
        let checked = try await Checked(["x", "--json"], home)
        let messages = (checked.json["problems"] as? [[String: Any]] ?? []).compactMap { $0["message"] as? String }
        #expect(checked.codes == ["BRIDGE_ERROR", "BRIDGE_ERROR"], "\(checked.out)")
        #expect(messages.contains { $0.contains("VALUE_NOT_OFFERED") } && messages.contains { $0.contains("BAD_PARAMS") }, "\(checked.out)")
        let calls = checked.json["calls"] as? [[String: Any]] ?? []
        let codes = calls.map { (($0["answer"] as? [String: Any])?["error"] as? [String: Any])?["code"] as? String }
        #expect(calls.map { $0["method"] as? String } == ["launch", "launch"] && codes == ["VALUE_NOT_OFFERED", "BAD_PARAMS"], "\(checked.out)")
    }

    /// A --refuse word must name a declared right as it is declared, or nothing would be refused.
    @Test func refuseNamesADeclaredRight() async throws {
        let home = Home(prefix: "something-check-")
        defer { home.remove() }
        try home.space("x", declared("\"agents\": {\"see\": \"all\"}, \"rights\": [\"state\", \"send\"]", "<p>Invented.</p>"))
        for word in ["sned", "send:claude"] {
            let checked = try await Checked(["x", "--refuse", word], home)
            #expect(checked.status == 2 && checked.out.isEmpty, "\(checked.out)")
            #expect(checked.err == "--refuse \(word) names no right the space declares (it declares: state, send); refuse a right as it is declared.\n")
        }
    }

    /// An error thrown in a listener of something.on keeps its file and line.
    @Test func aListenerErrorSaysWhere() async throws {
        let home = Home(prefix: "something-check-")
        defer { home.remove() }
        try home.space("x", declared("\"agents\": {\"see\": \"all\"}, \"rights\": [\"state\"]",
                                     "<script>\nsomething.on(\"change\", (state) => { state.agnets.length; });\n</script>"))
        let checked = try await Checked(["x", "--json"], home)
        let problem = (checked.json["problems"] as? [[String: Any]])?.first
        #expect(checked.codes == ["SCRIPT_ERROR"] && (problem?["where"] as? [String: Any])?["file"] as? String == "x.html", "\(checked.out)")
        #expect((problem?["where"] as? [String: Any])?["line"] as? Int == 2, "\(checked.out)")
    }

    /// --state gives the page another state, named as the source; a broken one stops the check (status 2).
    @Test func stateGivesAnotherState() async throws {
        let home = Home(prefix: "something-check-")
        defer { home.remove() }
        try home.space("x", declared("\"agents\": {\"see\": \"all\"}, \"rights\": [\"state\"]", "<script>something.state();</script>"))
        var state = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: Home.share.appendingPathComponent("contract/state-example.json"))) as? [String: Any])
        state["agents"] = Array((state["agents"] as? [Any] ?? []).prefix(1))
        let file = home.root.appendingPathComponent("one.json")
        try JSONSerialization.data(withJSONObject: state).write(to: file)
        let checked = try await Checked(["x", "--json", "--state", file.path], home)
        #expect(checked.status == 0 && checked.codes.isEmpty, "\(checked.out)")
        #expect((checked.json["received"] as? [String: Any])?["source"] as? String == file.path)
        #expect((checked.json["received"] as? [String: Any])?["agents"] as? Int == 1)

        try "{\"contract\": 1, \"at\": \"x\", \"kinds\": {}, \"agents\": [{\"id\": \"a1\"}], \"threads\": [], \"requests\": []}".write(to: file, atomically: true, encoding: .utf8)
        let broken = try await Checked(["x", "--state", file.path], home)
        #expect(broken.status == 2 && broken.out.contains("fatal     STATE_FILE_UNREADABLE \(file.path) is not a state of contract 1: the key agents[0].kind is missing."), "\(broken.out)")
        #expect(broken.out.hasSuffix("The check could not run to its end: fix the fatal problem first.\n"))
    }

    /// --journal adds the space's journal, and never the check's own calls.
    @Test func journalPrintsTheSpacesJournal() async throws {
        let home = Home(prefix: "something-check-")
        defer { home.remove() }
        try home.space("x", declared("\"agents\": {\"see\": \"all\"}, \"rights\": [\"state\", \"send\"]", "<script>something.send(\"a1\", \"Hello.\");</script>"))
        let line = JournalLine(at: "2026-10-17T09:00:02Z", action: "send", agent: "a1", kind: "claude", when: "next", text: "Then run the tests.", result: "ok")
        try Journal(folder: home.places.journals).append(line, space: "x")
        let checked = try await Checked(["x", "--json", "--journal"], home)
        #expect(checked.json["journal"] as? [NSDictionary] == [["at": "2026-10-17T09:00:02Z", "action": "send", "agent": "a1", "kind": "claude",
                                                                 "when": "next", "text": "Then run the tests.", "result": "ok"]], "\(checked.out)")
        #expect(try Journal(folder: home.places.journals).last(10, space: "x") == [line])
        let human = try await Checked(["x", "--journal"], home)
        #expect(human.out.contains("\n  journal   2026-10-17T09:00:02Z send a1 claude next \"Then run the tests.\": ok\n"), "\(human.out)")
        #expect(try await Checked(["x", "--json"], home).json["journal"] is NSNull)

        // Over 100 lines, the human output says the older ones are left out.
        for _ in 0..<100 { try Journal(folder: home.places.journals).append(line, space: "x") }
        let long = try await Checked(["x", "--journal"], home)
        #expect(long.out.components(separatedBy: "\n  journal   2026").count == 101, "\(long.out)")
        #expect(long.out.contains("\n  journal   the last 100 lines; older ones are left out\n"))

        // A journal that cannot be read is null, and the human output says why.
        let file = Journal(folder: home.places.journals).file("x")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        #expect(try await Checked(["x", "--json", "--journal"], home).json["journal"] is NSNull)
        #expect(try await Checked(["x", "--journal"], home).out.contains("\n  journal   not read: The journal in \(file.path) cannot be read.\n"))
    }

    /// 0 with warnings only, 1 with an error, 2 when the check could not run.
    @Test func theThreeExitStatuses() async throws {
        let home = Home(prefix: "something-check-")
        defer { home.remove() }
        try home.space("warned", declared("<script>console.error(\"Invented problem.\");</script>"))
        try home.space("broken", declared("<script>agnets.length;</script>"))
        #expect(try await Checked(["warned"], home).status == 0)
        #expect(try await Checked(["broken"], home).status == 1)
        let missing = try await Checked(["nowhere"], home)
        #expect(missing.status == 2 && missing.out.contains("fatal     SPACE_NOT_FOUND There is no space nowhere in "), "\(missing.out)")
    }

    // MARK: In this process, through the runner's settings

    /// WebKit's private setter that turns off its window occlusion detection, looked up once; nil when this WebKit
    /// does not have it.
    static let occlusionSetter: (@convention(c) (AnyObject, Selector, Bool) -> Void)? = {
        guard let method = class_getInstanceMethod(WKWebView.self, NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")) else { return nil }
        return unsafeBitCast(method_getImplementation(method), to: (@convention(c) (AnyObject, Selector, Bool) -> Void).self)
    }()

    /// A runner for `home`, its snapshots in the home's tmp/. The command paints while AppKit runs the app, which
    /// tells WebKit its window is on screen; this process does not run the app, so WebKit is told not to wait for
    /// that (through a private setter these tests alone use), or the page would never paint. Throws at once when
    /// this WebKit has no such setter, rather than letting every check wait for its timeout.
    static func runner(_ home: Home) throws -> CheckRunner {
        let setter = try #require(occlusionSetter, "This WebKit has no _setWindowOcclusionDetectionEnabled:, so a check in this process would never paint.")
        let runner = CheckRunner(places: home.places, share: Home.share)
        runner.output = home.root.appendingPathComponent("tmp/something-check")
        runner.created = { setter($0, NSSelectorFromString("_setWindowOcclusionDetectionEnabled:"), false) }
        return runner
    }

    /// A space of the spaces folder has its snapshot in the hidden folder .check there, where the agent building it
    /// reads it without asking; a page elsewhere has its own in $TMPDIR/something-check. Check.main itself is not run
    /// here: Swift Testing runs this suite inside a job of the main queue, which NSApp.run cannot drain, so the report
    /// would never come. CI runs it through the assembled program instead.
    @Test func theSnapshotsGoToTheSpacesFolderOrTheTemporaryFolder() async throws {
        let temporary = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        let home = Home(prefix: "something-check-")
        defer { home.remove() }
        #expect(CheckRunner(places: home.places, share: Home.share).output == URL(fileURLWithPath: temporary).appendingPathComponent("something-check"))
        #expect(CheckRunner.snapshots(home.places) == home.places.spaces.appendingPathComponent(".check"))
        let elsewhere = home.root.appendingPathComponent("elsewhere/board.html")
        try FileManager.default.createDirectory(at: elsewhere.deletingLastPathComponent(), withIntermediateDirectories: true)
        try String(contentsOf: Home.share.appendingPathComponent("template.html"), encoding: .utf8).write(to: elsewhere, atomically: true, encoding: .utf8)
        let checked = try await Checked([elsewhere.path, "--json"], home)
        #expect(checked.json["snapshot"] as? String == home.root.appendingPathComponent("tmp/something-check/board.png").path, "\(checked.out)")
        #expect(!FileManager.default.fileExists(atPath: CheckRunner.snapshots(home.places).path))
    }

    /// Each check removes the snapshots older than a day, whatever space they were of, in both places; newer ones stay.
    @Test func aCheckRemovesTheSnapshotsOfMoreThanADay() async throws {
        let home = Home(prefix: "something-check-")
        defer { home.remove() }
        try home.space("x", declared(""))
        let runner = try CheckTests.runner(home)
        runner.windowServer = false
        var old: [URL] = [], recent: [URL] = []
        for folder in [runner.output, CheckRunner.snapshots(home.places)] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            old.append(folder.appendingPathComponent("gone.png"))
            recent.append(folder.appendingPathComponent("kept.png"))
        }
        for file in old + recent { try Data("invented".utf8).write(to: file) }
        for file in old { try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-86_500)], ofItemAtPath: file.path) }
        _ = try await runner.run(Check(space: "x"))
        #expect(old.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(recent.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    /// In an agent's sandbox there is no window server: the static checks run, the page does not, and the check says so.
    @Test func withoutAWindowServerOnlyTheStaticChecksRun() async throws {
        let home = Home(prefix: "something-check-")
        defer { home.remove() }
        try home.space("x", declared("\"colour\": \"blue\"", "<script>agnets.length;</script>"))
        let runner = try CheckTests.runner(home)
        runner.windowServer = false
        let report = try await runner.run(Check(space: "x"))
        #expect(report.problems.map(\.code) == ["NO_WINDOW_SERVER", "UNKNOWN_KEY"] && report.exitStatus == 2)
        // The page received nothing: it was not loaded.
        #expect(report.snapshot == nil && report.calls.isEmpty && report.received == nil)
        try home.space("clean", declared("<p>Invented.</p>"))
        #expect(try await runner.run(Check(space: "clean")).problems.map(\.code) == ["NO_WINDOW_SERVER"])
    }

    /// Ends the web process of `web` as a crash would. WebKit says its process only through a private key, which
    /// these tests alone read; false when this WebKit does not have it.
    @discardableResult
    static func kill(_ web: WKWebView) -> Bool {
        guard let pid = (web.value(forKey: "_webProcessIdentifier") as? NSNumber)?.int32Value, pid > 0 else { return false }
        return Darwin.kill(pid, SIGKILL) == 0
    }

    @Test func aPageThatNeverLoadsTimesOut() async throws {
        let home = Home(prefix: "something-check-")
        defer { home.remove() }
        try home.space("x", declared("<script>for (;;) {}</script>"))
        let runner = try CheckTests.runner(home)
        var web: WKWebView?
        let paint = runner.created
        runner.created = { paint($0); web = $0 }
        runner.timeout = 1
        let report = try await runner.run(Check(space: "x"))
        // The page's process still loops; it ends with the web view only when it is killed.
        if let web { CheckTests.kill(web) }
        #expect(report.problems.map(\.code) == ["LOAD_TIMEOUT"] && report.exitStatus == 1, "\(report.problems)")
        #expect(report.problems.first?.message == "The page did not finish loading within 1 second.")
    }

    @Test func aPageWhoseProcessEndsCrashed() async throws {
        let home = Home(prefix: "something-check-")
        defer { home.remove() }
        try home.space("x", declared("<p>Invented.</p>"))
        let runner = try CheckTests.runner(home)
        var killed = false
        runner.loaded = { killed = CheckTests.kill($0) }
        let report = try await runner.run(Check(space: "x"))
        try #require(killed, "This WebKit does not say the pid of its web process.")
        #expect(report.problems.map(\.code) == ["PAGE_CRASHED"] && report.exitStatus == 1, "\(report.problems)")
    }
}
