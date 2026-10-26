// The person's assistant as the window shows it: the coding agent that builds spaces with them in ~/something/spaces.
// The builder chosen among the installed ones, kept in the preferences with Ask Before Every Change; the knowledge
// files written into the spaces folder; one conversation per place, each space's own and New Space's, the card showing
// the open place's and a build from New Space going on as the new space's own; each agent launched at its first
// message, never before, and told at each message which space is open; a message written while a turn runs held until
// it ends, and Take Back; Stop, New Conversation, the switch to another builder, and what went wrong; sleep (after the
// Preferences' delay, past the cap of awake assistants, or when the person asks), and the wake on the next message,
// which resumes the conversation a space keeps when its kind can. Each turn of a space's conversation is said when it
// begins and when it ends, so that the window keeps the space as each turn found and left it. A Quick Change is a
// temporary session of a space's assistant, the same kind with the same model and effort, told the parts pointed at; it
// is stopped once its turn ends (never while one of its requests waits), its change kept as a quick version (its
// answer a margin note when it changed nothing), and the space's own conversation, untouched, holds what the person
// writes to it meanwhile. The engine keeps every space away from this agent (Bridge.visible); something writes to it
// on its own only its context line, its pointing lines and Ask to Fix, never a page's text.
import AppKit
import Observation
import SomethingAgents
import SomethingCore

@Observable final class AssistantModel {
    /// Where the person is when they write: what each message's context line says.
    enum Place: Equatable {
        case space(title: String, name: String, page: String), blank, templates
        /// Which conversation a place has: a space's own, or New Space's, which the blank page and the templates share.
        enum Key: Hashable { case space(String), new }
        /// The open space's name; nil off a space.
        var space: String? { if case .space(_, let name, _) = self { name } else { nil } }
        var key: Key { space.map(Key.space) ?? .new }
    }
    /// Where the conversation's agent is.
    enum Light { case off, ready, working, waiting, error }
    /// One line of the conversation: the day its turns start, the person's message with what it was about, the
    /// agent's text, or one tool it ran and whether it failed or was refused.
    enum Row: Equatable {
        case day(Date), mine(caption: String?, text: String), reply(String), tool(failed: Bool, words: String, command: String?)
        /// The person's words, or the agent's, when the row holds them.
        var mine: String? { if case .mine(_, let text) = self { text } else { nil } }
        var reply: String? { if case .reply(let text) = self { text } else { nil } }
    }
    /// What the open space reported while it ran: its title, its name and the codes, never its text. A page that
    /// stopped is named by its file, with the app's own reason `stopped`, which is no code of the contract.
    struct Fault: Equatable {
        static let stopped = "STOPPED"
        var title: String, name: String, codes: [String]
    }
    /// One builder in the agent menu.
    struct Entry: Identifiable { let id: String, title: String, checked: Bool, enabled: Bool, note: String? }

    @ObservationIgnored let engine: Engine
    @ObservationIgnored let places: Places
    /// The clock of sleep and of the presence; a test moves it.
    @ObservationIgnored var clock: () -> Date = Date.init
    /// Whether a builder of `kind` picks its conversation up when it wakes (Registry.resumesAsBuilt); a test fakes one.
    @ObservationIgnored var resumable: (String) -> Bool = { Registry.resumesAsBuilt.contains($0) }
    /// Puts a word on the pasteboard; a test keeps it.
    @ObservationIgnored var copy: (String) -> Void = {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString($0, forType: .string)
    }
    /// Asks before a switch that ends the conversation (a sheet on the window), then calls `switched`.
    @ObservationIgnored var confirmSwitch: (_ from: String, _ to: String, _ switched: @escaping () -> Void) -> Void = { _, _, go in go() }
    /// How to Get One, and bringing the permission panel forward: the window's.
    @ObservationIgnored var howTo: () -> Void = {}
    @ObservationIgnored var showRequest: () -> Void = {}
    /// The window's: opening a space said ready, and, when a build from the blank page ended, its space.
    @ObservationIgnored var openReady: (String) -> Void = { _ in }
    @ObservationIgnored var ended: () -> Void = {}
    /// A turn of a space's conversation begins, and ends with the person's sentence and the agent's name: the window
    /// keeps that space as it was before, then what the turn made of it (Changes). The session's space, wherever the
    /// person went meanwhile.
    @ObservationIgnored var turnStarts: (_ space: String) -> Void = { _ in }
    @ObservationIgnored var turnEnded: (_ space: String, _ sentence: String, _ who: String) -> Void = { _, _, _ in }
    /// A Quick Change on a space ended, with what went wrong if anything did: the window keeps what it made (Changes).
    /// Returns whether it changed the space.
    @ObservationIgnored var quickEnded: (_ space: String, _ sentence: String, _ who: String, _ problem: String?) -> Bool = { _, _, _, _ in false }
    /// A Quick Change ended having changed nothing, its agent's last words an answer: the window shows them as a note.
    @ObservationIgnored var answered: (_ quick: Quick, _ words: String) -> Void = { _, _ in }

