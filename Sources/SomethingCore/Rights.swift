// What a space may do: the rights' words, the one level a person chooses for them, the lasting rules they keep, the
// scope matched on whole path components, the `granted` a space receives, the grants file the engine keeps outside the
// spaces folder, and what to ask again at an opening.
// A space never inherits rights by name: grants are keyed by name, so whoever imports, renames or deletes a space removes its entry.
import Foundation

/// The person's answers for one space, as the grants file keeps them. Every key is required when read: the engine
/// always writes the whole file, and a file edited by hand that misses one reads as unreadable, never as half known.
public struct Grant: Codable, Equatable, Sendable {
    /// What the declaration asked when the person last answered: what the next opening is compared with.
    public var declared: Asked
    public var granted: [String] = [], refused: [String] = []
    /// The folder in force for launches, absolute; nil when none was chosen.
    public var folder: String?
    /// For a scope folder, as declared, that is not on this Mac: the absolute folder the person chose in its place.
    public var remap: [String: String] = [:]
    public var at: String
    /// The level the person chose for the whole space; nil for answers given right by right, before levels (optional,
    /// so that a grants file written before them still reads).
    public var level: Level?
    /// The commands the person allowed "Always for this space" (optional, so that an older grants file still reads).
    public var rules: [Rule]?
    /// The agents `state` shows, as the person's sentence says: it wins over the declared scope; nil follows the declared
    /// one (optional, as `level` is, and so is `start`).
    public var scope: Scope?
    /// The one agent Run may start, when the person named it.
    public var start: Start?
    public init(declared: Asked, at: String) { (self.declared, self.at) = (declared, at) }
}

/// A lasting rule: one exact command an agent of `kind` working in `folder` (absolute) may run for the space without
/// asking again, kept `at` (ISO 8601). It covers that command only, never another, a longer one or another folder.
public struct Rule: Codable, Hashable, Sendable {
    public var kind: String, command: String, folder: String, at: String
    public init(kind: String, command: String, folder: String, at: String) { (self.kind, self.command, self.folder, self.at) = (kind, command, folder, at) }
}

extension Grant {
    /// An agent of `kind` a space may start, with the model and effort a launch that names none takes.
    public struct Start: Codable, Equatable, Sendable {
        public var kind: String, model: String?, effort: String?
        public init(kind: String, model: String? = nil, effort: String? = nil) { (self.kind, self.model, self.effort) = (kind, model, effort) }
    }

    /// How far a space may work with the person's agents, one choice for all its rights: none, see them (`state`), see
    /// and write to them (`send`), or also start them in a folder the person picks (`launch`). Its memory (`store`)
    /// needs no level: it never leaves the space. A level is how the person answers; the rights stay the contract's words.
    public enum Level: String, Codable, CaseIterable, Comparable, Sendable {
        case none, watch, talk, run

        /// The words this level allows, each covering the same word narrowed to a kind ("send" covers "send:claude").
        public var words: [String] { Array(["state", "send", "launch"].prefix(Level.allCases.firstIndex(of: self) ?? 0)) }

        /// The highest level `rights` use: what a page that declares them needs to do all it says.
        public static func needed(by rights: [String]) -> Level {
            allCases.last { level in level != .none && rights.contains { Rights.covers([level.words.last ?? ""], $0) } } ?? .none
        }

        public static func < (a: Level, b: Level) -> Bool { (allCases.firstIndex(of: a) ?? 0) < (allCases.firstIndex(of: b) ?? 0) }
    }
}

/// The part of a declaration the person answers.
public struct Asked: Codable, Equatable, Sendable {
    public var rights: [String], agents: Scope, folder: String?
    public init(_ declaration: Declaration) { (rights, agents, folder) = (declaration.rights, declaration.agents, declaration.folder) }
}

/// The engine's own file (~/Library/Application Support/something/app.json in the app): the grants.
public struct AppFile: Codable, Equatable, Sendable {
    public var app = 1
    public var spaces: [String: Grant] = [:]
    public init() {}
    /// The file at `url`, or an empty one when it does not exist yet. Throws a `SpaceError` when it is there but does
    /// not read: starting empty would forget every answer the person gave, and the next write would erase them.
    public static func read(_ url: URL) throws -> AppFile {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppFile() }
        guard let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(AppFile.self, from: data) else {
            throw SpaceError("The grants in \(url.path) cannot be read; something leaves the file as it is. Move it away to answer every space again.")
        }
        return file
    }
    /// Writes the whole file at once. Throws a `SpaceError` when it cannot be written.
    public func write(_ url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(self).write(to: url, options: .atomic)
        } catch {
            throw SpaceError("The grants could not be written to \(url.path): \(error.localizedDescription)")
        }
    }
}

/// The grants file's one owner: every change, in the app as in the command, is a read, a change and a write under an
/// exclusive lock on app.json.lock, so `something new` in a terminal and a rights window in the app never undo each
/// other. The lock is taken on a file descriptor of its own at each update, so two threads exclude each other as two
/// processes do. It is never held while the person is asked.
public struct Grants: Sendable {
    public let url: URL
    public init(_ url: URL) { self.url = url }

