// The acceptance catalog, the interface's stop criterion: every screen id of the mockup Emi approved, with the one
// slice that builds it. Round 2's frozen v6.2 steps and round 4's final steps are ids too: the step in lower case with
// a dash ("x9-1" for X9.1, its function x9_1; "f2-1b" for F2.1b, f2_1b; "2-6" for the numbered step 2.6, its function
// v2_6, after the mockup's chapter "v2"), each in the area file of its screen. An id retires when a final step draws
// the same moment, in the slice that lands that step, or goes with what it showed; a step no scenario draws is retired
// with its reason (`retiredSteps`). Each id's scenario lives in its area's file and carries
// `.disabled("not built yet: <slice>")` until that slice lands, removes the trait and gives it a body that asserts;
// whether an id is built is read from that file, so this catalog is only edited to retire an id or to mark one shot.
// With SOMETHING_ACCEPT_STRICT=1 the end gate runs: it fails while any id that counts is still unbuilt or waits for
// its shots.
import Foundation
import Testing

enum Catalog {
    enum Status { case counted, pendingShots }

    /// The area files, by the letters of the ids they hold (trust and stopped share e).
    enum Area: String, CaseIterable {
        case shell = "AcceptanceShell", assistant = "AcceptanceAssistant", build = "AcceptanceBuild",
             trust = "AcceptanceTrust", stopped = "AcceptanceStopped", show = "AcceptanceShow", command = "AcceptanceCommand",
             agents = "AcceptanceAgents"
    }

