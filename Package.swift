// swift-tools-version:5.9
// The recipe to build something v2. No dependency.
// SomethingCore uses Foundation only, so it can build on Linux and Windows later.
import PackageDescription

let package = Package(
    name: "something",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SomethingCore"),
        .testTarget(name: "SomethingCoreTests", dependencies: ["SomethingCore"]),
    ]
)
