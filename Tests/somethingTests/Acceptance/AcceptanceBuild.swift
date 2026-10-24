// Acceptance scenarios of the first start and making a space: the welcome and the film (a1–a8), New Space, the build
// ladder, the arrival, templates and the rights sheet (d1–d8).
// Each scenario renders offscreen from the Stage, asserts structure, words, enabled state, counts and accessibility
// labels, and writes <id>.png and <id>-dark.png when SOMETHING_GALLERY is set. An unbuilt one stays disabled until
// its slice lands (AcceptanceTests reads these traits).
import AppKit
import SwiftUI
import Testing
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-build-"))
struct AcceptanceBuild {
    @Test("a1: the film on the glass", .disabled("not built yet: AB18")) func a1() async throws {}
    @Test("a2: welcome, step 1", .disabled("not built yet: AB17")) func a2() async throws {}
    @Test("a3: welcome, the builders", .disabled("not built yet: AB17")) func a3() async throws {}
    @Test("a4: welcome, launcher and notices", .disabled("not built yet: AB17")) func a4() async throws {}
    @Test("a5: welcome, the sticker and its keys", .disabled("not built yet: AB17")) func a5() async throws {}
    @Test("a6: welcome, the summary", .disabled("not built yet: AB17")) func a6() async throws {}
    @Test("a7: welcome with no builder", .disabled("not built yet: AB17")) func a7() async throws {}
    @Test("a8: welcome after the first hello", .disabled("not built yet: AB17")) func a8() async throws {}
    /// New Space with Claude Code as its builder: the sign, the question, the field with Build greyed until something
    /// is written, Built by and the model, the three suggestions, the first three templates and See All; the assistant
    /// away. d1-smallest in the smallest window; d1-no-agent: the notice in the field's place, no suggestion.
    @Test("d1: New Space") func d1() async throws {
        let stage = try Stage("build")
        defer { stage.remove() }
        let (shell, library, host) = try await Self.newSpace(stage, builder: true)
        let model = shell.assistant
        #expect(shell.window.title == "New Space" && shell.window.subtitle == "" && shell.glass.isHidden && !model.cardShown)
        #expect(model.kind == "claude" && model.draft.isEmpty && !model.canSend)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d1" + suffix, root: stage.home.root)
            let words = await Self.read(host)
            #expect(words == Self.newSpaceWords + ["My agents", "Project watch", "Daily brief"], "\(words)")
        }
        // Build is greyed while the field is empty or blank, and only then. (An offscreen SwiftUI view gives VoiceOver only
        // its descriptions: neither a control's enabled state nor its press can be reached here, so the model's are read.)
        model.draft = "  \n "
        #expect(!model.canSend)
        model.draft = "A page of my agents."
        #expect(model.canSend)
        model.draft = ""

