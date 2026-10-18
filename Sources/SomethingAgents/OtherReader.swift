// OtherReader: the coding agents something knows by name but has no reader for (Gemini CLI, Amp and the like), seen
// from their process only (design 4.2, kind "other"): alive while the process runs, in its folder, and nothing more.
// Many are Node programs: the system names their process node, and the program's path comes after the options.
import Foundation
import SomethingCore

final class OtherReader: Reader {
    let kind = "other"
    static let names: Set<String> = ["gemini", "amp", "qwen", "goose", "crush", "cursor-agent", "droid", "copilot", "auggie"]
    static let interpreters: Set<String> = ["node", "bun"]
    var programs: Set<String> { OtherReader.names.union(OtherReader.interpreters) }

    func owns(_ process: Running) -> Bool { OtherReader.program(process) != nil }

    /// The known name `process` runs as, or nil: its own name, its first argument's, or, under an interpreter, the
    /// first argument that is no option.
    static func program(_ process: Running) -> String? {
        let words = (process.arguments ?? []).map { ($0 as NSString).lastPathComponent }
        if names.contains(process.name) { return process.name }
        if let first = words.first, names.contains(first) { return first }
        guard interpreters.contains(process.name) || words.first.map(interpreters.contains) == true,
              let script = words.dropFirst().first(where: { !$0.hasPrefix("-") }) else { return nil }
        return names.contains(script) ? script : nil
    }

    func read(_ snapshot: Snapshot, discover: Bool, now: Date) -> Reading {
        let matched = snapshot.processes.values.compactMap { process in OtherReader.program(process).map { (process, $0) } }
        // A helper the agent started (Gemini CLI starts itself again with more memory) is the same agent.
        let pids = Set(matched.map(\.0.pid))
        return Reading(sightings: matched.filter { !pids.contains($0.0.parent) }.map { process, name in
            Sighting(kind: kind, key: "\(name)-\(process.pid)", pid: process.pid, facts: StateMap.Facts(alive: true, evidence: "process"),
                     folder: process.folder, title: name, started: process.started, processOnly: true,
                     because: ["send": "something has no reader for this agent; it only sees its process."])
        })
    }
}
