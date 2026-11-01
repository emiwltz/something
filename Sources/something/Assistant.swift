// The person's assistant as the window shows it: the coding agent that builds spaces with them in ~/something/spaces.
// The builder chosen among the installed ones, kept in the preferences with Ask Before Every Change; the knowledge
// files written into the spaces folder; one conversation per place, each space's own and New Space's, the card showing
// the open place's; each build from New Space a conversation of its own at once, going on wherever the person goes,
// as many at a time as they ask, never put to sleep, then handed to the space it made; each agent launched at its first
// message, never before, and told at each message which space is open; a message written while a turn runs held until
// it ends, and Take Back; Stop, New Conversation, the switch to another builder, and what went wrong; sleep (after the
// Preferences' delay, past the cap of awake assistants, or when the person asks), and the wake on the next message,
// which resumes the conversation a space keeps when its kind can. Each turn of a space's conversation is said when it
// begins and when it ends, so that the window keeps the space as each turn found and left it. A Quick Change is a
// temporary session of a space's assistant, the same kind with the same model and effort, told the parts pointed at; it
// is stopped once its turn ends (never while one of its requests waits), its change kept as a quick version (its
// answer a margin note when it changed nothing), and the space's own conversation, untouched, holds what the person
// writes to it meanwhile. Before a build, a reading asks the same agent, in a throwaway conversation launched as asking
// everything and lent nothing, what the person's words leave open (Brief); whatever goes wrong there means no question.
// The engine keeps every space away from this agent (Bridge.visible); something writes to it on its own only its
// context line, its pointing lines and Ask to Fix, never a page's text.
import AppKit
import Observation
import SomethingAgents
import SomethingCore

@Observable final class AssistantModel {
    /// Where the person is when they write: what each message's context line says.
    enum Place: Equatable {
        case space(title: String, name: String, page: String), blank, templates
        /// Which conversation a place has: a space's own, or New Space's, which the blank page and the templates share;
        /// and each build's while it runs, which New Space shows when the person follows it.
        enum Key: Hashable { case space(String), new, build(Int) }
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
    /// The window's: a build from the blank page ended, and it looks for its space (`appeared`).
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

    /// Arriving at the spaces shows the assistant as its sticker; from one space to another the card stays as it was,
    /// only its content changing: each place shows its own conversation.
    var place = Place.blank {
        didSet {
            if place.space != nil, oldValue.space == nil { open = false }
            // The space a build made, arriving: its card opens on the reply.
            if let space = place.space, space == revealing { (open, threadShown, revealing) = (true, true, nil) }
            // A template's copy: opening the card shows its first word.
            if let space = place.space, space == fromTemplate { threadShown = true }
            // Leaving New Space stops nothing: its builds go on, followed from their rows.
            if oldValue == .blank, place != .blank {
                (halted, nudged, watched) = (nil, false, nil)
                dropReading()
            }
            resolve()
            // The build's question is answered on New Space only: away, it is the panel's.
            follow()
        }
    }
    /// The build New Space shows, by its number; nil for its own field.
    private(set) var watched: Int?
    /// The space whose card opens on its conversation when it is shown: the one a build just made.
    @ObservationIgnored var revealing: String?

    /// Which conversation the open place has: on New Space, the build it shows, else its own.
    private var key: Place.Key { place == .blank ? watched.map(Place.Key.build) ?? .new : place.key }

    /// Takes the open place's conversation when it is another than the card's.
    private func resolve() {
        let now = sessions[key] ?? session(for: place)
        guard now !== session else { return }
        // The assistant left stays awake for the whole delay from now: it was the open one until now.
        (session.active, wantsFocus, unfolded) = (clock(), false, [])
        session = now
        // The left one is restful only now: nothing else may set the timer before its delay ends.
        rest()
        keepTime()
    }

