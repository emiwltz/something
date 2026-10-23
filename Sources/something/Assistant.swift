// The person's assistant as the window shows it: the coding agent that builds spaces with them in
// ~/something/spaces. The builder chosen among the installed ones, kept in window.json with Ask Before Every Change;
// the knowledge files written into the spaces folder; the agent launched at the first message, never before, and told
// at each message which space is open; Stop, New Conversation, the stop after 30 idle minutes, the switch to another
// builder, and what went wrong. The engine keeps every space away from this agent (Bridge.visible); the only words
// something writes to it on its own are its context line and Ask to Fix, never a page's text.
import AppKit
import Observation
import SomethingAgents
import SomethingCore

@Observable final class AssistantModel {
    /// Where the person is when they write: what each message's context line says.
    enum Place: Equatable { case space(title: String, name: String, page: String), blank, templates }
    /// The dot in front of the builder's name.
    enum Light: String { case off = "not started", ready, working, waiting = "waiting for you", error }
    /// One line of the drawer: the person's message with what it was about, the agent's text, or one tool it ran.
    enum Row: Equatable { case mine(caption: String?, text: String), reply(String), tool(symbol: String, words: String, command: String?) }
    /// What the open space reported while it ran: its title, its name and the codes, never its text.
    struct Fault: Equatable { var title: String, name: String, codes: [String] }
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

    var place = Place.blank
    var draft = ""
    var drawer = false
    /// Whether ⌘J hid the whole assistant, in full screen.
    var hidden = false
    /// The width the center leaves the assistant, and the height it floats over there, both set by the window
    /// (Floater): the conversation is measured as it wraps, and the blank page keeps clear of it.
    var room: CGFloat = 640
    var floating: CGFloat = 0
    /// The open space's runtime error, until dismissed or the next opening.
    var fault: Fault?
    /// Whether the open space's journal could not be written.
    var unkept = false
    /// Grows at each ⌘K: the input takes the focus.
    private(set) var focusing = 0
    /// The chosen builder; nil while none is found.
    private(set) var kind: String?
    private(set) var askEverything: Bool
    /// What the state says of each builder: installed or not; absent while not known.
    private(set) var installed: [String: Bool] = [:]
    private(set) var notes: [String: String] = [:]
    /// Why a builder that refused what something lends it is not offered, until the agents are looked for again.
    private(set) var refused: [String: String] = [:]
    /// This conversation's agent, as the state shows it, and its thread as the drawer shows it.
    private(set) var id: String?
    private(set) var agent: Agent?
    private(set) var rows: [Row] = []
    /// Whether this conversation's agent asks before every change: how it was launched, whatever the menu says now.
    private(set) var asking = false
    private(set) var launching = false
    /// Why the last launch or message failed, in the engine's words.
    private(set) var failure: String?
    /// Whether something stopped this conversation's agent, and whether for idleness.
    private(set) var stopped = false
    private(set) var idled = false
    /// The last message delivered, its context line included: Try Again sends it again.
    private(set) var last: String?
    /// The spaces there were and the conversation's last turn when the person asked from the blank page, until the
    /// turn that followed ends (answered, stopped, failed, or never started); the last turn now.
    private(set) var before: (spaces: Set<String>, turn: String?)?
    @ObservationIgnored private var turn: Turn?
    var ready: Library.Entry?
    /// The space just made from a template, until the person writes: the input offers to make it theirs.
    var fromTemplate: String?
    /// The spaces made while the person waited for one: their rights sheet says the agent made them.
    private(set) var made: Set<String> = []
    @ObservationIgnored private var preferred: String?
    /// something's own program, which runs and serves the tools a builder is lent; a trial gives another.
    @ObservationIgnored var program = Bundle.main.executableURL
    @ObservationIgnored private var active = Date()
    @ObservationIgnored private var told = false
    @ObservationIgnored private var timer: Timer?
    /// The messages written while the agent starts, sent once it runs; and the number of the launch that may still
    /// start it: Stop, New Conversation and a switch end a pending launch by moving this number on.
    @ObservationIgnored private var queued: [String] = []
    @ObservationIgnored private var launch = 0
    /// Where the assistant's pieces are drawn, in its hosting view: the window takes the clicks there only (Floater).
    @ObservationIgnored var drawn: [CGRect] = []

