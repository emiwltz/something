// Info, the inspector beside the open space: its title and description, where it lives, where the agents it starts
// work, its rights with a switch each and "Ask Again", and its activity, the journal newest first. A switched right is
// kept in the grants file and reaches the open space at once as a `granted` event.
import AppKit
import Observation
import SomethingAgents
import SomethingCore
import SwiftUI

@Observable final class Info {
    @ObservationIgnored let places: Places
    @ObservationIgnored let ask: Asking
    /// The open space's view, which hears of a switched right at once.
    @ObservationIgnored var current: () -> SpaceView? = { nil }
    /// The agents of the state, so that the journal names each one it still knows.
    @ObservationIgnored var agents: () -> [Agent] = { [] }
    /// Show in Finder, by the space's name: the library's, which a test replaces so that Finder never opens.
    @ObservationIgnored var reveal: (String) -> Void = { _ in }
    private(set) var space: Space?
    private(set) var title = ""
    private(set) var about: String?
    /// The declared rights and where each stands; empty until the person answered the space once.
    private(set) var rights: [(right: String, standing: Standing)] = []
    /// Set when the space declares no right: it only shows its page, and is never asked about.
    private(set) var asksNothing = false
    /// The journal, newest first: a time and a sentence each.
    private(set) var activity: [(time: String, what: String)] = []
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
        self.places = places
        self.ask = ask
    }

    /// Shows `space`, or nothing when no space is open. Read again at each change: it is a few small files.
    func show(_ space: Space?) {
        self.space = space
        rights = []
        activity = []
        folder = nil
        problem = nil
        guard let space else { return }
        let reading = Declaration.read(space, home: places.home, kinds: Registry.app.kinds)
        title = reading.declaration?.title ?? space.name
        about = reading.declaration?.description
        asksNothing = reading.declaration?.rights.isEmpty ?? true
        do {
            let grant = try Grants(places.grants).read().spaces[space.name]
            if let grant { rights = Info.standings(reading, grant, home: places.home) }
            folder = grant?.folder
        } catch {
            problem = error.sentence
        }
        do {
            let names = Dictionary(agents().compactMap { agent in agent.name.map { (agent.id, $0) } }) { first, _ in first }
            activity = try Journal(folder: places.journals).last(100, space: space.name).reversed().map {
                let line = Words.journal($0, names: names, home: places.home.path).split(separator: "\t", maxSplits: 1)
                return (String(line[0]), line.count > 1 ? String(line[1]) : "")
            }
        } catch {
            activity = [("", error.sentence)]
        }
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
    /// answered has no switch: its first answers are given in its rights sheet, with its scope and folder.
    func set(_ right: String, allowed: Bool) {
        let declared = space.flatMap { Declaration.read($0, home: places.home, kinds: Registry.app.kinds).declaration?.rights } ?? []
        change { grant in
            guard var next = grant else { return }
            // A wider or a narrower word answered earlier would decide in place of this answer. A wider one also
            // answered the other declared rights it covers: they keep that answer.
            let related = { (word: String) in Rights.covers([right], word) || Rights.covers([word], right) }
            let kept = { (words: [String]) in
                words.filter { $0 != right && Rights.covers([$0], right) }
                    .flatMap { wider in declared.filter { $0 != right && !related($0) && Rights.covers([wider], $0) } }
            }
            let keptAllowed = kept(next.granted)
            let keptRefused = kept(next.refused)
            next.granted.removeAll(where: related)
            next.refused.removeAll(where: related)
            next.granted += keptAllowed.filter { !next.granted.contains($0) }
            next.refused += keptRefused.filter { !next.refused.contains($0) }
            if allowed { next.granted.append(right) } else { next.refused.append(right) }
            next.at = iso8601.string(from: Date())
            grant = next
        }
        open()?.regrant()
    }

    /// Clears the space's refusals: what it was allowed, its folder and its remap stay. The refused rights are asked
    /// again now if it is open, otherwise at its next opening.
    func askAgain() {
        change { $0?.refused = [] }
        // Just after the button's action: the rights sheet waits for the person, and the view must not wait inside it.
        DispatchQueue.main.async { [weak self] in
            guard let self, let open = open() else { return }
            open.load()
            show(space)
        }
    }

    /// The open space's view, when it is the one shown here.
    private func open() -> SpaceView? { current().flatMap { $0.space.name == space?.name ? $0 : nil } }

    /// Changes the space's grant in the grants file, then shows it again; says a failure.
    private func change(_ edit: (inout Grant?) -> Void) {
        guard let space else { return }
        do { try Grants(places.grants).update { edit(&$0.spaces[space.name]) } } catch { ask.tell(error.sentence) }
        show(space)
    }
}

struct InspectorView: View {
    @Bindable var info: Info

    var body: some View {
        if let space = info.space {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.title).font(.system(size: 17, weight: .semibold))
                        if let about = info.about { Text(about).foregroundStyle(.secondary) }
                    }
                    part("Location") {
                        Text(Words.path(space.location.path, home: info.places.home.path))
                            .lineLimit(1).truncationMode(.middle).help(space.location.path).textSelection(.enabled)
                        Button("Show in Finder") { info.reveal(space.name) }
                            .buttonStyle(.link)
                    }
                    if let folder = info.folder {
                        part("Agents it starts work in") {
                            Text(Words.path(folder, home: info.places.home.path)).lineLimit(1).truncationMode(.middle).help(folder)
                        }
                    }
                    part("Permissions") { permissions }
                    part("Activity") { activity }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        } else {
            Text("No space is open.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var permissions: some View {
        if let problem = info.problem {
            Text(problem)
        } else if info.asksNothing {
            Text("It asks for nothing: it only shows its page.").foregroundStyle(.secondary)
        } else if info.rights.isEmpty {
            Text("Not answered yet: it asks when it opens.").foregroundStyle(.secondary)
        }
        ForEach(info.rights, id: \.right) { line in
            if case .notAnswered(let inForce) = line.standing {
                let now = inForce.isEmpty ? "" : " Allowed until then: " + inForce.map(Ask.words(for:)).joined(separator: "; ") + "."
                Text("\(Ask.words(for: line.right)): asked when it next opens.\(now)").foregroundStyle(.secondary)
            } else {
                Toggle(isOn: Binding(get: { line.standing == .allowed }, set: { info.set(line.right, allowed: $0) })) {
                    Text(Ask.words(for: line.right)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch).controlSize(.small)
            }
        }
        if info.rights.contains(where: { $0.standing == .refused }) {
            Button("Ask Again") { info.askAgain() }
        }
    }

    @ViewBuilder private var activity: some View {
        if info.activity.isEmpty {
            Text("Nothing yet. Each time this space writes to, starts or changes an agent, or opens a link, it shows here.")
                .foregroundStyle(.secondary)
        } else {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(Array(info.activity.enumerated()), id: \.offset) { _, line in
                    GridRow {
                        Text(line.time).monospacedDigit().foregroundStyle(.secondary)
                        Text(line.what).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.callout)
        }
    }

    private func part(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }
}
