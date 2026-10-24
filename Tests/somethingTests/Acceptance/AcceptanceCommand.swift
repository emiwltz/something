// Acceptance scenarios of the palette, Settings, the menus and the shortcuts card (g1–g11).
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import Testing
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-command-"))
struct AcceptanceCommand {
    @Test("g1: the palette", .disabled("not built yet: G2")) func g1() async throws {}
    @Test("g2: the palette's ask row", .disabled("not built yet: G3")) func g2() async throws {}
    @Test("g3: Settings, General", .disabled("not built yet: G4")) func g3() async throws {}
    @Test("g4: Settings, Assistant", .disabled("not built yet: G5")) func g4() async throws {}
    @Test("g5: Settings, Permissions", .disabled("not built yet: G5")) func g5() async throws {}
    @Test("g6: Settings, Interface", .disabled("not built yet: G4")) func g6() async throws {}
    @Test("g7: Settings, Shortcuts", .disabled("not built yet: G4")) func g7() async throws {}
    @Test("g8: Settings, Versions and Storage", .disabled("not built yet: G6")) func g8() async throws {}
    /// The menu bar is drawn by the window server, which no offscreen drawing reaches: g9 is checked as text, the
    /// menus against the mockup's table with no space open, then Go, the headers and the greyed items with Daily brief
    /// open. g9-menus.txt is the dump of both states.
    @Test("g9: the menus") func g9() async throws {
        let stage = try Stage("command")
        defer { stage.remove() }
        let (shell, library, _) = stage.window()
        let bar = MenuBar(builders: nil)
        var open: (id: String, title: String)?
        bar.spaces = { library.order().filter(\.isSpace).map { ($0.id, $0.title) } }
        bar.open = { open }
        bar.refresh()
        let (fixture, _) = try Mockup.menus()
        #expect(bar.menu.items.compactMap(\.submenu).map { Mockup.lines($0) } == fixture.map(\.lines))
        let closed = Mockup.dump(bar.menu, Keys.Situation())
        for line in ["  # No space open", "  Space Info  ⌘I  (greyed)", "  Ask…  ⌘K  (greyed)", "  Go to…  ⌘P  (greyed)",
                     "  New Space  ⌘N", "  Daily brief  ⌘1"] {
            #expect(closed.contains(line + "\n"), "\(line)")
        }
        let brief = try await stage.open("brief", in: shell, library)
        defer { brief.close() }
        open = ("brief", brief.title)
        bar.refresh()
        let go = try #require(bar.submenu("Go")).items.filter { $0.identifier?.rawValue.hasPrefix("space:") == true }
        #expect(go.count == library.entries.filter(\.isSpace).count && go.count == 7)
        #expect(go.filter { $0.state == .on }.map(\.title) == ["Daily brief"])
        let opened = Mockup.dump(bar.menu, Keys.Situation(space: true))
        for line in ["  # Daily brief", "  # Daily brief’s assistant", "  Space Info  ⌘I", "  Ask…  ⌘K", "  ✓ Daily brief  ⌘1",
                     "  Versions…  (greyed)", "  Put Idle Assistants to Sleep  (greyed)"] {
            #expect(opened.contains(line + "\n"), "\(line)")
        }
        #expect(Keys.versionLine(.main).hasPrefix("Version "))
        if let gallery {
            try FileManager.default.createDirectory(at: gallery, withIntermediateDirectories: true)
            try ("No space open\n\n" + closed + "\nDaily brief open\n\n" + opened).write(to: gallery.appendingPathComponent("g9-menus.txt"),
                                                                                           atomically: true, encoding: .utf8)
        }
    }
    @Test("g10: the shortcuts card", .disabled("not built yet: G1")) func g10() async throws {}
    @Test("g11: Settings, Agents", .disabled("not built yet: G5")) func g11() async throws {}
}
