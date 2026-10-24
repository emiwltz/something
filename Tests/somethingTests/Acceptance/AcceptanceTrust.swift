// Acceptance scenarios of what asks the person: the request panel and its queue, the Dock, the sheets and the quit alerts
// (e1–e9, e13–e15). Key-window and focus claims are not asserted offscreen: each slice lists them for the hand trial.
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import Testing

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-trust-"))
struct AcceptanceTrust {
    @Test("e1: the request panel", .disabled("not built yet: T2")) func e1() async throws {}
    @Test("e2: the command box", .disabled("not built yet: T3")) func e2() async throws {}
    @Test("e3: the request queue", .disabled("not built yet: T2")) func e3() async throws {}
    @Test("e4: Show Request", .disabled("not built yet: T5")) func e4() async throws {}
    @Test("e5: the Dock badge", .disabled("not built yet: T6")) func e5() async throws {}
    @Test("e6: a question", .disabled("not built yet: T4")) func e6() async throws {}
    @Test("e7: the link sheet", .disabled("not built yet: T7")) func e7() async throws {}
    @Test("e8: the trash sheet", .disabled("not built yet: T8")) func e8() async throws {}
    @Test("e9: quit while assistants work", .disabled("not built yet: T9")) func e9() async throws {}
    @Test("e13: the panel in full screen", .disabled("not built yet: T2")) func e13() async throws {}
    @Test("e14: the panel over the welcome", .disabled("not built yet: AB17w")) func e14() async throws {}
    @Test("e15: quit with requests", .disabled("not built yet: T9")) func e15() async throws {}
}
