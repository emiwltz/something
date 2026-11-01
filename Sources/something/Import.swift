// Import: what comes into something from outside, a folder, an .html file or a .something file. It is read whole, staged
// in a throwaway copy under a name of ours, checked there in a view locked off the network, and described from what was
// read, never from what the file would show elsewhere: a file made on purpose can show a browser one page and hold
// another, and the page read is the page checked and the page that comes in. Nothing is placed and no right is given
// until the person presses Import, the original never changes, and the copy gains a declaration if it has none.
// A file dragged over the window comes the same way (`Drops`): over a page only what import takes is the app's, and any
// other drag goes on to the page, whose drop zones keep working.
import AppKit
import SomethingAgents
import SomethingCore
import WebKit

enum Import {
    static let kinds = "It takes a folder, an .html file or a .something file."

    /// What was read, before anything was placed.
    struct Incoming {
        var received: Received
        /// Whether it came as an export of something, and the links of a folder, which never come in.
        var exported = false, left: [String] = []
    }

    /// What the sheet says, all of it from the copy read and checked.
    struct Found {
        var file: String, title: String
        /// "22 KB", or "4 files" for a folder.
        var weight: String
        /// What went wrong, each said once, what the check only warns of, and the addresses it kept out.
        var problems: [String] = [], warnings = 0, blocked: [String] = []
        /// The contract of an export of something; nil for anything else.
        var contract: Int?
        var left: [String] = [], memory = 0
        /// Whether the page painted: only then can it be said what it tried.
        var loaded = true
        /// What the page's rights use, and the sentence, pre-set at None; both nil when it asks nothing of your agents.
        var needs: Grant.Level?, question: RightsQuestion?
    }

    /// Whether something imports what is at `url`: a folder or a file of the kinds it reads.
    static func takes(_ url: URL) -> Bool { dropped(url) || url.pathExtension.lowercased() == "json" }

    /// Whether a drag over a page is the app's: the JSON of an old export goes on to the page.
    static func dropped(_ url: URL) -> Bool {
        ["html", "htm", "something"].contains(url.pathExtension.lowercased()) || isFolder(url)
    }

