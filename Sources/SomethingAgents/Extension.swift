// Extension: what something knows of each agent, written once as data. The tables the engine, the programs and the
// watch used to keep apart (kinds, names, install sentences, modes that ask as much, which conversations continue
// here) are computed from these descriptors, so that knowing one more agent is one more descriptor. Its driver and
// its reader stay in their own files.
import Foundation

/// What something knows of one agent, besides its driver and its reader. Pure data: building one does no I/O.
public struct AgentDescriptor: Equatable, Sendable {
    /// The contract's word for it, which is also the file name of its program: "claude".
    public var kind: String
    /// The name a person knows it by, in every window and sentence: "Claude Code".
    public var name: String
    /// What to type in Terminal to install it; nil for a kind something does not launch.
    public var install: String?
    /// An interpreter its program needs that the program's first line does not name.
    public var runsOn: String?
    /// Folders under the home where its installer puts it, which a shell's PATH may lack. They are looked in for
    /// every program, as the folders of the installers every agent may use are.
    public var homeFolders: [String] = []
    /// A folder under the data folder (`$XDG_DATA_HOME`, else `~/.local/share`) that its installer filled for it
    /// alone, which goes last on its PATH: pi's own node.
    public var bundled: String?
    /// Parts of a real path that make a copy of its program another app's own, never launched.
    public var refusedCopies: [String] = []
    /// The modes known to ask the person no less than its default; any other mode counts as asking less.
    public var asksAsMuch: Set<String> = []
    /// When a conversation of it seen elsewhere can be continued here.
    public var resume: Resume = .never

    public enum Resume: Equatable, Sendable {
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
    public static let all = [claude, codex, opencode, pi, omp]

    /// The descriptor of `kind`; nil for a kind something does not know.
    public static func of(_ kind: String) -> AgentDescriptor? { all.first { $0.kind == kind } }

    // The modes that ask no less than the default come from each program's --help (17 October 2026). Claude 2.1.296:
    // acceptEdits, auto, dontAsk and bypassPermissions lower asking; "default" is the name its channel reports (its
    // help's "manual" is never offered: ClaudeDriver.modes leaves it out). Codex 0.163: `--ask-for-approval` offers
    // on-request and never; untrusted, which older versions offered, asks more. OpenCode 2.0.20: a mode is an agent;
    // build and plan ask as the person's settings say, and only `--auto`, which something never passes, asks less.
    // pi 1.0.0 takes no mode and never asks: none is listed, so any mode for pi counts as lowering asking, which is
    // safe, since the bridge refuses a mode pi does not take before any confirmation.

    /// The Claude desktop app's own copy of `claude` is the app's, updated by the app, and may differ from the
    /// Claude Code the person installed.
    static let claude = AgentDescriptor(kind: "claude", name: "Claude Code", install: "brew install --cask claude-code",
                                        refusedCopies: ["/Application Support/Claude/", "/Claude.app/"],
                                        asksAsMuch: ["default", "plan"], resume: .whenNoneHolds)

    /// Codex refuses a second writer by itself, so a conversation whose holder is unknown is offered; Codex says so
    /// if its background service holds it.
    static let codex = AgentDescriptor(kind: "codex", name: "Codex", install: "brew install --cask codex",
                                       asksAsMuch: ["on-request", "untrusted"], resume: .unlessKnownHeld)

    static let opencode = AgentDescriptor(kind: "opencode", name: "OpenCode", install: "brew install opencode",
                                          homeFolders: [".opencode/bin"], asksAsMuch: ["build", "plan"])

    /// The install sentence is pi's README's (1.0.0), and `npm view` gives that package name. Its launcher is a
    /// shell script that starts a node script, and its installer may bring a node of its own.
    static let pi = AgentDescriptor(kind: "pi", name: "pi", install: "npm install -g --ignore-scripts @earendil-works/pi-coding-agent",
                                    runsOn: "node", bundled: "pi-node/current/bin")

    /// Looked for, to say whether it is installed, and read; something does not launch it.
    static let omp = AgentDescriptor(kind: "omp", name: "OMP")

    /// The coding agents something knows by their program's name alone (Gemini CLI, Amp and the like), seen by their
    /// process only, as `other`. A kind described above is never one of them.
    static let processOnly = Set(["gemini", "amp", "qwen", "goose", "crush", "cursor-agent", "droid", "copilot", "auggie"])
        .subtracting(all.map(\.kind))
}
