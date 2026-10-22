// Replay: a driver played over an exchange of Tests/Exchanges/<kind>, with no process. Each file was recorded in a
// trial against the real program and a fake model (invented text, paths made /Users/example), with the calls
// something made in between. The replay runs Launched, the code the engine runs: the program's lines go in (rows
// keyed by the kind), and every line the driver writes must be the next one the exchange recorded ("*" matches any
// uuid something made up; "*<uuid>" also stands for it in the program's later lines, which named the uuid of the
// recording).
import Foundation
import Testing
@testable import SomethingAgents
@testable import AgentACP
@testable import AgentCodex
import SomethingCore

final class Replay {
    var written: [Data] = []
    var agent: Launched!
    /// Recorded uuid → the one something made up this time.
    var bound: [String: String] = [:]
    /// What a Codex driver scheduled (its interrupt timeout), run by a {"timeout": true} row; and whether it quit.
    var scheduled: [() -> Void] = []
    var quit = false
    /// The words of each command a lent tool ran, and why the agent could not take the tools.
    var lentRuns: [[String]] = [], refusals: [String] = []
    /// What the lent commands give, in turn; an empty report once used up.
    var reports: [Lent.Reply] = []

    /// A Claude launched in /Users/example/shop as agent claude-1; with `assistant`, the person's assistant, in
    /// /Users/example/something/spaces.
    init(mode: String = "default", assistant: Bool = false) {
        var launch = Launch(agent: "claude-1", folder: assistant ? "/Users/example/something/spaces" : "/Users/example/shop", mode: mode,
                            thread: "5b2e0000-0000-4000-8000-000000000001")
        launch.assistant = assistant ? .building : nil
        start("claude", launch)
    }

    /// A launch of `kind`, driven as `driving` says when given (an invented agent over another's exchanges).
    init(_ kind: String, _ launch: Launch, driving: Driving? = nil) { start(kind, launch, driving) }

    private init(unstarted: Void) {}

    /// A Codex launched in /Users/example/shop as agent codex-1, continuing `resume` when given; with `assistant`, the
    /// person's assistant, in /Users/example/something/spaces, lent the check, whose commands give `reports` in turn
    /// (an empty report once they are used up), at once.
    static func codex(mode: String? = nil, effort: String? = nil, resume: String? = nil, assistant: Bool = false,
                      reports: [Lent.Reply] = []) -> Replay {
        var launch = Launch(agent: "codex-1", folder: assistant ? "/Users/example/something/spaces" : "/Users/example/shop", mode: mode,
                            effort: effort, thread: resume ?? "", resume: resume != nil)
        launch.assistant = assistant ? .building : nil
        let replay = Replay(unstarted: ())
        replay.reports = reports
        if assistant {
            launch.lent = Lent(tools: LentTool.all, run: { [unowned replay] words in
                replay.lentRuns.append(words)
                return replay.reports.isEmpty ? Lent.Reply(ok: true, text: "") : replay.reports.removeFirst()
            }, refused: { [unowned replay] kind, because in replay.refusals.append("\(kind): \(because)") }, hop: { work, then in work(); then() })
        }
        replay.start("codex", launch)
        return replay
    }

    /// An OpenCode launched in /Users/example/shop as agent opencode-1, continuing `resume` when given; with `driving`,
    /// another agent over ACP in its place.
    static func opencode(model: String? = nil, resume: String? = nil, driving: Driving? = nil) -> Replay {
        Replay("opencode", Launch(agent: "opencode-1", folder: "/Users/example/shop", model: model, thread: resume ?? "", resume: resume != nil),
               driving: driving)
    }

    /// A pi launched in /Users/example/shop as agent pi-1, continuing the conversation file `resume` when given.
    static func pi(model: String? = nil, effort: String? = nil, resume: String? = nil) -> Replay {
        Replay("pi", Launch(agent: "pi-1", folder: "/Users/example/shop", model: model, effort: effort, thread: resume ?? "", resume: resume != nil))
    }

    private func start(_ kind: String, _ launch: Launch, _ driving: Driving? = nil) {
        agent = Launched(try! driving ?? Registry.described.driving(kind), launch, write: { [unowned self] in written.append($0) }, now: { "2026-10-17T09:00:00Z" })
        if let codex = agent.driver as? CodexDriver {
            codex.schedule = { [unowned self] _, work in scheduled.append(work) }
            codex.quit = { [unowned self] in quit = true }
        }
        (agent.driver as? ACPDriver)?.quit = { [unowned self] in quit = true }
        try! agent.begin(pid: 4242)
    }

    var fold: Fold { agent.queue.fold }
    var items: [Item] { fold.turns.flatMap(\.items) }

