// What the app does at its start (design 5, "First run"): it makes the folders it keeps for the person, puts the
// agents example in the spaces folder the first time, then chooses what to show: the default space, else `agents`
// while it is the only space (P15), else Home.
import Foundation
import SomethingCore

enum FirstRun {
    /// Makes ~/something/spaces and ~/something/data under the places' home when they are missing, and returns
    /// whether the spaces folder was made now: the first start. Throws a `SpaceError` when one cannot be made:
    /// without them no space can be kept.
    @discardableResult
    static func prepare(_ places: Places) throws -> Bool {
        let first = !FileManager.default.fileExists(atPath: places.spaces.path)
        for folder in [places.spaces, places.data] {
            do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch {
                throw SpaceError("something cannot make \(folder.path): \(error.localizedDescription) Check that your home folder can be written.")
            }
        }
        return first
    }

    /// Copies the agents example of `examples` into the spaces folder of a first start, so that the person opens on
    /// their agents rather than on an empty Home (P15). Returns what went wrong, or nil: without the copy the app
    /// still starts, on Home.
    static func welcome(_ places: Places, examples: URL) -> String? {
        guard let agents = Spaces(root: examples).named("agents") else {
            return "The example agents is missing from \(examples.path); reinstall something to get it back."
        }
        do { try Home.copy(agents, into: places) } catch { return error.sentence }
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
