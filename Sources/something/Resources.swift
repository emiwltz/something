// Finds share/, the files something serves to its window (something.js, the template, the guide).
// Inside the .app they are in Contents/Resources/share; run from a clone (`swift run`), they are in the clone.
import Foundation

enum Resources {
    /// The share/ folder. Fails with a sentence when it cannot be found: without it there is no page to show.
    static let share: URL = {
        if Bundle.main.bundleIdentifier != nil, let resources = Bundle.main.resourceURL {
            return resources.appendingPathComponent("share")
        }
        // Not #filePath: that is where the sources were on the machine that built, not where they are now.
        // The executable's real path (symlinks resolved) sits under .build/ inside the clone.
        var folder = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
        while let current = folder, current.path != "/" {
            let share = current.appendingPathComponent("share")
            if FileManager.default.fileExists(atPath: current.appendingPathComponent("Package.swift").path),
               FileManager.default.fileExists(atPath: share.path) {
                return share
            }
            folder = current.deletingLastPathComponent()
        }
        FileHandle.standardError.write(Data("""
            something cannot find its share/ folder next to its program. Run it with `swift run something` \
            from its clone, or reinstall it.\n
            """.utf8))
        exit(1)
    }()
}
