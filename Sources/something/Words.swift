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

    /// English, as every word of the app, with the hours (12 or 24) and the order of the day of the person's region.
    static let english = Locale(identifier: "en_" + (Locale.current.region?.identifier ?? "US"))

    /// Past this, the text of a line is cut: the journal says what was done, the agent's own view has the rest.
    static let quoted = 40

    /// One journal line as a person reads it: the local time, with the day when it is not `now`'s, then a tab; what the space did,
    /// as a verb; the agent by its kind and by its name in `names` (by id), when the state still has it; its text on
    /// one line, cut; and the result only when it is not ok. Paths are shown from `home`.
    static func journal(_ line: JournalLine, names: [String: String], home: String, now: Date = Date(),
                        calendar: Calendar = .current, locale: Locale = Words.english) -> String {
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
        let result = line.result.lowercased() == "ok" ? "" : " — refused: " + Words.result(line.result)
        return "\(Words.time(line.at, now: now, calendar: calendar, locale: locale))\t\(what)\(result)"
    }

    /// `at`, an ISO 8601 date, in local time: the hour alone today, with the day this year, with the year before.
    /// A date that does not read is shown as it is written.
    static func time(_ at: String, now: Date, calendar: Calendar, locale: Locale) -> String {
        guard let date = ISO8601DateFormatter().date(from: at) else { return at }
        func format(_ template: String) -> String {
            let format = DateFormatter()
            format.locale = locale
            format.timeZone = calendar.timeZone
            format.setLocalizedDateFormatFromTemplate(template)
            return format.string(from: date)
        }
        if calendar.isDate(date, inSameDayAs: now) { return format("jmm") }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return format(sameYear ? "MMMd" : "yMMMd") + " " + format("jmm")
    }

    /// A journal result in plain words: a code of contract 4.3 in small letters, and REFUSED as the person's answer.
    static func result(_ code: String) -> String {
        code == "REFUSED" ? "you said no" : code.lowercased().replacingOccurrences(of: "_", with: " ")
    }

    /// `text` on one line, its spaces and line breaks made one space, cut with "…" past `quoted` characters.
    static func oneLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.count > quoted ? line.prefix(quoted - 1).trimmingCharacters(in: .whitespaces) + "…" : line
    }
}
