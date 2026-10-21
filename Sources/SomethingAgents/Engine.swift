// The engine: every agent on this Mac in one contract 1 State, and the hands on the ones something launched.
// The Mac app holds one Engine and talks to agents only through it. This file is the seam between the app and the
// agents: its public API is what the app may use. It drives the agents something launched (Claude Code, Codex,
// OpenCode and pi), on the main queue: each one's program through Spawn, its lines through its driver, its events folded by Launched.
// Agents started elsewhere come from the readers, through the watch; a conversation of one can be continued here.
import Foundation
import SomethingCore

public final class Engine {
    /// Called on the main queue when the state changed. The app decides how often it pushes.
    public var changed: () -> Void = {}

    /// The whole state before any space's scope, made once at each change and read many times a second, as of the read.
    public var state: State { var state = made; state.at = Engine.now(); return state }
    private lazy var made = make()

    /// `environment` is the one agents are started in: the terminal's when something was started from one,
    /// otherwise the app's own, and Programs then reads the login shell's PATH.
    public init(environment: [String: String]) {
        self.environment = environment
        programs = Programs(environment: environment)
    }

    /// The kinds something can launch, by their driver.
    static let drivers: [String: any Driver.Type] = ["claude": ClaudeDriver.self, "codex": CodexDriver.self, "opencode": ACPDriver.self,
                                                        "pi": PiDriver.self]

    private let environment: [String: String]
    /// Where programs are found; a test empties its system folders (`Engine.throwaway`).
    let programs: Programs
    /// Program lookups, one at a time off the main queue: reading the login shell's PATH can take seconds, and a
    /// launch's lookup waits behind the first look, whose shell read it then reuses.
    private let lookups = DispatchQueue(label: "something.programs")
    /// Whether each kind's program was found; empty until `start` looked (main queue only, as all that follows).
    private var installed: [String: Bool] = [:]
    /// The latest `lookFor` of each kind, which every launch or resume of that kind uses. Each bridge call looks
    /// again first, so it is never older than the call, and a launch that waited for the person still finds it.
    private var found: [String: Result<Program, any Error>] = [:]
    private var looked = false
    /// Whether a space is open, which sets the readers' cadence: every 2 s, else 10 s.
    private(set) var often = false
    /// The agents something launched, in launch order, with their program.
    private var launched: [(agent: Launched, spawn: Spawn)] = []
    /// The agents whose stop something asked for: their end is no failure.
    private var stopping: Set<String> = []
    private var count = 0
    /// The launched agents seen ended, in that order, with the time `clock` gave for their end (`forgetEnded`).
    private var ended: [(id: String, at: Date)] = []
    static let endedKept: TimeInterval = 600, endedMost = 20
    /// The clock of those ends; a test moves it.
    var clock: () -> Date = Date.init

    /// The agents started elsewhere: the readers, on their timer once `start` was called.
    lazy var watch = Watch(readers: Watch.readers(environment))
    /// What the watch saw last, before the dedupe.
    private var seen = Seen()
    /// The agents seen elsewhere as the state last showed them.
    private var outside: (agents: [Agent], threads: [AgentThread]) = ([], [])

    /// Starts watching this Mac: every 2 s while a space is open (`often`), 10 s otherwise, not at all while no window
    /// is `visible`, and at once when one is again. Called again, it only changes that: the programs are looked for once.
    public func start(often: Bool, visible: Bool = true) {
        self.often = often
        if visible {
            watch.start(every: often ? 2 : 10) { [weak self] seen in self?.saw(seen) }
        } else {
            watch.pause()
        }
        guard !looked else { return }
        looked = true
        lookAgain()
    }

    /// Looks for every kind's program again, off the main queue (the login shell can take 3 s); `installed` follows.
    public func lookAgain() {
        lookups.async { [self] in
            let found = Dictionary(uniqueKeysWithValues: Programs.kinds.compactMap { kind in programs.installed(kind).map { (kind, $0) } })
            DispatchQueue.main.async { [self] in installed = found; update() }
        }
    }

    /// Forgets the ended agents whose time is over, makes the state again and tells the app (internal: a test calls it).
    /// `outside` is the agents seen elsewhere when `saw` just built them; otherwise they are built here.
    func update(outside: (agents: [Agent], threads: [AgentThread])? = nil) {
        // An agent just forgotten may now be seen elsewhere: the agents seen elsewhere are then built again.
        if !forgetEnded(), let outside {
            self.outside = outside
        } else {
            self.outside = elsewhere
        }
        made = make()
        changed()
    }

