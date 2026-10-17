// `something check` (contract 9): one invented space per check code gives exactly that code, and a clean space none;
// --json has every key of share/contract/check-example.json; --refuse, --state, --journal and the three exit statuses.
// The page paints only while AppKit runs the app, which a test cannot do in its own process: these checks run the
// something program swift test built, in a throwaway home. The three codes a page cannot be made to give on demand
// (no window server, a timeout, a web process that ends) run in this process through the runner's own settings.
import AppKit
import Foundation
import SomethingCore
import Testing
import WebKit
@testable import something

/// One run of `something check` in `home`: its status, its standard output, and that output read as JSON when it is.
struct Checked {
    let status: Int32, out: String
    var json: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] ?? [:] }
    var codes: [String] { (json["problems"] as? [[String: Any]] ?? []).compactMap { $0["code"] as? String } }

    init(_ words: [String], _ home: Home) throws {
        let process = Process()
        process.executableURL = Bundle(for: FakeDoor.self).bundleURL.deletingLastPathComponent().appendingPathComponent("something")
        process.arguments = ["check"] + words
        var environment = ProcessInfo.processInfo.environment
        (environment["HOME"], environment["TMPDIR"]) = (home.root.path, home.root.appendingPathComponent("tmp").path)
        process.environment = environment
        let out = Pipe()
        (process.standardOutput, process.standardError) = (out, FileHandle.nullDevice)
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        (status, self.out) = (process.terminationStatus, String(decoding: data, as: UTF8.self))
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

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing)) struct CheckTests {
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
        ("RIGHT_UNAVAILABLE", { try $0.space("x", declared("\"rights\": [\"launch:omp\"]", "<p>Invented.</p>")) }, []),
        ("RIGHT_NOT_DECLARED", { try $0.space("x", declared("<script>something.send(\"a1\", \"Hello.\").catch(() => {});</script>")) }, []),
        ("RIGHT_REFUSED", { try $0.space("x", declared("\"agents\": {\"see\": \"all\"}, \"rights\": [\"state\", \"send\"]",
                                                        "<script>something.send(\"a1\", \"Hello.\");</script>")) }, ["--refuse", "send"]),
        ("RESOURCE_BLOCKED", { try $0.space("x", declared("<img src=\"https://example.com/logo.png\">")) }, []),
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
    func eachSpaceGivesExactlyItsCode(_ index: Int) throws {
        let fixture = CheckTests.fixtures[index], home = Home()
        defer { home.remove() }
        try fixture.make(home)
        let words = fixture.words.map { $0 == "STATE" ? home.root.appendingPathComponent("state.json").path : $0 }
        let checked = try Checked(["x", "--json"] + words, home)
        #expect(checked.codes == [fixture.code], "\(fixture.code): \(checked.out)")
        let level = try #require(Codes.all[fixture.code]).level
        #expect(checked.status == (level == .fatal ? 2 : level == .error ? 1 : 0), "\(fixture.code) exits with \(checked.status)")
    }

    /// The fixtures and the three run in this process cover every code check gives.
    @Test func everyCheckCodeHasItsFixture() {
        let check = Set(Codes.all.filter { $0.value.from == "check" }.keys)
        #expect(Set(CheckTests.fixtures.map(\.code)).union(["NO_WINDOW_SERVER", "LOAD_TIMEOUT", "PAGE_CRASHED"]) == check)
    }

    /// The template the command starts a space from is a clean space: no problem, a snapshot, every call answered.
    @Test func aCleanSpaceGivesNone() throws {
        let home = Home()
        defer { home.remove() }
        try home.space("board", try String(contentsOf: Home.share.appendingPathComponent("template.html"), encoding: .utf8))
        let checked = try Checked(["board", "--json"], home)
        #expect(checked.status == 0 && checked.codes.isEmpty, "\(checked.out)")
        let snapshot = try #require(checked.json["snapshot"] as? String)
        #expect(snapshot == home.root.appendingPathComponent("tmp/something-check/board.png").path)
        #expect(try Data(contentsOf: URL(fileURLWithPath: snapshot)).prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        let calls = checked.json["calls"] as? [[String: Any]] ?? []
        #expect(calls.contains { $0["method"] as? String == "state" && ($0["answer"] as? [String: Any])?["agents"] as? [String] == ["a1", "e1", "p1"] })
        #expect(checked.json["received"] as? NSDictionary == ["source": "invented", "agents": 3, "states": ["waiting": 1, "done": 1, "unknown": 1],
                                                               "requests": 1, "nullKeys": ["effort", "error", "mode", "model", "pid", "thread", "updated", "waiting"]])
        let human = try Checked(["board"], home)
        #expect(human.status == 0 && human.out.hasPrefix("something check board\n  space     "), "\(human.out)")
        #expect(human.out.contains("\n  received  3 agents (1 waiting, 1 done, 1 unknown), 1 request · invented state\n"))
        #expect(human.out.hasSuffix("\n  0 errors, 0 warnings.\n"))
    }

    /// --json has the keys of contract 9.3, at every level the example shows.
    @Test func theJsonMatchesTheContractKeyForKey() throws {
        let home = Home()
        defer { home.remove() }
        try home.space("x", declared("\"agents\": {\"see\": \"all\"}, \"rights\": [\"state\", \"send:claude\", \"sendd\"]", """
            <script>agnets;</script><script>console.warn("No agent yet."); something.send("a1", "Hello", { when: "next" });</script>
            """))
        let checked = try Checked(["x", "--json"], home)
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
    }

    /// --refuse takes a right from the declared ones; a page that reads granted and hides it is clean.
    @Test func refuseTakesARight() throws {
        let home = Home()
        defer { home.remove() }
        try home.space("board", try String(contentsOf: Home.share.appendingPathComponent("template.html"), encoding: .utf8))
        let checked = try Checked(["board", "--json", "--refuse", "send"], home)
        #expect(checked.status == 0 && checked.codes.isEmpty, "\(checked.out)")
        #expect((checked.json["rights"] as? [String: Any])?["granted"] as? [String] == ["state", "launch"])
        #expect((checked.json["rights"] as? [String: Any])?["refused"] as? [String] == ["send"])
    }

    /// --state gives the page another state, named as the source; a broken one stops the check (status 2).
    @Test func stateGivesAnotherState() throws {
        let home = Home()
        defer { home.remove() }
        try home.space("x", declared("\"agents\": {\"see\": \"all\"}, \"rights\": [\"state\"]", "<script>something.state();</script>"))
        var state = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: Home.share.appendingPathComponent("contract/state-example.json"))) as? [String: Any])
        state["agents"] = Array((state["agents"] as? [Any] ?? []).prefix(1))
        let file = home.root.appendingPathComponent("one.json")
        try JSONSerialization.data(withJSONObject: state).write(to: file)
        let checked = try Checked(["x", "--json", "--state", file.path], home)
        #expect(checked.status == 0 && checked.codes.isEmpty, "\(checked.out)")
        #expect((checked.json["received"] as? [String: Any])?["source"] as? String == file.path)
        #expect((checked.json["received"] as? [String: Any])?["agents"] as? Int == 1)

        try "{\"contract\": 1, \"at\": \"x\", \"kinds\": {}, \"agents\": [{\"id\": \"a1\"}], \"threads\": [], \"requests\": []}".write(to: file, atomically: true, encoding: .utf8)
        let broken = try Checked(["x", "--state", file.path], home)
        #expect(broken.status == 2 && broken.out.contains("fatal     STATE_FILE_UNREADABLE \(file.path) is not a state of contract 1: the key agents[0].kind is missing."), "\(broken.out)")
        #expect(broken.out.hasSuffix("The check could not run to its end: fix the fatal problem first.\n"))
    }

    /// --journal adds the space's journal, and never the check's own calls.
    @Test func journalPrintsTheSpacesJournal() throws {
        let home = Home()
        defer { home.remove() }
        try home.space("x", declared("\"agents\": {\"see\": \"all\"}, \"rights\": [\"state\", \"send\"]", "<script>something.send(\"a1\", \"Hello.\");</script>"))
        let line = JournalLine(at: "2026-10-17T09:00:02Z", action: "send", agent: "a1", kind: "claude", when: "next", text: "Then run the tests.", result: "ok")
        try Journal(folder: home.places.journals).append(line, space: "x")
        let checked = try Checked(["x", "--json", "--journal"], home)
        #expect(checked.json["journal"] as? [NSDictionary] == [["at": "2026-10-17T09:00:02Z", "action": "send", "agent": "a1", "kind": "claude",
                                                                 "when": "next", "text": "Then run the tests.", "result": "ok"]], "\(checked.out)")
        #expect(try Journal(folder: home.places.journals).last(10, space: "x") == [line])
        let human = try Checked(["x", "--journal"], home)
        #expect(human.out.contains("\n  journal   2026-10-17T09:00:02Z send a1 claude next \"Then run the tests.\": ok\n"), "\(human.out)")
        #expect(try Checked(["x", "--json"], home).json["journal"] is NSNull)
    }

    /// 0 with warnings only, 1 with an error, 2 when the check could not run.
    @Test func theThreeExitStatuses() throws {
        let home = Home()
        defer { home.remove() }
        try home.space("warned", declared("<script>console.error(\"Invented problem.\");</script>"))
        try home.space("broken", declared("<script>agnets.length;</script>"))
        #expect(try Checked(["warned"], home).status == 0)
        #expect(try Checked(["broken"], home).status == 1)
        let missing = try Checked(["nowhere"], home)
        #expect(missing.status == 2 && missing.out.contains("fatal     SPACE_NOT_FOUND There is no space nowhere in "), "\(missing.out)")
    }

    // MARK: In this process, through the runner's settings

    func runner(_ home: Home) -> CheckRunner {
        let runner = CheckRunner(places: home.places, share: Home.share)
        runner.output = home.root.appendingPathComponent("tmp/something-check")
        return runner
    }

    /// In an agent's sandbox there is no window server: the static checks run, the page does not, and the check says so.
    @Test func withoutAWindowServerOnlyTheStaticChecksRun() async throws {
        let home = Home()
        defer { home.remove() }
        try home.space("x", declared("\"colour\": \"blue\"", "<script>agnets.length;</script>"))
        let runner = runner(home)
        runner.windowServer = false
        let report = await runner.run(Check(space: "x"))
        #expect(report.problems.map(\.code) == ["NO_WINDOW_SERVER", "UNKNOWN_KEY"] && report.exitStatus == 2)
        #expect(report.snapshot == nil && report.calls.isEmpty && report.received?.agents == 0)
        try home.space("clean", declared("<p>Invented.</p>"))
        #expect(await runner.run(Check(space: "clean")).problems.map(\.code) == ["NO_WINDOW_SERVER"])
    }

    /// Ends the web process of `web` as a crash would. WebKit says its process only through a private key, which
    /// these tests alone read; false when this WebKit does not have it.
    @discardableResult
    static func kill(_ web: WKWebView) -> Bool {
        guard let pid = (web.value(forKey: "_webProcessIdentifier") as? NSNumber)?.int32Value, pid > 0 else { return false }
        return Darwin.kill(pid, SIGKILL) == 0
    }

    @Test func aPageThatNeverLoadsTimesOut() async throws {
        let home = Home()
        defer { home.remove() }
        try home.space("x", declared("<script>for (;;) {}</script>"))
        let runner = runner(home)
        var web: WKWebView?
        runner.created = { web = $0 }
        runner.timeout = 1
        let report = await runner.run(Check(space: "x"))
        // The page's process still loops; it ends with the web view only when it is killed.
        if let web { CheckTests.kill(web) }
        #expect(report.problems.map(\.code) == ["LOAD_TIMEOUT"] && report.exitStatus == 1, "\(report.problems)")
        #expect(report.problems.first?.message == "The page did not finish loading within 1 second.")
    }

    @Test func aPageWhoseProcessEndsCrashed() async throws {
        let home = Home()
        defer { home.remove() }
        try home.space("x", declared("<p>Invented.</p>"))
        let runner = runner(home)
        var killed = false
        runner.loaded = { killed = CheckTests.kill($0) }
        let report = await runner.run(Check(space: "x"))
        try #require(killed, "This WebKit does not say the pid of its web process.")
        #expect(report.problems.map(\.code) == ["PAGE_CRASHED"] && report.exitStatus == 1, "\(report.problems)")
    }
}
