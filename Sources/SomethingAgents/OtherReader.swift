// OtherReader: coding agents seen from their process only: alive while the process runs, in its folder, and nothing
// more. Those something knows only by name (Registry.others) go by the kind "other"; an agent with a descriptor but no
// reader of its files goes by its own kind, through its descriptor's `reader`.
// Many are Node programs: the system names their process node (Running.runs).
import Foundation
import SomethingCore

package final class OtherReader: Reader {
    package let kind: String
    /// Their programs' names.
    let names: Set<String>
    package var programs: Set<String> { names.union(Running.interpreters) }

    package init(kind: String = "other", names: Set<String>) { (self.kind, self.names) = (kind, names) }

    package func owns(_ process: Running) -> Bool { process.runs(names) != nil }

    package func read(_ snapshot: Snapshot, discover: Bool, now: Date) -> Reading {
        let matched = snapshot.processes.values.compactMap { process in process.runs(names).map { (process, $0) } }
        // A helper the agent started (an agent may start itself again, with more memory) is the same agent.
        let pids = Set(matched.map(\.0.pid))
        return Reading(sightings: matched.filter { !pids.contains($0.0.parent) }.map { process, name in
            Sighting(kind: kind, key: "\(name)-\(process.pid)", pid: process.pid, facts: StateMap.Facts(alive: true, evidence: "process"),
                     folder: process.folder, program: name, started: process.started, processOnly: true,
                     because: ["send": "something has no reader for this agent; it only sees its process."])
        })
    }
}
