// What the app costs at rest, measured and never asserted: numbers for a commit message, read on this Mac. Each
// template is opened as a space against the invented state, whose agent a1 waits, in a window that is on screen
// (only then does WebKit animate), transparent and deaf to the mouse, as `something check` draws; then the CPU time
// of its WebKit processes (WebContent, GPU) and of this process is read over 20 seconds. It runs only when asked:
//
//   SOMETHING_TRIAL_REST=1 swift test --filter RestTrial
import AppKit
import Darwin
import Foundation
import SomethingAgents
import SomethingCore
import Testing
import WebKit
@testable import something

@MainActor @Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SOMETHING_TRIAL_REST"] == "1", "The rest trial is asked for with SOMETHING_TRIAL_REST=1."),
                  .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-rest-"))
struct RestTrial {
    init() { NSApplication.shared.setActivationPolicy(.prohibited) }

    @Test func eachTemplateWithAnAgentWaiting() async throws {
        let invented = try JSONDecoder().decode(SomethingCore.State.self, from: Data(contentsOf: Home.share.appendingPathComponent("contract/state-example.json")))
        let others = Set(RestTrial.webKit().keys)
        for name in TemplatesTests.names {
            let home = Home(prefix: "something-rest-")
            defer { home.remove() }
            let view = try await home.window(try home.space(name, try String(contentsOf: TemplatesTests.folder.appendingPathComponent("\(name).html"), encoding: .utf8)))
            let screen = NSScreen.main?.frame ?? .zero
            let window = NSWindow(contentRect: NSRect(x: screen.minX, y: screen.minY, width: 1280, height: 800), styleMask: .borderless, backing: .buffered, defer: false)
            (window.alphaValue, window.ignoresMouseEvents, window.hasShadow, window.isReleasedWhenClosed) = (0, true, false, false)
            // WebKit stops painting a page whose window macOS reports covered, as this transparent one is.
            let occlusion = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
            #expect(view.web.responds(to: occlusion))
            if view.web.responds(to: occlusion) { view.web.perform(occlusion, with: nil) }   // nil is NO
            window.contentView = view.web
            window.orderFrontRegardless()
            defer { view.close(); window.orderOut(nil); window.contentView = nil }
            view.open()
            #expect(await wait(until: { !view.web.isLoading && view.frame != nil }), "\(name) did not load")
            view.launched = ["a1"]
            SpaceView.push(try Rights.visible(invented, view.granted, launched: ["a1"]).json(), in: view.web, frame: try #require(view.frame))
            await wait(3)
            let content = view.web.value(forKey: "_webProcessIdentifier") as? Int32 ?? 0
            let gpu = RestTrial.webKit().first { !others.contains($0.key) && $0.value.contains("GPU") }?.key ?? 0
            let start = [content, gpu, getpid()].map(RestTrial.usage), began = Date()
            await wait(20)
            let end = [content, gpu, getpid()].map(RestTrial.usage), seconds = Date().timeIntervalSince(began)
            func percent(_ index: Int) -> String {
                guard let one = start[index], let two = end[index] else { return "unreadable" }
                return String(format: "%.1f %%", (two.cpu - one.cpu) / seconds * 100)
            }
            let wakeups = (end[2]?.wakeups ?? 0) - (start[2]?.wakeups ?? 0)
            // What moves on the page: each animation running without end, with the properties it moves.
            let moving = try await run(view, """
                return document.getAnimations().filter((a) => a.effect.getTiming().iterations === Infinity && a.playState === "running")
                  .map((a) => a.animationName + " (" + [...new Set(a.effect.getKeyframes().flatMap((k) => Object.keys(k)))]
                  .filter((k) => !["offset", "computedOffset", "easing", "composite"].includes(k)).join(", ") + ")").join(", ")
                """) as? String ?? "?"
            print("Rest \(name): WebContent \(percent(0)), GPU \(percent(1)), this process \(percent(2)) and \(String(format: "%.1f", Double(wakeups) / seconds)) idle wakeups/s; moving without end: \(moving.isEmpty ? "nothing" : moving)")
        }
    }

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

    /// The WebKit processes of this user, by pid, with their name.
    static func webKit() -> [Int32: String] {
        var pids = [Int32](repeating: 0, count: 8192)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size)))
        var found: [Int32: String] = [:]
        for pid in pids.prefix(max(count, 0)) where pid > 0 {
            var name = [CChar](repeating: 0, count: 256)
            proc_name(pid, &name, UInt32(name.count))
            let text = String(cString: name)
            if text.hasPrefix("com.apple.WebKit") { found[pid] = text }
        }
        return found
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
