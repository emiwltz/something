// What the app's own timers cost at rest, measured and never asserted: numbers for a commit message, read on this
// Mac, in a window never shown. The window is the app's, at rest as a person leaves it: Stack open with the sticker
// over it, three assistants asleep (kept conversations, no process), two messages held in Stack's queue, a toast come
// and gone; the watch (on a throwaway home), the spaces folder's poller and the open space's run. The sign's breath
// moves no frame off screen (PerformanceTests), so what the sticker costs on the screen is not in these numbers. It
// runs only when asked:
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
                  .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-rest-"))
struct RestTrial {
    /// The app's own timers with the window shown, then hidden.
    @Test func theTimersShownThenHidden() async throws {
        let stage = try Stage("rest")
        defer { stage.remove() }
        try FileManager.default.createDirectory(at: stage.home.places.assistants, withIntermediateDirectories: true)
        let names = ["logbook", "pet", "stack"]
        for name in names {
            let kept = Session.Saved(kind: "claude", model: nil, effort: nil, thread: "thread-\(name)", threadKind: "claude", asking: false, turns: [])
            try JSONEncoder().encode(kept).write(to: Session.file(name, in: stage.home.places.assistants))
        }
        let (shell, library, _) = stage.window()
        let assistant = shell.assistant, engine = assistant.engine
        library.watch()
        let view = try await stage.open("stack", in: shell, library)
        defer { view.close(); library.stop(); engine.start(often: false, visible: false) }
        let sessions = names.map { name in
            assistant.session(for: .space(title: name, name: name, page: stage.home.places.spaces.appendingPathComponent("\(name).html").path))
        }
        sessions.last?.held = ["Invented message, held.", "Another one."]
        _ = shell.toast("Invented toast.", seconds: 1)
        engine.start(often: true)
        await wait(3)
        #expect(sessions.allSatisfy(\.asleep) && !shell.glass.isHidden && assistant.beatAt == nil)
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
