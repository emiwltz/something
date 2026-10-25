// Each turn of a space's assistant as a version of that space, and its undo by the person's sentence. Before a turn,
// the space is kept as it is (a change no turn made is its own version first); when the turn ends, what it made is a
// version named by the sentence that asked for it, the toast says "Changed …" with Undo “…” ⌘Z, and the window's undo
// manager carries the same name, so the Edit menu and ⌘Z undo that sentence, after whatever typing the focused field
// undoes first. A Quick Change's turn is kept the same way, as a quick version. Undo and Redo restore a version, each
// itself a version; both wait while an assistant works on that space, whose next write would mix with the restore.
// The space is the turn's, never only the open one: a turn goes on after the person opens another space.
import AppKit
import SomethingCore

final class Changes {
    /// Which space an action of the undo manager changes: only those wait for an assistant.
    static let space = UndoManager.UserInfoKey("something.space")

    let places: Places
    let undo: WindowUndo
    /// The space of a name, as the spaces folder holds it now; nil once it is gone.
    var find: (String) -> Space? = { _ in nil }
    /// The name the window shows for a space: its title.
    var title: (String) -> String = { $0 }
    /// Whether an assistant works on a space now (AssistantModel.works).
    var working: (String) -> Bool = { _ in false }
    var recycle: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    /// Shows a toast: words, its action, whether it is only information, and how long it stays.
    var toast: (_ words: String, _ action: Toast.Action?, _ quiet: Bool, _ seconds: TimeInterval) -> Void = { _, _, _, _ in }
    /// The version each turn under way started from, by space.
    private var started: [String: String] = [:]

    init(places: Places, undo: WindowUndo) {
        (self.places, self.undo) = (places, undo)
        undo.allows = { [weak self] name in self?.allows(name) ?? true }
    }

    /// Follows the turns of `assistant`'s conversations, and says what changed in `shell`, the spaces titled as
    /// `library` lists them.
    func follow(_ assistant: AssistantModel, in shell: Shell, library: Library) {
        find = { [places] in Spaces(root: places.spaces).named($0) }
        title = { [weak library] name in library?.entry(name)?.title ?? name }
        working = { [weak assistant] in assistant?.works(on: $0) == true }
        recycle = { [weak library] url in try library?.recycle(url) }
        toast = { [weak shell] words, action, quiet, seconds in _ = shell?.toast(words, action: action, quiet: quiet, seconds: seconds) }
        assistant.turnStarts = { [weak self] in self?.before($0) }
        assistant.turnEnded = { [weak self] in self?.after($0, sentence: $1, who: $2) }
        assistant.quickEnded = { [weak self] in self?.quick($0, sentence: $1, who: $2, problem: $3) ?? false }
    }

    /// The store, with the person's limits as Settings has them now.
    var versions: Versions {
        let preferences = Preferences.at(places)
        return Versions(root: places.versions, keep: preferences.versionsKept, limit: preferences.storageLimit * 1_000_000)
    }

    /// A turn begins on the space `name`: it is kept as it is, when no version holds it yet.
    func before(_ name: String) {
        guard let space = find(name) else { return }
        do {
            try versions.capture(space, kind: .outside)
            started[name] = versions.list(name).first?.id
        } catch {
            started[name] = nil
        }
    }

    /// A Quick Change on `name` asked by `sentence` ended, `problem` saying what went wrong if anything did: what it
    /// changed is a quick version, offered to undo as a turn's is; a problem is said only when nothing changed, the
    /// change's own toast saying the rest. Returns whether the space changed.
    func quick(_ name: String, sentence: String, who: String, problem: String?) -> Bool {
        let made = after(name, sentence: sentence, who: who, kind: .quick)
        if made == nil, let problem { toast(problem, nil, true, 6) }
        return made != nil
    }

