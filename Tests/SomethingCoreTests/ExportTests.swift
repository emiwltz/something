// The .something export: each fixture of share/contract/exports read as it says, a file space and a
// folder space through a round trip, every hostile document refused with its code before anything is written, a
// taken name, and a string planted in an invented agent session never reaches an export.
import Foundation
import Testing
@testable import SomethingCore

@Suite struct ExportTests {
    /// A throwaway home: spaces, memory and an agent's session folder under it.
    struct Place {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("something-export-\(UUID().uuidString)")
        var spaces: Spaces { Spaces(root: root.appendingPathComponent("something/spaces")) }
        var data: URL { root.appendingPathComponent("something/data") }

        func write(_ text: String, _ path: String) throws {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        /// Every file under the root, by relative path: what an import left behind.
        var everything: [String] { (FileManager.default.enumerator(atPath: root.path)?.allObjects as? [String] ?? []).sorted() }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    /// A document as an export writes it, with `change` applied to its object.
    func document(_ change: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var object: [String: Any] = ["format": "something-space", "contract": 1, "exported": "2026-10-17T12:00:00Z", "app": "1.0.0",
                                     "name": "notes", "form": "folder", "files": ["index.html": Data("<p>invented</p>".utf8).base64EncodedString()],
                                     "data": NSNull()]
        change(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    /// Places `received` under the name an import gives it.
    func place(_ received: Received, _ place: Place) throws -> Space {
        try Export.place(received, as: try Export.freeName(received, in: place.spaces, memory: place.data), in: place.spaces, memory: place.data)
    }

    func code(_ document: Data) -> String? {
        do { _ = try Export.read(document); return nil } catch { return (error as? CodedError)?.code ?? "\(error)" }
    }

    @Test func eachFixtureIsReadAsItSays() throws {
        let names = ContractFiles.fixtures("exports")
        #expect(names.count >= 5)
        for name in names {
            let fixture = try ContractFiles.object(name)
            let expect = try #require(fixture["expect"] as? [String: Any])
            let document = try JSONSerialization.data(withJSONObject: try #require(fixture["export"]))
            guard expect["ok"] as? Bool == true else {
                #expect(code(document) == expect["code"] as? String, "\(name)")
                continue
            }
            let received = try Export.read(document)
            #expect(received.name == expect["name"] as? String, "\(name)")
            #expect(received.files.keys.sorted() == expect["files"] as? [String], "\(name)")
            #expect(received.data as NSDictionary? == expect["data"] as? NSDictionary, "\(name)")
        }
    }

    @Test func aFileSpaceMakesTheRoundTripWithoutItsData() throws {
        let from = Place(), to = Place()
        defer { from.remove(); to.remove() }
        try from.write("<!doctype html><title>Invented</title>", "something/spaces/morning-review.html")
        try Memory(folder: from.data, space: "morning-review").set("theme", "dark")
        let space = try #require(from.spaces.named("morning-review"))
        let at = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00Z")!
        let document = try Export.document(space, data: nil, app: "1.0.0-test", at: at)
        let object = try #require(try JSONSerialization.jsonObject(with: document) as? [String: Any])
        #expect(object["exported"] as? String == "2026-10-17T12:00:00Z" && object["app"] as? String == "1.0.0-test")
        #expect(object["data"] is NSNull && object["form"] as? String == "file" && object["contract"] as? Int == 1)

        let placed = try place(try Export.read(document), to)
        #expect(placed == to.spaces.named("morning-review"))
        #expect(try Data(contentsOf: placed.location) == Data(contentsOf: space.location))
        #expect(to.everything == ["something", "something/spaces", "something/spaces/morning-review.html"], "no memory, no staging folder left")
    }

    /// The document carries the contract the space declares: an engine that does not know it refuses the import.
    @Test func theContractIsTheOneTheSpaceDeclares() throws {
        let from = Place()
        defer { from.remove() }
        let declared = ["none": "<p>invented</p>", "one": #"<script type="application/json" id="something">{"contract": 1}</script>"#,
                        "two": #"<script type="application/json" id="something">{"contract": 2}</script>"#,
                        "half": #"<script type="application/json" id="something">{"contract": 1.5}</script>"#,
                        "word": #"<script type="application/json" id="something">{"contract": "one"}</script>"#]
        for (name, html) in declared { try from.write(html, "something/spaces/\(name).html") }
        try from.write(#"{"contract": 2}"#, "something/spaces/board/something.json")
        try from.write("<p>invented</p>", "something/spaces/board/index.html")
        for (name, contract) in [("none", 1), ("one", 1), ("two", 2), ("half", 2), ("word", 1), ("board", 2)] {
            let document = try Export.document(try #require(from.spaces.named(name)), data: nil, app: "1.0.0-test")
            let object = try #require(try JSONSerialization.jsonObject(with: document) as? [String: Any])
            #expect(object["contract"] as? Int == contract, "\(name)")
            #expect(code(document) == (contract == 1 ? nil : "IMPORT_TOO_NEW"), "\(name)")
        }
    }

    @Test func aFolderSpaceMakesTheRoundTripWithItsData() throws {
        let from = Place(), to = Place()
        defer { from.remove(); to.remove() }
        try from.write("<!doctype html><img src=img/logo.svg>", "something/spaces/board/index.html")
        try from.write("<svg xmlns=\"http://www.w3.org/2000/svg\"/>", "something/spaces/board/img/logo.svg")
        try from.write("hidden", "something/spaces/board/.notes")
        let memory = Memory(folder: from.data, space: "board")
        try memory.set("seen", ["a1"])
        try memory.set("settings/theme", "dark")
        let space = try #require(from.spaces.named("board"))
        let data = try #require(try memory.get("") as? [String: Any])

        let received = try Export.read(try Export.document(space, data: data, app: "1.0.0-test"))
        #expect(received.files.keys.sorted() == ["img/logo.svg", "index.html"], "a hidden file is not part of the space")
        let placed = try place(received, to)
        #expect(placed.form == .folder && placed.files().map(\.path) == ["img/logo.svg", "index.html"])
        for file in space.files() { #expect(try Data(contentsOf: placed.location.appendingPathComponent(file.path)) == Data(contentsOf: file.url)) }
        #expect(try Memory(folder: to.data, space: "board").get("") as? NSDictionary == data as NSDictionary)
    }

    @Test func aFileSpaceMakesTheRoundTripWithItsData() throws {
        let from = Place(), to = Place()
        defer { from.remove(); to.remove() }
        try from.write("<!doctype html><title>Invented</title>", "something/spaces/today.html")
        try Memory(folder: from.data, space: "today").set("done", ["Water the invented plant"])
        let space = try #require(from.spaces.named("today"))
        let data = try #require(try Export.memory("today", in: from.data))
        let placed = try place(try Export.read(try Export.document(space, data: data, app: "1.0.0-test")), to)
        #expect(placed.form == .file && placed.name == "today")
        #expect(try Data(contentsOf: placed.location) == Data(contentsOf: space.location))
        #expect(try Memory(folder: to.data, space: "today").get("done") as? [String] == ["Water the invented plant"])
        #expect(try Export.memory("nothing", in: from.data) == nil, "no memory: nothing to carry")
    }

    @Test func anExportTooBigOrWithTooManyFilesIsRefusedBeforeItIsSaved() throws {
        let place = Place()
        defer { place.remove() }
        try place.write("<p>invented</p>", "something/spaces/many/index.html")
        for index in 1...500 { try place.write("// \(index)", "something/spaces/many/f\(index).js") }
        #expect(throws: SpaceError.self) { try Export.document(try #require(place.spaces.named("many")), data: nil, app: "1.0.0-test") }

        try place.write("<p>invented</p>", "something/spaces/heavy/index.html")
        // 15.1 MB of files weigh over 20 MB in base64.
        try Data(count: 15_100_000).write(to: place.spaces.root.appendingPathComponent("heavy/video.bin"))
        #expect(throws: SpaceError.self) { try Export.document(try #require(place.spaces.named("heavy")), data: nil, app: "1.0.0-test") }
    }

    @Test func everyHostileDocumentIsRefusedWithItsReason() throws {
        let x = Data("x".utf8).base64EncodedString()
        let cases: [(String, Data)] = [
            ("IMPORT_NOT_A_SPACE", Data("not json".utf8)),
            ("IMPORT_NOT_A_SPACE", try document { $0["format"] = "something-else" }),
            ("IMPORT_NOT_A_SPACE", try document { $0["contract"] = "1" }),
            ("IMPORT_NOT_A_SPACE", try document { $0["name"] = "../notes" }),
            ("IMPORT_NOT_A_SPACE", try document { $0["form"] = "zip" }),
            ("IMPORT_NOT_A_SPACE", try document { $0["files"] = ["logo.svg": x] }),
            ("IMPORT_NOT_A_SPACE", try document { $0["form"] = "file"; $0["files"] = ["notes.html": x, "more.js": x] }),
            ("IMPORT_NOT_A_SPACE", try document { $0["files"] = ["index.html": "not base64!"] }),
            ("IMPORT_NOT_A_SPACE", try document { $0["data"] = ["a", "list"] }),
            ("IMPORT_TOO_NEW", try document { $0["contract"] = 2 }),
            ("IMPORT_UNSAFE_PATH", try document { $0["files"] = ["index.html": x, "/Users/example/.zshrc": x] }),
            ("IMPORT_UNSAFE_PATH", try document { $0["files"] = ["index.html": x, "img/../../outside.html": x] }),
            ("IMPORT_UNSAFE_PATH", try document { $0["files"] = ["index.html": x, "img//logo.svg": x] }),
            ("IMPORT_UNSAFE_PATH", try document { $0["files"] = ["index.html": x, "./index.html": x] }),
            ("IMPORT_UNSAFE_PATH", try document { $0["files"] = ["index.html": x, "img/": x] }),
            ("IMPORT_UNSAFE_PATH", try document { $0["files"] = ["index.html": x, "": x] }),
            ("IMPORT_UNSAFE_PATH", try document { $0["files"] = ["index.html": x, ".git/config": x] }),
            ("IMPORT_UNSAFE_PATH", try document { $0["files"] = ["index.html": x, "img/.hidden.js": x] }),
            ("IMPORT_TOO_BIG", try document { object in
                object["files"] = Dictionary(uniqueKeysWithValues: (0...500).map { ("f\($0).js", x) }) }),
            ("IMPORT_TOO_BIG", Data(count: Export.limit + 1)),
        ]
        for (expected, document) in cases { #expect(code(document) == expected, "\(String(decoding: document.prefix(300), as: UTF8.self))") }
        #expect(cases.allSatisfy { Codes.all[$0.0]?.from == "import" })
    }

    @Test func aTakenNameGetsANumberAndAMemoryOverTheLimitLeavesNothing() throws {
        let place = Place()
        defer { place.remove() }
        try place.write("<p>mine</p>", "something/spaces/notes/index.html")
        try place.write("{\"kept\": true}", "something/data/notes-2.json")
        let placed = try self.place(try Export.read(try document()), place)
        #expect(placed.name == "notes-3", "notes is a space, and notes-2 a memory left behind: neither is taken over")
        #expect(try String(contentsOf: place.root.appendingPathComponent("something/spaces/notes/index.html"), encoding: .utf8) == "<p>mine</p>")

        let before = place.everything
        let heavy = try Export.read(try document { $0["data"] = ["text": String(repeating: "a", count: Memory.limit)] })
        #expect(throws: CodedError.self) { try self.place(heavy, place) }
        #expect(place.everything == before)
        #expect(throws: SpaceError.self, "a name taken in the meantime") { try Export.place(heavy, as: "notes", in: place.spaces, memory: place.data) }
    }

    /// Criterion 7: a space can link to an agent's session, but nothing of the session reaches its export.
    @Test func aStringPlantedInAnAgentSessionNeverReachesAnExport() throws {
        let place = Place()
        defer { place.remove() }
        let planted = "planted-7f3c invented line of a session"
        let session = ".claude/projects/-Users-example-code-shop/0a1b2c3d-invented.jsonl"
        try place.write("{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"\(planted)\"}}\n", session)
        try place.write("<!doctype html><title>Board</title>", "something/spaces/board/index.html")
        let folder = place.spaces.root.appendingPathComponent("board")
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("session.jsonl"),
                                                   withDestinationURL: place.root.appendingPathComponent(session))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("claude"),
                                                   withDestinationURL: place.root.appendingPathComponent(".claude"))
        try Memory(folder: place.data, space: "board").set("seen", ["a1"])

        let space = try #require(place.spaces.named("board"))
        let data = try #require(try Export.memory("board", in: place.data))
        let document = try Export.document(space, data: data, app: "1.0.0-test")
        let received = try Export.read(document)
        #expect(received.files.keys.sorted() == ["index.html"])
        #expect(Export.links(space) == ["claude", "session.jsonl"], "what was left out can be named")
        let everything = [document] + Array(received.files.values) + [try JSONSerialization.data(withJSONObject: received.data ?? [:])]
        for bytes in everything { #expect(!String(decoding: bytes, as: UTF8.self).contains("planted-7f3c")) }

        // A single-file space that is a link to the session is refused, not followed.
        try FileManager.default.createSymbolicLink(at: place.spaces.root.appendingPathComponent("linked.html"),
                                                   withDestinationURL: place.root.appendingPathComponent(session))
        let linked = try #require(place.spaces.named("linked"))
        #expect(throws: SpaceError.self) { try Export.document(linked, data: nil, app: "1.0.0-test") }

        // A folder space whose index.html is a link to the session is refused too.
        try place.write("<p>invented</p>", "something/spaces/relay/style.css")
        try FileManager.default.createSymbolicLink(at: place.spaces.root.appendingPathComponent("relay/index.html"),
                                                   withDestinationURL: place.root.appendingPathComponent(session))
        let relay = try #require(place.spaces.named("relay"))
        #expect(throws: SpaceError.self) { try Export.document(relay, data: nil, app: "1.0.0-test") }

        // A memory that is a link to an agent's file (an invented ~/.claude.json) is refused, not read.
        try place.write("{\"projects\": {\"note\": \"\(planted)\"}}", ".claude.json")
        try FileManager.default.createSymbolicLink(at: place.data.appendingPathComponent("relay.json"),
                                                   withDestinationURL: place.root.appendingPathComponent(".claude.json"))
        #expect(throws: SpaceError.self) { try Export.memory("relay", in: place.data) }
    }
}
