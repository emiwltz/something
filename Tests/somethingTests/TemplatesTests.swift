// The templates of share/templates pass `something check` with no problem at all, as the person's spaces
// in a throwaway home: once with every right they declare, then with each of those rights refused, which they must
// adapt to. Each has its preview, made from the HTML it has now (previews.json keeps the SHA-256 of that HTML), loads
// nothing from the network and uses only fonts every Mac has. Use
// Template and `something new --from` make them spaces.
// With SOMETHING_PREVIEWS naming share/templates, `makesThePreviews` draws the previews again (tools/previews.sh).
import AppKit
import CryptoKit
import Foundation
import SomethingAgents
import SomethingCore
import SwiftUI
import Testing
import WebKit
@testable import something

@Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-templates-")) struct TemplatesTests {
    static let folder = Home.share.appendingPathComponent("templates")
    static let names = Template.names.filter { FileManager.default.fileExists(atPath: folder.appendingPathComponent("\($0).html").path) }
    /// The fonts a template may name: those of every Mac since macOS 15, and the generic families.
    static let fonts: Set = ["ui-monospace", "SF Mono", "Menlo", "Avenir Next Condensed", "Avenir Next", "Helvetica Neue", "Didot",
                             "Bodoni 72", "ui-serif", "New York", "Georgia", "American Typewriter", "Courier New", "ui-rounded",
                             "Futura", "system-ui", "-apple-system", "ui-sans-serif",
                             "serif", "sans-serif", "monospace"]
    /// The appearance each preview is drawn in: the template's own face, whatever the Mac that draws it uses.
    static let dark: Set = ["one-line"]

    /// A home with the folder Project watch's placeholder names, so that its check finds it.
    func home() throws -> Home {
        let home = Home(prefix: "something-templates-")
        try FileManager.default.createDirectory(at: home.root.appendingPathComponent("code/your-project"), withIntermediateDirectories: true)
        return home
    }

    @Test func eachTemplateHasItsPreviewOfItsHTMLNow() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: TemplatesTests.folder.path)
        let pages = files.filter { $0.hasSuffix(".html") }.map { String($0.dropLast(5)) }
        #expect(Set(pages) == Set(TemplatesTests.names), "share/templates holds a page that is not one of Template.names: \(pages)")
        #expect(TemplatesTests.names == Template.names, "share/templates lacks a template: \(Set(Template.names).subtracting(pages).sorted())")
        let kept = try JSONSerialization.jsonObject(with: Data(contentsOf: TemplatesTests.folder.appendingPathComponent("previews.json"))) as? [String: String]
        for name in TemplatesTests.names {
            #expect(files.contains("\(name).png"), "\(name) has no preview")
            let hash = try TemplatesTests.hash(name)
            #expect(kept?[name] == hash, "\(name).png was not made from \(name).html as it is now: run tools/previews.sh")
        }
        #expect(Set(kept?.keys ?? [:].keys) == Set(TemplatesTests.names))
    }

    static func hash(_ name: String) throws -> String {
        SHA256.hash(data: try Data(contentsOf: folder.appendingPathComponent("\(name).html"))).map { String(format: "%02x", $0) }.joined()
    }

    @Test(arguments: names) func staysOnThisMacWithItsFonts(_ name: String) throws {
        let html = try String(contentsOf: TemplatesTests.folder.appendingPathComponent("\(name).html"), encoding: .utf8)
        let lines = html.filter { $0 == "\n" }.count
        #expect(lines <= 2500, "\(name) has \(lines) lines; a template stays under 2,500, short enough for an agent to read")
        for banned in ["http://", "https://", "@import", "@font-face", "url("] {
            #expect(!html.lowercased().contains(banned), "\(name) contains \(banned)")
        }
        // Every font and font-family declaration, and every custom property one of them uses, ends in a generic family
        // and names only fonts of the list. A family of two words must be quoted: an unquoted one is read as its last word.
        var stacks: [String] = [], variables: Set<String> = []
        for match in html.matches(of: #/(?:^|[\s;{"'])(?:font|font-family)\s*:\s*([^;{}<\n]+)/#) {
            let value = String(match.output.1).trimmingCharacters(in: .whitespacesAndNewlines)
            let used = value.matches(of: #/var\((--[\w-]+)\)/#).map { String($0.output.1) }
            if used.isEmpty, value != "inherit" { stacks.append(value) }
            variables.formUnion(used)
        }
        for variable in variables {
            let defined = html.matches(of: try Regex("\(variable)\\s*:\\s*([^;{}]+)")).compactMap { $0.output[1].substring.map(String.init) }
            #expect(!defined.isEmpty, "\(name) uses \(variable) in a font but never sets it")
            stacks += defined
        }
        let generic: Set = ["serif", "sans-serif", "monospace", "system-ui", "ui-serif", "ui-sans-serif", "ui-monospace", "ui-rounded"]
        var named: Set<String> = []
        for value in stacks {
            // "700 clamp(15px, 1.12vw, 18px)/1.5 ui-serif": the sizes go first, then each family is the quoted name or
            // the last word of its item.
            let families = value.replacing(#/\([^()]*\)/#, with: "").split(separator: ",").map { item in
                item.firstMatch(of: #/"([^"]+)"/#).map { String($0.output.1) } ?? item.split(separator: " ").last.map(String.init) ?? ""
            }
            #expect(families.last.map(generic.contains) == true, "\(name): the font \(value) does not end in a generic family")
            named.formUnion(families)
        }
        #expect(!named.isEmpty, "no font stack was found in \(name)")
        #expect(named.subtracting(TemplatesTests.fonts).isEmpty, "\(name) names fonts a Mac may not have: \(named.subtracting(TemplatesTests.fonts).sorted())")
    }

    @Test(arguments: names) func passesTheCheck(_ name: String) async throws {
        let home = try home()
        defer { home.remove() }
        try home.space(name, try String(contentsOf: TemplatesTests.folder.appendingPathComponent("\(name).html"), encoding: .utf8))
        let checked = try await Checked([name, "--json"], home)
        #expect(checked.status == 0 && checked.codes.isEmpty, "\(checked.out)")
        #expect((checked.json["console"] as? [Any])?.isEmpty == true, "\(checked.out)")
        let declared = (checked.json["declaration"] as? [String: Any])?["rights"] as? [String] ?? []
        #expect(!declared.isEmpty)
        for right in declared {
            let refused = try await Checked([name, "--json", "--refuse", right], home)
            #expect(refused.status == 0 && refused.codes.isEmpty, "with \(right) refused: \(refused.out)")
        }
    }

    @MainActor @Test func useTemplateMakesASpaceUnderAFreeName() async throws {
        let home = try home()
        defer { home.remove() }
        let ask = FakeAsk(), library = Library(places: home.places, ask: ask, share: Home.share)
        var used: [String] = [], opened: [Library.Destination] = []
        library.used = { used.append($0) }
        library.opened = { opened.append($0) }
        let deck = try #require(library.templates.first { $0.id == "deck" })
        #expect(library.templates.map(\.id) == TemplatesTests.names)
        #expect(deck.title == "Decision Deck" && deck.needs == "Sees, writes to and starts agents" && !deck.follows)
        // A double click: the second click comes before the first space opened, and makes nothing.
        library.use(deck)
        library.use(deck)
        #expect(used == ["deck"] && Spaces(root: home.places.spaces).list().map(\.name) == ["deck"])
        #expect(await wait(30, until: { opened == [.space("deck")] }))
        await wait(0.05)
        library.use(deck)
        #expect(used == ["deck", "deck-2"] && library.selection == .space("deck-2") && ask.told.isEmpty)
        let made = try String(contentsOf: home.places.spaces.appendingPathComponent("deck-2.html"), encoding: .utf8)
        #expect(made == (try String(contentsOf: TemplatesTests.folder.appendingPathComponent("deck.html"), encoding: .utf8)))
    }

    // MARK: The Templates page

    /// The filters keep each template under one category, in the page's order; the shield line names every right.
    @Test func filtersByCategory() throws {
        let templates = Template.all(Home.share), gallery = Gallery()
        let kept = Template.Category.allCases.map { category in
            gallery.shown = category
            return gallery.cards(templates).map(\.id)
        }
        #expect(kept == [TemplatesTests.names, ["one-line", "deck", "council"], ["answers", "ledger"], ["village"]])
        let made = { (rights: [String]) in Template(id: "x", title: "X", line: "", rights: rights, follows: false, preview: nil, ground: nil).needs }
        #expect(made([]) == "Asks for nothing" && made(["state"]) == "Sees your agents" && made(["state", "launch"]) == "Sees and starts agents")
        #expect(made(["send:claude"]) == "Writes to your agents" && made(["store"]) == "Remembers")
    }

    /// Preview is a state of the page: it names the template in the toolbar, Escape (Close Preview's key) goes back to
    /// the cards, and Use This Template makes the copy. Show in Finder shows the template's own file.
    @MainActor @Test func previewThenEscapeThenUse() async throws {
        let home = try home()
        defer { home.remove() }
        let library = Library(places: home.places, ask: FakeAsk(), share: Home.share)
        var headings: [String] = [], shown: [URL] = []
        library.reveal = { shown.append($0) }
        let gallery = Gallery(told: { headings.append("\($0) · \($1)") }), host = NSHostingView(rootView: GalleryView(library: library, model: gallery))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 964, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        (window.contentView, window.isReleasedWhenClosed) = (host, false)
        defer { window.close() }
        let town = try #require(library.templates.first { $0.id == "village" })
        gallery.hovered = "village"
        gallery.preview(town)
        #expect(gallery.hovered == nil && gallery.heading == ("Prompt Town", "Template preview"))
        #expect(headings == ["Prompt Town · Template preview"])
        // SwiftUI draws the preview, and registers Close Preview's key, on the run loop, as late as a busy runner makes
        // it: Escape is pressed until it is taken. Before, it means nothing, and does nothing.
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                   context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        #expect(await wait { window.performKeyEquivalent(with: escape) })
        #expect(gallery.previewing == nil)
        #expect(headings.last == "Templates · Start from one, then make it yours")
        #expect(await wait { !window.performKeyEquivalent(with: escape) }, "Escape means nothing on the cards")
        #expect(gallery.previewing == nil && headings.count == 2, "\(headings)")
        library.use(town)
        #expect(Spaces(root: home.places.spaces).list().map(\.name) == ["village"])
        #expect(town.ground != nil)
        library.revealTemplate(town)
        #expect(shown == [Home.share.appendingPathComponent("templates/village.html")])
    }

    /// What an agent writes runs only in a frame cut off from something: Living Answers gives its frame scripts and
    /// nothing else, so the tool has no way to reach the page's rights.
    @Test func livingAnswersIsolatesWhatAnAgentWrites() throws {
        let page = try String(contentsOf: Self.folder.appendingPathComponent("answers.html"), encoding: .utf8)
        #expect(page.contains("allow-scripts") && !page.contains("allow-same-origin"))
    }

    // MARK: The previews

    /// Draws each template's preview into SOMETHING_PREVIEWS (share/templates) and writes previews.json there.
    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["SOMETHING_PREVIEWS"] != nil, "SOMETHING_PREVIEWS names no folder."))
    func makesThePreviews() async throws {
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["SOMETHING_PREVIEWS"]))
        var hashes: [String: String] = [:]
        for name in TemplatesTests.names {
            let image = try await TemplatesTests.snapshot(name, size: NSSize(width: 1280, height: 800), dark: TemplatesTests.dark.contains(name))
            try TemplatesTests.png(image, width: 960).write(to: folder.appendingPathComponent("\(name).png"))
            hashes[name] = try TemplatesTests.hash(name)
        }
        let json = try JSONSerialization.data(withJSONObject: hashes, options: [.prettyPrinted, .sortedKeys])
        try (json + Data("\n".utf8)).write(to: folder.appendingPathComponent("previews.json"))
    }

    /// The snapshot `something check <name>` takes of the template as a space of a throwaway home, against the invented
    /// state, at `size` points in the light or dark appearance. Project watch is checked with the invented agents of
    /// ~/code/shop moved into its placeholder folder, so that its preview shows a project at work.
    @MainActor static func snapshot(_ name: String, size: NSSize, dark: Bool) async throws -> NSImage {
        let home = try TemplatesTests().home()
        defer { home.remove() }
        try home.space(name, try String(contentsOf: folder.appendingPathComponent("\(name).html"), encoding: .utf8))
        var words = [name]
        if name == "project" {
            let state = try String(contentsOf: Home.share.appendingPathComponent("contract/state-example.json"), encoding: .utf8)
            let moved = home.root.appendingPathComponent("state.json")
            try state.replacingOccurrences(of: "/Users/example/code/shop", with: "/Users/example/code/your-project").write(to: moved, atomically: true, encoding: .utf8)
            words += ["--state", moved.path]
        }
        guard case .check(let check) = Check.parse(words) else { throw SpaceError("\(words) are not the words of a check.") }
        let runner = try CheckTests.runner(home), created = runner.created
        runner.created = { web in
            created(web)
            web.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        }
        runner.loaded = { $0.window?.setContentSize(size) }
        let report = try await runner.run(check)
        #expect(report.problems.isEmpty, "\(report.problems)")
        let file = try #require(report.snapshot)
        return try #require(NSImage(contentsOfFile: file))
    }

    /// `image` as a PNG `width` pixels wide, without the alpha a preview never uses: about a tenth smaller.
    static func png(_ image: NSImage, width: CGFloat) throws -> Data {
        let height = (width * image.size.height / image.size.width).rounded()
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        let opaque = try #require(CGContext(data: nil, width: rep.pixelsWide, height: rep.pixelsHigh, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        opaque.draw(try #require(rep.cgImage), in: CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
        let picture = try #require(opaque.makeImage())
        return try #require(NSBitmapImageRep(cgImage: picture).representation(using: .png, properties: [:]))
    }
}
