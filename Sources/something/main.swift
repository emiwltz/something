// Starts something: the Mac shell around SomethingCore. The shell lives in Shell.swift.
import AppKit

let app = NSApplication.shared
let shell = Shell()
app.delegate = shell
app.setActivationPolicy(.regular)
app.run()
