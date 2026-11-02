// Help, from this Mac only (rule 5): something Help and its promise are the README, the guide for coding agents is
// share/guide.md, both put in the .app by make-app.sh and shown read-only in one window. The Markdown is drawn here,
// a line at a time, rather than handed to a browser or an editor; its links stay words, since a click on one would
// reach the Internet.
import AppKit

@MainActor extension App {
    @objc func openHelp(_ sender: Any?) { Help.show("help") }
    @objc func showPromise(_ sender: Any?) { Help.show("promise") }
    @objc func showGuide(_ sender: Any?) { Help.show("guide") }
}

@MainActor
enum Help {
    /// What a Help item shows: its window title, a bundled file, and the heading it opens at (nil: the top).
    struct Page: Equatable {
        let title: String, file: URL, heading: String?
    }

    /// The page of the Help item `id` ("help", "promise" or "guide"), nil for any other id. The README sits beside
    /// `share`: in the .app's Resources, or at the clone's root.
    static func page(_ id: String, share: URL = Resources.share) -> Page? {
        let readme = share.deletingLastPathComponent().appendingPathComponent("README.md")
        let title = Keys.command(id)?.title ?? ""
        switch id {
        case "help": return Page(title: title, file: readme, heading: nil)
        case "promise": return Page(title: title, file: readme, heading: "The promise")
        case "guide": return Page(title: title, file: share.appendingPathComponent("guide.md"), heading: nil)
        default: return nil
        }
    }

    private static var window: NSWindow?

    /// Shows the page of `id` in the Help window, made once and kept; nothing when its file cannot be read.
    static func show(_ id: String) {
        guard let page = page(id), let made = window(page, reusing: window) else { return NSSound.beep() }
        window = made
        made.makeKeyAndOrderFront(nil)
    }

    /// `reusing`, or a new window, showing `page` read-only and scrolled to its heading. nil when its file cannot be
    /// read: a broken install, which a window with nothing in it would hide.
    static func window(_ page: Page, reusing: NSWindow? = nil) -> NSWindow? {
        guard let markdown = try? String(contentsOf: page.file, encoding: .utf8) else { return nil }
        let window = reusing ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 720),
                                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        if reusing == nil {
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 420, height: 320)
            let scroll = NSTextView.scrollableTextView()
            let view = scroll.documentView as? NSTextView
            view?.isEditable = false
            view?.textContainerInset = NSSize(width: 32, height: 28)
            view?.backgroundColor = Look.Token.bg.color
            window.contentView = scroll
            window.center()
        }
        window.title = page.title
        guard let view = (window.contentView as? NSScrollView)?.documentView as? NSTextView,
              let layout = view.layoutManager, let container = view.textContainer else { return window }
        let (text, headings) = Help.text(markdown)
        view.textStorage?.setAttributedString(text)
        layout.ensureLayout(for: container)
        // A heading opens a little below the top, the text before it out of sight.
        let at = page.heading.flatMap { headings[$0] }.map { layout.boundingRect(forGlyphRange: NSRange(location: $0, length: 1), in: container).minY }
        view.scroll(NSPoint(x: 0, y: at.map { $0 + view.textContainerOrigin.y - 18 } ?? 0))
        return window
    }

    /// One block of the file: a heading of a level, a paragraph, a list item, or lines kept as they are (code, tables).
    private enum Block { case heading(Int), paragraph, item(String), kept }

    /// `markdown` drawn for reading, and where each heading starts in it. A block's wrapped lines are joined; code
    /// and tables keep theirs in the code face. Links keep their words only: nothing in the window opens an address.
    static func text(_ markdown: String) -> (NSAttributedString, headings: [String: Int]) {
        var blocks: [(Block, String)] = [], fenced = false, open = false
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { fenced.toggle(); open = false; continue }
            if fenced || trimmed.hasPrefix("|") {
                if trimmed.hasPrefix("|-") || trimmed.hasPrefix("| -") || trimmed.hasPrefix("|:") { continue }
                if open, case .kept = blocks[blocks.count - 1].0 { blocks[blocks.count - 1].1 += "\n" + line } else { blocks.append((.kept, line)) }
                open = true
            } else if trimmed.isEmpty || trimmed.hasPrefix("<") {
                open = false
            } else if let level = trimmed.firstIndex(where: { $0 != "#" }).map({ trimmed.distance(from: trimmed.startIndex, to: $0) }),
                      level > 0, trimmed.dropFirst(level).first == " " {
                blocks.append((.heading(level), String(trimmed.dropFirst(level + 1))))
                open = false
            } else if let marker = trimmed.split(separator: " ", maxSplits: 1).first,
                      marker == "-" || marker == "*" || (marker.hasSuffix(".") && marker.dropLast().allSatisfy(\.isNumber) && marker.count > 1) {
                blocks.append((.item(marker.count == 1 ? "•" : String(marker)), String(trimmed.dropFirst(marker.count + 1))))
                open = true
            } else if open, case .kept = blocks[blocks.count - 1].0 {
                blocks.append((.paragraph, trimmed))
            } else if open {
                blocks[blocks.count - 1].1 += " " + trimmed
            } else {
                blocks.append((.paragraph, trimmed))
                open = true
            }
        }
        let text = NSMutableAttributedString(), ink = Look.Token.ink.color
        var headings: [String: Int] = [:]
        for (index, (block, words)) in blocks.enumerated() {
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = 1.2
            style.paragraphSpacing = 10
            let start = text.length
            switch block {
            case .heading(let level):
                headings[words] = start
                style.paragraphSpacingBefore = level == 1 ? 0 : 14
                let font = (level == 1 ? Look.titleL : level == 2 ? Look.titleM : Look.titleS).font
                text.append(NSAttributedString(string: words, attributes: [.font: font, .foregroundColor: ink]))
            case .kept:
                text.append(NSAttributedString(string: words, attributes: [.font: Look.font(.code, size: 11.5),
                                                                           .foregroundColor: Look.Token.ink2.color]))
            case .item, .paragraph:
                if case .item(let marker) = block {
                    style.headIndent = 16
                    style.tabStops = [NSTextTab(textAlignment: .left, location: 16)]
                    if index + 1 < blocks.count, case .item = blocks[index + 1].0 { style.paragraphSpacing = 4 }
                    text.append(NSAttributedString(string: marker + "\t", attributes: [.font: Look.body.font, .foregroundColor: ink]))
                }
                text.append(inline(words))
            }
            text.append(NSAttributedString(string: "\n"))
            text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: start, length: text.length - start))
        }
        return (text, headings)
    }

    /// One block's words with their bold, italics and code, and no link.
    private static func inline(_ words: String) -> NSAttributedString {
        let parsed = (try? AttributedString(markdown: words, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(words)
        let text = NSMutableAttributedString()
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            var font = Look.font(.ui, size: Look.body.size, weight: intent.contains(.stronglyEmphasized) ? .semibold : .regular)
            if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            if intent.contains(.code) { font = Look.font(.code, size: 12) }
            text.append(NSAttributedString(string: String(parsed[run.range].characters),
                                           attributes: [.font: font, .foregroundColor: Look.Token.ink.color]))
        }
        return text
    }
}
