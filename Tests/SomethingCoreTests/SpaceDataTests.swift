// The memory and the journal: paths, removal, the 5 MB limit that leaves the file as it was, a broken file never
// overwritten, the journal's cut text, its last lines and its rotation past 1 MB. All in temporary folders.
import Foundation
import Testing
@testable import SomethingCore

@Suite struct SpaceDataTests {
    @Test func pathsGetAndSetInsideTheDocument() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let memory = Memory(folder: folder.appendingPathComponent("data"), space: "notes")
        #expect(try memory.get("") as? NSDictionary == [:])
        #expect(try memory.get("a/b") == nil)

        try memory.set("settings/theme", "dark")
        try memory.set("seen", ["a1", "a2"])
        #expect(try memory.get("settings/theme") as? String == "dark")
        #expect(try memory.get("settings") as? NSDictionary == ["theme": "dark"])
        #expect(try memory.get("seen/0") == nil)
        #expect(try memory.get("") as? NSDictionary == ["settings": ["theme": "dark"], "seen": ["a1", "a2"]])

        try memory.set("settings/theme", NSNull())
        try memory.set("never/there", NSNull())
        #expect(try memory.get("") as? NSDictionary == ["settings": [:], "seen": ["a1", "a2"]])
        try memory.set("", ["fresh": true])
        #expect(try memory.get("") as? NSDictionary == ["fresh": true])
        try memory.set("", NSNull())
        #expect(try memory.get("") as? NSDictionary == [:])
        #expect(try JSONSerialization.jsonObject(with: Data(contentsOf: memory.file)) as? NSDictionary == [:])
    }

    @Test func badPathsAndValuesAreBadParams() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let memory = Memory(folder: folder, space: "notes")
        try memory.set("name", "Invented")
        for (path, value) in [("a//b", "x" as Any), ("a/", "x"), ("name/first", "x"), ("", "x"), ("n", Double.nan)] {
            #expect(throws: CodedError.self, "\(path)") { try memory.set(path, value) }
            do { try memory.set(path, value) } catch let error as CodedError { #expect(error.code == "BAD_PARAMS") }
        }
        #expect(throws: CodedError.self) { try memory.get("a//b") }
    }

    @Test func pastFiveMegabytesTheStoreIsFullAndTheFileIsUnchanged() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let memory = Memory(folder: folder, space: "notes")
        try memory.set("small", "Invented.")
        let before = try Data(contentsOf: memory.file)
        #expect(throws: CodedError("STORE_FULL", "The memory would weigh 5.0 MB; the limit is 5 MB.")) {
            try memory.set("big", String(repeating: "x", count: Memory.limit))
        }
        #expect(try Data(contentsOf: memory.file) == before)
        // The atomic write leaves no temporary file next to the memory.
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["notes.json"])
        try memory.set("big", String(repeating: "x", count: Memory.limit - 100))
    }

    @Test func aBrokenMemoryIsNeverOverwritten() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let memory = Memory(folder: folder, space: "notes")
        try Data("{ not json".utf8).write(to: memory.file)
        #expect(throws: SpaceError.self) { try memory.get("") }
        #expect(throws: SpaceError.self) { try memory.set("a", 1) }
        #expect(try String(contentsOf: memory.file, encoding: .utf8) == "{ not json")
    }

    @Test func theJournalKeepsLinesAndCutsText() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = Journal(folder: folder.appendingPathComponent("journal"))
        #expect(try journal.last(10, space: "notes").isEmpty)
        let long = String(repeating: "é", count: Journal.characters + 5)
        try journal.append(JournalLine(at: "2026-10-17T09:00:02Z", action: "send", agent: "a1", kind: "claude", when: "next", text: long, result: "ok"), space: "notes")
        try journal.append(JournalLine(at: "2026-10-17T09:00:03Z", action: "open", result: "REFUSED"), space: "notes")
        let lines = try journal.last(10, space: "notes")
        #expect(lines.count == 2 && lines[0].text?.count == Journal.characters && lines[1].result == "REFUSED")
        #expect(try journal.last(1, space: "notes") == [lines[1]])
        let written = try String(contentsOf: journal.file("notes"), encoding: .utf8).split(separator: "\n")
        #expect(written.last == #"{"action":"open","at":"2026-10-17T09:00:03Z","result":"REFUSED"}"#)
    }

    @Test func pastOneMegabyteTheJournalKeepsItsNewestHalf() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = Journal(folder: folder)
        let text = String(repeating: "x", count: 1_900)
        var rotated = false
        for n in 0..<700 {
            try journal.append(JournalLine(at: "2026-10-17T09:00:00Z", action: "send", agent: "a\(n)", text: text, result: "ok"), space: "notes")
            let size = try FileManager.default.attributesOfItem(atPath: journal.file("notes").path)[.size] as! Int
            #expect(size <= Journal.limit)
            if size < Journal.limit / 2 + 2_000, n > 400 { rotated = true }
        }
        #expect(rotated)
        let data = try Data(contentsOf: journal.file("notes"))
        let lines = data.split(separator: UInt8(ascii: "\n"))
        // Every line kept is whole, and the newest one is last.
        #expect(lines.allSatisfy { (try? JSONDecoder().decode(JournalLine.self, from: Data($0))) != nil })
        #expect(try journal.last(1, space: "notes").first?.agent == "a699")
    }
}
