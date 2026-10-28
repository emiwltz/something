// Info, docked at the window's right edge at full height, 320 points: the space narrows beside it, nothing hides under
// it. One panel holds Info or History (History.swift), swapped by `content` without a relayout; it opens and closes at
// once, the page laid out again a single time (SP10). Info is everything about the open space in one place, in three
// parts that follow what a space is (X5.1): Space (its file, its size and last change, Export in one click, History),
// Your agents (its level, one control, Run's folder, and the agents its page shows now) and Assistant (its eyes, the
// agent and model in one chip, its last reply, Open Conversation); Move to Trash… waits quietly at the foot. A level
// chosen here is the person's answer: kept in the grants file, it reaches the open space at once as a `granted`
// event (X5.2). ✕ and ⌘I close it, and Esc while the focus is in it: an Esc of the whole window would take it from
// every page and field.
import AppKit
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
    /// Why the level cannot be shown: the grants file does not read.
    private(set) var problem: String?
    /// Its last change (the newest of a folder's files) and its weight; nil when unread.
    private(set) var changed: Date?
    private(set) var size: Size?
    /// The agents its page sees now, as it receives them; and the folders the Mac's agents work in, Run's choices.
    private(set) var shown: [Agent] = []
    private(set) var folders: [String] = []
    /// What each agent shown did last, by its id, as its page sees it: the last step or message of its conversation.
    private(set) var lasts: [String: String] = [:]

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
        (about, level, folder, problem, changed, size) = (nil, nil, nil, nil, nil, nil)
        defer { refresh() }
        guard let space else { return }
        let declaration = Declaration.read(space, home: places.home, kinds: Registry.app.kinds).declaration
        about = declaration?.description
        if declaration != nil {
            do {
                let grant = try Grants(places.grants).read().spaces[space.name]
                (level, folder) = (grant.map(Rights.level(of:)) ?? Grant.Level.none, grant?.folder)
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
        let said = visible.map(Info.lasts) ?? [:]
        if agents != shown { shown = agents }
        if said != lasts { lasts = said }
        if known != folders { folders = known }
    }

    /// The person chose `level` here: it becomes the space's grant at once, as on New Space, and the open space hears
    /// it. Run takes `chosen`, else the folder in force, else the one its page declares when it is on this Mac, else
    /// asks for one; a folder not chosen changes nothing. Says a failure.
    func choose(_ level: Grant.Level, folder chosen: String? = nil) {
        guard let space, let declaration = Declaration.read(space, home: places.home, kinds: Registry.app.kinds).declaration else { return }
        let folder = level == .run ? chosen ?? self.folder ?? Levels.onThisMac(declaration.folder, home: places.home) : nil
        if level == .run, folder == nil { return pick { [weak self] in self?.choose(.run, folder: $0) } }
        do {
            try Grants(places.grants).update {
                $0.spaces[space.name] = Rights.leveled(level, folder: folder, declaration: declaration, at: iso8601.string(from: clock()), after: $0.spaces[space.name])
            }
        } catch {
            ask.tell(error.sentence)
        }
        open()?.regrant()
        show(space)
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

    /// What an agent is doing, as a page that sees it would say it in a word or two; the unknown is said as such.
    static func doing(_ agent: Agent) -> String {
        if agent.alive == false { return "ended" }
        return switch agent.state {
        case "working": "working"
        case "waiting": "waits for you"
        case "idle": "idle"
        case "interrupted": "stopped"
        case "done": "done"
        case "error": "stopped on an error"
        default: "state unknown"
        }
    }

    /// The last step or message of each agent's conversation in `state`, by agent, on one line: the last words a page
    /// that sees it has of what it does.
    static func lasts(_ state: SomethingCore.State) -> [String: String] {
        state.threads.reduce(into: [:]) { lasts, thread in
            guard let item = thread.turns.last?.items.last else { return }
            let line = item.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            if !line.isEmpty { lasts[thread.agent] = line.count > 60 ? String(line.prefix(58)) + "…" : line }
        }
    }

    /// What an agent shown is doing, with what it did last when its page has it; idle, since when.
    func doing(_ agent: Agent) -> String {
        let doing = Info.doing(agent)
        if agent.alive != false, agent.state == "idle", let updated = agent.updated.flatMap(iso8601.date) {
            return doing + " since " + Info.day(updated, now: clock(), time: true).inSentence.replacingOccurrences(of: "today, ", with: "")
        }
        guard ["working", "waiting"].contains(agent.state), agent.alive != false, let last = lasts[agent.id] else { return doing }
        return doing + ": " + last
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
                    Image(systemName: "arrow.up.forward.app").font(.system(size: 12)).foregroundStyle(Look.Token.ink2.ui).frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(Keys.tooltip("finder", "Show in Finder")).accessibilityLabel("Show in Finder")
            }
            if let size = info.size {
                Text(Info.weight(size, form: space.form, changed: info.changed, now: info.clock())).foot()
            }
            HStack(spacing: 8) {
                wide("Export", "square.and.arrow.up") { library.export(space.name) }.help(Keys.tooltip("export", "Export to Downloads"))
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
            if level != .none, !info.shown.isEmpty { now }
            Levels.note("Whatever an agent asks still waits for you: Allow Once or Deny.")
        } else {
            Text("It can't be shown now, so it shows no agent.").foot()
        }
    }

    /// The agents the page shows now: who, what it does, where.
    private var now: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(info.shown, id: \.id) { agent in
                // A program something only sees by its process goes by that process's name.
                let name = Registry.app.agent(agent.kind)?.name ?? agent.name ?? agent.kind, doing = info.doing(agent)
                let folder = agent.folder.map { Words.path($0, home: info.places.home.path) }
                HStack(alignment: .center, spacing: 8) {
                    Monogram(name: name)
                    VStack(alignment: .leading, spacing: 1) {
                        (Text(name).font(Look.font(.ui, size: 12, weight: .semibold).ui).foregroundColor(Look.Token.ink.ui) + Text(" " + doing))
                            .font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink2.ui).fixedSize(horizontal: false, vertical: true)
                        if let folder { Text(folder).font(Look.font(.code, size: 10.5).ui).foregroundStyle(Look.Token.ink3.ui).lineLimit(1).truncationMode(.head) }
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore).accessibilityLabel([name, doing, folder].compactMap { $0 }.joined(separator: ", "))
            }
        }
        .padding(4)
        .boxed(RoundedRectangle(cornerRadius: 9), Look.Token.bg2.ui, ring: Look.Token.line.ui)
        .accessibilityElement(children: .contain).accessibilityLabel("The agents it shows now")
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
