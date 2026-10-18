// swift-tools-version:5.9
// The recipe to build something. No package dependency.
// SomethingCore uses Foundation only, so it can build on Linux and Windows later. It names no agent beyond the kinds
// a right of contract 1 may name.
// SomethingAgents holds the engine and what is specific to each agent (Foundation and Darwin).
// The `something` executable is the Mac app around them (AppKit and WebKit); it reads share/ at run time.
import PackageDescription

let package = Package(
    name: "something",
    platforms: [.macOS(.v13)],
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
