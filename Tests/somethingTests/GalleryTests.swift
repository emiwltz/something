// A gallery of every native window, drawn offscreen with invented data, one PNG at 2x each, for a person to look at
// what nobody can see in a test: no window is shown, none takes the focus, and drawing a view into a bitmap needs no
// permission of macOS (a screenshot would need Screen Recording). It runs only when SOMETHING_GALLERY names a folder:
//   SOMETHING_GALLERY=/path/to/folder swift test --filter GalleryTests
import AppKit
import SomethingAgents
import SomethingCore
import Testing
import WebKit
@testable import something

let gallery = ProcessInfo.processInfo.environment["SOMETHING_GALLERY"].map { URL(fileURLWithPath: $0) }

@MainActor @Suite(.serialized, .enabled(if: gallery != nil, "SOMETHING_GALLERY does not name a folder, so the gallery of windows is not drawn."),
                  .enabled(if: windowServer, windowServerMissing))
struct GalleryTests {
    init() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .aqua)
    }

    /// A home with the space morning-review and a second one, a grant, ten journal lines, and a share folder with an
    /// example; its temporary path is shown as /Users/example in the pictures.
    func invented() throws -> (home: Home, share: URL) {
        let home = Home()
        let declaration = #"{"contract": 1, "title": "Morning review", "description": "Reads what the agents said overnight and asks each one for a summary.", "agents": {"folders": ["~/code/shop"]}, "folder": "~/code/shop", "rights": ["state", "send:claude", "launch:claude", "store"]}"#
        let space = try home.space("morning-review", page(declaration, "<p>Morning review</p>"))
        try home.space("garden-notes", page(#"{"contract": 1, "title": "Garden notes", "rights": ["store"]}"#, "<p>Garden</p>"))
        var file = AppFile()
        var grant = Grant(declared: Asked(try #require(Declaration.read(space, home: home.root).declaration)), at: "2026-10-17T08:00:00Z")
        grant.granted = ["state", "send:claude", "store"]
        grant.refused = ["launch:claude"]
        grant.folder = home.root.appendingPathComponent("code/shop").path
        file.spaces["morning-review"] = grant
        try file.write(home.places.grants)
        let journal = Journal(folder: home.places.journals)
        let texts = ["What changed in the cart overnight?", "Summarize the failing tests.", nil, "Stop after this file.", nil]
        for minute in 0..<10 {
            let line = JournalLine(at: "2026-10-17T08:0\(minute):00Z", action: minute % 5 == 2 ? "interrupt" : "send", agent: "a\(minute % 3 + 1)",
                                   kind: "claude", when: minute % 5 == 2 ? nil : "now", text: texts[minute % 5], result: minute == 7 ? "busy" : "ok")
            try journal.append(line, space: "morning-review")
        }
        let share = home.root.appendingPathComponent("share")
        try FileManager.default.createDirectory(at: share.appendingPathComponent("examples"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Home.share.appendingPathComponent("template.html"), to: share.appendingPathComponent("template.html"))
        try page(#"{"contract": 1, "title": "Who is waiting", "rights": ["state"]}"#, "<p>Waiting</p>")
            .write(to: share.appendingPathComponent("examples/who-is-waiting.html"), atomically: true, encoding: .utf8)
        return (home, share)
    }

    @Test func drawsEveryWindow() async throws {
        let folder = try #require(gallery)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let (test, share) = try invented()
        defer { test.remove() }
        let kinds = ["claude": Kind(launch: true, installed: true, tested: "2.1", seen: "2.1", reader: "ok", note: nil),
                     "codex": Kind(launch: true, installed: true, tested: "0.50", seen: "0.52", reader: "changed",
                                   note: "0.52 is newer than the one tested (0.50): what it says may be read wrong."),
                     "opencode": Kind(launch: false, installed: false, tested: "1.0", seen: nil, reader: "none", note: "OpenCode is not installed.")]

        let home = something.Home(places: test.places, share: share, ask: FakeAsk())
        home.card.kinds = { kinds }
        let window = home.makeWindow()
        home.reload(selecting: "morning-review")
        try draw(try #require(window.contentView), "home", test)

        let card = Card(places: test.places, ask: FakeAsk())
        card.kinds = { kinds }
        card.show(Spaces(root: test.places.spaces).named("morning-review"))
        try draw(card.view, "card", test)

        let first = RightsQuestion(space: "Morning review", description: "Reads what the agents said overnight and asks each one for a summary.",
                                   rights: ["state", "send:claude", "launch:claude", "store"], scope: .folders(["~/code/shop", "~/code/garden"]),
                                   missing: ["~/code/garden"], folder: FolderQuestion(declared: "~/code/shop", found: "/Users/example/code/shop"))
        try draw(Ask.rights(first).alert, "rights-first-opening", test)
        let pi = RightsQuestion(space: "Morning review", description: nil, rights: ["launch:pi"], scope: nil, missing: [],
                                folder: FolderQuestion(declared: "~/code/garden", found: nil))
        try draw(Ask.rights(pi).alert, "rights-launch-pi", test)
        try draw(Ask.lowers("acceptEdits", kind: "claude", folder: "/Users/example/code/shop", space: "Morning review"), "lowering-mode", test)
        try draw(Ask.link(try #require(URL(string: "https://example.com/notes/overnight")), space: "Morning review"), "link", test)
        try draw(Ask.withData("morning-review", keys: ["drafts", "last-read", "summaries"], bytes: 18_400), "export", test)
        try draw(Ask.quit(2), "quit-while-agents-run", test)

        let who = "Claude Code “shop”, working in /Users/example/code/shop, launched by “Morning review”,"
        let permission = Prompt(request: Request(id: "r1", agent: "a1", kind: "permission", tool: "Bash", about: "npm test",
                                                 at: "2026-10-17T09:00:01Z"), input: "npm test -- --runInBand src/cart")
        try draw(try #require(PromptPanel(permission, who: who) { _ in }.contentView), "permission-panel", test)
        let question = Prompt(request: Request(id: "r2", agent: "a1", kind: "question", tool: nil, about: "Which test runner?",
                                               at: "2026-10-17T09:00:02Z"),
                              questions: [Question(header: "Runner", text: "Which test runner should the cart use?",
                                                   options: ["Jest", "Vitest", "Node's own"], multiple: false),
                                          Question(header: "Scope", text: "Which folders should it cover?",
                                                   options: ["src/cart", "src/checkout"], multiple: true)])
        try draw(try #require(PromptPanel(question, who: who) { _ in }.contentView), "question-panel", test)

        let html = try String(contentsOf: Home.share.appendingPathComponent("template.html"), encoding: .utf8)
        let space = try test.space("morning-review", html)
        let open = try await test.window(space)
        defer { open.close() }
        let offscreen = Offscreen(open.web)
        open.open()
        #expect(await wait(until: { !open.web.isLoading && open.frame != nil }), "the space window did not load template.html")
        await wait(1)
        let snapshot = try await open.web.takeSnapshot(configuration: nil)
        try png(of: open.web.bounds.size, "space-window") { snapshot.draw(in: NSRect(origin: .zero, size: open.web.bounds.size)) }
        withExtendedLifetime(offscreen) {}
    }

    /// Draws an alert's window as it would be shown.
    func draw(_ alert: NSAlert, _ name: String, _ test: Home) throws {
        alert.layout()
        try draw(try #require(alert.window.contentView), name, test)
    }

    /// Draws `view`, laid out at its size (its fitting size when it has none), into `name`.png at 2x, on the window's
    /// background: an alert's content draws nothing behind its text when it is not on the screen.
    func draw(_ view: NSView, _ name: String, _ test: Home) throws {
        disguise(view, test.root.path)
        if view.frame.isEmpty { view.frame.size = view.fittingSize }
        view.layoutSubtreeIfNeeded()
        let rep = try bitmap(view.bounds.size)
        view.cacheDisplay(in: view.bounds, to: rep)
        try png(of: view.bounds.size, name) { rep.draw(in: NSRect(origin: .zero, size: view.bounds.size)) }
    }

    func bitmap(_ size: NSSize) throws -> NSBitmapImageRep {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        return rep
    }

    /// Writes `name`.png, `size` points at 2x: the window's background, then what `content` draws.
    func png(of size: NSSize, _ name: String, _ content: () -> Void) throws {
        let rep = try bitmap(size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: size).fill()
            content()
        }
        NSGraphicsContext.restoreGraphicsState()
        try #require(rep.representation(using: .png, properties: [:])).write(to: try #require(gallery).appendingPathComponent("\(name).png"))
    }

    /// Shows the temporary home as /Users/example: the pictures say what a person would read.
    func disguise(_ view: NSView, _ root: String) {
        if let field = view as? NSTextField { field.stringValue = field.stringValue.replacingOccurrences(of: root, with: "/Users/example") }
        if let text = view as? NSTextView { text.string = text.string.replacingOccurrences(of: root, with: "/Users/example") }
        view.subviews.forEach { disguise($0, root) }
    }
}
