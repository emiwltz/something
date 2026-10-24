// The acceptance catalog, the interface's stop criterion: every screen id of the mockup Emi approved, with the one
// slice that builds it. Each id's scenario lives in its area's file and carries `.disabled("not built yet: <slice>")`
// until that slice lands, removes the trait and gives it a body that asserts; whether an id is built is read from
// that file, so this catalog is only edited to bring back La page (b2 and the _p variants) or to mark f9–f11 shot. With SOMETHING_ACCEPT_STRICT=1
// the end gate runs: it fails while any id that counts is still unbuilt or waits for its shots.
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
        ("a1", "AB18"), ("a2", "AB17"), ("a3", "AB17"), ("a4", "AB17"), ("a5", "AB17"), ("a6", "AB17"), ("a7", "AB17"), ("a8", "AB17"),
        ("b1", "W3"), ("b2", "W7"), ("b3", "W2"), ("b4", "W4"), ("b5", "W5"), ("b6", "W2"), ("b7", "W6"), ("b8", "W3"),
        ("c1", "AB05"), ("c2", "AB04"), ("c3", "AB10"), ("c4", "AB07"), ("c5", "AB11"), ("c6", "AB09b"), ("c7", "AB05"),
        ("c8", "AB08"), ("c9", "AB06"), ("c10", "AB07"),
        ("d1", "AB12"), ("d2", "AB14"), ("d3", "AB15"), ("d4", "AB16"), ("d5", "AB13"), ("d6", "AB13"), ("d7", "AB14"), ("d8", "AB14"),
        ("e1", "T2"), ("e2", "T3"), ("e3", "T2"), ("e4", "T5"), ("e5", "T6"), ("e6", "T4"), ("e7", "T7"), ("e8", "T8"),
        ("e9", "T9"), ("e10", "T10"), ("e11", "T10"), ("e12", "T11"), ("e13", "T2"), ("e14", "AB17w"), ("e15", "T9"),
        ("f1", "T14"), ("f2", "T15"), ("f3", "T16"), ("f4", "T17"), ("f5", "T13"), ("f6", "T19"), ("f7", "T20"), ("f8", "T21"),
        ("f9", "T18"), ("f10", "T18"), ("f11", "T18"),
        ("g1", "G2"), ("g2", "G3"), ("g3", "G4"), ("g4", "G5"), ("g5", "G5"), ("g6", "G4"), ("g7", "G4"), ("g8", "G6"),
        ("g9", "F5"), ("g10", "G1"), ("g11", "G5"),
        ("b1_p", "W7"), ("c2_p", "W7"), ("d1_p", "W7"), ("e1_p", "W7"), ("f6_p", "W7"), ("g4_p", "W7"),
    ]
    /// La page, pending Emi's decision: no scenario is written for these, and the gate does not count them.
    static let excluded: Set<String> = ["b2", "b1_p", "c2_p", "d1_p", "e1_p", "f6_p", "g4_p"]
    /// Drawn in the mockup only after the plan: they count, and the gate waits for them until they are marked shot.
    static let pendingShots: Set<String> = ["f9", "f10", "f11"]

    static func status(_ id: String) -> Status { excluded.contains(id) ? .excluded : pendingShots.contains(id) ? .pendingShots : .counted }
    static func slice(_ id: String) -> String? { owners.first { $0.id == id }?.slice }

    /// The area file of a screen id.
    static func area(_ id: String) -> Area {
        let number = Int(id.dropFirst().prefix { $0.isNumber }) ?? 0
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

    /// The screen scenarios of `area`'s file, in order; functions that are not screen ids (a baseline) are left out.
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
            guard let id = part(match, 2), id.range(of: #"^[a-g][0-9]+(_p)?$"#, options: .regularExpression) != nil else { return nil }
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
        #expect(Set(ids.filter { !$0.hasSuffix("_p") }) == Set(expected))
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
            #expect(scenarios.map(\.id) == mine, "\(area.rawValue) registers \(scenarios.map(\.id)), its ids are \(mine)")
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