    /// The turn on `name` asked by `sentence` ended: when it changed the space, its version is kept, named by the
    /// sentence and `who` made it, and offered to undo. Returns that version; nil when nothing changed or nothing could
    /// be kept, which the toast then says.
    @discardableResult
    func after(_ name: String, sentence: String, who: String, kind: Versions.Kind = .turn) -> Versions.Version? {
        let from = started.removeValue(forKey: name)
        guard let space = find(name) else { return nil }
        let made: Versions.Version?
        do { made = try versions.capture(space, kind: kind, sentence: sentence, who: who) } catch {
            toast(error.sentence, nil, true, 6)
            return nil
        }
        guard let made else { return nil }
        // Without a version before it (the turn began on a space too heavy, since lightened), it cannot be undone.
        guard let back = from ?? versions.list(name).dropFirst().first?.id else {
            toast("Changed \(title(name))", nil, false, 3.2)
            return made
        }
        offer(name, sentence: sentence, back: back, forth: made.id)
        said(name, sentence: sentence, undone: false)
        return made
    }

    /// Registers the change of `name` by `sentence`, from the version `back` to `forth`, with the undo manager: undone,
    /// it restores `back`, and registers its own reverse, the Redo.
    private func offer(_ name: String, sentence: String, back: String, forth: String) {
        undo.registerUndo(withTarget: self) { changes in changes.restore(name, sentence: sentence, to: back, from: forth) }
        undo.setActionName(Changes.quoted(sentence))
        undo.setActionUserInfoValue(name, forKey: Changes.space)
    }

    /// Undo or Redo: `name` goes back to the version `target`, and the reverse is registered.
    private func restore(_ name: String, sentence: String, to target: String, from current: String) {
        let undoing = undo.isUndoing
        guard let space = find(name) else { return toast("\(title(name)) is gone; nothing was restored.", nil, true, 4) }
        do { try versions.restore(target, of: space, recycle: recycle) } catch {
            return toast(error.sentence, nil, true, 6)
        }
        offer(name, sentence: sentence, back: current, forth: target)
        said(name, sentence: sentence, undone: undoing)
    }

    /// The toast of a change, or of its undo: "Changed Daily brief" with Undo “…” ⌘Z, or Undone “…” with Redo ⇧⌘Z,
    /// whose action acts while that change is still the next one to undo or redo.
    private func said(_ name: String, sentence: String, undone: Bool) {
        let quoted = Changes.quoted(sentence)
        if undone {
            toast("Undone \(quoted)", Toast.Action(label: "Redo ⇧⌘Z") { [weak self] in
                guard let self, undo.redoActionUserInfoValue(forKey: Changes.space) as? String == name, undo.redoActionName == quoted else { return }
                undo.redo()
            }, false, 6)
        } else {
            toast("Changed \(title(name))", Toast.Action(label: "Undo \(quoted) ⌘Z") { [weak self] in
                guard let self, undo.undoActionUserInfoValue(forKey: Changes.space) as? String == name, undo.undoActionName == quoted else { return }
                undo.undo()
            }, false, 9)
        }
    }

    /// Whether the change of `name` may be undone or redone now; when an assistant works on it, the toast says to wait.
    private func allows(_ name: String) -> Bool {
        guard working(name) else { return true }
        toast("\(title(name))’s assistant is working · undo once it’s done", nil, true, 4)
        return false
    }

    /// The sentence as the toast and the Edit menu name it: one line, quoted, cut past 40 characters.
    static func quoted(_ sentence: String) -> String { "“\(Words.oneLine(sentence))”" }
}

/// The window's undo manager: a space's change waits, where it is, while an assistant works on that space.
final class WindowUndo: UndoManager {
    /// Whether the change of a space may be undone or redone now.
    var allows: (_ space: String) -> Bool = { _ in true }

    override func undo() {
        if let name = undoActionUserInfoValue(forKey: Changes.space) as? String, !allows(name) { return }
        super.undo()
    }

    override func redo() {
        if let name = redoActionUserInfoValue(forKey: Changes.space) as? String, !allows(name) { return }
        super.redo()
    }
}
