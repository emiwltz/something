// Where something finds its files: share/ (something.js, the template, the guide), and the folders it keeps for the
// person (spaces, their memory, the grants and the journals). Inside the .app share/ is in Contents/Resources/share;
// run from a clone (`swift run`), it is in the clone.
import Foundation
import SomethingCore

enum Resources {
    /// This engine's version, for `--version` and every export: the one make-app.sh wrote in the .app's Info.plist,
    /// the only place it is kept; "dev" when something runs from its clone.
    static let version = version(of: .main)

    /// The CFBundleShortVersionString of `bundle`, or "dev" when it has none.
    static func version(of bundle: Bundle) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

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

/// The folders something keeps for the person, all under one home, so a trial with a throwaway home touches nothing else.
struct Places {
    let home: URL
    var spaces: URL { Spaces.root(home: home) }
    var data: URL { Memory.folder(home: home) }
    /// The engine's own folder, outside the folders agents edit: the grants, the journals and the window's memory.
    var support: URL { home.appendingPathComponent("Library/Application Support/something") }
    var grants: URL { support.appendingPathComponent("app.json") }
    var journals: URL { support.appendingPathComponent("journal") }
    /// The window's own memory: the last space open.
    var window: URL { support.appendingPathComponent("window.json") }
    /// Claude Code's plan-B spools (PermissionSpool.swift): never in $TMPDIR, which a sandboxed agent (Codex in
    /// workspace-write) may write, and could then answer Claude's requests.
    var spools: URL { support.appendingPathComponent("spool") }

    /// The person's places. $HOME first, so that `HOME=<folder> swift run something` never reaches their own folders.
    static var person: Places {
        Places(home: ProcessInfo.processInfo.environment["HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser)
    }
}
