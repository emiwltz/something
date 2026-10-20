// The command: what `something <words>` does in a terminal. It starts or fronts the app,
// hands it a space, makes a space, says where the guide is, and routes check, hook and try. Every failure is one
// sentence that says what to type next (`Error.sentence`, which the app's windows say too). The status is 0 when it
// worked, 1 when it was refused or failed, 2 when the words were wrong or nothing could run; check has its own.
import AppKit
import SomethingAgents
import SomethingCore

enum Command: Equatable {
    case start, open(String), new(String, folder: Bool, from: String?), guide(print: Bool), version, help
    case check(Check), hook([String]), trial([String])
    case wrong(String)

    /// The usage, with the templates `share` holds.
    static func usage(_ share: URL) -> String {
        """
        Usage:
          something                       start something, or bring it to the front
          something open <name>           open a space of ~/something/spaces; or import an export (a .something file)
          something new <name> [--folder] make a space from the template (a folder holds more than one file)
          something new <name> --from <t> make a space from a template: \(Template.present(share).joined(separator: ", "))
          something guide [--print]       where the guide for the coding agent that writes your spaces is
          something check <name|path> [--json] [--refuse <right>]... [--state <file>] [--journal]
          something --version
        """
    }

    /// Whether this process is the app: the command passes --app to LaunchServices, and Finder, the Dock or
    /// Spotlight start the app with launchd (pid 1) as its parent and no words. Words make it the command, whoever
    /// its parent is: a hook whose agent ended is reparented to launchd too.
    static func isApp(_ words: [String], parent: pid_t) -> Bool { words.first == "--app" || parent == 1 && words.isEmpty }

    /// What the words after `something` ask for; `.wrong` with a sentence when they ask for nothing it knows.
    static func parse(_ words: [String]) -> Command {
        guard let first = words.first else { return .start }
        let rest = Array(words.dropFirst())
        switch first {
        case "open":
            guard rest.count == 1, !rest[0].hasPrefix("-") else {
                return .wrong("something open takes one space, for example: something open morning-review")
            }
            return .open(rest[0])
        case "new":
            var words = rest, from: String?
            if let at = words.firstIndex(of: "--from") {
                guard at + 1 < words.count, !words[at + 1].hasPrefix("-") else { return .wrong("--from takes a template, for example: something new my-agents --from agents") }
                from = words.remove(at: at + 1)
                words.remove(at: at)
            }
            let names = words.filter { $0 != "--folder" }
            guard names.count == 1, !names[0].hasPrefix("-"), words.count - names.count <= 1 else {
                return .wrong("something new takes the name of the new space, for example: something new morning-review")
            }
            if let from, names.count < words.count {
                return .wrong("A template is one file: leave out --folder, for example: something new \(names[0]) --from \(from)")
            }
            return .new(names[0], folder: names.count < words.count, from: from)
        case "guide":
            guard rest.isEmpty || rest == ["--print"] else { return .wrong("Type something guide, or something guide --print to read it here.") }
            return .guide(print: !rest.isEmpty)
        case "--version" where rest.isEmpty: return .version
        case "--help", "-h", "help": return .help
        case "check": return Check.parse(rest)
        case "hook" where rest.first == "permission": return .hook(words)
        case "try": return .trial(words)
        default: return .wrong("something does not know \"\(words.joined(separator: " "))\". Type something --help to see what it does.")
        }
    }

    /// What to say when `name` is the path of an export (a .something file) that is not there; nil otherwise. Checked
    /// before any app starts, inside the .app (here) and under `swift run` (main.swift) alike.
    static func missingExport(_ name: String) -> String? {
        guard (name as NSString).pathExtension == "something",
              !FileManager.default.fileExists(atPath: URL(fileURLWithPath: name).standardizedFileURL.path) else { return nil }
        return "There is no file at \(name): give the path of an export, a .something file."
    }

