// Acceptance scenarios of the palette, Settings, the menus and the shortcuts card (g1–g11).
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import Testing

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
    @Test("g9: the menus", .disabled("not built yet: F5")) func g9() async throws {}
    @Test("g10: the shortcuts card", .disabled("not built yet: G1")) func g10() async throws {}
    @Test("g11: Settings, Agents", .disabled("not built yet: G5")) func g11() async throws {}
}
