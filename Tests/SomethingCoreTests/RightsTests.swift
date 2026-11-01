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
        #expect(granted.rights == ["state", "send:claude", "store"])
        #expect(granted.refused == ["launch:codex"])
        #expect(granted.unavailable == ["launch:omp"])
        #expect(granted.limits == ["claude": ["effort"]])
        #expect(granted.agents == .folders(["/Users/example/code/shop"]))
        #expect(granted.folder == "/Users/example/code/shop")
        // A space's memory needs no permission: store is granted though nobody answered it.
        #expect(granted.rights.contains("store") && !granted.refused.contains("store"))
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
        #expect(Rights.toAsk(declaration(["store"]), since: nil).isEmpty, "memory is never asked, nor a scope without state")
        #expect(Rights.toAsk(declaration([], agents: .all, folder: "~/code/shop"), since: nil).isEmpty, "a space with no right is asked nothing")
    }

    @Test func theScopeIsAskedWithState() {
        let send = declaration(["send"], agents: .all)
        let grant = Rights.answered(send, allowed: ["send"], refused: [], folder: nil, at: "2026-10-17T09:00:00Z", after: nil)
        #expect(Rights.toAsk(declaration(["send", "state"], agents: .all), since: grant) == ToAsk(rights: ["state"], scope: true, folder: false),
                "state added later shows the scope it sees, though the scope was answered with send")
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
        #expect(Rights.toAsk(declaration(["state", "store", "launch"], agents: .folders(["~/code"]), folder: "~/code/shop"), since: grant).isEmpty,
                "memory added later is not asked")
        #expect(Rights.toAsk(declaration(["state", "launch"], agents: .folders(["~/code/shop"]), folder: "~/code/shop"), since: grant).isEmpty,
                "a narrower scope is not asked")
        #expect(Rights.toAsk(declaration(["state", "launch"], agents: .folders(["~/notes"]), folder: "~/code/shop"), since: grant).scope)
        #expect(Rights.toAsk(declaration(["state", "launch"], agents: .folders(["~/code2"]), folder: "~/code/shop"), since: grant).scope)
        #expect(Rights.toAsk(declaration(["state", "launch"], agents: .all, folder: "~/code/shop"), since: grant).scope)
        #expect(Rights.toAsk(declaration(["state", "launch"], agents: .folders(["~/code"]), folder: "~/code/blog"), since: grant).folder)
    }

    @Test func aLaterAnswerReplacesTheEarlierOneForTheSameRight() {
        let d = declaration(["state", "send"])
        var grant = Rights.answered(d, allowed: ["state"], refused: ["send"], folder: nil, at: "2026-10-17T09:00:00Z", after: nil)
        grant.level = .watch
        grant = Rights.answered(d, allowed: ["send"], refused: ["state"], folder: nil, at: "2026-10-17T10:00:00Z", after: grant)
        #expect(grant.granted == ["send"] && grant.refused == ["state"] && grant.level == nil, "an answer right by right replaces a level")
        #expect(grant.at == "2026-10-17T10:00:00Z" && grant.folder == nil)
    }

    @Test func aLevelAllowsItsWordsAndRefusesTheOthers() {
        #expect(Grant.Level.allCases.map(\.words) == [[], ["state"], ["state", "send"], ["state", "send", "launch"]])
        #expect(Grant.Level.allCases == Grant.Level.allCases.sorted() && Grant.Level.none < .run)
        #expect([["store"], ["state", "store"], ["send:claude"], ["state", "launch:codex"], []].map(Grant.Level.needed) == [.none, .watch, .talk, .run, .none])
        var reading = DeclarationReading()
        reading.declaration = declaration(["state", "send:claude", "launch", "store"], agents: .folders(["~/code/shop"]), folder: "~/code/blog")
        let talk = Rights.leveled(.talk, folder: "/Users/example/code/shop", declaration: reading.declaration!, at: "2026-10-17T09:00:00Z", after: nil)
        #expect(talk.level == .talk && talk.granted == ["state", "send"] && talk.refused == ["launch"] && talk.folder == nil, "a folder only for Run")
        let granted = Rights.granted(reading, talk, limits: [:], home: home)
        #expect(granted.rights == ["state", "send:claude", "store"] && granted.refused == ["launch"])
        #expect(granted.agents == .folders(["/Users/example/code/shop"]), "the scope stays the page's")
        let run = Rights.leveled(.run, folder: "/Users/example/code/shop", declaration: reading.declaration!, at: "2026-10-17T10:00:00Z", after: talk)
        #expect(run.refused.isEmpty && run.folder == "/Users/example/code/shop" && run.at == "2026-10-17T10:00:00Z")
        #expect(Rights.leveled(.run, folder: nil, declaration: reading.declaration!, at: "2026-10-17T11:00:00Z", after: run).folder == run.folder,
                "Run again keeps its folder")
        let none = Rights.leveled(.none, folder: nil, declaration: reading.declaration!, at: "2026-10-17T12:00:00Z", after: run)
        #expect(Rights.granted(reading, none, limits: [:], home: home).rights == ["store"] && none.folder == nil)
    }

    /// "May start pi" is what the bridge enforces: Run keeps the agent and grants only its kind, under a wider
    /// declaration too; a later change of level keeps it while Run lasts, and a grants file without these keys still reads.
    @Test func theSentenceNarrowsWhatIsGranted() throws {
        var reading = DeclarationReading()
        reading.declaration = declaration(["state", "launch"], agents: .folders(["~/code/shop"]))
        let declared = try #require(reading.declaration), at = "2026-11-01T09:00:00Z", pi = Grant.Start(kind: "pi", model: "invented")
        let run = Rights.leveled(.run, folder: "/Users/example/code/shop", declaration: declared, at: at, after: nil, start: pi)
        #expect(run.granted == ["state", "send", "launch:pi"] && run.start == pi)
        let given = Rights.granted(reading, run, limits: [:], home: home)
        #expect(given.rights == ["state", "launch:pi"], "\(given.rights)")
        #expect(Rights.covers(given.rights, "launch:pi") && !Rights.covers(given.rights, "launch:claude"))
        #expect(Rights.leveled(.run, folder: nil, declaration: declared, at: at, after: run).granted == run.granted, "kept like its folder")
        #expect(Rights.leveled(.talk, folder: nil, declaration: declared, at: at, after: run).start == nil)
        #expect(Rights.leveled(.run, folder: "/Users/example/a", declaration: declared, at: at, after: nil).granted == ["state", "send", "launch"], "no agent named: as before")

        #expect(Rights.granted(reading, nil, limits: [:], home: home).agents == .folders(["/Users/example/code/shop"]), "nil follows the declaration")
        let all = Rights.leveled(.watch, folder: nil, declaration: declared, at: at, after: nil, scope: .all)
        #expect(Rights.granted(reading, all, limits: [:], home: home).agents == .all, "the person's scope wins, wider")
        let narrow = Rights.leveled(.talk, folder: nil, declaration: declared, at: at, after: all, scope: .folders(["/Users/example/b"]))
        #expect(Rights.granted(reading, narrow, limits: [:], home: home).agents == .folders(["/Users/example/b"]), "or narrower")
        #expect(Rights.leveled(.none, folder: nil, declaration: declared, at: at, after: narrow).scope == narrow.scope, "it survives a change of level")

        // A page that declares all, at Run in a folder: an agent elsewhere stays hidden, what it launched stays seen.
        var page = DeclarationReading()
        page.declaration = declaration(["state", "launch"])
        let room = Rights.granted(page, Rights.leveled(.run, folder: "/Users/example/code/shop", declaration: declared, at: at, after: nil, start: pi, scope: .folders(["/Users/example/code/shop"])), limits: [:], home: home)
        var (inside, outside, mine) = (Agent(id: "in", kind: "pi", origin: "elsewhere"), Agent(id: "out", kind: "pi", origin: "elsewhere"), Agent(id: "mine", kind: "pi", origin: "launched"))
        (inside.folder, outside.folder, mine.folder) = ("/Users/example/code/shop", "/Users/example/notes", "/Users/example/notes")
        let world = State(at: at, kinds: [:], agents: [inside, outside, mine])
        #expect(Rights.visible(world, room, launched: ["mine"]).agents.map(\.id) == ["in", "mine"])

        var file = AppFile()
        file.spaces["a"] = run
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rights-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try file.write(url)
        #expect(try AppFile.read(url) == file)
        try Data(#"{"app": 1, "spaces": {"a": {"declared": {"rights": [], "agents": {"see": "all"}}, "granted": [], "refused": [], "remap": {}, "at": ""}}}"#.utf8).write(to: url)
        let older = try #require(try AppFile.read(url).spaces["a"])
        #expect(older.start == nil && older.scope == nil, "older files still read")
    }

    /// The level is the consent: nothing is asked again, whatever the page declares later, except a folder Run lacks.
    @Test func aLevelAsksNothingAgain() {
        let first = declaration(["state"], agents: .folders(["~/code"]))
        let watch = Rights.leveled(.watch, folder: nil, declaration: first, at: "2026-10-17T09:00:00Z", after: nil)
        #expect(Rights.toAsk(first, since: watch).isEmpty)
        for later in [declaration(["state", "send", "launch:codex", "store"], agents: .all, folder: "~/code/blog"), declaration([])] {
            #expect(Rights.toAsk(later, since: watch).isEmpty, "a right above the level stays refused, silently")
        }
        var reading = DeclarationReading()
        reading.declaration = declaration(["state", "send"], agents: .all)
        #expect(Rights.granted(reading, watch, limits: [:], home: home).refused == ["send"])
        let run = Rights.leveled(.run, folder: nil, declaration: first, at: "2026-10-17T09:00:00Z", after: nil)
        #expect(Rights.toAsk(declaration(["launch"]), since: run) == ToAsk(rights: [], scope: false, folder: true), "Run without a folder asks one")
        #expect(Rights.toAsk(first, since: run).isEmpty, "a page that starts nothing needs none")
        let chosen = Rights.leveled(.run, folder: "/Users/example/code/shop", declaration: first, at: "2026-10-17T09:00:00Z", after: nil)
        #expect(Rights.toAsk(declaration(["launch"], folder: "~/code/blog"), since: chosen).isEmpty, "the folder chosen wins over the one declared")
    }

    /// A grant answered right by right, before levels, reads as the highest level all of whose declared rights were
    /// allowed, never above what the page declared; nothing in it changes.
    @Test func anOlderGrantReadsAsALevel() throws {
        func level(_ declared: [String], allowed: [String], refused: [String] = []) -> Grant.Level {
            Rights.level(of: Rights.answered(declaration(declared), allowed: allowed, refused: refused, folder: nil, at: "2026-10-17T09:00:00Z", after: nil))
        }
        #expect(level(["state", "store"], allowed: ["state", "store"]) == .watch)
        #expect(level(["state", "send:claude", "store"], allowed: ["state", "send:claude"]) == .talk)
        #expect(level(["state", "launch"], allowed: ["state", "launch"]) == .run, "a word not declared neither raises nor stops it")
        #expect(level(["state", "send", "launch"], allowed: ["state", "launch"], refused: ["send"]) == .watch)
        #expect(level(["send"], allowed: ["send"]) == .talk && level(["state"], allowed: [], refused: ["state"]) == .none)
        #expect(level(["store"], allowed: ["store"]) == .none)
        // An older file, without the key, still reads; a level is written only once chosen.
        let old = #"{"app": 1, "spaces": {"agents": {"declared": {"rights": ["state"], "agents": {"see": "all"}}, "granted": ["state"], "refused": [], "remap": {}, "at": "2026-10-17T09:00:00Z"}}}"#
        let file = try JSONDecoder().decode(AppFile.self, from: Data(old.utf8))
        #expect(file.spaces["agents"]?.level == nil && file.spaces["agents"].map(Rights.level) == .watch)
        #expect(!String(decoding: try JSONEncoder().encode(file), as: UTF8.self).contains("level"))
    }

    /// A lasting rule keeps one plain command, exactly, for one kind in one folder; a chain, a pipe, a redirection, a
    /// substitution, a variable or a second line is never kept, and an older grants file reads without rules.
    @Test func aLastingRuleCoversOneExactCommand() throws {
        for plain in ["npm test", "git log --oneline -20", "swift test --filter Rights"] { #expect(Rights.single(plain), "\(plain)") }
        for chained in ["", "  ", "npm test && rm -rf .", "ls | wc -l", "a; b", "echo x > f", "cat < f", "echo $(id)", "echo `id`",
                        "echo $HOME", "npm test\nrm -rf .", "npm test &", "a \\\n b"] {
            #expect(!Rights.single(chained), "\(chained)")
        }
        var grant = Grant(declared: Asked(declaration(["launch"])), at: "2026-10-21T09:00:00Z")
        let kept = Rule(kind: "claude", command: "git log --oneline -20", folder: "/Users/example/code/atelier", at: "2026-10-21T09:00:00Z")
        #expect(Rights.rule(in: grant, kind: "claude", command: kept.command, folder: kept.folder) == nil, "no rule yet")
        grant.rules = [kept]
        #expect(Rights.rule(in: grant, kind: "claude", command: kept.command, folder: kept.folder) == kept)
        for (kind, command, folder) in [("codex", kept.command, kept.folder), ("claude", "git log --oneline -21", kept.folder),
                                        ("claude", kept.command + " ", kept.folder), ("claude", kept.command, "/Users/example/code"),
                                        ("claude", kept.command, nil as String?)] {
            #expect(Rights.rule(in: grant, kind: kind, command: command, folder: folder) == nil, "\(kind) \(command) \(folder ?? "nil")")
        }
        let leveled = Rights.leveled(.talk, folder: nil, declaration: declaration(["send"]), at: "2026-10-22T09:00:00Z", after: grant)
        #expect(leveled.rules == [kept], "a new level keeps the rules")
        let old = #"{"declared": {"rights": ["launch"], "agents": {"see": "all"}}, "granted": [], "refused": [], "remap": {}, "at": "2026-10-17T09:00:00Z"}"#
        #expect(try JSONDecoder().decode(Grant.self, from: Data(old.utf8)).rules == nil)
    }

    @Test func theGrantsFileRoundTripsAndAnUnreadableOneIsNotErased() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("grants-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("something/app.json")
        #expect(try AppFile.read(url) == AppFile())
        var file = AppFile()
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

    /// Two writers at once, as the app and `something new` in a terminal: 200 updates from two threads, each update on
    /// a file descriptor of its own (a lock belongs to an open file, so this is what two processes do), and no change
    /// is lost. An update that changes nothing writes nothing.
    @Test func concurrentUpdatesOfTheGrantsLoseNothing() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("grants-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let grants = Grants(folder.appendingPathComponent("something/app.json"))
        let asked = Asked(declaration([])), failures = NSLock()
        var failed: [String] = []
        DispatchQueue.concurrentPerform(iterations: 2) { thread in
            for index in 0..<100 {
                do {
                    try grants.update { file in
                        file.spaces["space-\(thread)-\(index)"] = Grant(declared: asked, at: "2026-10-17T09:00:00Z")
                    }
                } catch { failures.withLock { failed.append("\(error)") } }
            }
        }
        #expect(failed.isEmpty, "\(failed)")
        #expect(try grants.read().spaces.count == 200)
        let written = try FileManager.default.attributesOfItem(atPath: grants.url.path)[.modificationDate] as? Date
        try grants.update { _ in }
        #expect(try FileManager.default.attributesOfItem(atPath: grants.url.path)[.modificationDate] as? Date == written)
        // A file that does not read is never replaced by an update.
        try Data("{".utf8).write(to: grants.url)
        #expect(throws: SpaceError.self) { try grants.update { $0.spaces = [:] } }
        #expect(try Data(contentsOf: grants.url) == Data("{".utf8))
    }

    @Test func aScopeFolderNotOnThisMacIsReplacedByTheOneThePersonChose() {
        var reading = DeclarationReading()
        reading.declaration = declaration(["state"], agents: .folders(["~/code/shop", "~/code/blog"]))
        var grant = Grant(declared: Asked(reading.declaration!), at: "2026-10-17T09:00:00Z")
        grant.remap = ["~/code/shop": "/Users/example/work/shop"]
        #expect(Rights.granted(reading, grant, limits: [:], home: home).agents == .folders(["/Users/example/work/shop", "/Users/example/code/blog"]))
    }

    /// An agent's key lasts across its launches: program and conversation; without a conversation, its id.
    @Test func anAgentsKeyIsItsProgramAndItsConversation() {
        var agent = Agent(id: "claude-3", kind: "claude", origin: "launched")
        #expect(Rights.key(agent) == "claude-3")
        agent.thread = "t1"
        #expect(Rights.key(agent) == "claude:t1")
        agent = Agent(id: "claude-t1", kind: "claude", origin: "elsewhere")
        agent.thread = "t1"
        #expect(Rights.key(agent) == "claude:t1")
    }

    /// The person's list: by key, so it outlives an id; it wins over any scope; hides what the space launched only once
    /// that left `launched`; and at None nothing shows, not even what the space launched.
    @Test func theListWinsAndNoneShowsNothing() throws {
        func agent(_ id: String, thread: String?, folder: String) -> Agent {
            var agent = Agent(id: id, kind: "claude", origin: "elsewhere")
            (agent.thread, agent.folder) = (thread, folder)
            return agent
        }
        var world = State(at: "2026-10-22T18:00:00Z", kinds: [:], agents: [agent("a", thread: "one", folder: "/shop"), agent("b", thread: "two", folder: "/shop"), agent("c", thread: nil, folder: "/blog")])
        world.threads = [AgentThread(id: "one", agent: "a", title: nil, started: nil, turns: []), AgentThread(id: "two", agent: "b", title: nil, started: nil, turns: [])]
        var room = Granted()
        (room.rights, room.agents) = (["state"], .all)
        let list = ["claude:one", "c"]
        #expect(Rights.visible(world, room, launched: [], listed: list).agents.map(\.id) == ["a", "c"], "the scope says all, the list wins")
        #expect(Rights.visible(world, room, launched: [], listed: list).threads.map(\.id) == ["one"], "threads follow")
        #expect(Rights.visible(world, room, launched: ["b"], listed: list).agents.map(\.id) == ["a", "b", "c"], "a launch not yet in the list shows")
        world.agents[0].id = "a2"
        #expect(Rights.visible(world, room, launched: [], listed: list).agents.map(\.id) == ["a2", "c"], "the key outlives the id")
        var bare = room
        bare.rights = ["store"]
        #expect(Rights.visible(world, bare, launched: ["b"], listed: list).agents.isEmpty, "at None, none")
        bare.rights = ["send"]
        #expect(Rights.visible(world, bare, launched: ["b"], listed: list).agents.map(\.id) == ["b"], "without state, only what it launched")
    }

    /// A key with no conversation is an id, which the next run gives to another agent: none crosses a run.
    @Test func anIdDoesNotOutliveItsRun() throws {
        var file = AppFile()
        var grant = Rights.leveled(.talk, folder: nil, declaration: declaration(["state", "send"]), at: "t", after: nil)
        grant.listed = ["amp-1", "claude:t", "antigravity-pid-55000"]
        file.spaces["a"] = grant
        Rights.endRun(&file)
        #expect(file.spaces["a"]?.listed == ["claude:t"])
        var world = State(at: "t", kinds: [:], agents: [Agent(id: "amp-1", kind: "amp", origin: "launched")])
        world.agents[0].folder = "/shop"
        var room = Granted()
        (room.rights, room.agents) = (["state", "send"], .folders(["/blog"]))
        let kept = file.spaces["a"]?.listed
        let seen = Rights.visible(world, room, launched: [], listed: kept)
        #expect(seen.agents.isEmpty)
    }

    /// A list survives a level, a scope chosen ends it, and it is kept with the level.
    @Test func aScopeEndsTheListAndALevelKeepsIt() throws {
        let declared = declaration(["state", "send"])
        var grant = Rights.leveled(.watch, folder: nil, declaration: declared, at: "t", after: nil)
        grant.listed = ["claude:one"]
        #expect(Rights.leveled(.none, folder: nil, declaration: declared, at: "t", after: grant).listed == ["claude:one"])
        #expect(Rights.leveled(.talk, folder: nil, declaration: declared, at: "t", after: grant, scope: .all).listed == nil)
        // The raised grant and its list are one value: one write, nothing between them.
        var raised = Rights.leveled(.watch, folder: nil, declaration: declared, at: "t", after: nil)
        raised.listed = ["claude:one"]
        var file = AppFile()
        file.spaces["a"] = raised
        let read = try JSONDecoder().decode(AppFile.self, from: JSONEncoder().encode(file))
        #expect(read.spaces["a"]?.listed == ["claude:one"] && read.spaces["a"]?.level == .watch)
    }
}
