// Info, docked at the window's right edge at full height, 320 points: the space narrows beside it, nothing hides under
// it. One panel holds Info or History (History.swift), swapped by `content` without a relayout; it opens and closes at
// once, the page laid out again a single time (SP10). Info is everything about the open space in one place, in three
// parts that follow what a space is (X5.1): Space (its file, its size and last change, Export, History),
// Your agents (its level, one control, Run's folder, its lasting rules with Revoke, and the agents its page shows now,
// each with its reading and what it offers: model, effort, mode, its commands, Continue in Terminal)
// and Assistant (its eyes, the agent and model in one chip, its last reply, Open Conversation); Move to Trash… waits
// quietly at the foot. A level chosen here is the person's answer: kept in the grants file, it reaches the open space
// at once as a `granted` event (X5.2). ✕ and ⌘I close it, and Esc while the focus is in it: an Esc of the whole window
// would take it from every page and field.
import Observation
import SomethingAgents
import SomethingCore
import SwiftUI

@Observable final class Info {
    /// What the docked panel holds.
    enum Content { case info, history }

    @ObservationIgnored let places: Places
    @ObservationIgnored let ask: Asking
    /// The open space's view, which hears of a new level at once and says which agents its page sees.
    @ObservationIgnored var current: () -> SpaceView? = { nil }
    /// Closes the panel: the window's.
    @ObservationIgnored var close: () -> Void = {}
    /// The clock the dates are said by; a test sets it.
    @ObservationIgnored var clock: () -> Date = Date.init
    /// Shows History in the panel: the window's.
    @ObservationIgnored var showHistory: () -> Void = {}
    /// Open Conversation: the window closes the panel and opens the assistant's card on its conversation.
    @ObservationIgnored var converse: () -> Void = {}
    /// Asks the person for Run's folder and gives it on; a test answers in its place.
    @ObservationIgnored var pick: (@escaping (String) -> Void) -> Void = Levels.chooseFolder
    /// Opens a command file in Terminal; a test sets it.
    @ObservationIgnored var terminal: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// The open space's versions, which History shows.
    let history: History
    var content = Content.info
    private(set) var space: Space?
    /// Its declared description: the line under its title.
    private(set) var about: String?
    /// The level in force; nil while it cannot be shown (no declaration in force) or its grants do not read.
    private(set) var level: Grant.Level?
    /// Where the agents it starts work, for Run.
    private(set) var folder: String?
    /// Its lasting rules, oldest first (Rules.swift).
    private(set) var rules: [Rule] = []
    /// Why the level cannot be shown: the grants file does not read.
    private(set) var problem: String?
    /// Its last change (the newest of a folder's files) and its weight; nil when unread.
    private(set) var changed: Date?
    private(set) var size: Size?
    /// The agents its page sees now, as it receives them; and the folders the Mac's agents work in, Run's choices.
    private(set) var shown: [AgentReading] = []
    private(set) var folders: [String] = []
    /// The launched agents leaving for Terminal, by id, from the click on: each goes once. Ids are not reused in a run.
    private(set) var moving: Set<String> = []
    /// Where the agents shown run; a test gives its own lineage.
    @ObservationIgnored var runs = RunsIn()
    /// The titles read so far, by `Rights.key`: a title outlives the turns a conversation drops, and a move.
    @ObservationIgnored private var titles: [String: String] = [:]

    init(places: Places, ask: Asking) {
        self.places = places
        self.ask = ask
        history = History(places: places)
        history.clock = { [weak self] in self?.clock() ?? Date() }
        history.current = { [weak self] in self?.open() }
        history.tell = { [weak self] in self?.ask.tell($0) }
    }

