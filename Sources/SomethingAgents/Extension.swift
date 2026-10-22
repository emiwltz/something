// Extension: what something knows of each agent, written once as data. The tables the engine, the programs and the
// watch used to keep apart (kinds, names, install sentences, modes that ask as much, which conversations continue
// here) are computed from these descriptors, so that knowing one more agent is one more descriptor. For a kind
// something launches, its Driving says what its driver can do and makes one; the driver's code and the reader stay
// in their own files.
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
    /// The program's arguments for a launch, and what it changes in the person's environment.
    var command: @Sendable (Launch) -> Command
    /// Makes the driver of one launch. `write` hands one whole line (without its newline) to the program and throws
    /// AGENT_STOPPED once it no longer reads; `emit` takes what happened; `now` is the time of each item and request
    /// (ISO 8601).
    var driver: @Sendable (_ launch: Launch, _ write: @escaping (Data) throws -> Void, _ emit: @escaping (AgentEvent) -> Void,
                           _ now: @escaping () -> String) -> any Driver
}

extension Driving {
    /// None of `limits`: ClaudeTrial.swift showed that Claude takes an effort at launch (`--effort`) and during a session
    /// (`apply_flag_settings` with `effortLevel`, from its next request to the model). Claude refuses an effort its
    /// model does not list: `can.effort` follows `options.effort`. bypassPermissions is never among the modes: it
    /// cannot be entered unless the launch allowed it, and something never allows it.
    static let claude = Driving(tested: "2.1.296",
                                modes: [Option(value: "default", label: "Ask before acting"), Option(value: "acceptEdits", label: "Accept edits"),
                                        Option(value: "plan", label: "Plan only"), Option(value: "auto", label: "Auto (Claude decides what is safe)"),
                                        Option(value: "dontAsk", label: "Never ask (refuse what is not allowed)")],
                                effortOnlyWhenOffered: true,
                                command: { ClaudeDriver.command($0) }, driver: { ClaudeDriver($0, write: $1, emit: $2, now: $3) })

    /// None of `limits`: Codex takes a model, an effort and an approval policy with each turn it starts. The modes are
    /// the approval policies 0.163 accepts ("on-failure" is gone). A model the catalog does not list (a custom
    /// provider's) offers no effort, and Codex would take any word. Codex names the thread when it starts it.
    static let codex = Driving(tested: "0.163.0",
                               modes: [Option(value: "on-request", label: "Ask when needed"),
                                       Option(value: "untrusted", label: "Ask before most commands"),
                                       Option(value: "never", label: "Never ask (refuse what is not allowed)")],
                               effortOnlyWhenOffered: true, picksThread: false,
                               command: { CodexDriver.command($0) }, driver: { CodexDriver($0, write: $1, emit: $2, now: $3) })

    /// Over ACP a second session/prompt during a turn is refused ("Session already has an active ACP prompt"), and
    /// OpenCode has no steer there: a message for later waits in something's own queue. OpenCode's modes are its
    /// agents; build and plan come with it, and others the person wrote show in `options.mode` once OpenCode lists
    /// them. It offers an effort only for a model that has variants, and names the session when it starts it.
    static let opencode = Driving(tested: "2.0.20",
                                  limits: ["steer": "OpenCode cannot take a message during a turn; send it with when: \"next\"."],
                                  modes: [Option(value: "build", label: "Build"), Option(value: "plan", label: "Plan")],
                                  listsMoreModes: true, effortOnlyWhenOffered: true, picksThread: false,
                                  command: { ACPDriver.command($0) }, driver: { ACPDriver($0, write: $1, emit: $2, now: $3) })

    /// pi asks no permission and has no request to show: the sentence says so, for the consent window. It names its
    /// conversation file itself; something learns it from get_state.
    static let pi = Driving(tested: "1.0.0",
                            limits: ["mode": "pi has no permission modes: it runs commands and edits files without asking first."],
                            picksThread: false,
                            command: { PiDriver.command($0) }, driver: { PiDriver($0, write: $1, emit: $2, now: $3) })
}