    /// Every screen id and the slice that removes its `.disabled` trait (the plan's screen map, one owner each).
    static let owners: [(id: String, slice: String)] = [
        ("b1", "W3"), ("b3", "W2"), ("b5", "W5"), ("b6", "W2"),
        ("c1", "AB05"), ("c2", "AB04"), ("c3", "AB10"), ("c4", "AB07"), ("c5", "AB11"), ("c6", "AB09b"), ("c7", "AB05"),
        ("c8", "AB08"), ("c9", "AB06"), ("c10", "AB07"),
        ("d4", "AB16"), ("d5", "AB13"), ("d6", "AB13"), ("d7", "AB14"), ("d8", "AB14"),
        ("e1", "T2"), ("e2", "T3"), ("e3", "T2"), ("e4", "T5"), ("e5", "T6"), ("e6", "T4"), ("e7", "T7"), ("e8", "T8"),
        ("e9", "T9"), ("e10", "T10"), ("e11", "T10"), ("e12", "T11"), ("e13", "T2"), ("e15", "T9"),
        ("f1", "T14"), ("f2", "T15"), ("f3", "T16"), ("f4", "T17"), ("f5", "T13"), ("f6", "T19"), ("f7", "T20"), ("f8", "T21"),
        ("f9", "T18"), ("f10", "T18"), ("f11", "T18"),
        ("g1", "G2"), ("g2", "G3"), ("g9", "F5"), ("g10", "G1"),
    ] + frozen + final
    /// Round 2's frozen steps, by the step in lower case with a dash ("x3-1" for X3.1; its scenario's function is
    /// x3_1; "2-6" for 2.6, v2_6), and the slice that builds each.
    static let frozen: [(id: String, slice: String)] = [
        ("x1-2", "S2"), ("x3-1", "S2"), ("x5-1", "S3"), ("x5-2", "S3"), ("x5-3", "S3"),
        ("x9-1", "S5"), ("j3-4", "S4"), ("x3-2", "S4"), ("x3-3", "S4"),
        ("2-1", "S6"), ("2-2", "S6"), ("2-6", "S6"), ("2-8", "S6"),
        ("j4-2", "S8"), ("x6-1", "S9"), ("x6-2", "S9"), ("x6-3", "S9"),
        ("x2-1", "S12"), ("x2-2", "S12"), ("x2-3", "S12"), ("x2-4", "S12"), ("x8-1", "S12"), ("x8-2", "S12"), ("x0-1", "S12"),
        ("6-1", "S7"), ("6-3", "S7"), ("x7-1", "S10"), ("x7-2", "S10"), ("x7-3", "S10"), ("x7-4", "S10"),
        ("x4-1", "S11"), ("x4-2", "S11"), ("x4-3", "S11"),
        ("x1-1", "S14b"), ("x1-3", "S14b"), ("2-9", "S14b"), ("2-10", "S14b"),
    ]
    /// Round 4's final steps, each with the slice that finishes it: a step several slices build in turn keeps its trait
    /// until the last, the earlier ones asserting in a test without an id, so that the gate never counts half a screen.
    static let final: [(id: String, slice: String)] = [
        ("f1-1", "S7"), ("f1-2", "S8"), ("f1-3", "S8"), ("f1-4", "S8"), ("f1-5", "S7"), ("f1-6", "S7"), ("f1-7", "S9"),
        ("f1-8", "S9"), ("f1-9", "S8"), ("f1-10", "S9"), ("r1-1", "C1"), ("r1-2", "C1"), ("r2-1", "C7"), ("r2-2", "C7"),
        ("r3-1", "C7"), ("r3-2", "C3"), ("r3-3", "C4"), ("r3-4", "C4"), ("f2-1", "C5"), ("f2-1b", "C5"), ("r4-1", "S3"),
        ("r4-2", "S2"), ("r4-3", "S2"), ("r4-4", "S2"), ("f3-1", "AG8"), ("r5-1", "S4"), ("r5-2", "S4"), ("r5-3", "C1"),
        ("f3-2", "C8"), ("f3-3", "S10"), ("a1-1", "AG2"), ("a1-2", "AG7"), ("a1-3", "AG3"), ("a1-4", "AG4"), ("a1-5", "AG5"),
        ("a1-6", "AG5"), ("a1-7", "AG3"), ("a1-8", "AG6"), ("a1-9", "AG2"), ("a1-10", "AG7"), ("a1-11", "AG7"), ("a1-12", "AG8"),
        ("r9-1", "AG4"), ("r9-2", "AG4"), ("r9-3", "AG4"), ("r8-1", "AG4"), ("r8-2", "AG4"), ("f4-1", "AG5"), ("f4-1b", "AG5"),
        ("f4-2", "AG5"), ("f4-4", "AG6"), ("r6-1", "S5"), ("r6-2", "S5"), ("r7-1", "S6"), ("r7-2", "S6"), ("r7-3", "S6"),
        ("f5-1", "S6"), ("f5-2", "S6"), ("f6-1", "C8"), ("f6-2", "C9"), ("f6-2b", "C9"), ("f6-3", "S10"),
    ]
    /// Every step of the frozen mockup v6.2 and of the final mockup that has a reference picture, by its id: each is a
    /// scenario of `frozen` or `final`, or retired in `retiredSteps`, never both.
    static let steps: Set<String> = Set([
        "2-1", "2-2", "2-4", "2-6", "2-8", "2-9", "2-10", "6-1", "6-3", "j3-4", "j4-1", "j4-2", "j4-4", "x0-1",
        "x1-1", "x1-2", "x1-3", "x2-1", "x2-2", "x2-3", "x2-4", "x3-1", "x3-2", "x3-3", "x4-1", "x4-2", "x4-3",
        "x5-1", "x5-2", "x5-3", "x6-1", "x6-2", "x6-3", "x7-1", "x7-2", "x7-3", "x7-4", "x8-1", "x8-2", "x9-1", "x9-2", "xe-1",
        "f0-1", "f0-2", "f0-3", "f0-4", "ye-1",
    ] + final.map(\.id))
    /// The frozen steps no scenario draws, each with why: what they showed was replaced by a later step Emi chose, or
    /// is no screen of its own.
    static let retiredSteps: [String: String] = [
        "2-4": "the title's small card: v6.2's title opens Info itself (X9.1, S5), asserted by x9-1",
        "j4-4": "the card's mode chip and \"/\" chip: v6.2's minimal card has neither (X6.1–X6.3, S9); \"/\" in the field is x6-3, the mode Settings › Advanced (x7-4)",
        "xe-1": "the whole mockup to try, every axis at Emi's letter: no screen of its own, each part asserted by its step",
        "x9-2": "the rail's tiles: subject 4 C removes the rail, r4-2 proves the list",
        "j4-1": "finding a space in the rail: subject 4 C removes it; r4-2 finds a space, f3-1 says what waits",
        "f0-1": "a note for Emi, his choices: no screen",
        "f0-2": "a note for Emi, the vision: no screen",
        "f0-3": "a note for Emi, his recovered requests: no screen",
        "f0-4": "a note for Emi, the concepts: no screen",
        "ye-1": "the whole final mockup to try: no screen of its own, each part asserted by its step",
    ]
    /// The old ids whose screen a frozen step replaced: d1, New Space (x3-1); b4, Info (x5-1); b8, the rows' eyes,
    /// gone with v6.2's list of names (x9-1); d2, the build ladder (j3-4); d3, the arrival (x3-3); a1, the film, and
    /// a2–a8, the welcome's five steps, gone with v6.2's one welcome (x2-1); e14, the panel over the welcome that stepped
    /// the window back (the welcome now stands alone; WelcomeTests keeps the panel floating over it); g3–g8 and g11,
    /// Settings' seven tabs, gone with v6.2's four (x7-1 to x7-4); b7, the rail, which subject 4 C removes; b2, La page,
    /// with its variants: the final mockup's f3 steps are its screens. An old id whose heir is not built stays, and
    /// stays asserted, until the heir's slice retires it.
    static let retired: Set<String> = ["d1", "b2", "b4", "b7", "b8", "d2", "d3", "a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "e14",
                                       "g3", "g4", "g5", "g6", "g7", "g8", "g11"]
    /// Drawn in the mockup only after the plan: they count, and the gate waits for them until they are marked shot.
    /// f9–f11, the last ones, have their shots and are built (T18): none waits.
    static let pendingShots: Set<String> = []

