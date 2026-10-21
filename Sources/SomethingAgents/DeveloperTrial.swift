// DeveloperTrial: `something try <kind> [--record <file>] [--plan-b] [--assistant]`, a developer's trial of one
// driver against the real program, from a terminal, in the current folder. It launches through the engine, as the app does, prints what
// the agent does, and reads commands on standard input. With --record it writes the exchange in the format of
// Tests/Exchanges (one JSON object per line), the raw material of a replay: run it only in a throwaway session whose
// text is invented, since the file holds every line. --plan-b forces Claude's plan B (PermissionSpool.swift).
// --assistant launches the person's building assistant, lent something's own commands as the app lends them.
import Foundation
import SomethingCore

public enum DeveloperTrial {
    static let usage = """
        usage: something try <kind> [--record <file>] [--plan-b] [--assistant]
        Then type a message, or: /now <message> (steer), /interrupt, /allow, /deny, /answer <label>[; <label>…], /stop.
        """

    /// What the words ask for.
    struct Asked {
        var kind: String, type: any Driver.Type, record: String?, planB = false, assistant = false
    }

    /// What `arguments` (every word after `something`, `try` first) ask for, or the sentence that says why they are
    /// wrong. Launches nothing: the tests check with it that no test's words would start a real agent.
    static func parse(_ arguments: [String]) -> Result<Asked, SpaceError> {
        guard arguments.first == "try" else { return .failure(SpaceError(usage)) }
        var words = arguments.dropFirst()
        guard let kind = words.popFirst(), let type = Engine.drivers[kind] else { return .failure(SpaceError(usage)) }
        var asked = Asked(kind: kind, type: type, record: nil)
        while let word = words.popFirst() {
            switch word {
            case "--record":
                guard let path = words.popFirst() else { return .failure(SpaceError(usage)) }
                asked.record = path
            case "--plan-b":
                guard type is ClaudeDriver.Type else { return .failure(SpaceError("something try: --plan-b is for claude only.")) }
                asked.planB = true
            case "--assistant": asked.assistant = true
            default: return .failure(SpaceError(usage))
            }
        }
        return .success(asked)
    }

    /// Returns the exit status: 0 once the agent ended, 1 when it could not start or ended in an error, 2 for wrong words.
    public static func main(_ arguments: [String]) -> Int32 {
        let asked: Asked
        switch parse(arguments) {
        case .success(let words): asked = words
        case .failure(let wrong): return fail(wrong.message, 2)
        }
        var output: FileHandle?
        if let file = asked.record {
            guard FileManager.default.createFile(atPath: file, contents: nil), let handle = FileHandle(forWritingAtPath: file) else {
                return fail("something try: cannot write \(file).", 1)
            }
            output = handle
        }
        let row: ([String: Any]) -> Void = { object in
            guard let output, let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
            output.write(data + Data("\n".utf8))
        }
        let engine = Engine(environment: ProcessInfo.processInfo.environment)
        // The command that routes `try` here routes `hook permission` too.
        engine.hookCommand = Engine.ownHookCommand
        let printer = Printer()
        var id = ""
        engine.changed = { if let agent = engine.state.agents.first(where: { $0.id == id }) { printer.show(agent, engine.state) } }
        row(["begin": true])
        do {
            let lent = Engine.ownHookCommand.map { own in
                Lent(run: Lent.program(own[0], environment: ProcessInfo.processInfo.environment), refused: { _, because in print("Not a builder: \(because)") })
            }
            id = try engine.launch(asked.type, folder: FileManager.default.currentDirectoryPath, model: nil, mode: nil, effort: nil,
                                   planB: asked.planB, assistant: asked.assistant ? .building : nil, lent: lent) { written, line in
                row([written ? "something" : asked.kind: (try? JSONSerialization.jsonObject(with: line)) ?? String(decoding: line, as: UTF8.self)])
            }
        } catch {
            return fail("something try: \(error)", 1)
        }
        print("\(id) started\(asked.planB ? " with plan B" : ""). \(usage.split(separator: "\n").last!)")
        var stopAsked = false
        Thread.detachNewThread {
            while let line = readLine() {
                DispatchQueue.main.async { stopAsked = command(line, engine, id, row) || stopAsked }
            }
            DispatchQueue.main.async { stopAsked = true; engine.stopAll(within: 6) {} }
        }
        while engine.state.agents.first(where: { $0.id == id })?.alive != false { RunLoop.main.run(until: Date() + 0.1) }
        let error = engine.state.agents.first { $0.id == id }?.error
        // The program's code is not kept; a replay only needs to know whether the end was asked for.
        row(["ended": stopAsked || error == nil ? 0 : 1])
        if let error { return fail("\(id) ended: \(error.message)", 1) }
        print("\(id) ended.")
        return 0
    }

    /// Runs one typed command; returns true when it asked the agent to stop.
    private static func command(_ line: String, _ engine: Engine, _ id: String, _ row: ([String: Any]) -> Void) -> Bool {
        let request = engine.state.requests.first { $0.agent == id }?.id
        do {
            switch line {
            case "/stop":
                row(["stop": true])
                engine.stopAll(within: 6) {}
                return true
            case "/interrupt": row(["interrupted": try engine.interrupt(id)])
            case "/allow", "/deny":
                guard let request else { print("No request is open."); break }
                row(["answer": request, "with": line == "/allow" ? "once" : "deny"])
                try engine.answer(request, line == "/allow" ? .once : .deny)
            case _ where line.hasPrefix("/answer "):
                guard let request else { print("No request is open."); break }
                let chosen = line.dropFirst(8).split(separator: ";").map { [$0.trimmingCharacters(in: .whitespaces)] }
                row(["answer": request, "with": chosen])
                try engine.answer(request, .choice(chosen))
            default:
                let steer = line.hasPrefix("/now ")
                let text = steer ? String(line.dropFirst(5)) : line
                let delivery = try engine.deliver(text, to: id, when: steer ? "now" : "next")
                row(["send": text, "when": steer ? "now" : "next", "delivery": delivery])
                print("(\(delivery))")
            }
        } catch {
            print("\(error)")
        }
        return false
    }

    private static func fail(_ message: String, _ code: Int32) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return code
    }
}

/// Prints what changed in one agent since the last call: new or changed items, new requests, the state's word.
private final class Printer {
    private var items: [String: Item] = [:]
    private var requests: Set<String> = []
    private var state = ""

    func show(_ agent: Agent, _ all: State) {
        for item in all.threads.first(where: { $0.agent == agent.id })?.turns.flatMap(\.items) ?? [] where items[item.id] != item {
            let decided = item.decision.map { ", \($0.outcome) by \($0.by)" } ?? ""
            print(item.tool.map { "  [\($0.name) \($0.status ?? "?")\(decided)] \(item.text)" } ?? "\(item.author): \(item.text)")
            items[item.id] = item
        }
        for request in all.requests where request.agent == agent.id && !requests.contains(request.id) {
            requests.insert(request.id)
            print("? \(request.kind) for \(request.tool ?? "a tool"): \(request.about ?? "")  (/allow, /deny or /answer)")
        }
        if agent.state != state {
            state = agent.state
            print("— \(state)\(agent.error.map { ": \($0.message)" } ?? "")")
        }
    }
}
