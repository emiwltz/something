// Acceptance scenarios of the first start and making a space: the welcome and the film (a1–a8), New Space, the build
// ladder, the arrival, templates and the rights sheet (d1–d8).
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import Testing

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-build-"))
struct AcceptanceBuild {
    @Test("a1: the film on the glass", .disabled("not built yet: AB18")) func a1() async throws {}
    @Test("a2: welcome, step 1", .disabled("not built yet: AB17")) func a2() async throws {}
    @Test("a3: welcome, the builders", .disabled("not built yet: AB17")) func a3() async throws {}
    @Test("a4: welcome, launcher and notices", .disabled("not built yet: AB17")) func a4() async throws {}
    @Test("a5: welcome, the sticker and its keys", .disabled("not built yet: AB17")) func a5() async throws {}
    @Test("a6: welcome, the summary", .disabled("not built yet: AB17")) func a6() async throws {}
    @Test("a7: welcome with no builder", .disabled("not built yet: AB17")) func a7() async throws {}
    @Test("a8: welcome after the first hello", .disabled("not built yet: AB17")) func a8() async throws {}
    @Test("d1: New Space", .disabled("not built yet: AB12")) func d1() async throws {}
    @Test("d2: the build ladder", .disabled("not built yet: AB14")) func d2() async throws {}
    @Test("d3: the arrival", .disabled("not built yet: AB15")) func d3() async throws {}
    @Test("d4: the rights sheet", .disabled("not built yet: AB16")) func d4() async throws {}
    @Test("d5: templates", .disabled("not built yet: AB13")) func d5() async throws {}
    @Test("d6: a template's preview", .disabled("not built yet: AB13")) func d6() async throws {}
    @Test("d7: inline choices", .disabled("not built yet: AB14")) func d7() async throws {}
    @Test("d8: the check step", .disabled("not built yet: AB14")) func d8() async throws {}
}
