// Move to Trash with Undo (F3.2): the space's file and memory go at once, the next space opens, and the toast offers the
// way back. What the space leaves behind, its versions, grant, conversation and place in its group, stays until that
// toast is gone or the next Trash comes, so that Undo brings it all back. Quitting meanwhile needs nothing:
// `Library.forgetGone` does the same at the next start. Agents the space started are never touched: they keep running.
import AppKit
import SomethingCore

final class TrashUndo {
    private let shell: Shell
    /// What the toast on screen can still bring back.
    private var held: Library.Trashed?

    init(shell: Shell) { self.shell = shell }

    /// The names of the agents `name` started that still run: what the sheet and the toast say stays.
    func running(_ name: String) -> [String] {
        let ids = shell.assistant.launches.ids[name] ?? [], state = shell.assistant.engine.state
        // Only the title is read, so no parent of any process is walked.
        let runs = RunsIn { _ in [] }
        return state.agents.filter { ids.contains($0.id) && $0.alive != false }.map { agent in
            AgentReading(agent, thread: state.threads.first { $0.agent == agent.id }, runs: runs).title
        }
    }

    /// Moves `entry` to the Trash and offers Undo. A failure is said, and everything stays.
    func move(_ entry: Library.Entry) {
        finish()
        let name = entry.id, agents = running(name)
        guard let trashed = shell.library.trash(name) else { return }
        shell.assistant.leave(name)
        let kept = agents.count == 1 ? " · \(agents[0]) keeps running" : agents.isEmpty ? "" : " · \(agents.count) agents keep running"
        let toast = shell.toast("\(trashed.title) is in the Trash\(kept)", action: Toast.Action(label: "Undo") { [weak self] in self?.undo(trashed) },
                                seconds: agents.isEmpty ? 5.2 : 6.2)
        // After the toast before it left: that one's end is not this one's.
        held = trashed
        toast.left = { [weak self] in self?.finish() }
    }

    private func undo(_ trashed: Library.Trashed) {
        held = nil
        let said = shell.library.restore(trashed)
        if !said.back { forget(trashed) }
        _ = shell.toast(said.words, quiet: !said.back, seconds: said.back ? 3.2 : 6)
    }

    /// The Undo is over: what the space left goes for good.
    func finish() {
        if let trashed = held { forget(trashed) }
        held = nil
    }

    private func forget(_ trashed: Library.Trashed) {
        // A space made under that name meanwhile began anew, and what it has is its own.
        guard shell.library.entry(trashed.name) == nil else { return }
        shell.library.forget(trashed)
        shell.assistant.forget(trashed.name)
        shell.forget(trashed.name)
        shell.assistant.launches.ids[trashed.name] = nil
    }
}
