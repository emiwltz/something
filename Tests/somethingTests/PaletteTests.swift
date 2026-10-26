// ⌘P, go: the rows of an empty query (three recent spaces, the others with their group, state and eyes, the open
// one marked; the actions that can act, the templates), the scoring and its sections, what each kind of row opens
// (a space, made the most recent; a command, sent by its id; a template's preview, on the Templates page); and,
// offscreen, the field's keys: typing, ↓ and Return open the second row, Esc and ⌘P close.
import AppKit
import SwiftUI
import Testing
@testable import something

@MainActor @Suite(.serialized, .leavesNothing("something-accept-palette-")) struct PaletteTests {
    /// The Stage's spaces in the mockup's groups, Daily brief open, and the mockup's recent ones (CM_RECENT).
    static func library(_ stage: Stage) -> Library {
        let library = Library(places: stage.home.places, ask: FakeAsk(), share: Home.share)
        library.preferences.groups = Stage.groups.map { Preferences.Group(name: $0.0, spaces: $0.1) }
        library.relist()
        library.select(.space("brief"))
        library.preferences.change { $0.recents = ["brief", "agents", "pet", "logbook", "project", "oracle", "stack"] }
        return library
    }

    static func model(_ library: Library, space: Bool = true) -> PaletteModel {
        PaletteModel(library: library, eyes: { Stage.moment[$0] ?? .unknown }, enabled: { Keys.enabled($0, Keys.Situation(space: space)) })
    }

    @Test func anEmptyQueryListsRecentsThenSpacesThenActionsThenTemplates() throws {
        let stage = try Stage("palette")
        defer { stage.remove() }
        let library = Self.library(stage), rows = Self.model(library).rows
        func titles(_ section: PaletteModel.Row.Section) -> [String] { rows.filter { $0.section == section }.map(\.title) }
        #expect(titles(.recent) == ["My agents", "Pebble", "Logbook"], "three, the open space left out")
        #expect(titles(.spaces) == ["Daily brief", "Project watch", "Oracle", "Stack"], "the others, in the sidebar's order")
        #expect(titles(.actions) == ["New Space", "Talk to Daily brief’s Assistant", "Show Conversation", "Templates", "Enter Full Screen",
                                     "Put Idle Assistants to Sleep", "Settings", "Keyboard Shortcuts", "Look for Agents Again"])
        #expect(titles(.templates) == library.templates.map(\.title) && titles(.templates).count == 6)
        #expect(rows.map(\.section) == rows.map(\.section).sorted { order($0) < order($1) }, "the sections in their order")
        let brief = try #require(rows.first { $0.id == "space:brief" }), agents = try #require(rows.first)
        #expect(brief.kind == .space(.think, open: true) && brief.sub == "Agents")
        #expect(agents.kind == .space(.wait, open: false) && agents.sub == "Agents" && agents.target == "agents")
        #expect(rows.filter { if case .space(_, true) = $0.kind { true } else { false } }.count == 1, "only the open space is marked")
        #expect(rows.first { $0.id == "action:new" }?.kind == .action(key: "⌘N") && rows.first { $0.id == "action:sleep" }?.kind == .action(key: ""))
        #expect(PaletteCard.label(agents) == "My agents, Agents, Waiting for you" && PaletteCard.label(brief) == "Daily brief, Agents, open, Working")
    }

    func order(_ section: PaletteModel.Row.Section) -> Int { [.recent, .spaces, .actions, .templates].firstIndex(of: section) ?? 0 }

    @Test func actionsThatCannotActAreLeftOut() throws {
        let stage = try Stage("palette")
        defer { stage.remove() }
        let rows = Self.model(Self.library(stage), space: false).rows.filter { $0.section == .actions }.map(\.target)
        #expect(rows == ["new", "tpls", "full", "sleep", "settings", "keys", "lookAgain"], "the assistant's actions need a space")
        let nothing = PaletteModel(library: Self.library(stage), eyes: { _ in .unknown }, enabled: { _ in false }).rows
        #expect(!nothing.contains { $0.section == .actions })
    }

    @Test func typedWordsKeepWhatStartsThenWhatHasAWordThatStartsThenWhatContains() throws {
        let stage = try Stage("palette")
        defer { stage.remove() }
        let library = Self.library(stage), model = Self.model(library)
        func row(_ title: String, _ sub: String? = nil) -> PaletteModel.Row {
            PaletteModel.Row(id: "space:x", section: .spaces, title: title, sub: sub, symbol: "doc", kind: .template)
        }
        #expect(PaletteModel.score(row("Daily brief"), "dai") == 0 && PaletteModel.score(row("Daily brief"), "bri") == 1)
        #expect(PaletteModel.score(row("Daily brief"), "ly b") == 2 && PaletteModel.score(row("Daily brief", "Agents"), "gent") == 2)
        #expect(PaletteModel.score(row("Daily brief"), "zz") == nil)
        model.query = "  WATCH "
        #expect(model.rows.map(\.id) == ["space:project", "template:project"], "case and spaces around do not count; no recent section")
        model.query = "s"
        let rows = model.rows
        #expect(rows.first?.id == "space:stack", "a name that starts with it first in its section")
        #expect(!rows.contains { $0.section == .recent } && rows.allSatisfy { PaletteModel.score($0, "s") != nil })
        let ranks = rows.map { (order($0.section), PaletteModel.score($0, "s") ?? 9) }
        #expect(zip(ranks, ranks.dropFirst()).allSatisfy { $0 <= $1 }, "by section, then by score")
        model.selected = 3
        let keyings = model.keyings
        model.query = "st"
        #expect(model.selected == 0, "new words put the keys back on the first row")
        #expect(model.keyed == model.rows.first?.id && model.keyings == keyings + 1, "and scroll back to it")
        model.move(1)
        model.move(-1)
        #expect(model.keyed == model.rows.first?.id && model.keyings == keyings + 3, "the keys landing again scroll again")
        model.query = "qqq"
        #expect(model.rows.isEmpty)
        model.move(1)
        model.pick()
        #expect(model.selected == 0, "nothing to move to or open")
    }

    @Test func openingASpaceFromThePaletteMakesItTheMostRecent() async throws {
        let stage = try Stage("palette")
        defer { stage.remove() }
        let library = Self.library(stage), model = Self.model(library)
        var closed = 0
        model.close = { closed += 1 }
        model.chose = { row in row.open(in: library) { Issue.record("a space row sent \($0)") } }
        model.move(1)
        model.move(-2)
        #expect(model.selected == model.rows.count - 1 && model.keyed == model.rows.last?.id, "↑ from the first goes round to the last")
        let pebble = try #require(model.rows.firstIndex { $0.id == "space:pet" })
        model.pick(pebble)
        #expect(closed == 1 && library.selection == .space("pet"))
        #expect(library.preferences.recents.prefix(3) == ["pet", "brief", "agents"])
        #expect(model.rows.filter { $0.section == .recent }.map(\.title) == ["Daily brief", "My agents", "Logbook"])
    }

    /// An action row sends its command's id, as the menu item would, and selects nothing.
    @Test func anActionRowSendsItsCommand() throws {
        let stage = try Stage("palette")
        defer { stage.remove() }
        let library = Self.library(stage), model = Self.model(library)
        var sent: [String] = []
        model.chose = { row in row.open(in: library) { sent.append($0) } }
        model.pick(try #require(model.rows.firstIndex { $0.id == "action:settings" }))
        #expect(sent == ["settings"] && library.selection == .space("brief"))
    }

    /// A template row opens the Templates page on that template's preview, as the page draws, and the ask is used up.
    @Test(.enabled(if: windowServer, windowServerMissing)) func aTemplateRowOpensItsPreview() async throws {
        let stage = try Stage("palette")
        defer { stage.remove() }
        let library = Self.library(stage), model = Self.model(library)
        model.chose = { row in row.open(in: library) { Issue.record("a template row sent \($0)") } }
        model.pick(try #require(model.rows.firstIndex { $0.id == "template:pet" }))
        #expect(library.selection == .templates && library.asked == "pet")
        let gallery = Gallery(), host = NSHostingView(rootView: GalleryView(library: library, model: gallery))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 964, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        (window.contentView, window.isReleasedWhenClosed) = (host, false)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        #expect(await wait { gallery.previewing?.id == "pet" })
        #expect(library.asked == nil)
    }

    /// The pointer selects the row it moves onto; a row scrolled under a pointer that did not move takes nothing.
    @Test func onlyAMovingPointerSelects() throws {
        let stage = try Stage("palette")
        defer { stage.remove() }
        let model = Self.model(Self.library(stage))
        model.hover(2, at: CGPoint(x: 300, y: 200))
        #expect(model.selected == 2)
        model.move(1)
        model.hover(4, at: CGPoint(x: 300, y: 200))
        #expect(model.selected == 3, "the keys keep it")
        model.hover(4, at: CGPoint(x: 301, y: 200))
        #expect(model.selected == 4)
    }

    /// In a window, the field has the keys: typed words narrow the list, ↓ moves to the second row and Return opens
    /// it, the palette closed and the keys given back to the page; Esc and ⌘P again close it; it closes the sheet of
    /// shortcuts, one card at a time.
    @Test(.enabled(if: windowServer, windowServerMissing)) func typingDownAndReturnOpenTheSecondRow() throws {
        final class Page: NSView { override var acceptsFirstResponder: Bool { true } }
        let stage = try Stage("palette")
        defer { stage.remove() }
        let library = Self.library(stage)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let content = try #require(window.contentView), page = Page(frame: content.bounds)
        content.addSubview(page)
        let layer = WindowLayer(over: content)
        #expect(window.makeFirstResponder(page))
        var chosen: [String] = []
        func show() throws -> (Palette, NSTextView) {
            let model = Self.model(library)
            model.chose = { chosen.append($0.id) }
            let palette = try #require(Palette.toggle(in: layer, model: model, motion: .reduced))
            let editor = try #require(window.firstResponder as? NSTextView)
            #expect(editor.delegate === palette.field && palette.frame == layer.bounds, "the field has the keys")
            return (palette, editor)
        }
        _ = try #require(KeysSheet.toggle(in: layer, motion: .reduced))
        var (palette, editor) = try show()
        #expect(KeysSheet.shown(in: layer) == nil && layer.subviews == [palette], "one card at a time")
        #expect(palette.card.frame.width == 640 && abs(palette.card.frame.midX - 600) < 1 && abs(palette.card.frame.maxY - (760 - 84)) < 1)
        editor.insertText("o", replacementRange: editor.selectedRange())
        #expect(palette.model.query == "o")
        let second = try #require(palette.model.rows.dropFirst().first)
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        #expect(palette.model.selected == 1)
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(chosen == [second.id] && Palette.shown(in: layer) == nil && layer.isHidden)
        #expect(window.firstResponder === page, "the keys back to the page")
        (palette, editor) = try show()
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        #expect(Palette.shown(in: layer) == nil && window.firstResponder === page, "Esc closes it")
        _ = try show()
        #expect(Palette.toggle(in: layer, model: Self.model(library)) == nil && Palette.shown(in: layer) == nil, "⌘P again closes it")
        #expect(chosen.count == 1, "nothing opens but by Return or a click")
    }
}
