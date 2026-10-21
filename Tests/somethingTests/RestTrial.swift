// What the app's own timers cost at rest, measured and never asserted: numbers for a commit message, read on this
// Mac, in an offscreen window. It runs only when asked:
//
//   SOMETHING_TRIAL_REST=1 swift test --filter RestTrial
import AppKit
import Darwin
import Foundation
import SomethingAgents
import SomethingCore
import Testing
@testable import something

@MainActor @Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SOMETHING_TRIAL_REST"] == "1", "The rest trial is asked for with SOMETHING_TRIAL_REST=1."),
                  .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-rest-"))
struct RestTrial {
    init() { NSApplication.shared.setActivationPolicy(.prohibited) }

    /// The app's own timers with the window shown, then hidden: the watch (on a throwaway home), the spaces folder's
    /// poller and the open space's, with the six templates as spaces and Stack open (it moves nothing by itself).
    @Test func theTimersShownThenHidden() async throws {
        let home = Home(prefix: "something-rest-")
        defer { home.remove() }
        for name in TemplatesTests.names {
            try home.space(name, try String(contentsOf: TemplatesTests.folder.appendingPathComponent("\(name).html"), encoding: .utf8))
        }
        let library = Library(places: home.places, ask: FakeAsk(), share: Home.share), engine = home.engine()
        library.watch()
        let view = try await home.window(try #require(library.entry("stack")?.space))
        let offscreen = Offscreen(view.web)
        defer { view.close(); library.stop(); engine.start(often: false, visible: false) }
        view.open()
        engine.start(often: true)
        await wait(3)
        for shown in [true, false] {
            engine.start(often: true, visible: shown)
            library.watching(shown)
            view.watching(shown)
            await wait(1)
            let start = RestTrial.usage(getpid()), began = Date()
            await wait(20)
            let end = RestTrial.usage(getpid()), seconds = Date().timeIntervalSince(began)
            guard let start, let end else { continue }
            print(String(format: "Rest timers, window %@: this process %.2f %% and %.1f idle wakeups/s", shown ? "shown" : "hidden",
                         (end.cpu - start.cpu) / seconds * 100, Double(end.wakeups - start.wakeups) / seconds))
        }
        withExtendedLifetime(offscreen) {}
    }

    /// The CPU seconds `pid` used since it started, and its idle wakeups; nil when the system does not say.
    static func usage(_ pid: Int32) -> (cpu: Double, wakeups: UInt64)? {
        guard pid > 0 else { return nil }
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) } }
        guard result == 0 else { return nil }
        var base = mach_timebase_info_data_t()
        mach_timebase_info(&base)
        return (Double(info.ri_user_time + info.ri_system_time) * Double(base.numer) / Double(base.denom) / 1e9, info.ri_pkg_idle_wkups)
    }
}