    private func make() -> State {
        let kinds = Programs.kinds.map { kind in
            (kind, Kind(launch: Engine.drivers[kind] != nil, installed: installed[kind], tested: Engine.drivers[kind]?.tested ?? "none",
                        seen: seen.kinds[kind]?.version, reader: seen.kinds[kind]?.health ?? "none", note: seen.kinds[kind]?.note))
        }
        return State(at: Engine.now(), kinds: Dictionary(uniqueKeysWithValues: kinds), agents: launched.map(\.agent.agent) + outside.agents,
                     threads: launched.compactMap(\.agent.thread) + outside.threads, requests: launched.flatMap(\.agent.queue.fold.requests))
    }

    /// The agents the watch saw, but those something launched: the groups of its running children and the
    /// conversations its drivers reported are left out. An ended child's group is not: its pid may be
    /// reused by a program started by hand, and its conversation is still left out by its key. Every conversation in
    /// `assistantFolder` is left out too, whoever started it and when: it holds the person's words to their assistant.
    private var elsewhere: (agents: [Agent], threads: [AgentThread]) {
        let groups = Set(launched.filter(\.spawn.running).map(\.spawn.pid).filter { $0 > 0 })
        // A refused resume lists no thread (Launched.refused): its conversation is still the one seen elsewhere.
        let keys = launched.compactMap(\.agent.agent.thread)
        let real = HeldFiles.remembered(), mine = assistantFolder.map(real)
        let seen = Seen(sightings: seen.sightings.filter { mine == nil || $0.folder.map(real) != mine }, kinds: seen.kinds)
        return Watch.elsewhere(seen, groups: groups, keys: Set(keys), now: Date())
    }

    /// Takes one tick of the watch, on the main queue, and tells the app only when what it shows changed.
    func saw(_ seen: Seen) {
        let kinds = self.seen.kinds
        self.seen = seen
        let after = elsewhere
        if after.agents != outside.agents || after.threads != outside.threads || seen.kinds != kinds { update(outside: after) }
    }

    /// Drops from the state the launched agents ended `endedKept` seconds ago and the ended ones beyond the last
    /// `endedMost`, so that an app open all day does not push every agent it ever launched; a reader may then show their
    /// conversations as seen elsewhere. Nothing else may change the state by an end's time, so a timer makes it then.
    /// Returns whether it dropped any.
    private func forgetEnded() -> Bool {
        let now = clock()
        for entry in launched where entry.agent.agent.alive == false && !ended.contains(where: { $0.id == entry.agent.agent.id }) {
            ended.append((entry.agent.agent.id, now))
            DispatchQueue.main.asyncAfter(deadline: .now() + Engine.endedKept) { [weak self] in self?.update() }
        }
        let gone = Set(ended.enumerated().filter { $0.offset < ended.count - Engine.endedMost
            || now.timeIntervalSince($0.element.at) >= Engine.endedKept }.map(\.element.id))
        guard !gone.isEmpty else { return false }
        launched.removeAll { gone.contains($0.agent.agent.id) }
        stopping.subtract(gone)
        ended.removeAll { gone.contains($0.id) }
        return true
    }

    /// Per kind, the `can` entries that are always false here: `granted.limits`. A kind without any is left out.
    /// Static, so that `something check` gives the same without an engine.
    public static var limits: [String: [String]] { drivers.mapValues { $0.limits.keys.sorted() }.filter { !$0.value.isEmpty } }

    /// Whether choosing `mode` for an agent of `kind` makes it ask the person less than its default, so that the app
    /// asks the person first. Every mode is taken as one that lowers asking, but those known to ask
    /// as much or more: a mode something does not know (an OpenCode agent the person wrote, a kind without a driver)
    /// is confirmed rather than guessed. Throws VALUE_NOT_OFFERED, before any window, for a mode the kind never
    /// offers here: Claude's and Codex's modes are their drivers' lists (never `bypassPermissions`), while OpenCode's
    /// are its agents, which only the agent lists (the bridge checks a `set` against its options).
    public static func lowersAsking(mode: String, kind: String) throws -> Bool {
        if let type = drivers[kind], !(type is ACPDriver.Type), !type.modes.isEmpty, !type.modes.contains(where: { $0.value == mode }) {
            throw CodedError("VALUE_NOT_OFFERED", "\(mode) is not a mode something offers for \(kind); pick one from options.mode in the state.")
        }
        return !(asksAsMuch[kind] ?? []).contains(mode)
    }