    /// Shows `space`, or nothing when no space is open. Read again at each change: it is a few small files.
    func show(_ space: Space?) {
        self.space = space
        history.show(space)
        (about, level, folder, problem, changed, size, rules) = (nil, nil, nil, nil, nil, nil, [])
        defer { refresh() }
        guard let space else { return }
        let declaration = Declaration.read(space, home: places.home, kinds: Registry.app.kinds).declaration
        about = declaration?.description
        if declaration != nil {
            do {
                let grant = try Grants(places.grants).read().spaces[space.name]
                (level, folder, rules) = (grant.map(Rights.level(of:)) ?? Grant.Level.none, grant?.folder, grant?.rules ?? [])
            } catch {
                problem = error.sentence
            }
        }
        // One walk of its files for both. They are read again at each opening; an edit while Info shows waits for
        // the hook that hears the space's files change (T13).
        let files = space.files().compactMap { try? $0.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) }
        changed = files.compactMap(\.contentModificationDate).max()
        size = Size(bytes: files.compactMap(\.fileSize).reduce(0, +), files: files.count)
    }

    /// Reads again which agents the open space's page sees and where the Mac's agents work: at each change of the
    /// state, while the panel shows. Only a change is set, so the panel is drawn again only then.
    func refresh() {
        let view = open()
        let visible = view.map { Bridge.visible($0) }, agents = visible?.agents ?? []
        let known = view.map { Levels.folders($0.engine.state) } ?? []
        let threads = Dictionary((visible?.threads ?? []).map { ($0.agent, $0) }) { first, _ in first }
        let readings = agents.map { AgentReading($0, thread: threads[$0.id], known: titles[Rights.key($0)], runs: runs) }
        for reading in readings where reading.named { titles[reading.key] = reading.title }
        runs.keep(agents)
        if readings != shown { shown = readings }
        if known != folders { folders = known }
    }

    /// The person chose `level` here, or for `other` in Settings › Agents: it becomes the space's grant at once, as on
    /// New Space, and the space, when open, hears it. Run takes `chosen`, else the folder in force, else the one its page
    /// declares when it is on this Mac, else asks for one; a folder not chosen changes nothing. Says a failure.
    func choose(_ level: Grant.Level, folder chosen: String? = nil, in other: Space? = nil) {
        guard let space = other ?? space, let declaration = Declaration.read(space, home: places.home, kinds: Registry.app.kinds).declaration else { return }
        let kept = other == nil ? self.folder : (try? Grants(places.grants).read())?.spaces[space.name]?.folder
        let folder = level == .run ? chosen ?? kept ?? Levels.onThisMac(declaration.folder, home: places.home) : nil
        if level == .run, folder == nil { return pick { [weak self] in self?.choose(.run, folder: $0, in: other) } }
        do {
            try Grants(places.grants).update {
                $0.spaces[space.name] = Rights.leveled(level, folder: folder, declaration: declaration, at: iso8601.string(from: clock()), after: $0.spaces[space.name])
            }
        } catch {
            ask.tell(error.sentence)
        }
        if let open = open(), open.space.name == space.name { open.regrant() }
        show(self.space)
    }

    /// Revoke, in Info or Settings: `rule` goes from the grant of the space `name` (the open one by default), the next
    /// request for its command asks again, and Info shows it gone. Says a failure.
    func revoke(_ rule: Rule, in name: String? = nil) {
        guard let name = name ?? space?.name else { return }
        do { try Rules.revoke(rule, in: name, Grants(places.grants)) } catch { ask.tell(error.sentence) }
        show(space)
    }

    /// The person changed what `agent` runs with, in Info. A mode that makes it ask less waits for their click, as a
    /// page's does; the rest reaches it at once or from its next turn. Says a failure.
    func set(_ agent: Agent, model: String? = nil, mode: String? = nil, effort: String? = nil) {
        guard let view = open() else { return }
        do {
            if let mode, try !view.confirms(mode: mode, kind: agent.kind, folder: agent.folder) { return }
            _ = try view.set(agent, model: model, mode: mode, effort: effort)
        } catch { ask.tell(error.sentence) }
    }

    /// Sends the agent's own command `name`, held until its turn ends. Says a failure.
    func command(_ name: String, to agent: Agent) {
        do { _ = try open()?.deliver("/" + name, to: agent, when: "next") } catch { ask.tell(error.sentence) }
    }

    /// The words that continue `agent`'s conversation in Terminal, when it has one and its kind has a proven way.
    func terminalWords(_ reading: AgentReading) -> [String]? {
        guard reading.agent.origin == "launched", reading.talked, let thread = reading.agent.thread else { return nil }
        return Registry.app.agent(reading.agent.kind)?.terminal?(thread)
    }

    /// Continue in Terminal, once for an agent: something stops holding the conversation, then Terminal takes it, in the
    /// agent's folder, and the agent leaves the launched ones at once. It did not end: its row is now the conversation
    /// seen elsewhere, still in the sight of the space that launched it, while nothing shows it as Ended. A failure says so and keeps the
    /// stopped agent, so the person can try again.
    func continueInTerminal(_ reading: AgentReading) {
        let agent = reading.agent
        guard let view = open(), let words = terminalWords(reading), let folder = agent.folder, let thread = agent.thread,
              moving.insert(agent.id).inserted else { return }
        view.engine.stopAll(within: 5, only: agent.id) { [self] in
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("something-\(UUID().uuidString).command")
            do {
                try Data(Info.script(words, in: folder).utf8).write(to: file)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
                terminal(file)
                view.launches.moved(agent.id, to: Engine.seenID(agent.kind, thread: thread))
                view.engine.forget(agent.id)
            } catch {
                moving.remove(agent.id)
                ask.tell(error.sentence)
            }
        }
    }

    /// A command file that removes itself, then continues in `folder`; each word quoted, so none is read by the shell.
    static func script(_ words: [String], in folder: String) -> String {
        let quoted = ([folder] + words).map { "'" + $0.replacingOccurrences(of: "'", with: #"'\''"#) + "'" }
        return "#!/bin/sh\nrm -- \"$0\"\ncd \(quoted[0]) && exec \(quoted.dropFirst().joined(separator: " "))\n"
    }

    /// "Today", "Yesterday", "9 Oct", or "9 Oct 2025" in another year; with `time`, "Today, 18:12".
    static func day(_ date: Date, now: Date, time: Bool = false, calendar: Calendar = .current) -> String {
        let format = DateFormatter()
        (format.locale, format.calendar, format.timeZone) = (Locale(identifier: "en_US_POSIX"), calendar, calendar.timeZone)
        let clock = { format.dateFormat = "HH:mm"; return ", " + format.string(from: date) }
        if calendar.isDate(date, inSameDayAs: now) { return "Today" + (time ? clock() : "") }
        if let before = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: before) {
            return "Yesterday" + (time ? clock() : "")
        }
        format.dateFormat = calendar.isDate(date, equalTo: now, toGranularity: .year) ? "d MMM" : "d MMM yyyy"
        return format.string(from: date) + (time ? clock() : "")
    }

    /// "14 KB · one file", or "48 KB · 5 files" for a folder space; then its last change when known, "changed today,
    /// 18:04".
    static func weight(_ size: Size, form: Space.Form, changed: Date?, now: Date) -> String {
        Size.words(size.bytes) + " · " + (form == .file ? "one file" : "\(size.files) file\(size.files == 1 ? "" : "s")")
            + (changed.map { " · changed " + day($0, now: now, time: true).inSentence } ?? "")
    }

    /// The open space's view, when it is the one shown here.
    private func open() -> SpaceView? { current().flatMap { $0.space.name == space?.name ? $0 : nil } }
}

