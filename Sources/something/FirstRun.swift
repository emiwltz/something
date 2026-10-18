// What the app does at its start: it makes the folders it keeps for the person, puts the
// agents example in the spaces folder at its own first start, then chooses what to show: the default space, else `agents`
// while it is the only space, else Home.
import Foundation
import SomethingCore

enum FirstRun {
    /// Makes ~/something/spaces and ~/something/data under the places' home when they are missing. Throws a
    /// `SpaceError` when one cannot be made: without them no space can be kept.
    static func prepare(_ places: Places) throws {
        for folder in [places.spaces, places.data] {
            do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch {
                throw SpaceError("something cannot make \(folder.path): \(error.localizedDescription) Check that your home folder can be written.")
            }
        }
    }

    /// At the app's first start, copies the agents example of `examples` into the spaces folder, so that the person
    /// opens on their agents rather than on an empty Home, and marks the grants file `welcomed`. The first start
    /// is that mark, not a missing spaces folder: `something new`, run from a terminal before the app ever opened,
    /// makes that folder too. A space already named agents is kept as it is. Returns what went wrong, or nil:
    /// without the copy the app still starts, on Home.
    static func welcome(_ places: Places, examples: URL) -> String? {
        // A grants file that does not read is said when Home reads it; the welcome waits for a file it can mark.
        guard let file = try? AppFile.read(places.grants), file.welcomed != true else { return nil }
        if Spaces(root: places.spaces).named("agents") == nil {
            guard let agents = Spaces(root: examples).named("agents") else {
                return "The example agents is missing from \(examples.path); reinstall something to get it back."
            }
            do { try Home.copy(agents, into: places) } catch { return error.sentence }
        }
        do {
            // Read again: the copy forgot the answers a former space named agents left.
            var marked = try AppFile.read(places.grants)
            marked.welcomed = true
            try marked.write(places.grants)
        } catch { return error.sentence }
        return nil
    }

    /// The space to open at the start, or nil for Home. A default that names no space any more is passed over;
    /// a grants file that does not read has no default here, and the space window says it when a space opens.
    static func first(_ places: Places) -> Space? {
        let spaces = Spaces(root: places.spaces)
        if let name = (try? AppFile.read(places.grants))?.default, let space = spaces.named(name) { return space }
        let all = spaces.list()
        return all.map(\.name) == ["agents"] ? all.first : nil
    }
}
