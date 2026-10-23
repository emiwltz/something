// Registry: the agents one build of something knows, as the app lists them (Sources/something/Extensions.swift), and
// what follows from their descriptors: which kinds a space's rights may name, which values a launch takes, which
// modes make an agent ask less, the builders and their order. Built once by the app and handed to the engine; the
// checks are the same for the app's windows and for `something check`, which has no engine.
import Foundation
import SomethingCore

public struct Registry: Sendable {
    /// The agents, in the order of the state's kinds and of the builders offered.
    public let agents: [AgentDescriptor]
    /// What something can launch, by kind: what each driver can do, and how to make one.
    package let launchable: [String: Driving]
    /// The kinds a space's rights may name: those with a driver, and the other known ones, which something only reads.
    public let kinds: Kinds
    /// The program names of coding agents something has no extension for, seen from their process only (OtherReader).
    public let others: Set<String>

    public init(_ agents: [AgentDescriptor], others: Set<String> = []) {
        self.agents = agents
        self.others = others
        launchable = Dictionary(uniqueKeysWithValues: agents.compactMap(\.driving).map { ($0.kind, $0) })
        kinds = Kinds(launchable: Set(launchable.keys), readOnly: Set(agents.map(\.kind)).subtracting(launchable.keys))
    }

    /// The descriptor of `kind`; nil for a kind this build does not know.
    public func agent(_ kind: String) -> AgentDescriptor? { agents.first { $0.kind == kind } }

    /// The name a person knows the agent `kind` by, in every window and sentence; the kind itself when unknown.
    public func name(of kind: String) -> String { agent(kind)?.name ?? kind }

    /// The agents that can build spaces with the person, in the order they are offered.
    public var builders: [AgentDescriptor] { agents.filter { $0.builder != nil } }

    /// The readers of every agent's files, for the environment something runs in, then the one for `others`.
    func readers(_ environment: [String: String]) -> [Reader] {
        agents.compactMap { $0.reader?(environment) } + [OtherReader(names: others)]
    }

    /// The kinds whose conversations seen elsewhere can be continued here.
    var resumable: Set<String> { Set(agents.filter { $0.resume != .never }.map(\.kind)) }

    /// Whether a conversation seen elsewhere can be continued here, and why not, as its kind's `resume` says: only one
    /// no process holds, since one still held would get a second writer; for an agent that refuses a second writer
    /// itself (Codex), also one whose holder is unknown.
    func continuable(_ kind: String, alive: Bool?, pid: Int?) -> (Bool, String?) {
        let name = name(of: kind), resume = agent(kind)?.resume ?? .never
        guard resume != .never else { return (false, "something cannot continue \(name) conversations started elsewhere yet.") }
        switch alive {
        case true?: return (false, "\(name) still runs this conversation\(pid.map { " (pid \($0))" } ?? ""). Quit it there first.")
        case false?: return (true, nil)
        case nil:
            return resume == .unlessKnownHeld ? (true, nil) : (false, "something cannot tell whether \(name) still runs this conversation, so it cannot continue it here.")
        }
    }

    /// What the driver of `kind` can do. Throws NOT_SUPPORTED for a kind without a driver.
    func driving(_ kind: String) throws -> Driving {
        guard let driving = launchable[kind] else {
            throw CodedError("NOT_SUPPORTED", agent(kind)?.unavailable ?? "something cannot launch \(name(of: kind)) yet.")
        }
        return driving
    }

    /// Per kind, the `can` entries that are always false here: `granted.limits`. A kind without any is left out.
    public var limits: [String: [String]] { launchable.mapValues { $0.limits.keys.sorted() }.filter { !$0.value.isEmpty } }

    /// Whether choosing `mode` for an agent of `kind` makes it ask the person less than its default, so that the app
    /// asks the person first. Every mode is taken as one that lowers asking, but those known to ask
    /// as much or more: a mode something does not know (an OpenCode agent the person wrote, a kind without a driver)
    /// is confirmed rather than guessed. Throws VALUE_NOT_OFFERED, before any window, for a mode the kind never
    /// offers here: Claude's and Codex's modes are their drivers' lists (never `bypassPermissions`), while OpenCode's
    /// are its agents, which only the agent lists (the bridge checks a `set` against its options).
    public func lowersAsking(mode: String, kind: String) throws -> Bool {
        if let driving = launchable[kind], !driving.listsMoreModes, !driving.modes.isEmpty, !driving.modes.contains(where: { $0.value == mode }) {
            throw CodedError("VALUE_NOT_OFFERED", "\(mode) is not a mode something offers for \(kind); pick one from options.mode in the state.")
        }
        return !(agent(kind)?.asksAsMuch ?? []).contains(mode)
    }

    /// Returns when a launch of `kind` with these values can be tried; throws the error `launch` would give for them,
    /// before any program is looked for and before any window: NOT_SUPPORTED for a kind without a driver or a value
    /// its kind never takes, BAD_PARAMS for an empty model or effort or one that starts with "-", VALUE_NOT_OFFERED
    /// for a mode it does not offer (never one that skips every permission; OpenCode launches with build or plan).
    public func checkLaunch(_ kind: String, model: String?, mode: String?, effort: String?) throws {
        let driving = try driving(kind)
        for (key, value) in [("model", model), ("mode", mode), ("effort", effort)] where value != nil {
            if let because = driving.limits[key] { throw CodedError("NOT_SUPPORTED", because) }
        }
        if let model, model.isEmpty || model.hasPrefix("-") {
            throw CodedError("BAD_PARAMS", "model is a model's name, such as one of the agent's options.model.")
        }
        if let effort, effort.isEmpty || effort.hasPrefix("-") {
            throw CodedError("BAD_PARAMS", "effort is a level's name, such as one of the agent's options.effort.")
        }
        if let mode, !driving.modes.contains(where: { $0.value == mode }) {
            throw CodedError("VALUE_NOT_OFFERED", "\(mode) is not a mode something offers for \(kind); pick one of \(driving.modes.map(\.value).joined(separator: ", ")).")
        }
    }
}
