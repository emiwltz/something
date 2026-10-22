// Under the test runner, Spawn starts no real agent program. A real Claude or Codex started by the suite runs in the
// person's own environment (their home, their MCP servers) and, with the main run loop turned forever, stalls every
// test after it: it happened once. Here, under `swift test` only, a program is started when it is a fake in the
// temporary folder, one of the system's own tools, or the program a live trial's variable names
// (SOMETHING_TRIAL_CLAUDE, _CODEX, _OPENCODE, _PI).
// Outside the tests nothing is checked.
import Darwin
import Foundation
import SomethingCore

enum TestRunGuard {
    /// Whether this process runs the test bundle: swift test loads it from a `.xctest` folder.
    static let underTests: Bool = (0..<_dyld_image_count()).contains { index in
        _dyld_get_image_name(index).map { String(cString: $0).contains(".xctest/") } ?? false
    }

    /// Returns when `path` may be started; throws LAUNCH_FAILED, under the tests only, for any other program.
    static func check(_ path: String, environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        guard underTests, FileManager.default.fileExists(atPath: path), !allowed(path, environment: environment) else { return }
        throw CodedError("LAUNCH_FAILED", "The tests start no real agent program, and \(path) is not a fake in the temporary folder; set its SOMETHING_TRIAL_* variable for a live trial.")
    }

    static func allowed(_ path: String, environment: [String: String]) -> Bool {
        let real = (path as NSString).resolvingSymlinksInPath
        // resolvingSymlinksInPath drops the trailing slash NSTemporaryDirectory gives.
        let temporary = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath + "/"
        if [temporary, "/bin/", "/usr/bin/"].contains(where: real.hasPrefix) { return true }
        let trials = Engine.launchable.keys.compactMap { environment["SOMETHING_TRIAL_\($0.uppercased())"] }
        return trials.contains { $0 == path || ($0 as NSString).resolvingSymlinksInPath == real }
    }
}
