// swift-tools-version:5.9
// The recipe to build something v2. No dependency.
// SomethingCore uses Foundation only, so it can build on Linux and Windows later;
// the `something` executable is the Mac shell around it (AppKit and WebKit).
import PackageDescription

let package = Package(
    name: "something",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "something", targets: ["something"])],
    targets: [
        .target(name: "SomethingCore"),
        .executableTarget(name: "something", dependencies: ["SomethingCore"]),
        .testTarget(name: "SomethingCoreTests", dependencies: ["SomethingCore"]),
    ]
)
