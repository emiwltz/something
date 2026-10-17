// Codes.swift equals share/contract/codes.json, code for code, and the report reads as contract 9.2 and 9.3 show it.
import Foundation
import Testing
@testable import SomethingCore

@Suite struct CodesTests {
    @Test func theTableEqualsCodesJson() throws {
        let json = try #require(try ContractFiles.object("codes.json")["codes"] as? [String: [String: Any]])
        #expect(Set(Codes.all.keys) == Set(json.keys))
        for (name, entry) in json {
            let code = try #require(Codes.all[name])
            #expect(code.from == entry["from"] as? String, "\(name) from")
            #expect(code.level.rawValue == entry["level"] as? String, "\(name) level")
            #expect(code.blocks == (entry["blocks"] as? Bool ?? false), "\(name) blocks")
            #expect(code.when == entry["when"] as? String, "\(name) when")
            #expect(code.fix == entry["fix"] as? String, "\(name) fix")
        }
    }

    var report: Report {
        var report = Report(space: "morning-review", path: "/Users/example/something/spaces/morning-review.html")
        var declaration = Declaration(name: "morning-review")
        (declaration.title, declaration.agents, declaration.rights) = ("Morning review", .all, ["state", "send:claude"])
        report.declaration = declaration
        report.rights.granted = ["state", "send:claude"]
        report.rights.unavailable = ["launch:omp"]
        report.rights.unknown = ["sendd"]
        report.received = .init(source: "invented", agents: 3, states: ["unknown": 1, "waiting": 1, "working": 1], requests: 1, nullKeys: ["effort", "pid"])
        report.problems = [
            Problem("SCRIPT_ERROR", "ReferenceError: agnets is not defined", where: Where(file: "morning-review.html", line: 12, column: 5)),
            Problem("UNKNOWN_RIGHT", "\"sendd\" is not a right of contract 1."),
            Problem("UNKNOWN_KEY", "\"colour\" is not a declaration key; it is ignored."),
        ]
        report.size = Size(bytes: 48_211, files: 1)
        report.snapshot = "/Users/example/Library/Caches/something-check/morning-review.png"
        report.ms = 480
        return report
    }

    @Test func theHumanOutput() {
        #expect(report.text(home: "/Users/example") == """
            something check morning-review
              space     ~/something/spaces/morning-review.html · 1 file · 48 KB
              rights    state, send:claude · unavailable: launch:omp · unknown: sendd
              received  3 agents (1 working, 1 waiting, 1 unknown), 1 request · invented state
              error     SCRIPT_ERROR morning-review.html:12:5 ReferenceError: agnets is not defined
                        Fix the code at this line; the page stops running at this error.
              warning   UNKNOWN_RIGHT "sendd" is not a right of contract 1.
                        Use one of: state, send, launch, store, optionally with :kind.
              info      UNKNOWN_KEY "colour" is not a declaration key; it is ignored.
                        Remove the key, or check its spelling.
              snapshot  ~/Library/Caches/something-check/morning-review.png
              1 error, 1 warning.

            """)
    }

    @Test func theJsonOutputHasEveryKeyOfTheContract() throws {
        let json = try #require(try JSONSerialization.jsonObject(with: report.json()) as? [String: Any])
        #expect(Set(json.keys) == ["check", "contract", "space", "path", "ok", "errors", "warnings", "declaration", "rights",
                                   "received", "problems", "calls", "console", "size", "snapshot", "journal", "ms"])
        #expect(json["ok"] as? Bool == false && json["errors"] as? Int == 1 && json["warnings"] as? Int == 1)
        #expect(json["journal"] is NSNull)
        let problems = try #require(json["problems"] as? [[String: Any]])
        #expect(problems[0] as NSDictionary == ["code": "SCRIPT_ERROR", "level": "error", "message": "ReferenceError: agnets is not defined",
                                                "fix": "Fix the code at this line; the page stops running at this error.",
                                                "where": ["file": "morning-review.html", "line": 12, "column": 5]])
        #expect(problems[1]["where"] is NSNull)
        let shape = Shape(try ContractFiles.object("shape.json"))
        let declaration = try #require(json["declaration"])
        #expect(shape.problems(declaration, type: "InForce").isEmpty, "\(shape.problems(declaration, type: "InForce"))")
        #expect(json["rights"] as? NSDictionary == ["granted": ["state", "send:claude"], "refused": [], "unavailable": ["launch:omp"], "unknown": ["sendd"]])
    }

    @Test func theExitStatus() {
        var report = Report(space: "x", path: "/Users/example/x.html")
        #expect(report.exitStatus == 0 && report.text(home: "/Users/example").hasSuffix("  0 errors, 0 warnings.\n"))
        report.problems = [Problem("CONSOLE_ERROR", "Invented.")]
        #expect(report.exitStatus == 0)
        report.problems.append(Problem("LOAD_FAILED", "Invented."))
        #expect(report.exitStatus == 1)
        report.problems.append(Problem("NO_WINDOW_SERVER", "Invented."))
        #expect(report.exitStatus == 2 && report.errors == 2)
    }
}
