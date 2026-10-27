// Acceptance scenarios of a space that stops: the Stopped view, a second stop, the script error strip (e10–e12).
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits). A real crash of the web content process is in the hand trial:
// here the delegate is called as WebKit calls it.
import AppKit
import Testing
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-stopped-"))
struct AcceptanceStopped {
    /// Daily brief open in the window, wired as the app wires it, its stops on the Stage's clock: the mockup's 18:19
    /// and 18:20, in 24 hours.
    static func brief(_ stage: Stage) async throws -> (Shell, Library, SpaceView) {
        let (shell, library, _) = stage.window()
        let brief = try await stage.open("brief", in: shell, library)
        brief.loaded = { [weak shell, weak brief] in brief.map { shell?.show($0) } }
        // The mockup's moment around the stopped space: the groups, the rows' eyes and My agents' request in Needs You.
        try stage.moment(shell)
        shell.waiting(["agents"], mine: 0)
        brief.calendar.timeZone = try #require(Stage.zone)
        brief.hours = Locale(identifier: "en_GB")
        return (shell, library, brief)
    }

    static func stop(_ brief: SpaceView, at minutes: Double) {
        brief.now = { Stage.now.addingTimeInterval(60 * minutes) }
        brief.webViewWebContentProcessDidTerminate(brief.web)
    }

    @Test("e10: a space that stopped") func e10() async throws {
        let stage = try Stage("stopped")
        defer { stage.remove() }
        let (shell, library, brief) = try await Self.brief(stage)
        defer { brief.close() }
        // Point: enabled on a page that runs, greyed only by the stop.
        let point = { shell.toolbarItems.first { $0.itemIdentifier == Shell.point }?.isEnabled }
        #expect(point() == true && shell.assistant.pointable)
        Self.stop(brief, at: -1)
        let cover = try #require(brief.area.subviews.last as? Stopped)
        #expect(brief.stopped && !brief.paused && cover.frame == brief.web.frame)
        #expect(PanelsTests.texts(cover) == ["This space stopped",
                                             "Its page stopped responding. Nothing is lost: the page, its memory and its assistant are as they were.",
                                             "brief.html · stopped at 18:19"])
        #expect(cover.reload.title == "Reload" && cover.fix.title == "Ask Its Assistant to Fix It" && cover.fix.isEnabled)
        #expect(cover.subviews.first?.accessibilityLabel() == "This space stopped")
        // Nothing to point at in a page that stopped; Info and the View menu's Reload still act.
        let items = shell.toolbarItems
        #expect(point() == false && !shell.assistant.pointable && !brief.pointable)
        #expect(items.first { $0.itemIdentifier == Shell.info }?.isEnabled == true && Keys.enabled("reload", Keys.Situation(space: true)))
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "e10" + suffix, root: stage.home.root)
        }
        // Ask Its Assistant to Fix It is sent once, and the stops before it are forgotten.
        cover.fixNow()
        #expect(!cover.fix.isEnabled && brief.stops.isEmpty && brief.stopped)
        #expect(Stopped.words([], file: "brief.html", calendar: brief.calendar, hours: brief.hours).when == "brief.html")
    }

    @Test("e11: stopped twice") func e11() async throws {
        let stage = try Stage("stopped")
        defer { stage.remove() }
        let (shell, library, brief) = try await Self.brief(stage)
        defer { brief.close() }
        Self.stop(brief, at: -1)
        Self.stop(brief, at: 0)
        let cover = try #require(brief.area.subviews.last as? Stopped)
        #expect(brief.stopped && brief.paused && brief.area.subviews.filter { $0 is Stopped }.count == 1)
        #expect(PanelsTests.texts(cover) == ["This space stopped", "It stopped twice. something won't reload it again until you ask.",
                                             "brief.html · stopped at 18:19 and 18:20"])
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "e11" + suffix, root: stage.home.root)
        }
        // Reload, the person's: the page loads again, the watch resumes and the cover goes.
        cover.reloadNow()
        #expect(!brief.stopped && !brief.paused && !brief.area.subviews.contains { $0 is Stopped })
    }

    @Test("A stopped space that closes lets its cover and its web view go") func freed() async throws {
        let stage = try Stage("stopped")
        defer { stage.remove() }
        weak var space: SpaceView?, cover: Stopped?
        try await {
            let (shell, _, brief) = try await Self.brief(stage)
            Self.stop(brief, at: 0)
            cover = brief.area.subviews.last as? Stopped
            #expect(cover != nil)
            shell.show(nil)
            brief.close()
            space = brief
        }()
        // The fade-in holds the cover until it ends.
        #expect(await wait(until: { cover == nil }))
        #expect(space == nil)
    }

    @Test("e12: the script error strip") func e12() async throws {
        let stage = try Stage("stopped")
        defer { stage.remove() }
        let (shell, library, brief) = try await Self.brief(stage)
        defer { brief.close() }
        shell.show(brief)
        #expect(!brief.area.subviews.contains { $0 is ScriptError })
        // As faultScript reports them: only the first error's line is shown, every code is kept.
        let said = "TypeError: Cannot read properties of undefined (reading 'temp')"
        brief.fault("SCRIPT_ERROR", message: said, file: "brief.html", line: "142")
        brief.fault("SCRIPT_ERROR", message: "Error: a second one", file: "brief.html", line: "150")
        brief.fault("PROMISE_REJECTED", message: "Error: a rejection")
        let strip = try #require(brief.area.subviews.last as? ScriptError)
        #expect(brief.area.subviews.filter { $0 is ScriptError }.count == 1 && brief.faults == ["SCRIPT_ERROR", "PROMISE_REJECTED"])
        #expect(PanelsTests.texts(strip) == ["Script error", "“\(said) · brief.html, line 142”"])
        #expect(strip.fix.title == "Ask to Fix" && strip.fix.isEnabled && strip.close.toolTip == "Close")
        #expect(strip.accessibilityLabel() == "Script error" && strip.quote.accessibilityLabel() == "The page's message: \(said) · brief.html, line 142")
        // It pushes the page down: nothing of the page under it, and the page still runs (Point stays).
        #expect(strip.frame.height == 40 && strip.frame.width == brief.area.bounds.width && strip.frame.maxY == brief.area.bounds.maxY)
        #expect(brief.web.frame.maxY == strip.frame.minY && brief.web.frame.minY == 0 && !brief.stopped)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "e12" + suffix, root: stage.home.root)
        }
        // Ask to Fix goes once, in something's words, and the strip leaves until the next load.
        strip.fixNow()
        #expect(brief.dismissed && !brief.area.subviews.contains { $0 is ScriptError } && brief.web.frame == brief.area.bounds)
        shell.show(brief)
        #expect(!brief.area.subviews.contains { $0 is ScriptError })
    }
}
