// The welcome tour's model: five steps done by keyboard (Return goes on, ⌘[ goes back, Escape skips it all), shown at
// the first start and again from Help › Welcome Tour. It never starts an agent: choosing an assistant only says which
// one the first message will start. Each comfort is asked and starts off: the launcher, offered only under a Homebrew
// prefix, and the notifications. Its end is kept in the preferences, with whether it offered the launcher. Welcome.swift
// draws it and takes its keys.
import Foundation
import SomethingAgents

@Observable final class Tour {
    enum Step: Int, CaseIterable { case welcome, assistant, comforts, meet, ready }
    /// What the window shows: a step, or, at the assistant's step, no builder found (`none`, also while looking).
    enum Screen: Equatable { case welcome, assistant, none, comforts, meet, ready }
    /// A comfort the third step asks about.
    enum Comfort: Equatable { case launcher, notify }

    private(set) var step = Step.welcome
    /// Whether the last move went forward, for the side the next step slides in from.
    private(set) var forward = true
    /// The comfort under the keys (↑ ↓ move it, Space turns it on or off).
    private(set) var cursor = 0
    let offersLauncher: Bool
    private(set) var addLauncher = false
    private(set) var notify: Bool
    /// Whether ⌘K was tried at the fourth step, and whether Look Again is still looking.
    private(set) var met = false
    private(set) var looking = false
    /// Whether "What is a coding agent?" is open.
    var explained = false
    /// The install command just copied, for a moment.
    private(set) var copied: String?
    /// Called when the tour ended, with what went wrong when the launcher could not be made.
    @ObservationIgnored var finished: (_ problem: String?) -> Void = { _ in }
    let places: Places, app: URL

    /// The tour of the something.app at `app`, whose place says whether it offers the launcher.
    init(places: Places, app: URL = Bundle.main.bundleURL) {
        (self.places, self.app) = (places, app)
        offersLauncher = Launcher.offered(app: app, places: places)
        notify = Preferences.at(places).notify
    }

    /// The comforts asked, in order: the launcher only when it is offered.
    var comforts: [Comfort] { (offersLauncher ? [.launcher] : []) + [.notify] }

    func screen(_ assistant: AssistantModel) -> Screen {
        switch step {
        case .welcome: .welcome
        case .assistant: assistant.kind == nil ? .none : .assistant
        case .comforts: .comforts
        case .meet: .meet
        case .ready: .ready
        }
    }

    /// Whether Look Again is busy: it was just clicked, or the builders were never looked for yet.
    func searching(_ assistant: AssistantModel) -> Bool { looking || (assistant.kind == nil && !assistant.noAgent) }

    /// Return: Look Again when no builder was found, the end at the last step, else the next step.
    func next(_ assistant: AssistantModel) {
        switch screen(assistant) {
        case .none: lookAgain(assistant)
        case .ready: end()
        default: move(Step(rawValue: step.rawValue + 1) ?? .ready, forward: true)
        }
    }

    /// ⌘[ and Back: the step before, except while the builders are looked for, as the disabled Back button says.
    func back(_ assistant: AssistantModel) {
        guard !searching(assistant), let before = Step(rawValue: step.rawValue - 1) else { return }
        move(before, forward: false)
    }

    /// Goes to `step` (a picture or a test starts there).
    func move(_ to: Step, forward: Bool = true) {
        (self.forward, step, cursor) = (forward, to, 0)
    }

    /// The arrows at the assistant's step: in a grid of two columns ↑ ↓ move by a row and ← → by one, in a list only
    /// ↑ ↓ move; the choice wraps around. At the comforts, ↑ ↓ move the cursor. Returns whether the arrow was used.
    @discardableResult
    func arrow(_ dx: Int, _ dy: Int, _ assistant: AssistantModel) -> Bool {
        switch screen(assistant) {
        case .assistant:
            let kinds = assistant.entries.filter(\.enabled).map(\.id), grid = kinds.count > 2
            guard !kinds.isEmpty, dy != 0 || grid else { return false }
            let at = kinds.firstIndex(of: assistant.kind ?? "") ?? 0, by = dy * (grid ? 2 : 1) + dx
            assistant.choose(kinds[((at + by) % kinds.count + kinds.count) % kinds.count])
            return true
        case .comforts:
            guard dy != 0 else { return false }
            cursor = ((cursor + dy) % comforts.count + comforts.count) % comforts.count
            return true
        default: return false
        }
    }

    /// Space at the comforts: turns the one under the cursor on or off.
    func toggle() {
        guard step == .comforts, comforts.indices.contains(cursor) else { return }
        toggle(comforts[cursor])
    }

    /// Turns `comfort` on or off, and puts the cursor on it.
    func toggle(_ comfort: Comfort) {
        cursor = comforts.firstIndex(of: comfort) ?? cursor
        switch comfort {
        case .launcher: addLauncher.toggle()
        case .notify: notify.toggle()
        }
    }

    func isOn(_ comfort: Comfort) -> Bool { comfort == .launcher ? addLauncher : notify }

    /// ⌘K at the fourth step: the assistant says hello. Nothing is sent to it.
    func meet() { if step == .meet { met = true } }

    /// Looks for the builders again; the step says so for a moment, then shows what was found.
    func lookAgain(_ assistant: AssistantModel) {
        guard !looking else { return }
        looking = true
        assistant.lookAgain()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.looking = false
        }
    }

    /// Copies an install command with `copy`; its button says Copied for a moment.
    func copy(_ command: String, with copy: (String) -> Void) {
        copy(command)
        copied = command
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            if self?.copied == command { self?.copied = nil }
        }
    }

    /// Escape: ends the tour as it is, every comfort left as it was, and asks nothing more.
    func skip() { end(applying: false) }

    /// Ends the tour: it is not shown again at the next start, nor the launcher offered again. With `applying`, the
    /// notifications follow their switch, and the launcher is made when its switch is on.
    func end(applying: Bool = true) {
        let notify = notify
        Preferences.at(places).change { [offersLauncher] in
            $0.toured = true
            if offersLauncher { $0.launcherOffered = true }
            if applying { $0.notify = notify }
        }
        guard applying, offersLauncher, addLauncher, let prefix = Launcher.prefix(of: app) else { return finished(nil) }
        do {
            try Launcher.make(prefix: prefix, places: places, icon: Bundle.main.url(forResource: "something", withExtension: "icns"))
            finished(nil)
        } catch { finished(error.sentence) }
    }
}