    init(engine: Engine, places: Places) {
        self.engine = engine
        self.places = places
        let kept = Library.WindowFile.read(places)
        preferred = kept?.assistant
        askEverything = kept?.askEverything ?? false
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
        if !offered.contains(kind ?? "") { kind = offered.first { $0 == preferred } ?? offered.first }
        keep(\.agent, state.agents.first { $0.id == id })
        let thread = state.threads.first { $0.agent == id }
        keep(\.rows, AssistantModel.rows(thread))
        turn = thread?.turns.last
        if ["working", "waiting"].contains(agent?.state) { active = clock() }
        // The drawer opens on a new problem: the person must see why nothing happened.
        if problem != nil, !told { drawer = true }
        told = problem != nil
        guard let before, !launching else { return }
        let answered = turn.map { $0.id != before.turn && $0.state != "working" } == true && !working
        if answered || id == nil || stopped || light == .error || agent?.alive == false {
            ended()
            self.before = nil
        }
    }

    private func keep<Value: Equatable>(_ property: ReferenceWritableKeyPath<AssistantModel, Value>, _ value: Value) {
        if self[keyPath: property] != value { self[keyPath: property] = value }
    }

    /// The kinds that can build, in the order they are offered (Extensions.swift).
    var builders: [String] { Registry.app.builders.map(\.kind) }

    var name: String { Registry.app.name(of: kind ?? preferred ?? builders.first ?? "") }

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

    /// What the capsule says when no builder is offered.
    var notice: String {
        let found = builders.filter { installed[$0] == true }
        if found.count == 1, let because = refused[found[0]] { return because }
        return found.isEmpty ? "No coding agent found." : "\(found.map(Registry.app.name).joined(separator: ", ")) can't build spaces."
    }

    /// Whether a space is being made from the blank page: the sidebar shows a "New Space" row meanwhile.
    var building: Bool { before != nil }

    var working: Bool { light == .working || light == .waiting }

    /// What Stop does while the agent works: it pauses the turn, or ends an agent that cannot pause mid-task.
    var stopHelp: String {
        agent?.can.interrupt == false && !launching ? "Stop ends \(name), which can't pause mid-task; your next message starts it again." : "Stop (⌘.)"
    }

    var light: Light {
        if failure != nil { return .error }
        guard let agent, !stopped else { return launching ? .working : .off }
        switch agent.state {
        case "working": return .working
        case "waiting": return .waiting
        case "error": return .error
        default: return agent.alive == false ? (agent.error == nil ? .off : .error) : .ready
        }
    }

    /// The status line above the capsule, only while it matters.
    var status: String? {
        if failure != nil { return "Couldn't reach \(name)." }
        switch light {
        case .working:
            guard let retry else { return "Working…" }
            return "\(name) can't reach its model (attempt \(retry)). It keeps trying."
        case .waiting: return "Waiting for you: answer in the \(agent?.waiting == "answer" ? "question" : "permission") window."
        default: break
        }
        if let ready { return "“\(ready.title)” is ready. Open" }
        if agent?.alive == false, !stopped, agent?.error == nil { return "\(name) stopped." }
        return unkept ? "Couldn't keep this space's journal: its activity is not saved." : nil
    }

    /// What the agent reported while it could not reach its model (Claude Code's `detail.apiRetry`): its last retry,
    /// or, with no attempt, its sign-in refused before any request.
    private var apiRetry: [String: JSONValue] {
        guard case .object(let retry)? = agent?.detail["apiRetry"] else { return [:] }
        return retry
    }

    /// The number of the agent's last retry in this turn, nil when it did not retry. Not "of how many": Claude Code
    /// says 10, but gives up after three in a row from a busy server (529, measured on 2.1.296).
    var retry: Int? {
        guard case .number(let attempt)? = apiRetry["attempt"] else { return nil }
        return Int(attempt)
    }

    /// Whether the last message failed because the model's server refused the agent's sign-in: signing in cures it.
    var signedOut: Bool {
        guard failure == nil, light == .error else { return false }
        var (status, error): (Int?, String?) = (nil, nil)
        if case .number(let number)? = apiRetry["errorStatus"] { status = Int(number) }
        if case .string(let kind)? = apiRetry["error"] { error = kind }
        return agent.flatMap { Registry.app.agent($0.kind) }?.refusesSignIn(status: status, error: error) ?? false
    }

