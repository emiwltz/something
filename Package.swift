// swift-tools-version:5.9
// The recipe to build something. No package dependency.
// SomethingCore holds contract 1 and uses Foundation only. It names no agent beyond the kinds a right of contract 1
// may name.
// SomethingAgents holds the engine and what is specific to each agent (Foundation and Darwin).
// The `something` executable is the Mac app around them (AppKit and WebKit); it reads share/ at run time.
import PackageDescription

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
        .testTarget(name: "SomethingCoreTests", dependencies: ["SomethingCore"]),
        .testTarget(name: "SomethingAgentsTests", dependencies: ["SomethingCore", "SomethingAgents"]),
        .testTarget(name: "somethingTests", dependencies: ["something", "SomethingCore", "SomethingAgents"]),
    ]
)