    /// Returns when a launch of `kind` with these values can be tried; throws the error `launch` would give for them,
    /// before any program is looked for and before any window: NOT_SUPPORTED for a kind without a driver or a value
    /// its kind never takes, BAD_PARAMS for an empty model or effort or one that starts with "-", VALUE_NOT_OFFERED
    /// for a mode it does not offer (never one that skips every permission; OpenCode launches with build or plan).
    /// Static, so that `something check` answers as the app does.
    public static func checkLaunch(_ kind: String, model: String?, mode: String?, effort: String?) throws {
        guard let type = drivers[kind] else { throw CodedError("NOT_SUPPORTED", "something cannot launch \(kind) yet.") }
        for (key, value) in [("model", model), ("mode", mode), ("effort", effort)] where value != nil {
            if let because = type.limits[key] { throw CodedError("NOT_SUPPORTED", because) }
        }
        if let model, model.isEmpty || model.hasPrefix("-") {
            throw CodedError("BAD_PARAMS", "model is a model's name, such as one of the agent's options.model.")
        }
        if let effort, effort.isEmpty || effort.hasPrefix("-") {
            throw CodedError("BAD_PARAMS", "effort is a level's name, such as one of the agent's options.effort.")
        }
        if let mode, !type.modes.contains(where: { $0.value == mode }) {
            throw CodedError("VALUE_NOT_OFFERED", "\(mode) is not a mode something offers for \(kind); pick one of \(type.modes.map(\.value).joined(separator: ", ")).")
        }
    }

    /// Per kind, the modes known to ask no less than the default (`AgentDescriptor.asksAsMuch`); a kind without any is
    /// left out, so any mode for it counts as lowering asking.
    static let asksAsMuch = Dictionary(uniqueKeysWithValues: AgentDescriptor.all.filter { !$0.asksAsMuch.isEmpty }.map { ($0.kind, $0.asksAsMuch) })

    /// The details of an open request, or nil once it closed (the app then closes its window).
    public func prompt(_ request: String) -> Prompt? { launched.lazy.compactMap { $0.agent.prompt(request) }.first }

    /// The person's answer, from a native window; a request that closed meanwhile is left as it is. Throws the driver's
    /// error for an answer that does not fit, and AGENT_STOPPED, in words for the person, when the agent no longer reads.
    public func answer(_ request: String, _ answer: Answer) throws {
        guard let agent = launched.first(where: { $0.agent.prompt(request) != nil })?.agent else { return }
        do { _ = try agent.answer(request, answer) } catch let error as CodedError where error.code == "AGENT_STOPPED" {
            throw CodedError("AGENT_STOPPED", "\(Programs.name(of: agent.agent.kind)) did not receive your answer: it stopped listening.")
        }
    }

    // What a space asks through the bridge (SomethingCore/Bridge.swift checked the call first). Each throws a
    // `CodedError` with a bridge code of contract 1.

    /// Returns the delivery: "started", "steered" or "queued". Throws AGENT_NOT_FOUND, AGENT_STOPPED (also once its
    /// stop was asked), BAD_PARAMS.
    public func deliver(_ text: String, to agent: String, when: String) throws -> String {
        // A message during the stop would open a turn after the stop's interrupt, and the input would close in it.
        let found = try running(agent)
        guard !stopping.contains(agent) else { throw CodedError("AGENT_STOPPED", "The agent is stopping; launch or resume it to go on.") }
        return try found.send(text, when: when)
    }

    /// Returns whether a turn was running; the queue is emptied either way. Throws AGENT_NOT_FOUND, AGENT_STOPPED.
    public func interrupt(_ agent: String) throws -> Bool { try running(agent).interrupt() }

    /// Returns "now" or "next-turn". Throws AGENT_NOT_FOUND, AGENT_STOPPED, NOT_SUPPORTED.
    public func set(_ agent: String, model: String?, mode: String?, effort: String?) throws -> String {
        let applied = try running(agent).driver.set(model: model, mode: mode, effort: effort)
        update()
        return applied
    }

