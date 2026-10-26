// Each space's past, in a throwaway home: a content kept once however many versions hold it, nothing taken when
// nothing changed, a file space and a folder space restored, the files a version did not have sent to the test's own
// Trash, the limits (versions per space, the storage limit) dropping the oldest first and never a space's latest, a space
// too heavy refused in words yet still restored through the Trash, a version of the other form or a link refused before
// anything is written, an index that does not read never written over, and the summaries of what changed. Nothing
// reaches the person's Trash. History: the choice, its moves and the fold, the rows' words (the oldest kept state never
// an edit on disk), the days as it says them, a picture kept beside its version and dropped with it, and Restore This
// Version refused while the assistant works, then itself a version undone by ⌘Z.
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

    @Test func aVersionOfTheOtherFormRestoresNothing() throws {
        let test = Home(prefix: "something-versions-")
        defer { test.remove() }
        let page = try test.space("today", "<p>Morning</p>\n")
        let versions = store(test)
        let morning = try #require(try versions.capture(page, kind: .turn, sentence: "Say morning"))
        // The page became a folder of the same name: a single page written into it would leave it without index.html.
        try FileManager.default.removeItem(at: page.location)
        let space = try folder(test, "today", ["index.html": "<p>Board</p>\n", "style.css": "p {}\n"])
        #expect {
            try versions.restore(morning.id, of: space, recycle: { _ in Issue.record("nothing to trash") })
        } throws: { error in
            (error as? SpaceError)?.sentence.contains("was a single page; the space is a folder now") == true
        }
        #expect(space.files().map(\.path) == ["index.html", "style.css"])
        #expect(versions.list("today").count == 1, "nothing was taken either")
    }

    @Test func aRestoreNeverWritesThroughALink() throws {
        let test = Home(prefix: "something-versions-")
        defer { test.remove() }
        let space = try folder(test, "board", ["index.html": "<p>One</p>\n", "parts/a.js": "let a = 1\n"])
        let versions = store(test)
        let first = try #require(try versions.capture(space, kind: .turn, sentence: "Make me a board"))
        let elsewhere = test.root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: space.location.appendingPathComponent("parts"))
        try FileManager.default.createSymbolicLink(at: space.location.appendingPathComponent("parts"), withDestinationURL: elsewhere)
        #expect(throws: SpaceError.self) { try versions.restore(first.id, of: space, recycle: { _ in Issue.record("nothing to trash") }) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path).isEmpty, "nothing written outside the space")
    }

    @Test func anIndexThatDoesNotReadIsNeverWrittenOver() throws {
        let test = Home(prefix: "something-versions-")
        defer { test.remove() }
        let space = try test.space("today", "<p>Morning</p>\n")
        let versions = store(test, keep: 1)
        try versions.capture(space, kind: .turn, sentence: "Say morning")
        let index = versions.folder("today").appendingPathComponent("index.json")
        try Data("not json".utf8).write(to: index)
        try "<p>Evening</p>\n".write(to: space.location, atomically: true, encoding: .utf8)
        #expect {
            try versions.capture(space, kind: .turn, sentence: "Say evening")
        } throws: { error in
            (error as? SpaceError)?.sentence.contains("The versions of today do not read") == true
        }
        versions.prune()
        #expect(try String(contentsOf: index, encoding: .utf8) == "not json")
        #expect(try blobs(versions, "today") == 1, "its contents are left whole")
    }

    @Test func aSpaceTooHeavyIsStillRestoredItsChangesSentToTheTrash() throws {
        let test = Home(prefix: "something-versions-")
        defer { test.remove() }
        let space = try folder(test, "many", ["index.html": "<p>Few</p>\n", "a.txt": "a"])
        let versions = store(test)
        let few = try #require(try versions.capture(space, kind: .turn, sentence: "Make it"))
        // An agent filled it past 500 files and changed its page: no version can hold it now.
        for step in 1...Export.most { try "\(step)".write(to: space.location.appendingPathComponent("f\(step).txt"), atomically: true, encoding: .utf8) }
        try "<p>Many</p>\n".write(to: space.location.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let trash = test.root.appendingPathComponent("Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        var trashed: [String] = []
        let restore = try #require(try versions.restore(few.id, of: space, recycle: { url in
            trashed.append(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
        }))
        #expect(space.files().map(\.path).sorted() == ["a.txt", "index.html"])
        #expect(try String(contentsOf: space.location.appendingPathComponent("index.html"), encoding: .utf8) == "<p>Few</p>\n")
        #expect(trashed.count == Export.most + 1 && trashed.contains("index.html") && !trashed.contains("a.txt"), "the changed page and each extra file")
        #expect(try String(contentsOf: trash.appendingPathComponent("index.html"), encoding: .utf8) == "<p>Many</p>\n")
        #expect(restore.kind == .restore && versions.list("many").map(\.kind) == [.restore, .turn])
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
        #expect(try blobs(small, "today") + blobs(small, "other") == 2, "1000 bytes each, 2000 in all")
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

    /// A file space of `test` with `count` versions, 13 hours apart up to `now`: the first kept as it was, then turns,
    /// the fourth an edit no turn claims.
    func history(_ test: Home, now: Date, _ count: Int) throws -> (Space, Versions) {
        let space = try test.space("today", "<p>0</p>\n"), versions = store(test)
        try versions.capture(space, kind: .outside, at: now.addingTimeInterval(-Double(count) * 3_600 * 13))
        for step in 1..<count {
            try "<p>\(step)</p>\n".write(to: space.location, atomically: true, encoding: .utf8)
            let at = now.addingTimeInterval(-Double(count - step) * 3_600 * 13)
            try versions.capture(space, kind: step == 3 ? .outside : .turn, sentence: step == 3 ? nil : "Say \(step)", who: "Claude Code", at: at)
        }
        return (space, versions)
    }

    @Test func historyChoosesTheVersionBeforeTheNewestAndFoldsTheOlderOnes() throws {
        let test = Home(prefix: "something-versions-")
        defer { test.remove() }
        let now = Date()
        let (space, versions) = try history(test, now: now, 9)
        let history = History(places: test.places)
        history.clock = { now }
        history.show(space)
        let all = versions.list("today")
        #expect(history.versions == all && history.chosen == all[1].id && history.restorable && history.bytes > 0)
        #expect(history.rows.count == 6 && history.older?.hasPrefix("3 older versions, back to ") == true)
        // The words: a turn by its sentence, an edit no turn claims, the oldest as something first kept it.
        #expect(history.title(all[0]) == "“Say 8”" && history.byline(all[0]).hasSuffix(" · Claude Code"))
        let edit = try #require(all.first { $0.kind == .outside && $0.id != all.last?.id })
        #expect(history.title(edit) == "Edited outside something" && history.byline(edit).hasSuffix(" · Changed on disk, not by its assistant"))
        let first = try #require(all.last)
        #expect(history.title(first) == "As something first kept it" && history.byline(first).hasSuffix(" · Before its first change here"))
        #expect(!history.byline(first).contains("disk"))
        // ↓ past the sixth unfolds; the moves stop at both ends; the newest cannot be restored over itself.
        history.move(10)
        #expect(history.chosen == first.id && history.unfolded && history.rows.count == 9 && history.older == nil)
        history.move(-20)
        #expect(history.chosen == all[0].id && !history.restorable)
        // The same space read again keeps the choice; another starts over.
        history.move(2)
        history.show(space)
        #expect(history.chosen == all[2].id)
        history.show(nil)
        #expect(history.versions.isEmpty && history.chosen == nil && history.rows.isEmpty)
    }

    @Test func historyOpensBeforeTheNewestAfterATurnAndNamesOnlyTheFirstCaptureAsFirstKept() throws {
        let test = Home(prefix: "something-versions-")
        defer { test.remove() }
        let now = Date()
        let (space, _) = try history(test, now: now, 9)
        let history = History(places: test.places)
        history.show(space)
        // A turn kept while the panel shows chooses the newest; the panel opened again chooses the one before it.
        try "<p>9</p>\n".write(to: space.location, atomically: true, encoding: .utf8)
        try store(test, keep: 7).capture(space, kind: .turn, sentence: "Say 9", who: "Claude Code", at: now)
        history.kept("today")
        #expect(history.chosen == history.versions[0].id && !history.restorable)
        history.opened()
        #expect(history.chosen == history.versions[1].id && history.restorable && !history.unfolded)
        // The first capture pruned, the oldest kept is an edit on disk, said as one.
        let oldest = try #require(history.versions.last)
        #expect(history.versions.count == 7 && oldest.kind == .outside && oldest.first == nil)
        #expect(history.title(oldest) == "Edited outside something" && history.byline(oldest).hasSuffix(" · Changed on disk, not by its assistant"))
    }

    @Test func historySaysTheDaysAsTheMockupDoes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 18, minute: 20)))
        let at = { (day: Int, hour: Int, minute: Int, year: Int) in
            calendar.date(from: DateComponents(year: year, month: 10, day: day, hour: hour, minute: minute)) ?? now
        }
        #expect(History.when(at(22, 18, 12, 2026), now: now, calendar: calendar) == "Today 18:12")
        #expect(History.when(at(21, 21, 5, 2026), now: now, calendar: calendar) == "Yesterday 21:05")
        #expect(History.when(at(20, 11, 2, 2026), now: now, calendar: calendar) == "Tuesday 11:02")
        #expect(History.when(at(19, 9, 20, 2026), now: now, calendar: calendar) == "Monday 09:20")
        #expect(History.when(at(12, 9, 20, 2026), now: now, calendar: calendar) == "12 Oct 09:20")
        #expect(History.when(at(12, 9, 20, 2025), now: now, calendar: calendar) == "12 Oct 2025 09:20")
    }

    @Test func aPictureIsKeptBesideItsVersionAndGoesWithIt() throws {
        let test = Home(prefix: "something-versions-")
        defer { test.remove() }
        let space = try test.space("today", "<p>Morning</p>\n")
        let versions = store(test, keep: 1)
        let morning = try #require(try versions.capture(space, kind: .turn, sentence: "Say morning", who: "Codex"))
        #expect(versions.holds(space, morning))
        try versions.keep(picture: Data([1, 2, 3]), of: morning.id, in: "today")
        #expect(versions.list("today").first?.thumb == "thumbs/\(morning.id).png")
        #expect(FileManager.default.fileExists(atPath: versions.picture("today", morning.id).path))
        #expect(throws: SpaceError.self) { try versions.keep(picture: Data(), of: "gone", in: "today") }
        try "<p>Evening</p>\n".write(to: space.location, atomically: true, encoding: .utf8)
        #expect(!versions.holds(space, morning))
        try versions.capture(space, kind: .turn, sentence: "Say evening", who: "Codex")
        #expect(!FileManager.default.fileExists(atPath: versions.picture("today", morning.id).path), "dropped with its version")
    }

    @Test func restoreThisVersionWaitsForTheAssistantThenIsAVersionUndoneByCommandZ() throws {
        let test = Home(prefix: "something-versions-")
        defer { test.remove() }
        let now = Date()
        let (space, _) = try history(test, now: now, 3)
        let undo = WindowUndo()
        undo.groupsByEvent = false
        let changes = Changes(places: test.places, undo: undo)
        var working = true, said: [(String, String?)] = []
        changes.find = { Spaces(root: test.places.spaces).named($0) }
        changes.title = { _ in "Today" }
        changes.working = { _ in working }
        changes.recycle = { _ in Issue.record("nothing to trash") }
        changes.toast = { words, action, _, _ in said.append((words, action?.label)) }
        let history = History(places: test.places)
        history.clock = { now }
        history.restoring = { changes.bringBack($0, to: $1, words: $2) }
        changes.kept = { history.kept($0) }
        history.show(space)
        let before = history.versions, chosen = before[1]
        undo.beginUndoGrouping()
        history.restore()
        #expect(said.last?.0 == "Today’s assistant is working · restore once it’s done" && history.versions == before)
        #expect(try String(contentsOf: space.location, encoding: .utf8) == "<p>2</p>\n")
        working = false
        history.restore()
        undo.endUndoGrouping()
        let words = "the version of " + History.when(chosen.when, now: now)
        #expect(try String(contentsOf: space.location, encoding: .utf8) == "<p>1</p>\n")
        #expect(history.versions.count == 4 && history.versions[0].kind == .restore && history.versions[0].restored == chosen.id)
        #expect(history.chosen == history.versions[0].id && history.title(history.versions[0]) == "Restored " + words)
        #expect(said.last?.0 == "Restored " + words && said.last?.1 == "Undo ⌘Z")
        #expect(undo.undoMenuItemTitle == "Undo " + Changes.quoted("Restore " + words))
        undo.undo()
        #expect(try String(contentsOf: space.location, encoding: .utf8) == "<p>2</p>\n")
        #expect(history.versions.count == 5 && history.chosen == history.versions[0].id)
    }
}