/// The panel's controller: Esc closes it while the focus is in it, ↑ ↓ move History's choice, and Space held shows it
/// over the page.
final class InfoController: NSHostingController<InspectorView> {
    override func cancelOperation(_ sender: Any?) { rootView.info.close() }
    override func moveUp(_ sender: Any?) { if rootView.info.content == .history { rootView.info.history.move(-1) } }
    override func moveDown(_ sender: Any?) { if rootView.info.content == .history { rootView.info.history.move(1) } }

    override func keyDown(with event: NSEvent) {
        switch (rootView.info.content, event.keyCode) {
        case (.history, 126): moveUp(nil)
        case (.history, 125): moveDown(nil)
        case (.history, 49): if !event.isARepeat { hold() }
        case (_, 53): cancelOperation(nil) // Escape, which no field of the panel took
        default: super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard rootView.info.content == .history, event.keyCode == 49 else { return super.keyUp(with: event) }
        release()
    }

    /// What ends the hold wherever the focus went meanwhile: Space released in any window (the page took a click),
    /// the window losing the keys, or the app losing the focus (⌘-Tab).
    private var keyUp: Any?, resigned: [NSObjectProtocol] = []

    /// Space went down in History: the chosen version is shown over the page until the key comes up, wherever it does.
    private func hold() {
        rootView.info.history.compare(true)
        guard keyUp == nil, rootView.info.history.comparing else { return }
        keyUp = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard event.keyCode == 49, let self else { return event }
            // Taken while the version still shows: the page never gets a Space it did not see go down.
            let shown = rootView.info.history.comparing
            release()
            return shown ? nil : event
        }
        let center = NotificationCenter.default
        resigned = [(NSWindow.didResignKeyNotification, view.window as Any?), (NSApplication.didResignActiveNotification, nil)].map { name, object in
            center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.release() } }
        }
    }

    /// The hold ended: the page as it is now.
    private func release() {
        if let keyUp { NSEvent.removeMonitor(keyUp) }
        resigned.forEach(NotificationCenter.default.removeObserver)
        (keyUp, resigned) = (nil, [])
        rootView.info.history.compare(false)
    }
}

