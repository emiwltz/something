// The person's assistant as the window shows it: the coding agent that builds spaces with them in ~/something/spaces.
// The builder chosen among the installed ones, kept in the preferences with Ask Before Every Change; the knowledge
// files written into the spaces folder; one conversation per place, each space's own and New Space's, the card showing
// the open place's and a build from New Space going on as the new space's own; each agent launched at its first
// message, never before, and told at each message which space is open; a message written while a turn runs held until
// it ends, and Take Back; Stop, New Conversation, the stop after 30 idle minutes, the switch to another builder, and
// what went wrong. The engine keeps every space away from this agent (Bridge.visible); the only words something writes
// to it on its own are its context line and Ask to Fix, never a page's text.
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
    enum Row: Equatable { case day(Date), mine(caption: String?, text: String), reply(String), tool(failed: Bool, words: String, command: String?) }
    /// What the open space reported while it ran: its title, its name and the codes, never its text. A page that
    /// stopped is named by its file, with the app's own reason `stopped`, which is no code of the contract.
    struct Fault: Equatable {
        static let stopped = "STOPPED"
        var title: String, name: String, codes: [String]
    }
    /// One builder in the agent menu.
    struct Entry: Identifiable { let id: String, title: String, checked: Bool, enabled: Bool, note: String? }

    static let idleLimit: TimeInterval = 30 * 60

    @ObservationIgnored let engine: Engine
    @ObservationIgnored let places: Places
    /// The clock of the idle stop; a test moves it.
    @ObservationIgnored var clock: () -> Date = Date.init
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

    /// Arriving at the spaces shows the assistant as the sticker, as the mockup does; from one space to another the
    /// card stays as it was, only its content changing: each place shows its own conversation.
    var place = Place.blank {
        didSet {
            if place.space != nil, oldValue.space == nil { open = false }
            if place.key != oldValue.key { session = session(for: place) }
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
    var kind: String? { session.kind }
    var id: String? { session.id }
    var agent: Agent? { session.agent }
    var rows: [Row] { session.rows }
    var asking: Bool { session.asking }
    var launching: Bool { session.launching }
    var failure: String? { session.failure }
    var idled: Bool { session.idled }
    private(set) var askEverything: Bool
    /// What the state says of each builder: installed or not; absent while not known.
    private(set) var installed: [String: Bool] = [:]
    private(set) var notes: [String: String] = [:]
    /// Why a builder that refused what something lends it is not offered, until the agents are looked for again.
    private(set) var refused: [String: String] = [:]
    /// The spaces there were, the conversation building and its last turn when the person asked from the blank page,
    /// until the turn that followed ends (answered, stopped, failed, or never started).
    private(set) var before: (spaces: Set<String>, session: Session, turn: String?)?
    var ready: Library.Entry?
    /// The space just made from a template, until the person writes: the input offers to make it theirs.
    var fromTemplate: String?
    /// The spaces made while the person waited for one: their rights sheet says the agent made them.
    private(set) var made: Set<String> = []
    @ObservationIgnored private var preferred: String?
    /// something's own program, which runs and serves the tools a builder is lent; a trial gives another.
    @ObservationIgnored var program = Bundle.main.executableURL
    @ObservationIgnored private var timer: Timer?
    /// The presence changes with time alone twice: Stop is offered 10 s into a turn, and "Changed …" leaves 3.6 s after
    /// it. A one-shot timer moves `beat` then, which the presence reads, so the card and the sticker ask again; no timer
    /// runs at rest. `beatAt` is the moment it was set for.
    private(set) var beat = 0
    @ObservationIgnored private var beatTimer: Timer?
    @ObservationIgnored private var beatAt: Date?

    init(engine: Engine, places: Places) {
        self.engine = engine
        self.places = places
        let kept = Preferences.at(places)
        preferred = kept.assistant
        askEverything = kept.askEverything
        sessions[.new] = session
        refresh()
        // Once a minute: has the agent been idle for `idleLimit`?
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.checkIdle() }
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
            // A conversation whose program left the Mac keeps its builder: the card says it is missing rather than another
            // agent taking the conversation over unasked.
            let kind = each.kind ?? ""
            if !offered.contains(kind), each.last == nil || installed[kind] != false { each.kind = offered.first { $0 == preferred } ?? offered.first }
            each.read(state)
            if ["working", "waiting"].contains(each.agent?.state) { each.active = clock() }
        }
        keepTime()
        // No turn will end to release them: the held messages go back into the field rather than wait for ever.
        if !session.held.isEmpty, light == .error || (light == .off && id != nil) { takeBack() }
        // A build watched is concluded on the refresh where its turn ends, before a held message starts the next, wherever
        // the person went meanwhile.
        if let before, !before.session.launching {
            let built = before.session, light = light(built)
            let answered = built.turn.map { $0.id != before.turn && $0.state != "working" } == true && ![.working, .waiting].contains(light)
            if answered || built.id == nil || built.stopped || light == .error || built.agent?.alive == false {
                ended()
                if self.before?.session === built { self.before = nil }
            }
        }
        // A turn ended: the oldest held message of its conversation leaves, one per turn, as the mockup sends them.
        for each in sessions.values {
            guard let next = each.held.first, light(each) == .ready, !each.launching, each.releasedAfter != .some(each.turn?.id) else { continue }
            each.held.removeFirst()
            each.releasedAfter = .some(each.turn?.id)
            deliver(next, to: each)
        }
    }

    /// Sets the one-shot timer for the next moment a presence changes by itself, the card's or a space's in the
    /// sidebar, if there is one.
    private func keepTime() {
        let now = clock()
        let at = sessions.values.compactMap { each -> Date? in
            [.working, .waiting].contains(light(each)) ? each.turn?.started.flatMap(iso8601.date).map { $0 + Presence.late }
                : each.turn?.ended.flatMap(iso8601.date).map { $0 + Presence.changedFor }
        }.filter { $0 > now }.min()
        guard at != beatAt else { return }
        beatTimer?.invalidate()
        (beatTimer, beatAt) = (nil, at)
        guard let wait = at?.timeIntervalSince(clock()), wait > 0 else { return }
        beatTimer = Timer.scheduledTimer(withTimeInterval: wait + 0.05, repeats: false) { [weak self] _ in self?.tick() }
    }

    /// The presence is asked again: the time alone changed it.
    func tick() { beat += 1 }

    private func keep<Value: Equatable>(_ property: ReferenceWritableKeyPath<AssistantModel, Value>, _ value: Value) {
        if self[keyPath: property] != value { self[keyPath: property] = value }
    }

    /// The kinds that can build, in the order they are offered (Extensions.swift).
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

    /// Whether nothing can be sent until the person acts on the notice: its program left the Mac, or it quit.
    var blocked: Bool { kind != nil && [.missing, .crashed].contains(presence.stuck) }

    /// Whether Start Again picks this conversation up: its agent reported a thread, its kind resumes as it was launched,
    /// Ask Before Every Change is what it was (a resume keeps how it asked), and the last start did not fail, which a
    /// conversation the program cannot find again does: Start Again then begins a new one rather than fail for ever.
    var resumes: Bool { resumes(session) }

    func resumes(_ session: Session) -> Bool {
        session.thread != nil && Registry.resumesAsBuilt.contains(session.kind ?? "") && session.asking == askEverything
            && session.failure == nil && session.agent?.error?.code != "LAUNCH_FAILED"
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

    /// The conversation's first lines: where the agent works and how it asks, then how long a conversation lasts.
    var firstLines: [String] {
        let folder = Words.path(places.spaces.path, home: places.home.path), agent = kind.flatMap(Registry.app.agent)
        let how = if agent?.neverAsks == true { "\(name) works in \(folder). \(name) never asks: it can run any command on your Mac." }
            else if agent?.asksNothingByDefault == true {
                "\(name) works in \(folder). By default \(name) asks nothing: it can run any command on your Mac, unless your own \(name) settings say otherwise."
            }
            else if agent?.builder?.preAllowed == false { "\(name) works in \(folder). It asks as your own \(name) settings say." }
            else if id == nil ? askEverything : asking { "\(name) works in \(folder). It asks you before every change." }
            else { "\(name) works in \(folder). It may change your spaces and run something's own commands there without asking. Anything else asks you." }
        return [how, "A new conversation starts each time something starts."]
            + (session.renewed ? ["\(name) stopped and could not pick its conversation up. Started a new conversation."] : [])
            + (idled ? ["\(name) was stopped to save memory. Your next message starts it again."] : [])
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
        // While its turn runs, the app holds the message rather than the agent: Take Back and Stop can still give it back.
        // Behind messages already held it waits too, so they leave in the order they were written.
        if session.id != nil, !launching, working || !session.held.isEmpty {
            return session.held.append(AssistantModel.context(place, home: places.home.path) + "\n" + text)
        }
        if place == .blank, before == nil {
            // The build is watched from its first message: the conversation shows what the agent does.
            (before, threadShown) = ((Set(Spaces(root: places.spaces).list().map(\.name)), session, session.turn?.id), true)
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

    /// Stops the running turn, the agent staying for the next message; or, while the agent starts, ends its launch. An
    /// agent that cannot pause mid-task is ended: the conversation stays shown, and the next message starts it again.
    /// The held messages go back into the field: nothing is sent behind the person's back.
    func stop() {
        takeBack()
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
        session = Session(kind: kind, model: session.model, effort: session.effort, space: session.space)
        sessions[session.space.map(Place.Key.space) ?? .new] = session
        ready = nil
    }

    /// The conversation of `place`, made at its first use with the builder chosen now, launching nothing.
    func session(for place: Place) -> Session {
        if let kept = sessions[place.key] { return kept }
        let made = Session(kind: kind, space: place.space)
        made.active = clock()
        sessions[place.key] = made
        return made
    }

    /// The conversation whose agent is `agent`, of any place; nil when none of them launched it.
    func session(of agent: String) -> Session? { sessions.values.first { $0.id == agent } }

    /// The space the assistant `agent` works on: its conversation's space; nil for New Space's, which has none until
    /// the hand-off, whichever space is open meanwhile, so its requests are never counted as that space's own.
    func space(of agent: String) -> String? { session(of: agent)?.space }

    /// The messages held for the end of the turn, as the person wrote them.
    var held: [String] { session.held.map { AssistantModel.shown($0).text } }

    /// Take Back: the held messages go back into the field, after what it holds, and are never sent.
    func takeBack() {
        guard !session.held.isEmpty else { return }
        draft = ([draft.trimmingCharacters(in: .whitespacesAndNewlines)] + held).filter { !$0.isEmpty }.joined(separator: "\n")
        session.held = []
        wantsFocus = true
    }

    /// Relaunches, then sends the last message again.
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
            session.kept += engine.state.threads.first { $0.agent == session.id }?.turns ?? []
            // The dead agent's turns are kept now: its thread, still in the state, must not show them a second time.
            session.id = nil
        } else {
            newConversation()
            session.renewed = true
        }
        start([], resume: thread)
    }

    /// Copies the command that signs the builder in, in Terminal.
    func copyCommand() { copy(command) }

    /// Chooses the builder `kind`; a conversation running with another one ends, after the person said so.
    func choose(_ chosen: String) {
        guard chosen != kind, refused[chosen] == nil else { return }
        let switched = { [self] in
            newConversation()
            (session.kind, preferred) = (chosen, chosen)
            Preferences.at(places).assistant = chosen
        }
        if id != nil, agent?.alive != false, !session.stopped {
            confirmSwitch(name, Registry.app.name(of: chosen), switched)
        } else {
            switched()
        }
    }

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

    /// Ask Before Every Change: from the next conversation on.
    func toggleAsking() {
        askEverything.toggle()
        Preferences.at(places).askEverything = askEverything
    }

    /// Stops each conversation's agent after `idleLimit` without a turn: a Claude Code process holds a few hundred MB.
    func checkIdle() {
        for each in sessions.values {
            guard let agent = each.agent, agent.alive == true, !each.stopped, !["working", "waiting"].contains(agent.state),
                  clock().timeIntervalSince(each.active) >= AssistantModel.idleLimit else { continue }
            halt(each)
            each.idled = true
        }
    }

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
    /// launched; New Space begins a new one with the same builder, model and effort.
    private func hand(_ built: Session, to name: String) {
        guard sessions[.new] === built else { return }
        if let old = sessions[.space(name)] { halt(old) }
        built.space = name
        sessions[.space(name)] = built
        let fresh = Session(kind: built.kind, model: built.model, effort: built.effort)
        fresh.active = clock()
        sessions[.new] = fresh
        session = session(for: place)
    }

    /// The space `name` went to the Trash: its conversation goes with it, its agent stopped, and a space of the same
    /// name later begins a new one.
    func forget(_ name: String) {
        guard let gone = sessions.removeValue(forKey: .space(name)) else { return }
        halt(gone)
        if gone === session { session = session(for: place) }
    }

    /// The messages of the space `name`'s conversation, the person's and the agent's: what the Trash sheet says goes.
    func messages(of name: String) -> Int { sessions[.space(name)].map { AssistantModel.messages($0.rows) } ?? 0 }

    static func messages(_ rows: [Row]) -> Int {
        rows.filter { if case .mine = $0 { true } else if case .reply = $0 { true } else { false } }.count
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
    }

    private func endLaunch(_ session: Session) { (session.launching, session.queued, session.launch) = (false, [], session.launch + 1) }

    private func deliver(_ message: String) { deliver(message, to: session) }

    /// Sends `message` to the agent of `session`; launches it first when there is none, once: what is written while it
    /// starts waits for it.
    func deliver(_ message: String, to session: Session) {
        guard session.kind != nil else { return }
        (session.last, session.failure, session.active) = (message, nil, clock())
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
        (session.launching, session.queued, session.failure) = (true, messages, nil)
        let number = session.launch
        engine.lookFor(kind) { [weak self] in
            // A launch ended by Stop, New Conversation or a switch while the program was looked for never starts.
            guard let self, number == session.launch, sessions.values.contains(where: { $0 === session }) else { self?.refresh(); return }
            let messages = session.queued
            session.queued = []
            do {
                let id = try engine.launchAssistant(kind, folder: places.spaces.path, model: session.model, effort: session.effort,
                                                    resume: resume, askEverything: askEverything, lent: lent(for: kind))
                (session.id, session.asking, session.stopped, session.idled) = (id, askEverything, false, false)
                for message in messages { _ = try engine.deliver(message, to: id, when: "next") }
            } catch { session.failure = error.sentence }
            // Only now: the launch changes the state, and a build watched must not see it ended with no agent yet.
            session.launching = false
            refresh()
        }
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
            return day + turn.items.compactMap { item in
                switch (item.kind, item.author) {
                case ("message", "person"):
                    let shown = shown(item.text)
                    return .mine(caption: shown.caption, text: shown.text)
                case ("message", _): return .reply(item.text)
                case ("tool", _), ("subagent", _): return item.tool?.status == "running" ? nil : tool(item)
                default: return nil
                }
            }
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
