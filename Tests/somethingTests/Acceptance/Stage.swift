// The acceptance stage: the one invented world every screen scenario starts from, and the drawing that turns a
// window into a picture. The home holds the six templates as the mockup names them and Oracle (an invented page of
// Tests/Fixtures). Each scenario builds its own Stage, rather than one per area suite, so no scenario sees what another
// left; each suite is serialized, and the suites, which run side by side, take turns to draw. Nothing is shown: the
// app is .prohibited, and each window is drawn offscreen (drawing a view needs no permission of macOS, a screenshot
// would need Screen Recording). Pictures are written only when SOMETHING_GALLERY names a folder.
import AppKit
import SwiftUI
@testable import SomethingAgents
import SomethingCore
import Testing
import WebKit
@testable import something

let gallery = ProcessInfo.processInfo.environment["SOMETHING_GALLERY"].map { URL(fileURLWithPath: $0) }

@MainActor
final class Stage {
    /// The spaces made from share/templates: file name and title as the mockup shows them.
    static let templates = [("brief", "Daily brief"), ("agents", "My agents"), ("project", "Project watch"),
                            ("logbook", "Logbook"), ("pet", "Pebble"), ("stack", "Stack")]
    /// The sidebar's groups in the mockup, by space name (groups are a view: the spaces stay flat on disk). W2, which
    /// builds the groups, is the first to read them.
    static let groups = [("Agents", ["brief", "agents", "project"]), ("Notes", ["logbook", "oracle"]), ("Breaks", ["pet", "stack"])]
    /// The mockup's moment: Thursday 22 October 2026, 18:20, in UTC (`zone`), fixed so it cannot fall back to the real
    /// time. Nothing reads it yet: the app has no clock seam, and the slice that adds one (the first to show a date)
    /// passes `now` and `zone` to it, so no picture depends on the calendar or on this Mac's time zone.
    static let now = Date(timeIntervalSince1970: 1_792_693_200)
    static let zone = TimeZone(secondsFromGMT: 0)
    static let oracle = Home.share.deletingLastPathComponent().appendingPathComponent("Tests/Fixtures/spaces/oracle.html")

    /// The window sizes the mockup is shot at, in points; a slice adds the other sizes when it draws at them.
    enum Size {
        static let main = NSSize(width: 1200, height: 760)
    }

    let home: Home

    /// A home named `something-accept-<area>-…` in $TMPDIR, with every space written; `remove()` deletes it.
    init(_ area: String) throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        home = Home(prefix: "something-accept-\(area)-")
        try Library.prepare(home.places)
        for (name, _) in Stage.templates {
            try home.space(name, try String(contentsOf: Home.share.appendingPathComponent("templates/\(name).html"), encoding: .utf8))
        }
        try home.space("oracle", try String(contentsOf: Stage.oracle, encoding: .utf8))
    }

    func remove() { home.remove() }

    /// The main window of the home, never shown, at `size`, its spaces listed.
    func window(_ size: NSSize = Size.main) -> (shell: Shell, library: Library, info: Info) {
        let ask = FakeAsk()
        let library = Library(places: home.places, ask: ask, share: Home.share), info = Info(places: home.places, ask: ask)
        library.relist()
        let shell = Shell(library: library, info: info, assistant: AssistantModel(engine: home.engine(), places: home.places), autosave: false)
        shell.window.setContentSize(size)
        return (shell, library, info)
    }

    /// Opens the space `name` in `shell`'s center, loaded, its animations ended; the caller closes it.
    func open(_ name: String, in shell: Shell, _ library: Library) async throws -> SpaceView {
        let view = try await home.window(try #require(library.entry(name)?.space))
        view.open()
        #expect(await wait(until: { !view.web.isLoading && view.frame != nil }), "\(name) did not load")
        library.select(.space(name))
        shell.show(view)
        shell.assistant.place = AssistantModel.place(view)
        await Picture.settle(view)
        return view
    }

    /// Whether a scenario is drawing its pictures now: NSApp's appearance is one for the whole process.
    private static var drawing = false

    /// Runs `body` in the light appearance, then, when pictures are drawn, in the dark one; `body` gets the picture's
    /// suffix ("" or "-dark") and asserts in both. The area suites run side by side on the main actor and meet at each
    /// await: one scenario draws at a time, or another's night would reach this one's day picture.
    func appearances(_ body: (String) async throws -> Void) async throws {
        _ = await wait(600, until: { !Stage.drawing })
        Stage.drawing = true
        defer { (Stage.drawing, NSApp.appearance) = (false, nil) }
        for dark in gallery == nil ? [false] : [false, true] {
            let name: NSAppearance.Name = dark ? .darkAqua : .aqua
            NSApp.appearance = NSAppearance(named: name)
            // The windows follow it later, on the run loop.
            _ = await wait(5, until: { NSApp.windows.allSatisfy { $0.appearance != nil || $0.effectiveAppearance.name == name } })
            try await body(dark ? "-dark" : "")
        }
    }
}