extension Shell {
    /// Whether the docked panel shows.
    var infoShown: Bool { !inspector.isCollapsed }

    /// Opens Info, or closes the panel, at once: the page is laid out again a single time, never through an animation.
    func showInfo(_ shown: Bool) {
        if shown { info.content = .info }
        if shown { HintBubble.close(in: layer, only: .info) }
        info.history.closed()
        // Keys that were in the panel go back to the page as it closes, or to point mode's overlay while it is on.
        let panel = inspector.viewController.view
        if !shown, let held = window.firstResponder as? NSView, held.isDescendant(of: panel), let space {
            window.makeFirstResponder(space.pointer ?? space.web)
        }
        inspector.isCollapsed = !shown
        (controls[Shell.info] as? ToolButton)?.pressed = shown
        titleLine.held = shown && info.content == .info
    }

    /// Shows History in the panel, in Info's place, while a space is open, with the keys: ↑ ↓, Space and Esc are
    /// History's at once. Info's button is not pressed for it.
    func showHistory() {
        guard space != nil else { return }
        if info.content != .history || inspector.isCollapsed { info.history.opened() }
        info.content = .history
        inspector.isCollapsed = false
        (controls[Shell.info] as? ToolButton)?.pressed = false
        titleLine.held = false
        window.makeFirstResponder(inspector.viewController.view)
    }

    /// Info's Open Conversation: the panel closes, the assistant's card opens on its conversation, its field ready.
    func converse() {
        showInfo(false)
        assistant.threadShown = true
        assistant.focus()
    }

    /// ⌘I and the toolbar's Info: opens Info while a space is open (in History's place when it shows), else closes
    /// the panel.
    func toggleInfo(spaceOpen: Bool) { showInfo(!(infoShown && info.content == .info) && spaceOpen) }
}

struct InspectorView: View {
    @Bindable var info: Info
    let library: Library
    @Bindable var assistant: AssistantModel

