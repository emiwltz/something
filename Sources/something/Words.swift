// What the app's windows say about a path and a journal line, as a newcomer reads them: a path with ~ for the home
// folder, cut between two names when it is too long, never inside one; a journal line as one short sentence in local
// time. The words are made apart from the views, so that tests read exactly what Home and the rights window show.
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

    /// A one-line label, `prefix` then `path` cut to fit `width` points; the whole path shows when the pointer
    /// rests on it.
    static func pathLabel(_ prefix: String, _ path: String, home: String, width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        let font = label.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        label.stringValue = prefix + Words.path(path, home: home) { (prefix + $0 as NSString).size(withAttributes: [.font: font]).width <= width }
        label.toolTip = path
        // Even its first and last names may not fit: AppKit then cuts what is left, rather than widen the window.
        label.lineBreakMode = .byTruncatingMiddle
        label.widthAnchor.constraint(lessThanOrEqualToConstant: width).isActive = true
        return label
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
        let kind = line.kind.map(Programs.name(of:))
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
        guard let date = Words.iso.date(from: at) else { return at }
        // "j" is the hour as `clock` writes it: "a" in its pattern says it counts 12 hours.
        let twelve = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: clock)?.contains("a") ?? false
        let hour = Words.formatter(twelve ? "hmma" : "HHmm", locale, calendar.timeZone).string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return hour }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return Words.formatter(sameYear ? "MMMd" : "yMMMd", locale, calendar.timeZone).string(from: date) + " " + hour
    }

    private static let iso = ISO8601DateFormatter()
    /// Made once each: the card draws up to 100 lines at each look at Home.
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
    /// reason, or a failure; a code of contract 4.3 this table does not know is named as it is.
    static func result(_ code: String) -> String {
        [
            "REFUSED": "you said no",
            "RIGHT_NOT_GRANTED": "refused: you did not allow it",
            "FOLDER_NOT_GRANTED": "refused: outside the folder you chose for it",
            "READ_ONLY_AGENT": "refused: this agent was started outside something",
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

    /// `text` on one line, its spaces and line breaks made one space, cut with "…" past `quoted` characters.
    static func oneLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.count > quoted ? line.prefix(quoted - 1).trimmingCharacters(in: .whitespaces) + "…" : line
    }
}
