// Info, docked at the window's right edge at full height, 320 points: the space narrows beside it, nothing hides under
// it. One panel holds Info or History (History.swift), swapped by `content` without a relayout; it opens and closes at
// once, the page laid out again a single time (SP10). Info says, of the open space: its assistant (its eyes and a plain
// sentence, agent, model, conversation, New Conversation, Put to Sleep, and Show Request while a request of its own
// waits), what it may do (a switch for each right answered, Ask Again), its versions (how many, the latest, Show
// History…), about it (its description, group, made, size, last change, where), Show in Finder, Export… and Move to
// Trash…, and last its activity, the journal newest first.
// A switched right is kept in the grants file and reaches the open space at once as a `granted` event. ✕ and ⌘I close
// it, and Esc while the focus is in it: an Esc of the whole window would take it from every page and field.
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
    /// The open space's view, which hears of a switched right at once.
    @ObservationIgnored var current: () -> SpaceView? = { nil }
    /// The agents of the state, so that the journal names each one it still knows.
    @ObservationIgnored var agents: () -> [Agent] = { [] }
    /// Closes the panel: the window's.
    @ObservationIgnored var close: () -> Void = {}
    /// The clock the dates are said by; a test sets it.
    @ObservationIgnored var clock: () -> Date = Date.init
    /// Shows History in the panel: the window's.
    @ObservationIgnored var showHistory: () -> Void = {}
    /// The open space's versions, which History and the Versions part show.
    let history: History
    var content = Content.info
    /// How many requests of the open space's own wait: Show Request is offered while one does.
    var waiting = 0
    /// The tool the first of them asks for, as the request panel names it; nil when none waits or the app does not say.
    @ObservationIgnored var asks: () -> String? = { nil }
    private(set) var space: Space?
    private(set) var about: String?
    /// The declared rights and where each stands; empty until the person answered the space once.
    private(set) var rights: [(right: String, standing: Standing)] = []
    /// When the person last answered the space's rights.
    private(set) var answered: Date?
    /// Set when the space declares no right: it only shows its page, and is never asked about.
    private(set) var asksNothing = false
    /// The journal, newest first: a time and a sentence each.
    private(set) var activity: [(time: String, what: String)] = []
    /// Where the agents the space launches work, when a folder was chosen.
    private(set) var folder: String?
    /// Why the rights cannot be shown: the grants file does not read.
    private(set) var problem: String?
    /// What its files say: made, last changed (the newest of a folder's files), and its weight; nil when unread.
    private(set) var made: Date?
    private(set) var changed: Date?
    private(set) var size: Size?

    enum Standing: Equatable {
        case allowed, refused
        /// Declared after the last answer: asked at the next opening. `inForce` holds the narrower words allowed
        /// earlier that the space keeps until then.
        case notAnswered(inForce: [String])
    }

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
        (rights, activity, folder, problem, answered, made, changed, size) = ([], [], nil, nil, nil, nil, nil, nil)
        guard let space else { return }
        let reading = Declaration.read(space, home: places.home, kinds: Registry.app.kinds)
        about = reading.declaration?.description
        asksNothing = reading.declaration?.rights.isEmpty ?? true
        do {
            let grant = try Grants(places.grants).read().spaces[space.name]
            if let grant { rights = Info.standings(reading, grant, home: places.home) }
            folder = grant?.folder
            answered = grant.flatMap { iso8601.date(from: $0.at) }
        } catch {
            problem = error.sentence
        }
        made = try? space.location.resourceValues(forKeys: [.creationDateKey]).creationDate
        // One walk of its files for both. They are read again at each opening; an edit while Info shows waits for
        // the hook that hears the space's files change (T13).
        let files = space.files().compactMap { try? $0.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) }
        changed = files.compactMap(\.contentModificationDate).max()
        size = Size(bytes: files.compactMap(\.fileSize).reduce(0, +), files: files.count)
        journaled()
    }

    /// Reads the space's journal again, newest first: what a new journal line changes, without walking its files.
    func journaled() {
        guard let space else { return }
        do {
            let names = Dictionary(agents().compactMap { agent in agent.name.map { (agent.id, $0) } }) { first, _ in first }
            activity = try Journal(folder: places.journals).last(100, space: space.name).reversed().map {
                let line = Words.journal($0, names: names, home: places.home.path).split(separator: "\t", maxSplits: 1)
                return (String(line[0]), line.count > 1 ? String(line[1]) : "")
            }
        } catch {
            activity = [("", error.sentence)]
        }
    }

    /// Where each declared right stands, by what the space receives: the same reading as its `granted`.
    static func standings(_ reading: DeclarationReading, _ grant: Grant, home: URL) -> [(right: String, standing: Standing)] {
        let force = Rights.granted(reading, grant, limits: [:], home: home)
        return (reading.declaration?.rights ?? []).map { right in
            if force.rights.contains(right) { return (right, .allowed) }
            if force.refused.contains(right) { return (right, .refused) }
            return (right, .notAnswered(inForce: force.rights.filter { $0 != right && Rights.covers([right], $0) }))
        }
    }

    /// A right as the panel names it, as the rights sheet does, and what it lets the space do in the mockup's short
    /// words, with the warning the rights sheet gives when it has one.
    static func words(for right: String) -> (name: String, detail: String) {
        let detail = ["state": "Their state, folder and last messages.", "send": "Send them a message you typed here.",
                      "launch": "Launch one in a folder you choose.", "store": "A small memory, kept in its own folder."][Ask.parts(of: right).word]
        return (Ask.right(right).title, [detail ?? "", Ask.warning(for: right).map { $0 + "." }].compactMap { $0 }.joined(separator: " "))
    }

    /// What the assistant is doing, in one plain sentence after its state's word; the unknown is said as such.
    /// While it waits, `wants` says what its request asks ("run a command"), when known.
    static func sentence(_ state: Sign.State, wants: String? = nil) -> String {
        switch state {
        case .think: "It is changing the space."
        case .wait: "\(wants.map { "It wants to \($0)." } ?? "It asked you something.") Its request waits in a window of its own, outside the space."
        case .done: "It finished its last change a moment ago."
        case .listen: "It listens. Write to it and it changes the space with you."
        case .sleep: "It is asleep and wakes on your next message."
        case .limit: "It stopped: it can't reach its model right now."
        case .unknown: "something cannot read its state right now, so it does not guess."
        }
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

    /// "12 KB · one page", or "48 KB · 5 files" for a folder space.
    static func weight(_ size: Size, form: Space.Form) -> String {
        Size.words(size.bytes) + " · " + (form == .file ? "one page" : "\(size.files) file\(size.files == 1 ? "" : "s")")
    }

    /// Allows or refuses one declared right, as the person's answer, and tells the open space. A space never
    /// answered has no switch: its first answers are given in its rights sheet, with its scope and folder.
    func set(_ right: String, allowed: Bool) {
        let declared = space.flatMap { Declaration.read($0, home: places.home, kinds: Registry.app.kinds).declaration?.rights } ?? []
        change { grant in
            guard var next = grant else { return }
            // A wider or a narrower word answered earlier would decide in place of this answer. A wider one also
            // answered the other declared rights it covers: they keep that answer.
            let related = { (word: String) in Rights.covers([right], word) || Rights.covers([word], right) }
            let kept = { (words: [String]) in
                words.filter { $0 != right && Rights.covers([$0], right) }
                    .flatMap { wider in declared.filter { $0 != right && !related($0) && Rights.covers([wider], $0) } }
            }
            let keptAllowed = kept(next.granted)
            let keptRefused = kept(next.refused)
            next.granted.removeAll(where: related)
            next.refused.removeAll(where: related)
            next.granted += keptAllowed.filter { !next.granted.contains($0) }
            next.refused += keptRefused.filter { !next.refused.contains($0) }
            if allowed { next.granted.append(right) } else { next.refused.append(right) }
            next.at = iso8601.string(from: clock())
            grant = next
        }
        open()?.regrant()
    }

    /// Clears the space's refusals: what it was allowed, its folder and its remap stay. The refused rights are asked
    /// again now if it is open, otherwise at its next opening.
    func askAgain() {
        change { $0?.refused = [] }
        // Just after the button's action: the rights sheet waits for the person, and the view must not wait inside it.
        DispatchQueue.main.async { [weak self] in
            guard let self, let open = open() else { return }
            open.load()
            show(space)
        }
    }

    /// The open space's view, when it is the one shown here.
    private func open() -> SpaceView? { current().flatMap { $0.space.name == space?.name ? $0 : nil } }

    /// Changes the space's grant in the grants file, then shows it again; says a failure.
    private func change(_ edit: (inout Grant?) -> Void) {
        guard let space else { return }
        do { try Grants(places.grants).update { edit(&$0.spaces[space.name]) } } catch { ask.tell(error.sentence) }
        show(space)
    }
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
        info.history.closed()
        // Keys that were in the panel go back to the page as it closes, or to point mode's overlay while it is on.
        let panel = inspector.viewController.view
        if !shown, let held = window.firstResponder as? NSView, held.isDescendant(of: panel), let space {
            window.makeFirstResponder(space.pointer ?? space.web)
        }
        inspector.isCollapsed = !shown
        (controls[Shell.info] as? ToolButton)?.pressed = shown
    }

    /// Shows History in the panel, in Info's place, while a space is open, with the keys: ↑ ↓, Space and Esc are
    /// History's at once. Info's button is not pressed for it.
    func showHistory() {
        guard space != nil else { return }
        if info.content != .history || inspector.isCollapsed { info.history.opened() }
        info.content = .history
        inspector.isCollapsed = false
        (controls[Shell.info] as? ToolButton)?.pressed = false
        window.makeFirstResponder(inspector.viewController.view)
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
                        DockHeader(title: "Info", sub: "\(title) · \(space.location.lastPathComponent)",
                                    help: Words.path(space.location.path, home: info.places.home.path), close: ("Close Info", info.close))
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

    /// Info's parts, scrolled.
    private func details(_ space: Space) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if assistant.place.space == space.name { yours }
                group("What it may do") { permissions }
                group("Versions") { versions }
                group("About") { facts(space) }
                actions(space)
                group("Activity") { activity }
            }
            .padding(EdgeInsets(top: 20, leading: 18, bottom: 22, trailing: 18))
        }
        .scrollIndicators(.never)
    }

    /// Versions: how many are kept and what they weigh, when the latest was made (its sentence on hover), and
    /// Show History….
    private var versions: some View {
        let history = info.history, latest = history.versions.first
        return VStack(alignment: .leading, spacing: 11) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: Look.row * 0.32) {
                row("Kept", latest == nil ? "None yet" : "\(history.versions.count) · \(Size.words(history.bytes))")
                if let latest { row("Latest", History.when(latest.when, now: info.clock())).help(history.title(latest)) }
            }
            Button { info.showHistory() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 12)).foregroundStyle(Look.Token.ink2.ui)
                    Text("Show History…").font(Look.font(.ui, size: 12.5, weight: .medium).ui)
                }
            }
            .buttonStyle(Secondary(height: 30))
        }
    }

    /// Its assistant: the eyes and a sentence, Show Request while a request of its own waits, agent, model and
    /// conversation, New Conversation and Put to Sleep.
    private var yours: some View {
        let state = assistant.presence.state, name = assistant.name(of: assistant.session), count = assistant.messageCount
        let since = assistant.rows.lazy.compactMap { if case .day(let date) = $0 { date } else { nil } }.first
        let messages = "\(count) message\(count == 1 ? "" : "s")"
        let conversation = count == 0 ? "None yet"
            : assistant.resumes ? "Since \(since.map { Info.day($0, now: info.clock()).inSentence } ?? "today") · \(messages)" : "\(messages) · starts fresh"
        let words = assistant.modelWords
        return group("Its assistant") {
            VStack(alignment: .leading, spacing: 12) {
                let sentence = Info.sentence(state, wants: info.waiting > 0 ? info.asks().map(Words.wants) : nil)
                HStack(alignment: .top, spacing: 12) {
                    Image(nsImage: Sign.miniEyes(state, template: false)).resizable().interpolation(.high).frame(width: 30.6, height: 20.4)
                        .frame(width: 40, height: 34).boxed(RoundedRectangle(cornerRadius: 9), Look.Token.bg.ui, ring: Look.Token.line.ui)
                    (Text(state.word + ". ").font(Look.font(.ui, size: 13, weight: .semibold).ui).foregroundColor(Look.Token.ink.ui)
                        + Text(sentence).font(Look.font(.voice, size: 13).ui).foregroundColor(Look.Token.ink2.ui))
                        .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore).accessibilityLabel(state.word + ". " + sentence)
                if info.waiting > 0 {
                    Button { assistant.showRequest() } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "checkmark.shield").font(.system(size: 12, weight: .medium))
                            Text("Show Request").font(Look.font(.ui, size: 12.5, weight: .medium).ui)
                            Text(Keys.shown("showreq")).font(Look.font(.ui, size: 10, weight: .medium).ui).foregroundStyle(Look.Token.ink3.ui)
                                .padding(.leading, 4)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(Secondary(height: 30))
                }
                VStack(spacing: 0) {
                    Rectangle().fill(Look.Token.line.ui).frame(height: 1).padding(.bottom, 10)
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: Look.row * 0.32) {
                        row("Agent", name)
                        row("Model", words.model + (words.effort.map { " · " + $0 } ?? ""))
                        row("Conversation", conversation)
                    }
                }
                HStack(spacing: 6) {
                    // The first takes the room its words need, as the mockup's grid gives it; the second the rest.
                    small("New Conversation", "bubble.left") { assistant.newConversation() }.fixedSize()
                    small("Put to Sleep", "moon") { assistant.putToSleep() }
                        .disabled(!assistant.canSleep || info.waiting > 0)
                        .help(info.waiting > 0 ? "Answer its request first" : state == .sleep ? "It is asleep: it wakes on your next message" : "")
                }
            }
            .padding(14)
            .plate()
            // About the agent, not this conversation: a space with none yet must not read as if its agent never resumes.
            if !assistant.agentResumes {
                Text("\(name) cannot resume a conversation, so each one starts fresh.").foot()
            }
        }
    }

    /// What it may do: a switch for each right answered, its standing, when the person last answered, Ask Again.
    @ViewBuilder private var permissions: some View {
        if let problem = info.problem {
            Text(problem).foot()
        } else if info.asksNothing {
            Text("It asks for nothing: it only shows its page.").foot()
        } else if info.rights.isEmpty {
            Text("Not answered yet: it asks when it opens.").foot()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(info.rights.enumerated()), id: \.element.right) { index, line in
                    right(line.right, line.standing).overlay(alignment: .top) {
                        if index > 0 { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }
                    }
                }
            }
            .padding(.horizontal, 14)
            .plate()
            let answered = info.answered.map { "Last answered \(Info.day($0, now: info.clock()).inSentence). " } ?? ""
            Text(answered + "A space asks before it gets a new right. Turning one off works at once.").foot()
            if info.rights.contains(where: { $0.standing == .refused }) {
                Button { info.askAgain() } label: { Text("Ask Again").font(Look.font(.ui, size: 12, weight: .medium).ui) }
                    .buttonStyle(Secondary(height: 28, leading: 10, trailing: 10))
            }
        }
    }

    private func right(_ right: String, _ standing: Info.Standing) -> some View {
        let words = Info.words(for: right)
        let when: String = switch standing {
        case .allowed: "Allowed"
        case .refused: "Not allowed"
        case .notAnswered(let inForce):
            "Asked when it next opens" + (inForce.isEmpty ? "" : " · allowed until then: " + inForce.map { Info.words(for: $0).name }.joined(separator: ", "))
        }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(words.name).font(Look.font(.ui, size: 12.5, weight: .medium).ui)
                if !words.detail.isEmpty { Text(words.detail).font(Look.small.font.ui).foregroundStyle(Look.Token.ink2.ui) }
                Text(when).font(Look.font(.ui, size: 11).ui).foregroundStyle(Look.Token.ink3.ui)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if standing == .allowed || standing == .refused {
                Toggle(words.name, isOn: Binding(get: { standing == .allowed }, set: { info.set(right, allowed: $0) }))
                    .toggleStyle(SwitchStyle()).labelsHidden()
            }
        }
        .padding(.vertical, Look.row * 0.4)
        // Read as one line, its switch with it: "See your agents, …, Allowed".
        .accessibilityElement(children: .combine)
    }

    /// About: its description, group, made, size, last change, where; where its agents work, when a folder was chosen.
    private func facts(_ space: Space) -> some View {
        let now = info.clock(), group = library.preferences.group(of: space.name), groups = library.preferences.groups.map(\.name)
        return VStack(alignment: .leading, spacing: 9) {
            if let about = info.about { Text(about).foregroundStyle(Look.Token.ink2.ui).fixedSize(horizontal: false, vertical: true) }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: Look.row * 0.32) {
                GridRow {
                    Text("Group").foregroundStyle(Look.Token.ink3.ui)
                    // The groups as the sidebar's Show in Group has them: no "None", a space leaves a group only for
                    // another one there too.
                    PopMenu(title: "Group", shown: group ?? "None") {
                        Picker("Group", selection: Binding(get: { group ?? "" }, set: { if $0 != group { library.move(space.name, to: $0) } })) {
                            ForEach(groups, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    .disabled(groups.isEmpty).frame(maxWidth: .infinity, alignment: .trailing)
                }
                row("Made", info.made.map { Info.day($0, now: now) } ?? "Unknown")
                row("Size", info.size.map { Info.weight($0, form: space.form) } ?? "Unknown")
                row("Last change", info.changed.map { Info.day($0, now: now, time: true) } ?? "Unknown")
                GridRow {
                    Text("Where").foregroundStyle(Look.Token.ink3.ui)
                    Text(Words.path(space.location.path, home: info.places.home.path)).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Look.Token.ink2.ui).lineLimit(1).truncationMode(.head).help(space.location.path)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if let folder = info.folder { row("Agents work in", Words.path(folder, home: info.places.home.path)) }
            }
        }
    }

    /// Show in Finder, Export… and Move to Trash…, as the row's menu has them.
    private func actions(_ space: Space) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            action("Show in Finder", "macwindow", key: "finder") { library.showInFinder(space.name) }
            action("Export…", "square.and.arrow.up", key: "export", shortcut: true) { library.export(space.name) }
            action("Move to Trash…", "trash", key: "trash", bad: true) {
                if let entry = library.entry(space.name) { library.trashing(entry) }
            }
        }
        .padding(.top, 4)
        .overlay(alignment: .top) { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }
    }

    @ViewBuilder private var activity: some View {
        if info.activity.isEmpty {
            Text("Nothing yet. Each time this space writes to, starts or changes an agent, or opens a link, it shows here.").foot()
        } else {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(Array(info.activity.enumerated()), id: \.offset) { _, line in
                    GridRow {
                        Text(line.time).monospacedDigit().foregroundStyle(Look.Token.ink3.ui)
                        Text(line.what).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(Look.small.font.ui)
        }
    }

    /// A part of the panel: its title in small capitals, then its content.
    private func group(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased()).font(Look.font(.ui, size: 10.5, weight: .semibold).ui).kerning(0.525)
                .foregroundStyle(Look.Token.ink3.ui).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func row(_ name: String, _ value: String) -> some View {
        GridRow {
            Text(name).foregroundStyle(Look.Token.ink3.ui)
            Text(value).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func small(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Look.Token.ink2.ui)
                Text(title).font(Look.font(.ui, size: 12, weight: .medium).ui).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(Secondary(height: 28, leading: 8, trailing: 8)).modifier(Dimmed())
    }

    private func action(_ title: String, _ symbol: String, key: String, shortcut: Bool = false, bad: Bool = false, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle((bad ? Look.Token.bad : .ink2).ui).frame(width: 16)
                Text(title).font(Look.font(.ui, size: 12.5, weight: .medium).ui).foregroundStyle((bad ? Look.Token.bad : .ink).ui)
                if shortcut { Text(Keys.shown(key)).font(Look.font(.ui, size: 10, weight: .medium).ui).foregroundStyle(Look.Token.ink3.ui) }
            }
            .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 30, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(Keys.tooltip(key, title))
    }
}

/// The panel's header, Info's and History's: its title, a line under it, and ✕ (`close`: its label and action).
struct DockHeader: View {
    let title: String, sub: String, help: String?
    let close: (label: String, run: () -> Void)

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Look.titleS.font.ui).kerning(-0.34).accessibilityAddTraits(.isHeader)
                Text(sub).font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui).lineLimit(1).help(help ?? "")
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

/// The mockup's switch: 30 by 18, ink when on, mist when off, its knob bg2.
struct SwitchTrack: View {
    let on: Bool

    var body: some View {
        Capsule().fill((on ? Look.Token.ink : .mist).ui).frame(width: 30, height: 18)
            .overlay(alignment: on ? .trailing : .leading) { Circle().fill(Look.Token.bg2.ui).frame(width: 14, height: 14).padding(2) }
    }
}

/// A toggle drawn as the mockup's switch.
struct SwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: { SwitchTrack(on: configuration.isOn) }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// Half drawn while it cannot act: a custom button style draws the same either way.
private struct Dimmed: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View { content.opacity(enabled ? 1 : 0.45) }
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
