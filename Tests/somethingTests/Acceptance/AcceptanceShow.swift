// Acceptance scenarios of show and change: pointing, picked frames, the margin note, the toast, History, the glimpse and
// the comments (f1–f11; f9–f11 wait for their shots).
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import Testing

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-show-"))
struct AcceptanceShow {
    @Test("f1: pointing", .disabled("not built yet: T14")) func f1() async throws {}
    @Test("f2: picked frames and the composer", .disabled("not built yet: T15")) func f2() async throws {}
    @Test("f3: a frame at work", .disabled("not built yet: T16")) func f3() async throws {}
    @Test("f4: the margin note", .disabled("not built yet: T17")) func f4() async throws {}
    @Test("f5: the undo toast", .disabled("not built yet: T13")) func f5() async throws {}
    @Test("f6: History", .disabled("not built yet: T19")) func f6() async throws {}
    @Test("f7: the glimpse", .disabled("not built yet: T20")) func f7() async throws {}
    @Test("f8: changed outside something", .disabled("not built yet: T21")) func f8() async throws {}
    @Test("f9: comment pins", .disabled("not built yet: T18")) func f9() async throws {}
    @Test("f10: the comments tray", .disabled("not built yet: T18")) func f10() async throws {}
    @Test("f11: comments sent together", .disabled("not built yet: T18")) func f11() async throws {}
}
