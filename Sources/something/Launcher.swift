// The launcher: a small something.app in ~/Applications that opens the one Homebrew installed, so that Spotlight finds
// something (it indexes nothing under Homebrew's prefix). The tour offers it once, only when something runs from a
// Homebrew prefix and no launcher is there; it is made only when the person ticks the box, and never registered by
// something: Spotlight and Finder find it as they find any app put in Applications.
import Foundation
import SomethingCore

enum Launcher {
    static let id = "io.github.emiwltz.something.launcher"

    /// Homebrew's prefix when `app` is the something.app a formula installed, <prefix>/Cellar/something/<version>/
    /// something.app (or a link to it, such as <prefix>/opt/something); nil for any other place.
    static func prefix(of app: URL) -> String? {
        let parts = app.resolvingSymlinksInPath().pathComponents
        guard parts.count > 4, !parts.contains(where: { $0.contains("'") }), parts.last == "something.app", parts[parts.count - 4] == "Cellar", parts[parts.count - 3] == "something" else {
            return nil
        }
        return NSString.path(withComponents: Array(parts.dropLast(4)))
    }

    /// ~/Applications/something.app under the places' home.
    static func place(_ places: Places) -> URL { places.home.appendingPathComponent("Applications/something.app") }

    /// Whether the tour offers the launcher: something runs from a Homebrew prefix, the tour never offered it, and
    /// no launcher is there.
    static func offered(app: URL, places: Places) -> Bool {
        prefix(of: app) != nil && Library.WindowFile.read(places)?.launcherOffered != true
            && !FileManager.default.fileExists(atPath: place(places).path)
    }

    /// Makes the launcher of the something.app Homebrew keeps under `prefix`, with `icon` when there is one; a
    /// launcher already there is kept as it is. Its program opens something, or says it is no longer installed.
    /// Throws a `SpaceError` when it cannot be written, and then leaves nothing half made.
    static func make(prefix: String, places: Places, icon: URL?) throws {
        let app = place(places), contents = app.appendingPathComponent("Contents")
        guard !FileManager.default.fileExists(atPath: app.path) else { return }
        // The opt path stays the same across `brew upgrade`.
        let target = (prefix as NSString).appendingPathComponent("opt/something/something.app")
        let script = """
            #!/bin/sh
            # Made by something's tour: opens something as Homebrew installed it.
            if [ -d '\(target)' ]; then exec /usr/bin/open '\(target)'; fi
            exec /usr/bin/osascript -e 'display dialog "something is no longer installed. You can move this launcher to the Trash." buttons {"OK"} default button 1 with title "something"'

            """
        let info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": "something", "CFBundleExecutable": "something",
                                   "CFBundleIconFile": "something", "CFBundlePackageType": "APPL", "CFBundleInfoDictionaryVersion": "6.0",
                                   "LSUIElement": true]
        do {
            for folder in ["MacOS", "Resources"] {
                try FileManager.default.createDirectory(at: contents.appendingPathComponent(folder), withIntermediateDirectories: true)
            }
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
            let program = contents.appendingPathComponent("MacOS/something")
            try script.write(to: program, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
            if let icon { try FileManager.default.copyItem(at: icon, to: contents.appendingPathComponent("Resources/something.icns")) }
        } catch {
            // A half-made launcher would stand in the way of the next try.
            try? FileManager.default.removeItem(at: app)
            throw SpaceError("something could not add itself to \(app.deletingLastPathComponent().path): \(error.localizedDescription)")
        }
    }
}
