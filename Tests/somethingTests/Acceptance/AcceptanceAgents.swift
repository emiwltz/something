// Acceptance scenarios of the agents, round 4: the panel (a1-1 to a1-12), the three chips and the picker (r9-1 to r9-3),
// Full Access (r8-1, r8-2), a question in full and "/" (f4-1, f4-1b, f4-2) and My agents starting an agent (f4-4).
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import Testing
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-agents-"))
struct AcceptanceAgents {
    @Test("a1-1: The panel at rest: Agents, Info, History; the button's count", .disabled("not built yet: AG2")) func a1_1() async throws {}
    @Test("a1-2: Reading a row, each kind of agent", .disabled("not built yet: AG7")) func a1_2() async throws {}
    @Test("a1-3: At not see: the fallback, Show to This Space, Undo", .disabled("not built yet: AG3")) func a1_3() async throws {}
    @Test("a1-4: Modify: three chips, the ladder, the confirmation", .disabled("not built yet: AG4")) func a1_4() async throws {}
    @Test("a1-5: Talk: one card, its title's menu", .disabled("not built yet: AG5")) func a1_5() async throws {}
    @Test("a1-6: Read: no composer, Go to iTerm", .disabled("not built yet: AG5")) func a1_6() async throws {}
    @Test("a1-7: Hide: the page loses it, Undo", .disabled("not built yet: AG3")) func a1_7() async throws {}
    @Test("a1-8: + Start: the form, In something", .disabled("not built yet: AG6")) func a1_8() async throws {}
    @Test("a1-9: Others on This Mac, Look Again", .disabled("not built yet: AG2")) func a1_9() async throws {}
    @Test("a1-10: Continue in Terminal and in something, the sheet", .disabled("not built yet: AG7")) func a1_10() async throws {}
    @Test("a1-11: Quit and come back: who can't continue, Asleep", .disabled("not built yet: AG7")) func a1_11() async throws {}
    @Test("a1-12: ⌘P finds an agent; the window says its title; Show Agent", .disabled("not built yet: AG8")) func a1_12() async throws {}
    @Test("r9-1: Three chips, the picker", .disabled("not built yet: AG4")) func r9_1() async throws {}
    @Test("r9-2: A long list, search and groups", .disabled("not built yet: AG4")) func r9_2() async throws {}
    @Test("r9-3: Amp, and what is not known", .disabled("not built yet: AG4")) func r9_3() async throws {}
    @Test("r8-1: Full Access, the last rung", .disabled("not built yet: AG4")) func r8_1() async throws {}
    @Test("r8-2: The mark's two gestures", .disabled("not built yet: AG4")) func r8_2() async throws {}
    @Test("f4-1: A build's question in full", .disabled("not built yet: AG5")) func f4_1() async throws {}
    @Test("f4-1b: The same, in the window", .disabled("not built yet: AG5")) func f4_1b() async throws {}
    @Test("f4-2: \"/\" from the first try", .disabled("not built yet: AG5")) func f4_2() async throws {}
    @Test("f4-4: My agents starts an agent", .disabled("not built yet: AG6")) func f4_4() async throws {}
}
