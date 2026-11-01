// What the person's assistant wants to know before a build, in one plain turn: the message that asks it, whose rules
// travel with it so that it also holds for someone who kept their own AGENTS.md; its answer, one marked line of JSON read
// here, whatever a model wrapped around it; and the lines the person's answers become in the build's first message. Pure:
// nothing here runs, and anything unusable comes out as no question at all, since a build needs none.
import Foundation
import SomethingCore

struct Brief: Equatable {
    struct Option: Equatable { var label: String, about: String }
    struct Question: Equatable {
        var text: String, options: [Option]
        /// The option the agent would choose, always one of them; and whether this question decides what the space keeps.
        var pick: Int, remember: Bool
    }
    /// What the person did with a question: took an option, wrote their own (Other…), or left it to the agent.
    enum Answer: Equatable { case option(Int), own(String), skipped }

    /// A free name for the space, when the agent gave one.
    var name: String?
    var questions: [Question] = []

    /// The line of a build whose agent decides everything.
    static let nothing = "[something] Brief: none, decide and say so."
    private static let mark = "[something] Questions: "
    static let limits = (questions: 3, options: 2...3, text: 120, label: 40, about: 120, name: 64)
    /// The name in the turn's example: a model that echoes it named nothing.
    private static let example = "a-short-file-name"

    /// The turn that asks: `line` says what the person chose for the space, as the build's own message does.
    static func asking(_ words: String, line: String) -> String {
        """
        [something] Questions first. Do not build yet, do not read the guide, use no tool. Read the person's words below and answer with one line only, which starts `\(mark)` and goes on with one JSON object on that line:
        {"name":"\(example)","questions":[{"text":"…?","options":[{"label":"…","about":"…"}],"pick":0,"remember":false}]}
        At most 3 questions, only what their words truly leave open; never what they already say, never what the next line says, never the name. 2 or 3 options each: short labels, one sentence each; `pick` is the one you would choose; `remember` true on the question that decides whether the space keeps things. Nothing open: "questions":[]. In their language. Under 3,000 characters.
        \(line)
        \(words)
        """
    }

    /// The brief in the agent's message `item`: none when the contract cut it, as a cut answer is no answer.
    static func read(_ item: Item, taken: Set<String> = []) -> Brief {
        item.truncated ? Brief() : read(item.text, taken: taken)
    }

    /// The brief in `text`: the marked line found anywhere in it, from its first `{` to the last `}`, so that a code
    /// fence or words before it change nothing. Empty when there is none or it is not JSON. A question that breaks a
    /// limit is dropped alone; `name` is kept only as a valid, short name not in `taken` and not the example's.
    static func read(_ text: String, taken: Set<String> = []) -> Brief {
        guard let marked = text.range(of: mark), let open = text[marked.upperBound...].firstIndex(of: "{"),
              let close = text.lastIndex(of: "}"), open < close,
              let json = try? JSONSerialization.jsonObject(with: Data(text[open...close].utf8)) as? [String: Any] else { return Brief() }
        let name = (json["name"] as? String).flatMap { Spaces.isName($0) && $0.count <= limits.name && $0 != example && !taken.contains($0) ? $0 : nil }
        let questions = (json["questions"] as? [[String: Any]] ?? []).compactMap(question)
        return Brief(name: name, questions: Array(questions.prefix(limits.questions)))
    }

    /// One question as the agent gave it, its words on one line so that none can start a line of the build's message;
    /// nil when it breaks a limit.
    private static func question(_ json: [String: Any]) -> Question? {
        let text = line(json["text"]), options = (json["options"] as? [[String: Any]] ?? []).map { Option(label: line($0["label"]), about: line($0["about"])) }
        // Counted in scalars: one Character can carry thousands of combining marks.
        guard !text.isEmpty, text.unicodeScalars.count <= limits.text, limits.options.contains(options.count),
              options.allSatisfy({ !$0.label.isEmpty && $0.label.unicodeScalars.count <= limits.label && $0.about.unicodeScalars.count <= limits.about }) else { return nil }
        let pick = (json["pick"] as? Int).flatMap { options.indices.contains($0) ? $0 : nil } ?? 0
        return Question(text: text, options: options, pick: pick, remember: json["remember"] as? Bool ?? false)
    }

    /// `value` on one line, without control or direction marks, which would make the person read another answer.
    private static func line(_ value: Any?) -> String {
        let words = (value as? String ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(String.UnicodeScalarView(words.unicodeScalars.filter { !$0.properties.isBidiControl && $0.properties.generalCategory != .control }))
    }

    /// The lines of the build's message: each question answered, in full since the builder never saw them, then the
    /// name. A question the person did not reach is left out; with none answered or skipped, the agent decides.
    func lines(_ answers: [Int: Answer]) -> [String] {
        let said = questions.indices.compactMap { index in answers[index].flatMap { said($0, to: questions[index]) }.map { "\(questions[index].text) \($0)" } }
        return [said.isEmpty ? Brief.nothing : "[something] Brief: \(said.joined(separator: "; "))."] + (name.map { ["[something] Name it: \($0)."] } ?? [])
    }

    private func said(_ answer: Answer, to question: Question) -> String? {
        switch answer {
        case .option(let index): question.options.indices.contains(index) ? question.options[index].label : nil
        case .own(let words): Brief.line(words).isEmpty ? nil : Brief.line(words)
        case .skipped: "skipped, decide and say so"
        }
    }
}