/// How a picture is drawn: the window's frame by cacheDisplay, the page by WebKit's snapshot (it draws in another
/// process, which a view's drawing does not reach), then the assistant that floats over the page. T2 adds the
/// request panel, drawn on a canvas that holds the window and the panel together.
/// The vibrant columns (sidebar, Info) are blended by the window server, which no drawing here reaches: the same
/// views are drawn apart on a plain background and composed in their place.
@MainActor
enum Picture {
    /// Draws the whole window of `shell`, title bar and toolbar included, into `name`.png at 2x; its lights gray when
    /// it lost the keys (`keyed` false).
    static func window(_ shell: Shell, library: Library, web: WKWebView?, _ name: String, root: URL, keyed: Bool = true) async throws {
        // Below the title bar, as the columns' own contents start.
        let top = shell.window.frame.height - shell.window.contentLayoutRect.maxY
        let inspector = try #require(shell.inspector.viewController as? NSHostingController<InspectorView>)
        let columns: [(item: NSSplitViewItem, view: NSView)] = [
            (shell.split.splitViewItems[0], NSHostingView(rootView: SidebarView(library: library, assistant: shell.assistant))),
            (shell.inspector, NSHostingView(rootView: inspector.rootView)),
        ].filter { !$0.0.isCollapsed }
        let offscreens = columns.map { column in
            let offscreen = Offscreen(column.view), bounds = column.item.viewController.view.bounds
            offscreen.window.setContentSize(NSSize(width: max(bounds.width, 232), height: max(bounds.height - top, 100)))
            return offscreen
        }
        // SwiftUI and WebKit draw on the run loop.
        await wait(1.5)
        let frame = try #require(shell.window.contentView?.superview)
        disguise(frame, root.path)
        frame.layoutSubtreeIfNeeded()
        let rep = try bitmap(frame.bounds.size)
        frame.cacheDisplay(in: frame.bounds, to: rep)
        let apart = try columns.map { column in
            disguise(column.view, root.path)
            let drawn = try bitmap(column.view.bounds.size)
            selected(column.view) { column.view.cacheDisplay(in: column.view.bounds, to: drawn) }
            var place = column.item.viewController.view.convert(column.item.viewController.view.bounds, to: frame)
            place.size.height -= top
            return (drawn, place)
        }
        let snapshot = web?.superview == nil ? nil : try await web?.takeSnapshot(configuration: nil)
        // What covers the page in its area (Stopped), then the assistant, float over the page, which was drawn over
        // them; the window layer (the toast) covers all.
        let covers = web?.superview?.subviews.filter { $0 !== web && !$0.isHidden } ?? []
        let floating = covers + (web == nil ? [] : [shell.floating].compactMap { $0 }.filter { !$0.isHidden }) + [shell.layer].filter { !$0.isHidden }
        let over = try floating.map { view in
            let drawn = try bitmap(view.bounds.size)
            view.cacheDisplay(in: view.bounds, to: drawn)
            return (drawn, view.convert(view.bounds, to: frame))
        }
        // A window never shown is never key, and draws its lights gray: the main window keeps the keys while the
        // request panel, which never takes them, stands in front, so its lights are drawn in their colors.
        let lights = keyed ? Self.lights(of: shell.window) : []
        try png(of: frame.bounds.size, name) {
            rep.draw(in: NSRect(origin: .zero, size: frame.bounds.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            for (drawn, place) in apart {
                NSColor.windowBackgroundColor.setFill()
                place.fill()
                drawn.draw(in: place, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            if let snapshot, let web { snapshot.draw(in: web.convert(web.bounds, to: frame)) }
            for (drawn, place) in over {
                drawn.draw(in: place, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            paint(lights)
        }
        withExtendedLifetime(offscreens) {}
    }

    /// The places of `window`'s lights in its frame view, 12 points each, with the colors a key window draws them in.
    static func lights(of window: NSWindow) -> [(NSRect, NSColor)] {
        let colors: [(NSWindow.ButtonType, UInt32)] = [(.closeButton, 0xFF5F57), (.miniaturizeButton, 0xFEBC2E), (.zoomButton, 0x28C840)]
        return colors.compactMap { type, rgb -> (NSRect, NSColor)? in
            guard let button = window.standardWindowButton(type), let frame = window.contentView?.superview else { return nil }
            let place = button.convert(button.bounds, to: frame)
            let color = NSColor(srgbRed: CGFloat(rgb >> 16) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
            return (NSRect(x: place.midX - 6, y: place.midY - 6, width: 12, height: 12), color)
        }
    }

    static func paint(_ lights: [(NSRect, NSColor)]) {
        for (place, color) in lights {
            color.setFill()
            NSBezierPath(ovalIn: place).fill()
            (color.shadow(withLevel: 0.12) ?? color).setStroke()
            NSBezierPath(ovalIn: place.insetBy(dx: 0.25, dy: 0.25)).stroke()
        }
    }

    /// Draws an alert's window as it would be shown, with the app's icon.
    static func alert(_ alert: NSAlert, _ name: String, root: URL) throws {
        alert.icon = NSApp.applicationIconImage
        alert.layout()
        try view(try #require(alert.window.contentView), name, root: root)
    }

    /// Draws `view`, laid out at its size (its fitting size when it has none), into `name`.png at 2x, on the window's
    /// background: an alert's content draws nothing behind its text when it is not on the screen.
    static func view(_ view: NSView, _ name: String, root: URL) throws {
        disguise(view, root.path)
        if view.frame.isEmpty { view.frame.size = view.fittingSize }
        view.layoutSubtreeIfNeeded()
        let rep = try bitmap(view.bounds.size)
        selected(view) { view.cacheDisplay(in: view.bounds, to: rep) }
        try png(of: view.bounds.size, name) {
            rep.draw(in: NSRect(origin: .zero, size: view.bounds.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    /// Ends the page's animations that end, as its first second on the screen would: a window never shown has no
    /// animation clock, and a tile that arrives from transparent would stay transparent in the picture.
    static func settle(_ view: SpaceView) async {
        guard let frame = view.frame else { return }
        _ = try? await view.web.evaluateJavaScript("document.getAnimations().forEach((one) => { try { one.finish(); } catch (error) {} }); 0",
                                                   in: frame, contentWorld: .page)
    }

    /// Runs `draw` with the selected rows of `view`'s lists in the color of a selection: a row's highlight is a view of
    /// the selection material, its layer black, and the window server colors it on the screen with a filter
    /// (vibrantColorMatrixSourceOver) that no drawing in this process applies: cacheDisplay, CALayer.render and
    /// CARenderer all give black. Meanwhile it is the gray of a selection whose list does not have the focus, as the
    /// sidebar's when the person works in the open space: a reconstruction, not the window server's own pixels.
    static func selected(_ view: NSView, _ draw: () -> Void) {
        func highlights(_ view: NSView) -> [CALayer] {
            let own = (view as? NSVisualEffectView)?.material == .selection ? view.layer?.sublayers ?? [] : []
            return own + view.subviews.flatMap(highlights)
        }
        let layers = highlights(view), before = layers.map(\.backgroundColor)
        (NSApp.appearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance {
            layers.forEach { $0.backgroundColor = NSColor.unemphasizedSelectedContentBackgroundColor.cgColor }
        }
        draw()
        zip(layers, before).forEach { $0.backgroundColor = $1 }
    }

    static func bitmap(_ size: NSSize) throws -> NSBitmapImageRep {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        return rep
    }

    /// Writes `name`.png in the gallery folder, `size` points at 2x: the window's background, then what `content`
    /// draws. Nothing is drawn when SOMETHING_GALLERY names no folder.
    static func png(of size: NSSize, _ name: String, _ content: () -> Void) throws {
        guard let gallery else { return }
        try FileManager.default.createDirectory(at: gallery, withIntermediateDirectories: true)
        let rep = try bitmap(size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // NSApp.effectiveAppearance follows a change of NSApp.appearance only later, on the run loop.
        (NSApp.appearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: size).fill()
            content()
        }
        NSGraphicsContext.restoreGraphicsState()
        try #require(rep.representation(using: .png, properties: [:])).write(to: gallery.appendingPathComponent("\(name).png"))
    }

    /// Shows the temporary home as /Users/example: the pictures say what a person would read.
    static func disguise(_ view: NSView, _ root: String) {
        // Only what names the home is set again: setting a text view's string scrolls it to its end.
        if let field = view as? NSTextField, field.stringValue.contains(root) {
            field.stringValue = field.stringValue.replacingOccurrences(of: root, with: "/Users/example")
        }
        if let text = view as? NSTextView, text.string.contains(root) { text.string = text.string.replacingOccurrences(of: root, with: "/Users/example") }
        view.subviews.forEach { disguise($0, root) }
    }
}