    /// Looks for the program of `kind` off the main queue, then calls `then` on the main queue. The launches and
    /// resumes of `kind` that follow use what was found, so that they never read the login shell's PATH on the main
    /// queue, where the whole app would freeze for seconds. A kind never looked for is looked for by its launch.
    public func lookFor(_ kind: String, then: @escaping () -> Void) {
        lookups.async { [self] in
            let result = Result { try programs.find(kind) }
            DispatchQueue.main.async { [self] in found[kind] = result; then() }
        }
    }

    /// Starts an agent of `kind` in `folder` and returns its id. Throws as `checkLaunch` does, then NOT_INSTALLED,
    /// INTERPRETER_NOT_FOUND, LAUNCH_FAILED. Called after `lookFor(kind)`, it does not wait for the login shell.
    public func launch(_ kind: String, folder: String, model: String?, mode: String?, effort: String?) throws -> String {
        try Engine.checkLaunch(kind, model: model, mode: mode, effort: effort)
        return try launch(Engine.drivers[kind]!, folder: folder, model: model, mode: mode, effort: effort, planB: false)
    }

    /// The words Claude Code's plan-B hook runs, before `--spool <dir>`: a program, by its absolute path, whose
    /// `hook permission` runs `SpoolHook.main`. Nil until its owner sets it (the app and `something try` set
    /// `ownHookCommand`), and plan B is then not offered. Its folder comes first in the assistant's PATH, so that the
    /// `something` the assistant runs is this one, the one its rules allow.
    public var hookCommand: [String]?

    /// This program as `hookCommand`, for a program whose main routes `hook permission`; nil when its path is unknown.
    public static var ownHookCommand: [String]? { Bundle.main.executableURL.map { [$0.resolvingSymlinksInPath().path, "hook", "permission"] } }

    /// Where plan B's spool folders go; a test's own folder in tests.
    var spools = Spool.root

    /// Every agent launched as the person's assistant (`launchAssistant`), which no space may write to or read.
    public private(set) var assistants: Set<String> = []
    /// The assistant's folder, the spaces folder, which the app sets once before any reading: no conversation there,
    /// from this run, an earlier one or a terminal, is ever shown as seen elsewhere (`elsewhere`).
    public var assistantFolder: String?

    /// Starts the person's assistant, an agent of `kind` working in `folder` (the spaces folder, its links resolved,
    /// since Claude matches its rules against real paths), and returns its id, which `assistants` holds from then on.
    /// Its driver lets it build spaces without asking, and offers it `lent`, unless `askEverything`. Only the app calls
    /// this: a space launches through `launch`, which never makes an assistant. Throws as `launch`.
    public func launchAssistant(_ kind: String, folder: String, askEverything: Bool, lent: Lent? = nil) throws -> String {
        try Engine.checkLaunch(kind, model: nil, mode: nil, effort: nil)
        return try launch(Engine.drivers[kind]!, folder: HeldFiles.real(folder), model: nil, mode: nil, effort: nil, planB: false,
                          assistant: askEverything ? .askingEverything : .building, lent: askEverything ? nil : lent)
    }

    /// `launch` above, with plan B forced for Claude (`something try --plan-b`) and every line given to `record`.
    /// With `resume`, the program continues that conversation in `folder`; a pi conversation is its file, which must
    /// exist (THREAD_NOT_FOUND), and runs in the folder its header names.
    /// With `assistant`, the launch is the person's assistant, working that way, and offered `lent`.
    func launch(_ type: any Driver.Type, folder: String, model: String?, mode: String?, effort: String?, planB: Bool,
                resume: String? = nil, assistant: Assistant? = nil, lent: Lent? = nil,
                record: ((_ written: Bool, _ line: Data) -> Void)? = nil) throws -> String {
        // A resumed pi runs in its conversation's own folder, whatever folder it is started in: the state shows that one.
        let folder = try resume.map { type is PiDriver.Type ? try PiDriver.resumable($0) : folder } ?? folder
        let program = try found[type.kind]?.get() ?? programs.find(type.kind)
        count += 1
        var launch = Launch(agent: "\(type.kind)-\(count)", folder: folder, model: model, mode: mode, effort: effort)
        if let resume { (launch.thread, launch.resume) = (resume, true) }
        (launch.assistant, launch.lent) = (assistant, assistant == nil ? nil : lent)
        let started = try start(type, launch, program, planB: planB, record: record)
        // Marked before the state changes, so that no space ever sees the assistant as one it may write to.
        if assistant != nil { assistants.insert(launch.agent) }
        launched.append(started)
        update()
        return launch.agent
    }