    private static func isFolder(_ url: URL) -> Bool {
        var folder: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &folder) && folder.boolValue
    }

    /// What is at `url`, read whole. Throws a `CodedError`, as `Export.read` does, past its limits or when it is no
    /// space, and a `SpaceError` with `kinds` for what it does not take.
    static func incoming(at url: URL) throws -> Incoming {
        if isFolder(url) { return try folder(url) }
        guard takes(url) else { throw SpaceError(kinds) }
        // Mapped, not loaded: a huge file is refused for its size without being read.
        let file: Data
        do { file = try Data(contentsOf: url, options: .alwaysMapped) } catch { throw SpaceError("It cannot be read: \(error.localizedDescription)") }
        let page = ["html", "htm"].contains(url.pathExtension.lowercased())
        if !page { return Incoming(received: try Export.read(file), exported: true) }
        if let document = Export.unwrap(file) { return Incoming(received: try Export.read(document), exported: true) }
        guard file.count <= Export.limit else { throw tooBig(file.count) }
        let name = slug(url.deletingPathExtension().lastPathComponent)
        return Incoming(received: Received(name: name, form: .file, files: ["\(name).html": Data(file)], data: nil))
    }

    /// A folder with an index.html, its regular files as an export takes them: links and hidden files stay out.
    /// Measured first: a folder dropped by mistake is never read into memory.
    private static func folder(_ url: URL) throws -> Incoming {
        guard let space = Spaces(root: url).locate(url.path) else { throw SpaceError("This folder has no index.html. \(kinds)") }
        let size = space.size()
        guard size.files <= Export.most else { throw CodedError("IMPORT_TOO_BIG", "This folder has \(size.files) files; an import takes at most \(Export.most).") }
        // A third heavier in base64, as a document is measured.
        guard size.bytes / 3 * 4 <= Export.limit else { throw tooBig(size.bytes) }
        let files = try space.files().map { file -> (String, Data) in
            do { return (file.path, try Data(contentsOf: file.url)) } catch { throw SpaceError("\(file.path) cannot be read: \(error.localizedDescription)") }
        }
        guard files.contains(where: { $0.0 == "index.html" }) else {
            throw SpaceError(Versions.isLink(space.page) ? "The index.html of this folder is a link to somewhere else." : "This folder has no index.html. \(kinds)")
        }
        let name = slug(url.lastPathComponent)
        return Incoming(received: Received(name: name, form: .folder, files: Dictionary(uniqueKeysWithValues: files), data: nil), left: Library.links(space))
    }

    private static func tooBig(_ bytes: Int) -> CodedError {
        CodedError("IMPORT_TOO_BIG", "This weighs \(Size.words(bytes)); an import takes at most about 15 MB of files.")
    }

    /// A valid name for `words`: a file called "My Page" must not reach the scheme, which takes only names.
    static func slug(_ words: String) -> String {
        let plain = words.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        let parts = plain.unicodeScalars.map { Spaces.isName(String($0)) ? Character($0) : "-" }
        let name = String(String(parts).split(separator: "-").joined(separator: "-").prefix(100))
        return name.isEmpty ? "imported" : name
    }

    /// Writes a copy of `incoming` under `root`, without its memory, which no check may see, and returns it. A page
    /// that declares nothing would land as "not a space yet": the copy, and so what comes in, gains a minimal block.
    /// Throws as `Export.place` does.
    static func stage(_ incoming: inout Incoming, in root: URL, home: URL) throws -> Space {
        let received = incoming.received
        let space = try Export.place(Received(name: received.name, form: received.form, files: received.files, data: nil), as: received.name, in: Spaces(root: root), memory: root)
        let reading = Declaration.read(space, home: home, kinds: Registry.app.kinds)
        guard reading.problems.contains(where: { $0.code == "DECLARATION_MISSING" }), let page = try? Data(contentsOf: space.page) else { return space }
        let declared = declaring(page, name: received.name)
        try declared.write(to: space.page)
        var files = received.files
        files[space.form == .file ? "\(received.name).html" : "index.html"] = declared
        incoming.received = Received(name: received.name, form: received.form, files: files, data: received.data)
        return space
    }

    /// `page` with a declaration where an export puts its block, holding its `<title>` or the words of `name`. Found
    /// by bytes: a page may be in any encoding, and all it holds stays as it is.
    static func declaring(_ page: Data, name: String) -> Data {
        let object: [String: Any] = ["contract": Declaration.known, "title": title(of: page) ?? words(name)]
        // Nothing in JSON but a string holds a "<", so no title can end the script.
        let json = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            .map { String(decoding: $0, as: UTF8.self).replacingOccurrences(of: "<", with: "\\u003c") } ?? "{\"contract\": 1}"
        let block = Data("<script type=\"application/json\" id=\"something\">\(json)</script>".utf8), at = Export.opening(of: page)
        return Data(page[..<at]) + block + Data(page[at...])
    }

    private static func title(of page: Data) -> String? {
        let text = String(decoding: page, as: UTF8.self)
        guard let open = text.range(of: "<title[^>]*>", options: [.regularExpression, .caseInsensitive]),
              let close = text.range(of: "</title", options: .caseInsensitive, range: open.upperBound..<text.endIndex) else { return nil }
        let title = text[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : String(title.prefix(80))
    }

    /// "Garden plan" for garden-plan.
    private static func words(_ name: String) -> String {
        let spaced = name.replacingOccurrences(of: "-", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    /// The address a RESOURCE_BLOCKED problem names, when it has a host: code from a string or a `file:` load has none.
    private static func host(_ problem: Problem) -> String? {
        guard problem.code == "RESOURCE_BLOCKED" else { return nil }
        return problem.message.split(separator: " ").first.flatMap { URL(string: String($0))?.host }
    }

    /// `problem` in the app's words, one sentence per code. Never its message: a script's error is the page's own text,
    /// and no page writes in a sheet.
    static func said(_ problem: Problem) -> String {
        if host(problem) != nil { return "A part comes from the Internet, so it stays empty." }
        switch problem.code {
        case "RESOURCE_BLOCKED": return problem.message.hasPrefix("The page ran code") ? "It runs code from a string, which a space cannot do." : "A part comes from outside it, so it stays empty."
        case "SCRIPT_ERROR", "PROMISE_REJECTED", "CONSOLE_ERROR": return "A script on the page fails, so part of it may not work."
        case "LOAD_TIMEOUT": return "The page did not finish loading in time."
        case "LOAD_FAILED", "PAGE_CRASHED": return "The page could not be shown."
        default: return Codes.all[problem.code]?.when ?? "The check found a problem."
        }
    }

    /// What a `report` of the copy `space` says, for the sheet; `question` is the sentence, when the page needs one.
    static func found(_ report: Report, in space: Space, file: String, incoming: Incoming, question: RightsQuestion?) -> Found {
        let serious = report.problems.filter { $0.level == .fatal || $0.level == .error || $0.code == "RESOURCE_BLOCKED" }
        var said: [String] = []
        for problem in serious where !said.contains(Import.said(problem)) { said.append(Import.said(problem)) }
        let weight = space.form == .folder ? "\(report.size?.files ?? 0) file\(report.size?.files == 1 ? "" : "s")" : Size.words(report.size?.bytes ?? 0)
        // A title is the page's claim: one line, of a length the sheet can hold.
        let title = (report.declaration?.title ?? words(space.name)).split(whereSeparator: \.isNewline).joined(separator: " ")
        return Found(file: file, title: String(title.prefix(80)), weight: weight, problems: said,
                     warnings: report.problems.filter { $0.level == .warning }.count - serious.filter { $0.level == .warning }.count,
                     blocked: Array(Set(report.problems.compactMap(host))).sorted(), contract: incoming.exported ? report.declaration?.contract ?? Declaration.known : nil,
                     left: incoming.left, memory: incoming.received.data?.count ?? 0, loaded: report.snapshot != nil,
                     needs: question == nil ? nil : report.declaration.map { Grant.Level.needed(by: $0.rights) }, question: question)
    }
}

extension Library {
    /// Asks for what to import, then imports it.
    func importChosen() {
        if let url = ask.importFile() { importing([url]) }
    }

    /// Imports each of `urls`, after any import under way: its sheets take the window one at a time.
    func importing(_ urls: [URL]) {
        let before = arriving
        arriving = Task { @MainActor in
            await before?.value
            for url in urls { await bring(url) }
        }
    }

    /// Reads, stages and checks what is at `url`, says what it found, and on Import makes it a new space under a free
    /// name, with the level the sentence says, then opens it. What the grants file kept for that name is dropped first,
    /// so a grants file that cannot be changed leaves no space. Says what failed.
    @MainActor private func bring(_ url: URL) async {
        let file = url.lastPathComponent, runner = checker(places, share), stage = runner.output.appendingPathComponent("import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: stage) }
        do {
            var incoming = try Import.incoming(at: url)
            let staged = try Import.stage(&incoming, in: stage, home: places.home)
            var checked: Result<Report, Error>?
            guard await ask.checking(file, while: { checked = await Result { try await runner.run(Check(space: staged.location.path, stage: true)) } }), let report = try checked?.get() else { return }
            let found = Import.found(report, in: staged, file: file, incoming: incoming, question: question(report.declaration, of: staged))
            guard let choice = await ask.found(found) else { return }
            let spaces = Spaces(root: places.spaces)
            let name = try Export.freeName(incoming.received, in: spaces, memory: places.data)
            try Library.forget(name, in: places, recycle: recycle)
            try FileManager.default.createDirectory(at: places.spaces, withIntermediateDirectories: true)
            let space = try Export.place(incoming.received, as: name, in: spaces, memory: places.data)
            if let declaration = report.declaration { grant(choice, to: space.name, declaration) }
            ring(space.name)
            imported(found.title)
        } catch {
            ask.tell("something can’t import \(file). \(error.sentence)")
        }
    }

    /// The sentence's question for a page that asks something of your agents; nil for one that does not.
    private func question(_ declaration: Declaration?, of space: Space) -> RightsQuestion? {
        guard let declaration, Grant.Level.needed(by: declaration.rights) != .none else { return nil }
        let reading = Declaration.read(space, home: places.home, kinds: Registry.app.kinds), agents = seen()
        return RightsQuestion(space: declaration.title, level: .none, folder: Levels.onThisMac(declaration.folder, home: places.home),
                              folders: Levels.folders(agents), scope: Rights.granted(reading, nil, limits: [:], home: places.home).agents, name: space.name,
                              agents: agents, kinds: declaration.rights.filter { $0.hasPrefix("launch:") }.map { String($0.dropFirst("launch:".count)) })
    }

    /// Keeps the sentence as `name`'s grant, so that the first opening asks nothing. A failure is said, and the page
    /// then asks at its opening: it has no right until a grant says so.
    private func grant(_ choice: LevelChoice, to name: String, _ declaration: Declaration) {
        let folder = choice.folder == .blank ? places.blank(name) : choice.folder.path
        do {
            try Grants(places.grants).update {
                $0.spaces[name] = Rights.leveled(choice.level, folder: folder, declaration: declaration, at: iso8601.string(from: Date()), after: nil, start: choice.start, scope: choice.scope)
            }
        } catch { ask.tell(error.sentence) }
    }
}

extension Result where Failure == Error {
    /// `Result(catching:)` for work that waits.
    init(_ work: () async throws -> Success) async {
        do { self = .success(try await work()) } catch { self = .failure(error) }
    }
}

extension Ask {
    /// The sheet while a file is checked: only Cancel. The work takes it away.
    static func checking(_ file: String) -> Sheet {
        Sheet(icon: .eyes(.think), title: "Checking \(file)…", body: [("In a view locked off the network. Nothing opens yet.", false)],
              actions: [.init(title: "Cancel", role: .cancel)])
    }

    /// How wide the sheet of what was found is, as the mockup's.
    static let foundWidth: CGFloat = 470

    /// The sheet of what the check found, not yet shown, and the sentence's answer once it closed with Import: what it
    /// is, each thing found, the sentence at None when the page asks for your agents, then Cancel and Import. All of it
    /// says what was read, so an import shows what comes in. Import holds the focus, unless Run still needs its folder.
    static func found(_ found: Import.Found, home: String = NSHomeDirectory()) -> (sheet: Sheet, answer: () -> LevelChoice) {
        let text = Sheet.column(width: foundWidth), bad = found.problems.count
        let place = NSMutableAttributedString(string: found.file, attributes: [.font: Look.font(.code, size: 11.5), .foregroundColor: Look.Token.ink2.color])
        place.append(NSAttributedString(string: " · \(found.weight) · checked, locked off the network", attributes: [.font: Look.medium.font, .foregroundColor: Look.Token.ink2.color]))
        let lead = NSTextField(labelWithAttributedString: place)
        (lead.maximumNumberOfLines, lead.preferredMaxLayoutWidth) = (0, text)
        var rows: [Sheet.Row] = found.problems.prefix(3).map { .init(mark: .symbol("exclamationmark.triangle"), label: [($0, false)], meta: nil, bad: true) }
        if bad > 3 { rows.append(.init(mark: .symbol("ellipsis"), label: [("And \(bad - 3) more", false)], meta: nil)) }
        if let contract = found.contract { rows.append(.init(mark: .symbol("square.3.layers.3d"), label: [("An export from something", false)], meta: "contract \(contract)")) }
        if bad == 0 { rows.append(.init(mark: .symbol("checkmark"), label: [("No errors", false)], meta: "\(found.warnings) warning\(found.warnings == 1 ? "" : "s")")) }
        // An export says so only when it tried: its page was checked here all the same.
        if found.contract == nil || !found.blocked.isEmpty {
            let meta = found.blocked.isEmpty ? found.loaded ? "nothing to block" : "not loaded" : found.blocked.count == 1 ? "\(found.blocked[0]) is blocked" : "\(found.blocked.count) addresses are blocked"
            rows.append(.init(mark: .symbol("lock"), label: [("It stays off the network", false)], meta: meta))
        }
        if !found.left.isEmpty { rows.append(.init(mark: .symbol("link"), label: [("Links stay out", false)], meta: found.left.count == 1 ? found.left[0] : "\(found.left.count) links")) }
        rows.append(found.memory == 0 ? .init(mark: .symbol("note.text"), label: [("No memory yet", false)], meta: nil)
                    : .init(mark: .symbol("note.text"), label: [("Its memory inside", false)], meta: "\(found.memory) entr\(found.memory == 1 ? "y" : "ies")"))
        if let needs = found.needs { rows.append(.init(mark: .symbol("eye"), label: [("It asks to \(needs.word) your agents", false)], meta: nil)) }
        let choice = found.question.map { choosing($0, home: home, width: text) }
        let sheet = Sheet(icon: .symbol("checkmark.shield"), title: bad == 0 ? "\(found.title) is ready to import" : "\(found.title) has \(bad) problem\(bad == 1 ? "" : "s")",
                          lead: lead, rows: rows, block: choice?.view,
                          fine: (bad == 0 ? "It comes in as a copy." : "You can import it and ask its assistant to fix this.") + " The original file doesn’t change.",
                          actions: [.init(title: "Cancel", role: .cancel), .init(title: "Import", role: .primary, hint: "↵")], width: foundWidth)
        choice?.follow(sheet, sheet.buttons[1])
        // None gives nothing, and a level is the person's own pick: Return imports, as the mockup's focus says.
        sheet.makeFirstResponder(sheet.buttons[1])
        return (sheet, { choice?.chosen() ?? LevelChoice() })
    }
}

/// What a file dragged over the window does: which drags are the app's, the veil while one is over it, and the drop.
final class Drops {
    /// Shows or takes away the veil.
    var veiled: (Bool) -> Void = { _ in }
    /// Told the files dropped.
    var dropped: ([URL]) -> Void = { _ in }

    static func files(_ drag: NSDraggingInfo) -> [URL] {
        drag.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    /// Whether a drag over a page is the app's: all of it is what import takes. Anything else, a picture, a .txt, a mix,
    /// is the page's, to leave to its own drop zones.
    static func overPage(_ drag: NSDraggingInfo) -> Bool {
        // A drag begun in this app is a page's own, whatever it says it holds; one from Finder has no source here.
        let files = files(drag)
        return drag.draggingSource == nil && !files.isEmpty && files.allSatisfy(Import.dropped)
    }

    func over(_ on: Bool) -> NSDragOperation {
        veiled(on)
        return on ? .copy : []
    }

    func drop(_ drag: NSDraggingInfo) -> Bool {
        veiled(false)
        dropped(Drops.files(drag))
        return true
    }
}

/// The center of the window: where a page is not, any file dragged here is offered to import, which says what it takes.
/// A page's web view is deeper, so it answers first, over its own area.
final class DropCenter: NSView {
    var drops: Drops?

    init() {
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    private func offers(_ drag: NSDraggingInfo) -> NSDragOperation { drops?.over(!Drops.files(drag).isEmpty) ?? [] }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { offers(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { offers(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { drops?.veiled(false) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { drops?.drop(sender) ?? false }
}

/// A space's web view with the window's filter on its dragging: a drag that is the app's stops here and WebKit never hears
/// of it; every other goes on to WebKit, and to the page's own drop zones. `drops` is set only for the window's page.
final class SpaceWeb: WKWebView {
    var drops: Drops?

    private func ours(_ drag: NSDraggingInfo?) -> Drops? { drag.flatMap { drag in drops.flatMap { Drops.overPage(drag) ? $0 : nil } } }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { ours(sender)?.over(true) ?? super.draggingEntered(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { ours(sender)?.over(true) ?? super.draggingUpdated(sender) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { ours(sender) != nil || super.prepareForDragOperation(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { ours(sender)?.drop(sender) ?? super.performDragOperation(sender) }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if let ours = ours(sender) { ours.veiled(false) } else { super.draggingExited(sender) }
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        if ours(sender) == nil { super.concludeDragOperation(sender) }
    }
}

/// The veil over the window while a file is dragged over it: the mark, "Drop to Import", and that it is checked first.
/// It takes no event, and is drawn in draw(_:), so that a picture shows it.
final class DropVeil: NSView {
    static let inset: CGFloat = 10, radius: CGFloat = 12

    private init() {
        super.init(frame: .zero)
        let mark = NSImageView.symbol("square.and.arrow.down", 22, .regular, tint: .ink)
        let title = Sheet.label([("Drop to Import", false)], Look.titleS, width: 300, centred: true)
        let note = Sheet.label([("It’s checked before it opens.", false)], Look.Style(face: .ui, size: 12.5, weight: .regular, leading: 1.4), color: .ink2, width: 300, centred: true)
        let words = NSStackView(views: [mark, title, note])
        (words.orientation, words.alignment, words.spacing) = (.vertical, .centerX, 4)
        words.setCustomSpacing(8, after: mark)
        words.translatesAutoresizingMaskIntoConstraints = false
        addSubview(words)
        NSLayoutConstraint.activate([words.centerXAnchor.constraint(equalTo: centerXAnchor), words.centerYAnchor.constraint(equalTo: centerYAnchor)])
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    /// Shows the veil in `layer`, or takes it away.
    static func set(_ on: Bool, in layer: WindowLayer) {
        let shown = layer.subviews.first { $0 is DropVeil }
        guard on != (shown != nil) else { return }
        guard on else { return shown?.removeFromSuperview() ?? () }
        let veil = DropVeil()
        veil.frame = layer.bounds.insetBy(dx: inset, dy: inset)
        veil.autoresizingMask = [.width, .height]
        layer.hold(veil)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: Self.radius, yRadius: Self.radius)
        // Thicker than the mockup's 62 % with its blur: nothing here blurs a web view under it.
        Look.Token.bg.color.withAlphaComponent(0.9).setFill()
        shape.fill()
        Look.Token.ink2.color.setStroke()
        shape.lineWidth = 2
        shape.stroke()
    }
}
