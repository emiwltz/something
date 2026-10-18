// The suite trait that proves a whole suite cleans up after itself: the entries of $TMPDIR with the suite's own prefix
// are counted before its first test and after its last, and any new one fails the suite. Only a prefix no other suite
// uses is given, since suites run side by side; nothing is deleted here.
import Foundation
import Testing

struct LeavesNothing: SuiteTrait, TestScoping {
    let prefix: String

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        let before = LeavesNothing.entries(prefix)
        try await function()
        let left = LeavesNothing.entries(prefix).subtracting(before)
        #expect(left.isEmpty, "\(test.name) left \(left.count) folder(s) named \(prefix)* in $TMPDIR: \(left.sorted())")
    }

    /// The names in the temporary folder that start with `prefix`.
    static func entries(_ prefix: String) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory())) ?? []
        return Set(names.filter { $0.hasPrefix(prefix) })
    }
}

extension Trait where Self == LeavesNothing {
    /// The suite leaves no entry named `prefix`… in $TMPDIR.
    static func leavesNothing(_ prefix: String) -> Self { LeavesNothing(prefix: prefix) }
}
