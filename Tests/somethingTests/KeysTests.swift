// The one table of commands and the menu bar made from it, against the mockup's tables (Tests/Fixtures/mockup) both
// ways: the same keys with the same words, the same menus in the same order; every command owned by a slice; greyed,
// never hidden, while no space is open; the keys something keeps from a page, on any layout, and the monitor that
// keeps them; About's version and promise.
import AppKit
import Foundation
import Testing
@testable import something

/// The mockup's tables, and a menu written as lines to compare with them.
enum Mockup {
    static let folder = Home.share.deletingLastPathComponent().appendingPathComponent("Tests/Fixtures/mockup")

    static func json(_ name: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent(name))) as? [String: Any])
    }

    /// shortcuts.json as (area, id, words, keys, contextual), in its order.
    static func shortcuts() throws -> [(area: String, id: String, words: String, keys: String, contextual: Bool)] {
        let areas = try #require(try json("shortcuts.json")["areas"] as? [[String: Any]])
        return try areas.flatMap { area in
            try #require(area["items"] as? [[String]]).map { item in
                (try #require(area["area"] as? String), item[0], item[1], item[2], item.count > 3 && item[3] == "contextual")
            }
        }
    }

    /// menus.json, each menu's items as lines (system items left out: macOS adds them), and the titles greyed while
    /// no space is open.
    static func menus() throws -> (menus: [(title: String, lines: [String])], needsSpace: [String]) {
        let menus = try #require(try json("menus.json")["menus"] as? [[String: Any]])
        var needsSpace: [String] = []
        let lined = try menus.map { menu in
            let items = try #require(menu["items"] as? [[String: Any]]).filter { $0["system"] == nil }
            let title = try #require(menu["title"] as? String)
            needsSpace += items.filter { $0["needsSpace"] as? Bool == true }.compactMap { ($0["title"] as? String).map { "\(title) › \($0)" } }
            return (title, items.map { item -> String in
                if item["separator"] != nil { return "---" }
                if let header = item["header"] as? String { return "# " + header }
                if item["spaces"] != nil { return "(spaces)" }
                return line(item["title"] as? String ?? "", item["key"] as? String ?? "")
            })
        }
        return (lined, needsSpace)
    }

    static func line(_ title: String, _ key: String) -> String { key.isEmpty ? title : "\(title)  \(key)" }

    /// `menu`'s items as lines; the spaces of Go become one "(spaces)" line unless `spaces` keeps them.
    static func lines(_ menu: NSMenu, spaces: Bool = false) -> [String] {
        var lines: [String] = []
        for item in menu.items {
            if item.isSeparatorItem { lines.append("---"); continue }
            if item.isSectionHeader { lines.append("# " + item.title); continue }
            let key = item.keyEquivalent.isEmpty ? "" : Keys.symbols(item.keyEquivalentModifierMask) + Keys.name(item.keyEquivalent)
            if item.identifier?.rawValue.hasPrefix("space:") == true, !spaces {
                if lines.last != "(spaces)" { lines.append("(spaces)") }
                continue
            }
            lines.append(line((item.state == .on ? "✓ " : "") + item.title, key))
        }
        // Go with no space to list still has the place where they go.
        if menu.title == "Go", !lines.contains("(spaces)"), let header = lines.firstIndex(of: "# Spaces"), !spaces {
            lines.insert("(spaces)", at: header + 1)
        }
        return lines
    }

    /// The menu bar as text, each item's enabled state in `situation` said: the g9 dump.
    static func dump(_ bar: NSMenu, _ situation: Keys.Situation) -> String {
        bar.items.compactMap(\.submenu).map { menu in
            ([menu.title] + zip(menu.items, lines(menu, spaces: true)).map { item, line in
                let greyed = item.identifier.map { !Keys.enabled($0.rawValue, situation) } ?? false
                return "  " + line + (greyed ? "  (greyed)" : "")
            }).joined(separator: "\n")
        }.joined(separator: "\n") + "\n"
    }
}