    static func status(_ id: String) -> Status { pendingShots.contains(id) ? .pendingShots : .counted }
    static func slice(_ id: String) -> String? { owners.first { $0.id == id }?.slice }

    /// The area file of a screen id.
    static func area(_ id: String) -> Area {
        let number = Int(id.dropFirst().prefix { $0.isNumber }) ?? 0
        if id.contains("-") {
            let areas: [String: Area] = ["x1": .shell, "x2": .build, "x3": .build, "x5": .shell, "x6": .assistant, "x9": .shell, "j3": .build, "j4": .shell, "x4": .trust,
                                         "2": .shell, "6": .command, "x7": .command,
                                         "f1": .build, "r1": .build, "r2": .build, "r3": .build, "f2": .build, "r4": .shell, "f3": .shell, "r5": .shell, "f6": .shell,
                                         "a1": .agents, "r8": .agents, "r9": .agents, "f4": .agents, "r6": .command, "r7": .command, "f5": .command]
            return areas[String(id.prefix { $0 != "-" })] ?? .command
        }
        switch id.first {
        case "a", "d": return .build
        case "b": return .shell
        case "c": return .assistant
        case "e": return (10...12).contains(number) ? .stopped : .trust
        case "f": return .show
        default: return .command
        }
    }

    /// A scenario as its area file declares it: the screen id (its function's name), the slice its
    /// `.disabled("not built yet: <slice>")` names (nil once the trait is gone), and whether its text, up to the next
    /// test, holds an `#expect` or a `#require`. An id is built only when it has no trait and asserts: removing the
    /// trait from an empty body does not build it.
    struct Scenario: Equatable {
        let id: String, unbuilt: String?, asserts: Bool
        var built: Bool { unbuilt == nil && asserts }
    }

    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    /// The screen scenarios of `area`'s file, in order; functions that are not screen ids (b1's frame) are left out.
    static func scenarios(_ area: Area) throws -> [Scenario] {
        try scenarios(in: String(contentsOf: folder.appendingPathComponent("\(area.rawValue).swift"), encoding: .utf8))
    }

