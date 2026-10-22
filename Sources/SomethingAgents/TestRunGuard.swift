// Under the test runner, Spawn starts no real agent program. A real agent started by the suite runs in the person's
// own environment (their home, their MCP servers) and, with the main run loop turned forever, stalls every test after
// it: it happened once. Here, under `swift test` only, a program is started when it is a fake in the temporary
// folder, one of the system's own tools, or the program a live trial's variable names for the kind it launches
// (SOMETHING_TRIAL_<KIND>).
// Outside the tests nothing is checked.
import Darwin
import Foundation
import SomethingCore

enum TestRunGuard {
    /// Whether this process runs the test bundle: swift test loads it from a `.xctest` folder.
    static let underTests: Bool = (0..<_dyld_image_count()).contains { index in
        _dyld_get_image_name(index).map { String(cString: $0).contains(".xctest/") } ?? false
    }

    /// Returns when `path`, run as an agent of `kind` (nil: no agent), may be started; throws LAUNCH_FAILED, under the
    /// tests only, for any other program.
    static func check(_ path: String, kind: String?, environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        guard underTests, FileManager.default.fileExists(atPath: path), !allowed(path, kind: kind, environment: environment) else { return }
        throw CodedError("LAUNCH_FAILED", "The tests start no real agent program, and \(path) is not a fake in the temporary folder; set its SOMETHING_TRIAL_* variable for a live trial.")
    }

    static func allowed(_ path: String, kind: String?, environment: [String: String]) -> Bool {
        let real = (path as NSString).resolvingSymlinksInPath
        // resolvingSymlinksInPath drops the trailing slash NSTemporaryDirectory gives.
        let temporary = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath + "/"
        if [temporary, "/bin/", "/usr/bin/"].contains(where: real.hasPrefix) { return true }
        guard let kind, let trial = environment["SOMETHING_TRIAL_\(kind.uppercased())"] else { return false }
        return trial == path || (trial as NSString).resolvingSymlinksInPath == real
    }
}
