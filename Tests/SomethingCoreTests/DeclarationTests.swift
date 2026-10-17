// Declaration: every case of share/contract/declarations gives exactly its codes, its declaration in force and its
// unavailable rights; the block is found however its attributes are written; the disk checks (folder, weight) hold.
import Foundation
import Testing
@testable import SomethingCore

@Suite struct DeclarationTests {
    /// Writes a fixture's files as a space under a temporary root, with a home in which its declared folder exists.
    func reading(of fixture: [String: Any], makeFolder: Bool = true) throws -> (DeclarationReading, Space, URL) {
        let root = try temporaryFolder()
        let name = try #require(fixture["name"] as? String), form = try #require(fixture["form"] as? String)
        for (path, text) in try #require(fixture["files"] as? [String: String]) {
            try write(text, form == "file" ? "spaces/\(path)" : "spaces/\(name)/\(path)", under: root)
        }
        let home = root.appendingPathComponent("home")
        let declared = ((fixture["expect"] as? [String: Any])?["declaration"] as? [String: Any])?["folder"] as? String
        if makeFolder, let declared, let path = Declaration.expand(declared, home: home) {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        let space = try #require(Spaces(root: root.appendingPathComponent("spaces")).named(name), "\(name) is not found as a space")
        #expect(space.form.rawValue == form)
        return (Declaration.read(space, home: home), space, root)
    }

