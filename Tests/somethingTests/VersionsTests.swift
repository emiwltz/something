// Each space's past, in a throwaway home: a content kept once however many versions hold it, nothing taken when
// nothing changed, a file space and a folder space restored, the files a version did not have sent to the test's own
// Trash, the limits (versions per space, the storage limit) dropping the oldest first and never a space's latest, a space
// too heavy refused in words, and the summaries of what changed. Nothing reaches the person's Trash.
import Foundation
import SomethingCore
import Testing
@testable import something

@Suite(.leavesNothing("something-versions-")) struct VersionsTests {
    /// The store of `test`'s home with `keep` versions per space and `limit` bytes in all.
    func store(_ test: Home, keep: Int = 50, limit: Int = 500_000_000) -> Versions {
        Versions(root: test.places.versions, keep: keep, limit: limit)
    }

    /// A folder space `name` of `test`'s home holding `files`, by path.
    func folder(_ test: Home, _ name: String, _ files: [String: String]) throws -> Space {
        let location = test.places.spaces.appendingPathComponent(name)
        for (path, text) in files {
            let url = location.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return try #require(Spaces(root: test.places.spaces).named(name))
    }

    func blobs(_ store: Versions, _ name: String) throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: store.folder(name).appendingPathComponent("blobs").path).count
    }

    @Test func theVersionsLiveInTheEnginesFolderNeverInTheSpaces() {
        let places = Places(home: URL(fileURLWithPath: "/Users/example"))
        #expect(places.versions.path == "/Users/example/Library/Application Support/something/versions")
    }

    @Test func anUnchangedFileIsStoredOnceAndNothingIsTakenWhenNothingChanged() throws {
        let test = Home(prefix: "something-versions-")
        defer { test.remove() }
        let space = try folder(test, "board", ["index.html": "<p>An invented board.</p>\n", "style.css": "p { color: teal; }\n"])
        let versions = store(test)
        let first = try #require(try versions.capture(space, kind: .turn, sentence: "Make me a board", who: "Claude Code"))
        #expect(first.summary == "2 files" && first.files.count == 2)
        #expect(try versions.capture(space, kind: .outside) == nil, "the same files are no new version")
        try "<p>An invented board.</p>\n<p>A second line.</p>\n".write(to: space.location.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let second = try #require(try versions.capture(space, kind: .turn, sentence: "Add a line", who: "Claude Code"))
        #expect(second.summary == "index.html · one line added")
        #expect(second.files["style.css"] == first.files["style.css"])
        #expect(try blobs(versions, "board") == 3, "style.css is kept once for both versions")
        #expect(versions.list("board").map(\.sentence) == ["Add a line", "Make me a board"], "newest first")
        #expect(versions.weight("board").versions == 2)
    }

    @Test func aFileSpaceIsRestoredAndTheRestoreIsAVersion() throws {
        let test = Home(prefix: "something-versions-")
        defer { test.remove() }
        let space = try test.space("today", "<p>Morning</p>\n")
        let versions = store(test)
        let morning = try #require(try versions.capture(space, kind: .turn, sentence: "Say morning", who: "Codex"))
        try "<p>Evening</p>\n".write(to: space.location, atomically: true, encoding: .utf8)
        try versions.capture(space, kind: .turn, sentence: "Say evening", who: "Codex")
        let restore = try #require(try versions.restore(morning.id, of: space, recycle: { _ in Issue.record("nothing to trash") }))
        #expect(try String(contentsOf: space.location, encoding: .utf8) == "<p>Morning</p>\n")
        #expect(restore.kind == .restore && restore.restored == morning.id && restore.who == "You" && restore.sentence == nil)
        #expect(restore.summary == "today.html · one line changed")
        #expect(versions.list("today").map(\.kind) == [.restore, .turn, .turn])
        #expect(try versions.restore(morning.id, of: space, recycle: { _ in }) == nil, "already that version")
    }

    @Test func aFolderSpaceIsRestoredItsAddedFileTrashedAndAnUnclaimedEditKept() throws {
        let test = Home(prefix: "something-versions-")
        defer { test.remove() }
        let space = try folder(test, "board", ["index.html": "<p>One</p>\n", "parts/a.js": "let a = 1\n"])
        let versions = store(test)
        let first = try #require(try versions.capture(space, kind: .turn, sentence: "Make me a board", who: "Claude Code"))
        try "<p>Two</p>\n".write(to: space.location.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: space.location.appendingPathComponent("parts"))
        try "let b = 2\n".write(to: space.location.appendingPathComponent("b.js"), atomically: true, encoding: .utf8)
        var trashed: [String] = []
        let trash = test.root.appendingPathComponent("Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try versions.restore(first.id, of: space, recycle: { url in
            trashed.append(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
        })
        #expect(trashed == ["b.js"], "the file the version did not have goes to the Trash, never deleted")
        #expect(space.files().map(\.path) == ["index.html", "parts/a.js"])
        #expect(try String(contentsOf: space.location.appendingPathComponent("parts/a.js"), encoding: .utf8) == "let a = 1\n")
        let kept = versions.list("board")
        #expect(kept.map(\.kind) == [.restore, .outside, .turn], "the edit no turn claimed was kept before the restore")
        #expect(kept[1].summary == "b.js · new file; index.html · one line changed; parts/a.js · removed")
    }

    @Test func anIncompleteVersionRestoresNothing() throws {
        let test = Home(prefix: "something-versions-")
        defer { test.remove() }
        let space = try test.space("today", "<p>Morning</p>\n")
        let versions = store(test)
        let morning = try #require(try versions.capture(space, kind: .turn, sentence: "Say morning"))
        try "<p>Evening</p>\n".write(to: space.location, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: versions.folder("today").appendingPathComponent("blobs"))
        #expect(throws: SpaceError.self) { try versions.restore(morning.id, of: space, recycle: { _ in }) }
        #expect(try String(contentsOf: space.location, encoding: .utf8) == "<p>Evening</p>\n")
        #expect(throws: SpaceError.self) { try versions.restore("gone", of: space, recycle: { _ in }) }
    }

    @Test func pruningKeepsTheNewestWithinTheCountAndTheStorageLimit() throws {
        let test = Home(prefix: "something-versions-")
        defer { test.remove() }
        let space = try test.space("today", "0")
        let few = store(test, keep: 2)
        for step in 1...4 {
            try String(repeating: "\(step)", count: 1000).write(to: space.location, atomically: true, encoding: .utf8)
            try few.capture(space, kind: .turn, sentence: "Step \(step)")
        }
        #expect(few.list("today").map(\.sentence) == ["Step 4", "Step 3"])
        #expect(try blobs(few, "today") == 2, "a content no version holds is removed")

        // 1000 bytes a version, 2500 in all: the oldest of all go first, across spaces, never a space's latest.
        let other = try test.space("other", "x")
        let small = store(test, keep: 0, limit: 2500)
        try String(repeating: "o", count: 1000).write(to: other.location, atomically: true, encoding: .utf8)
        try small.capture(other, kind: .turn, sentence: "Other")
        #expect(small.list("today").map(\.sentence) == ["Step 4"] && small.list("other").count == 1)
        #expect(small.weight("today").bytes + small.weight("other").bytes == 2000)
        let tiny = store(test, keep: 0, limit: 10)
        tiny.prune()
        #expect(tiny.list("today").count == 1 && tiny.list("other").count == 1, "a space's latest version is never dropped")
    }

    @Test func aSpaceTooHeavyIsRefusedInWords() throws {
        let test = Home(prefix: "something-versions-")
        defer { test.remove() }
        let space = try folder(test, "many", Dictionary(uniqueKeysWithValues: (1...Export.most).map { ("f\($0).txt", "\($0)") } + [("index.html", "<p>Many</p>")]))
        #expect {
            try store(test).capture(space, kind: .turn)
        } throws: { error in
            (error as? SpaceError)?.sentence.contains("versions are kept up to 15 MB and 500 files") == true
        }
        #expect(store(test).list("many").isEmpty)
    }

    @Test func theSummariesSayWhatChangedLineByLine() {
        let data = { (text: String) in Data(text.utf8) }
        #expect(Versions.summary(nil, ["brief.html": data("a")]) == "brief.html")
        #expect(Versions.summary(["p.html": data("a\nb\nc")], ["p.html": data("a\nB\nc\nd\ne")]) == "p.html · one line changed, 2 added")
        #expect(Versions.summary(["p.html": data("a\nb\nc")], ["p.html": data("a")]) == "p.html · 2 lines removed")
        #expect(Versions.summary(["i.png": Data([0xff, 0xfe, 0x00])], ["i.png": Data([0xff, 0x00])]) == "i.png · changed")
        let many = Dictionary(uniqueKeysWithValues: (1...5).map { ("f\($0)", data("\($0)")) })
        #expect(Versions.summary([:], many) == "f1 · new file; f2 · new file; f3 · new file; and 2 more files")
    }

    @Test func aTrashedSpaceTakesItsVersions() throws {
        let test = Home(prefix: "something-versions-")
        defer { test.remove() }
        let space = try test.space("today", "<p>Morning</p>")
        let versions = store(test)
        try versions.capture(space, kind: .turn)
        var recycled: [URL] = []
        try versions.trash("today", recycle: { recycled.append($0) })
        try versions.trash("never-versioned", recycle: { recycled.append($0) })
        #expect(recycled == [versions.folder("today")])
    }
}
