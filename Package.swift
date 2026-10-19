// swift-tools-version:5.9
// The recipe to build something. No package dependency.
// SomethingCore holds contract 1 and uses Foundation only. It names no agent beyond the kinds a right of contract 1
// may name.
// SomethingAgents holds the engine and what is specific to each agent (Foundation and Darwin).
// The `something` executable is the Mac app around them (AppKit and WebKit); it reads share/ at run time.
import Foundation
import PackageDescription

// With the Command Line Tools alone (27, Swift 6.4), SwiftPM's build system picks one of two names for the same
// toolchain at each run, and under one of them it does not give the compiler the folder of Swift Testing's macros:
// many runs of `swift test` then fail with "plugin for module 'TestingMacros' not found". The test targets name
// that folder themselves, only when the Command Line Tools are the developer folder (as xcrun finds it: DEVELOPER_DIR,
// then the folder xcode-select chose if it still exists), so a build with Xcode keeps Xcode's own macros.
let commandLineTools = "/Library/Developer/CommandLineTools"
let developer = Context.environment["DEVELOPER_DIR"]
    ?? (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link")).flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
    ?? commandLineTools
let testing: [SwiftSetting] = developer.hasPrefix(commandLineTools)
    ? [.unsafeFlags(["-plugin-path", commandLineTools + "/usr/lib/swift/host/plugins/testing"])] : []

let package = Package(
    name: "something",
    // macOS 15, the oldest macOS this repository's CI runs on; the formula and Info.plist say the same. Tools 5.9
    // have no .v15, hence the string.
    platforms: [.macOS("15.0")],
    products: [.executable(name: "something", targets: ["something"])],
    targets: [
        .target(name: "SomethingCore"),
        .target(name: "SomethingAgents", dependencies: ["SomethingCore"]),
        .executableTarget(name: "something", dependencies: ["SomethingCore", "SomethingAgents"]),
        .testTarget(name: "SomethingCoreTests", dependencies: ["SomethingCore"], swiftSettings: testing),
        .testTarget(name: "SomethingAgentsTests", dependencies: ["SomethingCore", "SomethingAgents"], swiftSettings: testing),
        .testTarget(name: "somethingTests", dependencies: ["something", "SomethingCore", "SomethingAgents"], swiftSettings: testing),
    ]
)
