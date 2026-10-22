// pi and OMP, which write the same log: what something knows of them. pi's driver (PiDriver), the log's reader
// (PiReader, PiLog) and OMP's (OMPReader) are the other files of this target.
import SomethingAgents

extension AgentDescriptor {
    /// The install sentence is pi's README's (1.0.0), and `npm view` gives that package name. Its launcher is a
    /// shell script that starts a node script, and its installer may bring a node of its own. It takes no mode and
    /// never asks: none is listed, and the bridge refuses a mode pi does not take before any confirmation.
    package static let pi = AgentDescriptor(kind: "pi", name: "pi", install: "npm install -g --ignore-scripts @earendil-works/pi-coding-agent",
                                            runsOn: "node", bundled: "pi-node/current/bin", driving: .pi, reader: { PiReader(environment: $0) },
                                            builder: Builder(), neverAsks: true)

    /// Looked for, to say whether it is installed, and read; something does not launch it.
    package static let omp = AgentDescriptor(kind: "omp", name: "OMP", reader: { OMPReader(environment: $0) })
}
