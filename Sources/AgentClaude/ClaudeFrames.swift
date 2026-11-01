// What ClaudeDriver reads off Claude's frames with no state of its own: its models' rows and commands in plain words,
// who decided a tool, its questions, one line for a tool's input, and the words of what it refused.
import Foundation
import SomethingAgents
import SomethingCore

extension ClaudeDriver {
    /// The start of the sentence for a control request Claude refused.
    static let refusals = ["initialize": "Claude Code refused to start the session", "interrupt": "Claude Code refused to stop the turn",
                           "set_model": "Claude Code refused the new model", "set_permission_mode": "Claude Code refused the new mode",
                           "apply_flag_settings": "Claude Code refused the new effort"]

    /// Who let a tool run or stopped it, as the tool's result says (`tool_result_meta`, seen on 2.1.296): its own
    /// settings ("config") are a rule; the person's answers are known already, from `answer`.
    static func decision(_ frame: [String: Any], _ toolID: String) -> Decision? {
        let meta = (frame["tool_result_meta"] as? [[String: Any]] ?? []).first { $0["id"] as? String == toolID }
        guard let decided = meta?["permission_decision"] as? [String: Any],
              let outcome = ["accept": "allowed", "reject": "denied"][decided["decision"] as? String ?? ""],
              let by = ["config": "rule", "rule": "rule", "hook": "hook", "mode": "mode", "classifier": "mode"][decided["source"] as? String ?? ""]
        else { return nil }
        return Decision(by: by, outcome: outcome)
    }

    static func questions(_ input: [String: Any]) -> [Question] {
        (input["questions"] as? [[String: Any]] ?? []).compactMap { question in
            guard let text = question["question"] as? String else { return nil }
            return Question(header: question["header"] as? String, text: text, listed: question["options"], multiple: question["multiSelect"] as? Bool == true)
        }
    }

    /// One line for a tool's input: the command, path or address it acts on, else its input as JSON.
    static func summary(_ input: Any?) -> String {
        let input = input as? [String: Any] ?? [:]
        for key in ["command", "file_path", "path", "pattern", "url", "query", "description", "prompt"] {
            if let value = input[key] as? String, !value.isEmpty { return value }
        }
        return shown(input) ?? ""
    }

    /// The input as Claude sent it, readable in a native window.
    static func shown(_ input: [String: Any]) -> String? {
        if let command = input["command"] as? String { return command }
        guard let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// A row of `initialize`'s models in plain words: Claude's description starts with the full name ("Sonnet 5.5 ·
    /// Efficient for routine tasks · $2/$10 per Mtok"), and its default row says which model it is now. Prices stay out.
    static func option(_ model: [String: Any]) -> Option? {
        guard let value = model["value"] as? String else { return nil }
        let label = model["displayName"] as? String ?? value
        let parts = (model["description"] as? String ?? "").components(separatedBy: " · ").filter { !$0.contains("$") }, first = parts.first ?? ""
        if value == "default", let now = first.range(of: "(currently ") { return Option(value: value, label: "Default · " + first[now.upperBound...].dropLast()) }
        let named = first.hasPrefix(label), about = parts.dropFirst(named ? 1 : 0).joined(separator: " · ")
        return Option(value: value, label: named ? first : label, about: about.isEmpty ? nil : about)
    }

    /// The commands initialize lists, by name, with what each does (else its argument's hint, else its name). Only a
    /// hint in angle brackets says the command needs its text: any other shape may be optional, and stays sendable.
    static func commands(_ list: [Any]) -> [Option] {
        list.compactMap { $0 as? [String: Any] }.compactMap { entry in
            let hint = (entry["argumentHint"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return (entry["name"] as? String).map {
                Option(value: $0, label: [entry["description"] as? String, hint].compactMap { $0 }.first { !$0.isEmpty } ?? $0,
                       about: hint.flatMap { $0.hasPrefix("<") && !$0.lowercased().contains("optional") ? $0 : nil })
            }
        }
    }
}
