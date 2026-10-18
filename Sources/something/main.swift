// Decides, before any window, whether this process is the app (App.swift) or the command (Command.swift).
// Inside the .app the command reaches the app through LaunchServices. Run from a clone (`swift run`) there is no
// .app for LaunchServices to start, so `something` and `something open <space>` run the app in this process.
import AppKit

/// Runs the app until it quits. `opening` is a space named on the command line, nil for what the start chooses.
func runApp(opening: String?) -> Never {
    let delegate = App(opening: opening)
    NSApplication.shared.delegate = delegate
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.run()
    exit(0)
}

let words = Array(CommandLine.arguments.dropFirst())
let command = Command.parse(words)
let inProcess = Bundle.main.bundleIdentifier == nil
if Command.isApp(words, parent: getppid()) || inProcess && command == .start {
    // LaunchServices keeps one app, but `something --app` typed in a terminal does not go through it.
    if let id = Bundle.main.bundleIdentifier,
       let other = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { $0.processIdentifier != getpid() }) {
        other.activate(options: [])
        exit(0)
    }
    runApp(opening: nil)
} else if inProcess, case .open(let name) = command, Command.missingExport(name) == nil {
    runApp(opening: name)
}
// This is the main thread; check runs a window, which AppKit allows there only.
exit(MainActor.assumeIsolated {
    command.run(places: .person, share: Resources.share, door: LaunchServices(app: Bundle.main.bundleURL)) { text, problem in
        (problem ? FileHandle.standardError : FileHandle.standardOutput).write(Data((text + "\n").utf8))
    }
})