    /// The lines the driver wrote, as JSON objects, from `start` on.
    func lines(from start: Int = 0) -> [[String: Any]] {
        written[start...].map { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] ?? [:] }
    }

    func feed(_ frame: [String: Any]) {
        var line = String(decoding: try! JSONSerialization.data(withJSONObject: frame), as: UTF8.self)
        for (recorded, made) in bound { line = line.replacingOccurrences(of: recorded, with: made) }
        agent.driver.receive(Data(line.utf8))
    }

    /// Plays an exchange file of `kind`; each mismatch is an issue that names the file and the line. A first row with
    /// "resume" makes a Codex, OpenCode or pi launch that continues that thread, "model" an OpenCode or pi launch with
    /// that model, "effort" a pi launch with that thinking level, and "assistant" a Claude or Codex launched as the person's assistant.
    /// `database` is the OpenCode database the driver reads at the end, as the engine sets it; `driving` plays an
    /// OpenCode exchange with another agent over ACP.
    static func play(_ name: String, kind: String = "claude", database: String? = nil, driving: Driving? = nil) throws -> Replay {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Exchanges/\(kind)/\(name).jsonl")
        let rows = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map { text in
            try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        }
        let resume = rows.first?["resume"] as? String
        let model = rows.first?["model"] as? String
        let assistant = rows.first?["assistant"] as? Bool ?? false
        // A lent command gives what it gave in the recording: the text something sent back, in turn.
        let reports = rows.compactMap { (($0["something"] as? [String: Any])?["result"] as? [String: Any]) }.compactMap { result -> Lent.Reply? in
            guard let text = (result["contentItems"] as? [[String: Any]])?.first?["text"] as? String else { return nil }
            return Lent.Reply(ok: result["success"] as? Bool ?? false, text: text)
        }
        let replay = kind == "codex" ? codex(resume: resume, assistant: assistant, reports: reports) : kind == "opencode" ? opencode(model: model, resume: resume, driving: driving)
            : kind == "pi" ? pi(model: model, effort: rows.first?["effort"] as? String, resume: resume) : Replay(assistant: assistant)
        (replay.agent.driver as? ACPDriver)?.environment = database.map { ["OPENCODE_DB": $0] } ?? [:]
        var read = 0
        for (number, row) in rows.enumerated() {
            let at = "\(name).jsonl:\(number + 1)"
            // {"begin": true} marks where the launch wrote its first lines: the replay already began.
            if let frame = row[kind] as? [String: Any] { replay.feed(frame) }
            if let expected = row["something"] as? [String: Any] {
                guard read < replay.written.count else { Issue.record("\(at): nothing was written"); continue }
                let actual = replay.lines(from: read)[0]
                read += 1
                #expect(replay.matches(expected, actual), "\(at): wrote \(String(decoding: replay.written[read - 1], as: UTF8.self))")
            }
            if let text = row["send"] as? String {
                #expect(try replay.agent.send(text, when: row["when"] as! String) == row["delivery"] as! String, "\(at)")
            }
            if let interrupted = row["interrupted"] as? Bool { #expect(try replay.agent.interrupt() == interrupted, "\(at)") }
            if let request = row["answer"] as? String {
                let with: Answer = row["with"] as? String == "once" ? .once : row["with"] as? String == "deny" ? .deny
                    : .choice(row["with"] as? [[String]] ?? [])
                #expect(try replay.agent.answer(request, with), "\(at): the request was not open")
            }
            if let set = row["set"] as? [String: String] {
                #expect(try replay.agent.driver.set(model: set["model"], mode: set["mode"], effort: set["effort"]) == row["applied"] as? String, "\(at)")
            }
            if row["timeout"] != nil {
                let due = replay.scheduled
                replay.scheduled = []
                due.forEach { $0() }
            }
            if row["stop"] != nil, let goodbye = replay.agent.driver.goodbye { replay.written.append(goodbye) }
            // OpenCode's first step of the ladder is the engine's interrupt.
            if row["stop"] != nil, replay.agent.driver is ACPDriver { _ = try replay.agent.interrupt() }
            if let code = row["ended"] as? Int { replay.agent.ended(code: Int32(code), errors: "", asked: row["stop"] != nil) }
            if let check = row["check"] as? [String: Any] { replay.check(check, at) }
        }
        #expect(read == replay.written.count, "\(name): \(replay.written.count - read) line(s) written that the exchange does not have")
        return replay
    }

    func check(_ check: [String: Any], _ at: String) {
        let agent = fold.agent
        if let state = check["state"] as? String { #expect(agent.state == state, "\(at)") }
        if let waiting = check["waiting"] as? String { #expect(agent.waiting == waiting, "\(at)") }
        if let alive = check["alive"] as? Bool { #expect(agent.alive == alive, "\(at)") }
        if let mode = check["mode"] as? String { #expect(agent.mode == mode, "\(at)") }
        if let count = check["requests"] as? Int { #expect(fold.requests.count == count, "\(at)") }
        if let queue = check["queue"] as? [String] { #expect(agent.queue.map(\.text) == queue, "\(at)") }
        if let detail = check["detail"] as? NSDictionary {
            let shown = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(agent.detail)) as? NSDictionary
            #expect(shown == detail, "\(at): detail \(agent.detail)")
        }
    }

    /// Equal JSON, but for a string starting with "*", which matches any string ("*<uuid>" binds that uuid to it).
    func matches(_ expected: Any, _ actual: Any) -> Bool {
        switch (expected, actual) {
        case (let e as [String: Any], let a as [String: Any]):
            return Set(e.keys) == Set(a.keys) && e.allSatisfy { key, value in matches(value, a[key]!) }
        case (let e as [Any], let a as [Any]): return e.count == a.count && zip(e, a).allSatisfy { matches($0, $1) }
        case (let e as String, let a as String):
            guard e.hasPrefix("*") else { return e == a }
            if e.count > 1 { bound[String(e.dropFirst())] = a }
            return true
        default: return (expected as? NSObject) == (actual as? NSObject)
        }
    }
}
