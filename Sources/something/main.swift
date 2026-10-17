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
    runApp(opening: nil)
} else if inProcess, case .open(let name) = command {
    runApp(opening: name)
}
exit(command.run(places: .person, share: Resources.share, door: LaunchServices(app: Bundle.main.bundleURL)) { text, problem in
    (problem ? FileHandle.standardError : FileHandle.standardOutput).write(Data((text + "\n").utf8))
})
