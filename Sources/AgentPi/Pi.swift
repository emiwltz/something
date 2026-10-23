// pi and OMP, which write the same log: what something knows of them. pi's driver (PiDriver), the log's reader
// (PiReader, PiLog) and OMP's (OMPReader) are the other files of this target. OMP is driven over ACP: its descriptor
// is AgentACP's, given the reader here (Extensions.swift).
import SomethingAgents

extension AgentDescriptor {
    /// The install sentence is pi's README's (1.0.0), and `npm view` gives that package name. Its launcher is a
    /// shell script that starts a node script, and its installer may bring a node of its own. It takes no mode and
    /// never asks: none is listed, and the bridge refuses a mode pi does not take before any confirmation.
    package static let pi = AgentDescriptor(kind: "pi", name: "pi", install: "npm install -g --ignore-scripts @earendil-works/pi-coding-agent",
                                            runsOn: "node", bundled: "pi-node/current/bin", driving: .pi, reader: { PiReader(environment: $0) },
                                            builder: Builder(), neverAsks: true)
}

/// OMP's files, for its descriptor (AgentDescriptor.omp, in AgentACP).
package enum OMP {
    /// The reader of OMP's logs, for the environment something runs in.
    @Sendable package static func reader(_ environment: [String: String]) -> any Reader { OMPReader(environment: environment) }
}