    var body: some View {
        Group {
            if let space = info.space {
                let title = library.entry(space.name)?.title ?? space.name
                VStack(spacing: 0) {
                    // The toolbar's lower edge goes on over the panel.
                    Rectangle().fill(Look.Token.line.ui).frame(height: 1)
                    if info.content == .history {
                        HistoryView(history: info.history, title: title, close: info.close)
                    } else {
                        DockHeader(title: title, sub: info.about ?? "", close: ("Close Info", info.close), titleSize: 19, lines: 3)
                        details(space)
                    }
                }
            } else {
                Color.clear
            }
        }
        .font(Look.medium.font.ui)
        .foregroundStyle(Look.Token.ink.ui)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Look.Token.bg.ui)
        .overlay(alignment: .leading) { Rectangle().fill(Look.Token.line.ui).frame(width: 1) }
    }

    /// Info's three parts and its foot, scrolled.
    private func details(_ space: Space) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                part("Space") { file(space) }
                part("Your agents") { agents }
                if assistant.place.space == space.name { part("Assistant") { yours } }
                Button {
                    if let entry = library.entry(space.name) { library.trashing(entry) }
                } label: {
                    Text("Move to Trash…").font(Look.font(.ui, size: 11.5).ui).foregroundStyle(Look.Token.ink3.ui).padding(2).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(Keys.tooltip("trash", "Move to Trash…"))
                .padding(EdgeInsets(top: 10, leading: 14, bottom: 16, trailing: 16)).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .scrollIndicators(.never)
    }

    /// Space: where its file is, with Show in Finder; its weight and last change; Export and History.
    private func file(_ space: Space) -> some View {
        let path = Words.path(space.location.path, home: info.places.home.path)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(path).font(Look.font(.code, size: 11).ui).foregroundStyle(Look.Token.ink2.ui).lineLimit(1).truncationMode(.head)
                    .padding(.horizontal, 8).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Look.Token.sunk.ui, in: RoundedRectangle(cornerRadius: 7)).help(space.location.path)
                    .accessibilityLabel("Its file: \(path)")
                Button { library.showInFinder(space.name) } label: {
                    Image(systemName: "finder").font(.system(size: 12)).foregroundStyle(Look.Token.ink2.ui).frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(Keys.tooltip("finder", "Show in Finder")).accessibilityLabel("Show in Finder")
            }
            if let size = info.size {
                Text(Info.weight(size, form: space.form, changed: info.changed, now: info.clock())).foot()
            }
            HStack(spacing: 8) {
                wide("Export…", "square.and.arrow.up") { library.export(space.name) }.help(Keys.tooltip("export", "Export to Downloads"))
                wide("History", "clock") { info.showHistory() }
            }
        }
    }

    /// Your agents: the level, Run's folder, the agents the page shows now, and what a level never covers.
    @ViewBuilder private var agents: some View {
        if let problem = info.problem {
            Text(problem).foot()
        } else if let level = info.level {
            LevelPicker(level: Binding(get: { level }, set: { info.choose($0) }), wide: true)
            Text(level.sentence).font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink2.ui).fixedSize(horizontal: false, vertical: true)
            if level == .run {
                HStack(spacing: 8) {
                    Text("Starts them in").font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink2.ui)
                    Spacer(minLength: 0)
                    FolderChip(folder: info.folder, folders: info.folders, home: info.places.home.path) { info.choose(.run, folder: $0) }
                }
                Levels.runNote
            }
            if level == .run || !info.rules.isEmpty { always }
            if level != .none, !info.shown.isEmpty { now }
            Levels.note(Levels.sheetFine)
        } else {
            Text("It can’t be shown now, so it shows no agent.").foot()
        }
    }

    /// Always for this space: each lasting rule, its agent, its command and its folder, with Revoke; or how one is made.
    private var always: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Always for this space").font(Look.font(.ui, size: 11.5, weight: .semibold).ui).foregroundStyle(Look.Token.ink3.ui)
                .accessibilityAddTraits(.isHeader)
            if info.rules.isEmpty {
                Text("None yet. Tick “Always for this space” when an agent asks.").foot()
            }
            ForEach(info.rules, id: \.self) { rule in
                let name = Registry.app.name(of: rule.kind), folder = Words.path(rule.folder, home: info.places.home.path)
                HStack(spacing: 8) {
                    Monogram(name: name)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rule.command).font(Look.font(.code, size: 11.5).ui).foregroundStyle(Look.Token.ink.ui).lineLimit(2)
                        Text("in " + folder).font(Look.font(.code, size: 10.5).ui).foregroundStyle(Look.Token.ink3.ui).lineLimit(1).truncationMode(.head)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore).accessibilityLabel("\(name): \(rule.command), in \(folder)")
                    Button("Revoke") { info.revoke(rule) }.buttonStyle(Secondary(height: 26, leading: 9, trailing: 9))
                        .font(Look.font(.ui, size: 12, weight: .medium).ui).accessibilityLabel("Revoke \(rule.command)")
                }
                .padding(.horizontal, 8).padding(.vertical, 7)
                .boxed(RoundedRectangle(cornerRadius: 9), Look.Token.sunk.ui, ring: Look.Token.line.ui)
            }
        }
        .padding(.top, 2)
    }

    /// The agents the page shows now: who, what it does, where.
    private var now: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(info.shown, id: \.id) { reading in
                VStack(alignment: .leading, spacing: 5) {
                    row(reading)
                    controls(reading)
                }
            }
        }
        .padding(4)
        .boxed(RoundedRectangle(cornerRadius: 9), Look.Token.bg2.ui, ring: Look.Token.line.ui)
        .accessibilityElement(children: .contain).accessibilityLabel("The agents it shows now")
    }

    /// One agent: its title and state word; under them its program, its folder and where it runs.
    private func row(_ reading: AgentReading) -> some View {
        let folder = reading.folder.map { Words.path($0, home: info.places.home.path) }
        let under = [reading.named ? reading.program : nil, folder, reading.tag].compactMap { $0 }.joined(separator: " · ")
        return HStack(alignment: .center, spacing: 8) {
            Monogram(name: reading.program)
            VStack(alignment: .leading, spacing: 1) {
                (Text(reading.title).font(Look.font(.ui, size: 12, weight: .semibold).ui).foregroundColor(Look.Token.ink.ui) + Text(" " + reading.word))
                    .font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink2.ui).fixedSize(horizontal: false, vertical: true)
                Text(under).font(Look.font(.code, size: 10.5).ui).foregroundStyle(Look.Token.ink3.ui).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore).accessibilityLabel([reading.title, reading.word, under].joined(separator: ", "))
    }

    /// What the person can change of an agent, as it lists it; what it cannot do says why. Nothing for one only seen.
    @ViewBuilder private func controls(_ reading: AgentReading) -> some View {
        let agent = reading.agent
        if agent.origin == "launched", agent.alive != false, agent.can.send {
            setting("Model", agent.options.model, agent.model, agent.can.model, agent.because["model"]) { info.set(agent, model: $0) }
            setting("Effort", agent.options.effort, agent.effort, agent.can.effort, agent.because["effort"]) { info.set(agent, effort: $0) }
            setting("Mode", agent.options.mode, agent.mode, agent.can.mode, agent.because["mode"]) { info.set(agent, mode: $0) }
            setting("Command", agent.commands, nil, true, nil) { info.command($0, to: agent) }
        }
        if info.terminalWords(reading) != nil {
            let busy = agent.alive != false && ["working", "waiting"].contains(agent.state), moving = info.moving.contains(agent.id)
            wide("Continue in Terminal", "terminal") { info.continueInTerminal(reading) }.disabled(busy || moving)
                .help(moving ? "It is moving to Terminal." : busy ? "It can continue in Terminal once this turn ends." : "something stops this agent, and Terminal continues its conversation.")
                .padding(.horizontal, 6)
        }
    }

    /// One line of an agent's settings: a menu of what it lists, else why not; nothing when neither is known.
    @ViewBuilder private func setting(_ title: String, _ list: [Option]?, _ chosen: String?, _ can: Bool, _ why: String?,
                                      _ run: @escaping (String) -> Void) -> some View {
        if can, let list, !list.isEmpty {
            HStack(spacing: 8) {
                Text(title).font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink2.ui)
                Spacer(minLength: 0)
                Menu(list.first { $0.value == chosen }?.label ?? chosen ?? "Choose…") {
                    ForEach(list, id: \.value) { option in Button(option.label) { run(option.value) } }
                }
                .menuStyle(.borderlessButton).fixedSize().font(Look.font(.ui, size: 12).ui).accessibilityLabel(title)
            }
            .padding(.horizontal, 6)
        } else if let why {
            Text("\(title): \(why)").foot().padding(.horizontal, 6)
        }
    }

    /// Assistant: its eyes, the agent and model in one chip, its last reply, Open Conversation.
    private var yours: some View {
        let state = assistant.presence.state
        let last = assistant.rows.last { $0.reply != nil }?.reply.map { $0.split(whereSeparator: \.isNewline).joined(separator: " ") }
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                PageSign(state: state, side: 22, lands: false, motion: library.preferences.motion)
                    .accessibilityElement().accessibilityLabel("Its assistant: \(state.word)")
                AgentModelChip(model: assistant)
            }
            if let last {
                Text("“\(last.count > 110 ? String(last.prefix(108)) + "…" : last)”").font(Look.font(.voice, size: 12).ui).lineSpacing(3)
                    .foregroundStyle(Look.Token.ink2.ui).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Its last reply: \(last)")
            }
            Button(action: info.converse) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left").font(.system(size: 11)).foregroundStyle(Look.Token.ink2.ui)
                    Text("Open Conversation").font(Look.font(.ui, size: 12.5, weight: .medium).ui)
                    Text(Keys.shown("ask")).font(Look.font(.ui, size: 10, weight: .medium).ui).foregroundStyle(Look.Token.ink3.ui)
                }
            }
            .buttonStyle(Secondary(height: 30, leading: 10, trailing: 10)).fixedSize()
            .accessibilityLabel("Open Conversation")
        }
    }

    /// A part of the panel, above a line: its title in small capitals, then its content.
    private func part(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased()).font(Look.font(.ui, size: 10.5, weight: .semibold).ui).kerning(0.525)
                .foregroundStyle(Look.Token.ink3.ui).accessibilityAddTraits(.isHeader).accessibilityLabel(title)
            content()
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }
    }

    /// One of two buttons sharing a row, each as wide as the other.
    private func wide(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11.5)).foregroundStyle(Look.Token.ink2.ui)
                Text(title).font(Look.font(.ui, size: 12.5, weight: .medium).ui)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(Secondary(height: 30))
    }
}

