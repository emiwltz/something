// Extension: what something knows of each agent, written once as data. The tables the engine, the programs and the
// watch used to keep apart (kinds, names, install sentences, modes that ask as much, which conversations continue
// here) are computed from these descriptors, so that knowing one more agent is one more descriptor. For a kind
// something launches, its Driving says what its driver can do and makes one; each Driving, the driver's code and
// the reader stay in their own files.
import Foundation
import SomethingCore

/// What something knows of one agent, besides its driver and its reader. Pure data: building one does no I/O.
struct AgentDescriptor: Sendable {
    /// The contract's word for it, which is also the file name of its program: "claude".
    var kind: String
    /// The name a person knows it by, in every window and sentence: "Claude Code".
    var name: String
    /// What to type in Terminal to install it; nil for a kind something does not launch.
    var install: String?
    /// An interpreter its program needs that the program's first line does not name.
    var runsOn: String?
    /// Folders under the home where its installer puts it, which a shell's PATH may lack. They are looked in for
    /// every program, after the shared installers' folders and before `.volta/bin`, the order of 0.2.
    var homeFolders: [String] = []
    /// A folder under the data folder (`$XDG_DATA_HOME`, else `~/.local/share`) that its installer filled for it
    /// alone, which goes last on its PATH: pi's own node.
    var bundled: String?
    /// Parts of a real path that make a copy of its program another app's own, never launched.
    var refusedCopies: [String] = []
    /// The modes known to ask the person no less than its default, from its program's --help (17 October 2026); any
    /// mode not listed counts as asking less, which is safe.
    var asksAsMuch: Set<String> = []
    /// When a conversation of it seen elsewhere can be continued here.
    var resume: Resume = .never
    /// How something launches and drives it; nil for a kind it only reads.
    var driving: Driving?

    enum Resume: Equatable, Sendable {
        /// Never: something cannot continue its conversations started elsewhere.
        case never
        /// Only when no process is known to hold it: a second writer would break it.
        case whenNoneHolds
        /// Unless a process is known to hold it: the agent refuses a second writer itself and says so.
        case unlessKnownHeld
    }
}

extension AgentDescriptor {
    /// The agents something knows, in the order of the state's kinds.
    static let all = [claude, codex, opencode, pi, omp]

    /// The descriptor of `kind`; nil for a kind something does not know.
    static func of(_ kind: String) -> AgentDescriptor? { all.first { $0.kind == kind } }

    /// The Claude desktop app's own copy of `claude` is the app's, updated by the app, and may differ from the
    /// Claude Code the person installed. Modes (2.1.296): acceptEdits, auto, dontAsk and bypassPermissions lower
    /// asking; "default" is the name its channel reports (its help's "manual" is never offered: Driving.claude.modes
    /// leaves it out).
    static let claude = AgentDescriptor(kind: "claude", name: "Claude Code", install: "brew install --cask claude-code",
                                        refusedCopies: ["/Application Support/Claude/", "/Claude.app/"],
                                        asksAsMuch: ["default", "plan"], resume: .whenNoneHolds, driving: .claude)

    /// Codex refuses a second writer by itself, so a conversation whose holder is unknown is offered; Codex says so
    /// if its background service holds it. Modes (0.163): `--ask-for-approval` offers on-request and never;
    /// untrusted, which older versions offered, asks more.
    static let codex = AgentDescriptor(kind: "codex", name: "Codex", install: "brew install --cask codex",
                                       asksAsMuch: ["on-request", "untrusted"], resume: .unlessKnownHeld, driving: .codex)

    /// Modes (2.0.20): a mode is an agent; build and plan ask as the person's settings say, and only `--auto`, which
    /// something never passes, asks less.
    static let opencode = AgentDescriptor(kind: "opencode", name: "OpenCode", install: "brew install opencode",
                                          homeFolders: [".opencode/bin"], asksAsMuch: ["build", "plan"], driving: .opencode)

    /// The install sentence is pi's README's (1.0.0), and `npm view` gives that package name. Its launcher is a
    /// shell script that starts a node script, and its installer may bring a node of its own. It takes no mode and
    /// never asks: none is listed, and the bridge refuses a mode pi does not take before any confirmation.
    static let pi = AgentDescriptor(kind: "pi", name: "pi", install: "npm install -g --ignore-scripts @earendil-works/pi-coding-agent",
                                    runsOn: "node", bundled: "pi-node/current/bin", driving: .pi)

    /// Looked for, to say whether it is installed, and read; something does not launch it.
    static let omp = AgentDescriptor(kind: "omp", name: "OMP")
}

/// What something knows of a kind it launches: what its driver can do, the program's arguments, and the driver itself.
/// The engine, Launched and `something check` read these; no driver is asked about itself.
struct Driving: Sendable {
    /// Its descriptor's kind, which DescriptorsTests checks: one value names the agent a launch makes.
    var kind: String
    /// The newest version of the program its driver was proven on (`kinds.<kind>.tested`).
    var tested: String
    /// The `can` entries that are always false for this kind, each with its sentence (`because`, `granted.limits`).
    var limits: [String: String] = [:]
    /// The modes a launch or `set` may choose; empty when the kind has none.
    var modes: [Option] = []
    /// Whether `set` may also choose modes the agent lists itself, beyond `modes`: the bridge then checks a `set`
    /// against the agent's `options.mode`, after the person confirmed (Engine.lowersAsking).
    var listsMoreModes = false
    /// Whether an effort can be set only when `options.effort` lists levels.
    var effortOnlyWhenOffered = false
    /// Whether the launch picks the conversation id (`Launch.thread`) for the program. When false, the thread is
    /// unknown until the program names it, unless the launch resumes one.
    var picksThread = true
    /// The folder a resume of a conversation runs in, when the conversation names it (pi's file header); nil: the
    /// folder asked. Throws THREAD_NOT_FOUND for a conversation that is not there.
    var resumeFolder: (@Sendable (_ thread: String) throws -> String)?
    /// The program's arguments for a launch, and what it changes in the person's environment.
    var command: @Sendable (Launch) -> Command
    /// The command of a launch that takes plan B (`Launch.planB`), for a kind that has one: Claude's permission
    /// hook. Throws LAUNCH_FAILED when the host lacks what it needs.
    var planB: (@Sendable (Launch, HostFacts) throws -> Command)?
    /// Makes the driver of one launch. `write` hands one whole line (without its newline) to the program and throws
    /// AGENT_STOPPED once it no longer reads; `emit` takes what happened; `now` is the time of each item and request
    /// (ISO 8601).
    var driver: @Sendable (_ launch: Launch, _ write: @escaping (Data) throws -> Void, _ emit: @escaping (AgentEvent) -> Void,
                           _ now: @escaping () -> String) -> any Driver
}

/// What the host knows that a kind's command or driver may need, the same for every launch.
public struct HostFacts: Sendable {
    /// This program's words that answer an agent's hook (`<abs>/something hook permission`); nil when unknown.
    public var hookCommand: [String]?
    /// Where a launch may keep files as long as it runs (plan B's spools); nil: its kind's own place, for Claude
    /// `Spool.root` in the person's real Application Support.
    public var spools: String?
}
