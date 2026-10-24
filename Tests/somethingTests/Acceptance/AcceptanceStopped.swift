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
        brief.loaded = { [weak shell, weak brief] in
            brief.map { shell?.show($0) }
            // The composer goes with the sticker's slice: the mockup shows the page and the card alone.
            shell?.floating?.isHidden = true
        }
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
        Self.stop(brief, at: -1)
        let cover = try #require(brief.area.subviews.last as? Stopped)
        #expect(brief.stopped && !brief.paused && cover.frame == brief.web.frame)
        #expect(PanelsTests.texts(cover) == ["This space stopped",
                                             "Its page stopped responding. Nothing is lost: the page, its memory and its assistant are as they were.",
                                             "brief.html · stopped at 18:19"])
        #expect(cover.reload.title == "Reload" && cover.fix.title == "Ask Its Assistant to Fix It" && cover.fix.isEnabled)
        #expect(cover.subviews.first?.accessibilityLabel() == "This space stopped")
        // Nothing to point at in a page that stopped; Reload and Info still act.
        let items = shell.toolbarItems
        #expect(items.first { $0.itemIdentifier == Shell.point }?.isEnabled == false)
        #expect(items.filter { [Shell.reload, Shell.info].contains($0.itemIdentifier) }.allSatisfy { $0.isEnabled })
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: brief.web, "e10" + suffix, root: stage.home.root)
        }
        // Ask Its Assistant to Fix It is sent once, and the stops before it are forgotten.
        cover.fixNow()
        #expect(!cover.fix.isEnabled && brief.stops.isEmpty && brief.stopped)
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

    @Test("e12: the script error strip", .disabled("not built yet: T11")) func e12() async throws {}
}
