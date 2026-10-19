// The person's assistant as the window shows it (plan B.3): the coding agent that builds spaces with them in
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

    /// The kinds that can build, in the order they are offered: by how much each asks before acting.
    static let builders = ["claude", "codex", "opencode", "pi"]
    /// Why an installed kind is not offered. Trial T-1 (S3): inside Codex's sandbox `something check` finds no window
    /// server, so it would ask to run each check outside it, more windows than plan A.2 #6 allows.
    static let cannotBuild = ["codex": "can't build spaces yet: its sandbox blocks something check"]
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

    var place = Place.blank
    var draft = ""
    var drawer = false
    /// Whether ⌘J hid the whole assistant, in full screen.
    var hidden = false
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
    /// The spaces there were when the person asked from the blank page: the first new one opens by itself.
    private(set) var before: Set<String>?
    @ObservationIgnored private var preferred: String?
    @ObservationIgnored private var active = Date()
    @ObservationIgnored private var told = false
    @ObservationIgnored private var timer: Timer?

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
    /// at each change of the state.
    func refresh() {
        let state = engine.state
        installed = state.kinds.filter { AssistantModel.builders.contains($0.key) }.compactMapValues(\.installed)
        notes = state.kinds.compactMapValues(\.note)
        let offered = AssistantModel.builders.filter { installed[$0] == true && AssistantModel.cannotBuild[$0] == nil }
        if !offered.contains(kind ?? "") { kind = offered.first { $0 == preferred } ?? offered.first }
        agent = state.agents.first { $0.id == id }
        rows = AssistantModel.rows(state.threads.first { $0.agent == id })
        if ["working", "waiting"].contains(agent?.state) { active = clock() }
        // The drawer opens on a new problem: the person must see why nothing happened.
        if problem != nil, !told { drawer = true }
        told = problem != nil
    }

    var name: String { Programs.name(of: kind ?? preferred ?? "claude") }

    /// Whether every builder was looked for and none can build.
    var noAgent: Bool { kind == nil && !installed.isEmpty }

    /// What the capsule says when no builder is offered.
    var notice: String {
        let found = AssistantModel.builders.filter { installed[$0] == true }
        return found.isEmpty ? "No coding agent found." : "\(found.map(Programs.name).joined(separator: ", ")) can't build spaces yet."
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
        case .working: return "Working…"
        case .waiting: return "Waiting for you: answer in the \(agent?.waiting == "answer" ? "question" : "permission") window."
        default: break
        }
        if agent?.alive == false, !stopped, agent?.error == nil { return "\(name) stopped." }
        return unkept ? "Couldn't keep this space's journal: its activity is not saved." : nil
    }

    /// What went wrong with the last message, for the red row; nil when nothing did.
    var problem: String? {
        if let failure { return failure }
        guard light == .error, !stopped else { return nil }
        return agent?.error?.message
    }

    var placeholder: String {
        switch place {
        case .space(let title, _, _): return "Ask \(name) to change \(title)…"
        case .blank: return "Describe the space you want…"
        case .templates: return "Ask \(name) about templates, or anything about something…"
        }
    }

    /// The drawer's first lines: where the agent works and how it asks, then how long a conversation lasts.
    var firstLines: [String] {
        let folder = Words.path(places.spaces.path, home: places.home.path)
        let how = switch kind {
        case "opencode": "OpenCode works in \(folder). It asks as your own OpenCode settings say."
        case "pi": "pi works in \(folder). pi never asks: it can run any command on your Mac."
        default: (id == nil ? askEverything : asking) ? "\(name) works in \(folder). It asks you before every change."
            : "\(name) works in \(folder). It may change your spaces and run something's own commands there without asking. Anything else asks you."
        }
        return [how, "A new conversation starts each time something starts."]
            + (idled ? ["\(name) was stopped to save memory. Your next message starts it again."] : [])
    }

    /// The builders found, as the agent menus list them.
    var entries: [Entry] {
        AssistantModel.builders.filter { installed[$0] == true }.map { kind in
            let because = AssistantModel.cannotBuild[kind] ?? (kind == "pi" ? "never asks before acting" : nil)
            let title = [Programs.name(of: kind), because].compactMap { $0 }.joined(separator: " · ") + (notes[kind] == nil ? "" : " ⚠")
            return Entry(id: kind, title: title, checked: kind == self.kind, enabled: AssistantModel.cannotBuild[kind] == nil, note: notes[kind])
        }
    }

    /// Whether Ask Before Every Change means anything for the chosen builder: only Claude Code and Codex are pre-allowed.
    var canAskEverything: Bool { kind == "claude" || kind == "codex" }

    // MARK: What the person does

    /// Sends the draft, with the context line, launching the agent first when this conversation has none.
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, kind != nil else { return }
        draft = ""
        if place == .blank { before = Set(Spaces(root: places.spaces).list().map(\.name)) }
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

    /// Stops the running turn; the agent stays for the next message.
    func stop() {
        if let id, light == .working || light == .waiting { _ = try? engine.interrupt(id) }
    }

    /// Ends the conversation: its agent stops, and the next message starts a new one.
    func newConversation() {
        halt()
        (id, agent, rows, failure, idled, last, stopped) = (nil, nil, [], nil, false, nil, false)
    }

    /// Relaunches, then sends the last message again.
    func tryAgain() {
        guard let last else { return }
        halt()
        id = nil
        deliver(last)
    }

    /// Copies the command that signs the builder in, in Terminal.
    func copyCommand() { copy(kind ?? "claude") }

    /// Chooses the builder `kind`; a conversation running with another one ends, after the person said so.
    func choose(_ chosen: String) {
        guard chosen != kind, AssistantModel.cannotBuild[chosen] == nil else { return }
        let keep = { [self] in
            if id != nil { newConversation() }
            (kind, preferred) = (chosen, chosen)
            Library.WindowFile.update(places) { $0.assistant = chosen }
        }
        if id != nil, agent?.alive != false, !stopped {
            confirmSwitch(name, Programs.name(of: chosen), keep)
        } else {
            keep()
        }
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

    /// The space to open by itself: the first new space listed since the person asked from the blank page, while no
    /// other space is open.
    func appeared(_ entries: [Library.Entry], open: String?) -> String? {
        guard let before, open == nil, let new = entries.first(where: { $0.isSpace && !before.contains($0.id) }) else { return nil }
        self.before = nil
        return new.id
    }

    private func halt() {
        if let id, agent?.alive != false { engine.stopAll(within: 5, only: id) {} }
        stopped = true
    }

    private func deliver(_ message: String) {
        guard let kind else { return }
        (last, failure, active) = (message, nil, clock())
        if let id, agent?.alive != false, !stopped {
            do { _ = try engine.deliver(message, to: id, when: "next") } catch { failure = error.sentence }
            return refresh()
        }
        launching = true
        engine.lookFor(kind) { [weak self] in
            guard let self else { return }
            launching = false
            do {
                let id = try engine.launchAssistant(kind, folder: places.spaces.path, askEverything: askEverything)
                (self.id, asking, stopped, idled) = (id, askEverything, false, false)
                _ = try engine.deliver(message, to: id, when: "next")
            } catch { failure = error.sentence }
            refresh()
        }
    }

    // MARK: Words

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

    /// Ask to Fix's words (plan A.1).
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
        switch name.lowercased() {
        case "edit", "write", "multiedit", "notebookedit", "filechange": return .tool(symbol: "pencil", words: "Edited \(file)" + after, command: nil)
        case "read": return .tool(symbol: "eye", words: "Read \(file)" + after, command: nil)
        case "bash", "commandexecution", "execute": return .tool(symbol: "terminal", words: after, command: item.text)
        default: return .tool(symbol: "wrench.and.screwdriver", words: "Used \(name)" + after, command: nil)
        }
    }
}
