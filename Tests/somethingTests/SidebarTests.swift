// The sidebar's groups and names, in a throwaway home: moving a space to a group writes only the preferences, a new
// group takes the first free name, a name another group has is refused, a folded group keeps its count and its rows
// leave ↑ and ↓, renaming in place keeps the name on Return and none on Esc, a space's new name is only shown (its
// file and declaration stay), and a row's menu is the mockup's. No window is shown.
import AppKit
import Foundation
import SomethingCore
import Testing
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-sidebar-")) struct SidebarTests {
    init() { NSApplication.shared.setActivationPolicy(.prohibited) }

    /// A home with five spaces in the mockup's three groups (Oracle in none), its library listed.
    func library(_ test: Home) throws -> Library {
        for (name, title) in [("brief", "Daily brief"), ("agents", "My agents"), ("logbook", "Logbook"), ("pet", "Pebble"), ("oracle", "Oracle")] {
            try test.space(name, page(#"{"contract": 1, "title": "\#(title)"}"#, ""))
        }
        let library = Library(places: test.places, ask: FakeAsk(), share: Home.share)
        library.preferences.groups = [.init(name: "Agents", spaces: ["brief", "agents"]), .init(name: "Notes", spaces: ["logbook"]),
                                      .init(name: "Breaks", spaces: ["pet"])]
        library.relist()
        return library
    }

    /// The item of `lines` with that title, found in submenus too; its action runs with `run`.
    func run(_ title: String, in lines: [SidebarMenu.Line]) {
        for line in lines {
            switch line {
            case let .item(name, _, _, _, enabled, _, action) where name == title:
                #expect(enabled, "\(title) is dimmed")
                return action()
            case let .submenu(_, _, inner): run(title, in: inner)
            default: continue
            }
        }
    }

    func files(_ test: Home) throws -> [String: Date] {
        Library.stamp(test.places.spaces).merging(
            try FileManager.default.contentsOfDirectory(atPath: test.places.spaces.path).map { ($0, Date.distantPast) }) { stamp, _ in stamp }
    }

    @Test func movingToAGroupWritesOnlyThePreferences() throws {
        let test = Home(prefix: "something-sidebar-")
        defer { test.remove() }
        let library = try library(test)
        let before = try files(test)
        library.preferences.fold("Notes", true)
        run("Notes", in: library.menu(for: try #require(library.entry("brief"))))
        #expect(library.preferences.groups.map(\.spaces) == [["agents"], ["logbook", "brief"], ["pet"]])
        #expect(!library.folded("Notes"), "the group it went to opens, so the space shows")
        #expect(try files(test) == before, "no file moved or changed")
        #expect(Preferences(test.places).groups == library.preferences.groups, "written to window.json at once")
        #expect(library.sections().map { $0.group } == ["Agents", "Notes", "Breaks", nil])
        #expect(library.sections().map { $0.entries.map(\.id) } == [["agents"], ["brief", "logbook"], ["pet"], ["oracle"]])
        #expect(library.order().map(\.id) == ["agents", "brief", "logbook", "pet", "oracle"], "the one order follows")
    }

    @Test func aNewGroupTakesTheFirstFreeNameAndADuplicateIsRefused() throws {
        let test = Home(prefix: "something-sidebar-")
        defer { test.remove() }
        let library = try library(test)
        library.addGroup()
        #expect(library.sidebar.renaming == .group("New Group") && library.sidebar.draft == "New Group")
        library.commitRename()
        library.addGroup(moving: "oracle")
        #expect(library.sidebar.renaming == .group("New Group 2") && library.preferences.group(of: "oracle") == "New Group 2")
        library.sidebar.draft = "  Ideas "
        library.commitRename()
        #expect(library.preferences.groups.map(\.name) == ["Agents", "Notes", "Breaks", "New Group", "Ideas"])
        #expect(library.preferences.newGroup() == "New Group 2", "a name freed is free again")
        #expect(!library.preferences.renameGroup("Ideas", to: "Notes") && !library.preferences.renameGroup("Ideas", to: "  "))
        #expect(!library.preferences.renameGroup("Nowhere", to: "Somewhere"))
        library.beginRename(.group("Ideas"))
        library.sidebar.draft = "Agents"
        library.commitRename()
        #expect(library.preferences.group(of: "oracle") == "Ideas" && library.sidebar.renaming == nil, "refused: it keeps its name")
        library.preferences.fold("Ideas", true)
        #expect(library.preferences.renameGroup("Ideas", to: "Later") && library.folded("Later"), "the folding follows the name")
    }

    @Test func aFoldedGroupKeepsItsCountAndLeavesTheKeys() async throws {
        let test = Home(prefix: "something-sidebar-")
        defer { test.remove() }
        let library = try library(test)
        library.toggle("Breaks")
        #expect(library.folded("Breaks") && library.sections()[2].entries.map(\.id) == ["pet"], "folded, it still counts its space")
        #expect(library.label(group: "Breaks", count: 1) == "Breaks, 1 space, folded")
        #expect(library.stops() == [.newSpace, .group("Agents"), .space("brief"), .space("agents"), .group("Notes"), .space("logbook"),
                                    .group("Breaks"), .space("oracle")])
        // ↓ from New Space: the header holds the keys, then a row opens.
        #expect(library.selection == .newSpace)
        #expect(library.step(1) == .group("Agents") && library.sidebar.cursor == "Agents" && library.selection == .newSpace)
        #expect(library.step(1) == .space("brief") && library.sidebar.cursor == nil && library.selection == .space("brief"))
        for _ in 0..<4 { library.step(1) }
        #expect(library.sidebar.cursor == "Breaks")
        // Return unfolds the header the keys rest on; its row is a stop again.
        #expect(library.enter() && !library.folded("Breaks"))
        #expect(library.step(1) == .space("pet") && library.selection == .space("pet"))
        #expect(!library.enter(), "Return on a row is the system's")
        #expect(library.step(1) == .space("oracle") && library.step(1) == .space("oracle"), "the last stop holds")
        library.select(.templates)
        #expect(library.step(-1) == nil, "on the Templates page the keys are not in the list")
        library.select(.space("agents"))
        #expect(library.step(-1) == .space("brief") && library.step(-1) == .group("Agents") && library.step(-1) == .newSpace)
    }

    @Test func renamingInPlaceKeepsTheNameAndEscCancels() throws {
        let test = Home(prefix: "something-sidebar-")
        defer { test.remove() }
        let library = try library(test)
        library.preferences.fold("Agents", true)
        run("Rename…", in: library.menu(for: try #require(library.entry("brief"))))
        #expect(library.sidebar.renaming == .space("brief") && library.sidebar.draft == "Daily brief" && !library.folded("Agents"))
        library.sidebar.draft = "Morning paper"
        library.cancelRename()
        #expect(library.entry("brief")?.title == "Daily brief" && library.preferences.names.isEmpty, "Esc changes nothing")
        library.beginRename(.space("brief"))
        library.sidebar.draft = "Morning paper "
        library.commitRename()
        let entry = try #require(library.entry("brief"))
        #expect(entry.title == "Morning paper" && entry.declared == "Daily brief" && entry.space.name == "brief")
        #expect(Preferences(test.places).names == ["brief": "Morning paper"], "a display name, in the preferences")
        #expect(FileManager.default.fileExists(atPath: test.places.spaces.appendingPathComponent("brief.html").path), "the file keeps its name")
        #expect(library.sections()[0].entries.map(\.title) == ["Morning paper", "My agents"], "sorted by the name shown")
        library.rename("brief", to: "Daily brief")
        #expect(library.preferences.names.isEmpty, "its own title again forgets the name")
        library.beginRename(.group("Notes"))
        library.sidebar.draft = "Journal"
        library.cancelRename()
        #expect(library.preferences.groups[1].name == "Notes")
    }

    @Test func aRowsMenuIsTheMockups() throws {
        let test = Home(prefix: "something-sidebar-")
        defer { test.remove() }
        let library = try library(test)
        #expect(SidebarMenu.text(library.menu(for: try #require(library.entry("agents")))) == [
            "Open", "Show Info  ⌘I", "Rename…", "Show in Group  ▸", "  Agents  ✓  (dimmed)", "  Notes", "  Breaks", "  —", "  New Group…",
            "  (Groups are only in the sidebar. The file does not move.)", "—", "Show in Finder", "Export…", "—", "Move to Trash…  (red)",
        ])
        #expect(SidebarMenu.text(library.menu(forGroup: "Notes")) == ["Rename…", "New Group"])
        var asked: [String] = []
        library.trashing = { asked.append($0.id) }
        run("Move to Trash…", in: library.menu(for: try #require(library.entry("agents"))))
        #expect(asked == ["agents"], "Move to Trash… asks first")
        #expect(Library.symbol("agents-2") == "square.3.layers.3d" && Library.symbol("oracle") == "doc")
        #expect(Library.label(try #require(library.entry("pet")), .sleep) == "Pebble, \(Sign.State.sleep.word)")
    }
}