    /// Arriving at the spaces shows the assistant as Settings' "When a space opens, its assistant is" says: the sticker
    /// (Reduced, the mockup's default) or the open card; from one space to another the card stays as it was, only its
    /// content changing: each place shows its own conversation.
    var place = Place.blank {
        didSet {
            if place.space != nil, oldValue.space == nil { open = Preferences.at(places).assistantAtOpening == .open }
            // Leaving New Space stops its build, the words kept in its field, and says so.
            if oldValue == .blank, place != .blank {
                if before?.session === session, let left = ladder { stop(before); told(left.left) }
                (halted, nudged) = (nil, false)
            }
            if place.key != oldValue.key {
                // The assistant left stays awake for the whole delay from now: it was the open one until now.
                session.active = clock()
                session = session(for: place)
                // The left one is restful only now: nothing else may set the timer before its delay ends.
                rest()
                keepTime()
            }
        }
    }
    /// What the field holds: the open place's own, so a message half written goes to the agent it was written for.
    var draft: String {
        get { session.draft }
        set { session.draft = newValue }
    }
    /// Whether the card is open (Reduce and ⌘\ close it), and whether it shows the conversation (⌘J).
    var open = true
    var threadShown = false
    /// Whether the open space has a page to point at, and whether the person points at it now: the card's Point.
    var pointable = false
    var pointing = false
    /// The height the card takes at the bottom of the center, set by the glass: the blank page keeps clear of it.
    var floating: CGFloat = 0
    /// Whether the card, closed, is still shrinking into the sticker: it is drawn until it is there.
    var folding = false
    /// Whether the open space's journal could not be written.
    var unkept = false
    /// Set by ⌘K until the field takes the focus, which it may do only once it is drawn.
    var wantsFocus = false
    /// Each place's conversation, made at its first use; and the one the card shows and the messages go to, the open
    /// place's, with what the window reads of it.
    private(set) var sessions: [Place.Key: Session] = [:]
    private(set) var session = Session(kind: nil)
    /// The Quick Change of each space, by its name: at work, or just ended while its frame and chip still show.
    private(set) var quicks: [String: Quick] = [:]
    var kind: String? { session.kind }
    var id: String? { session.id }
    var agent: Agent? { session.agent }
    var rows: [Row] { session.rows }
    var asking: Bool { session.asking }
    var launching: Bool { session.launching }
    var failure: String? { session.failure }
    var asleep: Bool { session.asleep }
    private(set) var askEverything: Bool
    /// What the state says of each builder: installed or not; absent while not known.
    private(set) var installed: [String: Bool] = [:]
    private(set) var notes: [String: String] = [:]
    /// Why a builder that refused what something lends it is not offered, until the agents are looked for again.
    private(set) var refused: [String: String] = [:]
    /// A build asked from the blank page: the spaces there were, the conversation building and its last turn then,
    /// when it was asked and in which words, and when something first saw each of its items and their ends (the
    /// agents stamp theirs to the second): the ladder's times.
    struct Build {
        let spaces: Set<String>, session: Session, turn: String?, at: Date, sentence: String
        var seen: [String: Date] = [:]
    }
    /// The build watched until the turn that followed ends (answered, stopped, failed, or never started).
    private(set) var before: Build?
    /// The ladder of the build the person stopped on the blank page, kept until they build again or leave.
    private(set) var halted: Ladder?
    /// Whether Esc was just pressed while the blank page builds: its ladder says how to stop, for a moment.
    private(set) var nudged = false
    @ObservationIgnored private var nudges = 0
    /// The question the build asks, by its request, answered on the blank page (Panels leaves it there).
    struct Asked: Equatable { let request: String, question: Question }
    private(set) var asked: Asked?
    /// The question of a build the person stopped or left, until its agent withdraws it, which comes later: kept out of
    /// the panel meanwhile, as nobody should be asked what they just stopped.
    @ObservationIgnored private var dropped: String?
    /// Says a sentence in a toast: the window's.
    @ObservationIgnored var told: (String) -> Void = { _ in }
    var ready: Library.Entry?
    /// The space just made from a template, until the person writes: the input offers to make it theirs.
    var fromTemplate: String?
    /// The spaces made while the person waited for one: their rights sheet says the agent made them.
    private(set) var made: Set<String> = []
    @ObservationIgnored private var preferred: String?
    /// something's own program, which runs and serves the tools a builder is lent; a trial gives another.
    @ObservationIgnored var program = Bundle.main.executableURL
    /// Moved by a one-shot timer when time alone changes the presence (Stop offered 10 s into a turn, "Changed …" gone
    /// 3.6 s after it, sleep after the delay): the presence reads it, so the card and the sticker ask again.
    private(set) var beat = 0
    @ObservationIgnored private var beatTimer: Timer?
    @ObservationIgnored private(set) var beatAt: Date?

    init(engine: Engine, places: Places) {
        self.engine = engine
        self.places = places
        let kept = Preferences.at(places)
        preferred = kept.assistant
        askEverything = kept.askEverything
        sessions[.new] = session
        refresh()
    }

    // MARK: Knowledge files

