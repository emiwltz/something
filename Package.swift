// swift-tools-version:5.9
// The recipe to build something. No package dependency.
// SomethingCore holds contract 1 and uses Foundation only. It names no agent beyond the kinds a right of contract 1
// may name.
// SomethingAgents is the host (Foundation and Darwin): the engine, the watch, the programs, and the contract an agent
// meets (AgentDescriptor, Driving, Driver, Reader). It names no agent.
// Each Agent* target is one family of agents, behind that contract: AgentClaude, AgentCodex, AgentACP (OpenCode, over
// the Agent Client Protocol) and AgentPi (pi and OMP). One never imports another. What they share with the host is
// `package` (seen by this package's targets only), or public where the app needs it too.
// The `something` executable is the Mac app around them (AppKit and WebKit); it reads share/ at run time, and its
// Extensions.swift is the one file that names the agents.
import Foundation
import PackageDescription

// With the Command Line Tools alone (27, Swift 6.4), SwiftPM's build system picks one of two names for the same
// toolchain at each run, and under one of them it does not give the compiler the folder of Swift Testing's macros:
// many runs of `swift test` then fail with "plugin for module 'TestingMacros' not found". The test targets name
// that folder themselves, only when the Command Line Tools are the developer folder (as xcrun finds it: DEVELOPER_DIR,
// then the folder xcode-select chose if it still exists) and have it, so a build with Xcode keeps Xcode's own macros.
// Seen on a Mac whose xcode-select still named a removed Xcode, with or without DEVELOPER_DIR; not yet tried on one
// whose xcode-select names the Command Line Tools.
let commandLineTools = "/Library/Developer/CommandLineTools"
let developer = Context.environment["DEVELOPER_DIR"]
    ?? (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link")).flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
    ?? commandLineTools
let plugins = commandLineTools + "/usr/lib/swift/host/plugins/testing"
let testing: [SwiftSetting] = developer.hasPrefix(commandLineTools) && FileManager.default.fileExists(atPath: plugins)
    ? [.unsafeFlags(["-plugin-path", plugins])] : []

let agents = ["AgentClaude", "AgentCodex", "AgentACP", "AgentPi"]

let package = Package(
    name: "something",
    // macOS 15, the oldest macOS this repository's CI runs on; the formula and Info.plist say the same. Tools 5.9
    // have no .v15, hence the string.
    platforms: [.macOS("15.0")],
    products: [.executable(name: "something", targets: ["something"])],
    targets: [
        .target(name: "SomethingCore"),
        .target(name: "SomethingAgents", dependencies: ["SomethingCore"]),
    ] + agents.map { .target(name: $0, dependencies: ["SomethingCore", "SomethingAgents"]) } + [
        .executableTarget(name: "something", dependencies: ["SomethingCore", "SomethingAgents"] + agents.map { .target(name: $0) }),
        .testTarget(name: "SomethingCoreTests", dependencies: ["SomethingCore"], swiftSettings: testing),
        .testTarget(name: "SomethingAgentsTests", dependencies: ["SomethingCore", "SomethingAgents"] + agents.map { .target(name: $0) },
                    swiftSettings: testing),
        .testTarget(name: "somethingTests", dependencies: ["something", "SomethingCore", "SomethingAgents"], swiftSettings: testing),
    ]
)
