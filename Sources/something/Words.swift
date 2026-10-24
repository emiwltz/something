// What the app's windows say about a path and a journal line, as a newcomer reads them: a path with ~ for the home
// folder, cut between two names when it is too long, never inside one; a journal line as one short sentence in local
// time; a request's title, effect, age, place in the queue and who asks; what quitting ends. The words are made apart
// from the views, so that tests read exactly what Info, the rights sheet and the request panel show.
import AppKit
import SomethingAgents
import SomethingCore

enum Words {
    /// `path` with ~ for the home folder `home`. While `fits` refuses it, the names of its middle give way to one
    /// "…", from the middle out; its first name and its last always stay, even when it still does not fit.
    static func path(_ path: String, home: String, fits: (String) -> Bool = { _ in true }) -> String {
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        // A folder written with a final "/" keeps its last name: "~/code/shop/" is cut as "~/code/shop".
        let path = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        let short = path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        let names = short.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !fits(short), names.count > 2 else { return short }
        for kept in stride(from: names.count - 1, through: 2, by: -1) {
            let head = max(1, kept / 2)
            let cut = (names.prefix(head) + ["…"] + names.suffix(kept - head)).joined(separator: "/")
            if fits(cut) || kept == 2 { return cut }
        }
        return short
    }

    /// English, as every word of the app, with the order of the day and the month of the person's region.
    static let english = Locale(identifier: "en_" + (Locale.current.region?.identifier ?? "US"))

    /// Past this, the text of a line is cut: the journal says what was done, the agent's own view has the rest.
    static let quoted = 40

    /// One journal line as a person reads it: the local time, with the day when it is not `now`'s, then a tab; what the
    /// space did, as a verb; the agent by its kind and by its name in `names` (by id), when the state still has it; its
    /// text on one line, cut; and the result only when it is not ok. Paths are shown from `home`. The day's words come
    /// from `locale`, the 12 or 24 hours from `clock`: only the person's own locale carries their choice in System Settings.
    static func journal(_ line: JournalLine, names: [String: String], home: String, now: Date = Date(), calendar: Calendar = .current,
                        locale: Locale = Words.english, clock: Locale = .current) -> String {
        let kind = line.kind.map(Registry.app.name(of:))
        let name = line.agent.flatMap { names[$0] }
        let who = (kind ?? "an agent") + (name.map { " “\($0)”" } ?? "")
        let text = line.text.map(Words.oneLine)
        let what: String
        switch line.action {
        case "send": what = "wrote to \(who)" + (text.map { ": “\($0)”" } ?? "")
        case "interrupt": what = "interrupted \(who)"
        case "set":
            // Bridge.swift writes what was asked as "model=opus mode=plan".
            let values = line.text?.split(separator: " ").map { $0.replacingOccurrences(of: "=", with: " ") }
            what = "changed \(who)" + (values.map { ": " + $0.joined(separator: ", ") } ?? "")
        case "launch": what = "launched \(who)" + (line.text.map { " in " + Words.path($0, home: home) } ?? "")
        case "resume": what = "continued " + (name == nil ? "a conversation" + (kind.map { " of \($0)" } ?? "") : who) + " here"
        case "open": what = "opened a link" + (text.map { ": \($0)" } ?? "")
        default: what = "\(line.action) \(who)"
        }
        let time = Words.time(line.at, now: now, calendar: calendar, locale: locale, clock: clock)
        return "\(time)\t\(what)" + (line.result.lowercased() == "ok" ? "" : " — " + Words.result(line.result))
    }

