// Rights: what covers what, the scope on whole path components, the granted a space receives, the grants file, and
// what an opening asks again.
import Foundation
import Testing
@testable import SomethingCore

struct RightsTests {
    let home = URL(fileURLWithPath: "/Users/example")

    func declaration(_ rights: [String], agents: Scope = .all, folder: String? = nil) -> Declaration {
        var declaration = Declaration(name: "example")
        (declaration.rights, declaration.agents, declaration.folder) = (rights, agents, folder)
        return declaration
    }

    @Test func aRightWithoutAKindCoversEveryKindNeverTheReverse() {
        #expect(Rights.covers(["send"], "send:claude"))
        #expect(Rights.covers(["send:claude"], "send:claude"))
        #expect(!Rights.covers(["send:claude"], "send"))
        #expect(!Rights.covers(["send:claude"], "send:codex"))
        #expect(!Rights.covers(["sen"], "send:claude"))
        #expect(!Rights.covers(["state"], "store"))
    }

    @Test func scopesMatchWholePathComponents() {
        #expect(Rights.inside("/Users/example/code/shop", "/Users/example/code/shop"))
        #expect(Rights.inside("/Users/example/code/shop/web", "/Users/example/code/shop/"))
        #expect(!Rights.inside("/Users/example/code/shop2", "/Users/example/code/shop"))
        #expect(!Rights.inside("/Users/example/code/shop/../blog", "/Users/example/code/shop"))
        #expect(Rights.inside("/Users/example", "/"))
        #expect(Rights.contains(.all, nil))
        #expect(!Rights.contains(.folders(["/Users/example"]), nil), "an agent whose folder is unknown is in no folder scope")
        #expect(Rights.contains(.folders(["/Users/example/code/blog", "/Users/example/code/shop"]), "/Users/example/code/shop/web"))
    }

    @Test func grantedListsWhatWasAllowedRefusedAndCannotBe() throws {
        var reading = DeclarationReading()
        reading.declaration = declaration(["state", "send:claude", "launch:codex", "store"], agents: .folders(["~/code/shop"]))
        reading.unavailable = ["launch:omp"]
        var grant = Grant(declared: Asked(reading.declaration!), at: "2026-10-17T09:00:00Z")
        (grant.granted, grant.refused, grant.folder) = (["state", "send:claude"], ["launch:codex"], "/Users/example/code/shop")
        let granted = Rights.granted(reading, grant, limits: ["claude": ["effort"]], home: home)
        #expect(granted.rights == ["state", "send:claude"])
        #expect(granted.refused == ["launch:codex"])
        #expect(granted.unavailable == ["launch:omp"])
        #expect(granted.limits == ["claude": ["effort"]])
        #expect(granted.agents == .folders(["/Users/example/code/shop"]))
        #expect(granted.folder == "/Users/example/code/shop")
        // store was never answered: neither allowed nor refused yet.
        #expect(!granted.rights.contains("store") && !granted.refused.contains("store"))
    }

    @Test func aRightNoLongerDeclaredIsNoLongerGranted() {
        var reading = DeclarationReading()
        reading.declaration = declaration(["state"])
        var grant = Grant(declared: Asked(declaration(["state", "store"])), at: "2026-10-17T09:00:00Z")
        grant.granted = ["state", "store"]
        #expect(Rights.granted(reading, grant, limits: [:], home: home).rights == ["state"])
        // A wider right keeps the narrower one already allowed until the person answers the wider one.
        reading.declaration = declaration(["send"])
        grant.granted = ["send:claude"]
        #expect(Rights.granted(reading, grant, limits: [:], home: home).rights == ["send:claude"])
        #expect(Rights.granted(DeclarationReading(), grant, limits: [:], home: home).rights.isEmpty, "a space that cannot display gets nothing")
    }

    @Test func theFirstOpeningAsksEverything() {
        let ask = Rights.toAsk(declaration(["state", "launch:claude"]), since: nil)
        #expect(ask == ToAsk(rights: ["state", "launch:claude"], scope: true, folder: true))
        #expect(Rights.toAsk(declaration(["state"]), since: nil).folder == false, "no launch right, no folder to choose")
        #expect(!Rights.toAsk(declaration(["store"]), since: nil).scope, "without state, the scope shows nothing")
    }

