// Acceptance scenarios of each space's assistant: the sticker on the glass, the card, its states and notices (c1–c10).
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import Testing

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-assistant-"))
struct AcceptanceAssistant {
    @Test("c1: the sticker on the glass", .disabled("not built yet: AB05")) func c1() async throws {}
    @Test("c2: the card", .disabled("not built yet: AB04")) func c2() async throws {}
    @Test("c3: a thread kept after sleep", .disabled("not built yet: AB10")) func c3() async throws {}
    @Test("c4: still working, Stop", .disabled("not built yet: AB07")) func c4() async throws {}
    @Test("c5: model and effort", .disabled("not built yet: AB11")) func c5() async throws {}
    @Test("c6: one assistant per space", .disabled("not built yet: AB09b")) func c6() async throws {}
    @Test("c7: the sign's seven states", .disabled("not built yet: AB05")) func c7() async throws {}
    @Test("c8: the notice slot", .disabled("not built yet: AB08")) func c8() async throws {}
    @Test("c9: the sticker dragged", .disabled("not built yet: AB06")) func c9() async throws {}
    @Test("c10: a message held by the app", .disabled("not built yet: AB07")) func c10() async throws {}
}