    /// New Space shows the build `number`, or its own field for nil: a click on a building row, or on New Space.
    func watch(_ number: Int?) {
        watched = number.flatMap { n in builds.contains { $0.id == n } ? n : nil }
        if watched != nil { halted = nil }
        resolve()
        follow()
    }
    /// What the field holds: the open place's own, so a message half written goes to the agent it was written for.
    var draft: String {
        get { session.draft }
        set { if newValue != session.draft { commandPick = 0 }; session.draft = newValue }
    }
    /// The command chosen in the "/" list; -1 once Esc closed it, until the field changes.
    var commandPick = 0
    /// Whether the card is open (Reduce and ⌘\ close it), and whether it shows the conversation (⌘J).
    var open = true
    var threadShown = false
    /// The rows of the card's conversation whose Details are unfolded; folded again with another conversation.
    var unfolded: Set<Int> = []
    /// The height the card takes at the bottom of the center, set by the glass: the blank page keeps clear of it.
    var floating: CGFloat = 0
    /// The card's width, set by the glass: 412 points, less in a center too narrow for them.
    var cardWidth = AssistantCard.width
    /// Whether the card, closed, is still shrinking into the sticker: it is drawn until it is there.
    var folding = false
    /// Whether the open space's journal could not be written.
    var unkept = false
    /// Set by ⌘K until a field takes the focus; dropped as the place changes, so a stale one never takes another's keys.
    var wantsFocus = false
    /// Each place's conversation, made at its first use; and the one the card shows and the messages go to, the open
    /// place's, with what the window reads of it.
    private(set) var sessions: [Place.Key: Session] = [:]
    private(set) var session = Session(kind: nil)
    /// The Quick Change of each space, by its name: at work, or just ended while its frame and chip still show.
    private(set) var quicks: [String: Quick] = [:]
    /// New Space's reading of its words: under way, or ended and waiting for Build.
    private(set) var reading: Reading?
    /// Every agent a reading launched, for as long as the app runs: one stopped may still ask as it goes.
    @ObservationIgnored private var readers: Set<String> = []
    var kind: String? { session.kind }
    var id: String? { session.id }
    var agent: Agent? { session.agent }
    var rows: [Row] { session.rows }
    var asking: Bool { session.asking }
    var launching: Bool { session.launching }
    var failure: String? { session.failure }
    var asleep: Bool { session.asleep }
    private(set) var askEverything: Bool
    /// Full Access in Settings › Permissions, kept here so that the first lines follow it while they show.
    var fullAccess: Bool
    /// What the state says of each builder: installed or not; absent while not known.
    private(set) var installed: [String: Bool] = [:]
    private(set) var notes: [String: String] = [:]
    /// Why a builder that refused what something lends it is not offered, until the agents are looked for again.
    private(set) var refused: [String: String] = [:]
    /// A build asked from the blank page: its number, the spaces there were, the conversation building and its last
    /// turn then, when it was asked and in which words, and when something first saw each of its items and their ends
    /// (the agents stamp theirs to the second): the ladder's times.
    struct Build: Identifiable {
        let id: Int, spaces: Set<String>, session: Session, turn: String?, at: Date, sentence: String
        var seen: [String: Date] = [:]
        /// What the space may do with the person's agents, chosen before Build: written as its grant once it appears.
        var choice = LevelChoice()
    }
    /// The builds running, oldest first, each watched until the turn that followed ends (answered, stopped, failed, or
    /// never started).
    private(set) var builds: [Build] = []
    @ObservationIgnored private var numbered = 0
    /// The build New Space shows.
    var before: Build? { watched.flatMap { n in builds.first { $0.id == n } } }
    /// The build that just ended, while the window looks for the space it made (`appeared`), and whether New Space
    /// showed it then.
    @ObservationIgnored private var ending: (build: Build, shown: Bool)?
    /// The ladder of the build the person stopped on the blank page, kept until they build again or leave.
    private(set) var halted: Ladder?
    /// Whether Esc was just pressed while the blank page builds: its ladder says how to stop, for a moment.
    private(set) var nudged = false
    @ObservationIgnored private var nudges = 0
    /// The question the build asks, by its request, answered on the blank page (Panels leaves it there).
    struct Asked: Equatable { let request: String, question: Question }
    private(set) var asked: Asked?
    /// When the blank page first showed `asked`: its choices take a click or a digit only RequestPanel.arming later,
    /// so that one meant for the page as the question grows under it does not answer the agent.
    private(set) var askedShown: Date?
    /// The question of a build the person stopped or left, until its agent withdraws it, which comes later: kept out of
    /// the panel meanwhile, as nobody should be asked what they just stopped.
    @ObservationIgnored private var dropped: String?
    /// Add Comment's message on each space until its turn ends: its sentence, the turn it followed once it left the
    /// hold (nil while held), and whether the person stopped it.
    struct Commenting { let message: String, sentence: String; var after: String??, stopped = false }
    @ObservationIgnored private var commenting: [String: Commenting] = [:]
    /// Says a sentence in a toast: the window's.
    @ObservationIgnored var told: (String) -> Void = { _ in }
    /// The spaces builds made while the person was elsewhere, until each is opened: their rows carry a dot.
    var ready: Set<String> = []
    /// The space just made from a template, until the person writes: the input offers to make it theirs.
    var fromTemplate: String?
    /// The spaces made while the person waited for one: their level sheet says the agent made them.
    private(set) var made: Set<String> = []
    @ObservationIgnored private var preferred: String?
    /// something's own program, which runs and serves the tools a builder is lent; a trial gives another.
    @ObservationIgnored var program = Bundle.main.executableURL
    /// Moved by a one-shot timer when time alone changes the presence (Stop offered 10 s into a turn, "Changed …" gone
    /// 3.6 s after it, sleep after the delay): the presence reads it, so the card and the sticker ask again.
    private(set) var beat = 0
    @ObservationIgnored private var beatTimer: Timer?
    @ObservationIgnored private(set) var beatAt: Date?

    /// The agents each space launched, kept by the app: a space this build makes is new, whatever its name was before.
    @ObservationIgnored let launches: Launches

    init(engine: Engine, places: Places, launches: Launches = Launches()) {
        self.engine = engine
        self.places = places
        self.launches = launches
        let kept = Preferences.at(places)
        preferred = kept.assistant
        askEverything = kept.askEverything
        fullAccess = kept.fullAccess
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
            if let kind = each.kind, let options = each.agent?.options, options.model?.isEmpty == false, Preferences.at(places).listed[kind] != options { Preferences.at(places).listed[kind] = options }
            if let kind = each.kind, let commands = each.agent?.commands, Preferences.at(places).commands[kind] != commands { Preferences.at(places).commands[kind] = commands }
            if ["working", "waiting"].contains(each.agent?.state) { each.active = clock() }
        }
        rest()
        keepTime()
        // No turn will end to release them: the held messages go back into the field rather than wait for ever.
        if !session.held.isEmpty, !quickWorks(on: place.space), light == .error || (light == .off && id != nil) { takeBack() }
        follow()
        followQuicks()
        followReading()
        // Each build is concluded on the refresh where its turn ends, before a held message starts the next, wherever
        // the person went meanwhile.
        for build in builds where !build.session.launching && over(build.session, after: build.turn) { conclude(build) }
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
        let inline = inlineQuestion()
        if inline?.request != asked?.request { askedShown = inline.map { _ in clock() } }
        keep(\.asked, inline)
        if let dropped, !engine.state.requests.contains(where: { $0.id == dropped }) { self.dropped = nil }
        let now = clock()
        for index in builds.indices {
            guard let turn = builds[index].session.turn, turn.id != builds[index].turn else { continue }
            var seen = builds[index].seen
            for item in turn.items {
                for key in [item.id] + ((item.tool?.status).map { ["\(item.id)/\($0)"] } ?? []) where seen[key] == nil { seen[key] = now }
            }
            if let asked = question(of: builds[index]), seen[asked.request] == nil { seen[asked.request] = now }
            if seen != builds[index].seen { builds[index].seen = seen }
        }
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
        guard build.session === sessions[.build(build.id)], let id = build.session.id else { return nil }
        for request in engine.state.requests where request.kind == "question" && request.agent == id {
            if let questions = engine.prompt(request.id)?.questions, questions.count == 1, let one = questions.first, !one.multiple,
               (1...9).contains(one.options.count) { return Asked(request: request.id, question: one) }
        }
        return nil
    }

