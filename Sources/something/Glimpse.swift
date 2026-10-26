// Hold to compare: while the person holds a version in History, or Space, that version shows over the open page at the
// same scroll, cross-faded, with a label that says which one and to let go; released, the page is what it is now. The
// version is written out of the store into a copy in the store's own folder (Application Support/something/versions/
// <space>/glimpse/), never in the spaces folder, so the library never lists it and no agent edits it; History removes
// it when it closes. The copy shows in a second locked web view, a SpaceView like the open one (the same scheme, rules
// and guards) that is read-only: it answers the state as the open space's and refuses every write before the core
// (SpaceBridge.swift), so the space's journal gets no line from it. Only the page's files are versions: the old page
// shows today's state, never that day's. A web view weighs about 45 MB, so it is let go at each release.
import AppKit
import SomethingCore

final class Glimpse {
    /// What lies over the page while a version is held: its web view and the label. No click reaches it: the person's
    /// hand is on History.
    final class Cover: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    let version: Versions.Version
    let cover = Cover()
    /// The older version's read-only view; nil once released.
    private(set) var view: SpaceView?
    /// Whether it shows: it fades in once its page loaded and scrolled.
    private(set) var shown = false

    /// The folder of the copies of `name`'s versions, in the store, outside the spaces folder.
    static func folder(_ store: Versions, _ name: String) -> URL { store.folder(name).appendingPathComponent(Versions.glimpse, isDirectory: true) }

    /// Removes the copy of `name`'s held version, when there is one.
    static func remove(_ store: Versions, _ name: String) { try? FileManager.default.removeItem(at: folder(store, name)) }

    /// Writes `version` of `open`'s space out of `store` and shows it over the page, labelled with its `words` and
    /// `when`. Throws a `SpaceError` when the version is no longer kept or complete, has no page, or cannot be written.
    init(_ version: Versions.Version, over open: SpaceView, store: Versions, words: String, when: String) throws {
        let name = open.space.name, (_, contents) = try store.read(version.id, of: name), root = Glimpse.folder(store, name)
        Glimpse.remove(store, name)
        // A single page is a file named after the space; anything else, a folder around its index.html.
        let page = contents.count == 1 && contents["index.html"] == nil
        do {
            for (path, data) in contents {
                let url = page ? root.appendingPathComponent("\(name).html") : root.appendingPathComponent(name).appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url)
            }
        } catch {
            throw SpaceError("This version of \(name) could not be shown: \(error.localizedDescription)")
        }
        guard let copy = Spaces(root: root).named(name) else { throw SpaceError("This version of \(name) has no page to show.") }
        self.version = version
        let view = SpaceView(glimpse: copy, of: open), label = Glimpse.label(words, when)
        self.view = view
        view.web.frame = cover.bounds
        view.web.autoresizingMask = [.width, .height]
        cover.addSubview(view.web)
        cover.addSubview(label)
        NSLayoutConstraint.activate([label.topAnchor.constraint(equalTo: cover.topAnchor, constant: 14),
                                     label.centerXAnchor.constraint(equalTo: cover.centerXAnchor)])
        cover.alphaValue = 0
        open.glimpse(cover)
        view.load()
        view.loaded = { [weak self] in self?.show() }
        // A page its declaration keeps from showing has nothing to wait for.
        if !view.blocked.isEmpty { show() }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "\(words), \(when). Release to see now.", .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private func show() {
        guard !shown, view != nil else { return }
        shown = true
        Look.animate(0.4, Look.douce) { [cover] in cover.moving.alphaValue = 1 }
    }

    /// Lets the version go: the page as it is now fades back, and the older page's web view is released.
    func release() {
        guard let view else { return }
        (self.view, shown) = (nil, false)
        view.close()
        Look.animate(0.4, Look.douce, { [cover] in cover.moving.alphaValue = 0 }, done: { [cover] in cover.removeFromSuperview() })
    }

    /// The label at the top of the space: which version shows, when it was made, and that letting go shows now.
    static func label(_ words: String, _ when: String) -> NSView {
        let fg = Look.Token.actfg.color, font = Look.font(.ui, size: 12.5, weight: .medium)
        func text(_ string: String, _ alpha: CGFloat) -> NSTextField {
            let field = NSTextField(labelWithString: string)
            (field.font, field.textColor, field.lineBreakMode) = (font, fg.withAlphaComponent(alpha), .byTruncatingTail)
            return field
        }
        let title = text(words, 1)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let icon = NSImageView.symbol("rectangle.split.2x1", 11, .medium, tint: .actfg)
        // The words say it all; the picture is not read.
        icon.image?.accessibilityDescription = ""
        let row = NSStackView(views: [icon, title, text(when, 0.65), Dot(), text("Release to see now", 0.65)])
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 14)
        let pill = Pill()
        pill.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(row)
        NSLayoutConstraint.activate([pill.heightAnchor.constraint(equalToConstant: 34), row.leadingAnchor.constraint(equalTo: pill.leadingAnchor),
                                     row.trailingAnchor.constraint(equalTo: pill.trailingAnchor), row.centerYAnchor.constraint(equalTo: pill.centerYAnchor)])
        return pill
    }

    /// The label's ground, drawn rather than layered so that it follows day and night.
    private final class Pill: NSView {
        override func draw(_ dirtyRect: NSRect) {
            Look.Token.act.color.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        }
    }

    /// The dot between when and Release to see now.
    private final class Dot: NSView {
        override var intrinsicContentSize: NSSize { NSSize(width: 3, height: 3) }
        override func draw(_ dirtyRect: NSRect) {
            Look.Token.actfg.color.withAlphaComponent(0.45).setFill()
            NSBezierPath(ovalIn: bounds).fill()
        }
    }
}
