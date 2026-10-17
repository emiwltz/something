// Tail: follows a JSONL file a harness appends to, and hands over its new whole lines (design 4.2, step 3). Session
// files reach tens of megabytes and single lines of several (tool outputs, images), so nothing is ever read whole:
// a file seen for the first time gives its last 512 KB, widened to 4 MB when that is not enough, and a line longer
// than 4 MB is skipped without being decoded. Lines are filtered by a substring before anyone decodes them.
import Darwin
import Foundation

/// Where the reading of one file stopped. A file replaced (new inode), cut shorter, or whose first bytes changed (a
/// harness that rewrites its file in place) is read again from its end, as a new one.
public struct Cursor: Equatable, Sendable {
    var inode: UInt64
    /// Just after the last whole line handed over.
    var offset: UInt64
    /// A hash of the file's first `headLength` bytes, at most 256.
    var head: Int
    var headLength: Int
    /// The bytes at `offset` belong to a line given up on (over 4 MB): they are skipped up to its end.
    var skipping: Bool
}

public enum Tail {
    static let window = 512 * 1024, widest = 4 * 1024 * 1024, headSize = 256

    public struct Read {
        /// The whole lines that hold one of the substrings asked for, oldest first, without their newline.
        public var lines: [Data]
        public var cursor: Cursor
        /// true when `lines` come from the end of the file rather than right after the cursor given: the caller
        /// starts over from them. That is the case for a first read, a file replaced, cut or rewritten, and when more
        /// than 4 MB were written since the last read.
        public var fresh: Bool
        /// How many bytes were read from the file, for the budget of a tick.
        public var bytes: Int
    }

    /// Returns the lines of `path` written after `cursor` (nil for a first read) that hold one of `containing`; nil
    /// when the file cannot be opened. On a fresh read, `enough` tells whether the lines of the last 512 KB are enough
    /// for the caller; if not, the last 4 MB are read. It never reads more than 4 MB plus 256 bytes.
    public static func read(_ path: String, after cursor: Cursor?, containing: [Data],
                            enough: ([Data]) -> Bool = { !$0.isEmpty }) -> Read? {
        let file = open(path, O_RDONLY | O_CLOEXEC)
        guard file >= 0 else { return nil }
        defer { close(file) }
        var status = stat()
        guard fstat(file, &status) == 0 else { return nil }
        let size = UInt64(max(status.st_size, 0)), inode = UInt64(status.st_ino)
        var bytes = 0
        func chunk(_ start: UInt64, _ end: UInt64) -> Data {
            let data = Tail.chunk(file, from: start, to: end)
            bytes += data.count
            return data
        }
        let headLength = Int(min(size, UInt64(headSize)))
        let headBytes = chunk(0, UInt64(headLength))
        let head = hash(headBytes)

        if let cursor, cursor.inode == inode, cursor.offset <= size, size - cursor.offset <= UInt64(widest),
           hash(headBytes.prefix(cursor.headLength)) == cursor.head {
            let (lines, consumed, skipping) = split(chunk(cursor.offset, size), startsMidLine: cursor.skipping, containing: containing)
            let next = Cursor(inode: inode, offset: cursor.offset + consumed, head: head, headLength: headLength, skipping: skipping)
            return Read(lines: lines, cursor: next, fresh: false, bytes: bytes)
        }
        // A fresh read: the last 512 KB, then the 4 MB before the end when the caller needs more.
        var start = size > UInt64(window) ? size - UInt64(window) : 0
        var data = chunk(start, size)
        var (lines, consumed, skipping) = split(data, startsMidLine: start > 0, containing: containing)
        if start > 0, !enough(lines) {
            let wider = size > UInt64(widest) ? size - UInt64(widest) : 0
            data = chunk(wider, start) + data
            start = wider
            (lines, consumed, skipping) = split(data, startsMidLine: start > 0, containing: containing)
        }
        let next = Cursor(inode: inode, offset: start + consumed, head: head, headLength: headLength, skipping: skipping)
        return Read(lines: lines, cursor: next, fresh: true, bytes: bytes)
    }

    /// The whole lines of `data` that hold one of `containing`, and how many bytes were used up. The bytes before the
    /// first newline are dropped when `startsMidLine`. What follows the last newline is left for the next read,
    /// unless it already passes 4 MB: then it is used up, and the next read skips the rest of that line.
    static func split(_ data: Data, startsMidLine: Bool, containing: [Data]) -> (lines: [Data], consumed: UInt64, skipping: Bool) {
        var lines: [Data] = []
        var index = data.startIndex
        if startsMidLine {
            guard let newline = data[index...].firstIndex(of: UInt8(ascii: "\n")) else { return ([], UInt64(data.count), true) }
            index = newline + 1
        }
        while let newline = data[index...].firstIndex(of: UInt8(ascii: "\n")) {
            let line = data[index..<newline]
            if line.count <= widest, containing.contains(where: { line.range(of: $0) != nil }) { lines.append(Data(line)) }
            index = newline + 1
        }
        if data.endIndex - index > widest { return (lines, UInt64(data.count), true) }
        return (lines, UInt64(index - data.startIndex), false)
    }

    /// The bytes of `file` from `start` to `end`; fewer when the file is shorter now.
    private static func chunk(_ file: Int32, from start: UInt64, to end: UInt64) -> Data {
        guard end > start else { return Data() }
        var data = Data(count: Int(end - start))
        let got = data.withUnsafeMutableBytes { pread(file, $0.baseAddress, $0.count, off_t(start)) }
        return got > 0 ? data.prefix(got) : Data()
    }

    private static func hash(_ data: Data) -> Int {
        var hasher = Hasher()
        hasher.combine(data)
        return hasher.finalize()
    }
}
