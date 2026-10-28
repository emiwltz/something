// The acceptance catalog, the interface's stop criterion: every screen id of the mockup Emi approved, with the one
// slice that builds it; round 2's frozen v6.2 steps join it as their slices land, their ids the step in lower case
// with a dash ("x9-1" for X9.1, its function x9_1; "2-6" for the numbered step 2.6, its function v2_6, after the
// mockup's chapter "v2"), each in the area file of its screen, and retire the old ids they
// replace. Each id's scenario lives in its area's file and carries `.disabled("not built yet: <slice>")` until that
// slice lands, removes the trait and gives it a body that asserts; whether an id is built is read from that file, so
// this catalog is only edited to bring back La page (b2 and the _p variants) or to mark an id shot. With
// SOMETHING_ACCEPT_STRICT=1 the end gate runs: it fails while any id that counts is still unbuilt or waits for its shots.
import Foundation
import Testing

enum Catalog {
    enum Status { case counted, pendingShots, excluded }

    /// The area files, by the first letter of the ids they hold (trust and stopped share e).
    enum Area: String, CaseIterable {
        case shell = "AcceptanceShell", assistant = "AcceptanceAssistant", build = "AcceptanceBuild",
             trust = "AcceptanceTrust", stopped = "AcceptanceStopped", show = "AcceptanceShow", command = "AcceptanceCommand"
    }

    /// Every screen id and the slice that removes its `.disabled` trait (the plan's screen map, one owner each).
    static let owners: [(id: String, slice: String)] = [
        ("b1", "W3"), ("b2", "W7"), ("b3", "W2"), ("b5", "W5"), ("b6", "W2"), ("b7", "W6"),
        ("c1", "AB05"), ("c2", "AB04"), ("c3", "AB10"), ("c4", "AB07"), ("c5", "AB11"), ("c6", "AB09b"), ("c7", "AB05"),
        ("c8", "AB08"), ("c9", "AB06"), ("c10", "AB07"),
        ("d4", "AB16"), ("d5", "AB13"), ("d6", "AB13"), ("d7", "AB14"), ("d8", "AB14"),
        ("e1", "T2"), ("e2", "T3"), ("e3", "T2"), ("e4", "T5"), ("e5", "T6"), ("e6", "T4"), ("e7", "T7"), ("e8", "T8"),
        ("e9", "T9"), ("e10", "T10"), ("e11", "T10"), ("e12", "T11"), ("e13", "T2"), ("e15", "T9"),
        ("f1", "T14"), ("f2", "T15"), ("f3", "T16"), ("f4", "T17"), ("f5", "T13"), ("f6", "T19"), ("f7", "T20"), ("f8", "T21"),
        ("f9", "T18"), ("f10", "T18"), ("f11", "T18"),
        ("g1", "G2"), ("g2", "G3"), ("g9", "F5"), ("g10", "G1"),
        ("b1_p", "W7"), ("c2_p", "W7"), ("d1_p", "W7"), ("e1_p", "W7"), ("f6_p", "W7"), ("g4_p", "W7"),
    ] + frozen
    /// Round 2's frozen steps, by the step in lower case with a dash ("x3-1" for X3.1; its scenario's function is
    /// x3_1; "2-6" for 2.6, v2_6), and the slice that builds each.
    static let frozen: [(id: String, slice: String)] = [
        ("x1-2", "S2"), ("x3-1", "S2"), ("x5-1", "S3"), ("x5-2", "S3"), ("x5-3", "S3"),
        ("x9-1", "S5"), ("x9-2", "S5"), ("j4-1", "S5"), ("j3-4", "S4"), ("x3-2", "S4"), ("x3-3", "S4"),
        ("2-1", "S6"), ("2-2", "S6"), ("2-6", "S6"), ("2-8", "S6"),
        ("j4-2", "S8"), ("x6-1", "S9"), ("x6-2", "S9"), ("x6-3", "S9"),
        ("x2-1", "S12"), ("x2-2", "S12"), ("x2-3", "S12"), ("x2-4", "S12"), ("x8-1", "S12"), ("x8-2", "S12"), ("x0-1", "S12"),
        ("6-1", "S7"), ("6-3", "S7"), ("x7-1", "S10"), ("x7-2", "S10"), ("x7-3", "S10"), ("x7-4", "S10"),
        ("x4-1", "S11"), ("x4-2", "S11"), ("x4-3", "S11"),
    ]
    /// The old ids whose screen a frozen step replaced: d1, New Space (x3-1); b4, Info (x5-1); b8, the rows' eyes,
    /// gone with v6.2's list of names (x9-1); d2, the build ladder (j3-4); d3, the arrival (x3-3); a1, the film, and
    /// a2–a8, the welcome's five steps, gone with v6.2's one welcome (x2-1); e14, the panel over the welcome that stepped
    /// the window back (the welcome now stands alone; WelcomeTests keeps the panel floating over it); g3–g8 and g11,
    /// Settings' seven tabs, gone with v6.2's four (x7-1 to x7-4).
    static let retired: Set<String> = ["d1", "b4", "b8", "d2", "d3", "a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "e14",
                                       "g3", "g4", "g5", "g6", "g7", "g8", "g11"]
    /// La page, pending Emi's decision: no scenario is written for these, and the gate does not count them.
    static let excluded: Set<String> = ["b2", "b1_p", "c2_p", "d1_p", "e1_p", "f6_p", "g4_p"]
    /// Drawn in the mockup only after the plan: they count, and the gate waits for them until they are marked shot.
    /// f9–f11, the last ones, have their shots and are built (T18): none waits.
    static let pendingShots: Set<String> = []