@MainActor @Suite struct KeysTests {
    @Test func theTableIsTheMockupsShortcutsBothWays() throws {
        let shortcuts = try Mockup.shortcuts()
        for shortcut in shortcuts {
            let command = try #require(Keys.command(shortcut.id), "\(shortcut.id) is missing")
            #expect(command.area?.rawValue == shortcut.area && command.line == shortcut.words && command.shown == shortcut.keys,
                    "\(shortcut.id): \(command.area?.rawValue ?? "-") \(command.line ?? "-") \(command.shown)")
            // A contextual key is said in words, never a key equivalent that would take it from every page and field.
            #expect(shortcut.contextual == (command.key.isEmpty && command.words != nil && shortcut.id != "goto"), "\(shortcut.id)")
        }
        let listed = Keys.commands.filter { $0.area != nil }
        #expect(listed.map(\.id) == shortcuts.map(\.id), "the sheet lists the mockup's in its order, and no other")
        #expect(Keys.Command.Area.allCases.map(\.rawValue) == Array(NSOrderedSet(array: shortcuts.map(\.area))) as? [String])
        // The plan's keys, said the Mac's way.
        let keys = ["⌘N", "⇧⌘T", "⌘P", "⌘I", "⌘K", "⌘J", "⌘R", "⌘1 … ⌘9", "⌘/", "⌘\\", "⌥⌘S", "⌥⌘P", "⇧⌘K", "⌘.", "⇧⌘E", "⌥⌘R",
                    "⌃⌘F", "⌃⌘S", "⇧⌘Z", "⌘W", "⌘⌫", "⌘↵", "hold ⌥", "esc"]
        #expect(Set(keys).isSubset(of: Set(Keys.commands.map(\.shown))), "\(Set(keys).subtracting(Keys.commands.map(\.shown)))")
    }

    @Test func theMenuBarIsTheMockupsBothWays() throws {
        let (fixture, _) = try Mockup.menus()
        let bar = MenuBar(builders: nil)
        bar.spaces = { [("brief", "Daily brief"), ("agents", "My agents")] }
        bar.refresh()
        let menus = bar.menu.items.compactMap(\.submenu)
        #expect(menus.map(\.title) == fixture.map(\.title))
        for (menu, expected) in zip(menus, fixture) {
            #expect(Mockup.lines(menu) == expected.lines, "\(menu.title)")
        }
        let go = try #require(bar.submenu("Go"))
        #expect(Mockup.lines(go, spaces: true).contains("Daily brief  ⌘1") && Mockup.lines(go, spaces: true).contains("My agents  ⌘2"))
    }

    @Test func noTwoCommandsShareAKeyAndEachHasAnOwner() throws {
        let keyed = Keys.commands.map(\.shown).filter { !$0.isEmpty }
        #expect(keyed.count == Set(keyed).count, "\(keyed.filter { key in keyed.filter { $0 == key }.count > 1 })")
        #expect(Set(Keys.commands.map(\.id)).count == Keys.commands.count)
        #expect(!keyed.contains("⇧⌘I"), "Import Space… has no key; Info is ⌘I")
        #expect(Keys.shown("import").isEmpty && Keys.shown("insp") == "⌘I")
        let slice = try Regex("^[A-Z]+[0-9]+[a-z]?$")
        for command in Keys.commands { #expect(command.owner.wholeMatch(of: slice) != nil, "\(command.id) has no owning slice") }
        // Every item of the menus is a command of the table.
        for case .item(let id, _) in Keys.menus.flatMap(\.entries) { #expect(Keys.command(id) != nil, "\(id)") }
        #expect(Keys.tooltip("reload") == "Reload Space (⌘R)")
    }

    @Test func withNoSpaceOpenSpaceAndAssistantArePresentAndGreyed() throws {
        let bar = MenuBar(builders: nil)
        bar.refresh()
        let none = Keys.Situation()
        for title in ["Space", "Assistant"] {
            let items = try #require(bar.submenu(title)).items.filter { !$0.isSeparatorItem && !$0.isSectionHeader }
            #expect(!items.isEmpty && items.allSatisfy { !$0.isHidden })
            for item in items { #expect(!Keys.enabled(try #require(item.identifier?.rawValue), none), "\(title) › \(item.title)") }
            #expect(bar.submenu(title)?.items.first?.title == "No space open")
        }
        // Both ways: what the mockup greys without a space is greyed, and a command the table greys is greyed somewhere
        // in the mockup (Reload, Export and the others are greyed in Space, not repeated in View or File).
        let (fixture, needsSpace) = try Mockup.menus()
        var greyedSomewhere: Set<String> = []
        for (title, _) in fixture {
            for item in try #require(bar.submenu(title)).items {
                guard let id = item.identifier?.rawValue, Keys.command(id) != nil else { continue }
                guard needsSpace.contains("\(title) › \(item.title)") else { continue }
                greyedSomewhere.insert(id)
                #expect(!Keys.enabled(id, none), "\(title) › \(item.title)")
            }
        }
        for command in Keys.commands where command.needsSpace { #expect(greyedSomewhere.contains(command.id), "\(command.id)") }
        let open = Keys.Situation(space: true)
        #expect(["insp", "reload", "finder", "export", "trash", "ask", "convo", "newconvo", "buildWith"].allSatisfy { Keys.enabled($0, open) })
        // Not wired yet: present and greyed, a space open or not.
        #expect(!["palette", "settings", "keys", "reduce", "pointpart", "history", "rights", "versions", "askAll", "sleep"]
            .contains { Keys.enabled($0, open) })
        #expect(Keys.enabled("stop", Keys.Situation(working: true)), "a build on the New Space page can be stopped")
        #expect(!Keys.enabled("showreq", open) && Keys.enabled("showreq", Keys.Situation(waiting: true)), "Show Request while one waits")
    }

    @Test func moveToTrashStepsAsideWhileTextIsEdited() throws {
        var editing = false
        let bar = MenuBar(builders: nil)
        bar.editingText = { editing }
        bar.refresh()
        let trashes = ["File", "Space"].compactMap { bar.submenu($0)?.items.first { $0.identifier?.rawValue == "trash" } }
        #expect(trashes.count == 2 && trashes.allSatisfy { $0.keyEquivalent == "\u{8}" })
        editing = true
        bar.refresh()
        #expect(trashes.allSatisfy { $0.keyEquivalent.isEmpty }, "⌘⌫ deletes in the field")
        #expect(!Keys.enabled("trash", Keys.Situation(space: true, editingText: true)))
        #expect(Keys.enabled("trash", Keys.Situation(space: true)))
    }

    @Test func goListsTheSpacesWithTheirKeysAndTheHeadersNameTheOpenOne() throws {
        let bar = MenuBar(builders: nil)
        let spaces = (1...10).map { ("s\($0)", "Space \($0)") } + [("logs", "Logs")]
        bar.spaces = { spaces }
        bar.open = { ("logs", "Logs") }
        bar.refresh()
        bar.refresh()
        let go = try #require(bar.submenu("Go"))
        let listed = go.items.filter { $0.identifier?.rawValue.hasPrefix("space:") == true }
        #expect(listed.map(\.title) == spaces.map(\.1), "made again, never twice")
        #expect(listed.prefix(9).map(\.keyEquivalent) == (1...9).map(String.init) && listed[9].keyEquivalent.isEmpty)
        #expect(listed.filter { $0.state == .on }.map(\.title) == ["Logs"])
        #expect(listed.allSatisfy { $0.action == #selector(App.goToSpace(_:)) })
        #expect(bar.submenu("Space")?.items.first?.title == "Logs" && bar.submenu("Assistant")?.items.first?.title == "Logs’ assistant")
        bar.open = { ("s1", "Daily brief") }
        bar.refresh()
        #expect(bar.submenu("Assistant")?.items.first?.title == "Daily brief’s assistant")
    }

    static func event(_ key: String, _ modifiers: NSEvent.ModifierFlags, keyCode: UInt16 = 0, window: Int = 0) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window, context: nil,
                                      characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: keyCode))
    }

    @Test func theKeysSomethingKeepsFromAPage() throws {
        let kept: [(String, NSEvent.ModifierFlags)] = [("p", .command), ("k", .command), ("j", .command), ("i", .command), ("n", .command),
            (",", .command), ("/", .command), ("\\", .command), (".", .command), ("K", [.command, .shift]), ("T", [.command, .shift]),
            ("p", [.command, .option]), ("s", [.command, .option]), ("1", .command), ("9", .command), ("f", [.command, .control]),
            ("s", [.command, .control]), ("r", .command)]
        for (key, modifiers) in kept { #expect(Keys.claims(try Self.event(key, modifiers)), "\(Keys.symbols(modifiers))\(key)") }
        let left: [(String, NSEvent.ModifierFlags)] = [("z", .command), ("Z", [.command, .shift]), ("c", .command), ("v", .command),
            ("a", .command), ("w", .command), ("0", .command), ("P", [.command, .shift]), ("p", []), ("1", [.command, .option])]
        for (key, modifiers) in left { #expect(!Keys.claims(try Self.event(key, modifiers)), "\(Keys.symbols(modifiers))\(key)") }
        // The guide tells a page which keys it cannot keep.
        let guide = try String(contentsOf: Home.share.appendingPathComponent("guide.md"), encoding: .utf8)
        for command in Keys.commands where command.mine { #expect(guide.contains(command.shown), "\(command.shown)") }
    }

    /// On a layout that needs ⇧ for a character (French AZERTY: . is ⇧;, / is ⇧:, the digits are the shifted top row),
    /// the keys are still something's; a ⇧ the character does not need still leaves them to the page.
    @Test func aLayoutThatNeedsShiftKeepsTheKeys() throws {
        #expect(Keys.claim(try Self.event(".", [.command, .shift], keyCode: 43)) == .command("stop"))
        #expect(Keys.claim(try Self.event("/", [.command, .shift], keyCode: 47)) == .command("keys"))
        #expect(Keys.claim(try Self.event("&", .command, keyCode: 18)) == .space(1), "the bare 1 key types &")
        #expect(Keys.claim(try Self.event("ç", .command, keyCode: 25)) == .space(9))
        #expect(Keys.claim(try Self.event("1", [.command, .shift], keyCode: 18)) == .space(1), "⇧ types the digit")
        #expect(Keys.claim(try Self.event("!", [.command, .shift], keyCode: 18)) == nil, "⇧⌘1 on QWERTY types !")
        #expect(Keys.claim(try Self.event("P", [.command, .shift], keyCode: 35)) == nil)
        #expect(Keys.claim(try Self.event("&", [.command, .option], keyCode: 18)) == nil)
        #expect(Keys.claim(try Self.event("1", [.command, .option], keyCode: 18)) == nil)
        #expect(Keys.claim(try Self.event("K", [.command, .shift], keyCode: 40)) == .command("newconvo"))
    }

    /// The key monitor: a claimed key typed in the app's window acts through its item and never reaches the page; in
    /// another window, or a key that is the page's, it goes on.
    @Test(.enabled(if: windowServer, windowServerMissing)) func theMonitorGivesAClaimedKeyToItsItem() throws {
        let bar = MenuBar(builders: nil)
        bar.spaces = { [("brief", "Daily brief"), ("agents", "My agents")] }
        var acted: [String] = []
        bar.act = { acted.append($0.identifier?.rawValue ?? "") }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        #expect(bar.intercept(try Self.event("2", .command, keyCode: 19, window: window.windowNumber), window: window) == nil)
        #expect(bar.intercept(try Self.event("k", .command, keyCode: 40, window: window.windowNumber), window: window) == nil)
        #expect(bar.intercept(try Self.event("9", .command, keyCode: 25, window: window.windowNumber), window: window) == nil,
                "a number with no space is still not the page's")
        #expect(acted == ["space:agents", "ask"])
        #expect(bar.intercept(try Self.event("&", .command, keyCode: 18, window: window.windowNumber), window: window) == nil)
        #expect(acted.last == "space:brief", "AZERTY's ⌘&")
        let elsewhere = try Self.event("k", .command, keyCode: 40, window: other.windowNumber)
        #expect(bar.intercept(elsewhere, window: window) === elsewhere)
        let copy = try Self.event("c", .command, keyCode: 8, window: window.windowNumber)
        #expect(bar.intercept(copy, window: window) === copy)
        #expect(acted.count == 3)
    }

    @Test func aboutSaysTheVersionAndThePromise() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("something-keys-\(UUID().uuidString).bundle")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let info = ["CFBundleShortVersionString": "0.3.0", "CFBundleVersion": "31", "CFBundleIdentifier": "com.example.keys-test"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: folder.appendingPathComponent("Contents/Info.plist"))
        let bundle = try #require(Bundle(url: folder))
        let about = Keys.about(bundle)
        #expect(about[.applicationVersion] as? String == "0.3.0" && about[.version] as? String == "31")
        #expect((about[.credits] as? NSAttributedString)?.string.hasSuffix("Nothing leaves this Mac.") == true)
    }
}
