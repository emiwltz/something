// ⌘P, go: the rows of an empty query (three recent spaces, the others with their group, state and eyes, the open
// one marked; the actions that can act, the templates), the scoring and its sections, what each kind of row opens
// (a space, made the most recent; a command, sent by its id; a template's preview, on the Templates page); and,
// offscreen, the field's keys: typing, ↓ and Return open the second row, Esc and ⌘P close. ⌘P, ask: where the ask
// row sits, the destinations' order, Tab and the segments, one destination, nothing sent before Return, and after it
// the sentence sent with its space's context line, or kept in the field when no agent can take it.
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
        model.query = "qq"
        #expect(model.rows.isEmpty, "two letters nothing answers are not a sentence")
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
        model.chose = { row in row.open(in: library, send: { Issue.record("a space row sent \($0)") }) { _, _ in Issue.record("a space row asked") } }
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
        model.chose = { row in row.open(in: library, send: { sent.append($0) }) { _, _ in Issue.record("an action row asked") } }
        model.pick(try #require(model.rows.firstIndex { $0.id == "action:settings" }))
        #expect(sent == ["settings"] && library.selection == .space("brief"))
    }

    /// A template row opens the Templates page on that template's preview, as the page draws, and the ask is used up.
    @Test(.enabled(if: windowServer, windowServerMissing)) func aTemplateRowOpensItsPreview() async throws {
        let stage = try Stage("palette")
        defer { stage.remove() }
        let library = Self.library(stage), model = Self.model(library)
        model.chose = { row in row.open(in: library, send: { Issue.record("a template row sent \($0)") }) { _, _ in Issue.record("a template row asked") } }
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

    static let sentence = "A small page that tracks my reading list"

    /// A sentence nothing names is the only row, on top and without a header, and goes first to the open space; Tab
    /// goes to New Space, then to the other spaces, most recent first, and round; ⇧Tab back. The footer says where.
    @Test func aSentenceAsksTheOpenSpaceFirstAndTabChangesWhere() throws {
        let stage = try Stage("palette")
        defer { stage.remove() }
        let library = Self.library(stage), model = Self.model(library)
        model.query = "  " + Self.sentence + " "
        let ask = try #require(model.rows.first)
        #expect(model.rows.count == 1 && ask.section == .sentence && ask.section.rawValue.isEmpty)
        #expect(ask.kind == .ask(.space("brief"), text: Self.sentence, none: false) && ask.title == "Ask Daily brief’s assistant")
        #expect(ask.sub == "“\(Self.sentence)”" && model.enter == "Send to Daily brief" && model.sends)
        #expect(model.destinations == [.space("brief"), .newSpace, .space("agents"), .space("pet"), .space("logbook"), .space("project"),
                                       .space("oracle"), .space("stack")], "this space, a new one, then the others, most recent first")
        model.cycle(1)
        #expect(model.rows.first?.title == "Make a New Space" && model.enter == "Build New Space" && model.flips == 1)
        model.cycle(1)
        #expect(model.rows.first?.title == "Ask My agents’ assistant" && model.enter == "Send to My agents")
        model.cycle(-1)
        model.cycle(-1)
        model.cycle(-1)
        #expect(model.goes == .space("stack"), "⇧Tab from the first goes round to the last")
        model.query = "A small page that tracks my books"
        #expect(model.goes == .space("stack"), "new words keep where it goes")
        try #expect(PaletteCard.label(#require(model.rows.first)) == "Ask Stack’s assistant, “A small page that tracks my books”")
    }

    /// The line "Goes to": This Space, New Space, Another naming the first other space until one is chosen; one on.
    /// A click on Another while another space is chosen moves on to the next one, round; a click elsewhere chooses it.
    @Test func theSegmentsSayOneDestination() throws {
        let stage = try Stage("palette")
        defer { stage.remove() }
        let library = Self.library(stage), model = Self.model(library)
        model.query = Self.sentence
        func line() -> [String] { model.segments.map { "\($0.place)\($0.space.map { ":" + $0 } ?? "")\($0.on ? "*" : "")" } }
        #expect(line() == ["here:brief*", "new", "another:agents"])
        model.cycle(1)
        #expect(line() == ["here:brief", "new*", "another:agents"], "the mockup's picture")
        model.choose(2)
        #expect(line() == ["here:brief", "new", "another:agents*"])
        model.choose(2)
        #expect(line() == ["here:brief", "new", "another:pet*"], "Another again: the next other space")
        for _ in 0..<5 { model.choose(model.segments[2].index) }
        #expect(line() == ["here:brief", "new", "another:agents*"], "round")
        model.choose(0)
        #expect(line() == ["here:brief*", "new", "another:agents"] && model.segments.filter(\.on).count == 1)
        #expect(PaletteCard.label(model.segments[2], model) == "Another space, My agents, click again for the next one")
        let flips = model.flips
        model.choose(99)
        #expect(model.flips == flips && model.goes == .space("brief"), "no such segment")
    }

    /// With no space open, a sentence goes first to a new space, and there is no This Space.
    @Test func withNoSpaceOpenASentenceMakesANewSpace() throws {
        let stage = try Stage("palette")
        defer { stage.remove() }
        let library = Self.library(stage)
        library.select(.newSpace)
        let model = Self.model(library, space: false)
        model.query = Self.sentence
        #expect(model.rows.first?.title == "Make a New Space" && model.enter == "Build New Space")
        #expect(model.destinations.first == .newSpace && model.destinations.count == 8 && model.segments.map(\.place) == [.new, .another])
    }

    /// A sentence that also names a space comes last, under Ask, and Return opens the space first; one word that
    /// names something is no sentence; one word nothing answers is, and says so; a row's words never become a sentence
    /// below three letters.
    @Test func whereTheAskRowSits() throws {
        let stage = try Stage("palette")
        defer { stage.remove() }
        let model = Self.model(Self.library(stage))
        model.query = "Daily brief"
        #expect(model.rows.first?.id == "space:brief" && model.rows.last?.section == .ask && model.rows.filter(\.asks).count == 1)
        #expect(model.enter == "Open" && !model.sends)
        model.query = "brief"
        #expect(!model.rows.contains { $0.asks }, "one word that answers is a name")
        model.query = "new space"
        #expect(model.rows.first?.asks == true && model.rows.dropFirst().first?.id == "action:new", "an action named leaves the sentence on top")
        model.query = "zebra"
        #expect(model.rows.map(\.kind) == [.ask(.space("brief"), text: "zebra", none: true)], "one word nothing answers")
        model.query = "zebra crossing"
        #expect(model.rows.map(\.kind) == [.ask(.space("brief"), text: "zebra crossing", none: false)])
        model.query = "ab"
        #expect(model.rows.isEmpty)
        model.query = "go x"
        #expect(model.rows.first?.asks == true)
        try #expect(PaletteCard.height(#require(model.rows.first)) == 88)
        model.query = "zebra"
        try #expect(PaletteCard.height(#require(model.rows.first)) == 116)
    }

    /// Typing, Tab and the segments send nothing; Return gives the sentence and its one destination to `ask`, and
    /// selects nothing itself. It reaches the assistant only where it was going.
    @Test func nothingLeavesBeforeReturn() throws {
        let stage = try Stage("palette")
        defer { stage.remove() }
        let library = Self.library(stage), model = Self.model(library)
        var asked: [(String, Library.Destination)] = [], closed = 0
        model.close = { closed += 1 }
        model.chose = { row in row.open(in: library, send: { Issue.record("an ask row sent \($0)") }) { asked.append(($0, $1)) } }
        model.query = Self.sentence
        model.cycle(1)
        model.choose(2)
        model.choose(1)
        #expect(asked.isEmpty && closed == 0)
        model.pick()
        #expect(asked.count == 1 && asked.first?.0 == Self.sentence && asked.first?.1 == .newSpace && closed == 1)
        #expect(library.selection == .space("brief"))
        #expect(PaletteModel.arrived(at: .newSpace, .blank) && !PaletteModel.arrived(at: .newSpace, .templates))
        let brief = AssistantModel.Place.space(title: "Daily brief", name: "brief", page: "/Users/example/something/spaces/brief/brief.html")
        #expect(PaletteModel.arrived(at: .space("brief"), brief) && !PaletteModel.arrived(at: .space("pet"), brief))
        #expect(!PaletteModel.arrived(at: .space("brief"), .blank))
    }

    /// After Return, at the destination: with no agent chosen the sentence waits in the field, focused, and nothing
    /// is delivered; a destination that did not open says the message was not sent and keeps the field as it was.
    @Test func aSentenceNoAgentCanTakeWaitsInTheField() async throws {
        let (home, model) = try AssistantTests().assistant([], prefix: "something-accept-palette-")
        defer { home.remove() }
        var told: [String] = []
        model.place = .space(title: "My agents", name: "agents", page: home.places.spaces.appendingPathComponent("agents.html").path)
        model.open = false
        #expect(model.kind == nil)
        PaletteModel.deliver(Self.sentence, to: .space("agents"), assistant: model, title: "My agents") { told.append($0) }
        #expect(model.draft == Self.sentence && model.open && told.isEmpty)
        #expect(await wait(until: { model.wantsFocus }), "the field is asked for the focus on the next turn")
        #expect(model.engine.state.agents.isEmpty && model.rows.isEmpty, "nothing delivered")
        model.draft = ""
        PaletteModel.deliver(Self.sentence, to: .space("pet"), assistant: model, title: "Pebble") { told.append($0) }
        PaletteModel.deliver(Self.sentence, to: .newSpace, assistant: model, title: nil) { told.append($0) }
        #expect(told == ["The message was not sent: Pebble did not open", "The message was not sent: New Space did not open"])
        #expect(model.draft.isEmpty)
    }

    /// After Return, at a space whose agent is chosen: the card opens and the message leaves with the context line
    /// that names that space.
    @Test func aSentenceGoesWithItsSpacesContextLine() async throws {
        let assistants = AssistantTests()
        let (home, model) = try assistants.assistant(prefix: "something-accept-palette-")
        defer { home.remove() }
        await assistants.look(model)
        model.place = .space(title: "My agents", name: "agents", page: home.places.spaces.appendingPathComponent("agents.html").path)
        model.open = false
        PaletteModel.deliver("Make the tiles wider.", to: .space("agents"), assistant: model, title: "My agents") { Issue.record("told \($0)") }
        #expect(model.open && model.draft.isEmpty)
        #expect(await wait(until: { model.rows.contains(.reply("Invented reply.")) }))
        #expect(assistants.input(home).contains { $0.contains(#"[something] Open space: “My agents” (agents, ~/something/spaces/agents.html).\nMake the tiles wider."#) })
        await assistants.finish(home, model)
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
        // Tab and ⇧Tab change where a sentence goes and keep the keys in the field.
        (palette, editor) = try show()
        editor.insertText(Self.sentence, replacementRange: editor.selectedRange())
        editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
        #expect(palette.model.goes == .newSpace && window.firstResponder === editor)
        editor.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        #expect(palette.model.goes == .space("brief") && window.firstResponder === editor && chosen.count == 1)
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(chosen == [second.id, "ask:brief"])
    }
}
