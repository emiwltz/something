// Acceptance scenarios of a space that stops: the Stopped view, a second stop, the script error strip (e10–e12).
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import Testing

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-stopped-"))
struct AcceptanceStopped {
    @Test("e10: a space that stopped", .disabled("not built yet: T10")) func e10() async throws {}
    @Test("e11: stopped twice", .disabled("not built yet: T10")) func e11() async throws {}
    @Test("e12: the script error strip", .disabled("not built yet: T11")) func e12() async throws {}
}
