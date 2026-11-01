// The sidebar's groups and names, in a throwaway home: moving a space to a group writes only the preferences, a new
// group takes the first free name, a name another group has is refused, a folded group keeps its count and its rows
// leave ↑ and ↓, a space being built leads its group for the keys as it is drawn, renaming in place keeps the name on
// Return and none on Esc, a space's new name is only shown (its file and declaration stay), and a row's menu is the
// mockup's; the rows are names only, Needs You mirrors the spaces that wait and a click on one goes to what waits,
// never answering. No window is shown.
import AppKit
import Foundation
import SomethingCore
import SwiftUI
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
        var told: [String] = []
        library.told = { told.append($0) }
        library.preferences.fold("Notes", true)
        run("Notes", in: library.menu(for: try #require(library.entry("brief"))))
        #expect(told == ["Daily brief is in Notes now · groups are only a view, the file stays where it is"])
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
        library.toggle("Breaks")
        library.select(.space("pet"))
        #expect(library.step(1) == .space("oracle"), "from a space its folded group hides, the keys start at its header")
        library.select(.space("pet"))
        #expect(library.step(-1) == .space("logbook"))
        library.select(.templates)
        #expect(library.step(-1) == nil, "on the Templates page the keys are not in the list")
        library.select(.space("agents"))
        #expect(library.step(-1) == .space("brief") && library.step(-1) == .group("Agents") && library.step(-1) == .newSpace)
    }

    @Test func aSpaceBeingBuiltLeadsItsGroupForTheKeysToo() throws {
        let test = Home(prefix: "something-sidebar-")
        defer { test.remove() }
        let library = try library(test)
        library.building = { $0 == "agents" }
        // Drawn first in its group (Sidebar draws the sections), and ↑ ↓ and ⌘1–9 follow the same order.
        #expect(library.sections()[0].entries.map(\.id) == ["agents", "brief"])
        #expect(library.order().map(\.id) == ["agents", "brief", "logbook", "pet", "oracle"])
        #expect(library.stops().prefix(4) == [.newSpace, .group("Agents"), .space("agents"), .space("brief")])
        library.select(.space("agents"))
        #expect(library.step(1) == .space("brief") && library.step(1) == .group("Notes"))
        library.building = { _ in false }
        #expect(library.order().map(\.id) == ["brief", "agents", "logbook", "pet", "oracle"])
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
        // A second rename begun while one is open keeps the first name typed, then takes the keys.
        library.beginRename(.space("brief"))
        library.sidebar.draft = "Front page"
        library.beginRename(.group("Notes"))
        #expect(library.entry("brief")?.title == "Front page")
        #expect(library.sidebar.renaming == .group("Notes") && library.sidebar.draft == "Notes")
    }

    @Test func aRowsMenuIsTheMockups() throws {
        let test = Home(prefix: "something-sidebar-")
        defer { test.remove() }
        let library = try library(test)
        #expect(SidebarMenu.text(library.menu(for: try #require(library.entry("agents")))) == [
            "Open", "Show Info  ⌘I", "Rename…", "Show in Group  ▸", "  Agents  ✓  (dimmed)", "  Notes", "  Breaks", "  —", "  New Group…",
            "  (Groups are only in the sidebar. The file does not move.)", "—", "Show in Finder", "Export", "—", "Move to Trash…  (red)",
        ])
        #expect(SidebarMenu.text(library.menu(forGroup: "Notes")) == ["Rename…", "New Group"])
        var asked: [String] = []
        library.trashing = { asked.append($0.id) }
        run("Move to Trash…", in: library.menu(for: try #require(library.entry("agents"))))
        #expect(asked == ["agents"], "Move to Trash… asks first")
        #expect(Template.symbol(of: "agents-2") == "square.3.layers.3d" && Template.symbol(of: "oracle") == "doc")
        #expect(Library.label(try #require(library.entry("pet")), .sleep) == "Pebble, \(Sign.State.sleep.word)")
    }

    /// A sidebar of `library` 232 by 420 points offscreen, every assistant's eyes `eyes`.
    func side(_ library: Library, _ test: Home, eyes: Sign.State) -> (NSHostingView<SidebarView>, Offscreen) {
        let side = NSHostingView(rootView: SidebarView(library: library, assistant: AssistantModel(engine: test.engine(), places: test.places),
                                                       eyes: { _ in eyes }))
        side.appearance = NSAppearance(named: .aqua)
        let offscreen = Offscreen(side)
        offscreen.window.setContentSize(NSSize(width: 232, height: 420))
        side.frame.size = NSSize(width: 232, height: 420)
        return (side, offscreen)
    }

    /// The dark pixels in the sidebar from `left` points on: past 200, where the rows' eyes were.
    func inked(_ side: NSView, from left: Double = 200) async throws -> Int {
        await wait(0.5)
        side.layoutSubtreeIfNeeded()
        let rep = try #require(side.bitmapImageRepForCachingDisplay(in: side.bounds))
        side.cacheDisplay(in: side.bounds, to: rep)
        var count = 0
        for x in Int(Double(rep.pixelsWide) * left / 232)..<rep.pixelsWide - 8 {
            for y in 0..<rep.pixelsHigh {
                if let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.5, color.brightnessComponent < 0.4 {
                    count += 1
                }
            }
        }
        return count
    }

    /// v6.2's list of names: whatever the assistants do, no row draws eyes at its trailing end, folded or not; the
    /// state stays in each row's VoiceOver label.
    @Test func theRowsAreNamesOnly() async throws {
        let test = Home(prefix: "something-sidebar-")
        defer { test.remove() }
        let library = try library(test)
        let (side, offscreen) = side(library, test, eyes: .wait)
        defer { _ = offscreen }
        #expect(try await inked(side) < 20, "no eyes at the rows' end")
        for group in ["Agents", "Notes", "Breaks"] { library.preferences.fold(group, true) }
        #expect(try await inked(side, from: 120) < 20, "no eyes on a folded group's header")
        #expect(Library.label(try #require(library.entry("agents")), .wait) == "My agents, Waiting for You")
    }

    /// Needs You lists the spaces whose requests wait, in the order the window gave (oldest first), a space the
    /// sidebar no longer lists left out; each stays in its group, so the stops and ⌘1–9 never move.
    @Test func needsYouMirrorsTheWaitingSpaces() throws {
        let test = Home(prefix: "something-sidebar-")
        defer { test.remove() }
        let library = try library(test)
        let order = library.order().map(\.id), stops = library.stops()
        #expect(library.needing().isEmpty)
        library.sidebar.needs = ["oracle", "gone", "agents"]
        #expect(library.needing().map(\.title) == ["Oracle", "My agents"])
        #expect(library.order().map(\.id) == order && library.stops() == stops, "mirrored, never moved")
        #expect(library.preferences.group(of: "agents") == "Agents")
    }

    /// A click on a Needs You row goes to what waits and never answers it: another space opens; the open space's
    /// row shows its request in the panel, the selection kept; no word of the row or its menu is Allow or Deny.
    @Test func needsYouGoesToTheRequestAndNeverAnswers() throws {
        let test = Home(prefix: "something-sidebar-")
        defer { test.remove() }
        let library = try library(test)
        library.sidebar.needs = ["agents", "oracle"]
        library.select(.space("brief"))
        #expect(library.needsGo("agents") == .space("agents"), "another space opens")
        library.select(.space("agents"))
        #expect(library.needsGo("agents") == .request && library.needsGo("oracle") == .space("oracle"))
        #expect(library.selection == .space("agents"), "asking where it goes moves nothing")
        #expect(Keys.command("showreq")?.action == #selector(App.showRequest(_:)), "the panel, which asks")
        for entry in library.needing() {
            let words = SidebarMenu.text(library.menu(for: entry)) + [Library.label(entry, .wait)]
            #expect(!words.contains { $0.contains("Allow") || $0.contains("Deny") }, "\(words)")
        }
    }

    /// The rows' eyes, which VoiceOver says, come from each space's own session: no session reads asleep, never
    /// ready; the unknown is said.
    @Test func eyesComeFromSessions() throws {
        let test = Home(prefix: "something-sidebar-")
        defer { test.remove() }
        let library = try library(test)
        let model = AssistantModel(engine: test.engine(), places: test.places)
        #expect(library.entries.filter(\.isSpace).allSatisfy { model.eyes(of: $0.id) == .sleep }, "no session is asleep, not ready")
        library.preferences.fold("Agents", true)
        #expect(library.label(group: "Agents", count: 2) == "Agents, 2 spaces, folded")
        #expect(library.label(group: "Notes", count: 1) == "Notes, 1 space, open")
        #expect(Library.label(try #require(library.entry("pet")), .unknown) == "Pebble, Can’t Tell", "unknown is said, never idle")
    }

    /// Go lists each space with its assistant's still eyes and state word, the name alone as its title.
    @Test func goShowsEachSpacesEyes() throws {
        let test = Home(prefix: "something-sidebar-")
        defer { test.remove() }
        let library = try library(test)
        let bar = MenuBar(builders: nil)
        bar.spaces = { library.order().filter(\.isSpace).map { ($0.id, $0.title) } }
        bar.eyes = { ["brief": .think, "agents": .wait][$0] ?? .sleep }
        bar.refresh()
        let go = try #require(bar.submenu("Go")).items.filter { $0.identifier?.rawValue.hasPrefix("space:") == true }
        #expect(go.map(\.title) == ["Daily brief", "My agents", "Logbook", "Pebble", "Oracle"])
        #expect(go.map { $0.attributedTitle?.string ?? "" } == ["Daily brief\tWorking", "My agents\tWaiting for You", "Logbook\tAsleep", "Pebble\tAsleep",
                                                                "Oracle\tAsleep"])
        #expect(go.allSatisfy { $0.image?.isTemplate == true }, "still template eyes the menu colours")
        #expect(go.first?.toolTip == "Daily brief · Working", "the state in words, not only drawn")
        #expect(go.prefix(2).map(\.keyEquivalent) == ["1", "2"])
    }
}

extension SidebarMenu {
    /// The menu in words, one line per item, a submenu's indented: what the pictures write beside them.
    static func text(_ lines: [Line], indent: String = "") -> [String] {
        lines.flatMap { line -> [String] in
            switch line {
            case let .item(title, _, key, checked, enabled, destructive, _):
                let marks = [key.map(Keys.shown), checked ? "✓" : nil, enabled ? nil : "(dimmed)", destructive ? "(red)" : nil].compactMap { $0 }
                return [indent + ([title] + marks).joined(separator: "  ")]
            case let .submenu(title, _, lines): return [indent + title + "  ▸"] + text(lines, indent: indent + "  ")
            case .separator: return [indent + "—"]
            case .note(let words): return [indent + "(" + words + ")"]
            }
        }
    }
}