    /// The file as it is now. Throws as `AppFile.read`.
    public func read() throws -> AppFile { try AppFile.read(url) }

    /// Reads the file, applies `change`, and writes it when it changed; returns the file as it is after. Throws a
    /// `SpaceError` when the lock cannot be taken, as `AppFile.read` and `write` do, or what `change` throws.
    @discardableResult
    public func update(_ change: (inout AppFile) throws -> Void) throws -> AppFile {
        let lock = url.appendingPathExtension("lock").path
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let held = open(lock, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard held >= 0 else { throw SpaceError("The grants cannot be changed: \(lock) cannot be opened (\(String(cString: strerror(errno)))).") }
        // Closing the descriptor releases the lock, whatever happens below.
        defer { close(held) }
        guard flock(held, LOCK_EX) == 0 else { throw SpaceError("The grants cannot be changed: \(lock) cannot be locked.") }
        var file = try AppFile.read(url)
        let before = file
        try change(&file)
        if file != before { try file.write(url) }
        return file
    }
}

/// What an opening must ask the person: declared rights never answered, whether the scope is new or wider than the
/// one answered, and whether a launch folder must be chosen or confirmed. Nothing when all are empty or false.
public struct ToAsk: Equatable, Sendable {
    public var rights: [String], scope: Bool, folder: Bool
    public var isEmpty: Bool { rights.isEmpty && !scope && !folder }
}

public enum Rights {
    /// What an agent stays across its launches: its program and its conversation, else its id, which lasts as its process does.
    public static func key(_ agent: Agent) -> String { agent.thread.map { "\(agent.kind):\($0)" } ?? agent.id }

    /// The words a level grants or refuses; `store` is never asked.
    static let leveled = Grant.Level.run.words

    /// The level a grant is at: the one chosen, or for a grant answered right by right, the highest level whose
    /// declared rights were all allowed (a word the page did not declare neither raises nor stops it), never above what
    /// the page declared. Reading an older grant this way widens nothing.
    public static func level(of grant: Grant) -> Grant.Level {
        if let level = grant.level { return level }
        var reached = Grant.Level.none
        for level in Grant.Level.allCases.dropFirst() {
            guard let word = level.words.last else { continue }
            let declared = grant.declared.rights.filter { covers([word], $0) }
            if declared.isEmpty { continue }
            guard declared.allSatisfy({ covers(grant.granted, $0) }) else { break }
            reached = level
        }
        return reached
    }

    /// The grant once the person chose `level` for the space declaring `declaration`: the level's words allowed, the
    /// others refused, `folder` in force for Run (kept from before when nil). A later declaration asks nothing more: a
    /// right above the level stays refused, and Run's folder is the one chosen, whatever the page then declares. `start`,
    /// kept like the folder, narrows Run's `launch` to that kind, so that "may start pi" is what the bridge enforces;
    /// `scope` replaces the scope in force when given.
    public static func leveled(_ level: Grant.Level, folder: String?, declaration: Declaration, at: String, after grant: Grant?,
                               start: Grant.Start? = nil, scope: Scope? = nil) -> Grant {
        var next = grant ?? Grant(declared: Asked(declaration), at: at)
        (next.declared, next.at, next.level) = (Asked(declaration), at, level)
        next.start = level == .run ? start ?? next.start : nil
        next.scope = scope ?? next.scope
        (next.granted, next.refused) = (level.words.map { $0 == "launch" ? next.start.map { "launch:" + $0.kind } ?? $0 : $0 }, leveled.filter { !level.words.contains($0) })
        next.folder = level == .run ? folder ?? next.folder : nil
        return next
    }

    /// Whether `command` is one plain command a rule may keep: no chain, pipe, redirection, substitution, variable or
    /// second line, so that a rule never allows more than the person read.
    public static func single(_ command: String) -> Bool {
        !command.trimmingCharacters(in: .whitespaces).isEmpty && command.rangeOfCharacter(from: CharacterSet(charactersIn: ";&|<>`$\\\n\r")) == nil
    }

    /// The rule of `grant` that allows exactly `command` for an agent of `kind` working in `folder`; nil when none does.
    public static func rule(in grant: Grant?, kind: String, command: String, folder: String?) -> Rule? {
        guard single(command), let folder else { return nil }
        return grant?.rules?.first { $0.kind == kind && $0.command == command && $0.folder == folder }
    }

    /// Whether one of `words` covers `right`: the same word, or a word without a kind for a right with one
    /// ("send" covers "send:claude", never the reverse).
    public static func covers(_ words: [String], _ right: String) -> Bool { words.contains { $0 == right || (!$0.contains(":") && right.hasPrefix($0 + ":")) } }

    /// Whether `path` is `folder` or inside it, by whole path components after `..` and `.` are resolved, so
    /// /code/shop2 is not inside /code/shop. Both are absolute.
    public static func inside(_ path: String, _ folder: String) -> Bool {
        let path = URL(fileURLWithPath: path).standardizedFileURL.path, folder = URL(fileURLWithPath: folder).standardizedFileURL.path
        return path == folder || path.hasPrefix(folder == "/" ? "/" : folder + "/")
    }

