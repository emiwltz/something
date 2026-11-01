// The panel, docked at the window's right edge at full height, 320 points: the space narrows beside it, nothing hides
// under it. One panel with three tabs, Agents (AgentsPanel.swift), Info and History (History.swift), swapped by `content`
// without a relayout; it opens and closes at once, the page laid out again a single time (SP10). It is the person's: it
// works at every level, whatever the page draws, and no page can see it, draw it or press it. Info holds the space's
// file, its size and last change, Export, its memory, its versions and its assistant; Move to Trash… waits quietly at
// the foot. A level chosen in the panel's sentence is the person's answer: kept in the grants file, it reaches the open
// space at once as a `granted` event. ✕ and ⌘I close it, and Esc while the focus is in it: an Esc of the whole window
// would take it from every page and field.
import Observation
import SomethingAgents
import SomethingCore
import SwiftUI

@Observable final class Info {
    /// The panel's tabs.
    enum Content: String, CaseIterable { case agents = "Agents", info = "Info", history = "History" }

    @ObservationIgnored let places: Places
    @ObservationIgnored let ask: Asking
    /// The open space's view, which hears of a new level at once and says which agents its page sees.
    @ObservationIgnored var current: () -> SpaceView? = { nil }
    /// Closes the panel: the window's.
    @ObservationIgnored var close: () -> Void = {}
    /// The clock the dates are said by; a test sets it.
    @ObservationIgnored var clock: () -> Date = Date.init
    /// Shows a tab of the panel: the window's.
    @ObservationIgnored var select: (Content) -> Void = { _ in }
    /// Hears how many agents the page sees and what their eyes say, at each reading: the window's panel button.
    @ObservationIgnored var counted: (Int, [Sign.State]) -> Void = { _, _ in }
    /// Whether the panel shows: closed, only what its button counts is read.
    @ObservationIgnored var showing: () -> Bool = { true }
    /// Asks the person for Run's folder and gives it on; a test answers in its place.
    @ObservationIgnored var pick: (@escaping (String) -> Void) -> Void = Levels.chooseFolder
    /// Opens a command file in Terminal; a test sets it.
    @ObservationIgnored var terminal: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// The open space's versions, which History shows.
    let history: History
    var content = Content.agents
    private(set) var space: Space?
    /// Its declared description: the line under its title.
    private(set) var about: String?
    /// The level in force; nil while it cannot be shown (no declaration in force) or its grants do not read.
    private(set) var level: Grant.Level?
    /// Where the agents it starts work, for Run, and the one its page declares when it is on this Mac.
    private(set) var folder: String?
    private var declared: String?
    /// Which agents it shows, the one agent it may start, and the kinds its page declares it starts.
    private var scope: Scope?
    private var start: Grant.Start?
    private(set) var kinds: [String] = []
    /// The sentence while Run waits for its folder: nothing is granted until then.
    private var draft: LevelChoice?
    /// Its lasting rules, oldest first (Rules.swift).
    private(set) var rules: [Rule] = []
    /// Why the level cannot be shown: the grants file does not read.
    private(set) var problem: String?
    /// Its last change (the newest of a folder's files) and its weight; nil when unread.
    private(set) var changed: Date?
    private(set) var size: Size?
    /// The agents its page sees now, and the others on this Mac, assistants apart; and the folders the Mac's agents work
    /// in, Run's choices.
    private(set) var shown: [AgentReading] = []
    private(set) var others: [AgentReading] = []
    private(set) var folders: [String] = []
    /// How many assistants its page sees: their own row says them, their state is all it gets.
    private(set) var seenAssistants = 0
    /// The warning that replaces the sentence's lock line, when an agent in reach never asks.
    private(set) var warning: String?
    /// The launched agents leaving for Terminal, by id, from the click on: each goes once. Ids are not reused in a run.
    private(set) var moving: Set<String> = []
    /// Whether Look Again is at work; what it found; and the rows of what it found, by key, for their halo.
    private(set) var looking = false
    private(set) var said: String?
    private(set) var fresh: Set<String> = []
    /// Looks at the Mac now, then calls back; a test gives what is found.
    @ObservationIgnored var look: (Engine, @escaping (Bool) -> Void) -> Void = { $0.lookNow(then: $1) }
    /// The row opened in place and the row under the pointer, by id; and Others, folded or not, once the person chose.
    var opened: String?
    var hovered: String?
    var othersOpen: Bool?
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
        if space?.name != self.space?.name { (opened, othersOpen, said, fresh, looking) = (nil, nil, nil, [], false) }
        self.space = space
        history.show(space)
        (about, level, folder, problem, changed, size, rules) = (nil, nil, nil, nil, nil, nil, [])
        (declared, scope, start, kinds, draft) = (nil, nil, nil, [], nil)
        defer { refresh() }
        guard let space else { return }
        let reading = Declaration.read(space, home: places.home, kinds: Registry.app.kinds), declaration = reading.declaration
        about = declaration?.description
        if let declaration {
            kinds = declaration.rights.filter { $0.hasPrefix("launch:") }.map { String($0.dropFirst("launch:".count)) }
            declared = Levels.onThisMac(declaration.folder, home: places.home)
            do {
                let grant = try Grants(places.grants).read().spaces[space.name]
                (level, folder, rules, start) = (grant.map(Rights.level(of:)) ?? Grant.Level.none, grant?.folder, grant?.rules ?? [], grant?.start)
                scope = Rights.granted(reading, grant, limits: [:], home: places.home).agents
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

    /// Reads again the Mac's agents, which of them the open space's page sees, and where they work: at each change of
    /// the state, as the panel's button counts them even while the panel is closed. The panel is the person's, so it reads
    /// the state as it is; only which agents the page sees comes through the page's own sight. Only a change is set, so
    /// the panel is drawn again only then.
    func refresh() {
        let view = open(), state = view?.engine.state
        let sees = Set(view.map { Bridge.visible($0).agents.map(\.id) } ?? []), mine = view?.engine.assistants ?? []
        let wanted = showing()
        let agents = (state?.agents ?? []).filter { !mine.contains($0.id) && (wanted || sees.contains($0.id)) }
        let threads = Dictionary((state?.threads ?? []).map { ($0.agent, $0) }) { first, _ in first }
        let readings = agents.map { AgentReading($0, thread: threads[$0.id], known: titles[Rights.key($0)], runs: runs) }
        for reading in readings where reading.named { titles[reading.key] = reading.title }
        runs.keep(agents)
        let seen = readings.filter { sees.contains($0.id) }, rest = readings.filter { !sees.contains($0.id) }
        // The list holds only what the page sees: its reach is that list, whatever the sentence's scope.
        let warns = Levels.warning(choice, agents: seen.map(\.agent), threads: seen.compactMap { threads[$0.id] }, reach: .all)
        let known = state.map(Levels.folders) ?? []
        if seen != shown { shown = seen }
        if rest != others { others = rest }
        if warns != warning { warning = warns }
        if sees.intersection(mine).count != seenAssistants { seenAssistants = sees.intersection(mine).count }
        if known != folders { folders = known }
        counted(seen.count, seen.map(\.eyes))
    }

    /// The sentence as it stands: Run waiting for its folder, else the grant in force. The folder is kept ready under Run,
    /// so that choosing Run opens no menu when it is already known.
    var choice: LevelChoice {
        draft ?? LevelChoice(level: level ?? .none, scope: scope, start: start ?? (kinds.count == 1 ? Grant.Start(kind: kinds[0]) : nil),
                             folder: (folder ?? declared).map { .path($0) } ?? .none)
    }

    /// The person changed a word of the sentence: it applies at once, but for Run, which waits for its folder.
    func say(_ chosen: LevelChoice) {
        guard let space else { return }
        guard chosen.level != .run || chosen.folder != .none else {
            draft = chosen
            return refresh()
        }
        draft = nil
        choose(chosen.level, folder: chosen.folder == .blank ? places.blank(space.name) : chosen.folder.path, start: chosen.start,
               scope: chosen.scope == scope ? nil : chosen.scope)
    }

    /// Look Again: reads the Mac now, then says what it found since this look began, its rows lit for a moment.
    func lookAgain() {
        guard !looking, let name = space?.name, let engine = open()?.engine else { return }
        let before = Set((shown + others).map(\.key))
        (looking, said) = (true, nil)
        look(engine) { [weak self] whole in
            // Another space took the panel meanwhile: this look speaks of nothing there.
            guard let self, looking, space?.name == name else { return }
            guard whole else {
                (looking, said) = (false, "Couldn’t look just now.")
                return
            }
            refresh()
            let found = (shown + others).filter { !before.contains($0.key) }
            looking = false
            said = found.count > 1 ? "Found \(found.count) agents." : found.first.map { [home = places.home.path] reading in
                "Found \(reading.title)\(reading.folder.map { " in " + Words.path($0, home: home) } ?? "")."
            } ?? "Nothing new."
            guard !found.isEmpty else { return }
            if !Set(others.map(\.key)).isDisjoint(with: found.map(\.key)) { othersOpen = true }
            fresh = Set(found.map(\.key))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) { [weak self] in self?.fresh = [] }
        }
    }

    /// Others by folder, each folder where its first agent stands; agents whose folder is unknown make one group.
    var groups: [(folder: String?, rows: [AgentReading])] {
        others.reduce(into: []) { groups, reading in
            if let at = groups.firstIndex(where: { $0.folder == reading.folder }) { groups[at].rows.append(reading) } else { groups.append((reading.folder, [reading])) }
        }
    }

    /// Whether Others is folded: when long, unless the person chose or the page sees nothing, where it is all there is.
    var othersFolded: Bool { othersOpen.map { !$0 } ?? (level != nil && level != Grant.Level.none && others.count > 3) }

    /// What the eyes of a list say together: what needs the person, else what works, else what cannot be told.
    static func mood(_ eyes: [Sign.State]) -> Sign.State { [.wait, .think, .unknown].first(where: eyes.contains) ?? .listen }

    /// The person chose `level` here, or for `other` in Settings › Permissions: it becomes the space's grant at once, as on
    /// New Space, and the space, when open, hears it. Run takes `chosen`, else the folder in force, else the one its page
    /// declares when it is on this Mac, else asks for one; a folder not chosen changes nothing. `start` and `scope`, given,
    /// are the sentence's. Says a failure.
    func choose(_ level: Grant.Level, folder chosen: String? = nil, in other: Space? = nil, start: Grant.Start? = nil, scope: Scope? = nil) {
        guard let space = other ?? space, let declaration = Declaration.read(space, home: places.home, kinds: Registry.app.kinds).declaration else { return }
        let kept = other == nil ? self.folder : (try? Grants(places.grants).read())?.spaces[space.name]?.folder
        let folder = level == .run ? chosen ?? kept ?? Levels.onThisMac(declaration.folder, home: places.home) : nil
        if level == .run, folder == nil { return pick { [weak self] in self?.choose(.run, folder: $0, in: other, start: start, scope: scope) } }
        do {
            try Grants(places.grants).update {
                $0.spaces[space.name] = Rights.leveled(level, folder: folder, declaration: declaration, at: iso8601.string(from: clock()), after: $0.spaces[space.name], start: start, scope: scope)
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

    /// What its memory holds, in words.
    var memory: String {
        guard let space, let bytes = try? Memory(folder: places.data, space: space.name).file.resourceValues(forKeys: [.fileSizeKey]).fileSize, bytes > 2 else {
            return "It keeps no memory."
        }
        return "\(Size.words(bytes)) of \(Size.words(Memory.limit))"
    }

    /// The open space's view, when it is the one shown here.
    private func open() -> SpaceView? { current().flatMap { $0.space.name == space?.name ? $0 : nil } }
}

/// The panel's controller: ↑ ↓ move History's choice, and Space held shows it
/// over the page.
final class InfoController: NSHostingController<InspectorView> {
    override func moveUp(_ sender: Any?) { if rootView.info.content == .history { rootView.info.history.move(-1) } }
    override func moveDown(_ sender: Any?) { if rootView.info.content == .history { rootView.info.history.move(1) } }

    override func keyDown(with event: NSEvent) {
        switch (rootView.info.content, event.keyCode) {
        case (.history, 126): moveUp(nil)
        case (.history, 125): moveDown(nil)
        case (.history, 49): if !event.isARepeat { hold() }
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

    /// Opens the panel on `tab`, or closes it, at once: the page is laid out again a single time, never through an animation.
    func showInfo(_ shown: Bool, on tab: Info.Content = .agents) {
        if shown { info.content = tab }
        if shown { HintBubble.close(in: layer, only: .info) }
        info.history.closed()
        // Keys that were in the panel go back to the page as it closes, or to point mode's overlay while it is on.
        let panel = inspector.viewController.view
        if !shown, let held = window.firstResponder as? NSView, held.isDescendant(of: panel), let space {
            window.makeFirstResponder(space.pointer ?? space.web)
        }
        inspector.isCollapsed = !shown
        (controls[Shell.info] as? ToolButton)?.pressed = shown
        titleLine.held = shown && tab == .info
        if shown { info.refresh() }
    }

    /// Shows History in the panel, while a space is open, with the keys: ↑ ↓, Space and Esc are History's at once.
    func showHistory() {
        guard space != nil else { return }
        if info.content != .history || inspector.isCollapsed { info.history.opened() }
        info.content = .history
        inspector.isCollapsed = false
        (controls[Shell.info] as? ToolButton)?.pressed = true
        titleLine.held = false
        window.makeFirstResponder(inspector.viewController.view)
    }

    /// A tab of the panel, chosen.
    func show(tab: Info.Content) { tab == .history ? showHistory() : showInfo(true, on: tab) }

    /// ⌘I and the toolbar's button: opens the panel on Agents while a space is open, else closes it.
    func toggleInfo(spaceOpen: Bool) { showInfo(!infoShown && spaceOpen) }

    /// The title: opens the panel on Info, or closes it from there.
    func toggleTitle() {
        guard space != nil else { return }
        showInfo(!(infoShown && info.content == .info), on: .info)
    }
}

struct InspectorView: View {
    @Bindable var info: Info
    let library: Library
    @Bindable var assistant: AssistantModel

    var body: some View {
        Group {
            if let space = info.space {
                let title = title(space)
                VStack(spacing: 0) {
                    // The toolbar's lower edge goes on over the panel.
                    Rectangle().fill(Look.Token.line.ui).frame(height: 1)
                    top
                    switch info.content {
                    case .agents: AgentsPanel(info: info, assistant: assistant, title: title, motion: library.preferences.motion)
                    case .history: HistoryView(history: info.history, title: title)
                    case .info:
                        DockHeader(title: title, sub: info.about ?? "", titleSize: 19, lines: 3)
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

    /// The tabs and ✕, the same on all three.
    private var top: some View {
        HStack(spacing: 8) {
            Segments(title: "This space", options: Info.Content.allCases.map { .init(value: $0.rawValue, label: $0.rawValue) }, chosen: info.content.rawValue,
                     set: { tab in if let tab = Info.Content(rawValue: tab) { info.select(tab) } }, wide: true)
            Button(action: info.close) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Look.Token.ink2.ui)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(Keys.tooltip("insp", "Close")).accessibilityLabel("Close the panel")
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 10))
        .overlay(alignment: .bottom) { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }
    }

    /// Info's parts and its foot, scrolled.
    private func details(_ space: Space) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                part("Space") { file(space) }
                if info.level == .run || !info.rules.isEmpty { part("Lasting Rules") { always } }
                part("Memory") { Text(info.memory).foot() }
                part("Versions") { versions }
                if assistant.place.space == space.name { part("Assistant") { Text("\(Words.possessive(title(space))) assistant works with \(assistant.name) · \(assistant.modelWords.model).").foot() } }
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

    /// How many versions it keeps, and the way to them.
    private var versions: some View {
        let count = info.history.versions.count
        return HStack(spacing: 8) {
            Text("\(count) version\(count == 1 ? "" : "s")").foot()
            Spacer(minLength: 0)
            Button { info.select(.history) } label: {
                Text("Show History").font(Look.font(.ui, size: 12, weight: .medium).ui).underline(color: Look.Token.line2.ui).foregroundStyle(Look.Token.ink.ui)
            }
            .buttonStyle(.plain)
        }
    }

    /// Its title. Whether its assistant built the page is not kept: a template's or an imported page's has an assistant too.
    private func title(_ space: Space) -> String { library.entry(space.name)?.title ?? space.name }

    /// Space: where its file is, with Show in Finder; its weight and last change; Export.
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
            wide("Export…", "square.and.arrow.up") { library.export(space.name) }.help(Keys.tooltip("export", "Export to Downloads"))
        }
    }

    /// Always for this space: each lasting rule, its agent, its command and its folder, with Revoke; or how one is made.
    private var always: some View {
        VStack(alignment: .leading, spacing: 6) {
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
    }

    /// A part of the panel, above a line: its title in small capitals, then its content.
    private func part(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Heading(words: title)
            content()
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }
    }

    /// A button as wide as its part.
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

/// The head of Info's and History's tab: its title, and a line under it (none when empty; Info's description wraps on
/// up to `lines`).
struct DockHeader: View {
    let title: String, sub: String
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
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 11, trailing: 12))
        .overlay(alignment: .bottom) { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }
    }
}

extension View {
    /// The mockup's small foot under a part: 11.5 in ink3.
    func foot() -> some View {
        font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui).fixedSize(horizontal: false, vertical: true)
    }
}

private extension String {
    /// A day said inside a sentence: "today", "yesterday"; a date stays as it is.
    var inSentence: String { hasPrefix("Today") || hasPrefix("Yesterday") ? prefix(1).lowercased() + dropFirst() : self }
}
