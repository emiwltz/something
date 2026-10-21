// OtherReader: the coding agents something knows by name but has no reader for (Gemini CLI, Amp and the like), seen
// from their process only: alive while the process runs, in its folder, and nothing more.
// Many are Node programs: the system names their process node (Running.runs).
import Foundation
import SomethingCore

final class OtherReader: Reader {
    let kind = "other"
    static let names: Set<String> = ["gemini", "amp", "qwen", "goose", "crush", "cursor-agent", "droid", "copilot", "auggie"]
    var programs: Set<String> { OtherReader.names.union(Running.interpreters) }

    func owns(_ process: Running) -> Bool { process.runs(OtherReader.names) != nil }

    func read(_ snapshot: Snapshot, discover: Bool, now: Date) -> Reading {
        let matched = snapshot.processes.values.compactMap { process in process.runs(OtherReader.names).map { (process, $0) } }
        // A helper the agent started (Gemini CLI starts itself again with more memory) is the same agent.
        let pids = Set(matched.map(\.0.pid))
        return Reading(sightings: matched.filter { !pids.contains($0.0.parent) }.map { process, name in
            Sighting(kind: kind, key: "\(name)-\(process.pid)", pid: process.pid, facts: StateMap.Facts(alive: true, evidence: "process"),
                     folder: process.folder, program: name, started: process.started, processOnly: true,
                     because: ["send": "something has no reader for this agent; it only sees its process."])
        })
    }
}
