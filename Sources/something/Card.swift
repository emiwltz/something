// The space card (design 5), shown in Home beside the list: the rights of the selected space with a switch each,
// "Ask again", where the space lives and where its agents work, the last 100 lines of its journal, and the readers'
// notes. A switched right is kept in the grants file and reaches the open space at once as a `granted` event.
import AppKit
import SomethingCore

final class Card: NSObject {
    let places: Places, ask: Asking
    /// The readers' notes come from the state's `kinds`.
    var kinds: () -> [String: Kind] = { [:] }
    /// The open window of a space, by name, if one is open: it hears of a change at once.
    var window: (String) -> SpaceWindow? = { _ in nil }
    let view = NSStackView()
    private(set) var space: Space?
    /// The declared rights and whether each is allowed; empty until the person answered the space once.
    private(set) var rights: [(right: String, allowed: Bool)] = []
    private(set) var journal: [String] = [], notes: [String] = []
    /// Where the agents the space launches work, when a folder was chosen.
    private(set) var folder: String?

    init(places: Places, ask: Asking) {
        (self.places, self.ask) = (places, ask)
        super.init()
        view.orientation = .vertical
        view.alignment = .leading
        view.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    }

    /// Shows `space`, or nothing when no space is selected.
    func show(_ space: Space?) {
        self.space = space
        (rights, journal, folder) = ([], [], nil)
        notes = kinds().sorted { $0.key < $1.key }.compactMap { kind, about in about.note.map { "\(Ask.name(of: kind)): \($0)" } }
        if let space {
            let grant = (try? AppFile.read(places.grants))?.spaces[space.name]
            let declared = Declaration.read(space, home: places.home).declaration?.rights ?? []
            if let grant { rights = declared.map { ($0, Rights.covers(grant.granted, $0)) } }
            folder = grant?.folder
            do {
                journal = try Journal(folder: places.journals).last(100, space: space.name).map(Card.words)
            } catch {
                journal = [(error as? SpaceError)?.message ?? "\(error)"]
            }
        }
        draw()
    }

    /// Allows or refuses one declared right, as the person's answer, and tells the open space. A space never
    /// answered has no switch: its first answers are given in its rights window, with its scope and folder.
    func set(_ right: String, allowed: Bool) {
        change { grant in
            // A wider or a narrower word answered earlier would decide in place of this answer.
            let related = { (word: String) in Rights.covers([right], word) || Rights.covers([word], right) }
            grant?.granted.removeAll(where: related)
            grant?.refused.removeAll(where: related)
            allowed ? grant?.granted.append(right) : grant?.refused.append(right)
            grant?.at = ISO8601DateFormatter().string(from: Date())
        }
        if let space { window(space.name)?.regrant() }
    }

    /// Forgets every answer for the space: it asks everything again now if it is open, otherwise at its next opening.
    func askAgain() {
        change { $0 = nil }
        if let space { window(space.name)?.load() }
    }

    /// Changes the space's grant in the grants file, then shows the card again; says a failure.
    private func change(_ edit: (inout Grant?) -> Void) {
        guard let space else { return }
        do {
            var file = try AppFile.read(places.grants)
            edit(&file.spaces[space.name])
            try file.write(places.grants)
        } catch {
            ask.tell((error as? SpaceError)?.message ?? "\(error)")
        }
        show(space)
    }

    static func words(_ line: JournalLine) -> String {
        let what = [line.action, line.kind, line.agent, line.when].compactMap { $0 }.joined(separator: " ")
        return "\(line.at)  \(what)  \(line.result)" + (line.text.map { "  “\($0.prefix(120))”" } ?? "")
    }

    private func draw() {
        view.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let space else {
            view.addArrangedSubview(NSTextField(labelWithString: "Select a space to see its card."))
            return
        }
        view.addArrangedSubview(Card.line("Lives in \(space.location.path)"))
        if let folder { view.addArrangedSubview(Card.line("Agents it launches work in \(folder)")) }
        view.addArrangedSubview(Card.header("Rights"))
        if rights.isEmpty {
            view.addArrangedSubview(NSTextField(wrappingLabelWithString: "Not answered yet: its rights are asked when it opens."))
        }
        for (index, line) in rights.enumerated() {
            let toggle = NSSwitch()
            toggle.state = line.allowed ? .on : .off
            toggle.tag = index
            toggle.target = self
            toggle.action = #selector(switched(_:))
            view.addArrangedSubview(NSStackView(views: [toggle, Card.line(Ask.words(for: line.right))]))
        }
        view.addArrangedSubview(NSButton(title: "Ask again", target: self, action: #selector(askAgainClicked)))
        view.addArrangedSubview(Card.header("Journal"))
        let text = NSTextView()
        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        text.string = journal.isEmpty ? "Nothing yet: each write of the space is written here." : journal.joined(separator: "\n")
        let scroll = NSScrollView()
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        text.autoresizingMask = [.width]
        scroll.heightAnchor.constraint(equalToConstant: 160).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 420).isActive = true
        view.addArrangedSubview(scroll)
        view.addArrangedSubview(Card.header("Readers"))
        view.addArrangedSubview(NSTextField(wrappingLabelWithString: notes.isEmpty ? "No note from the readers." : notes.joined(separator: "\n")))
    }

    /// A label that wraps at the column's width: a long path must not widen the window.
    static func line(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.preferredMaxLayoutWidth = 380
        return label
    }

    static func header(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return label
    }

    @objc private func switched(_ toggle: NSSwitch) {
        guard rights.indices.contains(toggle.tag) else { return }
        set(rights[toggle.tag].right, allowed: toggle.state == .on)
    }

    @objc private func askAgainClicked() { askAgain() }
}
