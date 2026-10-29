// What the app costs, measured with fake agents only, in windows never shown: opening Info lays the page out once; ⌘P
// opens in under 100 ms of the main thread's time with fifty spaces; a version held in History, History closed and a
// template's Preview leave no web content process behind; assistants asleep are no process at all and leave no timer
// waiting; the sticker's sign ticks only with its window's display link, so no frame off screen. What the timers cost
// at rest, in CPU and wakeups, is RestTrial's to measure.
import AppKit
import Darwin
import SomethingCore
import SwiftUI
import Testing
import WebKit
@testable import SomethingAgents
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-perf-"))
struct PerformanceTests {
    /// The process a web view's pages run in; nil when WebKit does not say (a name only a test reads).
    static func process(_ web: WKWebView) -> pid_t? {
        guard web.responds(to: Selector(("_webProcessIdentifier"))), let pid = web.value(forKey: "_webProcessIdentifier") as? Int, pid > 0 else { return nil }
        return pid_t(pid)
    }

    /// Whether the process `pid` still runs.
    static func alive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

    /// Info opened beside Daily brief: the page narrows by Info's width in one step and gets one resize, never one per
    /// frame of an animation; closed, the same once more.
    @Test func openingInfoLaysThePageOutOnce() async throws {
        let stage = try Stage("perf")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        // Every resize counted is this test's: no size test of another suite resizes the window meanwhile.
        try await Stage.alone {
            shell.window.layoutIfNeeded()
            let resizes = "await new Promise((done) => setTimeout(done, 300)); return window.resizes"
            _ = try await run(brief, "window.resizes = 0; window.seen = []; addEventListener('resize', () => { window.resizes += 1; window.seen.push(innerWidth + 'x' + innerHeight + '@' + Math.round(performance.now())); }); return 0")
            // A resize the window's first layout left pending reaches the page first: counted from a settled page.
            await wait(1)
            _ = try await run(brief, "window.resizes = 0; window.seen = []; return 0")
            var widths: [CGFloat] = []
            brief.web.postsFrameChangedNotifications = true
            let watch = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: brief.web, queue: nil) { _ in
                MainActor.assumeIsolated { widths.append(brief.web.frame.width) }
            }
            defer { NotificationCenter.default.removeObserver(watch) }
            let wide = brief.web.frame.width
            for (shown, step) in [(true, 1), (false, 2)] {
                shell.showInfo(shown)
                shell.window.layoutIfNeeded()
                await wait(1)
                let panel = shell.inspector.viewController.view.frame.width
                #expect(widths.count == step && widths.last == (shown ? wide - panel : wide), "\(widths)")
                let count = try await run(brief, resizes) as? Int
                let seen = try await run(brief, "return JSON.stringify(window.seen)") as? String
                #expect(count == step, "one resize of the page each time: \(String(describing: count)) \(seen ?? "")")
            }
        }
    }

    /// ⌘P with fifty spaces: from the key to the card laid out and drawn, its rows built from the fifty spaces' names
    /// and eyes. The first opening of the run fills SwiftUI's and the fonts' caches, as the app's first does once; each
    /// of the next three is timed (three more, up to ten times, while none is in bound), and the quickest is under
    /// 100 ms on a Mac. What is timed is the main thread's own processor time, where all of that work runs: a loaded
    /// Mac (the suite's other processes, another build) lends the thread less of the processor and stretches the clock,
    /// not the work. Time the thread spends blocked (on the window server, a font read from disk) is not counted: the
    /// clock's time is printed beside it, so a regression there still shows in the log. On CI's virtual Macs, with no
    /// graphics card and a shared processor, the bound is 500 ms: still a gross regression, rows built per spaces
    /// squared for one, but no false red.
    @Test func thePaletteOpensUnderATenthOfASecondWithFiftySpaces() async throws {
        let stage = try Stage("perf")
        defer { stage.remove() }
        for index in 1...43 {
            try stage.home.space(String(format: "notes-%02d", index), page(#"{"contract": 1, "title": "Invented notes \#(index)"}"#, "<p>Invented.</p>"))
        }
        let (shell, library, _) = stage.window()
        #expect(library.entries.count == 50)
        library.select(.space("brief"))
        // This thread's processor time, in seconds.
        func busy() -> TimeInterval { TimeInterval(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e9 }
        var clock: [TimeInterval] = []
        func open() throws -> TimeInterval {
            let (began, started) = (busy(), Date())
            let model = PaletteModel(library: library, eyes: { shell.assistant.eyes(of: $0) }, enabled: { Keys.enabled($0, Keys.Situation(space: true)) })
            let palette = try #require(Palette.toggle(in: shell.layer, model: model, motion: .reduced))
            palette.layoutSubtreeIfNeeded()
            let rep = try #require(palette.bitmapImageRepForCachingDisplay(in: palette.card.frame))
            palette.cacheDisplay(in: palette.card.frame, to: rep)
            let took = busy() - began
            clock.append(Date().timeIntervalSince(started))
            #expect(model.rows.filter { $0.section == .spaces || $0.section == .recent }.count == 50)
            #expect(Palette.toggle(in: shell.layer, model: model) == nil, "⌘P again closes it")
            return took
        }
        // While no other test turns on a mode of the whole process that slows every view made (VoiceOver's, a night).
        // On a loaded Mac the system may run the thread on an efficiency core, which does the same work in twice the
        // time or more: three more openings, up to ten times, half a second apart, until the quickest is in bound.
        let bound = ProcessInfo.processInfo.environment["CI"] == nil ? 0.1 : 0.5
        let times = try await Stage.alone {
            _ = try open()
            var times: [TimeInterval] = []
            for round in 0..<10 where (times.min() ?? .infinity) >= bound {
                if round > 0 { await wait(0.5) }
                times += try (0..<3).map { _ in try open() }
            }
            return times
        }
        let said = zip(times, clock.dropFirst()).map { String(format: "%.1f ms (%.1f ms by the clock)", $0 * 1000, $1 * 1000) }
        print("⌘P with 50 spaces opened in " + said.joined(separator: ", "))
        #expect(try #require(times.min()) < bound, "\(times)")
    }

    /// A version held in History shows in a second web view; let go, its process ends; History closed, only the open
    /// space's process runs, and it ends with the space. A template's Preview is a picture: it makes no web view.
    @Test func historyHoldAndPreviewLeaveNoWebContentProcess() async throws {
        let stage = try Stage("perf")
        defer { stage.remove() }
        let (shell, library, info) = stage.window()
        var brief: SpaceView? = try await stage.open("brief", in: shell, library)
        info.clock = { Stage.local }
        info.current = { [weak brief] in brief }
        let all = try await AcceptanceShow.keepVersions(of: try #require(brief), info)
        let open = try #require(brief.flatMap { Self.process($0.web) }, "WebKit says the process of a web view")
        shell.showHistory()
        shell.window.layoutIfNeeded()
        let history = info.history
        history.chosen = all[3].id
        history.press(all[3].id)
        #expect(await wait(until: { history.glimpse?.shown == true }), "the held version did not show")
        let held = try #require(history.glimpse?.view.flatMap { Self.process($0.web) })
        #expect(held != open, "the held version runs in its own process")
        history.lift()
        #expect(await wait(30, until: { !Self.alive(held) }), "the held version's process ended once let go")
        #expect(await wait(until: { brief?.glimpsed == nil }), "the space let the faded cover go")
        shell.showInfo(false)
        #expect(Self.alive(open))
        brief?.close()
        shell.show(nil)
        brief = nil
        #expect(await wait(30, until: { !Self.alive(open) }), "the space's process ended with it")
        // Templates, then a template's preview: no web view anywhere in the window.
        library.select(.templates)
        shell.show(nil, templates: true)
        let host = try #require(shell.center.subviews.first { $0 is NSHostingView<GalleryView> } as? NSHostingView<GalleryView>)
        host.rootView.model.preview(try #require(library.templates.first { $0.id == "pet" }))
        shell.window.layoutIfNeeded()
        await wait(1)
        #expect(host.rootView.model.previewing?.id == "pet" && Self.views(of: WKWebView.self, in: shell.window).isEmpty)
    }

    /// Three assistants that answered, then idled past the Preferences' delay: asleep, none of their processes runs,
    /// and the assistant waits for no moment (no timer) until a message wakes one.
    @Test func sleepingAssistantsAreNoProcess() async throws {
        let helper = AssistantTests()
        let (home, model) = try helper.assistant(prefix: "something-accept-perf-sessions-")
        defer { home.remove() }
        var now = Date() + 3600
        model.clock = { now }
        await helper.look(model)
        let places = [("Logbook", "logbook"), ("Pebble", "pet"), ("Stack", "stack")].map {
            AssistantModel.Place.space(title: $0.0, name: $0.1, page: home.places.spaces.appendingPathComponent("\($0.1).html").path)
        }
        let sessions = places.map { model.session(for: $0) }
        for session in sessions { model.deliver("Hello.", to: session) }
        #expect(await wait(until: { sessions.allSatisfy { $0.agent?.state == "idle" && $0.agent?.pid != nil } }))
        let pids = sessions.compactMap { $0.agent?.pid }.map { pid_t($0) }
        #expect(pids.count == 3 && pids.allSatisfy(Self.alive))
        now += 2 * 60 * 60
        model.tick()
        #expect(sessions.allSatisfy(\.asleep) && sessions.allSatisfy { !model.awake($0) })
        #expect(await wait(30, until: { !pids.contains(where: Self.alive) }), "asleep, no process runs")
        #expect(model.beatAt == nil, "nothing left to wait for: no timer")
        await helper.finish(home, model)
    }

    /// The sticker's sign breathes at up to 30 frames a second while its window is on the screen. It ticks with its
    /// window's display link, which the system never fires off screen: this proves it uses that link and starts no timer
    /// of its own, whatever its state; the sign itself does not check its window's visibility. In the drawing turn: a
    /// change of the whole app's appearance or size by another suite marks every view for drawing, the sign's too.
    @Test func theSignTicksOnlyWithItsWindowsDisplayLink() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        await Stage.alone {
            for state in [Sign.State.listen, .think, .sleep] {
                let sign = SignView(state)
                window.contentView?.addSubview(sign)
                defer { sign.removeFromSuperview() }
                #expect(sign.animating, "it would move on the screen")
                var frames = 0
                for _ in 0..<10 {
                    sign.displayIfNeeded()
                    await wait(0.1)
                    if sign.needsDisplay { frames += 1 }
                }
                #expect(frames == 0, "\(state): \(frames) frames off screen")
            }
        }
    }


    /// The views of `type` in `window`, its frame's included.
    static func views<Kind: NSView>(of type: Kind.Type, in window: NSWindow) -> [Kind] {
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        return window.contentView?.superview.map(all)?.compactMap { $0 as? Kind } ?? []
    }
}