    static func status(_ id: String) -> Status { excluded.contains(id) ? .excluded : pendingShots.contains(id) ? .pendingShots : .counted }
    static func slice(_ id: String) -> String? { owners.first { $0.id == id }?.slice }

    /// The area file of a screen id.
    static func area(_ id: String) -> Area {
        let number = Int(id.dropFirst().prefix { $0.isNumber }) ?? 0
        if id.contains("-") {
            let areas: [String: Area] = ["x1": .shell, "x2": .build, "x3": .build, "x5": .shell, "x6": .assistant, "x9": .shell, "j3": .build, "j4": .shell, "x4": .trust,
                                         "2": .shell, "6": .command, "x7": .command]
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
            // A frozen step's function, x3_1, is the screen id x3-1; a numbered step's, v2_6, is 2-6.
            let step = name.range(of: #"^([xj]|v(?=[0-9]))[0-9]+_[0-9]+$"#, options: .regularExpression) != nil
            let id = step ? String(name.drop { $0 == "v" }).replacingOccurrences(of: "_", with: "-") : name
            guard id.contains("-") || id.range(of: #"^[a-g][0-9]+(_p)?$"#, options: .regularExpression) != nil else { return nil }
            let traits = part(match, 1) ?? ""
            let slice = unbuilt.firstMatch(in: traits, range: NSRange(traits.startIndex..., in: traits)).flatMap { Range($0.range(at: 1), in: traits) }
            // The body runs from the function's name to the next test, or to the end of the file.
            let end = index + 1 < matches.count ? matches[index + 1].range.location : (text as NSString).length
            let body = (text as NSString).substring(with: NSRange(location: match.range.upperBound, length: end - match.range.upperBound))
            let asserts = body.contains("#expect") || body.contains("#require")
            return Scenario(id: id, unbuilt: slice.map { String(traits[$0]) }, asserts: asserts)
        }
    }

    /// The ids the end gate still waits for, in the catalog's order: counted ones whose scenario is missing or
    /// disabled, and every one pending its shots.
    static func unfinished() throws -> [String] {
        let built = Set(try Area.allCases.flatMap(scenarios).filter(\.built).map(\.id))
        return owners.map(\.id).filter { status($0) == .pendingShots || (status($0) == .counted && !built.contains($0)) }
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
        #expect(Set(ids.filter { !$0.hasSuffix("_p") && !$0.contains("-") }) == Set(expected).subtracting(Catalog.retired))
        #expect(Catalog.frozen.allSatisfy { $0.id.range(of: #"^[xj]?[0-9]+-[0-9]+$"#, options: .regularExpression) != nil })
        #expect(Catalog.retired.isDisjoint(with: Set(ids)))
        #expect(Set(ids.filter { $0.hasSuffix("_p") }) == Catalog.excluded.subtracting(["b2"]))
        #expect(Catalog.excluded.isSubset(of: Set(ids)) && Catalog.pendingShots.isSubset(of: Set(ids)))
        #expect(owners.allSatisfy { !$0.slice.isEmpty })
    }

    /// Each area file holds the scenarios of its own ids, each once, none excluded, and a disabled one names the
    /// slice the catalog says builds it.
    @Test func eachAreaRegistersOnlyItsOwnIds() throws {
        for area in Catalog.Area.allCases {
            let scenarios = try Catalog.scenarios(area)
            let mine = owners.map(\.id).filter { Catalog.area($0) == area && Catalog.status($0) != .excluded }
            // The old ids in the catalog's order; a frozen step stands where its screen did.
            #expect(scenarios.map(\.id).filter { !$0.contains("-") } == mine.filter { !$0.contains("-") } && Set(scenarios.map(\.id)) == Set(mine),
                    "\(area.rawValue) registers \(scenarios.map(\.id)), its ids are \(mine)")
            for scenario in scenarios {
                if let slice = scenario.unbuilt { #expect(slice == Catalog.slice(scenario.id), "\(scenario.id) waits for \(slice)") }
                #expect(scenario.unbuilt != nil || scenario.asserts, "\(scenario.id) is enabled but asserts nothing")
            }
        }
    }

    /// The gate's list: every pending id is in it, no excluded one, and an id leaves it only once built.
    @Test func theGateListsWhatIsLeft() throws {
        let left = try Catalog.unfinished()
        #expect(Catalog.pendingShots.isSubset(of: Set(left)))
        #expect(Catalog.excluded.isDisjoint(with: Set(left)))
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
        let scenarios = try Catalog.scenarios(in: text)
        #expect(scenarios == [Catalog.Scenario(id: "b1", unbuilt: nil, asserts: false), Catalog.Scenario(id: "b3", unbuilt: nil, asserts: true),
                              Catalog.Scenario(id: "b4", unbuilt: "W4", asserts: false)])
        #expect(scenarios.map(\.built) == [false, true, false])
    }

    /// The end gate: zero ids left. It runs only when asked, since it fails until the last slice lands.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SOMETHING_ACCEPT_STRICT"] == "1", "SOMETHING_ACCEPT_STRICT is not 1."))
    func noScreenIsLeft() throws {
        let left = try Catalog.unfinished()
        #expect(left.isEmpty, "\(left.count) screen(s) not built or not shot: \(left.map { "\($0) (\(Catalog.slice($0) ?? "?"))" })")
    }

    var owners: [(id: String, slice: String)] { Catalog.owners }
}
