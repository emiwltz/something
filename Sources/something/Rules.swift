// What something answers by itself, only where the person said so (AGENTS.md rule 2): a lasting rule kept with "Always
// for this space" (one exact command, one kind of agent, one folder, in the space's grant, so that a rename, an import
// or a deletion drops it as it drops the level), and Full Access for the person's assistant alone (Settings › Advanced,
// one confirmation, an orange mark in the toolbar while it is on). Agents a space starts keep their own settings under
// Full Access, and a question always waits for the person. Here: the rule a request could keep, whether one applies,
// keeping and revoking one, every rule for Settings, Full Access's confirmation and its mark.
import AppKit
import SomethingAgents
import SomethingCore

/// One lasting rule as Info and Settings list it: the space it is kept for, by name and title, and the rule.
struct LastingRule: Identifiable, Equatable {
    let space: String, title: String, rule: Rule
    var id: String { [space, rule.kind, rule.folder, rule.command].joined(separator: "\u{0}") }
}

enum Rules {
    /// Full Access's colour, the mockup's.
    static let orange = Look.srgb(0xD9822B, 1)

    /// The rule a permission could keep: a plain command, `input`, of an agent a space started (never an assistant),
    /// whose folder is known, for a space that has a grant. nil when "Always for this space" is not offered.
    static func offer(_ request: Request, input: String?, agent: Agent?, assistant: Bool, grant: Grant?, at: String) -> Rule? {
        guard request.kind == "permission", !assistant, grant != nil, Words.isCommand(request.tool), let agent, let folder = agent.folder,
              let input, Rights.single(input) else { return nil }
        return Rule(kind: agent.kind, command: input, folder: folder, at: at)
    }

    /// Whether something answers a request by itself: a permission of the person's assistant while Full Access is on,
    /// or a command, `input`, that a lasting rule of `grant` keeps exactly for `agent`. Never a question.
    static func alone(_ request: Request, input: String?, agent: Agent?, assistant: Bool, fullAccess: Bool, grant: Grant?) -> Bool {
        guard request.kind == "permission" else { return false }
        if assistant { return fullAccess }
        guard let agent, let input else { return false }
        return Rights.rule(in: grant, kind: agent.kind, command: input, folder: agent.folder) != nil
    }

    /// Keeps `rule` in the grant of the space `name`, once. Throws as `Grants.update`.
    static func keep(_ rule: Rule, in name: String, _ grants: Grants) throws {
        try grants.update { file in
            guard var grant = file.spaces[name], Rights.rule(in: grant, kind: rule.kind, command: rule.command, folder: rule.folder) == nil else { return }
            grant.rules = (grant.rules ?? []) + [rule]
            file.spaces[name] = grant
        }
    }

    /// Takes `rule` out of the grant of the space `name`: the next request for that command asks again. Throws as
    /// `Grants.update`.
    static func revoke(_ rule: Rule, in name: String, _ grants: Grants) throws {
        try grants.update { file in
            guard var grant = file.spaces[name] else { return }
            grant.rules = grant.rules?.filter { $0 != rule }
            if grant.rules?.isEmpty == true { grant.rules = nil }
            file.spaces[name] = grant
        }
    }

    /// Every lasting rule, space by space in `spaces`' order (name and title), oldest first in each; none when the
    /// grants do not read.
    static func all(_ grants: Grants, spaces: [(id: String, title: String)]) -> [LastingRule] {
        let file = try? grants.read()
        return spaces.flatMap { space in (file?.spaces[space.id]?.rules ?? []).map { LastingRule(space: space.id, title: space.title, rule: $0) } }
    }

    /// "Claude Code · in ~/code/atelier · for Project watch · since 21 Oct": what a rule keeps, in Settings' words;
    /// `space` left out in Info, which is the space's own.
    static func line(_ rule: Rule, space: String?, home: String, now: Date) -> String {
        let day = iso8601.date(from: rule.at).map { Info.day($0, now: now) }
        let since = day.map { " · since " + (["Today", "Yesterday"].contains($0) ? $0.lowercased() : $0) } ?? ""
        return [Registry.app.name(of: rule.kind), "in " + Words.path(rule.folder, home: home), space.map { "for " + $0 }].compactMap { $0 }
            .joined(separator: " · ") + since
    }

