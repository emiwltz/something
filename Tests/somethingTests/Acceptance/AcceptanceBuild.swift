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
    @Test("d1: New Space", .disabled("not built yet: AB12")) func d1() async throws {}
    @Test("d2: the build ladder", .disabled("not built yet: AB14")) func d2() async throws {}
    @Test("d3: the arrival", .disabled("not built yet: AB15")) func d3() async throws {}
    @Test("d4: the rights sheet", .disabled("not built yet: AB16")) func d4() async throws {}
    /// The Templates page in the window, the toolbar's chip at the mockup's one request, the old composer gone (the
    /// mockup shows the page alone); and the page's model.
    static func templates(_ stage: Stage, _ size: NSSize = Stage.Size.main) throws -> (Shell, Library, Gallery, NSView) {
        let (shell, library, _) = stage.window(size)
        library.select(.templates)
        shell.show(nil, templates: true)
        shell.floating?.isHidden = true
        shell.waiting(1)
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
        shell.window.setContentSize(NSSize(width: 760, height: 680))
        #expect(GalleryView.columns(760 - 236 - 80) == 2 && GalleryView.columns(1200 - 236 - 80) == 3)
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
