// Extension: what something knows of each agent, written once as data. The tables the engine, the programs, the
// watch and the app's windows used to keep apart (kinds, names, install sentences, modes that ask as much, which
// conversations continue here, the builders, the words of tools and modes) are computed from these descriptors, so
// that knowing one more agent is one more descriptor. For a kind something launches, its Driving says what its
// driver can do and makes one. Each agent's descriptor, Driving, driver and reader live in its own target (Agent*);
// this host names none of them.
import Foundation
import SomethingCore

/// What something knows of one agent, besides its driver and its reader. Pure data: building one does no I/O.
public struct AgentDescriptor: Sendable {
    /// The contract's word for it, which is also the file name of its program: "claude".
    public var kind: String
    /// The name a person knows it by, in every window and sentence: "Claude Code".
    public var name: String
    /// What to type in Terminal to install it; nil for a kind something does not launch.
    public var install: String?
    /// An interpreter its program needs that the program's first line does not name.
    package var runsOn: String?
    /// Folders under the home where its installer puts it, which a shell's PATH may lack. They are looked in for
    /// every program, after the shared installers' folders and before `.volta/bin`, the order of 0.2.
    package var homeFolders: [String]
    /// A folder under the data folder (`$XDG_DATA_HOME`, else `~/.local/share`) that its installer filled for it
    /// alone, which goes last on its PATH: pi's own node.
    package var bundled: String?
    /// Parts of a real path that make a copy of its program another app's own, never launched.
    package var refusedCopies: [String]
    /// The modes known to ask the person no less than its default, from its program's --help (17 October 2026); any
    /// mode not listed counts as asking less, which is safe.
    package var asksAsMuch: Set<String>
    /// When a conversation of it seen elsewhere can be continued here.
    package var resume: Resume
    /// How something launches and drives it; nil for a kind it only reads.
    package var driving: Driving?
    /// Makes the reader of its files, for the environment something runs in; nil for a kind seen by its process only.
    package var reader: (@Sendable (_ environment: [String: String]) -> any Reader)?
    /// How it builds spaces as the person's assistant; nil for a kind that cannot.
    public var builder: Builder?
    /// Whether, launched, it acts without ever asking the person: the rights sheet and the assistant say so.
    public var neverAsks: Bool
    /// Whether, launched as the person's own settings leave it by default, it acts without asking: the rights sheet
    /// and the assistant say so too, with "by default".
    public var asksNothingByDefault: Bool
    /// What its tools and requests do, by the name its driver gives them, for the permission panel's title.
    public var tools: [String: Tool]
    /// What each of its modes that lowers asking lets it do, in words that follow "a mode where it".
    public var modeWords: [String: String]

    package init(kind: String, name: String, install: String? = nil, runsOn: String? = nil, homeFolders: [String] = [],
                 bundled: String? = nil, refusedCopies: [String] = [], asksAsMuch: Set<String> = [], resume: Resume = .never,
                 driving: Driving? = nil, reader: (@Sendable ([String: String]) -> any Reader)? = nil, builder: Builder? = nil,
                 neverAsks: Bool = false, asksNothingByDefault: Bool = false, tools: [String: Tool] = [:], modeWords: [String: String] = [:]) {
        (self.kind, self.name, self.install, self.runsOn, self.homeFolders, self.bundled) = (kind, name, install, runsOn, homeFolders, bundled)
        (self.refusedCopies, self.asksAsMuch, self.resume, self.driving, self.reader) = (refusedCopies, asksAsMuch, resume, driving, reader)
        (self.builder, self.neverAsks, self.asksNothingByDefault) = (builder, neverAsks, asksNothingByDefault)
        (self.tools, self.modeWords) = (tools, modeWords)
    }

    /// What the person's assistant gets when it is this agent.
    public struct Builder: Sendable {
        /// Whether its driver pre-allows its building work (rule 2 of AGENTS.md), which Ask Before Every Change
        /// turns off; without it, it asks as its own settings say.
        public var preAllowed = false
        /// The commands something lends it as tools, on its own channel (Lent.swift).
        public var lent: [LentTool] = []

        package init(preAllowed: Bool = false, lent: [LentTool] = []) { (self.preAllowed, self.lent) = (preAllowed, lent) }
    }

    /// What a tool or a request does, as the permission panel says it.
    public enum Tool: Sendable { case command, file, permissions }

    package enum Resume: Equatable, Sendable {
        /// Never: something cannot continue its conversations started elsewhere.
        case never
        /// Only when no process is known to hold it: a second writer would break it.
        case whenNoneHolds
        /// Unless a process is known to hold it: the agent refuses a second writer itself and says so.
        case unlessKnownHeld
    }