    @Test(arguments: ContractFiles.fixtures("declarations"))
    func eachFixtureGivesExactlyItsCodes(_ name: String) throws {
        let fixture = try ContractFiles.object(name)
        let expect = try #require(fixture["expect"] as? [String: Any])
        let (reading, _, root) = try reading(of: fixture)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(reading.problems.map(\.code).sorted() == expect["problems"] as? [String], "\(reading.problems)")
        #expect((reading.declaration != nil) == expect["displays"] as? Bool)
        #expect(reading.unavailable == expect["unavailable"] as? [String])
        if let declaration = reading.declaration {
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(declaration))
            #expect(encoded as? NSDictionary == expect["declaration"] as? NSDictionary, "\(encoded)")
        } else {
            #expect(expect["declaration"] is NSNull)
        }
    }

    @Test func aDeclaredFolderMissingOnThisMacIsAWarning() throws {
        let (reading, _, root) = try reading(of: ContractFiles.object("declarations/full.json"), makeFolder: false)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(reading.problems.map(\.code) == ["FOLDER_MISSING"])
        #expect(reading.declaration?.folder == "~/code/shop")
    }

    @Test func aSpaceOverFiveMegabytesIsTooHeavy() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(#"<script type="application/json" id="something">{"contract": 1}</script>"#, "board/index.html", under: root)
        let space = try #require(Spaces(root: root).named("board"))
        #expect(Declaration.read(space, home: root).problems.isEmpty)
        try Data(count: Size.heavy).write(to: root.appendingPathComponent("board/photo.jpg"))
        #expect(Declaration.read(space, home: root).problems.map(\.code) == ["TOO_HEAVY"])
    }

    @Test func theBlockIsFoundHoweverItIsWritten() {
        let json = #"{"contract": 1, "title": "Found"}"#
        for opening in [
            #"<script type="application/json" id="something">"#,
            #"<script id="something" type="application/json">"#,
            #"<SCRIPT ID='something' TYPE='Application/JSON'>"#,
            "<script\n  id=something\n  type = \"application/json\"\n  data-note=\"x\" >",
        ] {
            let html = "<!doctype html>\n<script>let a = 1;</script>\n\(opening)\n\(json)\n</script >\n<p>Invented.</p>"
            let reading = Declaration.read(html: html, json: nil, name: "notes", page: "notes.html")
            #expect(reading.declaration?.title == "Found", "\(opening)")
            #expect(reading.problems.isEmpty, "\(opening): \(reading.problems)")
        }
        // A script that would run as code is not a declaration, nor is another id.
        for html in [#"<script id="something">{"contract": 1}</script>"#, #"<script type="application/json" id="other">{"contract": 1}</script>"#] {
            #expect(Declaration.read(html: html, json: nil, name: "notes", page: "notes.html").problems.map(\.code) == ["DECLARATION_MISSING"])
        }
    }

    @Test func oddValuesAreWarnedAndReadAsTheDefault() {
        func codes(_ json: String) -> [String] {
            Declaration.read(html: nil, json: Data(json.utf8), name: "x", page: "index.html").problems.map(\.code)
        }
        #expect(codes(#"[1]"#) == ["DECLARATION_UNREADABLE"])
        #expect(codes(#"{"contract": 1.0}"#) == ["CONTRACT_MISSING"])
        #expect(codes(#"{"contract": "1"}"#) == ["CONTRACT_MISSING"])
        #expect(codes(#"{"contract": true}"#) == ["CONTRACT_MISSING"])
        #expect(codes(#"{"contract": 1.5}"#) == ["CONTRACT_TOO_NEW"])
        #expect(codes(#"{"contract": 1, "rights": "state"}"#) == ["UNKNOWN_RIGHT"])
        #expect(codes(#"{"contract": 1, "agents": {"folders": "~/code"}}"#) == ["SCOPE_INVALID"])
        #expect(codes(#"{"contract": 1, "agents": {"folders": ["~/code", "code/shop"]}}"#) == ["SCOPE_INVALID"])
        #expect(codes(#"{"contract": 1, "agents": {"folders": ["~", "~/code", "/Users/example/code"]}}"#).isEmpty)
        func message(_ json: String) -> String? {
            Declaration.read(html: nil, json: Data(json.utf8), name: "x", page: "index.html").problems.first?.message
        }
        #expect(message(#"{"contract": 0}"#) == "contract is 0, not the whole number 1; it is read as 1.")
        #expect(message(#"{"contract": null}"#) == "contract is null, not the whole number 1; it is read as 1.")
        #expect(message(#"{"contract": "1"}"#) == #"contract is "1", not the whole number 1; it is read as 1."#)
        #expect(codes(#"{"contract": 1, "rights": ["state:claude", "send:", "send:gemini", "send:codex", 3]}"#)
                == ["UNKNOWN_RIGHT", "UNKNOWN_RIGHT", "UNKNOWN_RIGHT", "UNKNOWN_RIGHT"])
        let reading = Declaration.read(html: nil, json: Data(#"{"contract": 1, "rights": ["send", "launch:pi", "send:omp"]}"#.utf8),
                                       name: "x", page: "index.html")
        #expect(reading.declaration?.rights == ["send", "launch:pi"] && reading.unavailable == ["send:omp"])
    }

    @Test func aBlockInsideAnHtmlCommentDoesNotCount() {
        let html = #"<!-- <script type="application/json" id="something">{"contract": 1, "title": "Old"}</script> -->"#
        #expect(Declaration.read(html: html, json: nil, name: "notes", page: "notes.html").problems.map(\.code) == ["DECLARATION_MISSING"])
        let after = html + #"<script type="application/json" id="something">{"contract": 1, "title": "New"}</script>"#
        #expect(Declaration.read(html: after, json: nil, name: "notes", page: "notes.html").declaration?.title == "New")
    }

    @Test func aRelativeFolderIsSaidToBeRelative() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(#"<script type="application/json" id="something">{"contract": 1, "folder": "code/shop"}</script>"#, "notes.html", under: root)
        let problems = Declaration.read(try #require(Spaces(root: root).named("notes")), home: root).problems
        #expect(problems.map(\.code) == ["FOLDER_MISSING"])
        #expect(problems.first?.message == "folder is code/shop: it must be absolute or start with ~, for example ~/code/shop.")
    }

    @Test func aPageThatCannotBeReadIsNotSaidToHaveNoBlock() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(#"<script type="application/json" id="something">{"contract": 1}</script>"#, "notes.html", under: root)
        let page = root.appendingPathComponent("notes.html")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: page.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: page.path) }
        let problems = Declaration.read(try #require(Spaces(root: root).named("notes")), home: root).problems
        #expect(problems.map(\.code) == ["DECLARATION_MISSING"])
        #expect(problems.first?.message.hasPrefix("notes.html could not be read (") == true, "\(problems)")
    }

    @Test func pathsExpandFromHome() {
        let home = URL(fileURLWithPath: "/Users/example")
        #expect(Declaration.expand("~", home: home) == "/Users/example")
        #expect(Declaration.expand("~/code/shop", home: home) == "/Users/example/code/shop")
        #expect(Declaration.expand("/Users/example/code", home: home) == "/Users/example/code")
        #expect(Declaration.expand("code/shop", home: home) == nil)
    }
}
