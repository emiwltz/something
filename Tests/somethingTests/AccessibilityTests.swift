// The accessibility tree of every main view, read whole as an assistive app reads it: each element's label and every
// attribute it names, depth first. A label that resolves through itself (SwiftUI's selectable text given a label of
// its own did, and an assistive app reading New Space after a build crashed the app on it) ends this process here.
import AppKit
import SwiftUI
@testable import SomethingAgents
import SomethingCore
import Testing
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-accept-ax-"))
struct AccessibilityTests {
    /// What the walk read: the elements, the words they say, and the buttons that say nothing. Offscreen, SwiftUI's
    /// elements give no role, so only AppKit's buttons can be found unnamed.
    struct Tree {
        var count = 0, words: [String] = [], unnamed: [String] = []
    }

    /// The whole tree under `root`, read as an assistive app asks (AXEnhancedUserInterface on, so SwiftUI makes its
    /// elements), once it holds still: two reads 0.1 s apart with the same words (none only
    /// after a second: SwiftUI may not have made them yet), or after ten seconds.
    /// The mode is the whole process's, and slows every SwiftUI view made meanwhile: the walk takes Stage's turn, as
    /// what is timed does.
    static func walk(_ root: Any) async -> Tree {
        await Stage.alone {
            let enhanced = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
            NSApp.accessibilitySetValue(true, forAttribute: enhanced)
            defer { NSApp.accessibilitySetValue(false, forAttribute: enhanced) }
            let end = Date() + 10
            var last: [String]?
            while true {
                await wait(0.1)
                var tree = Tree()
                read(root, depth: 0, into: &tree)
                if tree.words == last && (!tree.words.isEmpty || Date() > end - 9) || Date() > end { return tree }
                last = tree.words
            }
        }
    }

    private static func read(_ element: Any, depth: Int, into tree: inout Tree) {
        // A tree deeper than this, or this large, is itself the fault: the walk stops rather than hang.
        guard depth < 80, tree.count < 20_000 else { return }
        tree.count += 1
        let object = element as AnyObject, described = NSAccessibility.Attribute(rawValue: "AXAttributedDescription")
        let label = (object as? NSAccessibilityProtocol)?.accessibilityLabel() ?? nil
        var said: [String] = [label].compactMap { $0 }
        for name in (object.accessibilityAttributeNames() as [NSAccessibility.Attribute]?) ?? [] {
            let value = object.accessibilityAttributeValue(name)
            // Offscreen, SwiftUI's elements say their words only as AXAttributedDescription.
            guard [.description, .title, .value, described].contains(name) else { continue }
            said += [(value as? String) ?? (value as? NSAttributedString)?.string].compactMap { $0 }
        }
        said = said.filter { !$0.isEmpty }
        tree.words += said
        // The window's own buttons and a scroll bar's arrows are macOS's, named once shown on a screen.
        let kind = String(describing: type(of: object))
        if (object as? NSAccessibilityProtocol)?.accessibilityRole() == .button, said.isEmpty,
           !kind.hasPrefix("_NSTheme"), kind != "NSAccessibilityScrollerPart" {
            tree.unnamed.append(kind)
        }
        for child in (object as? NSAccessibilityProtocol)?.accessibilityChildren() ?? [] {
            read(child, depth: depth + 1, into: &tree)
        }
    }

    /// New Space while a build runs and after it ended in a reply: the reply, selectable, says who speaks.
    @Test func newSpace() async throws {
        let stage = try Stage("ax")
        defer { stage.remove() }
        let (shell, _, _) = try await AcceptanceBuild.newSpace(stage, builder: true)
        let model = shell.assistant
        let empty = await Self.walk(shell.window)
        #expect(empty.count > 20 && empty.words.contains(BlankView.chips[0].0) && empty.words.contains("With your agents: None") && empty.unnamed.isEmpty, "\(empty)")
        model.send(BlankView.chips[0].1)
        #expect(model.building)
        let building = await Self.walk(shell.window)
        #expect(building.count > 20 && building.unnamed.isEmpty, "\(building)")
        #expect(await wait(until: { !model.building && model.rows.last == .reply("Invented reply.") }))
        let answered = await Self.walk(shell.window)
        #expect(answered.words.contains("Your assistant: Invented reply.") && answered.unnamed.isEmpty, "\(answered)")
        await AcceptanceBuild.finish(model)
    }

    /// Templates, a space with its card and conversation open, and the request panel beside the window.
    @Test func spaceTemplatesAndPanel() async throws {
        let stage = try Stage("ax")
        defer { stage.remove() }
        let (shell, library, brief) = try await AcceptanceAssistant.atWork(stage)
        defer { brief.close() }
        let model = shell.assistant
        model.focus()
        model.threadShown = true
        let space = await Self.walk(shell.window)
        #expect(space.words.contains("Message") && space.words.contains("Fold Conversation") && space.unnamed.isEmpty, "\(space)")

        let source = FakePrompts()
        AcceptanceTrust.request("r", [0], in: source)
        let panels = AcceptanceTrust.panels(source, shell, open: "brief")
        panels.refresh()
        let panel = try #require(panels.panel)
        let asked = await Self.walk(panel)
        #expect(asked.words.contains("Allow Once") && asked.words.contains("Deny") && asked.unnamed.isEmpty, "\(asked)")

        library.select(.templates)
        shell.show(nil, templates: true)
        let templates = await Self.walk(shell.window)
        #expect(templates.words.contains("My agents") && templates.unnamed.isEmpty, "\(templates)")
        await AcceptanceBuild.finish(model)
    }

    /// Every tab of Settings, and the two views of something's own words: a space that cannot be shown, and the list of
    /// agents to install.
    @Test func settingsAndNotices() async throws {
        let stage = try Stage("ax")
        defer { stage.remove() }
        let model = SettingsModel(preferences: Preferences(stage.home.places), places: stage.home.places)
        model.spaces = { [("brief", "Daily brief")] }
        model.apply = { _ in }
        let settings = SettingsWindow(model)
        settings.window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        settings.window.alphaValue = 0
        defer { settings.window.close() }
        for tab in SettingsTab.allCases {
            settings.select(tab)
            let page = await Self.walk(settings.window)
            #expect(page.words.contains(tab.label) && page.unnamed.isEmpty, "\(tab): \(page)")
        }

        let (shell, _, _) = stage.window()
        let fault = AssistantModel.Fault(title: "Daily brief", name: "brief", codes: ["BAD_DECLARATION"])
        let unshown = NSHostingView(rootView: Unshown(problems: ["The declaration is not valid JSON. Fix it. (BAD_DECLARATION)"],
                                                      fault: fault, assistant: shell.assistant))
        let window = Offscreen(unshown).window
        // Its texts, plain and selectable, give no words offscreen: the walk only proves each one resolves.
        let notice = await Self.walk(window)
        #expect(notice.count > 3 && notice.unnamed.isEmpty, "\(notice)")
        let install = Offscreen(NSHostingView(rootView: InstallList(rows: [("Claude Code", "brew install example")], copy: { _ in })))
        let list = await Self.walk(install.window)
        #expect(list.words.contains("Copy") && list.unnamed.isEmpty, "\(list)")
    }
}
