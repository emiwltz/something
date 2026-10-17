// Spaces: both forms are listed and located, names follow the rule, the stamp follows every visible file, the weight
// is counted, and `new` copies the template. Everything happens in a temporary folder.
import Foundation
import Testing
@testable import SomethingCore

/// A new empty folder under the system's temporary folder; the caller removes it.
func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("something-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// Writes `text` at `path` under `root`, making the folders on the way.
func write(_ text: String, _ path: String, under root: URL) throws {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

@Suite struct SpacesTests {
    @Test func bothFormsAreListedAndOthersAreNot() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("<p>Invented.</p>", "notes.html", under: root)
        try write("<p>Invented.</p>", "board/index.html", under: root)
        try write("<p>Invented.</p>", "both.html", under: root)
        try write("<p>Invented.</p>", "both/index.html", under: root)
        try write("<p>No index.</p>", "empty/page.html", under: root)
        try write("<p>An index that is a folder.</p>", "odd/index.html/page.html", under: root)
        try write("<p>Bad name.</p>", "My Notes.html", under: root)
        try write("<p>Bad name.</p>", "Upper.html", under: root)
        try write("hidden", ".DS_Store", under: root)
        try write("not a page", "readme.txt", under: root)
        let spaces = Spaces(root: root)
        #expect(spaces.list().map(\.name) == ["board", "both", "notes"])
        #expect(spaces.named("notes") == Space(name: "notes", form: .file, location: root.appendingPathComponent("notes.html")))
        #expect(spaces.named("board")?.page == root.appendingPathComponent("board/index.html"))
        #expect(spaces.named("both")?.form == .folder)
        #expect(spaces.named("empty") == nil && spaces.named("odd") == nil && spaces.named("Upper") == nil && spaces.named("../notes") == nil)
        #expect(Spaces(root: root.appendingPathComponent("nowhere")).list().isEmpty)
    }

    @Test func theNameRule() {
        for name in ["notes", "morning-review", "a1", "2026"] { #expect(Spaces.isName(name), "\(name)") }
        for name in ["", "Notes", "my notes", "notes.html", "a_b", "../x", "café"] { #expect(!Spaces.isName(name), "\(name)") }
    }

    @Test func aSpaceIsLocatedByNameOrPath() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("<p>Invented.</p>", "notes.html", under: root)
        try write("<p>Invented.</p>", "elsewhere/My Board/index.html", under: root)
        let spaces = Spaces(root: root)
        #expect(spaces.locate("notes")?.form == .file)
        #expect(spaces.locate(root.appendingPathComponent("notes.html").path)?.name == "notes")
        let board = spaces.locate(root.appendingPathComponent("elsewhere/My Board").path)
        #expect(board?.form == .folder && board?.name == "My Board")
        #expect(spaces.locate("missing") == nil)
        #expect(spaces.locate(root.appendingPathComponent("elsewhere").path) == nil)
        #expect(spaces.locate(root.appendingPathComponent("missing.html").path) == nil)
    }

    @Test func theStampFollowsEveryVisibleFileAndTheSizeCountsThem() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("<p>Invented.</p>", "board/index.html", under: root)
        try write("<svg/>", "board/img/logo.svg", under: root)
        try write("hidden", "board/.cache/big", under: root)
        try write("hidden", "board/.notes", under: root)
        let space = try #require(Spaces(root: root).named("board"))
        #expect(space.files().map(\.path) == ["img/logo.svg", "index.html"])
        #expect(space.size() == Size(bytes: 22, files: 2))

        let set = { (path: String, seconds: TimeInterval) in
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: seconds)],
                                                  ofItemAtPath: root.appendingPathComponent(path).path)
        }
        try set("board/index.html", 1_800_000_000)
        try set("board/img/logo.svg", 1_800_000_100)
        try set("board/.notes", 1_900_000_000)
        #expect(space.stamp() == Date(timeIntervalSince1970: 1_800_000_100))
        try set("board/img/logo.svg", 1_800_000_200)
        #expect(space.stamp() == Date(timeIntervalSince1970: 1_800_000_200))
    }

    @Test func newCopiesTheTemplateAndRefusesBadOrTakenNames() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let template = ContractFiles.root.appendingPathComponent("share/template.html")
        let spaces = Spaces(root: root.appendingPathComponent("spaces"))
        let space = try spaces.new("morning-review", from: template)
        #expect(space.form == .file && space.name == "morning-review")
        #expect(try Data(contentsOf: space.location) == Data(contentsOf: template))
        #expect(spaces.list().map(\.name) == ["morning-review"])

        #expect(throws: SpaceError.self) { try spaces.new("morning-review", from: template) }
        #expect(throws: SpaceError.self) { try spaces.new("Morning Review", from: template) }
        try write("<p>Invented.</p>", "spaces/board/index.html", under: root)
        #expect(throws: SpaceError.self) { try spaces.new("board", from: template) }
        #expect(throws: SpaceError.self) { try spaces.new("other", from: root.appendingPathComponent("missing.html")) }
        #expect(spaces.named("other") == nil)
    }

    @Test func newMakesAFolderSpaceWhenAsked() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let template = ContractFiles.root.appendingPathComponent("share/template.html")
        let spaces = Spaces(root: root.appendingPathComponent("spaces"))
        let space = try spaces.new("garden", from: template, folder: true)
        #expect(space == spaces.named("garden"))
        #expect(space.form == .folder && space.page.lastPathComponent == "index.html")
        #expect(try Data(contentsOf: space.page) == Data(contentsOf: template))
        #expect(throws: SpaceError.self) { try spaces.new("garden", from: template) }
        // A template that cannot be read leaves no empty folder holding the name.
        #expect(throws: SpaceError.self) { try spaces.new("other", from: root.appendingPathComponent("missing.html"), folder: true) }
        #expect(!FileManager.default.fileExists(atPath: spaces.root.appendingPathComponent("other").path))
    }

    @Test func sizesReadAsFinderWritesThem() {
        #expect(Size.words(812) == "812 bytes")
        #expect(Size.words(48_211) == "48 KB")
        #expect(Size.words(6_240_000) == "6.2 MB")
    }
}
