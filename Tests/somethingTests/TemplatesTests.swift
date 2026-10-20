// The templates of share/templates (plan B.5) pass `something check` with no problem at all, as the person's spaces
// in a throwaway home: once with every right they declare, then with each of those rights refused, which they must
// adapt to. Each has its preview, made from the HTML it has now (previews.json keeps the SHA-256 of that HTML), loads
// nothing from the network and uses only fonts every Mac has. Use Template and `something new --from` make them spaces.
// With SOMETHING_PREVIEWS naming share/templates, `makesThePreviews` draws the previews again (tools/previews.sh).
import AppKit
import CryptoKit
import Foundation
import SomethingCore
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
    static let dark: Set = ["agents", "project"]

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
        #expect(TemplatesTests.names.count >= 3)
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
        #expect(lines <= 700, "\(name) has \(lines) lines; a template stays under 700, short enough for an agent to read")
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
        var used: [String] = [], opened: [String?] = []
        library.used = { used.append($0) }
        library.opened = { opened.append($0) }
        let agents = try #require(library.templates.first { $0.id == "agents" })
        #expect(library.templates.map(\.id) == TemplatesTests.names)
        #expect(agents.title == "My agents" && agents.tags == ["Sees your agents", "Writes to your agents"] && !agents.follows)
        // A double click: the second click comes before the first space opened, and makes nothing.
        library.use(agents)
        library.use(agents)
        #expect(used == ["agents"] && Spaces(root: home.places.spaces).list().map(\.name) == ["agents"])
        #expect(await wait(1, until: { opened == ["agents"] }))
        await wait(0.05)
        library.use(agents)
        #expect(used == ["agents", "agents-2"] && library.selection == "agents-2" && ask.told.isEmpty)
        let made = try String(contentsOf: home.places.spaces.appendingPathComponent("agents-2.html"), encoding: .utf8)
        #expect(made == (try String(contentsOf: TemplatesTests.folder.appendingPathComponent("agents.html"), encoding: .utf8)))
    }

    @MainActor @Test func projectWatchFollowsTheFolderChosenFirst() throws {
        let home = try home()
        defer { home.remove() }
        let ask = FakeAsk(), library = Library(places: home.places, ask: ask, share: Home.share)
        let project = try #require(library.templates.first { $0.id == "project" })
        #expect(project.follows && project.tags == ["Sees your agents", "Writes to your agents", "Starts agents", "Remembers"])
        // Cancel makes nothing.
        library.use(project)
        #expect(ask.folderMessages == ["Choose the project folder this space follows"] && Spaces(root: home.places.spaces).list().isEmpty)
        // A quote, and a "</script>" that must not end the declaration's block early (the folder "shop <" holds "script>").
        ask.folder = home.root.appendingPathComponent("code/my \"shop\" </script>")
        library.use(project)
        let space = try #require(Spaces(root: home.places.spaces).named("project"))
        let declaration = try #require(Declaration.read(space, home: home.root).declaration)
        let chosen = "~/code/my \"shop\" </script>"
        #expect(declaration.folder == chosen && declaration.agents == .folders([chosen]))
        #expect(library.selection == "project")
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

    /// `image` as a PNG `width` pixels wide.
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
        return try #require(rep.representation(using: .png, properties: [:]))
    }
}