/// The panel's header, Info's and History's: its title, a line under it (none when empty; Info's description wraps on
/// up to `lines`), and ✕ (`close`: its label and action).
struct DockHeader: View {
    let title: String, sub: String
    let close: (label: String, run: () -> Void)
    var titleSize: CGFloat = 17, lines = 1

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Look.font(.title, size: titleSize, weight: .semibold).ui).kerning(-0.02 * titleSize).accessibilityAddTraits(.isHeader)
                if !sub.isEmpty {
                    Text(sub).font(Look.small.font.ui).foregroundStyle((lines > 1 ? Look.Token.ink2 : .ink3).ui).lineLimit(lines)
                        .fixedSize(horizontal: false, vertical: lines > 1)
                }
            }
            .padding(.top, 1)
            Spacer(minLength: 0)
            Button(action: close.run) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Look.Token.ink2.ui)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(Keys.tooltip("insp", "Close")).accessibilityLabel(close.label)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 11, trailing: 12))
        .overlay(alignment: .bottom) { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }
    }
}

private extension View {
    /// The mockup's small foot under a part: 11.5 in ink3.
    func foot() -> some View {
        font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui).fixedSize(horizontal: false, vertical: true)
    }
}

private extension String {
    /// A day said inside a sentence: "today", "yesterday"; a date stays as it is.
    var inSentence: String { hasPrefix("Today") || hasPrefix("Yesterday") ? prefix(1).lowercased() + dropFirst() : self }
}
