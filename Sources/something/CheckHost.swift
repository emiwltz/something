// The bridge host of `something check` (contract 9): it answers a space's calls from an invented state, as a real
// engine would answer them, and records each call with its answer. It reaches no agent and opens no window, and the
// person's journal and memory stay untouched: the check's memory is a throwaway file.
import Foundation
import SomethingAgents
import SomethingCore

final class CheckHost: BridgeHost {
    /// One call of the page, as it sent it, and Bridge's answer, `{id, result}` or `{id, error}`.
    struct Call {
        let method: String, params: [String: Any], answer: [String: Any]
    }

    let state: State, granted: Granted
    var launched: Set<String> = []
    let memory: Memory?
    /// The rights the space declares, before `--refuse` takes any.
    let declared: [String]
    private(set) var calls: [Call] = []
    private var started = 0

    init(state: State, granted: Granted, declared: [String], memory: Memory?) {
        (self.state, self.granted, self.declared, self.memory) = (state, granted, declared, memory)
    }

    /// Bridge's answer to one request of the page, recorded.
    func answer(_ request: [String: Any]) -> [String: Any] {
        let answer = Bridge.answer(request, host: self)
        calls.append(Call(method: request["method"] as? String ?? "", params: request["params"] as? [String: Any] ?? [:], answer: answer))
        return answer
    }

    /// The person's journal says what was done to real agents; nothing was.
    func journal(_ line: JournalLine) {}

    func deliver(_ text: String, to agent: Agent, when: String) throws -> String {
        !CheckHost.busy(agent) ? "started" : when == "now" ? "steered" : "queued"
    }

    func interrupt(_ agent: Agent) throws -> Bool { CheckHost.busy(agent) }

    func set(_ agent: Agent, model: String?, mode: String?, effort: String?) throws -> String {
        CheckHost.busy(agent) ? "next-turn" : "now"
    }

    func launch(_ kind: String, folder: String, model: String?, mode: String?, effort: String?) throws -> String { newAgent() }

    func resume(_ kind: String, thread: String, of agent: Agent) throws -> String { newAgent() }

    /// As if the person chose Cancel: no link leaves the machine during a check.
    func open(_ url: URL) throws -> Bool { false }

    /// As if the person allowed a mode that lowers asking; a mode something never offers is refused as in the app.
    func confirms(mode: String, kind: String, folder: String?) throws -> Bool {
        _ = try Engine.lowersAsking(mode: mode, kind: kind)
        return true
    }

    /// The engine's own check of a launch's values, so that a launch the app refuses is refused here too.
    func checkLaunch(_ kind: String, model: String?, mode: String?, effort: String?) throws {
        try Engine.checkLaunch(kind, model: model, mode: mode, effort: effort)
    }

    /// An id for an agent the space launched or resumed. It is in no state: the check has no real agent to show.
    private func newAgent() -> String {
        started += 1
        launched.insert("check-\(started)")
        return "check-\(started)"
    }

    private static func busy(_ agent: Agent) -> Bool { ["working", "waiting"].contains(agent.state) }

    /// The right a call needs (with the agent's kind when the call names an agent of the state), or nil.
    func needs(_ call: Call) -> String? {
        switch call.method {
        case "send", "interrupt", "set":
            return state.agents.first { $0.id == call.params["agent"] as? String }.map { "send:\($0.kind)" } ?? "send"
        case "launch", "resume": return (call.params["kind"] as? String).map { "launch:\($0)" } ?? "launch"
        case "store.get", "store.set": return "store"
        default: return nil
        }
    }

    /// What an unhandled rejection of the page says: RIGHT_REFUSED when it is the answer to a call that --refuse
    /// refused (the page threw instead of adapting to granted), PROMISE_REJECTED for any other.
    func problem(_ rejection: CheckPage.Rejection, refused: [String]) -> Problem {
        let refusedCall = rejection.code == "RIGHT_NOT_GRANTED" && calls.contains { call in
            guard let error = call.answer["error"] as? [String: Any], error["code"] as? String == "RIGHT_NOT_GRANTED",
                  let message = error["message"] as? String, rejection.message.hasSuffix(message),
                  let right = needs(call) else { return false }
            return Rights.covers(refused, right)
        }
        return refusedCall ? Problem("RIGHT_REFUSED", "A call to a refused right was not caught: \(rejection.message)")
            : Problem("PROMISE_REJECTED", rejection.message)
    }

    /// What the calls say about the space, each problem once. A call refused because of `--refuse` is not one: the
    /// page is expected to meet it, and whether it threw instead shows in its unhandled rejections (`problem`).
    func problems(refused: [String]) -> [Problem] {
        var problems: [Problem] = []
        for call in calls {
            var problem: Problem?
            if call.method == "state", !declared.contains(where: { $0 == "state" || $0.hasPrefix("launch") }) {
                problem = Problem("RIGHT_NOT_DECLARED", "state() was called, but the declaration asks for no state right: the page sees no agent.")
            } else if let error = call.answer["error"] as? [String: Any], let code = error["code"] as? String {
                let right = code == "RIGHT_NOT_GRANTED" ? needs(call) : nil
                if let right, !Rights.covers(declared, right) {
                    problem = Problem("RIGHT_NOT_DECLARED", "\(call.method) needs the right \(right), which the declaration does not ask for.")
                } else if right == nil || !Rights.covers(refused, right!) {
                    problem = Problem("BRIDGE_ERROR", "\(call.method) was answered \(code): \(error["message"] as? String ?? "")")
                }
            }
            if let problem, !problems.contains(problem) { problems.append(problem) }
        }
        return problems
    }

    /// The calls as the report gives them: method, params and answer (the result, or `{error}`). A state answer is
    /// cut to the ids of the agents the page received, which `received` describes.
    var recorded: [JSONValue] {
        calls.map { call in
            var answer: Any = call.answer["error"].map { ["error": $0] } ?? call.answer["result"] ?? NSNull()
            if call.method == "state", let state = call.answer["result"] as? [String: Any] {
                answer = ["agents": (state["agents"] as? [[String: Any]] ?? []).compactMap { $0["id"] }]
            }
            return JSONValue.of(["method": call.method, "params": call.params, "answer": answer])
        }
    }
}

extension JSONValue {
    /// A value JSONSerialization made or can write; null for anything else.
    static func of(_ value: Any) -> JSONValue {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let list = try? JSONDecoder().decode([JSONValue].self, from: data) else { return .null }
        return list[0]
    }
}