        shell.window.setContentSize(NSSize(width: 640, height: 480))
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d1-smallest" + suffix, root: stage.home.root)
        }
        // A turn that ends without a new space (the fake answers in words): its reply stays on the page above the field,
        // to be answered there, since the assistant's card stays away. (A plain text is out of reach offscreen: the
        // page's own choice is read, and d1-answer shows it.)
        shell.window.setContentSize(Stage.Size.main)
        model.send("A page for my mornings.")
        #expect(await wait(until: { !model.building && model.rows.last == .reply("Invented reply.") }))
        #expect(BlankView.reply(in: model) == "Invented reply." && model.draft.isEmpty && !model.blocked)
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d1-answer" + suffix, root: stage.home.root)
            let answered = await Self.read(host)
            #expect(shell.glass.isHidden && answered.contains("Who is waiting for me"), "\(answered)")
        }
        // A suggestion sends its whole sentence, the draft kept: the build starts (the fake keeps working on the game),
        // the field holds the sentence read only, the suggestions and templates step aside, the assistant stays away.
        model.draft = "Half written"
        BlankView.suggest(BlankView.chips[2], to: model)
        #expect(model.building && model.draft == "Half written")
        #expect(await wait(until: { model.rows.contains(.mine(caption: "on the blank page", text: BlankView.chips[2].1)) && model.light == .working }))
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d1-building" + suffix, root: stage.home.root)
            let building = await Self.read(host)
            #expect(shell.glass.isHidden && !building.contains("Build") && !building.contains("Who is waiting for me"), "\(building)")
        }
        var stopped = false
        model.engine.stopAll(within: 6) { stopped = true }
        _ = await wait(until: { stopped })

        let none = try Stage("build")
        defer { none.remove() }
        let (bare, alone, page) = try await Self.newSpace(none, builder: false)
        #expect(bare.assistant.noAgent && bare.assistant.notice?.title == "No coding agent found.")
        try await none.appearances { suffix in
            try await Picture.window(bare, library: alone, web: nil, "d1-no-agent" + suffix, root: none.home.root)
            let words = await Self.read(page)
            #expect(!words.contains("Build") && !words.contains("Who is waiting for me") && words.contains("How to Get One"), "\(words)")
        }
    }

    /// What VoiceOver reads of New Space before the templates' cards, as far as an offscreen SwiftUI view gives it (its
    /// field, menus and the sign are out of reach here).
    static let newSpaceWords = ["What do you want to make?", "Build", "Who is waiting for me", "A morning brief of my agents", "A small game for my breaks", "Or start from a template",
                                "See All Templates"]

    /// New Space in a window of `stage`, the toolbar's chip at the mockup's one request; with `builder`, AssistantTests'
    /// fake claude is the builder found, else none is.
    static func newSpace(_ stage: Stage, builder: Bool) async throws -> (Shell, Library, NSView) {
        let bin = stage.home.root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        if builder {
            let claude = bin.appendingPathComponent("claude")
            try AssistantTests.fake.write(to: claude, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
        }
        let (shell, library, _) = stage.window()
        let model = shell.assistant
        model.engine.changed = { model.refresh() }
        model.engine.lookAgain()
        #expect(await wait(until: { builder ? model.kind == "claude" : model.noAgent }))
        library.select(.newSpace)
        shell.show(nil)
        shell.waiting(1, mine: 0)
        let host = try #require(shell.center.subviews.first { $0 is NSHostingView<BlankView> })
        return (shell, library, host)
    }

    @Test("d2: the build ladder", .disabled("not built yet: AB14")) func d2() async throws {}
    @Test("d3: the arrival", .disabled("not built yet: AB15")) func d3() async throws {}
    /// The rights sheet over the space just made: "Waiting room would like to", where its page is, one row per right
    /// with its switch off, the fine print, Don't Allow holding the focus and Allow greyed until a switch is on.
    @Test("d4: the rights sheet") func d4() async throws {
        let stage = try Stage("build")
        defer { stage.remove() }
        let space = try stage.home.space("waiting-room", Self.waitingRoom)
        let (shell, library, _) = stage.window()
        let room = try await stage.open("waiting-room", in: shell, library)
        defer { room.close() }
        shell.waiting(1, mine: 0)
        let question = RightsQuestion(space: "Waiting room", description: nil, rights: ["state", "store"], scope: nil, missing: [],
                                      folder: nil, made: true, page: space.location.path, declared: ["state", "store"])
        let sheet = Ask.rights(question, home: stage.home.root.path).sheet
        #expect(sheet.title == "Waiting room would like to" && sheet.frame.width == 440 && !sheet.isAlert)
        #expect(PanelsTests.texts(sheet.contentView) == [
            "Waiting room would like to", "~/something/spaces/waiting-room.html · made just now",
            "See your agents", "Which agents run on this Mac, what each one is doing, and its last messages. It only reads.",
            "Remember things", "Keep a small memory in its own folder, so it knows what you saw last time.",
            "It does not ask to write to your agents or start agents. Each right starts off; change it later in its Info."])
        let switches = SpaceViewTests.switches(sheet.contentView)
        #expect(switches.map(\.state) == [.off, .off] && switches.map { $0.accessibilityLabel() } == ["See your agents", "Remember things"])
        #expect(sheet.buttons.map(\.title) == ["Don't Allow", "Allow"] && sheet.buttons.map(\.hint) == ["esc", nil])
        #expect(sheet.firstResponder === sheet.buttons[0] && sheet.buttons[0].keyEquivalent == "\u{1b}" && !sheet.buttons[1].isEnabled)
        #expect(sheet.accessibilitySubrole() == .dialog)
        // Under the toolbar, centred over the space beside the sidebar.
        let hang = shell.window(shell.window, willPositionSheet: sheet, using: .zero)
        #expect(hang.minY == shell.window.contentLayoutRect.maxY && hang.minX == shell.split.splitViewItems[0].viewController.view.frame.width)
        try await stage.appearances { suffix in
            try await Picture.sheet(sheet, over: shell, library: library, web: room.web, "d4" + suffix, root: stage.home.root)
        }
        switches[1].performClick(nil)
        #expect(sheet.buttons[1].isEnabled)
    }

    /// The space the assistant just made in the mockup, its words invented: one agent waiting in its terminal.
    static let waitingRoom = """
        <!doctype html><html><head><meta charset="utf-8"><title>Waiting room</title>
        <script type="application/json" id="something">{"contract": 1, "title": "Waiting room", "rights": ["state", "store"]}</script><style>
        body{margin:0;padding:34px 46px;background:#F4F4F1;color:#121316;font:13.5px -apple-system,sans-serif}
        @media (prefers-color-scheme:dark){body{background:#15171C;color:#F1F1EE}.w{background:#1F2126!important}}
        h2{font:600 34px/1.05 Georgia,serif;letter-spacing:-.025em;margin:0}
        .lead{color:#5C5E66;margin:8px 0 22px}
        .w{display:grid;grid-template-columns:auto 1fr auto;gap:16px;align-items:center;background:#fff;border-radius:10px;
           box-shadow:0 0 0 1px rgba(18,19,22,.1);padding:14px 16px}
        .age{font:600 22px/1 -apple-system;width:64px}.age small{display:block;font-size:11px;font-weight:500;color:#8A8C92;margin-top:3px}
        b{display:block;font-size:13px}span{color:#5C5E66;font-size:12.5px}
        button{font:500 12.5px -apple-system;padding:6px 11px;border-radius:7px;border:1px solid rgba(18,19,22,.17);background:#fff}
        .none{color:#8A8C92;font-size:12.5px;margin:12px 2px}
        </style></head><body><h2>Waiting room</h2><p class="lead">Agents that wait for you in their own terminal, oldest first.</p>
        <div class="w"><div class="age">34<small>minutes</small></div><div><b>Amp · ~/code/shop</b><span>Asks to run the tests before touching the cart page.</span></div><button>Open Terminal</button></div>
        <p class="none">Nobody else waits. Two Claude Code sessions are working, and pi is idle.</p></body></html>
        """
    /// The Templates page in the window, the toolbar's chip at the mockup's one request, the assistant's glass hidden (the
    /// mockup shows the page alone); and the page's model.
    static func templates(_ stage: Stage) throws -> (Shell, Library, Gallery, NSView) {
        let (shell, library, _) = stage.window()
        library.select(.templates)
        shell.show(nil, templates: true)
        shell.glass.isHidden = true
        shell.waiting(1, mine: 0)
        let host = try #require(shell.center.subviews.first { $0 is NSHostingView<GalleryView> } as? NSHostingView<GalleryView>)
        return (shell, library, host.rootView.model, host)
    }


    /// The labels VoiceOver reads in `view`, depth first. A SwiftUI view offscreen gives only the description of its
    /// outer elements (AXAttributedDescription): what is inside a card or a bar is out of reach here.
    static func read(_ view: NSView) async -> [String] {
        let enhanced = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
        // As an assistive app asks: SwiftUI makes its elements only then.
        NSApp.accessibilitySetValue(true, forAttribute: enhanced)
        defer { NSApp.accessibilitySetValue(false, forAttribute: enhanced) }
        // The first question makes them, on the run loop.
        _ = view.accessibilityChildren()
        await wait(0.3)
        return labels(view)
    }

    private static func labels(_ element: Any) -> [String] {
        let object = element as AnyObject
        let described = object.accessibilityAttributeValue(NSAccessibility.Attribute(rawValue: "AXAttributedDescription")) as? NSAttributedString
        let words = [NSAccessibility.Attribute.description, .title, .value].compactMap { object.accessibilityAttributeValue($0) as? String }
            + [described?.string].compactMap { $0 }
        let children = (object as? NSAccessibilityProtocol)?.accessibilityChildren() ?? []
        return words.filter { !$0.isEmpty } + children.flatMap(labels)
    }

    /// Six cards in three columns, the first under the pointer with Preview, Show in Finder and Use; Agents keeps two.
    /// d5-narrow: two columns in the narrow window.
    @Test("d5: templates") func d5() async throws {
        let stage = try Stage("build")
        defer { stage.remove() }
        let (shell, library, gallery, host) = try Self.templates(stage)
        #expect(shell.window.title == "Templates" && shell.window.subtitle == "Start from one, then make it yours")
        #expect(gallery.cards(library.templates).map(\.title) == ["My agents", "Project watch", "Daily brief", "Logbook", "Stack", "Pebble"])
        #expect(library.templates.map(\.needs) == ["Sees and writes to your agents", "Sees, writes to and starts agents · Remembers",
                                                   "Sees your agents · Remembers", "Sees your agents · Remembers", "Remembers",
                                                   "Sees your agents · Remembers"])
        gallery.hovered = "agents"
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d5" + suffix, root: stage.home.root)
            // VoiceOver reads the heading, the filters and one element per card, named by its template.
            #expect(await Self.read(host) == ["Templates", "Show", "My agents", "Project watch", "Daily brief", "Logbook", "Stack", "Pebble"])
        }
        gallery.shown = .agents
        #expect(gallery.cards(library.templates).map(\.id) == ["agents", "project"])
        gallery.shown = .all
        // The cards as drawn: their left edges make three columns, then two in the narrow window.
        let columns = { Set(gallery.drawn.values.map { $0.minX.rounded() }).count }
        #expect(gallery.drawn.count == 6 && columns() == 3, "\(gallery.drawn)")
        // Forgotten first, so that only cards drawn at the new size count.
        gallery.drawn = [:]
        shell.window.setContentSize(NSSize(width: 760, height: 680))
        await wait(0.3)
        #expect(gallery.drawn.count == 6 && columns() == 2, "\(gallery.drawn)")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d5-narrow" + suffix, root: stage.home.root)
        }
    }

    /// My agents' preview: its picture under the bar, the toolbar naming it; Escape goes back to the cards
    /// (TemplatesTests uses one from its preview).
    @Test("d6: a template's preview") func d6() async throws {
        let stage = try Stage("build")
        defer { stage.remove() }
        let (shell, library, gallery, host) = try Self.templates(stage)
        let agents = try #require(library.templates.first { $0.id == "agents" })
        gallery.preview(agents)
        #expect(shell.window.title == "My agents" && shell.window.subtitle == "Template preview")
        try await stage.appearances { suffix in
            try await Picture.window(shell, library: library, web: nil, "d6" + suffix, root: stage.home.root)
            // The bar, then the picture; the cards are gone.
            #expect(await Self.read(host) == ["Template preview", "A picture of My agents"])
        }
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: shell.window.windowNumber,
                                                   context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        #expect(shell.window.performKeyEquivalent(with: escape))
        #expect(gallery.previewing == nil && shell.window.title == "Templates")
    }

    @Test("d7: inline choices", .disabled("not built yet: AB14")) func d7() async throws {}
    @Test("d8: the check step", .disabled("not built yet: AB14")) func d8() async throws {}
}
