// The native windows that ask the person: send a message, allow a tool, quit with agents running.
// A page cannot draw them, so a page cannot answer them.
import AppKit
import SomethingAgents
import SomethingCore

enum Ask {
    /// `--click <button title>`: something clicks that button of its own windows, half a second after
    /// showing them, instead of waiting for a person. It checks the windows from the command line and
    /// needs no permission from macOS; a person's click is still to be tried by a person.
    static let scripted = Shell.option("--click")

    static func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        if let title = scripted, let button = alert.buttons.first(where: { $0.title.hasPrefix(title) }) {
            let timer = Timer(timeInterval: 0.5, repeats: false) { _ in
                print("window: \(alert.messageText) · clicked: \(button.title)")
                button.performClick(nil)
            }
            RunLoop.main.add(timer, forMode: .modalPanel)
        }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    /// The name a person knows an agent by.
    static func name(of harness: String) -> String {
        ["claude": "Claude Code", "codex": "Codex", "opencode": "OpenCode", "pi": "pi"][harness] ?? harness
    }

    enum Consent { case once, always, refused }

    static func send(_ text: String, to agent: Agent) -> Consent {
        let alert = NSAlert()
        alert.messageText = "Send this message to \(name(of: agent.harness)) in “\(agent.name)”?"
        alert.informativeText = String(text.prefix(400))
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Always for this agent")
        alert.addButton(withTitle: "Don't send").keyEquivalent = "\u{1b}"
        switch run(alert) {
        case .alertFirstButtonReturn: return .once
        case .alertSecondButtonReturn: return .always
        default: return .refused
        }
    }

    static func permission(_ request: PermissionRequest, of agent: Agent) -> PermissionAnswer {
        let alert = NSAlert()
        alert.messageText = "\(name(of: agent.harness)) in “\(agent.name)” asks to use \(request.tool)."
        alert.informativeText = request.about ?? ""
        alert.addButton(withTitle: "Allow once")
        alert.addButton(withTitle: "Deny").keyEquivalent = "\u{1b}"
        return run(alert) == .alertFirstButtonReturn ? .once : .deny
    }

    static func quit(stopping count: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Quit something?"
        alert.informativeText = "\(count) agent(s) will stop."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return run(alert) == .alertFirstButtonReturn
    }
}