    /// Starts one launch of `program` and joins it to its driver and, for Claude's plan B, to its spool. A Claude that
    /// refuses plan A is launched again with plan B, under the same agent id and a new conversation id (the same one
    /// for a resume).
    private func start(_ type: any Driver.Type, _ launch: Launch, _ program: Program, planB: Bool,
                       record: ((Bool, Data) -> Void)?) throws -> (agent: Launched, spawn: Spawn) {
        let spool = planB && type is ClaudeDriver.Type ? PermissionSpool(folder: (spools as NSString).appendingPathComponent("\(launch.agent)-\(launch.thread)")) : nil
        guard spool == nil || hookCommand != nil else { throw CodedError("LAUNCH_FAILED", "Plan B needs something's own program to answer Claude Code's permission requests, and this launch does not know it; launch Claude Code from the something app.") }
        let first = launch.assistant == nil ? nil : hookCommand?.first.map { ($0 as NSString).deletingLastPathComponent }
        let command = spool.map { ClaudeDriver.command(launch, hook: hookCommand! + ["--spool", $0.folder]) } ?? type.command(launch)
        let spawn = Spawn(path: program.path, arguments: command.arguments, folder: launch.folder,
                          environment: program.environment(environment, adding: command.adding, removing: command.removing, first: first))
        let agent = try Engine.start(type, launch, spawn, spool: spool, asked: { [weak self] id in self?.stopping.contains(id) == true }, record: record)
        agent.changed = { [weak self] in self?.update() }
        if !planB, hookCommand != nil, let claude = agent.driver as? ClaudeDriver {
            claude.fallback = { [weak self, weak spawn] in
                guard let self, let spawn, let index = launched.firstIndex(where: { $0.spawn === spawn }) else { return false }
                var again = launch
                // A resume continues the same conversation with plan B.
                if !launch.resume { again.thread = UUID().uuidString.lowercased() }
                guard let started = try? start(type, again, program, planB: true, record: record) else { return false }
                // The first program's end now reaches a Launched no longer listed: it changes nothing.
                spawn.stop()
                launched[index] = started
                update()
                return true
            }
        }
        return (agent, spawn)
    }

    /// Continues here the conversation `thread` of `agent`, an agent seen elsewhere, in the conversation's own folder,
    /// and returns the id of the agent launched for it, which lists it from then on. Throws THREAD_NOT_FOUND when no
    /// agent seen now holds that conversation, STILL_RUNNING while its process runs, NOT_SUPPORTED when it cannot be
    /// continued here, then as `launch` does. Codex's background service holding the conversation comes after the
    /// launch, as the agent's HELD_ELSEWHERE error.
    public func resume(_ kind: String, thread: String, of agent: String) throws -> String {
        guard let seen = elsewhere.agents.first(where: { $0.id == agent && $0.kind == kind && $0.thread == thread }), let folder = seen.folder else {
            throw CodedError("THREAD_NOT_FOUND", "No \(Programs.name(of: kind)) conversation \(thread) is seen on this Mac now; use a thread id from the latest state.")
        }
        guard seen.can.resume, let type = Engine.drivers[kind] else {
            throw CodedError(seen.alive == true ? "STILL_RUNNING" : "NOT_SUPPORTED", seen.because["resume"] ?? "This conversation cannot be continued here.")
        }
        return try launch(type, folder: folder, model: nil, mode: nil, effort: nil, planB: false, resume: thread)
    }

    /// Stops every agent something launched, or only `only`, all at once, within `seconds`, then calls `done` on the main queue.
    public func stopAll(within seconds: TimeInterval, only: String? = nil, done: @escaping () -> Void) {
        let chosen = launched.filter { only == nil || $0.agent.agent.id == only }
        stopping.formUnion(chosen.map(\.agent.agent.id))
        Spawn.stopAll(chosen.map(\.spawn), cap: seconds) { DispatchQueue.main.async(execute: done) }
    }

    /// The launched agent `id`, while its program runs.
    private func running(_ id: String) throws -> Launched {
        guard let found = launched.first(where: { $0.agent.agent.id == id }) else {
            throw CodedError("AGENT_NOT_FOUND", "No agent \(id) was launched by something; use an id from the latest state.")
        }
        guard found.agent.agent.alive != false else { throw CodedError("AGENT_STOPPED", "The agent has ended; launch or resume it to go on.") }
        return found.agent
    }

    static func now() -> String { iso8601.string(from: Date()) }
}
