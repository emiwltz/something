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
    /// The declared rights and where each stands; empty until the person answered the space once.
    private(set) var rights: [(right: String, standing: Standing)] = []
    private(set) var journal: [String] = [], notes: [String] = []
    /// Where the agents the space launches work, when a folder was chosen.
    private(set) var folder: String?
    /// Why the rights cannot be shown: the grants file does not read.
    private(set) var problem: String?

    enum Standing: Equatable {
        case allowed, refused
        /// Declared after the last answer: asked at the next opening. `inForce` holds the narrower words allowed
        /// earlier that the space keeps until then.
        case notAnswered(inForce: [String])
    }

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
        rights = []
        journal = []
        folder = nil
        problem = nil
        notes = kinds().sorted { $0.key < $1.key }.compactMap { kind, about in about.note.map { "\(Ask.name(of: kind)): \($0)" } }
        if let space {
            do {
                let grant = try AppFile.read(places.grants).spaces[space.name]
                if let grant { rights = Card.standings(Declaration.read(space, home: places.home), grant, home: places.home) }
                folder = grant?.folder
            } catch {
                problem = error.sentence
            }
            do {
                journal = try Journal(folder: places.journals).last(100, space: space.name).map(Card.words)
            } catch {
                journal = [error.sentence]
            }
        }
        draw()
    }

    /// Where each declared right stands, by what the space receives: the same reading as its `granted`.
    static func standings(_ reading: DeclarationReading, _ grant: Grant, home: URL) -> [(right: String, standing: Standing)] {
        let force = Rights.granted(reading, grant, limits: [:], home: home)
        return (reading.declaration?.rights ?? []).map { right in
            if force.rights.contains(right) { return (right, .allowed) }
            if force.refused.contains(right) { return (right, .refused) }
            return (right, .notAnswered(inForce: force.rights.filter { $0 != right && Rights.covers([right], $0) }))
        }
    }

    /// Allows or refuses one declared right, as the person's answer, and tells the open space. A space never
    /// answered has no switch: its first answers are given in its rights window, with its scope and folder.
    func set(_ right: String, allowed: Bool) {
        let declared = space.flatMap { Declaration.read($0, home: places.home).declaration?.rights } ?? []
        change { grant in
            guard var next = grant else { return }
            // A wider or a narrower word answered earlier would decide in place of this answer. A wider one also
            // answered the other declared rights it covers: they keep that answer.
            let related = { (word: String) in Rights.covers([right], word) || Rights.covers([word], right) }
            let kept = { (words: [String]) in
                words.filter { $0 != right && Rights.covers([$0], right) }
                    .flatMap { wider in declared.filter { $0 != right && !related($0) && Rights.covers([wider], $0) } }
            }
            let (keptAllowed, keptRefused) = (kept(next.granted), kept(next.refused))
            next.granted.removeAll(where: related)
            next.refused.removeAll(where: related)
            next.granted += keptAllowed.filter { !next.granted.contains($0) }
            next.refused += keptRefused.filter { !next.refused.contains($0) }
            if allowed { next.granted.append(right) } else { next.refused.append(right) }
            next.at = ISO8601DateFormatter().string(from: Date())
            grant = next
        }
        if let space { window(space.name)?.regrant() }
    }

    /// Clears the space's refusals (design 3.4): what it was allowed, its folder and its remap stay. The refused
    /// rights are asked again now if it is open, otherwise at its next opening.
    @objc func askAgain() {
        change { $0?.refused = [] }
        guard let space, let open = window(space.name) else { return }
        open.load()
        show(space)
    }

    /// Changes the space's grant in the grants file, then shows the card again; says a failure.
    private func change(_ edit: (inout Grant?) -> Void) {
        guard let space else { return }
        do {
            var file = try AppFile.read(places.grants)
            edit(&file.spaces[space.name])
            try file.write(places.grants)
        } catch {
            ask.tell(error.sentence)
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
        if let problem {
            view.addArrangedSubview(Card.line(problem))
        } else if rights.isEmpty {
            view.addArrangedSubview(NSTextField(wrappingLabelWithString: "Not answered yet: its rights are asked when it opens."))
        }
        for (index, line) in rights.enumerated() {
            guard case .notAnswered(let inForce) = line.standing else {
                let toggle = NSSwitch()
                toggle.state = line.standing == .allowed ? .on : .off
                toggle.tag = index
                toggle.target = self
                toggle.action = #selector(switched(_:))
                view.addArrangedSubview(NSStackView(views: [toggle, Card.line(Ask.words(for: line.right))]))
                continue
            }
            let now = inForce.isEmpty ? "" : " Allowed until then: " + inForce.map(Ask.words(for:)).joined(separator: "; ") + "."
            view.addArrangedSubview(Card.line("\(Ask.words(for: line.right)): asked at its next opening.\(now)"))
        }
        view.addArrangedSubview(NSButton(title: "Ask again", target: self, action: #selector(askAgain)))
        view.addArrangedSubview(Card.header("Journal"))
        let text = NSTextView()
        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        text.string = journal.isEmpty ? "Nothing yet: each write of the space is written here." : journal.joined(separator: "\n")
        text.autoresizingMask = [.width]
        view.addArrangedSubview(Card.scroll(text, height: 160))
        view.addArrangedSubview(Card.header("Readers"))
        view.addArrangedSubview(NSTextField(wrappingLabelWithString: notes.isEmpty ? "No note from the readers." : notes.joined(separator: "\n")))
    }

    /// A label that wraps at the column's width: a long path must not widen the window.
    static func line(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.preferredMaxLayoutWidth = 380
        return label
    }

    /// `content` in a column-wide scroll view `height` points tall: Home's lists and the card's journal.
    static func scroll(_ content: NSView, height: CGFloat) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.documentView = content
        scroll.hasVerticalScroller = true
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 420).isActive = true
        return scroll
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
}
