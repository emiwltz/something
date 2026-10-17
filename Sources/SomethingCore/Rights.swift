// What a space may do (contract 5): the rights' words, the scope matched on whole path components, the `granted` a
// space receives, the grants file the engine keeps outside the spaces folder, and what to ask again at an opening.
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
    public init(declared: Asked, at: String) { (self.declared, self.at) = (declared, at) }
}

/// The part of a declaration the person answers.
public struct Asked: Codable, Equatable, Sendable {
    public var rights: [String], agents: Scope, folder: String?
    public init(_ declaration: Declaration) { (rights, agents, folder) = (declaration.rights, declaration.agents, declaration.folder) }
}

/// The engine's own file (~/Library/Application Support/something/app.json in the app): the default space and the grants.
public struct AppFile: Codable, Equatable, Sendable {
    public var app = 1
    public var `default`: String?
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

/// What an opening must ask the person: declared rights never answered, whether the scope is new or wider than the
/// one answered, and whether a launch folder must be chosen or confirmed. Nothing when all are empty or false.
public struct ToAsk: Equatable, Sendable {
    public var rights: [String], scope: Bool, folder: Bool
    public var isEmpty: Bool { rights.isEmpty && !scope && !folder }
}

public enum Rights {
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

    /// The state limited to what a space sees (contract 3.4): the agents it launched, and those in its scope when it
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
        let allowed = grant?.granted ?? [], refused = grant?.refused ?? []
        for right in declaration.rights {
            if covers(allowed, right) { granted.rights.append(right) }
            // A wider right declared after a narrower one was allowed keeps what was allowed, until the person answers.
            else { granted.rights += allowed.filter { covers([right], $0) && !granted.rights.contains($0) } }
            if !covers(allowed, right), covers(refused, right) { granted.refused.append(right) }
        }
        if case .folders(let folders) = declaration.agents { granted.agents = .folders(folders.map { grant?.remap[$0] ?? Declaration.expand($0, home: home) ?? $0 }) }
        else { granted.agents = .all }
        return granted
    }

    /// What to ask at this opening: everything at the first one; afterwards only a right never answered, a scope wider
    /// than the one answered, or a declared folder that changed. Refusals are remembered and not asked again.
    public static func toAsk(_ declaration: Declaration, since grant: Grant?) -> ToAsk {
        let answered = (grant?.granted ?? []) + (grant?.refused ?? [])
        let rights = declaration.rights.filter { !covers(answered, $0) }
        let launches = declaration.rights.contains { $0.hasPrefix("launch") && !covers(grant?.refused ?? [], $0) }
        guard let grant else { return ToAsk(rights: rights, scope: true, folder: launches) }
        let folder = launches && (grant.folder == nil || declaration.folder != grant.declared.folder)
        return ToAsk(rights: rights, scope: wider(declaration.agents, than: grant.declared.agents), folder: folder)
    }

    /// The grant after the person answered: their allowed and refused rights replace earlier answers for the same
    /// words, the declaration becomes the one answered, and `folder`, when given, becomes the folder in force.
    public static func answered(_ declaration: Declaration, allowed: [String], refused: [String], folder: String?,
                                at: String, after grant: Grant?) -> Grant {
        var next = grant ?? Grant(declared: Asked(declaration), at: at)
        next.granted = next.granted.filter { !refused.contains($0) } + allowed.filter { !next.granted.contains($0) }
        next.refused = next.refused.filter { !allowed.contains($0) } + refused.filter { !next.refused.contains($0) }
        (next.declared, next.at) = (Asked(declaration), at)
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
