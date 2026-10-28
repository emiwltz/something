// The one queue of the agents' requests the person has not answered: in the order they came, the one on screen, the
// steps between them, which wrap, and the counts the window shows: all of them for the Dock, their spaces for Needs
// You, a space's own for its sticker's label. A request answered stays in the state until its agent takes the answer;
// it never comes back into the queue meanwhile.
import Observation
import SomethingCore

@Observable final class RequestQueue {
    /// The requests waiting, oldest first.
    private(set) var waiting: [Request] = []
    /// The index of the one on screen in `waiting`.
    private(set) var current = 0
    @ObservationIgnored private var answered: Set<String> = []
    /// The space a request belongs to, by name, or nil: the app's (`RequestQueue.space`).
    @ObservationIgnored var space: (Request) -> String? = { _ in nil }

    /// The request on screen; nil while none waits.
    var shown: Request? { waiting.indices.contains(current) ? waiting[current] : nil }

    /// "2 of 3" while more than one waits.
    var position: String? { Words.position(current, of: waiting.count) }

    /// The requests waiting for `name`'s space.
    func count(in name: String) -> Int { waiting.count { space($0) == name } }

    /// Follows the state's requests, oldest first: a new one joins at the end, one that left (withdrawn or answered
    /// and taken) leaves. The one on screen stays on screen while it waits; else its place goes to the next.
    func follow(_ open: [Request]) {
        let now = Dictionary(open.map { ($0.id, $0) }) { first, _ in first }
        // Forgotten once its agent took the answer: the same id would then be a new request.
        answered.formIntersection(now.keys)
        let new = open.filter { request in !answered.contains(request.id) && !waiting.contains { $0.id == request.id } }
        keep(waiting.compactMap { now[$0.id] } + new)
    }

    /// Whether `id` waits here or was answered.
    func knows(_ id: String) -> Bool { answered.contains(id) || waiting.contains { $0.id == id } }

    /// Takes `id` out once the person answered it, for good.
    func answer(_ id: String) { drop(id) }

    /// Takes `id` out for good when its details are gone: it closed, though it may linger in the state. Held out
    /// until it leaves the state, as an answered one.
    func drop(_ id: String) {
        answered.insert(id)
        keep(waiting.filter { $0.id != id })
    }

    private func keep(_ kept: [Request]) {
        guard kept != waiting else { return }
        let was = shown?.id, removedBefore = waiting.prefix(current).count { old in !kept.contains { $0.id == old.id } }
        waiting = kept
        current = kept.firstIndex { $0.id == was } ?? min(max(0, current - removedBefore), max(0, kept.count - 1))
    }

    /// Puts `id` on screen, when it waits.
    func select(_ id: String) {
        if let index = waiting.firstIndex(where: { $0.id == id }) { current = index }
    }

    /// Moves the one on screen by `by`, wrapping at both ends.
    func step(_ by: Int) {
        guard !waiting.isEmpty else { return }
        current = ((current + by) % waiting.count + waiting.count) % waiting.count
    }

    /// The space a request of `agent` belongs to: the person's assistant's is the space it works on (`working`), any
    /// other agent's is the space that launched it (`launches`, by space name); nil when none did.
    static func space(of agent: String, assistant: Bool, working: String?, launches: [String: Set<String>]) -> String? {
        assistant ? working : launches.first { $0.value.contains(agent) }?.key
    }
}