    /// Whether its failure means the model's server refused its sign-in, which signing in again in Terminal cures:
    /// `status` is the HTTP status when there was one, `error` its error kind otherwise. False for a kind whose driver
    /// does not tell.
    public func refusesSignIn(status: Int?, error: String?) -> Bool { driving?.refusesSignIn?(status, error) ?? false }
}

/// What something knows of a kind it launches: what its driver can do, the program's arguments, and the driver itself.
/// The engine, Launched and `something check` read these; no driver is asked about itself.
package struct Driving: Sendable {
    /// Its descriptor's kind, which DescriptorsTests checks: one value names the agent a launch makes.
    package var kind: String
    /// The newest version of the program its driver was proven on (`kinds.<kind>.tested`).
    package var tested: String
    /// The `can` entries that are always false for this kind, each with its sentence (`because`, `granted.limits`).
    package var limits: [String: String]
    /// The modes a launch or `set` may choose; empty when the kind has none.
    package var modes: [Option]
    /// Whether `set` may also choose modes the agent lists itself, beyond `modes`: the bridge then checks a `set`
    /// against the agent's `options.mode`, after the person confirmed (Registry.lowersAsking).
    package var listsMoreModes: Bool
    /// Whether an effort can be set only when `options.effort` lists levels.
    package var effortOnlyWhenOffered: Bool
    /// Whether the launch picks the conversation id (`Launch.thread`) for the program. When false, the thread is
    /// unknown until the program names it, unless the launch resumes one.
    package var picksThread: Bool
    /// The folder a resume of a conversation runs in, when the conversation names it (pi's file header); nil: the
    /// folder asked. Throws THREAD_NOT_FOUND for a conversation that is not there.
    package var resumeFolder: (@Sendable (_ thread: String) throws -> String)?
    /// The program's arguments for a launch, and what it changes in the person's environment.
    package var command: @Sendable (Launch) -> Command
    /// The command of a launch that takes plan B (`Launch.planB`), for a kind that has one: Claude's permission
    /// hook. Throws LAUNCH_FAILED when the host lacks what it needs.
    package var planB: (@Sendable (Launch, HostFacts) throws -> Command)?
    /// Whether a failure its driver reported (`detail.apiRetry`: an HTTP status, else an error kind) means the
    /// model's server refused the sign-in; nil when its driver reports none (AgentDescriptor.refusesSignIn).
    package var refusesSignIn: (@Sendable (_ status: Int?, _ error: String?) -> Bool)?
    /// Makes the driver of one launch. `write` hands one whole line (without its newline) to the program and throws
    /// AGENT_STOPPED once it no longer reads; `emit` takes what happened; `now` is the time of each item and request
    /// (ISO 8601).
    package var driver: @Sendable (_ launch: Launch, _ write: @escaping (Data) throws -> Void, _ emit: @escaping (AgentEvent) -> Void,
                                   _ now: @escaping () -> String) -> any Driver

    package init(kind: String, tested: String, limits: [String: String] = [:], modes: [Option] = [], listsMoreModes: Bool = false,
                 effortOnlyWhenOffered: Bool = false, picksThread: Bool = true, resumeFolder: (@Sendable (String) throws -> String)? = nil,
                 command: @escaping @Sendable (Launch) -> Command, planB: (@Sendable (Launch, HostFacts) throws -> Command)? = nil,
                 refusesSignIn: (@Sendable (Int?, String?) -> Bool)? = nil,
                 driver: @escaping @Sendable (Launch, @escaping (Data) throws -> Void, @escaping (AgentEvent) -> Void, @escaping () -> String) -> any Driver) {
        (self.kind, self.tested, self.limits, self.modes, self.listsMoreModes) = (kind, tested, limits, modes, listsMoreModes)
        (self.effortOnlyWhenOffered, self.picksThread, self.resumeFolder) = (effortOnlyWhenOffered, picksThread, resumeFolder)
        (self.command, self.planB, self.refusesSignIn, self.driver) = (command, planB, refusesSignIn, driver)
    }
}

/// What the host knows that a kind's command or driver may need, the same for every launch.
public struct HostFacts: Sendable {
    /// This program's words that answer an agent's hook (`<abs>/something hook permission`); nil when unknown.
    public var hookCommand: [String]?
    /// Where a launch may keep files as long as it runs (plan B's spools); nil when the host has none, and plan B is
    /// then not offered.
    public var spools: String?
}