    @Test func theScopeIsAskedWithState() {
        let store = declaration(["store"], agents: .all)
        let grant = Rights.answered(store, allowed: ["store"], refused: [], folder: nil, at: "2026-10-17T09:00:00Z", after: nil)
        #expect(Rights.toAsk(declaration(["store", "state"], agents: .all), since: grant) == ToAsk(rights: ["state"], scope: true, folder: false),
                "state added later shows the scope it sees, though the scope was answered with store")
        let refused = Rights.answered(declaration(["state"]), allowed: [], refused: ["state"], folder: nil, at: "2026-10-17T09:00:00Z", after: nil)
        #expect(Rights.toAsk(declaration(["state"], agents: .all), since: refused).isEmpty, "a refused state asks no scope, even a wider one")
    }

    @Test func laterOpeningsAskOnlyWhatChanged() {
        let first = declaration(["state", "send", "launch"], agents: .folders(["~/code"]), folder: "~/code/shop")
        let grant = Rights.answered(first, allowed: ["state", "launch"], refused: ["send"], folder: "/Users/example/code/shop",
                                    at: "2026-10-17T09:00:00Z", after: nil)
        #expect(Rights.toAsk(first, since: grant).isEmpty, "nothing changed, nothing asked; the refusal is remembered")
        #expect(Rights.toAsk(declaration(["state", "send:claude", "launch"], agents: .folders(["~/code"]), folder: "~/code/shop"), since: grant).isEmpty,
                "a narrower right of a refused one stays refused")
        #expect(Rights.toAsk(declaration(["state", "store", "launch"], agents: .folders(["~/code"]), folder: "~/code/shop"), since: grant).rights == ["store"])
        #expect(Rights.toAsk(declaration(["state", "launch"], agents: .folders(["~/code/shop"]), folder: "~/code/shop"), since: grant).isEmpty,
                "a narrower scope is not asked")
        #expect(Rights.toAsk(declaration(["state", "launch"], agents: .folders(["~/notes"]), folder: "~/code/shop"), since: grant).scope)
        #expect(Rights.toAsk(declaration(["state", "launch"], agents: .folders(["~/code2"]), folder: "~/code/shop"), since: grant).scope)
        #expect(Rights.toAsk(declaration(["state", "launch"], agents: .all, folder: "~/code/shop"), since: grant).scope)
        #expect(Rights.toAsk(declaration(["state", "launch"], agents: .folders(["~/code"]), folder: "~/code/blog"), since: grant).folder)
    }

    @Test func aLaterAnswerReplacesTheEarlierOneForTheSameRight() {
        let d = declaration(["state", "store"])
        var grant = Rights.answered(d, allowed: ["state"], refused: ["store"], folder: nil, at: "2026-10-17T09:00:00Z", after: nil)
        grant = Rights.answered(d, allowed: ["store"], refused: ["state"], folder: nil, at: "2026-10-17T10:00:00Z", after: grant)
        #expect(grant.granted == ["store"] && grant.refused == ["state"])
        #expect(grant.at == "2026-10-17T10:00:00Z" && grant.folder == nil)
    }

    @Test func theGrantsFileRoundTripsAndAnUnreadableOneIsNotErased() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("grants-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("something/app.json")
        #expect(try AppFile.read(url) == AppFile())
        var file = AppFile()
        file.default = "agents"
        file.spaces["morning-review"] = Rights.answered(declaration(["state"]), allowed: ["state"], refused: [], folder: nil,
                                                        at: "2026-10-17T09:00:00Z", after: nil)
        try file.write(url)
        #expect(try AppFile.read(url) == file)
        try Data("{".utf8).write(to: url)
        #expect(throws: SpaceError.self) { try AppFile.read(url) }
        #expect(try Data(contentsOf: url) == Data("{".utf8))
        // Every key of a grant is required: a file edited by hand without remap is unreadable, not read half.
        let withoutRemap = #"{"app":1,"spaces":{"x":{"declared":{"rights":[],"agents":{"see":"all"}},"granted":[],"refused":[],"at":"2026-10-17T09:00:00Z"}}}"#
        try Data(withoutRemap.utf8).write(to: url)
        #expect(throws: SpaceError.self) { try AppFile.read(url) }
    }

    @Test func aScopeFolderNotOnThisMacIsReplacedByTheOneThePersonChose() {
        var reading = DeclarationReading()
        reading.declaration = declaration(["state"], agents: .folders(["~/code/shop", "~/code/blog"]))
        var grant = Grant(declared: Asked(reading.declaration!), at: "2026-10-17T09:00:00Z")
        grant.remap = ["~/code/shop": "/Users/example/work/shop"]
        #expect(Rights.granted(reading, grant, limits: [:], home: home).agents == .folders(["/Users/example/work/shop", "/Users/example/code/blog"]))
    }
}