    /// Whether an agent working in `folder` is in `scope`. An agent whose folder is unknown is in no folder scope.
    public static func contains(_ scope: Scope, _ folder: String?) -> Bool {
        guard case .folders(let folders) = scope else { return true }
        return folder.map { path in folders.contains { inside(path, $0) } } ?? false
    }

    /// The state limited to what a space sees: the agents it launched, and those in its scope when it
    /// holds `state`; the threads and requests of those agents only.
    public static func visible(_ state: State, _ granted: Granted, launched: Set<String>) -> State {
        var state = state, sees = covers(granted.rights, "state")
        state.agents = state.agents.filter { launched.contains($0.id) || (sees && contains(granted.agents, $0.folder)) }
        let ids = Set(state.agents.map(\.id))
        (state.threads, state.requests) = (state.threads.filter { ids.contains($0.agent) }, state.requests.filter { ids.contains($0.agent) })
        return state
    }

    /// What the space receives as `something.granted`. `limits` comes from the drivers, the only ones that know what
    /// each kind cannot do; `~` in the scope is `home`, so a space compares absolute paths only.
    public static func granted(_ reading: DeclarationReading, _ grant: Grant?, limits: [String: [String]], home: URL) -> Granted {
        var granted = Granted()
        (granted.unavailable, granted.limits, granted.folder) = (reading.unavailable, limits, grant?.folder)
        guard let declaration = reading.declaration else { return granted }
        // A space's memory needs no permission: it never leaves the space.
        let allowed = (grant?.granted ?? []) + ["store"], refused = grant?.refused ?? []
        for right in declaration.rights {
            if covers(allowed, right) { granted.rights.append(right) }
            // A wider right declared after a narrower one was allowed keeps what was allowed, until the person answers.
            else { granted.rights += allowed.filter { covers([right], $0) && !granted.rights.contains($0) } }
            if !covers(allowed, right), covers(refused, right) { granted.refused.append(right) }
        }
        if let scope = grant?.scope { granted.agents = scope }
        else if case .folders(let folders) = declaration.agents { granted.agents = .folders(folders.map { grant?.remap[$0] ?? Declaration.expand($0, home: home) ?? $0 }) }
        else { granted.agents = .all }
        return granted
    }

    /// What to ask at this opening: everything at the first one; afterwards only a right never answered, a scope wider
    /// than the one answered, or a declared folder that changed. Refusals are remembered and not asked again. The scope
    /// says which agents `state` shows, so it is asked with `state` and only while `state` is declared and not refused.
    public static func toAsk(_ declaration: Declaration, since grant: Grant?) -> ToAsk {
        // A level answers every right; only Run without a folder chosen yet asks again.
        if let grant, let level = grant.level {
            return ToAsk(rights: [], scope: false, folder: level == .run && grant.folder == nil && declaration.rights.contains { $0.hasPrefix("launch") })
        }
        let answered = (grant?.granted ?? []) + (grant?.refused ?? []) + ["store"]
        let rights = declaration.rights.filter { !covers(answered, $0) }
        let launches = declaration.rights.contains { $0.hasPrefix("launch") && !covers(grant?.refused ?? [], $0) }
        let sees = declaration.rights.contains("state") && !covers(grant?.refused ?? [], "state")
        guard let grant else { return ToAsk(rights: rights, scope: sees, folder: launches) }
        let folder = launches && (grant.folder == nil || declaration.folder != grant.declared.folder)
        let scope = sees && (rights.contains("state") || wider(declaration.agents, than: grant.declared.agents))
        return ToAsk(rights: rights, scope: scope, folder: folder)
    }

    /// The grant after the person answered: their allowed and refused rights replace earlier answers for the same
    /// words, the declaration becomes the one answered, and `folder`, when given, becomes the folder in force. Answers
    /// given right by right replace a level.
    public static func answered(_ declaration: Declaration, allowed: [String], refused: [String], folder: String?,
                                at: String, after grant: Grant?) -> Grant {
        var next = grant ?? Grant(declared: Asked(declaration), at: at)
        next.granted = next.granted.filter { !refused.contains($0) } + allowed.filter { !next.granted.contains($0) }
        next.refused = next.refused.filter { !allowed.contains($0) } + refused.filter { !next.refused.contains($0) }
        (next.declared, next.at, next.level) = (Asked(declaration), at, nil)
        if let folder { next.folder = folder }
        return next
    }

    /// Whether `scope` shows an agent that `old` did not. Paths are compared as written: a folder written another way
    /// counts as wider, which only asks once more.
    static func wider(_ scope: Scope, than old: Scope) -> Bool {
        switch (scope, old) {
        case (_, .all): return false
        case (.all, .folders): return true
        case (.folders(let new), .folders(let old)):
            // `~` stands for a home this comparison does not need: as a first component it compares like any other.
            func rooted(_ path: String) -> String { path.hasPrefix("~") ? "/" + path : path }
            return new.contains { folder in !old.contains { inside(rooted(folder), rooted($0)) } }
        }
    }
}
