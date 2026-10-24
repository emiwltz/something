// The Mac app: one Engine and one window (Shell.swift) with the spaces (Library.swift), the open space (SpaceView.swift),
// Info (Inspector.swift) and the assistant (Assistant.swift); the tour at the first start (Tour.swift); the menu bar
// (Keys.swift) and the keys it keeps from a page; the spaces and exports LaunchServices hands it; the panel of the
// agents' requests; the state pushed at most four times a second; and quitting, which asks first while a request waits
// or an agent something launched works, then denies the requests and stops the agents. Closing the window keeps the
// app and its agents running, as a Mac app with one main window does; the open space closes with it, and opens again
// when the window comes back.
import AppKit
import SomethingAgents
import SomethingCore
import WebKit

final class App: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    /// The space named on the command line, or the path of an export; nil to open the last space open.
    let opening: String?
    let places = Places.person
    let engine = Engine(environment: ProcessInfo.processInfo.environment, registry: .app)
    let ask = NativeAsk()
    let launches = Launches()
    lazy var library = Library(places: places, ask: ask, share: Resources.share)
    lazy var info = Info(places: places, ask: ask)
    lazy var assistant = AssistantModel(engine: engine, places: places)
    lazy var shell = Shell(library: library, info: info, assistant: assistant, autosave: true)
    lazy var panels = Panels(source: engine)
    lazy var menuBar = MenuBar(builders: self)
    /// The open space. One at a time: opening another closes it.
    var current: SpaceView?
    var pushing = false
    /// Lockdown's rule list, compiled before the first space opens.
    var rules: WKContentRuleList?
    /// What LaunchServices handed the app before it was ready to open anything; nil once it is.
    var handed: [URL]? = []
    /// Whether the window can be seen. While it cannot, nothing is looked at: the agents, the spaces folder and the
    /// open space's files are looked at again the moment it shows.
    var shown = true

    init(opening: String?) {
        self.opening = opening
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar.install()
        menuBar.spaces = { [weak self] in self?.library.order().filter(\.isSpace).map { ($0.id, $0.title) } ?? [] }
        menuBar.open = { [weak self] in self?.current.map { ($0.space.name, $0.title) } }
        menuBar.editingText = { [weak self] in self?.shell.window.firstResponder is NSText }
        // WebKit hands a page the keys it has the focus for, ⌘P and ⌘1 included: something's own go to the menu first.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return menuBar.intercept(event, window: shell.window)
        }
        ask.window = { [weak self] in self?.shell.window }
        library.opened = { [weak self] name in self?.open(name) }
        library.trashing = { [weak self] entry in self?.confirmTrash(entry) }
        library.used = { [weak self] name in self?.assistant.fromTemplate = name }
        info.current = { [weak self] in self?.current }
        info.agents = { [weak self] in self?.engine.state.agents ?? [] }
        info.reveal = { [weak self] in self?.library.showInFinder($0) }
        // The space stays selected, so that it opens again with the window.
        shell.closed = { [weak self] in self?.open(nil) }
        shell.visible = { [weak self] visible in
            guard let self, visible != shown else { return }
            shown = visible
            engine.start(often: current != nil, visible: visible)
            library.watching(visible)
            current?.watching(visible)
        }
        panels.who = { [weak self] request in self?.who(request) ?? Asker(program: "An agent") }
        panels.beside = { [weak self] in self?.shell.window }
        panels.counted = { [weak self] _ in self?.counted() }
        panels.attention = Attention(dock: NSApp, notifier: SystemNotifier.make { [weak self] in
            self?.front()
            self?.showRequest(nil)
        })
        panels.attention?.notify = { [weak self] in self?.library.preferences.notify == true }
        panels.queue.space = { [weak self] request in
            guard let self else { return nil }
            return RequestQueue.space(of: request.agent, assistant: engine.assistants.contains(request.agent), place: assistant.place,
                                      launches: launches.ids)
        }
        engine.changed = { [weak self] in self?.schedulePush() }
        // This program's main routes `something hook permission`, inside the .app and under `swift run` alike.
        engine.hookCommand = Engine.ownHookCommand
        engine.spools = places.spools.path
        assistant.confirmSwitch = { [weak self] from, to, switched in self?.sheet(Ask.switching(from: from, to: to), then: switched) }
        assistant.howTo = { [weak self] in
            guard let self else { return }
            sheet(Ask.howToGetOne(copy: assistant.copy)) { [weak self] in self?.assistant.lookAgain() }
        }
        assistant.showRequest = { [weak self] in self?.showRequest(nil) }
        assistant.openReady = { [weak self] in self?.library.select(.space($0)) }
        assistant.ended = { [weak self] in
            guard let self else { return }
            library.relist()
            if let new = assistant.appeared(library.entries, open: library.selection.space) { library.select(.space(new)) }
        }
        // Before any reading: the conversations there are the person's with their assistant, never a space's to see.
        engine.assistantFolder = places.spaces.path
        engine.start(often: false)
        shell.front()
        Task { @MainActor in
            do { rules = try await Lockdown.ruleList() } catch { fail(error.sentence) }
            do { try Library.prepare(places) } catch { fail(error.sentence) }
            do { try AssistantModel.writeKnowledge(places, share: Resources.share) } catch { ask.tell(error.sentence) }
            // A space deleted or renamed while the app was not running loses its grants before any space opens.
            do { try Library.forgetGone(places) } catch { ask.tell(error.sentence) }
            library.preferences.forgetGone(in: places.spaces)
            library.watch()
            let early = handed ?? []
            handed = nil
            if let opening, (opening as NSString).pathExtension == "something" {
                receive(URL(fileURLWithPath: opening).standardizedFileURL)
            } else if let opening {
                guard library.entry(opening) != nil else {
                    return ask.tell("There is no space \(opening) in \(places.spaces.path). Type something new \(opening) to make it.")
                }
                library.select(.space(opening))
            } else if !early.isEmpty {
                early.forEach(receive)
            } else if let last = library.last() {
                library.select(.space(last))
            } else if !library.preferences.toured {
                showTour(nil)
            }
        }
    }

    /// `something open`, a double click on an export, or a file dropped on the Dock icon. It may come before the app
    /// is ready, and then waits for it.
    func application(_ application: NSApplication, open urls: [URL]) {
        if handed != nil { handed?.append(contentsOf: urls) } else { urls.forEach(receive) }
    }

    /// Imports an export, or opens a space of the spaces folder; says how to open any other page.
    func receive(_ url: URL) {
        if url.pathExtension == "something" {
            shell.front()
            return library.importSpace(from: url)
        }
        guard let space = Command.kept(url, places) else {
            shell.front()
            return ask.tell(Command.elsewhere(url))
        }
        library.relist()
        library.select(.space(space.name))
        front()
    }

    /// Shows the tour in the window, the open space closed; it ends on the blank page.
    @objc func showTour(_ sender: Any?) {
        library.select(.tour)
        shell.front()
    }

    /// The tour in the center, made anew; at its end the window goes to New Space.
    private func showTourNow() {
        let tour = Tour(places: places)
        tour.finished = { [weak self] problem in
            self?.library.select(.newSpace)
            problem.map { self?.ask.tell($0) }
        }
        shell.show(tour)
    }

    @objc func newSpace(_ sender: Any?) {
        library.select(.newSpace)
        askAssistant(sender)
    }

    @objc func showTemplates(_ sender: Any?) {
        library.select(.templates)
        shell.front()
    }

    @objc func showPromise(_ sender: Any?) { sheet(Ask.doesAndDoesnt()) {} }

    /// something Help: the README on GitHub, in the person's browser, once they said so.
    @objc func openHelp(_ sender: Any?) {
        guard let readme = URL(string: "https://github.com/emiwltz/something#readme") else { return }
        sheet(Ask.alert("Open something's Help on GitHub?", readme.absoluteString, buttons: ["Open", "Cancel"], escape: 1)) {
            NSWorkspace.shared.open(readme)
        }
    }

    /// The guide for coding agents, shown in Finder: the person hands its path to their agent.
    @objc func showGuide(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting([Resources.share.appendingPathComponent("guide.md")])
    }

    /// Shows the window; the space open when it was closed opens again.
    func front() {
        shell.front()
        if current == nil, library.selection.space != nil { open(library.selection) }
    }

    /// Closes the open space and shows `destination` in the center. The space already open stays as it is. nil, when
    /// the window closed, only closes the open space: the selection stays, and opens again with the window.
    func open(_ destination: Library.Destination?) {
        let name = destination?.space
        if let name, current?.space.name == name { return }
        let closing = current != nil
        current?.close()
        current = nil
        assistant.unkept = false
        if assistant.ready?.id == name { assistant.ready = nil }
        defer {
            assistant.place = (destination ?? library.selection) == .templates ? .templates : AssistantModel.place(current)
            info.show(current?.space)
            counted()
            // The readers look often while a space is open, and rarely when nobody is looking.
            engine.start(often: current != nil, visible: shown)
            current?.watching(shown)
        }
        switch destination {
        case nil:
            if closing { shell.show(nil) }
            return
        case .newSpace?: return shell.show(nil)
        case .templates?: return shell.show(nil, templates: true)
        case .tour?: return showTourNow()
        case .space?: break
        }
        guard let name, let space = library.entry(name)?.space else { return shell.show(nil) }
        guard let rules else {
            shell.show(nil)
            return ask.tell("something is still starting; try again in a moment.")
        }
        do {
            let view = try SpaceView(space: space, places: places, engine: engine, ask: ask, share: Resources.share, rules: rules,
                                     launches: launches)
            view.loaded = { [weak self, weak view] in
                guard let self, let view, current === view else { return }
                shell.show(view)
                info.show(view.space)
                assistant.place = AssistantModel.place(view)
                library.relist()
            }
            view.made = assistant.made.contains(name)
            view.journaled = { [weak self] in self?.info.show(self?.current?.space) }
            view.unkept = { [weak self] in self?.assistant.unkept = true }
            current = view
            // Blank behind the rights sheet, which the first load may show before the page runs.
            shell.show(view)
            view.open()
        } catch {
            shell.show(nil)
            ask.tell(error.sentence)
        }
    }

    /// The requests waiting: all of them in the toolbar's chip, as in the Dock, and the open space's own on its sticker.
    func counted() {
        shell.waiting(panels.queue.waiting.count, mine: current.map { panels.queue.count(in: $0.space.name) } ?? 0)
    }

    /// Who asks in the panel: the agent, and the title of the space its request belongs to.
    func who(_ request: Request) -> Asker {
        let space = panels.queue.space(request).map { library.entry($0)?.title ?? $0 }
        return App.who(engine.state.agents.first { $0.id == request.agent }, space: space, home: places.home.path,
                       assistant: engine.assistants.contains(request.agent), building: assistant.id == request.agent && !assistant.asking)
    }

    /// `agent` in the panel's words, "An agent" when the state no longer holds it: pre-allowed only as an assistant launched
    /// without Ask Before Every Change (`building`) whose builder is; named unless the assistant; its folder with ~.
    static func who(_ agent: Agent?, space: String?, home: String, assistant: Bool = false, building: Bool = false) -> Asker {
        guard let agent else { return Asker(program: "An agent", space: space) }
        return Asker(program: Registry.app.name(of: agent.kind), space: space, assistant: assistant,
                     preAllowed: assistant && building && Registry.app.agent(agent.kind)?.builder?.preAllowed == true,
                     name: assistant ? nil : agent.name, folder: agent.folder.map { Words.path($0, home: home) })
    }

    /// The engine may change many times a second; the open space hears of it at most every quarter of a second.
    func schedulePush() {
        guard !pushing else { return }
        pushing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.pushing = false
            self?.current?.push()
            self?.panels.refresh()
            self?.assistant.refresh()
        }
    }

    // MARK: Menus

    @objc func showAbout(_ sender: Any?) { NSApp.orderFrontStandardAboutPanel(options: Keys.about(.main)) }
    @objc func importSpace(_ sender: Any?) { library.importChosen() }
    @objc func exportSpace(_ sender: Any?) { current.map { library.export($0.space.name) } }
    @objc func showInFinder(_ sender: Any?) { current.map { library.showInFinder($0.space.name) } }
    @objc func reloadSpace(_ sender: Any?) { current?.load() }
    @objc func toggleInfo(_ sender: Any?) { shell.split.toggleInspector(sender) }
    @objc func showConversation(_ sender: Any?) { shell.toggleConversation(sender) }
    @objc func reduceAssistant(_ sender: Any?) { shell.reduceAssistant(sender) }

    /// Go ▸ a space (⌘1 to ⌘9 for the first nine).
    @objc func goToSpace(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        library.select(.space(name))
        front()
    }

    @objc func moveToTrash(_ sender: Any?) {
        if let entry = library.entry(current?.space.name) { confirmTrash(entry) }
    }

    @objc func askAssistant(_ sender: Any?) {
        front()
        assistant.focus()
    }
    @objc func stopAssistant(_ sender: Any?) { assistant.stop() }
    @objc func showRequest(_ sender: Any?) { panels.present(in: current?.space.name) }
    @objc func newConversation(_ sender: Any?) { assistant.newConversation() }
    @objc func chooseBuilder(_ sender: NSMenuItem) { (sender.representedObject as? String).map(assistant.choose) }
    /// Never sent: Build With only holds its submenu, and this selector lets validateMenuItem grey it.
    @objc func buildWith(_ sender: Any?) {}

    /// Build With ▸, made again each time it opens: the builders found (the agent menu of the capsule has the rest).
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items = AssistantModel.builderItems(assistant.entries)
        if menu.items.isEmpty { menu.addItem(NSMenuItem(title: "No coding agent found", action: nil, keyEquivalent: "")) }
    }

    /// Greyed, never hidden: Keys says when each command can act.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let id = item.identifier?.rawValue else { return true }
        let situation = Keys.Situation(space: current != nil, working: assistant.working, agent: !assistant.noAgent,
                                       touring: library.selection == .tour, editingText: shell.window.firstResponder is NSText,
                                       waiting: !panels.queue.waiting.isEmpty)
        return Keys.enabled(id, situation)
    }

    /// Shows `alert` as a sheet on the window; `then` runs when its first button is clicked.
    func sheet(_ alert: NSAlert, then: @escaping () -> Void) {
        shell.front()
        guard shell.window.attachedSheet == nil else { return }
        alert.beginSheetModal(for: shell.window) { if $0 == .alertFirstButtonReturn { then() } }
    }

    /// Asks in a sheet that says what goes with the space, then moves the space and its memory to the Trash.
    func confirmTrash(_ entry: Library.Entry) {
        shell.front()
        guard shell.window.attachedSheet == nil else { return }
        Ask.trash(entry, remembers: library.remembers(entry.id)).hang(on: shell.window) { [weak self] in
            if $0 == .destructive { self?.library.trash(entry.id) }
        }
    }

    // MARK: The window and quitting

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// A click on the Dock icon, or `something` typed again, shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { front() }
        return true
    }

    /// Asks first in an alert when a request waits or an agent something launched works, then denies the requests and
    /// stops every agent before quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let leaving = leaving()
        App.quit(leaving, source: engine, stop: { [engine] done in engine.stopAll(within: 5, done: done) }, confirm: { [shell] answer in
            shell.front()
            // A question left open is answered as its Cancel would be: Quit always asks, never does nothing.
            Shell.endSheets(of: shell.window)
            Ask.quit(leaving).hang(on: shell.window) { answer($0 == .secondary) }
        }, reply: { NSApp.reply(toApplicationShouldTerminate: $0) })
        return .terminateLater
    }

    /// What quitting ends now, from the app's own sources.
    func leaving() -> Leaving {
        App.leaving(agents: engine.state.agents, threads: engine.state.threads, waiting: panels.queue.waiting, who: who) { agent in
            RequestQueue.space(of: agent.id, assistant: self.engine.assistants.contains(agent.id), place: self.assistant.place,
                               launches: self.launches.ids).map { self.library.entry($0)?.title ?? $0 }
        }
    }

    /// What quitting ends: the requests `waiting`, oldest first, each named as the panel names it (`who`); then the
    /// agents something launched that are alive, work and wait for nothing, each by its space's title (`space`) and
    /// what its conversation in `threads` says it is doing.
    static func leaving(agents: [Agent], threads: [AgentThread] = [], waiting: [Request], who: (Request) -> Asker,
                        space: (Agent) -> String?) -> Leaving {
        let working = agents.filter { agent in
            agent.origin == "launched" && agent.alive == true && agent.state == "working" && !waiting.contains { $0.agent == agent.id }
        }
        return Leaving(requests: waiting.map { let who = who($0); return Leaving.Row(id: $0.id, space: who.space, program: who.program) },
                       working: working.map { agent in
                           Leaving.Row(id: agent.id, space: space(agent), program: Registry.app.name(of: agent.kind),
                                       doing: Words.doing(threads.first { $0.agent == agent.id }))
                       })
    }

    /// Quitting: when `leaving` holds anything, `confirm` asks the person first. Then each request waiting is denied,
    /// in so many words, before `stop` ends every agent, and `reply` gets true; or it gets false at once when the
    /// person keeps the app. Nothing is asked when nothing waits or works: idle agents are stopped without a word.
    static func quit(_ leaving: Leaving, source: PromptSource, stop: @escaping (@escaping () -> Void) -> Void,
                     confirm: (@escaping (Bool) -> Void) -> Void, reply: @escaping (Bool) -> Void) {
        let end = {
            // An agent stopped while it waits would never hear the answer: it hears a no, never a yes.
            for request in leaving.requests { try? source.answer(request.id, .deny) }
            stop { reply(true) }
        }
        guard !leaving.isEmpty else { return end() }
        confirm { $0 ? end() : reply(false) }
    }

    /// Ends the app at its start, before any agent was launched: in a sheet, which is all a person sees when the app
    /// was not started from a terminal, and on standard error. Later failures go through `ask.tell`, never here, so
    /// that quitting always stops the agents.
    func fail(_ message: String) -> Never {
        ask.tell(message)
        exit(1)
    }
}

/// What quitting ends: the requests waiting, which it denies, and the agents at work, which it stops. A row is a
/// request's id or an agent's, the title of its space (nil when none is known), its program's name and, for an agent,
/// what it is doing.
struct Leaving: Equatable {
    struct Row: Equatable { var id: String, space: String?, program: String, doing = "working" }
    var requests: [Row] = [], working: [Row] = []
    var isEmpty: Bool { requests.isEmpty && working.isEmpty }
}

/// The agents each space launched or resumed, by space name, for the app's whole life: an agent outlives the opening
/// of the space that launched it, and that space, opened again, still sees and drives it.
final class Launches {
    var ids: [String: Set<String>] = [:]
}
