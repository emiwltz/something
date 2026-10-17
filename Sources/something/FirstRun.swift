// What the app does at its start (design 5, "First run"): it makes the folders it keeps for the person, then
// chooses what to show: the default space, else `agents` while it is the only space (P15), else Home.
import Foundation
import SomethingCore

enum FirstRun {
    /// Makes ~/something/spaces and ~/something/data under the places' home when they are missing.
    /// Throws a `SpaceError` when one cannot be made: without them no space can be kept.
    static func prepare(_ places: Places) throws {
        for folder in [places.spaces, places.data] {
            do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch {
                throw SpaceError("something cannot make \(folder.path): \(error.localizedDescription) Check that your home folder can be written.")
            }
        }
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