    /// What went wrong with the last message, for the red row; nil when nothing did.
    var problem: String? {
        if let failure { return failure }
        guard light == .error, !stopped else { return nil }
        return agent?.error?.message
    }

    var placeholder: String {
        switch place {
        case .space(_, let space, _) where space == fromTemplate: return "Ask \(name) to make it yours: colors, sections, anything."
        case .space(let title, _, _): return "Ask \(name) to change \(title)…"
        case .blank: return "Describe the space you want…"
        case .templates: return "Ask \(name) about templates, or anything about something…"
        }
    }

    /// The drawer's first lines: where the agent works and how it asks, then how long a conversation lasts.
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
        guard !text.isEmpty, kind != nil else { return }
        if sentence == nil { draft = "" }
        fromTemplate = nil
        if place == .blank, before == nil {
            // The build is watched from its first message: the conversation shows what the agent does.
            (before, drawer) = ((Set(Spaces(root: places.spaces).list().map(\.name)), turn?.id), true)
        }
        deliver(AssistantModel.context(place, home: places.home.path) + "\n" + text)
    }

    /// Ask to Fix: only something's own words, the space's validated title and name and the codes.
    func fix(_ fault: Fault) {
        self.fault = nil
        deliver(AssistantModel.context(place, home: places.home.path) + "\n" + AssistantModel.fixing(fault))
    }

    func focus() {
        hidden = false
        focusing += 1
    }

    /// Stops the running turn, the agent staying for the next message; or, while the agent starts, ends its launch. An
    /// agent that cannot pause mid-task is ended: the conversation stays shown, and the next message starts it again.
    func stop() {
        if launching { return endLaunch() }
        guard let id, working else { return }
        if agent?.can.interrupt == false { return halt() }
        _ = try? engine.interrupt(id)
    }

    /// Ends the conversation: its agent stops, and the next message starts a new one.
    func newConversation() {
        halt()
        (id, agent, rows, failure, idled, last, stopped) = (nil, nil, [], nil, false, nil, false)
        (before, ready) = (nil, nil)
    }

    /// Relaunches, then sends the last message again.
    func tryAgain() {
        guard let last else { return }
        halt()
        id = nil
        deliver(last)
    }

    /// Copies the command that signs the builder in, in Terminal.
    func copyCommand() { copy(command) }

    /// Chooses the builder `kind`; a conversation running with another one ends, after the person said so.
    func choose(_ chosen: String) {
        guard chosen != kind, refused[chosen] == nil else { return }
        let switched = { [self] in
            newConversation()
            (kind, preferred) = (chosen, chosen)
            Library.WindowFile.update(places) { $0.assistant = chosen }
        }
        if id != nil, agent?.alive != false, !stopped {
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
        if draft.isEmpty, agent?.thread == nil, let last, let line = last.firstIndex(of: "\n") { draft = String(last[last.index(after: line)...]) }
        refresh()
    }

    /// Ask Before Every Change: from the next conversation on.
    func toggleAsking() {
        askEverything.toggle()
        Library.WindowFile.update(places) { [askEverything] in $0.askEverything = askEverything }
    }

    /// Stops the agent after `idleLimit` without a turn: a Claude Code process holds a few hundred MB.
    func checkIdle() {
        guard let agent, agent.alive == true, !stopped, !["working", "waiting"].contains(agent.state),
              clock().timeIntervalSince(active) >= AssistantModel.idleLimit else { return }
        halt()
        idled = true
    }

    /// The space to open by itself once the build asked from the blank page ended: the first new space listed since,
    /// while no other space is open. When one is, the new space is said `ready` instead, and nil returned.
    func appeared(_ entries: [Library.Entry], open: String?) -> String? {
        guard let before, let new = entries.first(where: { $0.isSpace && !before.spaces.contains($0.id) }) else { return nil }
        self.before = nil
        made.insert(new.id)
        if open == nil { return new.id }
        ready = new
        return nil
    }

    private func halt() {
        endLaunch()
        if let id, agent?.alive != false { engine.stopAll(within: 5, only: id) {} }
        stopped = true
    }

    private func endLaunch() { (launching, queued, launch) = (false, [], launch + 1) }

    /// Sends `message` to this conversation's agent; launches it first when there is none, once: what is written while
    /// it starts waits for it.
    private func deliver(_ message: String) {
        guard let kind else { return }
        (last, failure, active) = (message, nil, clock())
        if launching { return queued.append(message) }
        if let id, agent?.alive != false, !stopped {
            do { _ = try engine.deliver(message, to: id, when: "next") } catch { failure = error.sentence }
            return refresh()
        }
        (launching, queued) = (true, [message])
        let number = launch
        engine.lookFor(kind) { [weak self] in
            // A launch ended by Stop, New Conversation or a switch while the program was looked for never starts.
            guard let self, number == launch else { self?.refresh(); return }
            let messages = queued
            queued = []
            do {
                let id = try engine.launchAssistant(kind, folder: places.spaces.path, askEverything: askEverything, lent: lent(for: kind))
                (self.id, asking, stopped, idled) = (id, askEverything, false, false)
                for message in messages { _ = try engine.deliver(message, to: id, when: "next") }
            } catch { failure = error.sentence }
            // Only now: the launch changes the state, and a build watched must not see it ended with no agent yet.
            launching = false
            refresh()
        }
    }

    // MARK: Words

    /// Where the person is with `view` open: its title as its declaration gave it, else its name; the blank page for nil.
    static func place(_ view: SpaceView?) -> Place {
        view.map { .space(title: $0.title, name: $0.space.name, page: $0.space.page.path) } ?? .blank
    }

    /// The line something puts before each message, which the drawer strips: which space is open, by the title and
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
        "The space “\(clean(fault.title))” (\(fault.name)) has problems: \(fault.codes.joined(separator: ", ")). Run something check \(fault.name) and fix what it reports."
    }

    /// A message as the drawer shows it: its context line taken off, said as a caption ("about My agents").
    static func shown(_ text: String) -> (caption: String?, text: String) {
        guard text.hasPrefix("[something] ") else { return (nil, text) }
        let line = text.prefix { $0 != "\n" }, rest = String(text.dropFirst(line.count + 1))
        if line.hasSuffix("on the blank page.") { return ("on the blank page", rest) }
        if line.hasSuffix("on the templates.") { return ("on the templates", rest) }
        guard let open = line.range(of: "Open space: “"), let close = line.range(of: "” (", options: .backwards),
              open.upperBound <= close.lowerBound else { return (nil, rest) }
        return ("about " + line[open.upperBound..<close.lowerBound], rest)
    }

    /// The drawer's rows from the agent's thread: messages and tools, never thoughts.
    static func rows(_ thread: AgentThread?) -> [Row] {
        (thread?.turns ?? []).flatMap(\.items).compactMap { item in
            switch (item.kind, item.author) {
            case ("message", "person"):
                let shown = shown(item.text)
                return .mine(caption: shown.caption, text: shown.text)
            case ("message", _): return .reply(item.text)
            case ("tool", _), ("subagent", _): return tool(item)
            default: return nil
            }
        }
    }

    /// One tool in a few words: "Edited agents.html", "Read guide", "Ran" and the command.
    static func tool(_ item: Item) -> Row {
        let name = item.tool?.name ?? "tool", file = (item.text as NSString).lastPathComponent
        let after = item.decision?.outcome == "denied" ? " · denied" : item.tool?.status == "failed" ? " · failed" : ""
        if item.text.hasPrefix("something guide") { return .tool(symbol: "book", words: "Read guide" + after, command: nil) }
        // A command, code (Amp's, which calls something's tools), or a tool something lent (something_check), for which the
        // driver gives the command something ran.
        if name.hasPrefix("something_") || ["bash", "commandexecution", "execute", "shell_command", "code_exec"].contains(name.lowercased()) {
            return .tool(symbol: "terminal", words: after, command: item.text)
        }
        switch name.lowercased() {
        case "edit", "write", "multiedit", "notebookedit", "filechange", "apply_patch": return .tool(symbol: "pencil", words: "Edited \(file)" + after, command: nil)
        case "read": return .tool(symbol: "eye", words: "Read \(file)" + after, command: nil)
        default: return .tool(symbol: "wrench.and.screwdriver", words: "Used \(name)" + after, command: nil)
        }
    }
}
