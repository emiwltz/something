// The suite trait that proves a whole suite cleans up after itself: the entries of $TMPDIR this test process made
// (`scratch`) with the suite's own prefix are counted before its first test and after its last, and any new one fails
// the suite. Only a prefix no other suite uses is given, since suites run side by side; another run at the same time,
// from another clone, makes its folders under its own mark and is never counted. Nothing is deleted here.
// Tests/somethingTests/LeavesNothing.swift is a link to this file, so both test targets compile the one copy.
import Foundation
import Testing

/// This test process's mark, in the name of every folder the tests make in $TMPDIR.
let thisRun = "run\(getpid())-"

extension FileManager {
    /// A new path in $TMPDIR, made of `prefix`, this run's mark and a UUID; nothing is made there yet.
    func scratch(_ prefix: String) -> URL { temporaryDirectory.appendingPathComponent("\(prefix)\(thisRun)\(UUID().uuidString)") }
}

#if compiler(>=6.1)
struct LeavesNothing: SuiteTrait, TestScoping {
    let prefix: String

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        let before = LeavesNothing.entries(prefix)
        try await function()
        let left = LeavesNothing.entries(prefix).subtracting(before)
        #expect(left.isEmpty, "\(test.name) left \(left.count) folder(s) named \(prefix)* in $TMPDIR: \(left.sorted())")
    }

    /// The names this run made in the temporary folder that start with `prefix`.
    static func entries(_ prefix: String) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory())) ?? []
        return Set(names.filter { $0.hasPrefix(prefix) && $0.contains(thisRun) })
    }
}
#else
// TestScoping came with Swift 6.1 (Xcode 16.3). An older toolchain, which macOS 15.0 and 15.1 may have, still builds
// and runs the suite; only this check is left out there.
struct LeavesNothing: SuiteTrait {
    let prefix: String
}
#endif

extension Trait where Self == LeavesNothing {
    /// The suite leaves no entry named `prefix`… in $TMPDIR.
    static func leavesNothing(_ prefix: String) -> Self { LeavesNothing(prefix: prefix) }
}