    /// The screen scenarios declared in `text`, a Swift file's source, in order.
    static func scenarios(in text: String) throws -> [Scenario] {
        let test = try NSRegularExpression(pattern: #"@Test(?:\((.*?)\))?\s+func\s+(\w+)\("#, options: .dotMatchesLineSeparators)
        let unbuilt = try NSRegularExpression(pattern: #"\.disabled\("not built yet: ([A-Za-z0-9-]+)"\)"#)
        func part(_ match: NSTextCheckingResult, _ group: Int) -> String? { Range(match.range(at: group), in: text).map { String(text[$0]) } }
        let matches = test.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.enumerated().compactMap { index, match in
            guard let name = part(match, 2) else { return nil }
            // A step's function, x3_1, is the screen id x3-1; f2_1b is f2-1b; a numbered step's, v2_6, is 2-6.
            let step = name.range(of: #"^([xjfra]|v(?=[0-9]))[0-9]+_[0-9]+b?$"#, options: .regularExpression) != nil
            let id = step ? String(name.drop { $0 == "v" }).replacingOccurrences(of: "_", with: "-") : name
            guard id.contains("-") || id.range(of: #"^[a-g][0-9]+$"#, options: .regularExpression) != nil else { return nil }
            let traits = part(match, 1) ?? ""
            let slice = unbuilt.firstMatch(in: traits, range: NSRange(traits.startIndex..., in: traits)).flatMap { Range($0.range(at: 1), in: traits) }
            // The body runs from the function's name to the next test or the first brace at column 0, the suite's end:
            // what follows the suite in its file (an extension's #require) is no part of the last scenario.
            let next = index + 1 < matches.count ? matches[index + 1].range.location : (text as NSString).length
            var body = (text as NSString).substring(with: NSRange(location: match.range.upperBound, length: next - match.range.upperBound))
            if let close = body.range(of: "\n}") { body = String(body[..<close.upperBound]) }
            let asserts = body.contains("#expect") || body.contains("#require")
            // Any other .disabled is unbuilt too: a scenario switched off proves nothing.
            return Scenario(id: id, unbuilt: slice.map { String(traits[$0]) } ?? (traits.contains(".disabled(") ? "?" : nil), asserts: asserts)
        }
    }

    /// The ids the end gate still waits for, in the catalog's order: counted ones whose scenario is missing or
    /// disabled, and every one pending its shots.
    static func unfinished() throws -> [String] {
        let built = Set(try Area.allCases.flatMap(scenarios).filter(\.built).map(\.id))
        return owners.map(\.id).filter { status($0) == .pendingShots || !built.contains($0) }
    }
}

@Suite struct AcceptanceTests {
    @Test func everyIdHasOneEntryAndOneOwner() {
        let ids = owners.map(\.id)
        #expect(Set(ids).count == ids.count, "an id is listed twice")
        let expected = [("a", 8), ("b", 8), ("c", 10), ("d", 8), ("e", 15), ("f", 11), ("g", 11)].flatMap { letter, count in
            (1...count).map { "\(letter)\($0)" }
        }
        #expect(expected.count == 71)
        #expect(Set(ids.filter { !$0.contains("-") }) == Set(expected).subtracting(Catalog.retired))
        #expect((Catalog.frozen + Catalog.final).allSatisfy { $0.id.range(of: #"^[xjfra]?[0-9]+-[0-9]+b?$"#, options: .regularExpression) != nil })
        #expect(Catalog.final.count == 62)
        // Every step is asserted by a scenario or retired with its reason, not both.
        let drawn = Set((Catalog.frozen + Catalog.final).map(\.id)), retired = Set(Catalog.retiredSteps.keys)
        #expect(drawn.isDisjoint(with: retired) && drawn.union(retired) == Catalog.steps,
                "missing \(Catalog.steps.subtracting(drawn.union(retired)).sorted()), unknown \(drawn.union(retired).subtracting(Catalog.steps).sorted())")
        #expect(Catalog.retiredSteps.values.allSatisfy { !$0.isEmpty })
        #expect(Catalog.retired.isDisjoint(with: Set(ids)))
        #expect(Catalog.pendingShots.isSubset(of: Set(ids)))
        #expect(owners.allSatisfy { !$0.slice.isEmpty })
    }

    /// Each area file holds the scenarios of its own ids, each once, and a disabled one names the slice the catalog
    /// says builds it.
    @Test func eachAreaRegistersOnlyItsOwnIds() throws {
        for area in Catalog.Area.allCases {
            let scenarios = try Catalog.scenarios(area)
            let mine = owners.map(\.id).filter { Catalog.area($0) == area }
            // The old ids in the catalog's order; a frozen step stands where its screen did.
            #expect(scenarios.map(\.id).filter { !$0.contains("-") } == mine.filter { !$0.contains("-") } && Set(scenarios.map(\.id)) == Set(mine),
                    "\(area.rawValue) registers \(scenarios.map(\.id)), its ids are \(mine)")
            for scenario in scenarios {
                if let slice = scenario.unbuilt { #expect(slice == Catalog.slice(scenario.id), "\(scenario.id) waits for \(slice)") }
                #expect(scenario.unbuilt != nil || scenario.asserts, "\(scenario.id) is enabled but asserts nothing")
            }
        }
    }

    /// The gate's list: every pending id is in it, and an id leaves it only once built.
    @Test func theGateListsWhatIsLeft() throws {
        let left = try Catalog.unfinished()
        #expect(Catalog.pendingShots.isSubset(of: Set(left)))
        let unbuilt = try Catalog.Area.allCases.flatMap(Catalog.scenarios).filter { !$0.built }.map(\.id)
        #expect(Set(unbuilt).isSubset(of: Set(left)))
    }

    /// An id whose trait is gone counts as built only when its body asserts something.
    @Test func anEmptyEnabledScenarioIsNotBuilt() throws {
        let text = """
            @Test("b1: the window") func b1() async throws {}
            /// A doc comment.
            @Test("b3: sidebar groups") func b3() async throws {
                #expect(true)
            }
            @Test("b4: Info", .disabled("not built yet: W4")) func b4() async throws {}
            """
        #expect(try Catalog.scenarios(in: "@Test(\"x9-1: the toolbar\") func x9_1() async throws {\n#expect(true)\n}")
                == [Catalog.Scenario(id: "x9-1", unbuilt: nil, asserts: true)])
        #expect(try Catalog.scenarios(in: "@Test(\"2-6: Page Full Screen\") func v2_6() async throws {\n#expect(true)\n}")
                == [Catalog.Scenario(id: "2-6", unbuilt: nil, asserts: true)])
        #expect(try Catalog.scenarios(in: "@Test(\"f2-1b: one problem left\") func f2_1b() async throws {\n#expect(true)\n}")
                == [Catalog.Scenario(id: "f2-1b", unbuilt: nil, asserts: true)])
        // A stub that ends its suite does not take in what follows the suite, nor does a foreign .disabled build it.
        let last = "@Test(\"f2-1b: one\") func f2_1b() async throws {}\n}\n\nextension Picture {\n    func f() { #expect(true) }\n}"
        #expect(try Catalog.scenarios(in: last) == [Catalog.Scenario(id: "f2-1b", unbuilt: nil, asserts: false)])
        #expect(try Catalog.scenarios(in: "@Test(\"x9-1: a\", .disabled(\"flaky\")) func x9_1() async throws {\n#expect(true)\n}")
                == [Catalog.Scenario(id: "x9-1", unbuilt: "?", asserts: true)])
        let scenarios = try Catalog.scenarios(in: text)
        #expect(scenarios == [Catalog.Scenario(id: "b1", unbuilt: nil, asserts: false), Catalog.Scenario(id: "b3", unbuilt: nil, asserts: true),
                              Catalog.Scenario(id: "b4", unbuilt: "W4", asserts: false)])
        #expect(scenarios.map(\.built) == [false, true, false])
    }

    /// The Stage's world is the final mockup's: eleven agents with their titles, each with where it runs, and each
    /// space's list made only of them.
    @MainActor @Test func theStagesWorldIsTheMockups() throws {
        let world = Stage.world, ids = world.agents.map(\.id)
        #expect(ids.count == 11 && Set(ids) == Set(Stage.runs.keys) && Set(world.threads.map(\.agent)).isSubset(of: Set(ids)))
        #expect(world.agents.allSatisfy { $0.name?.isEmpty == false && $0.folder != nil })
        #expect(world.threads.count == 10, "Antigravity is seen only by its process: it has no thread")
        #expect(Stage.these.mapValues(\.count) == ["agents": 5, "brief": 3, "project": 2, "logbook": 2, "pet": 1, "week-end": 3, "oracle": 0, "stack": 0])
        #expect(Set(Stage.these.values.flatMap { $0 }).isSubset(of: Set(ids)) && !ids.contains(Stage.twelfth.id))
    }

    /// The end gate: zero ids left. It runs only when asked, since it fails until the last slice lands.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SOMETHING_ACCEPT_STRICT"] == "1", "SOMETHING_ACCEPT_STRICT is not 1."))
    func noScreenIsLeft() throws {
        let left = try Catalog.unfinished()
        #expect(left.isEmpty, "\(left.count) screen(s) not built or not shot: \(left.map { "\($0) (\(Catalog.slice($0) ?? "?"))" })")
    }

    var owners: [(id: String, slice: String)] { Catalog.owners }
}
