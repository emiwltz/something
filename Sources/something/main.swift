// Starts something, the Mac app (App.swift). `something [<space>]` opens a space: a name in ~/something/spaces or the
// path of a space's .html file or folder; without one, the template. The command of design 5 comes later.
import AppKit

let app = NSApplication.shared
let delegate = App(opening: CommandLine.arguments.dropFirst().first)
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