    /// Does what was asked and returns the exit status. `door` reaches the app; `say` prints to the terminal, on
    /// standard error when its second argument is true.
    @MainActor func run(places: Places, share: URL, door: Door, say: (String, Bool) -> Void) -> Int32 {
        switch self {
        case .start:
            return door.start().map { say($0, true); return 1 } ?? 0
        case .open(let name) where (name as NSString).pathExtension == "something":
            // An export goes to the app, which imports it as a double click in Finder does.
            if let missing = Command.missingExport(name) {
                say(missing, true)
                return 1
            }
            return door.deliver(URL(fileURLWithPath: name).standardizedFileURL).map { say($0, true); return 1 } ?? 0
        case .open(let name) where !Spaces.isName(name):
            // A path is a space only when it is one of the spaces folder, given by its path.
            let url = URL(fileURLWithPath: name).standardizedFileURL
            let named = url.pathExtension == "html" ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
            guard let space = Spaces(root: places.spaces).named(named),
                  space.location.resolvingSymlinksInPath().path == url.resolvingSymlinksInPath().path else {
                say(Command.elsewhere(named), true)
                return 1
            }
            return door.deliver(space.location).map { say($0, true); return 1 } ?? 0
        case .open(let name):
            guard let space = Spaces(root: places.spaces).named(name) else {
                say("There is no space \(name) in \(places.spaces.path). Type something new \(name) to make it.", true)
                return 1
            }
            return door.deliver(space.location).map { say($0, true); return 1 } ?? 0
        case .new(let name, let folder, let from):
            do {
                let template = from.map { share.appendingPathComponent("templates/\($0).html") } ?? share.appendingPathComponent("template.html")
                if let from, !Template.present(share).contains(from) {
                    throw SpaceError("There is no template \(from). The templates are: \(Template.present(share).joined(separator: ", ")).")
                }
                let space = try Command.new(name, folder: folder, places: places, template: template)
                say("Made \(space.page.path). Open it with: something open \(name)", false)
                if from != nil, (try? String(contentsOf: space.page, encoding: .utf8))?.contains("\"\(Template.placeholder)\"") == true {
                    say("It follows \(Template.placeholder), a placeholder: write the project folder in its place, then run: something check \(name)", false)
                }
                return 0
            } catch {
                say(error.sentence, true)
                return 1
            }
        case .guide(let print):
            let guide = share.appendingPathComponent("guide.md")
            guard print else {
                say("""
                    The guide for the coding agent that writes your spaces:
                      \(Command.stable(guide).path)
                    Give your agent this path. It says how a space is written (an HTML page in \(places.spaces.path)), \
                    and what it may ask for. Next to it are the template, the templates in templates/, and a skill to add \
                    to your agent yourself, so that it knows how to build a space anywhere:
                      \(Command.stable(guide).deletingLastPathComponent().appendingPathComponent("skill/SKILL.md").path)
                    """, false)
                return 0
            }
            guard let text = try? String(contentsOf: guide, encoding: .utf8) else {
                say("The guide cannot be read at \(guide.path). Reinstall something.", true)
                return 1
            }
            say(text, false)
            return 0
        case .version:
            say("something \(Resources.version)", false)
            return 0
        case .help:
            say(Command.usage(share), false)
            return 0
        case .check(let check):
            return check.main(CheckRunner(places: places, share: share), say: say)
        case .hook(let words):
            return SpoolHook.main(words)
        case .trial(let words):
            return DeveloperTrial.main(words)
        case .wrong(let sentence):
            say(sentence + "\n\n" + Command.usage(share), true)
            return 2
        }
    }

    /// Makes the space `name` from `template` and returns it; one that follows the placeholder folder follows
    /// `following` instead, when given. A new space never inherits the answers a deleted space of the same name left
    /// in the grants file. Throws a `SpaceError` when the name is not free or a file cannot be written; then no space
    /// is left.
    static func new(_ name: String, folder: Bool, places: Places, template: URL, following: String? = nil) throws -> Space {
        let space = try Spaces(root: places.spaces).new(name, from: template, folder: folder)
        do {
            // A folder named "</script>" must not end the declaration's block: "<" is written as \u003c.
            if let following, let quoted = String(data: try JSONSerialization.data(withJSONObject: following, options: [.fragmentsAllowed, .withoutEscapingSlashes]), encoding: .utf8)?
                .replacingOccurrences(of: "<", with: "\\u003c") {
                let text = try String(contentsOf: space.page, encoding: .utf8)
                try text.replacingOccurrences(of: "\"\(Template.placeholder)\"", with: quoted).write(to: space.page, atomically: true, encoding: .utf8)
            }
            try Library.forget(name, in: places)
        } catch {
            try? FileManager.default.removeItem(at: space.location)
            throw error
        }
        return space
    }

    /// What to do with a page outside the spaces folder, named `name` there: something opens only that folder's spaces,
    /// which have a memory, a journal and kept answers.
    static func elsewhere(_ name: String) -> String {
        let named = Spaces.isName(name) ? name : "<name>"
        return "something opens spaces from ~/something/spaces. Copy it there, then run: something open \(named)"
    }