    /// The one confirmation before Full Access: who gets what, what stays true; Cancel, the safe action, first in focus.
    static func confirmation() -> Sheet {
        Sheet(icon: .symbol("bolt.fill"), title: "Turn On Full Access?", body: [("Nobody asks you for your assistant anymore, until you turn it off.", false)],
              rows: [.init(mark: .symbol("bolt"), label: [("Your assistant changes any space and runs any command, without asking.", false)], meta: nil, plain: true),
                     .init(mark: .symbol("checkmark.shield"), label: [("The agents your spaces start still ask, as their own settings say.", false)],
                           meta: nil, plain: true)],
              fine: "Still true: a space never answers for you, a question still waits for you, nothing leaves your Mac, and your agents’ own settings stay untouched.",
              actions: [.init(title: "Turn On Full Access", role: .destructive), .init(title: "Cancel", role: .primary)], alert: true)
    }
}

/// The orange mark in the toolbar while Full Access is on: "Full Access" after a bolt; a click turns it off.
final class FullMark: NSButton {
    init(target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        (self.target, self.action, isBordered, title) = (target, action, false, "Full Access")
        toolTip = "Full Access is on: your assistant asks you nothing. Click to turn it off."
        setAccessibilityLabel("Full Access is on. Turn Off")
        setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { nil }

    private var words: NSAttributedString {
        NSAttributedString(string: title, attributes: [.font: Look.font(.ui, size: 11.5, weight: .semibold), .foregroundColor: Rules.orange])
    }

    override var intrinsicContentSize: NSSize { NSSize(width: (words.size().width + 8 + 12 + 5 + 8).rounded(.up), height: 22) }

    override func draw(_ dirtyRect: NSRect) {
        Rules.orange.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        let bolt = NSImage.symbol("bolt.fill", 10, .semibold).tinted(Rules.orange)
        bolt.draw(in: NSRect(x: 8, y: ((bounds.height - bolt.size.height) / 2).rounded(), width: bolt.size.width, height: bolt.size.height))
        words.draw(at: NSPoint(x: 25, y: ((bounds.height - words.size().height) / 2).rounded()))
    }
}

extension App {
    /// The panels hear of the rules and of Full Access: what "Always for this space" would keep, keeping it, and what
    /// something answers by itself.
    func followRules() {
        panels.offer = { [weak self] request, prompt in
            guard let self, let name = space(ofAgent: request.agent) else { return nil }
            return Rules.offer(request, input: prompt.input, agent: engine.state.agents.first { $0.id == request.agent },
                               assistant: engine.assistants.contains(request.agent),
                               grant: try? Grants(places.grants).read().spaces[name], at: iso8601.string(from: Date()))
        }
        panels.keep = { [weak self] rule, request in
            guard let self, let name = space(ofAgent: request.agent) else { return }
            do { try Rules.keep(rule, in: name, Grants(places.grants)) } catch { ask.tell(error.sentence) }
            if shell.infoShown { info.show(info.space) }
        }
        panels.alone = { [weak self] request, prompt in
            guard let self else { return false }
            return Rules.alone(request, input: prompt.input, agent: engine.state.agents.first { $0.id == request.agent },
                               assistant: engine.assistants.contains(request.agent), fullAccess: library.preferences.fullAccess,
                               grant: space(ofAgent: request.agent).flatMap { try? Grants(self.places.grants).read().spaces[$0] })
        }
        panels.allowed = { [weak self] request, prompt in
            guard let self, !engine.assistants.contains(request.agent), let name = space(ofAgent: request.agent), let command = prompt.input else { return }
            let kind = engine.state.agents.first { $0.id == request.agent }?.kind
            try? Journal(folder: places.journals).append(JournalLine(at: iso8601.string(from: Date()), action: "allow", agent: request.agent, kind: kind,
                                                                     text: command, result: "ok"), space: name)
            _ = shell.toast("Allowed by your rule · \(command)", quiet: true)
        }
    }

    /// Revoke, in Info or Settings: the rule goes from the space's grant, and Info shows it gone.
    func revoke(_ rule: Rule, in name: String) {
        do { try Rules.revoke(rule, in: name, Grants(places.grants)) } catch { ask.tell(error.sentence) }
        if shell.infoShown { info.show(info.space) }
    }

    /// Settings › Advanced's Full Access: turning it on asks once, in a sheet over Settings; turning it off does not.
    /// The toolbar's mark follows.
    func fullAccess(_ on: Bool, over window: NSWindow?) {
        guard on else { return setFullAccess(false) }
        guard let window, window.attachedSheet == nil else { return }
        Rules.confirmation().hang(on: window) { [weak self] in if $0 == .destructive { self?.setFullAccess(true) } }
    }

    func setFullAccess(_ on: Bool) {
        library.preferences.fullAccess = on
        shell.fullMark.isHidden = !on
        if !on { _ = shell.toast("Full Access is off · your assistant asks you again", quiet: true) }
    }

    /// The toolbar's mark: Full Access off.
    @objc func turnOffFullAccess(_ sender: Any?) { setFullAccess(false) }
}
