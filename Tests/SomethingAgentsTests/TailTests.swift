// Tail: following a JSONL file as a harness writes it, with invented lines. The long case builds a 200 MB file with
// a 12 MB line in a throwaway folder: its first read must stay within 4 MB, and the whole case within 64 MB of memory.
import Darwin
import Foundation
import Testing
@testable import SomethingAgents

@Suite(.serialized) struct TailTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tail-\(UUID().uuidString)")
    static let wanted = [Data(#""type":"message""#.utf8)]

    init() throws { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }

    func file(_ name: String = "session.jsonl") -> String { folder.appendingPathComponent(name).path }

    func line(_ n: Int, type: String = "message") -> String { #"{"type":"\#(type)","text":"Invented line \#(n)."}"# + "\n" }

    func append(_ text: String, to path: String) throws {
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        handle.seekToEndOfFile()
        handle.write(Data(text.utf8))
        try handle.close()
    }

    func texts(_ read: Tail.Read?) -> [String] { (read?.lines ?? []).map { String(decoding: $0, as: UTF8.self) } }

    @Test func newLinesAreFollowedAndFilteredBeforeDecoding() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = file()
        try (line(1) + line(2, type: "noise") + line(3)).write(toFile: path, atomically: false, encoding: .utf8)
        let first = try #require(Tail.read(path, after: nil, containing: TailTests.wanted))
        #expect(first.fresh && texts(first) == [line(1), line(3)].map { String($0.dropLast()) })
        // A line still being written is left for the next read.
        try append(line(4) + #"{"type":"message","text":"Invented, unfin"#, to: path)
        let second = try #require(Tail.read(path, after: first.cursor, containing: TailTests.wanted))
        #expect(!second.fresh && texts(second) == [String(line(4).dropLast())])
        try append("ished.\"}\n", to: path)
        let third = try #require(Tail.read(path, after: second.cursor, containing: TailTests.wanted))
        #expect(texts(third) == [#"{"type":"message","text":"Invented, unfinished."}"#])
        let nothing = try #require(Tail.read(path, after: third.cursor, containing: TailTests.wanted))
        #expect(!nothing.fresh && nothing.lines.isEmpty)
        #expect(Tail.read(file("missing.jsonl"), after: nil, containing: TailTests.wanted) == nil)
    }

    @Test func aReplacedCutOrRewrittenFileIsReadAgain() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = file()
        try (line(1) + line(2)).write(toFile: path, atomically: false, encoding: .utf8)
        let first = try #require(Tail.read(path, after: nil, containing: TailTests.wanted))
        // Cut shorter.
        try line(9).write(toFile: path, atomically: false, encoding: .utf8)
        let cut = try #require(Tail.read(path, after: first.cursor, containing: TailTests.wanted))
        #expect(cut.fresh && texts(cut) == [String(line(9).dropLast())])
        // Its first bytes rewritten in place, as long as before (a title slot).
        try line(8).write(toFile: path, atomically: false, encoding: .utf8)
        let rewritten = try #require(Tail.read(path, after: cut.cursor, containing: TailTests.wanted))
        #expect(rewritten.fresh && texts(rewritten) == [String(line(8).dropLast())])
        // Replaced by another file (a new inode), longer.
        try (line(8) + line(7)).write(toFile: path, atomically: true, encoding: .utf8)
        let replaced = try #require(Tail.read(path, after: rewritten.cursor, containing: TailTests.wanted))
        #expect(replaced.fresh && replaced.lines.count == 2)
    }

    @Test func aFirstReadTakesTheEndAndWidensWhenAskedTo() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = file()
        // 1 MB of lines nobody wants, after one wanted line.
        let noise = String(repeating: line(0, type: "noise"), count: 1_048_576 / line(0, type: "noise").utf8.count)
        try (line(1) + noise).write(toFile: path, atomically: false, encoding: .utf8)
        let narrow = try #require(Tail.read(path, after: nil, containing: TailTests.wanted, enough: { _ in true }))
        #expect(narrow.lines.isEmpty && narrow.bytes <= Tail.window + Tail.headSize)
        let wide = try #require(Tail.read(path, after: nil, containing: TailTests.wanted))
        #expect(texts(wide) == [String(line(1).dropLast())], "widened to 4 MB, which holds the whole file")
    }

    /// 200 MB with a 12 MB line near the end: the first read takes at most 4 MB, the long line is never handed over
    /// (nor decoded), and memory grows by less than 64 MB.
    @Test func aLargeFileWithAHugeLine() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = file()
        FileManager.default.createFile(atPath: path, contents: nil)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        let block = Data(String(repeating: line(0), count: 1_048_576 / line(0).utf8.count).utf8)
        for _ in 0..<188 { handle.write(block) }
        let huge = Data(#"{"type":"message","text":""#.utf8) + Data(repeating: UInt8(ascii: "x"), count: 12 * 1_048_576) + Data("\"}\n".utf8)
        handle.write(huge)
        handle.write(Data(line(1).utf8))
        try handle.close()
        #expect(try FileManager.default.attributesOfItem(atPath: path)[.size] as! Int > 200_000_000)

        let peak = Peak()
        let first = try #require(Tail.read(path, after: nil, containing: TailTests.wanted, enough: { _ in false }))
        #expect(first.bytes <= Tail.widest + Tail.headSize, "\(first.bytes) bytes read")
        #expect(texts(first) == [String(line(1).dropLast())], "the end of the long line is dropped")
        // Then 12 MB more in one line, and a short one: the long line is skipped, the short one read.
        let appending = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        appending.seekToEndOfFile()
        appending.write(huge)
        appending.write(Data(line(2).utf8))
        try appending.close()
        let next = try #require(Tail.read(path, after: first.cursor, containing: TailTests.wanted))
        #expect(next.bytes <= Tail.widest + Tail.headSize)
        #expect(texts(next) == [String(line(2).dropLast())])
        #expect(next.lines.allSatisfy { $0.count <= Tail.widest })
        let grown = peak.stop()
        #expect(grown < 64 * 1_048_576, "memory grew by \(grown / 1_048_576) MB at most")
    }

    @Test func aLineGivenUpOnIsSkippedToItsEnd() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = file()
        try line(1).write(toFile: path, atomically: false, encoding: .utf8)
        let first = try #require(Tail.read(path, after: nil, containing: TailTests.wanted))
        // A line that grows past 4 MB before it ends, read while it grows.
        try append(#"{"type":"message","text":""# + String(repeating: "x", count: Tail.widest + 10), to: path)
        let growing = try #require(Tail.read(path, after: first.cursor, containing: TailTests.wanted))
        #expect(growing.lines.isEmpty && growing.cursor.skipping)
        try append(String(repeating: "x", count: 1000) + "\"}\n" + line(2), to: path)
        let after = try #require(Tail.read(path, after: growing.cursor, containing: TailTests.wanted))
        #expect(texts(after) == [String(line(2).dropLast())])
    }

    /// The highest footprint above the one at its start, sampled every millisecond until `stop`.
    final class Peak: @unchecked Sendable {
        private let lock = NSLock()
        private var highest = 0, running = true
        private let start = TailTests.footprint()
        private let done = DispatchSemaphore(value: 0)

        init() {
            Thread.detachNewThread { [self] in
                while lock.withLock({ running }) {
                    let now = TailTests.footprint()
                    lock.withLock { highest = max(highest, now) }
                    usleep(1000)
                }
                done.signal()
            }
        }

        func stop() -> Int {
            lock.withLock { running = false }
            done.wait()
            return max(0, lock.withLock { highest } - start)
        }
    }

    /// This process's physical memory footprint, as Activity Monitor shows it.
    static func footprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }
}