    /// Writes AGENTS.md (share/assistant/AGENTS.md) and CLAUDE.md (`@AGENTS.md`, which Claude Code follows) into the
    /// spaces folder, each when it is missing or still starts with something's marker: a file whose first line the
    /// person removed is theirs and left alone. Throws a `SpaceError` when the source cannot be read or a file written.
    static func writeKnowledge(_ places: Places, share: URL) throws {
        let source = share.appendingPathComponent("assistant/AGENTS.md")
        guard let text = try? String(contentsOf: source, encoding: .utf8), let marker = text.split(separator: "\n").first else {
            throw SpaceError("something cannot read \(source.path); reinstall something, or restore share/ in its clone.")
        }
        for (name, content) in [("AGENTS.md", text), ("CLAUDE.md", [String(marker), "@AGENTS.md", ""].joined(separator: "\n"))] {
            let file = places.spaces.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path),
               (try? String(contentsOf: file, encoding: .utf8))?.split(separator: "\n").first != marker { continue }
            do { try content.write(to: file, atomically: true, encoding: .utf8) } catch {
                throw SpaceError("something cannot write \(file.path): \(error.localizedDescription) Check that the folder can be written.")
            }
        }
    }

    // MARK: What the window shows

    /// Takes what the engine's state says now: the builders found, this conversation's agent and its thread. Called
    /// at each change of the state, up to four times a second: only what changed is written, so the window draws the
    /// assistant again only then.
    func refresh() {
        let state = engine.state
        keep(\.installed, state.kinds.filter { builders.contains($0.key) }.compactMapValues(\.installed))
        keep(\.notes, state.kinds.compactMapValues(\.note))
        let offered = builders.filter { installed[$0] == true && refused[$0] == nil }
        for each in sessions.values {
            // A conversation with a past keeps its builder while that builder is not known to be installed, whether its
            // program left the Mac or the agents are not looked for yet (a space reopened at start): the card says it is
            // missing rather than another agent taking the conversation over unasked. Only one refused passes on.
            let kind = each.kind ?? ""
            if !offered.contains(kind), !each.hasHistory || each.kind == nil || installed[kind] == true {
                let chosen = offered.first { $0 == preferred } ?? offered.first
                // Another builder's model means nothing to this one; a conversation kept before the agents were looked
                // for keeps what it chose.
                if chosen != nil, each.kind != nil || (each.model, each.effort) == (nil, nil) { (each.model, each.effort) = defaults(chosen) }
                each.kind = chosen
            }
            if each.read(state) { save(each) }
            // What its agent lists is what the chip offers for its kind, the next time too.
            if let kind = each.kind, let options = each.agent?.options, options.model?.isEmpty == false, Preferences.at(places).listed[kind] != options {
                Preferences.at(places).listed[kind] = options
            }
            if ["working", "waiting"].contains(each.agent?.state) { each.active = clock() }
        }
        rest()
        keepTime()
        // No turn will end to release them: the held messages go back into the field rather than wait for ever.
        if !session.held.isEmpty, !quickWorks(on: place.space), light == .error || (light == .off && id != nil) { takeBack() }
        follow()
        followQuicks()
        // A build watched is concluded on the refresh where its turn ends, before a held message starts the next, wherever
        // the person went meanwhile.
        if let before, !before.session.launching {
            let built = before.session
            if over(built, after: before.turn) {
                ended()
                if self.before?.session === built { self.before = nil }
            }
        }
        // A turn that may have changed its space ended, however it ended: before the next starts, it is kept.
        for each in sessions.values {
            guard let changing = each.changing, let space = each.space, !each.launching, over(each, after: changing.after) else { continue }
            each.changing = nil
            turnEnded(space, changing.sentence, name(of: each))
        }
        // A turn ended: the oldest held message of its conversation leaves, one per turn, as the mockup sends them.
        for each in sessions.values {
            guard !each.held.isEmpty, light(each) == .ready, !each.launching, !quickWorks(on: each.space),
                  each.releasedAfter != .some(each.turn?.id) else { continue }
            release(each)
        }
    }

    /// Whether the turn of `session` that followed the turn `after` (any turn for nil) is over: answered, stopped,
    /// failed, or never started.
    private func over(_ session: Session, after: String?) -> Bool {
        let light = light(session)
        let answered = session.turn.map { $0.id != after && $0.state != "working" } == true && ![.working, .waiting].contains(light)
        return answered || session.id == nil || session.stopped || light == .error || session.agent?.alive == false
    }

    /// Sends the oldest message held for `session`, noting the turn it leaves after.
    private func release(_ session: Session) {
        let next = session.held.removeFirst()
        session.releasedAfter = .some(session.turn?.id)
        deliver(next, to: session)
    }

    /// Notes when something first saw each item of the build's turn and each end of its tools, and the question the
    /// blank page answers.
    private func follow() {
        keep(\.asked, inlineQuestion())
        if let dropped, !engine.state.requests.contains(where: { $0.id == dropped }) { self.dropped = nil }
        guard var build = before, let turn = build.session.turn, turn.id != build.turn else { return }
        let now = clock(), was = build.seen.count
        for item in turn.items {
            for key in [item.id] + ((item.tool?.status).map { ["\(item.id)/\($0)"] } ?? []) where build.seen[key] == nil { build.seen[key] = now }
        }
        if let asked, build.seen[asked.request] == nil { build.seen[asked.request] = now }
        if build.seen.count != was { before = build }
    }

    /// The build's question while the blank page shows, when keys 1 to 9 can answer it (`question(of:)`); any other
    /// request goes to the panel.
    private func inlineQuestion() -> Asked? {
        guard place == .blank, let build = before else { return nil }
        return question(of: build)
    }

    /// The question `build` asks that the blank page can answer, wherever the person is: one question with one choice
    /// among at most nine labels.
    private func question(of build: Build) -> Asked? {
        guard build.session === sessions[.new], let id = build.session.id else { return nil }
        for request in engine.state.requests where request.kind == "question" && request.agent == id {
            if let questions = engine.prompt(request.id)?.questions, questions.count == 1, let one = questions.first, !one.multiple,
               (1...9).contains(one.options.count) { return Asked(request: request.id, question: one) }
        }
        return nil
    }

    /// Whether `request` is answered on the blank page rather than in the panel: Panels' filter.
    func answersInline(_ request: Request) -> Bool { request.id == dropped || inlineQuestion()?.request == request.id }

    /// The ladder New Space shows: the build's as it goes, or the one stopped there; nil when there is neither.
    var ladder: Ladder? {
        if let halted { return halted }
        guard let build = before else { return nil }
        let turn = build.session.turn.flatMap { $0.id == build.turn ? nil : $0 }
        return Ladder.read(turn?.items ?? [], seen: build.seen, from: build.at, asked: asked?.question, askedAt: asked.flatMap { build.seen[$0.request] })
    }

    /// Answers the build's question with its choice `index`. An answer that did not reach the agent is its failure.
    func answer(_ index: Int) {
        guard let asked, asked.question.options.indices.contains(index) else { return }
        self.asked = nil
        do { try engine.answer(asked.request, .choice([[asked.question.options[index]]])) } catch { before?.session.failure = error.sentence }
    }

    /// Sets the one-shot timer for the next moment a presence changes by itself, the card's or a space's in the
    /// sidebar, or an assistant falls asleep, if there is one.
    private func keepTime() {
        let now = clock(), delay = sleepDelay
        let at = sessions.values.flatMap { each -> [Date?] in
            [[.working, .waiting].contains(light(each)) ? each.turn?.started.flatMap(iso8601.date).map { $0 + Presence.late }
                : each.turn?.ended.flatMap(iso8601.date).map { $0 + Presence.changedFor },
             delay.flatMap { restful(each) ? each.active + $0 : nil }]
        }.compactMap { $0 }.filter { $0 > now }.min()
        guard at != beatAt else { return }
        beatTimer?.invalidate()
        (beatTimer, beatAt) = (nil, at)
        guard let wait = at?.timeIntervalSince(clock()), wait > 0 else { return }
        beatTimer = Timer.scheduledTimer(withTimeInterval: wait + 0.05, repeats: false) { [weak self] _ in self?.tick() }
    }

    func tick() {
        rest()
        keepTime()
        beat += 1
    }

    private func keep<Value: Equatable>(_ property: ReferenceWritableKeyPath<AssistantModel, Value>, _ value: Value) {
        if self[keyPath: property] != value { self[keyPath: property] = value }
    }

    /// The kinds that can build, in their order (Extensions.swift).
    var builders: [String] { Registry.app.builders.map(\.kind) }

    var name: String { name(of: session) }

    func name(of session: Session) -> String { Registry.app.name(of: session.kind ?? preferred ?? builders.first ?? "") }

    /// What to type in Terminal to sign the builder in: its program, whose name is its kind.
    var command: String { kind ?? builders.first ?? "" }

    /// What the builder `kind` is lent: something's own commands its descriptor takes, run by this program outside
    /// the agent's sandbox; nil when it takes none.
    func lent(for kind: String) -> Lent? {
        guard let tools = Registry.app.agent(kind)?.builder?.lent, !tools.isEmpty, let program else { return nil }
        return Lent.own(program.resolvingSymlinksInPath().path, tools: tools, environment: ProcessInfo.processInfo.environment,
                        refused: { [weak self] kind, because in self?.cannotBuild(kind, because) })
    }

    /// Whether every builder was looked for and none can build.
    var noAgent: Bool { kind == nil && !installed.isEmpty }

    /// What the card says when no builder is offered.
    var noBuilder: String {
        let found = builders.filter { installed[$0] == true }
        if found.count == 1, let because = refused[found[0]] { return because }
        return found.isEmpty ? "No coding agent found." : "\(found.map(Registry.app.name).joined(separator: ", ")) can't build spaces."
    }

    /// Whether a space is being made from the blank page: the sidebar shows a "New Space" row meanwhile.
    var building: Bool { before != nil }

    var working: Bool { light == .working || light == .waiting }

    /// Whether Stop has something to stop here: this conversation's turn, or a Quick Change on this space.
    var stoppable: Bool { working || quickWorks(on: place.space) }

    /// Whether nothing can be sent until the person acts on the notice: its program left the Mac, or it quit.
    var blocked: Bool { kind != nil && [.missing, .crashed].contains(presence.stuck) }

    /// Whether Start Again picks this conversation up: its agent reported a thread, its kind resumes as it was launched,
    /// Ask Before Every Change is what it was (a resume keeps how it asked), and the last start did not fail, which a
    /// conversation the program cannot find again does: Start Again then begins a new one rather than fail for ever.
    var resumes: Bool { resumes(session) }

    /// Only a thread an earlier launch of the same kind reported, and only while the person keeps "Resume each space's
    /// conversation" on.
    func resumes(_ session: Session) -> Bool {
        session.thread != nil && session.threadKind == session.kind && resumable(session.kind ?? "") && session.asking == askEverything
            && session.failure == nil && session.agent?.error?.code != "LAUNCH_FAILED" && Preferences.at(places).resume
    }

    /// The other builders the person may choose when this one left the Mac.
    var others: [Entry] { entries.filter { $0.id != kind && $0.enabled } }

    var light: Light { light(session) }

    /// Where the agent of `session` is.
    func light(_ session: Session) -> Light {
        if session.failure != nil { return .error }
        guard let agent = session.agent, !session.stopped else { return session.launching ? .working : .off }
        switch agent.state {
        case "working": return .working
        case "waiting": return .waiting
        case "error": return .error
        default: return agent.alive == false ? (agent.error == nil ? .off : .error) : .ready
        }
    }

    /// What the agent reported while it could not reach its model (Claude Code's `detail.apiRetry`): its last retry,
    /// or, with no attempt, its sign-in refused before any request.
    private var apiRetry: [String: JSONValue] {
        guard case .object(let retry)? = agent?.detail["apiRetry"] else { return [:] }
        return retry
    }

    /// Whether the last message failed because the model's server refused the agent's sign-in: signing in cures it.
    var signedOut: Bool {
        guard failure == nil, light == .error else { return false }
        var (status, error): (Int?, String?) = (nil, nil)
        if case .number(let number)? = apiRetry["errorStatus"] { status = Int(number) }
        if case .string(let kind)? = apiRetry["error"] { error = kind }
        return agent.flatMap { Registry.app.agent($0.kind) }?.refusesSignIn(status: status, error: error) ?? false
    }

    /// What went wrong with the last message, in the agent's or the engine's words; nil when nothing did.
    var problem: String? {
        if let failure { return failure }
        guard light == .error, !session.stopped else { return nil }
        return agent?.error?.message
    }

    var placeholder: String {
        if blocked { return presence.stuck == .missing ? "Choose an agent to continue" : "Start Again to send a message" }
        switch place {
        case .space(_, let space, _) where space == fromTemplate: return "Ask \(name) to make it yours: colors, sections, anything."
        case .space(let title, _, _):
            if !held.isEmpty { return "Write another request…" }
            if presence.stuck == .cannotReachModel { return "Write your next request · it waits until the model answers" }
            // Waiting for an answer, the way on is the request's own window, not this field: it reads as usual.
            if light == .working { return "Write your next request · it waits for this one" }
            return presence.state == .sleep ? "Ask for a change · it wakes up" : "Ask \(AssistantModel.clean(title))'s assistant for a change…"
        case .blank: return "Describe the space you want…"
        case .templates: return "Ask \(name) about templates, or anything about something…"
        }
    }

    /// The spaces folder as the person reads it: "~/something/spaces".
    var folder: String { Words.path(places.spaces.path, home: places.home.path) }

    /// The conversation's first lines: where the agent works and how it asks, whether it can pick a conversation up,
    /// and why a new one began. A conversation picked up after sleep said them when it began: it shows none.
    var firstLines: [String] {
        guard session.kept.isEmpty else { return [] }
        let agent = kind.flatMap(Registry.app.agent)
        let how = if agent?.neverAsks == true { "\(name) works in \(folder). \(name) never asks: it can run any command on your Mac." }
            else if agent?.asksNothingByDefault == true {
                "\(name) works in \(folder). By default \(name) asks nothing: it can run any command on your Mac, unless your own \(name) settings say otherwise."
            }
            else if agent?.builder?.preAllowed == false { "\(name) works in \(folder). It asks as your own \(name) settings say." }
            else if id == nil ? askEverything : asking { "\(name) works in \(folder). It asks you before every change." }
            else { "\(name) works in \(folder). It may change your spaces and run something's own commands there without asking. Anything else asks you." }
        return [how] + (resumable(kind ?? "") ? [] : ["\(name) cannot resume a conversation, so each one starts fresh."])
            + [session.renewed].compactMap { $0 }
    }

    /// The builders found, as the agent menus list them.
    var entries: [Entry] {
        builders.filter { installed[$0] == true }.map { kind in
            let agent = Registry.app.agent(kind)
            let because = refused[kind] != nil ? "can't build spaces" : agent?.neverAsks == true ? "never asks before acting"
                : agent?.asksNothingByDefault == true ? "asks nothing by default" : nil
            let title = [Registry.app.name(of: kind), because].compactMap { $0 }.joined(separator: " · ") + (notes[kind] == nil ? "" : " ⚠")
            return Entry(id: kind, title: title, checked: kind == self.kind, enabled: refused[kind] == nil, note: refused[kind] ?? notes[kind])
        }
    }

    /// Whether Ask Before Every Change means anything for the chosen builder: only one whose building is pre-allowed.
    var canAskEverything: Bool { kind.flatMap(Registry.app.agent)?.builder?.preAllowed == true }

    // MARK: What the person does

    /// Sends `sentence` (a suggestion), or else the draft, with the context line, launching the agent first when this
    /// conversation has none.
    func send(_ sentence: String? = nil) {
        let text = (sentence ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, kind != nil, !blocked else { return }
        if sentence == nil { draft = "" }
        fromTemplate = nil
        halted = nil
        // While its turn runs, the app holds the message rather than the agent: Take Back and Stop can still give it back.
        // Behind messages already held it waits too, so they leave in the order they were written; and while a Quick
        // Change works on this space, until it ends.
        if quickWorks(on: place.space) || (session.id != nil && !launching && (working || !session.held.isEmpty)) {
            return session.held.append(AssistantModel.context(place, home: places.home.path) + "\n" + text)
        }
        if place == .blank, before == nil {
            // The build is watched from its first message: the conversation shows what the agent does.
            let spaces = Set(Spaces(root: places.spaces).list().map(\.name))
            (before, threadShown) = (Build(spaces: spaces, session: session, turn: session.turn?.id, at: clock(), sentence: text), true)
        }
        deliver(AssistantModel.context(place, home: places.home.path) + "\n" + text)
    }

    /// Ask to Fix: only something's own words, the space's validated title and name and the codes.
    func fix(_ fault: Fault) {
        deliver(AssistantModel.context(place, home: places.home.path) + "\n" + AssistantModel.fixing(fault))
    }

    /// ⌘K: opens the card, its field taking the focus.
    func focus() {
        open = true
        wantsFocus = true
    }

    /// Esc in the card: reduces it into the sticker over a space. Elsewhere there is no sticker to bring it back, so
    /// Esc leaves it open.
    func escape() {
        if place.space != nil { open = false }
    }

    /// Esc while the blank page builds: never a stop, the ladder says for 2.6 s how to stop instead.
    func nudge() {
        guard place == .blank, building else { return }
        nudges += 1
        let mine = nudges
        nudged = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            if self?.nudges == mine { self?.nudged = false }
        }
    }

    /// Stops the running turn, the agent staying for the next message; or, while the agent starts, ends its launch. An
    /// agent that cannot pause mid-task is ended: the conversation stays shown, and the next message starts it again.
    /// The held messages go back into the field, except while a Quick Change works on this space: Stop then ends the
    /// Quick Change, keeps what it changed, and the messages held for it leave as they would at its end.
    func stop() {
        if let space = place.space, let quick = quicks[space], quick.phase == .working {
            // An agent stopped while it waits would never hear the answer: it hears a no, never a yes (as at quit).
            if let id = quick.session.id {
                for request in engine.state.requests where request.agent == id { try? engine.answer(request.id, .deny) }
            }
            return end(quick)
        }
        stop(place == .blank && before?.session === session ? before : nil)
    }

    /// Stops the running turn, and `build`, asked from the blank page, with it: its ladder stays as it was, saying what
    /// stays on disk, and the sentence goes back into the field, to change or build again. The watch ends here: a space
    /// it began is not opened by itself.
    private func stop(_ build: Build?) {
        if let build {
            dropped = question(of: build)?.request
            halted = ladder?.halted()
            (before, asked, nudged) = (nil, nil, false)
        }
        takeBack()
        // A message never delivered may be back in the field already.
        if let build, !draft.contains(build.sentence) { draft = [build.sentence, draft].filter { !$0.isEmpty }.joined(separator: "\n") }
        if launching { return endLaunch(session) }
        guard let id, working else { return }
        if agent?.can.interrupt == false { return halt(session) }
        _ = try? engine.interrupt(id)
    }

    /// Ends the conversation: its agent stops, the held messages go back into the field, and the next message starts a
    /// new one.
    func newConversation() {
        takeBack()
        halt(session)
        if before?.session === session { before = nil }
        halted = nil
        session = Session(kind: kind, model: session.model, effort: session.effort, space: session.space)
        sessions[session.space.map(Place.Key.space) ?? .new] = session
        save(session)
        ready = nil
    }

    /// The conversation of `place`, made at its first use, launching nothing: the one its space kept, asleep, else a
    /// new one with the builder chosen now.
    func session(for place: Place) -> Session {
        if let kept = sessions[place.key] { return kept }
        let made = place.space.flatMap { Session.restored($0, in: places.assistants) }
            ?? Session(kind: kind, model: defaults(kind).model, effort: defaults(kind).effort, space: place.space)
        made.active = clock()
        sessions[place.key] = made
        return made
    }

    /// The conversation whose agent is `agent`, of any place or a Quick Change's; nil when none of them launched it.
    func session(of agent: String) -> Session? {
        sessions.values.first { $0.id == agent } ?? quicks.values.first { $0.session.id == agent }?.session
    }

    /// The space the assistant `agent` works on: its conversation's space, or its Quick Change's; nil for New Space's,
    /// which has none until the hand-off, whichever space is open meanwhile, so its requests are never counted as that
    /// space's own.
    func space(of agent: String) -> String? { quicks.values.first { $0.session.id == agent }?.space ?? session(of: agent)?.space }

    /// Whether `agent` is a Quick Change's: the request panel says so.
    func quick(_ agent: String) -> Bool { quicks.values.contains { $0.session.id == agent } }

    /// The messages held for the end of the turn, as the person wrote them.
    var held: [String] { session.held.map { AssistantModel.shown($0).text } }

    /// Take Back: the held messages go back into the field, after what it holds, and are never sent.
    func takeBack() {
        guard !session.held.isEmpty else { return }
        draft = ([draft.trimmingCharacters(in: .whitespacesAndNewlines)] + held).filter { !$0.isEmpty }.joined(separator: "\n")
        session.held = []
        wantsFocus = true
    }

    func tryAgain() {
        guard let last = session.last else { return }
        halt(session)
        session.id = nil
        deliver(last)
    }

    /// Start Again, once the agent quit: launches it again, continuing its conversation when it `resumes`, else in a
    /// new conversation that says so; nothing is sent on its own. A launch that never started its conversation sends its
    /// last message again, as Try Again does, or launches afresh when nothing was sent yet.
    func startAgain() {
        guard session.thread != nil else { return session.last == nil ? start([]) : tryAgain() }
        let thread = resumes ? session.thread : nil
        halt(session)
        if thread != nil {
            session.fold(engine.state)
        } else {
            newConversation()
            session.renewed = "\(name) stopped and could not pick its conversation up. Started a new conversation."
        }
        start([], resume: thread)
    }

    func copyCommand() { copy(command) }

    /// Chooses the builder `kind`; a conversation running with another one ends, after the person said so.
    func choose(_ chosen: String) {
        guard chosen != kind, refused[chosen] == nil else { return }
        let switched = { [self] in
            newConversation()
            keepDefault(chosen)
            (session.kind, session.model, session.effort) = (chosen, defaults(chosen).model, defaults(chosen).effort)
        }
        if id != nil, agent?.alive != false, !session.stopped {
            confirmSwitch(name, Registry.app.name(of: chosen), switched)
        } else {
            switched()
        }
    }

    /// Chooses the model or the effort of this place's conversation alone, nil leaving each as it is: an awake agent
    /// takes them from its next turn (Engine.set), and they are kept for every later launch, the wake's included.
    func choose(model: String? = nil, effort: String? = nil) {
        guard model != nil || effort != nil, model == nil || !ownModel else { return }
        if let model { session.model = model }
        if let effort { session.effort = effort }
        save(session)
        // A launch under way reads them when it starts.
        guard let id, awake(session), !launching else { return }
        do { _ = try engine.set(id, model: model, mode: nil, effort: effort) } catch { session.failure = error.sentence }
    }

    /// Whether the builder chooses its model alone, which something cannot set (its kind's limits).
    var ownModel: Bool { Registry.app.limits[kind ?? ""]?.contains("model") == true }

    /// The model and effort a new conversation of `kind` starts with: the defaults for new spaces when `kind` is their
    /// agent, else the agent's own.
    func defaults(_ kind: String?) -> (model: String?, effort: String?) {
        let kept = Preferences.at(places)
        guard let kind, kind == kept.assistant ?? kind else { return (nil, nil) }
        return (kept.model, kept.effort)
    }

    /// `kind` becomes the default builder; the default model and effort, another builder's, are its own again.
    private func keepDefault(_ kind: String) {
        preferred = kind
        Preferences.at(places).change { if $0.assistant != kind { ($0.assistant, $0.model, $0.effort) = (kind, nil, nil) } }
    }

    /// Build With ▸: the builder of new spaces from now on, kept as the default. New Space's conversation takes it
    /// now when it has not begun, else from its next one. Returns what the toast says; nil for a builder not offered.
    func buildNew(with chosen: String) -> String? {
        guard installed[chosen] == true, refused[chosen] == nil else { return nil }
        keepDefault(chosen)
        let new = session(for: .blank), name = Registry.app.name(of: chosen)
        guard new.kind != chosen else { return "New spaces build with \(name)" }
        if new.id != nil || new.launching || new.hasHistory { return "New spaces build with \(name) from the next conversation" }
        (new.kind, new.model, new.effort) = (chosen, defaults(chosen).model, defaults(chosen).effort)
        return "New spaces build with \(name)"
    }

    /// The builder Build With ▸ checks: the default when it is offered, else New Space's.
    var newKind: String? { entries.contains { $0.id == preferred } ? preferred : sessions[.new]?.kind }

    /// Looks for the builders again; one that refused what something lends it is tried again (it may have been updated).
    func lookAgain() {
        refused = [:]
        refresh()
        engine.lookAgain()
    }

    /// `kind` cannot take what something lends it, as the sentence `because` says: it is no longer offered, another
    /// builder is chosen, and a message that never reached it (no thread was started) is back in the composer,
    /// without the context line, which goes with every message.
    func cannotBuild(_ kind: String, _ because: String) {
        refused[kind] = because
        if draft.isEmpty, agent?.thread == nil, let last = session.last, let line = last.firstIndex(of: "\n") { draft = String(last[last.index(after: line)...]) }
        refresh()
    }

    /// Ask Before Every Change, from the next conversation on.
    func toggleAsking() {
        askEverything.toggle()
        Preferences.at(places).askEverything = askEverything
    }

    // MARK: Sleep

    /// The Preferences' "Put idle assistants to sleep after", in seconds; nil for never.
    var sleepDelay: TimeInterval? {
        let minutes = Preferences.at(places).sleepAfter
        return minutes > 0 ? TimeInterval(minutes * 60) : nil
    }

    /// Whether the agent of `session` runs, or is starting.
    func awake(_ session: Session) -> Bool { session.launching || (session.id != nil && session.agent?.alive != false && !session.stopped) }

    /// Whether `session` can be put to sleep without the person asking: awake and idle, not the open place's, not the
    /// build watched, and of a kind that picks its conversation up when it wakes.
    private func restful(_ session: Session) -> Bool {
        idle(session) && session !== self.session && resumable(session.kind ?? "")
    }

    /// Whether an assistant works on the space `name` now: starting, in a turn, or waiting for the person. Its change
    /// cannot be undone meanwhile: the restore would mix with what it writes.
    func works(on name: String) -> Bool {
        quickWorks(on: name) || sessions.values.contains { $0.space == name && ($0.launching || $0.changing != nil || [.working, .waiting].contains(light($0))) }
    }

    /// Awake with nothing under way: no turn running or waiting, no message held, not starting, not the build watched.
    /// An agent whose state nobody can read is not idle: something never guesses.
    private func idle(_ session: Session) -> Bool {
        awake(session) && !session.launching && session.held.isEmpty && before?.session !== session
            && !["working", "waiting", "unknown"].contains(session.agent?.state)
    }

    /// Puts to sleep each restful assistant idle for the Preferences' delay, then, while more than "awake at most" of
    /// the kinds that resume are awake, the one idle the longest: a Claude Code process holds a few hundred MB.
    func rest() {
        let now = clock()
        if let delay = sleepDelay {
            for each in sessions.values where restful(each) && now.timeIntervalSince(each.active) >= delay { sleep(each) }
        }
        var count = sessions.values.filter { awake($0) && resumable($0.kind ?? "") }.count
        for each in sessions.values.filter(restful).sorted(by: { $0.active < $1.active }) where count > Preferences.at(places).awakeAtMost {
            sleep(each)
            count -= 1
        }
    }

    var canSleep: Bool { idle(session) }

    /// Put to Sleep: the open place's assistant sleeps now, whatever its kind; one that cannot resume begins a new
    /// conversation at its next message, and says so.
    func putToSleep() {
        guard canSleep else { return }
        sleep(session)
    }

    /// Put Idle Assistants to Sleep: every other assistant awake with nothing under way sleeps now. Returns how many.
    @discardableResult func putIdleToSleep() -> Int {
        let idle = sessions.values.filter { $0 !== session && idle($0) }
        idle.forEach(sleep)
        return idle.count
    }

    /// Stops the agent of `session` and keeps its turns: its next message wakes it.
    private func sleep(_ session: Session) {
        halt(session)
        session.fold(engine.state)
        session.asleep = true
        save(session)
    }

    private func save(_ session: Session) { session.save(in: places.assistants) }

    /// The space to open by itself once the build asked from the blank page ended: the first new space listed since,
    /// while no other space is open. When one is, the new space is said `ready` instead, and nil returned.
    func appeared(_ entries: [Library.Entry], open: String?) -> String? {
        guard let before, let new = entries.first(where: { $0.isSpace && !before.spaces.contains($0.id) }) else { return nil }
        self.before = nil
        made.insert(new.id)
        hand(before.session, to: new.id)
        if open == nil { return new.id }
        ready = new
        return nil
    }

    /// The build's conversation becomes the space `name`'s own, its agent going on there rather than another being
    /// launched; New Space begins a new one with the same builder, model and effort, or with the builder Build With
    /// chose meanwhile.
    private func hand(_ built: Session, to name: String) {
        guard sessions[.new] === built else { return }
        if let old = sessions[.space(name)] { halt(old) }
        built.space = name
        sessions[.space(name)] = built
        save(built)
        let next = installed[preferred ?? ""] == true ? preferred : built.kind
        let fresh = next == built.kind ? Session(kind: next, model: built.model, effort: built.effort)
            : Session(kind: next, model: defaults(next).model, effort: defaults(next).effort)
        fresh.active = clock()
        sessions[.new] = fresh
        session = session(for: place)
    }

    /// The space `name` went to the Trash: its conversation goes with it, its agent stopped, and a space of the same
    /// name later begins a new one.
    func forget(_ name: String) {
        // Halted first, as halting saves: the file goes after, before the open space's conversation is made again.
        let gone = sessions.removeValue(forKey: .space(name))
        gone.map(halt)
        if let quick = quicks.removeValue(forKey: name) {
            halt(quick.session)
            quick.phase = .gone
        }
        try? FileManager.default.removeItem(at: Session.file(name, in: places.assistants))
        if let gone, gone === session { session = session(for: place) }
    }

    /// The messages of the space `name`'s conversation, the person's and the agent's: what the Trash sheet says goes.
    func messages(of name: String) -> Int {
        (sessions[.space(name)] ?? Session.restored(name, in: places.assistants)).map { AssistantModel.messages($0.rows) } ?? 0
    }

    static func messages(_ rows: [Row]) -> Int {
        rows.filter { $0.mine != nil || $0.reply != nil }.count
    }

    /// The eyes of the space `name`'s assistant, as its card would draw them: asleep while it has no conversation yet,
    /// which its next message starts.
    func eyes(of name: String) -> Sign.State {
        presence(of: sessions[.space(name)] ?? Session(kind: kind)).state
    }

    private func halt(_ session: Session) {
        endLaunch(session)
        if let id = session.id, session.agent?.alive != false { engine.stopAll(within: 5, only: id) {} }
        session.stopped = true
        save(session)
    }

    private func endLaunch(_ session: Session) { (session.launching, session.queued, session.launch) = (false, [], session.launch + 1) }

    private func deliver(_ message: String) { deliver(message, to: session) }

    /// Sends `message` to the agent of `session`; launches it first when there is none, once: what is written while it
    /// starts waits for it.
    func deliver(_ message: String, to session: Session) {
        guard session.kind != nil else { return }
        (session.last, session.failure, session.active) = (message, nil, clock())
        if let space = session.space, session.changing == nil {
            session.changing = (AssistantModel.shown(message).text, session.turn?.id)
            turnStarts(space)
        }
        if session.launching { return session.queued.append(message) }
        if let id = session.id, session.agent?.alive != false, !session.stopped {
            do { _ = try engine.deliver(message, to: id, when: "next") } catch { session.failure = error.sentence }
            return refresh()
        }
        start([message], in: session)
    }

    /// Launches this conversation's agent, continuing the thread `resume` when given, and sends `messages` once it runs,
    /// with what is written meanwhile.
    private func start(_ messages: [String], in session: Session? = nil, resume: String? = nil) {
        let session = session ?? self.session
        guard let kind = session.kind else { return }
        var resume = resume
        // A wake: the conversation goes on when its kind can pick it up, else a new one begins and says why.
        if resume == nil, session.asleep, session.thread != nil {
            if resumes(session) { resume = session.thread } else {
                session.renew(!Preferences.at(places).resume ? "Started a new conversation: resuming is off in Settings."
                              : !resumable(kind) ? "\(name(of: session)) cannot resume a conversation. Started a new conversation."
                              : session.asking != askEverything ? "Started a new conversation: Ask Before Every Change changed."
                              : "\(name(of: session)) could not pick its conversation up. Started a new conversation.")
                save(session)
            }
        }
        (session.launching, session.queued, session.failure) = (true, messages, nil)
        let number = session.launch
        engine.lookFor(kind) { [weak self] in
            // A launch ended by Stop, New Conversation or a switch while the program was looked for never starts.
            guard let self, number == session.launch,
                  sessions.values.contains(where: { $0 === session }) || quicks.values.contains(where: { $0.session === session }) else { self?.refresh(); return }
            let messages = session.queued
            session.queued = []
            do {
                let id = try engine.launchAssistant(kind, folder: places.spaces.path, model: session.model, effort: session.effort,
                                                    resume: resume, askEverything: askEverything, lent: lent(for: kind))
                (session.id, session.asking, session.stopped, session.asleep) = (id, askEverything, false, false)
                for message in messages { _ = try engine.deliver(message, to: id, when: "next") }
            } catch { session.failure = error.sentence }
            // Only now: the launch changes the state, and a build watched must not see it ended with no agent yet.
            session.launching = false
            refresh()
        }
    }

    // MARK: Quick Change

    /// A Quick Change on a space: its temporary session, the parts pointed at, the person's words and the chip's, and
    /// where it is: at work, done with a change (its frame says Done), ended (only the chip, which says so), or gone.
    @Observable final class Quick {
        enum Phase { case working, done, ended, gone }
        let space: String, sentence: String, session: Session, chip: String
        let parts: [Pointing.Part]
        var phase = Phase.working

        init(space: String, sentence: String, session: Session, chip: String, parts: [Pointing.Part]) {
            (self.space, self.sentence, self.session, self.chip, self.parts) = (space, sentence, session, chip, parts)
        }
    }

    /// How long a frame says Done before it leaves, and the chip says the session ended: the mockup's; a test lengthens
    /// them to draw each moment.
    @ObservationIgnored var lingers: (done: TimeInterval, ended: TimeInterval) = (0.9, 2.2)

    /// Whether a Quick Change works on the space `name` now.
    func quickWorks(on name: String?) -> Bool { name.flatMap { quicks[$0] }?.phase == .working }

    /// Quick Change: `words` about `parts` of the space `place` go to a temporary session of that space's assistant,
    /// launched now with the same kind, model and effort (none for a kind that picks its own model), Ask Before Every
    /// Change as it is set, in the spaces folder; the space's conversation is not touched. Its message holds the context
    /// line, one pointing line per part and the words. Returns why it is refused (another assistant works on this
    /// space, or it has no builder to ask); nil once it started.
    func quickChange(_ words: String, parts: [Pointing.Part], at place: Place) -> String? {
        let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .space(let title, let name, _) = place, !text.isEmpty, !parts.isEmpty else { return "Point at a part and say what should change." }
        let main = session(for: place)
        guard let kind = main.kind, installed[kind] != false, ![.missing, .crashed].contains(presence(of: main).stuck) else {
            return "\(AssistantModel.clean(title))’s assistant can’t start · open its card to see why"
        }
        if works(on: name) { return "\(AssistantModel.clean(title))’s assistant is working · try once it’s done" }
        let own = Registry.app.limits[kind]?.contains("model") == true
        let options = main.agent?.alive != false ? main.agent?.options : nil
        let model = own ? nil : main.model ?? main.agent?.model
        let label = model.map { m in (options ?? Preferences.at(places).listed[kind])?.model?.first { $0.value == m }?.label ?? m }
        let chip = ["Quick session", Registry.app.name(of: kind), own ? "its own model" : label].compactMap { $0 }.joined(separator: " · ")
        let temporary = Session(kind: kind, model: model, effort: main.effort)
        quicks[name] = Quick(space: name, sentence: text, session: temporary, chip: chip, parts: parts)
        turnStarts(name)
        deliver(([AssistantModel.context(place, home: places.home.path)] + AssistantModel.pointing(parts) + [text]).joined(separator: "\n"), to: temporary)
        return nil
    }

    /// One line per part: its name and its path, which holds only standard tags and their order (Pointing), nothing
    /// the page chose.
    static func pointing(_ parts: [Pointing.Part]) -> [String] { parts.map { "[something] Pointing at \($0.kind): \($0.path)" } }

    /// Ends each Quick Change whose turn ended (answered, failed, or its agent gone), once none of its requests waits.
    private func followQuicks() {
        let state = engine.state
        for quick in quicks.values where quick.phase == .working {
            let each = quick.session
            each.read(state)
            guard !each.launching else { continue }
            let asks = each.id.map { id in state.requests.contains { $0.agent == id } } == true
            guard !asks, over(each, after: nil) else { continue }
            end(quick)
        }
    }

    /// Stops the Quick Change's agent, keeps what it made, says Done on its frame when it changed the space, then that
    /// the session ended; the space's conversation sends the first message it held meanwhile.
    private func end(_ quick: Quick) {
        let each = quick.session
        let problem = each.failure ?? (light(each) == .error ? each.agent?.error?.message ?? "\(name(of: each)) stopped before it was done." : nil)
        let reply = each.rows.last { $0.reply != nil }?.reply
        halt(each)
        let changed = quickEnded(quick.space, quick.sentence, name(of: each), problem)
        quick.phase = changed ? .done : .ended
        if !changed, problem == nil, let reply { answered(quick, reply) }
        // Each moment waits its time, then moves on while this Quick Change is still the space's.
        let lingers = lingers, space = quick.space
        let after = { [weak self, weak quick] (seconds: TimeInterval, then: @escaping (Quick) -> Void) in
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { if let quick, self?.quicks[space] === quick { then(quick) } }
        }
        let leave = { [weak self] in
            after(lingers.ended) {
                $0.phase = .gone
                self?.quicks[space] = nil
            }
        }
        if changed {
            after(lingers.done) {
                $0.phase = .ended
                leave()
            }
        } else {
            leave()
        }
        if let main = sessions[.space(quick.space)], !main.held.isEmpty, !main.launching, ![.working, .waiting].contains(light(main)) { release(main) }
    }

    // MARK: Words

    /// Where the person is with `view` open: its title as its declaration gave it, else its name; the blank page for nil.
    static func place(_ view: SpaceView?) -> Place {
        view.map { .space(title: $0.title, name: $0.space.name, page: $0.space.page.path) } ?? .blank
    }

    /// The line something puts before each message, which the conversation strips: which space is open, by the title and
    /// name the declaration validated, the title kept on its line and out of brackets.
    static func context(_ place: Place, home: String) -> String {
        switch place {
        case .space(let title, let name, let page): return "[something] Open space: “\(clean(title))” (\(name), \(Words.path(page, home: home)))."
        case .blank: return "[something] No space is open: the person is on the blank page."
        case .templates: return "[something] No space is open: the person is on the templates."
        }
    }

    static func clean(_ title: String) -> String { String(title.filter { !$0.isNewline && $0 != "[" && $0 != "]" }) }

    /// Ask to Fix's words.
    static func fixing(_ fault: Fault) -> String {
        if fault.codes == [Fault.stopped] { return "The page of the space “\(clean(fault.title))” (\(fault.name)) stopped responding. Find why and fix it." }
        return "The space “\(clean(fault.title))” (\(fault.name)) has problems: \(fault.codes.joined(separator: ", ")). Run something check \(fault.name) and fix what it reports."
    }

    /// A message as the conversation shows it: its context line taken off, said as a caption ("about My agents").
    static func shown(_ text: String) -> (caption: String?, text: String) {
        guard text.hasPrefix("[something] ") else { return (nil, text) }
        let line = text.prefix { $0 != "\n" }, rest = String(text.dropFirst(line.count + 1))
        if line.hasSuffix("on the blank page.") { return ("on the blank page", rest) }
        if line.hasSuffix("on the templates.") { return ("on the templates", rest) }
        guard let open = line.range(of: "Open space: “"), let close = line.range(of: "” (", options: .backwards),
              open.upperBound <= close.lowerBound else { return (nil, rest) }
        return ("about " + line[open.upperBound..<close.lowerBound], rest)
    }

    /// The conversation's rows from the agent's thread: the day each turn starts when it is another than the last
    /// one's, messages and finished tools, never thoughts; a running tool is the present-tense line's.
    static func rows(_ turns: [Turn], calendar: Calendar = .current) -> [Row] {
        var last: Date?
        return turns.flatMap { turn -> [Row] in
            let start = (turn.started ?? turn.items.first?.at).flatMap(iso8601.date)
            let day: [Row] = start.map { start in
                defer { last = start }
                return last.map { calendar.isDate($0, inSameDayAs: start) } == true ? [] : [.day(start)]
            } ?? []
            var rows: [Row] = [], edit: Int?
            for item in turn.items {
                switch (item.kind, item.author) {
                case ("message", "person"):
                    let shown = shown(item.text)
                    rows.append(.mine(caption: shown.caption, text: shown.text))
                case ("message", _): rows.append(.reply(item.text))
                case ("tool", _), ("subagent", _):
                    guard item.tool?.status != "running" else { continue }
                    // A check that passed after an edit is said on the edit's line ("· checked"), as the mockup's.
                    if Presence.Step.of(item) == .check, item.tool?.status == "done", let at = edit,
                       case .tool(false, let words, nil) = rows[at] {
                        (rows[at], edit) = (.tool(failed: false, words: words + " · checked", command: nil), nil)
                        continue
                    }
                    rows.append(tool(item))
                    if Presence.Step.of(item) == .edit { edit = rows.count - 1 }
                default: continue
                }
            }
            return day + rows
        }
    }

    /// One tool in a few words: "Edited agents.html", "Read guide", "Ran" and the command.
    static func tool(_ item: Item) -> Row {
        let name = item.tool?.name ?? "tool", file = (item.text as NSString).lastPathComponent
        let denied = item.decision?.outcome == "denied", failed = denied || item.tool?.status == "failed"
        let after = denied ? " · denied" : failed ? " · failed" : ""
        // A command, code (Amp's, which calls something's tools), or a tool something lent (something_check), for which the
        // driver gives the command something ran.
        let words: String? = switch Presence.Step.of(item) {
        case .guide: "Read guide"
        case .command, .check: nil
        case .edit: "Edited \(file)"
        case .read: "Read \(file)"
        default: "Used \(name)"
        }
        return .tool(failed: failed, words: (words ?? "") + after, command: words == nil ? item.text : nil)
    }
}