    /// `at`, an ISO 8601 date, in local time: the hour alone today, with the day this year, with the year before.
    /// A date that does not read is shown as it is written.
    static func time(_ at: String, now: Date, calendar: Calendar, locale: Locale, clock: Locale) -> String {
        guard let date = iso8601.date(from: at) else { return at }
        // "j" is the hour as `clock` writes it: "a" in its pattern says it counts 12 hours.
        let twelve = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: clock)?.contains("a") ?? false
        let hour = Words.formatter(twelve ? "hmma" : "HHmm", locale, calendar.timeZone).string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return hour }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return Words.formatter(sameYear ? "MMMd" : "yMMMd", locale, calendar.timeZone).string(from: date) + " " + hour
    }

    /// Made once each: Info draws up to 100 lines at each change.
    private static var formatters: [String: DateFormatter] = [:]

    private static func formatter(_ template: String, _ locale: Locale, _ zone: TimeZone) -> DateFormatter {
        let key = [template, locale.identifier, zone.identifier].joined(separator: "|")
        if let made = formatters[key] { return made }
        let format = DateFormatter()
        format.locale = locale
        format.timeZone = zone
        format.setLocalizedDateFormatFromTemplate(template)
        formatters[key] = format
        return format
    }

    /// What a journal result that is not ok means, in plain words: a refusal, said as the person's or the app's
    /// reason, or a failure; a bridge code of contract 1 this table does not know is named as it is.
    static func result(_ code: String) -> String {
        [
            "REFUSED": "you said no",
            "RIGHT_NOT_GRANTED": "refused: you did not allow it",
            "FOLDER_NOT_GRANTED": "refused: outside the folder you chose for it",
            "READ_ONLY_AGENT": "refused: spaces cannot write to this agent",
            "AGENT_NOT_FOUND": "refused: the space cannot see this agent",
            "NOT_SUPPORTED": "refused: this agent cannot do that",
            "VALUE_NOT_OFFERED": "refused: this agent does not offer that value",
            "BUSY": "refused: a link was already waiting for your answer",
            "BAD_PARAMS": "refused: the space asked it the wrong way",
            "UNKNOWN_METHOD": "refused: the space asked it the wrong way",
            "AGENT_STOPPED": "failed: the agent had ended",
            "NOT_INSTALLED": "failed: the program is not on this Mac",
            "INTERPRETER_NOT_FOUND": "failed: what the program needs to run is not on this Mac",
            "LAUNCH_FAILED": "failed: the program stopped at once",
            "THREAD_NOT_FOUND": "failed: the conversation was not found",
            "STILL_RUNNING": "failed: the conversation is still open elsewhere",
            "HELD_ELSEWHERE": "failed: a background service of the agent holds the conversation",
            "STORE_FULL": "failed: the space's memory is full",
            "AGENT_ERROR": "failed: the agent said no or did not answer",
        ][code] ?? "failed (\(code))"
    }

    // MARK: Requests

    /// What a tool does, as a request's title says it: "run a command", "change a file", or "use <tool>". Each agent
    /// says what its tools do, by the names its driver gives them (Claude Code's tool names, Codex's request kinds,
    /// the kinds of the Agent Client Protocol).
    static func wants(_ tool: String?) -> String {
        guard let tool else { return "do something that needs your permission" }
        switch kinds[tool] {
        case .command?: return "run a command"
        case .file?: return "change a file"
        case .permissions?: return "change its permissions"
        case nil: return "use \(tool)"
        }
    }

    /// What an agent at work is doing, as its conversation `thread` says: "editing brief.html" while a file tool runs
    /// on one file, "changing files" or "running a command" by the running tool's kind, else "working", since the
    /// text of a tool item is whatever its driver gives (a path, a patch, a command) and nothing more is known.
    static func doing(_ thread: AgentThread?) -> String {
        guard let turn = thread?.turns.last, turn.state == "working",
              let item = turn.items.last(where: { $0.tool?.status == "running" }), let tool = item.tool else { return "working" }
        switch kinds[tool.name] {
        case .file?:
            let path = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let one = !path.isEmpty && !path.contains(where: \.isWhitespace) && !item.truncated
            return one ? "editing " + (path as NSString).lastPathComponent : "changing files"
        case .command?: return "running a command"
        default: return "working"
        }
    }

    /// The effect of a request, said before its exact text, in the mockup's words: by its tool's kind, in the space
    /// titled `space` when known. Its folder has a row of its own in the panel, not a place in this sentence.
    static func effect(_ tool: String?, space: String?) -> String {
        let place = space.map { " in the \($0) space" } ?? ""
        guard let tool else { return "It needs your permission to go on." }
        switch kinds[tool] {
        case .command?: return "It will run one command\(place)."
        case .file?: return "It will change files\(place)."
        case .permissions?: return "It will change what it may do without asking you."
        case nil: return "It will use \(tool)\(place)."
        }
    }

    /// What each tool does, by its name, as the first agent that names it says.
    private static let kinds = Dictionary(Registry.app.agents.flatMap(\.tools).map { ($0.key, $0.value) }) { first, _ in first }

    /// How long ago `at`, an ISO 8601 date, was asked: "just now" in its first minute, then "asked 3 min ago", "asked
    /// 2 hours ago"; nil when the date does not read.
    static func age(_ at: String, now: Date) -> String? {
        guard let date = iso8601.date(from: at) else { return nil }
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "asked \(minutes) min ago" }
        let hours = minutes / 60
        return "asked \(hours) hour\(hours == 1 ? "" : "s") ago"
    }

    /// "2 of 3" for the second of three; nil for a lone request, which needs no steps.
    static func position(_ index: Int, of count: Int) -> String? {
        count > 1 ? "\(index + 1) of \(count)" : nil
    }

    /// The line under a request's title, as the mockup's "My agents · its assistant · asked 3 min ago": the space's
    /// title, who asks (the space's assistant, or the agent by its name), and the age; what is not known is left out.
    static func who(space: String?, assistant: Bool, name: String?, age: String?) -> String {
        let asker = assistant ? (space == nil ? "your assistant" : "its assistant") : name.map { "“\($0)”" }
        return [space, asker, age].compactMap { $0 }.joined(separator: " · ")
    }

    /// The quit alert's title and its last line, given `requests` waiting and `working` agents at work: the four
    /// titles of the mockup, each in the singular or the plural.
    static func quit(requests: Int, working: Int) -> (title: String, fine: String) {
        let waits = requests == 1 ? "1 request waits" : "\(requests) requests wait"
        let work = working == 1 ? "1 assistant is working" : "\(working) assistants are working"
        let title = requests > 0 && working > 0 ? "\(waits) and \(work). Quit anyway?"
            : requests > 0 ? "\(waits) for you. Quit anyway?" : "\(work). Quit anyway?"
        let denies = requests == 0 ? nil : "Quitting denies \(requests == 1 ? "this request" : "these requests")."
        let stops = working == 0 ? nil : working == 1 ? "It stops the one working in the middle of a turn; what it already changed stays."
            : "It stops those working in the middle of a turn; what they already changed stays."
        return (title, [denies, stops].compactMap { $0 }.joined(separator: " "))
    }

    /// `text` on one line, its spaces and line breaks made one space, cut with "…" past `quoted` characters.
    static func oneLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.count > quoted ? line.prefix(quoted - 1).trimmingCharacters(in: .whitespaces) + "…" : line
    }
}
