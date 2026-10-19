// The Mac app: one Engine and one window (Shell.swift) with the spaces (Library.swift), the open space (SpaceView.swift),
// Info (Inspector.swift) and the assistant (Assistant.swift); the spaces and exports LaunchServices hands it; the
// permission and question panels; the state pushed at most four times a second; and quitting, which asks first while
// agents something launched run, then stops them. Closing the window keeps the app and its agents running, as a Mac app
// with one main window does; the open space closes with it, and opens again when the window comes back.
import AppKit
import SomethingAgents
import SomethingCore
import WebKit

final class App: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    /// The space named on the command line, or the path of an export; nil to open the last space open.
    let opening: String?
    let places = Places.person
    let engine = Engine(environment: ProcessInfo.processInfo.environment)
    let ask = NativeAsk()
    let launches = Launches()
    lazy var library = Library(places: places, ask: ask)
    lazy var info = Info(places: places, ask: ask)
    lazy var assistant = AssistantModel(engine: engine, places: places)
    lazy var shell = Shell(library: library, info: info, assistant: assistant, autosave: true)
    lazy var panels = Panels(source: engine)
    /// The open space. One at a time: opening another closes it.
    var current: SpaceView?
    var pushing = false
    /// Lockdown's rule list, compiled before the first space opens.
    var rules: WKContentRuleList?
    /// What LaunchServices handed the app before it was ready to open anything; nil once it is.
    var handed: [URL]? = []

    init(opening: String?) {
        self.opening = opening
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Shell.menu()
        ask.window = { [weak self] in self?.shell.window }
        library.opened = { [weak self] name in self?.open(name) }
        library.trashing = { [weak self] entry in self?.confirmTrash(entry) }
        info.current = { [weak self] in self?.current }
        info.agents = { [weak self] in self?.engine.state.agents ?? [] }
        info.reveal = { [weak self] in self?.library.showInFinder($0) }
        // The space stays selected, so that it opens again with the window.
        shell.closed = { [weak self] in self?.open(nil) }
        panels.who = { [weak self] request in self?.who(request) ?? Asker(program: "An agent", line: "") }
        engine.changed = { [weak self] in self?.schedulePush() }
        // This program's main routes `something hook permission`, inside the .app and under `swift run` alike.
        engine.hookCommand = Engine.ownHookCommand
        assistant.confirmSwitch = { [weak self] from, to, switched in self?.sheet(Ask.switching(from: from, to: to), then: switched) }
        assistant.howTo = { [weak self] in
            guard let self else { return }
            sheet(Ask.howToGetOne(copy: assistant.copy)) { [weak self] in self?.engine.lookAgain() }
        }
        assistant.showRequest = { [weak self] in self?.panels.panel?.orderFrontRegardless() }
        library.relisted = { [weak self] in
            guard let self, let new = assistant.appeared(library.entries, open: library.selection) else { return }
            library.select(new)
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
            library.watch()
            let early = handed ?? []
            handed = nil
            if let opening, (opening as NSString).pathExtension == "something" {
                receive(URL(fileURLWithPath: opening).standardizedFileURL)
            } else if let opening {
                guard library.entry(opening) != nil else {
                    return ask.tell("There is no space \(opening) in \(places.spaces.path). Type something new \(opening) to make it.")
                }
                library.select(opening)
            } else if !early.isEmpty {
                early.forEach(receive)
            } else {
                library.select(library.last())
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
        let name = url.pathExtension == "html" ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
        let real = { (url: URL) in url.resolvingSymlinksInPath().path }
        guard let space = Spaces(root: places.spaces).named(name), real(space.location) == real(url) else {
            shell.front()
            return ask.tell(Command.elsewhere(name))
        }
        library.relist()
        library.select(space.name)
        front()
    }

    /// Shows the window; the space open when it was closed opens again.
    func front() {
        shell.front()
        if current == nil, let name = library.selection { open(name) }
    }

    /// Closes the open space and opens the space `name` in the center; nil leaves the center empty. The space already
    /// open stays as it is.
    func open(_ name: String?) {
        if let name, current?.space.name == name { return }
        current?.close()
        current = nil
        assistant.fault = nil
        assistant.unkept = false
        defer {
            assistant.place = AssistantModel.place(current)
            info.show(current?.space)
            // The readers look often while a space is open, and rarely when nobody is looking.
            engine.start(often: current != nil)
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
            view.journaled = { [weak self] in self?.info.show(self?.current?.space) }
            view.unkept = { [weak self] in self?.assistant.unkept = true }
            view.faulted = { [weak self, weak view] in
                guard let self, let view, current === view else { return }
                assistant.fault = AssistantModel.Fault(title: view.title, name: view.space.name, codes: view.faults)
            }
            current = view
            // Blank behind the rights sheet, which the first load may show before the page runs.
            shell.show(view)
            view.open()
        } catch {
            shell.show(nil)
            ask.tell(error.sentence)
        }
    }

    /// Who asks in a panel: the agent's program, its name, the space that started it when one did, and its folder.
    func who(_ request: Request) -> Asker {
        let starter = launches.ids.first { $0.value.contains(request.agent) }.map { library.entry($0.key)?.title ?? $0.key }
        return App.who(engine.state.agents.first { $0.id == request.agent }, startedBy: starter, home: places.home.path,
                       assistant: engine.assistants.contains(request.agent))
    }

    /// `agent` in a panel's words ("Claude Code" / "“shop”, started by “My agents”, working in ~/code/shop"), with the
    /// title of the space that started it when one did; "Your assistant, working in ~/something/spaces" for the
    /// person's assistant; "An agent" when the state no longer holds it.
    static func who(_ agent: Agent?, startedBy space: String?, home: String, assistant: Bool = false) -> Asker {
        guard let agent else { return Asker(program: "An agent", line: "") }
        if assistant {
            return Asker(program: Programs.name(of: agent.kind), line: "Your assistant, working in " + Words.path(agent.folder ?? "", home: home))
        }
        let parts = [agent.name.map { "“\($0)”" }, space.map { "started by “\($0)”" },
                     agent.folder.map { "working in " + Words.path($0, home: home) }].compactMap { $0 }
        let line = parts.joined(separator: ", ")
        return Asker(program: Programs.name(of: agent.kind), line: line.prefix(1).uppercased() + line.dropFirst())
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

    @objc func importSpace(_ sender: Any?) { library.importChosen() }
    @objc func exportSpace(_ sender: Any?) { current.map { library.export($0.space.name) } }
    @objc func showInFinder(_ sender: Any?) { current.map { library.showInFinder($0.space.name) } }
    @objc func reloadSpace(_ sender: Any?) { current?.load() }

    @objc func moveToTrash(_ sender: Any?) {
        if let entry = library.entry(current?.space.name) { confirmTrash(entry) }
    }

    @objc func askAssistant(_ sender: Any?) {
        front()
        assistant.focus()
    }
    @objc func stopAssistant(_ sender: Any?) { assistant.stop() }
    @objc func newConversation(_ sender: Any?) { assistant.newConversation() }
    @objc func chooseBuilder(_ sender: NSMenuItem) { (sender.representedObject as? String).map(assistant.choose) }

    /// Build With ▸, made again each time it opens: the builders found (the agent menu of the capsule has the rest).
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for entry in assistant.entries {
            let item = NSMenuItem(title: entry.title, action: entry.enabled ? #selector(chooseBuilder) : nil, keyEquivalent: "")
            (item.representedObject, item.state, item.toolTip) = (entry.id, entry.checked ? .on : .off, entry.note)
            menu.addItem(item)
        }
        if menu.items.isEmpty { menu.addItem(NSMenuItem(title: "No coding agent found", action: nil, keyEquivalent: "")) }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(stopAssistant) { return [.working, .waiting].contains(assistant.light) }
        if item.action == #selector(askAssistant) { return !assistant.noAgent }
        return [#selector(exportSpace), #selector(showInFinder), #selector(reloadSpace), #selector(moveToTrash)].contains(item.action)
            ? current != nil : true
    }

    /// Shows `alert` as a sheet on the window; `then` runs when its first button is clicked.
    func sheet(_ alert: NSAlert, then: @escaping () -> Void) {
        shell.front()
        guard shell.window.attachedSheet == nil else { return }
        alert.beginSheetModal(for: shell.window) { if $0 == .alertFirstButtonReturn { then() } }
    }

    /// Asks in a sheet, then moves the space and its memory to the Trash.
    func confirmTrash(_ entry: Library.Entry) {
        sheet(Ask.trash(entry.title)) { [weak self] in self?.library.trash(entry.id) }
    }

    // MARK: The window and quitting

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// A click on the Dock icon, or `something` typed again, shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { front() }
        return true
    }

    /// Asks first in a sheet when agents something launched still run, then stops them all before quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let alive = engine.state.agents.filter { $0.origin == "launched" && $0.alive == true }
        let running = alive.count
        let stop = { [engine] in engine.stopAll(within: 5) { NSApp.reply(toApplicationShouldTerminate: true) } }
        guard running > 0 else {
            stop()
            return .terminateLater
        }
        shell.front()
        // A question left open is answered as its Cancel would be: Quit always asks, never does nothing.
        Shell.endSheets(of: shell.window)
        Ask.quit(running, assistant: alive.contains { engine.assistants.contains($0.id) }).beginSheetModal(for: shell.window) { answer in
            if answer == .alertFirstButtonReturn { stop() } else { NSApp.reply(toApplicationShouldTerminate: false) }
        }
        return .terminateLater
    }

    /// Ends the app at its start, before any agent was launched: in a sheet, which is all a person sees when the app
    /// was not started from a terminal, and on standard error. Later failures go through `ask.tell`, never here, so
    /// that quitting always stops the agents.
    func fail(_ message: String) -> Never {
        ask.tell(message)
        exit(1)
    }
}

/// The agents each space launched or resumed, by space name, for the app's whole life: an agent outlives the opening
/// of the space that launched it, and that space, opened again, still sees and drives it.
final class Launches {
    var ids: [String: Set<String>] = [:]
}