    /// Whether `request` is answered on the blank page rather than in the panel: Panels' filter.
    /// A reading's agent is covered too: it hears a no (`followReading`), the person never sees it.
    func answersInline(_ request: Request) -> Bool {
        request.id == dropped || readers.contains(request.agent) || inlineQuestion()?.request == request.id
    }

    /// The ladder New Space shows: the build's it follows as it goes, or the one stopped there; nil when there is neither.
    var ladder: Ladder? { halted ?? before.map(ladder) }

    /// The ladder of `build` as it goes; its question only while New Space shows it, where it is answered.
    func ladder(_ build: Build) -> Ladder {
        let turn = build.session.turn.flatMap { $0.id == build.turn ? nil : $0 }
        let asked = build.id == watched ? asked : nil
        return Ladder.read(turn?.items ?? [], seen: build.seen, from: build.at, asked: asked?.question, askedAt: asked.flatMap { build.seen[$0.request] })
    }

    /// The space `build` writes, by its name, once its ladder names the page; nil before.
    func space(of build: Build) -> String? {
        ladder(build).wrote.flatMap { $0.hasSuffix(".html") ? String($0.dropLast(5)) : nil }
    }

    /// The build that writes the space `name`, when one does.
    func build(writing name: String) -> Build? { builds.first { space(of: $0) == name } }