    /// The path that stays the same across upgrades. Homebrew installs in <prefix>/Cellar/something/<version>/ and
    /// keeps <prefix>/opt/something pointing at the current version; any other path is returned as it is.
    static func stable(_ url: URL) -> URL {
        let parts = url.pathComponents
        guard let cellar = parts.lastIndex(of: "Cellar"), cellar + 3 < parts.count else { return url }
        let opt = NSString.path(withComponents: Array(parts[..<cellar]) + ["opt", parts[cellar + 1]] + parts[(cellar + 3)...])
        return FileManager.default.fileExists(atPath: opt) ? URL(fileURLWithPath: opt) : url
    }
}

/// `something check`'s words. The check itself is in Check.swift.
struct Check: Equatable {
    var space: String
    var json = false, journal = false
    var refuse: [String] = [], state: String?

    /// The check the words ask for, or `.wrong` with a sentence.
    static func parse(_ words: [String]) -> Command {
        var spaces: [String] = [], check = Check(space: "")
        var rest = words[...]
        while let word = rest.popFirst() {
            switch word {
            case "--json": check.json = true
            case "--journal": check.journal = true
            case "--refuse", "--state":
                guard let value = rest.popFirst(), !value.hasPrefix("-") else {
                    return .wrong(word == "--refuse" ? "--refuse takes a right, for example: something check morning-review --refuse send"
                        : "--state takes a file, for example: something check morning-review --state state.json")
                }
                if word == "--refuse" { check.refuse.append(value) } else { check.state = value }
            case let flag where flag.hasPrefix("-"):
                return .wrong("something check does not know \(flag). Type something --help to see its options.")
            default: spaces.append(word)
            }
        }
        guard spaces.count == 1 else { return .wrong("something check takes one space, for example: something check morning-review") }
        check.space = spaces[0]
        return .check(check)
    }
}

/// How the command reaches the app. Each returns nil when it worked, or the sentence that says what went wrong.
protocol Door {
    func start() -> String?
    func deliver(_ space: URL) -> String?
}

/// The app's .app through LaunchServices, which keeps one instance: it starts the app, or fronts the running one,
/// and hands it the space as `application(_:open:)`. The app gets the terminal's environment, so the agents it
/// launches find the programs and the folders the terminal finds, less what only says where the terminal runs.
struct LaunchServices: Door {
    let app: URL

    func start() -> String? {
        wait("something could not be started") { NSWorkspace.shared.openApplication(at: app, configuration: configuration(), completionHandler: $0) }
    }

    func deliver(_ space: URL) -> String? {
        wait("The space could not be handed to something") {
            NSWorkspace.shared.open([space], withApplicationAt: app, configuration: configuration(), completionHandler: $0)
        }
    }

    private func configuration() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--app"]
        configuration.environment = LaunchServices.inherited(ProcessInfo.processInfo.environment)
        return configuration
    }

    /// The variables an agent, a terminal or a multiplexer sets for what runs inside it. The app outlives the
    /// terminal it was started from, often an agent's shell: a Claude it launches with CLAUDECODE thinks it is
    /// nested and refuses to start, and one with CLAUDE_CODE_ENTRYPOINT records the wrong origin in its session.
    static let markers: Set<String> = [
        "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_CHILD_SESSION", "CLAUDE_CODE_SSE_PORT",
        "CODEX_SANDBOX", "CODEX_SANDBOX_NETWORK_DISABLED", "PI_CODING_AGENT", "AI_AGENT",
        "TERM_SESSION_ID", "ITERM_SESSION_ID", "TMUX", "TMUX_PANE",
    ]

    /// `environment` without the markers. Settings such as CODEX_HOME or CLAUDE_CONFIG_DIR stay: the agents and
    /// their readers need them.
    static func inherited(_ environment: [String: String]) -> [String: String] {
        environment.filter { !markers.contains($0.key) }
    }

    /// LaunchServices answers on a queue of its own, so the main thread can wait for it.
    private func wait(_ failure: String, _ ask: (@escaping (NSRunningApplication?, Error?) -> Void) -> Void) -> String? {
        let answered = DispatchSemaphore(value: 0)
        var problem: Error?
        ask { _, error in
            problem = error
            answered.signal()
        }
        guard answered.wait(timeout: .now() + 30) == .success else {
            return "\(failure): macOS did not answer within 30 seconds. Try again, or open \(app.path) in Finder."
        }
        return problem.map { "\(failure): \($0.localizedDescription) Try again, or open \(app.path) in Finder." }
    }
}

extension Error {
    /// What went wrong, in the sentence the person reads: a coded error's message with its code and its fix, a
    /// `SpaceError`'s message, or the system's words.
    var sentence: String {
        if let coded = self as? CodedError { return "\(coded.message) (\(coded.code)) \(Codes.all[coded.code]?.fix ?? "")" }
        return (self as? SpaceError)?.message ?? localizedDescription
    }
}
