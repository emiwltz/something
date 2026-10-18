// Packaging: tools/make-app.sh assembles something.app in a temporary prefix, from the program this suite built, and
// the app is then run as Homebrew runs it, through the wrapper its write_exec_script writes: a symlink would break
// Bundle.main. The bundle's version is read inside it, its ad-hoc signature verifies, and its program answers plan B's
// hook.
import Foundation
import Testing
@testable import something

@Suite(.leavesNothing("something-packaging-"), .leavesNothing("something-prefix-")) struct PackagingTests {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Runs `program` with `arguments`; its status and standard output.
    func run(_ program: String, _ arguments: [String], quiet: Bool = false) throws -> (status: Int32, out: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        if quiet { process.standardError = FileHandle.nullDevice }
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    @Test func theAppRunsThroughHomebrewsWrapper() throws {
        // The something program swift test built, next to this suite's bundle.
        let program = Bundle(for: FakeDoor.self).bundleURL.deletingLastPathComponent().appendingPathComponent("something")
        try #require(FileManager.default.isExecutableFile(atPath: program.path), "swift test built no something program at \(program.path)")
        let prefix = FileManager.default.temporaryDirectory.appendingPathComponent("something-prefix-\(UUID().uuidString)")
        let app = prefix.appendingPathComponent("something.app")
        defer {
            // Running a program inside a bundle may register the bundle with LaunchServices: forget it before deleting it.
            _ = try? run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-u", app.path], quiet: true)
            try? FileManager.default.removeItem(at: prefix)
        }
        #expect(try run(root.appendingPathComponent("tools/make-app.sh").path, [prefix.path, "9.8.7", program.path]).status == 0)

        let info = try #require(try PropertyListSerialization.propertyList(
            from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any])
        #expect(info["CFBundleIdentifier"] as? String == "io.github.emiwltz.something")
        #expect(info["CFBundleShortVersionString"] as? String == "9.8.7" && info["CFBundleVersion"] as? String == "9.8.7")
        #expect(FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Resources/share/something.js").path))

        let wrapper = prefix.appendingPathComponent("bin/something")
        try FileManager.default.createDirectory(at: wrapper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/bash\nexec \"\(app.path)/Contents/MacOS/something\" \"$@\"\n".write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        let version = try run(wrapper.path, ["--version"])
        #expect(version.status == 0 && version.out == "something 9.8.7\n")
        let guide = try run(wrapper.path, ["guide"])
        #expect(guide.out.contains(app.appendingPathComponent("Contents/Resources/share/guide.md").path))

        #expect(try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]).status == 0)

        // Plan B's hook, as Engine.ownHookCommand gives it inside the app: the bundle's own program, not the wrapper.
        let home = Home(prefix: "something-packaging-")
        defer { home.remove() }
        let spool = home.root.appendingPathComponent("spool")
        try FileManager.default.createDirectory(at: spool, withIntermediateDirectories: true)
        let inside = app.appendingPathComponent("Contents/MacOS/something")
        let wrong = try runBuilt(inside, ["hook", "permission", "--bogus"], home: home)
        #expect(wrong.status == 2 && wrong.out.isEmpty && wrong.err.contains("usage: something hook permission"), "\(wrong)")
        let ran = try runBuilt(inside, ["hook", "permission", "--spool", spool.path], home: home)
        let decision = hookDecision(ran.out)
        #expect(ran.status == 0 && decision.behavior == "deny" && decision.message?.contains("something is not running") == true, "\(ran)")
    }

    @Test func makeAppRefusesWrongUse() throws {
        #expect(try run(root.appendingPathComponent("tools/make-app.sh").path, ["/Users/example/prefix"]).status == 2)
        // An unset variable in a formula or a CI job must not become /something.app.
        #expect(try run(root.appendingPathComponent("tools/make-app.sh").path, ["", "1.0.0"], quiet: true).status == 2)
    }

    /// The floor is macOS 15 everywhere a person or a tool reads it.
    @Test func everyPlaceSaysMacOS15() throws {
        func text(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
        #expect(try text("Package.swift").contains(#"platforms: [.macOS("15.0")]"#))
        #expect(try text("packaging/Info.plist").contains("<key>LSMinimumSystemVersion</key>\n\t<string>15.0</string>"))
        #expect(try text("packaging/homebrew/something.rb").contains("depends_on macos: :sequoia"))
        #expect(try text("README.md").contains("macOS 15 or later") && text("share/guide.md").contains("macOS 15 or later"))
    }
}