    /// The name a build's row shows until its space has one: its words, cut at a word before 26 characters.
    static func provisional(_ sentence: String) -> String {
        var shown = ""
        for word in sentence.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines)).split(whereSeparator: \.isWhitespace) {
            guard (shown + " " + word).count <= 26 else { return shown.trimmingCharacters(in: CharacterSet(charactersIn: ",;:")) + "…" }
            shown = shown.isEmpty ? String(word) : shown + " " + word
        }
        return shown
    }

    /// How far the question's choices have armed, from 0 to 1; they answer at 1.
    func arming(now: Date) -> Double {
        guard let askedShown else { return 0 }
        return min(1, max(0, now.timeIntervalSince(askedShown) / RequestPanel.arming))
    }

    /// Answers the build's question with its choice `index`, once its choices have armed; before, nothing happens. An
    /// answer that did not reach the agent is its failure.
    func answer(_ index: Int) {
        guard let asked, asked.question.options.indices.contains(index), arming(now: clock()) >= 1 else { return }
        self.asked = nil
        do { try engine.answer(asked.request, .choice([[asked.question.options[index]]])) } catch { before?.session.failure = error.sentence }
    }

    /// Sets the one-shot timer for the next moment a presence changes by itself, the card's or a space's in the
    /// sidebar, or an assistant falls asleep, if there is one.
    private func keepTime() {
        let now = clock(), delay = sleepDelay
        let at = (sessions.values.flatMap { each -> [Date?] in
            [[.working, .waiting].contains(light(each)) ? each.turn?.started.flatMap(iso8601.date).map { $0 + Presence.late }
                : each.turn?.ended.flatMap(iso8601.date).map { $0 + Presence.changedFor },
             delay.flatMap { restful(each) ? each.active + $0 : nil }]
        } + [reading.flatMap { $0.brief == nil ? $0.until : nil }]).compactMap { $0 }.filter { $0 > now }.min()
        guard at != beatAt else { return }
        beatTimer?.invalidate()
        (beatTimer, beatAt) = (nil, at)
        guard let wait = at?.timeIntervalSince(clock()), wait > 0 else { return }
        beatTimer = Timer.scheduledTimer(withTimeInterval: wait + 0.05, repeats: false) { [weak self] _ in self?.tick() }
    }

    func tick() {
        followReading()
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

    /// Whether the agent this place's assistant uses (the one name(of:) names) picks a conversation up when it wakes.
    var agentResumes: Bool { resumable(session.kind ?? preferred ?? builders.first ?? "") }

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
        return found.isEmpty ? "No coding agent found." : "\(found.map(Registry.app.name).joined(separator: ", ")) can’t build spaces."
    }

    /// Whether New Space shows a build as it goes.
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

    /// The card's status line: the presence's, or, signed out, the notice's cause rather than the model it could not reach.
    var header: String { signedOut ? "Not signed in to its model" : presence.header }

    /// What went wrong with the last message, in the agent's or the engine's words; nil when nothing did.
    var problem: String? {
        if let failure { return failure }
        guard light == .error, !session.stopped else { return nil }
        return agent?.error?.message
    }

    var placeholder: String {
        if blocked { return presence.stuck != .missing ? "Start Again to send a message" : others.isEmpty ? "Install \(name) to continue" : "Choose an agent to continue" }
        switch place {
        case .space(_, let space, _) where space == fromTemplate: return "Ask \(name) to make it yours: colors, sections, anything."
        case .space(let title, _, _):
            if !held.isEmpty { return "Write another request…" }
            if presence.stuck == .cannotReachModel { return "Write now · sent when the model answers" }
            // Waiting for an answer, the way on is the request's own window, not this field: it reads as usual.
            if light == .working { return "Write the next one · sent when this one ends" }
            // Asleep, its commands are not listed yet, but "/" says so, and the header says it wakes (X1.3).
            return commands.isEmpty && presence.state != .sleep ? "Ask for a change…" : "Ask for a change · / for " + Words.possessive(name) + " commands"
        case .blank: return "Describe the space you want…"
        case .templates: return "Ask \(name) about templates, or anything about something…"
        }
    }

    /// The spaces folder as the person reads it: "~/something/spaces".
    var folder: String { Words.path(places.spaces.path, home: places.home.path) }

    /// New Space's level with the person's agents: the one they chose, else the one the field's words suggest, else
    /// Settings' "A new space may". The choice is the consent: the space it builds opens with it, nothing asked.
    var level: Grant.Level { chosenLevel ?? Grant.Level.guess(draft, otherwise: Preferences.at(places).level) }
    var chosenLevel: Grant.Level?
    /// Which agents it shows, and which it starts, once the person chose; the assistant's own program until then.
    var chosenScope: Scope?
    var chosenStart: Grant.Start?
    /// The folder agents start in at Run, chosen on New Space.
    var runFolder = LevelChoice.Folder.none
    /// New Space's sentence. Any word the person changes makes all of it their choice.
    var choice: LevelChoice {
        get { choice(at: level) }
        set {
            (chosenLevel, chosenScope) = (newValue.level, newValue.scope)
            if newValue.level == .run { (chosenStart, runFolder) = (newValue.start, newValue.folder) }
        }
    }
    /// The sentence at `level`: only Run has an agent and a folder.
    private func choice(at level: Grant.Level) -> LevelChoice {
        let run = level == .run
        return LevelChoice(level: level, scope: chosenScope, start: run ? chosenStart ?? kind.map { Grant.Start(kind: $0) } : nil, folder: run ? runFolder : .none)
    }
    /// The tag of the sentence: who set it. A default is said as such, so that it can be changed where it is set.
    var origin: String { chosenLevel != nil ? "Your choice" : Grant.Level.guessed(draft) != nil ? "Pre-set from your words" : Self.defaultOrigin }
    static let defaultOrigin = "Your default"
    /// What replaces the sentence's lock line. Assistants are no agent of a space: none can write to them.
    var warning: String? {
        Levels.warning(choice, agents: engine.state.agents.filter { !engine.assistants.contains($0.id) }, threads: engine.state.threads)
    }
    /// Asks Run's folder when Build finds none; a test answers in its place.
    @ObservationIgnored var chooseFolder: (@escaping (String) -> Void) -> Void = Levels.chooseFolder

    /// What the assistant says first on a template's copy, until the conversation has rows.
    var firstWord: String? {
        guard case .space(let title, let space, _) = place, space == fromTemplate, rows.isEmpty else { return nil }
        return "This is your copy of \(title). Tell me what to change, and I change it here."
    }

    /// The conversation's first lines: where the agent works and how it asks, whether it can pick a conversation up,
    /// and why a new one began. A conversation picked up after sleep said them when it began: it shows none.
    var firstLines: [String] {
        guard session.kept.isEmpty else { return [] }
        let agent = kind.flatMap(Registry.app.agent), full = fullAccess ? "Full Access is on: something allows what it asks." : nil
        let how = if agent?.neverAsks == true { "\(name) works in \(folder). \(name) never asks: it can run any command on your Mac." }
            else if agent?.asksNothingByDefault == true {
                "\(name) works in \(folder). By default \(name) asks nothing: it can run any command on your Mac, unless your own \(name) settings say otherwise."
            }
            else if agent?.builder?.preAllowed == false {
                "\(name) works in \(folder). It asks as your own \(name) settings say." + (full.map { " " + $0 } ?? "")
            }
            else if id == nil ? askEverything : asking {
                "\(name) works in \(folder). It asks you before every change." + (full.map { " " + $0 } ?? "")
            }
            else {
                "\(name) works in \(folder). It may change your spaces and run something’s own commands there without asking. "
                    + (full ?? "Anything else asks you.")
            }
        return [how] + (resumable(kind ?? "") ? [] : ["\(name) cannot resume a conversation, so each one starts fresh."])
            + [session.renewed].compactMap { $0 }
    }

    /// The builders found, as the agent menus list them.
    var entries: [Entry] {
        builders.filter { installed[$0] == true }.map { kind in
            let agent = Registry.app.agent(kind)
            let because = refused[kind] != nil ? "can’t build spaces" : agent?.neverAsks == true ? "never asks before acting"
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
        let blankBuild = place == .blank && before == nil, level = chosenLevel ?? Grant.Level.guess(text, otherwise: Preferences.at(places).level)
        // Run starts agents in a folder: the build waits for one.
        if blankBuild, level == .run, runFolder == .none {
            return chooseFolder { [weak self] folder in
                guard let self else { return }
                (runFolder, chosenLevel) = (.path(folder), .run)
                send(sentence)
            }
        }
        if sentence == nil { draft = "" }
        fromTemplate = nil
        halted = nil
        // While its turn runs, the app holds the message rather than the agent: Take Back and Stop can still give it back.
        // Behind messages already held it waits too, so they leave in the order they were written; and while a Quick
        // Change works on this space, until it ends.
        // One of the agent's own commands goes as written, which the agent reads only at a message's start.
        let message = commands.contains { text == "/" + $0.value || text.hasPrefix("/\($0.value) ") } ? text : AssistantModel.context(place, home: places.home.path) + "\n" + text
        if quickWorks(on: place.space) || (session.id != nil && !launching && (working || !session.held.isEmpty)) { return session.held.append(message) }
        if blankBuild {
            // The build is watched from its first message, in a conversation of its own: New Space shows it, and starts
            // afresh for the next one. The level goes with it, said to the agent on a line of its own.
            let spaces = Set(Spaces(root: places.spaces).list().map(\.name)), built = session
            numbered += 1
            builds.append(Build(id: numbered, spaces: spaces, session: built, turn: built.turn?.id, at: clock(), sentence: text, choice: choice(at: level)))
            sessions[.build(numbered)] = built
            // What is still written in the field (a suggestion was sent) stays with New Space.
            let next = fresh(after: built)
            (next.draft, built.draft) = (built.draft, "")
            sessions[.new] = next
            let line = choice(at: level).line(home: places.home.path)
            (watched, threadShown, chosenLevel, chosenScope, chosenStart) = (numbered, true, nil, nil, nil)
            // A sentence sent from elsewhere leaves the field's reading alone.
            let brief = sentence == nil ? briefed(text) : [Brief.nothing]
            return deliver(([AssistantModel.context(place, home: places.home.path), line] + brief + [text]).joined(separator: "\n"), to: built)
        }
        deliver(message)
    }

    /// Ask to Fix: only something's own words, the space's validated title and name and the codes.
    func fix(_ fault: Fault) {
        deliver(AssistantModel.context(place, home: places.home.path) + "\n" + AssistantModel.fixing(fault))
    }

    /// ⌘K: opens the card. Its field is asked a turn later, after the glass shows it and the page the library opens.
    func focus() {
        open = true
        DispatchQueue.main.async { [weak self] in self?.wantsFocus = true }
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
        stop(place == .blank ? before : nil)
    }

    /// Stops the running turn, and `build`, asked from the blank page, with it: its ladder stays as it was, saying what
    /// stays on disk, and the sentence goes back into the field, to change or build again. The watch ends here: a space
    /// it began is not opened by itself.
    private func stop(_ build: Build?) {
        if let build {
            dropped = question(of: build)?.request
            let left = ladder(build).halted()
            (asked, nudged) = (nil, false)
            remove(build)
            back(build)
            keepLevel(build)
            halted = left
        }
        takeBack()
        // Comments at work come back to their tray: a stopped turn did not do them, whatever the agent's state says.
        if let space = session.space, commenting[space]?.after != nil { commenting[space]?.stopped = true }
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
        // A build shown ends with its conversation; New Space's own stays as it is.
        if let build = before {
            remove(build)
            halt(build.session)
            return resolve()
        }
        halt(session)
        halted = nil
        session = Session(kind: kind, model: session.model, effort: session.effort, space: session.space)
        sessions[session.space.map(Place.Key.space) ?? .new] = session
        save(session)
        ready = []
    }

    /// New Space's next conversation after `built` began building: the same builder, model and effort, or the builder
    /// Build With chose meanwhile.
    private func fresh(after built: Session) -> Session {
        let next = installed[preferred ?? ""] == true ? preferred : built.kind
        let fresh = next == built.kind ? Session(kind: next, model: built.model, effort: built.effort)
            : Session(kind: next, model: defaults(next).model, effort: defaults(next).effort)
        fresh.active = clock()
        return fresh
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
    /// Held comments go back to their tray instead (`commented(on:)`), never twice into the field.
    func takeBack() {
        guard !session.held.isEmpty else { return }
        let comments = session.space.flatMap { commenting[$0]?.message }
        let words = session.held.filter { $0 != comments }.map { AssistantModel.shown($0).text }
        draft = ([draft.trimmingCharacters(in: .whitespacesAndNewlines)] + words).filter { !$0.isEmpty }.joined(separator: "\n")
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
            followReading()
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

    /// `kind` becomes the default builder; the default model and effort, another builder's, are its own again; what it offers is read once, for its menu before its first run.
    private func keepDefault(_ kind: String) {
        preferred = kind
        Preferences.at(places).change { if $0.assistant != kind { ($0.assistant, $0.model, $0.effort) = (kind, nil, nil) } }
        guard Preferences.at(places).listed[kind] == nil, Registry.app.limits[kind]?.contains("model") != true else { return }
        engine.peek(kind, folder: places.spaces.path) { [self] in if let options = $0 { Preferences.at(places).listed[kind] = options } }
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
        followReading()
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
        if draft.isEmpty, agent?.thread == nil, let last = session.last { draft = AssistantModel.shown(last).text }
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

    /// Whether `session` can be put to sleep without the person asking: awake and idle, not the open place's, not a
    /// build's, and of a kind that picks its conversation up when it wakes.
    private func restful(_ session: Session) -> Bool {
        idle(session) && session !== self.session && resumable(session.kind ?? "")
    }

    /// Whether an assistant works on the space `name` now: starting, in a turn, or waiting for the person. Its change
    /// cannot be undone meanwhile: the restore would mix with what it writes.
    func works(on name: String) -> Bool {
        quickWorks(on: name) || sessions.values.contains { $0.space == name && ($0.launching || $0.changing != nil || [.working, .waiting].contains(light($0))) }
    }

    /// Awake with nothing under way: no turn running or waiting, no message held, not starting, not building: a
    /// building assistant never sleeps. An agent whose state nobody can read is not idle: something never guesses.
    private func idle(_ session: Session) -> Bool {
        awake(session) && !session.launching && session.held.isEmpty && !builds.contains { $0.session === session }
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

    /// The space the build that just ended made: the page it wrote, which may have been there before; else, when it
    /// wrote none, the first space listed since it began that no other build writes and none made. Returns it to open
    /// while the person is on New Space following that build, or with nothing written; anywhere else, Templates
    /// included, it is said `ready` (`arrived`), and nil returned.
    func appeared(_ entries: [Library.Entry]) -> String? {
        guard let (before, shown) = ending else { return nil }
        // Several builds run at once: a page another one writes is new to this one too, and is never its to take.
        let others = Set(builds.compactMap(space(of:)))
        let wrote = space(of: before)
        let found = wrote != nil ? entries.first { $0.isSpace && $0.id == wrote }
            : entries.first { $0.isSpace && !before.spaces.contains($0.id) && !others.contains($0.id) && !made.contains($0.id) }
        guard let new = found else { return nil }
        ending = nil
        made.insert(new.id)
        consent(new.id, before.choice)
        hand(before.session, to: new.id)
        if place == .blank, shown || (watched == nil && sessions[.new]?.draft.isEmpty != false) {
            revealing = new.id
            return new.id
        }
        ready.insert(new.id)
        arrived(new.id, new.title)
        return nil
    }

    /// Said once a build made the space `name`, titled `title`, while the person was elsewhere: the window's toast, and
    /// the Mac's notification while something is in the background.
    @ObservationIgnored var arrived: (_ name: String, _ title: String) -> Void = { _, _ in }

    /// Ends `build`, whose turn is over: the window looks for the space it made; with none, its conversation goes back
    /// to New Space, its reply or its trouble said there.
    private func conclude(_ build: Build) {
        let shown = watched == build.id
        remove(build)
        ending = (build, shown)
        ended()
        if let left = ending, left.build.id == build.id {
            ending = nil
            back(build)
            if !shown && !(place == .blank && watched == nil) {
                told(trouble(build.session) ? "Your new space didn’t build · your words are back" : "Your assistant answered on New Space")
            }
        }
        resolve()
    }

    /// Whether the conversation `session` ended in trouble: failed, or its agent gone, not stopped by the person.
    private func trouble(_ session: Session) -> Bool {
        session.failure != nil || (!session.stopped && (light(session) == .error || session.agent?.alive == false))
    }

    /// `build` is no longer one: its number is forgotten, and New Space shows its own field when it showed it.
    private func remove(_ build: Build) {
        builds.removeAll { $0.id == build.id }
        sessions[.build(build.id)] = nil
        if watched == build.id { watched = nil }
    }

    /// A build that made no space, or that the person stopped: its conversation becomes New Space's, its agent going
    /// on there; one New Space had is stopped and its turns kept above, or, while it still works or waits, goes on and
    /// keeps the build's turns above its own. Either way no reply is lost. A failed build's words are back in New
    /// Space's field.
    private func back(_ build: Build) {
        let built = build.session, failed = trouble(built)
        if let new = sessions[.new], new !== built {
            let busy = new.launching || !new.held.isEmpty || (new.agent?.alive != false && ["working", "waiting"].contains(new.agent?.state))
            if busy {
                halt(built)
                built.fold(engine.state)
                new.kept = built.kept + new.kept
                new.read(engine.state)
            } else {
                halt(new)
                new.fold(engine.state)
                built.kept = new.kept + built.kept
                built.read(engine.state)
                built.draft = [built.draft, new.draft].filter { !$0.isEmpty }.joined(separator: "\n")
                sessions[.new] = built
            }
        }
        if failed, let target = sessions[.new], !target.draft.contains(build.sentence) {
            target.draft = [build.sentence, target.draft].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        // Its words back, the level it was built with comes with them: never a fresh guess that would seem to change it.
        if failed { keepLevel(build) }
        resolve()
    }

    /// The level `build` was chosen with, on New Space again with its words.
    private func keepLevel(_ build: Build) {
        choice = build.choice
    }

    /// Writes the level chosen on New Space as the grant of the space `name` it built: the choice is the consent, so
    /// its first opening asks nothing. A page that cannot be read yet is asked at its opening instead.
    private func consent(_ name: String, _ choice: LevelChoice) {
        // The name was free when the build began: agents kept under it were launched by a space since deleted, and
        // the grant written here would hide that from the opening, which drops them only when it finds no grant.
        launches.ids[name] = nil
        guard let space = Spaces(root: places.spaces).list().first(where: { $0.name == name }),
              let declaration = Declaration.read(space, home: places.home, kinds: Registry.app.kinds).declaration else { return }
        let folder = choice.folder == .blank ? places.blank(name) : choice.folder.path
        // The sentence holds, whatever the page declares: said "all your agents", it means all; said "start pi in a
        // folder", the page sees that folder and what it starts, nothing wider.
        let scope: Scope? = switch choice.level {
        case .none: nil
        case .run: folder.map { .folders([$0]) }
        case .watch, .talk: choice.scope ?? .all
        }
        try? Grants(places.grants).update {
            $0.spaces[name] = Rights.leveled(choice.level, folder: folder, declaration: declaration, at: iso8601.string(from: clock()), after: nil, start: choice.start, scope: scope)
        }
    }

    /// The build's conversation becomes the space `name`'s own, its agent going on there rather than another being
    /// launched; a conversation the space had ends.
    private func hand(_ built: Session, to name: String) {
        if let old = sessions[.space(name)], old !== built { halt(old) }
        built.space = name
        sessions[.space(name)] = built
        save(built)
        resolve()
    }

    /// The space `name` went to the Trash, which Undo may still reverse: its agent stops, and its conversation stays in
    /// its file, to come back asleep.
    func leave(_ name: String) { end(name, forgetting: false) }

    /// The space `name` is gone for good: its conversation goes with it, and a space of the same name later begins a new one.
    func forget(_ name: String) { end(name, forgetting: true) }

    private func end(_ name: String, forgetting: Bool) {
        // Halted first, as halting saves: the file goes after, before the open space's conversation is made again.
        let gone = sessions.removeValue(forKey: .space(name))
        gone.map(halt)
        if let quick = quicks.removeValue(forKey: name) {
            halt(quick.session)
            quick.phase = .gone
        }
        if forgetting { try? FileManager.default.removeItem(at: Session.file(name, in: places.assistants)) }
        if let gone, gone === session { session = session(for: place) }
    }

    /// The messages of the space `name`'s conversation, the person's and the agent's: what the Trash sheet says goes.
    func messages(of name: String) -> Int {
        (sessions[.space(name)] ?? Session.restored(name, in: places.assistants)).map { AssistantModel.messages($0.rows) } ?? 0
    }

    /// A build asked on the blank page, said short once its turn ended, as the mockup's: the person's sentence, one line
    /// of what was made, the reply's first paragraph, and under Details what came between (`steps`) and the reply's rest.
    struct Built: Equatable { var steps: Range<Int>, made: String?, short: String, rest: String? }

    /// The reply at `index` as a finished build: nil when it is not the last reply of a turn asked on the blank page,
    /// while that turn goes on (`ended` false and nothing asked since), or when it has nothing to fold.
    static func built(_ rows: [Row], at index: Int, ended: Bool) -> Built? {
        guard rows.indices.contains(index), let text = rows[index].reply, let asked = rows[..<index].lastIndex(where: { $0.mine != nil }),
              case .mine(let caption, _) = rows[asked], caption == "on the blank page" else { return nil }
        let next = rows[(index + 1)...].firstIndex { $0.mine != nil }
        guard next != nil || ended, !rows[(index + 1)..<(next ?? rows.endIndex)].contains(where: { $0.reply != nil }) else { return nil }
        let steps = (asked + 1)..<index, cut = text.range(of: "\n\n")
        let rest = cut.map { text[$0.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        guard !steps.isEmpty || rest != nil else { return nil }
        return Built(steps: steps, made: made(rows[steps]), short: cut.map { String(text[..<$0.lowerBound]) } ?? text, rest: rest)
    }

    /// "Made week-end.html · checked, 0 errors": the page last edited and what its last check said; nil when no page
    /// was edited. An edit after a check leaves it unchecked.
    static func made(_ steps: ArraySlice<Row>) -> String? {
        var file: String?, checked: Bool?
        for case .tool(let failed, let words, let command) in steps {
            if words.hasPrefix("Edited ") {
                (file, checked) = (String(words.dropFirst(7).prefix { $0 != " " }), words.hasSuffix(" · checked") ? true : nil)
            } else if command?.contains("something check") == true || words.hasPrefix("Used something_check") {
                checked = !failed
            }
        }
        return file.map { "Made \($0) · " + (checked == true ? "checked, 0 errors" : checked == false ? "check found errors" : "unchecked") }
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
        let comments = session.space.flatMap { commenting[$0] }.flatMap { $0.message == message ? $0 : nil }
        if let space = session.space, comments != nil { commenting[space]?.after = .some(session.turn?.id) }
        if let space = session.space, session.changing == nil {
            session.changing = (comments?.sentence ?? AssistantModel.shown(message).text, session.turn?.id)
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
            let reads = self?.reading?.session === session
            guard let self, number == session.launch, reads || sessions.values.contains(where: { $0 === session })
                    || quicks.values.contains(where: { $0.session === session }) else { self?.refresh(); return }
            let messages = session.queued
            session.queued = []
            do {
                // Asking everything, an agent is lent nothing (Engine.launchAssistant): a reading can change no file unasked.
                let asking = askEverything || reads
                let id = try engine.launchAssistant(kind, folder: places.spaces.path, model: session.model, effort: session.effort,
                                                    resume: resume, askEverything: asking, lent: lent(for: kind))
                if reads { readers.insert(id) }
                (session.id, session.asking, session.stopped, session.asleep) = (id, asking, false, false)
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
            return Words.possessive(AssistantModel.clean(title)) + " assistant can’t start · open its card to see why"
        }
        if works(on: name) { return Words.possessive(AssistantModel.clean(title)) + " assistant is working · try once it’s done" }
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

    // MARK: Reading the words

    /// A reading of New Space's words: what it read, in which throwaway conversation, until when it may take, and what
    /// came of it. `brief` is nil while the agent reads; no question in it means there is nothing to ask.
    @Observable final class Reading {
        let words: String, session: Session, until: Date
        var brief: Brief?
        /// The person's answers, by question: a question not here was left as it is, and is not sent.
        var answers: [Int: Brief.Answer] = [:]

        init(words: String, session: Session, until: Date) { (self.words, self.session, self.until) = (words, session, until) }
    }

    /// How long a reading may take, the launch included, before it counts as nothing usable.
    @ObservationIgnored var readingLimit: TimeInterval = 25

    /// Starts reading the field's words when the person wants questions first. The same words with the same agent keep
    /// what was read and answered, with no second turn; a change of level after it read does not ask again.
    func read() {
        let words = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Preferences.at(places).askFirst, place == .blank, before == nil, !words.isEmpty, let kind, !blocked else { return }
        if let reading, reading.words == words, reading.session.kind == kind { return }
        dropReading()
        reading = nil
        let turn = Reading(words: words, session: Session(kind: kind, model: session.model, effort: session.effort), until: clock() + readingLimit)
        reading = turn
        deliver(Brief.asking(words, line: choice.line(home: places.home.path)), to: turn.session)
        keepTime()
    }

    /// Esc, or leaving New Space: a reading under way stops and is forgotten; one that ended stays for the same words.
    func dropReading() {
        guard let reading, reading.brief == nil else { return }
        self.reading = nil
        halt(reading.session)
    }

    /// Follows the reading on each change of the state and at its limit. Any request of a reader hears a no. A reading
    /// whose agent chip changed is forgotten. One that ended, or can no longer end well (an error, a request, its time
    /// gone), stops its agent and keeps what it read, which is nothing but for a clean end.
    private func followReading() {
        let state = engine.state
        for request in state.requests where readers.contains(request.agent) { try? engine.answer(request.id, .deny) }
        guard let reading else { return }
        let each = reading.session
        guard each.kind == sessions[.new]?.kind else {
            self.reading = nil
            if reading.brief == nil { halt(each) }
            return
        }
        guard reading.brief == nil else { return }
        each.read(state)
        let asked = state.requests.contains { $0.agent == each.id }, late = clock() >= reading.until
        guard asked || late || (!each.launching && over(each, after: nil)) else { return }
        let last = each.turn?.items.last { $0.kind == "message" && $0.author != "person" }
        let spaces = Set(Spaces(root: places.spaces).list().map(\.name))
        // Before the halt, which changes the state: this reading ends once.
        reading.brief = asked || late || trouble(each) ? Brief() : last.map { Brief.read($0, taken: spaces) } ?? Brief()
        halt(each)
    }

    /// What the build of `words` is told of the reading, which ends here: its answers and its name, or that the agent
    /// decides when there are none, or when the words changed since. A reading under way stops.
    private func briefed(_ words: String) -> [String] {
        guard let reading else { return [Brief.nothing] }
        self.reading = nil
        if reading.brief == nil { halt(reading.session) }
        guard reading.words == words, let brief = reading.brief else { return [Brief.nothing] }
        return brief.lines(reading.answers)
    }

    // MARK: Comments

    /// Add Comment's comments on the space `place`, sent together in one message to that space's own conversation, as a
    /// written message is: held while it works, or while a Quick Change works on the space. The message holds the
    /// context line, one line per comment with its part's name and path, then the numbered words; nothing of the page's
    /// text. Returns why it is refused (nothing to send, or no builder to ask); nil once sent or held.
    func comment(_ comments: [(part: Pointing.Part, words: String)], at place: Place) -> String? {
        let list = comments.filter { !$0.words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard case .space(let title, let name, _) = place, !list.isEmpty else { return "Point at a part and add a comment first." }
        let main = session(for: place)
        guard let kind = main.kind, installed[kind] != false, ![.missing, .crashed].contains(presence(of: main).stuck) else {
            return Words.possessive(AssistantModel.clean(title)) + " assistant can’t start · open its card to see why"
        }
        let lines = AssistantModel.comments(list), message = ([AssistantModel.context(place, home: places.home.path)] + lines).joined(separator: "\n")
        commenting[name] = Commenting(message: message, sentence: "\(list.count) comment\(list.count == 1 ? "" : "s")", after: nil)
        if quickWorks(on: name) || (main.id != nil && !main.launching && ([.working, .waiting].contains(light(main)) || !main.held.isEmpty)) {
            main.held.append(message)
            refresh()
        } else {
            deliver(message, to: main)
        }
        return nil
    }

    /// The comments' lines: where each part is, for the agent, then "3 comments on this page:" and each one numbered as
    /// its pin, by its part's name, its words on one line.
    static func comments(_ list: [(part: Pointing.Part, words: String)]) -> [String] {
        let header = "\(list.count) comment\(list.count == 1 ? "" : "s") on this page:"
        return list.indices.map { "[something] Comment \($0 + 1) is on \(list[$0].part.kind): \(list[$0].part.path)" } + [header]
            + list.indices.map { index in
                let kind = list[index].part.kind, words = list[index].words.split(whereSeparator: \.isNewline).joined(separator: " ")
                return "\(index + 1). \(kind.prefix(1).uppercased() + kind.dropFirst()): \(words.trimmingCharacters(in: .whitespaces))"
            }
    }

    /// What became of the comments sent on a space: on their way, done, or back to send again.
    enum Commented { case pending, done, back }

    /// What became of the last comments sent on the space `name`: done only once their own message was delivered and
    /// its turn answered; back when that turn was stopped or failed, or the message left the hold unsent (Take Back,
    /// Stop, New Conversation); pending until then. Back when none were sent: never a guess.
    func commented(on name: String) -> Commented {
        guard let comments = commenting[name], let session = sessions[.space(name)] else { return .back }
        guard let after = comments.after else { return session.held.contains(comments.message) ? .pending : .back }
        if comments.stopped { return .back }
        if session.launching || !over(session, after: after) { return .pending }
        let answered = session.last == comments.message && session.id != nil && !session.stopped && session.failure == nil
            && light(session) != .error && session.agent?.alive != false
        return answered ? .done : .back
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

    /// A message as the conversation shows it: its context line taken off, said as a caption ("about My agents"), and
    /// something's lines after it (where the parts pointed at are, for the agent) with it.
    static func shown(_ text: String) -> (caption: String?, text: String) {
        guard text.hasPrefix("[something] ") else { return (nil, text) }
        let line = text.prefix { $0 != "\n" }
        var after = text.dropFirst(line.count + 1)
        // Only something's own forms: a line the person wrote stays, whatever it starts with.
        let ours = { (line: Substring) in
            let number = line.dropFirst("[something] Comment ".count)
            return line.hasPrefix("[something] Pointing at ") || line.hasPrefix("[something] With your agents: ")
                || line.hasPrefix("[something] Brief: ") || line.hasPrefix("[something] Name it: ")
                || (line.hasPrefix("[something] Comment ") && number.first?.isNumber == true && number.drop { $0.isNumber }.hasPrefix(" is on "))
        }
        while ours(after) { after = after.drop { $0 != "\n" }.dropFirst() }
        let rest = String(after)
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
