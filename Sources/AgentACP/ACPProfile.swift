// ACPProfile: one agent that something drives over the Agent Client Protocol (ACP), as data. ACPDriver speaks the
// protocol the same way to every agent; a profile says what differs: the words that start the agent and sign it in,
// its modes, the names it gives its options and tools, and, as small closures, the few things it does its own way
// that only code can say (its quirks). Adding an agent that speaks ACP is a profile and a descriptor.
import SomethingAgents
import SomethingCore

struct ACPProfile: Sendable {
    /// Its descriptor's kind and name.
    var kind: String, name: String
    /// The newest version of the program the driver was proven on.
    var tested: String
    /// The program's arguments that start it over ACP, and what the launch adds to its environment.
    var arguments: [String]
    var environment: [String: String] = [:]
    /// What to type in a terminal to sign it in.
    var signIn: String
    /// The modes a launch may choose, and whether `set` may also choose modes it lists itself.
    var modes: [Option] = []
    var listsMoreModes = false
    /// The category its effort has among its config options; the protocol's own word for it is "thought_level".
    var effortCategory = "thought_level"
    /// The `_meta` key that marks a sub-agent's updates in its parent's stream; nil when it marks none.
    var childKey: String?
    /// The tool it asks the person a question with, which it cannot show when something launches it; nil: none.
    var questionTool: String?
    /// Words of its error when a conversation to continue is not there (or not in that folder).
    var notFoundWords = ["session not found"]
    /// Quirk: the model a new conversation that names none should take, read from the launch's environment; nil when
    /// the agent's own choice stands.
    var lastModel: (@Sendable (_ environment: [String: String]) -> String?)?
    /// Quirk: what to say when it ended during one of something's turns and may have left its conversation marked as
    /// running (`session`, in the launch's environment); nil when there is nothing to say.
    var leftRunning: (@Sendable (_ session: String, _ environment: [String: String]) -> String?)?

    /// What its tools do, by the kinds the protocol gives them, for the permission panel's title.
    static let tools: [String: AgentDescriptor.Tool] = ["execute": .command, "edit": .file, "delete": .file, "move": .file]

    /// How something launches and drives it. Over ACP the agent names the session when it starts it, a second
    /// session/prompt during a turn is refused (there is no steer: a message for later waits in something's own
    /// queue), and an effort is offered only by a model that lists levels.
    var driving: Driving {
        Driving(kind: kind, tested: tested, limits: ["steer": steerLimit], modes: modes, listsMoreModes: listsMoreModes,
                effortOnlyWhenOffered: true, picksThread: false,
                command: { [arguments, environment] _ in Command(arguments: arguments, adding: environment) },
                driver: { [self] in ACPDriver(self, $0, write: $1, emit: $2, now: $3) })
    }

    // MARK: What is said in its name

    var steerLimit: String { "\(name) cannot take a message during a turn; send it with when: \"next\"." }

    var questionDismissed: String {
        "\(name) tried to ask you a question, but when something launches it, \(name) cannot show questions. Ask it to write its question in its reply instead."
    }

    var noAllowOnce: String { "\(name) offered no one-time allow for this request, and something never allows always: it was refused." }

    /// A failed turn in words a newcomer can act on; the agent's own words otherwise. A refused sign-in names the
    /// `model` in use and its provider: the agent may be signed in to others, so "sign in" alone would mislead. Only
    /// when something `picked` the model (`lastModel`) does choosing another in the agent change it.
    func failure(_ error: [String: Any]?, _ words: String, _ text: String, model: String?, picked: Bool) -> String {
        guard error?["code"] as? Int == -32000 || words.lowercased().contains("authentication required") else {
            return "\(name) did not finish the message “\(Launched.short(text))”: \(words)"
        }
        let provider = model.flatMap { $0.contains("/") ? $0.split(separator: "/").first.map(String.init) : nil } ?? "its provider"
        let what = model.map { "\(name)'s model \($0) needs a sign-in to \(provider), which \(name) does not have." }
            ?? "\(name)'s model needs a sign-in to its provider, which \(name) does not have."
        let other = picked ? " Or use another model once in \(name) and start a new conversation: something takes the model you used last there." : ""
        return "\(what) Sign in to \(provider) in \(name) (`\(signIn)` in a terminal) and send the message again.\(other)"
    }
}
