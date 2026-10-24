// Block 3's spikes SP9, SP10, SP11 and SP12: the smallest prototypes that answer what block 3 stands on. Each answer is
// written in the commit that adds this file, with the numbers this Mac measured; the file is test code only and is
// removed at the end of the phase. Every window is offscreen at alpha 0 and never ordered front.
import AppKit
import Darwin
import Observation
import SomethingAgents
import SomethingCore
import SwiftUI
import Testing
import WebKit
@testable import something

/// SP9's part(x,y): the element under the point, grown to its first ancestor at least 40x24, and its path of tags and
/// :nth-of-type only. Run in something's world, where the page's scripts cannot see or change it.
private let partScript = """
    let node = document.elementFromPoint(x, y);
    while (node && node !== document.body) {
      const box = node.getBoundingClientRect();
      if (box.width >= 40 && box.height >= 24) break;
      node = node.parentElement;
    }
    if (!node) return null;
    const path = [];
    for (let n = node; n && n !== document.documentElement; n = n.parentElement) {
      let i = 1;
      for (let s = n.previousElementSibling; s; s = s.previousElementSibling) if (s.localName === n.localName) i++;
      path.unshift(`${n.localName}:nth-of-type(${i})`);
    }
    const box = node.getBoundingClientRect();
    globalThis.pointedOnce = true;
    return {path: path.join(" > "), tag: node.localName, x: box.x, y: box.y, width: box.width, height: box.height};
    """

/// A page of 2,000 table cells, 60x30 each, taller than the view; it counts its resizes and keeps its widths.
private let gridPage = page(nil, """
    <style>body { margin: 0 } td { width: 60px; height: 30px; padding: 0 } td span { font-size: 9px }</style>
    <table>\((0..<200).map { row in "<tr>" + (0..<10).map { "<td><span>\(row).\($0)</span></td>" }.joined() + "</tr>" }.joined())</table>
    <script>
      window.resizes = 0; window.widths = [innerWidth];
      addEventListener("resize", () => { resizes++; widths.push(innerWidth); });
      window.done = true;
    </script>
    """)

/// The overlay point mode puts over the web view: it takes every click, and hands the wheel to the page under it.
private final class Overlay: NSView {
    weak var web: WKWebView?
    var clicks = 0
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) { clicks += 1 }
    override func scrollWheel(with event: NSEvent) { web?.scrollWheel(with: event) }
}

/// The inspector's one slot: Info or History, by a flag of its model, in one hosting view that is never replaced.
@Observable private final class Slot { var history = false }

private struct SlotView: View {
    let slot: Slot
    var body: some View {
        VStack(alignment: .leading) {
            if slot.history {
                Text("History").font(.headline)
                ForEach(0..<8, id: \.self) { Text("Version \($0)") }
            } else {
                Text("Info").font(.headline)
                Text("Daily brief")
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A view that keeps each frame it is given.
private final class Watched: NSView {
    var frames: [NSRect] = []
    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        frames.append(frame)
    }
}

/// SP12's two sidebars: the system's List(.sidebar), and the custom rows the app draws (b1), both on one model.
@Observable private final class Rows {
    var selection: String? = "Daily brief"
    let names = ["Daily brief", "My agents", "Project watch", "Logbook", "Pebble"]
}

private struct ListSidebar: View {
    @Bindable var rows: Rows
    var body: some View {
        List(selection: $rows.selection) {
            Section("Spaces") { ForEach(rows.names, id: \.self) { Text($0).tag($0) } }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 25)
    }
}

/// A Settings tab: a grouped Form of `count` rows.
private struct Tab: View {
    let count: Int
    var body: some View {
        Form { Section { ForEach(0..<count, id: \.self) { Toggle("Setting \($0)", isOn: .constant($0.isMultiple(of: 2))) } } }
            .formStyle(.grouped)
            .frame(width: 720)
    }
}

@MainActor private func offscreen(_ view: NSView, _ size: NSSize, titled: Bool = false) -> NSWindow {
    let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
                          styleMask: titled ? [.titled, .closable, .resizable, .fullSizeContentView] : .borderless, backing: .buffered, defer: false)
    (window.alphaValue, window.isReleasedWhenClosed, window.contentView) = (0, false, view)
    return window
}

@MainActor private func key(_ code: UInt16, _ characters: String, in window: NSWindow) throws -> NSEvent {
    try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: window.windowNumber, context: nil, characters: characters,
                                  charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
}

private func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

/// The WebContent processes of this user, by pid: a new view's process is the one that was not there before it.
private func webContents() -> Set<pid_t> {
    var pids = [pid_t](repeating: 0, count: 8192)
    let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
    return Set(pids.prefix(max(count, 0)).filter { pid in
        var name = [CChar](repeating: 0, count: 256)
        proc_name(pid, &name, UInt32(name.count))
        return String(cString: name).contains("WebContent")
    })
}

/// A process's footprint in MB (what Activity Monitor calls Memory), or nil when it cannot be read.
private func footprint(_ pid: pid_t) -> Double? {
    var info = rusage_info_v4()
    let read = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) } }
    return read == 0 ? Double(info.ri_phys_footprint) / 1_048_576 : nil
}

/// Waits until the space's frame is there and its document complete. Not requestAnimationFrame: a window never shown
/// draws no frame, and the promise would never settle.
@MainActor private func shown(_ space: SpaceView) async throws {
    #expect(await wait(60, until: { !space.web.isLoading && space.frame != nil }))
    for _ in 0..<600 where try await run(space, "return document.readyState") as? String != "complete" { await wait(0.05) }
}

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-spike-")) struct SpikeTests {
    init() { NSApplication.shared.setActivationPolicy(.prohibited) }

    /// SP9. part(x,y) through callAsyncJavaScript in Lockdown.world on a 2,000-cell page: 100 calls, median at most
    /// 33 ms (hover at 30 Hz); the page's own world sees nothing of it; the overlay takes the click and the wheel
    /// reaches the page.
    @Test func partIsFastEnoughForHover() async throws {
        let home = Home(prefix: "something-spike-")
        defer { home.remove() }
        let space = try await home.window(try home.space("grid", gridPage))
        defer { space.close() }
        let overlay = Overlay(frame: space.area.bounds)
        overlay.web = space.web
        space.area.addSubview(overlay)
        let window = offscreen(space.area, NSSize(width: 900, height: 640))
        defer { window.close() }
        space.open()
        try await ready(space)
        #expect(try await run(space, "return document.querySelectorAll('td').length") as? Int == 2_000)

        var times: [Double] = [], last: [String: Any] = [:]
        for call in 0..<100 {
            let start = Date()
            let found = try await space.web.callAsyncJavaScript(partScript, arguments: ["x": 32 + (call % 10) * 62, "y": 17 + (call % 17) * 32],
                                                                in: space.frame, contentWorld: Lockdown.world)
            times.append(Date().timeIntervalSince(start) * 1000)
            last = try #require(found as? [String: Any])
        }
        print("SP9 part(x,y): median \(median(times)) ms, max \(times.max() ?? 0) ms, first \(times[0]) ms over 100 calls; last \(last)")
        #expect(median(times) <= 33)
        #expect(last["tag"] as? String == "td")
        #expect((last["path"] as? String)?.hasPrefix("body:nth-of-type(1) > table:nth-of-type(1) > tbody:nth-of-type(1) > tr:nth-of-type(") == true)
        // A 9-px span grows to its cell.
        #expect(last["width"] as? Double ?? 0 >= 40)

        // The page's world has no trace of it.
        #expect(try await run(space, "return typeof pointedOnce") as? String == "undefined")

        // The overlay takes the click; the wheel it is given scrolls the page.
        let center = NSPoint(x: 450, y: 320)
        #expect(window.contentView?.hitTest(center) === overlay)
        let wheel = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -400, wheel2: 0, wheel3: 0))
        wheel.location = CGPoint(x: window.frame.minX + 450, y: (NSScreen.screens.first?.frame.maxY ?? 0) - (window.frame.minY + 320))
        wheel.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.windowNumber))
        let event = try #require(NSEvent(cgEvent: wheel))
        overlay.scrollWheel(with: event)
        await wait(1)
        let y = try await run(space, "return scrollY") as? Double ?? 0
        print("SP9 wheel forwarded: scrollY \(y) after a 400-px wheel event (window number \(event.windowNumber))")
        if y == 0 {
            // The fallback: the overlay scrolls the page itself, from something's world.
            _ = try await space.web.callAsyncJavaScript("scrollBy(0, dy)", arguments: ["dy": 400], in: space.frame, contentWorld: Lockdown.world)
            #expect(try await run(space, "return scrollY") as? Double ?? 0 > 0)
        }
    }

    /// SP10. Info and History share the inspector item: opening it narrows the space once; swapping its content moves
    /// nothing, and the page hears no resize.
    @Test func theInspectorSwapsWithoutARelayout() async throws {
        let home = Home(prefix: "something-spike-")
        defer { home.remove() }
        let space = try await home.window(try home.space("grid", gridPage))
        defer { space.close() }
        let split = NSSplitViewController(), center = Watched(), slot = Slot()
        let content = NSViewController()
        content.view = center
        space.area.frame = center.bounds
        space.area.autoresizingMask = [.width, .height]
        center.addSubview(space.area)
        let sidebar = NSSplitViewItem(sidebarWithViewController: NSViewController())
        sidebar.viewController.view = NSView()
        let host = NSHostingController(rootView: SlotView(slot: slot))
        let inspector = NSSplitViewItem(inspectorWithViewController: host)
        (inspector.minimumThickness, inspector.maximumThickness) = (320, 320)
        [sidebar, NSSplitViewItem(viewController: content), inspector].forEach(split.addSplitViewItem)
        let window = offscreen(NSView(), NSSize(width: 1200, height: 760), titled: true)
        defer { window.close() }
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1200, height: 760))
        window.layoutIfNeeded()
        split.splitView.setPosition(236, ofDividerAt: 0)
        split.splitView.setPosition(1200 - 320, ofDividerAt: 1)
        inspector.isCollapsed = true
        window.layoutIfNeeded()
        space.open()
        try await ready(space)
        let before = try await run(space, "return innerWidth") as? Double ?? 0

        // Open, without animation: one relayout.
        center.frames = []
        inspector.isCollapsed = false
        window.layoutIfNeeded()
        await wait(1)
        let opened = try #require(try await run(space, "return [resizes, innerWidth]") as? [Double])
        print("SP10 open: \(center.frames.count) frame(s) of the center, \(opened[0]) resize(s), innerWidth \(before) -> \(opened[1]) on \(ProcessInfo.processInfo.operatingSystemVersionString)")
        #expect(opened[0] == 1)
        #expect(opened[1] == before - 320)
        #expect(host.view.frame.width == 320)

        // Swap Info for History and back, by the model, then by the root view: nothing moves.
        let hosted = host.view, frame = center.frame
        center.frames = []
        for swap in [{ slot.history = true }, { slot.history = false }, { host.rootView = SlotView(slot: slot) }] {
            swap()
            window.layoutIfNeeded()
            await wait(0.5)
            #expect(host.view === hosted)
            #expect(host.view.frame.width == 320)
            #expect(!inspector.isCollapsed)
        }
        let swapped = try #require(try await run(space, "return [resizes, innerWidth]") as? [Double])
        print("SP10 swap: \(center.frames.count) frame(s) of the center, \(swapped[0] - opened[0]) more resize(s)")
        #expect(center.frames.isEmpty)
        #expect(center.frame == frame)
        #expect(swapped[0] == opened[0])

        // Closed, then opened with the animator: how many relayouts the page hears on the way.
        inspector.isCollapsed = true
        window.layoutIfNeeded()
        await wait(0.5)
        let closed = try await run(space, "return resizes") as? Double ?? 0
        center.frames = []
        await withCheckedContinuation { done in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.allowsImplicitAnimation = true
                inspector.animator().isCollapsed = false
            }, completionHandler: { done.resume() })
        }
        await wait(1)
        let animated = try await run(space, "return resizes") as? Double ?? 0
        print("SP10 animated open: \(center.frames.count) frame(s) of the center, \(animated - closed) resize(s)")
    }

    /// SP11. What a thumbnail and a second locked web view cost: takeSnapshot's time on a template, and the second
    /// view's load time and process footprint (counts only).
    @Test func snapshotsAndASecondViewCost() async throws {
        let home = Home(prefix: "something-spike-"), ask = FakeAsk()
        defer { home.remove() }
        ask.answer = { RightsAnswer(allowed: $0, refused: [], folder: nil, remap: [:]) }
        let template = try String(contentsOf: Home.share.appendingPathComponent("templates/brief.html"), encoding: .utf8)
        let ours = getpid(), mine = footprint(ours) ?? 0
        let before = webContents()
        var start = Date()
        let first = try await home.window(try home.space("brief", template), ask)
        defer { first.close() }
        let window = offscreen(first.area, NSSize(width: 1200, height: 760))
        defer { window.close() }
        first.area.frame = NSRect(x: 0, y: 0, width: 1200, height: 760)
        first.open()
        try await shown(first)
        let firstLoad = Date().timeIntervalSince(start) * 1000
        let firstProcesses = webContents().subtracting(before)

        var thumbs: [Double] = [], full: [Double] = []
        let small = WKSnapshotConfiguration()
        small.snapshotWidth = 160
        for _ in 0..<10 {
            start = Date()
            let image = try await first.web.takeSnapshot(configuration: small)
            thumbs.append(Date().timeIntervalSince(start) * 1000)
            #expect(image.size.width == 160)
            if thumbs.count == 1 {
                // A real drawing, not a blank: the template's paper has many colours.
                let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
                let colours = Set((0..<bitmap.pixelsHigh).flatMap { y in stride(from: 0, to: bitmap.pixelsWide, by: 4).compactMap { bitmap.colorAt(x: $0, y: y)?.description } })
                print("SP11 thumbnail: \(bitmap.pixelsWide)x\(bitmap.pixelsHigh) px, \(colours.count) colours")
                #expect(colours.count > 20)
            }
            start = Date()
            _ = try await first.web.takeSnapshot(configuration: nil)
            full.append(Date().timeIntervalSince(start) * 1000)
        }
        print("SP11 takeSnapshot: thumbnail 160 pt median \(median(thumbs)) ms (first \(thumbs[0])), full 1200x760 median \(median(full)) ms")

        let between = webContents(), app = footprint(ours) ?? 0
        start = Date()
        let second = try await home.window(try home.space("brief-copy", template), ask)
        defer { second.close() }
        let other = offscreen(second.area, NSSize(width: 1200, height: 760))
        defer { other.close() }
        second.area.frame = NSRect(x: 0, y: 0, width: 1200, height: 760)
        second.open()
        try await shown(second)
        let secondLoad = Date().timeIntervalSince(start) * 1000
        let secondProcesses = webContents().subtracting(between)
        let sizes = { (pids: Set<pid_t>) in pids.compactMap(footprint).map { String(format: "%.0f MB", $0) }.joined(separator: ", ") }
        print("SP11 first view: load \(Int(firstLoad)) ms, \(firstProcesses.count) new WebContent process(es): \(sizes(firstProcesses))")
        print("SP11 second view: load \(Int(secondLoad)) ms, \(secondProcesses.count) new WebContent process(es): \(sizes(secondProcesses)); "
              + String(format: "app process %.0f -> %.0f -> %.0f MB", mine, app, footprint(ours) ?? 0))
        #expect(median(thumbs) < 200)
        #expect(secondProcesses.count == 1, "a second locked view is a process of its own")
    }

    /// SP12a. The system's sidebar List against the custom rows: its row height, its keys and what VoiceOver reads.
    @Test func theSidebarList() async throws {
        let rows = Rows(), host = NSHostingView(rootView: ListSidebar(rows: rows))
        host.frame = NSRect(x: 0, y: 0, width: 236, height: 400)
        let window = offscreen(host, host.frame.size)
        defer { window.close() }
        window.layoutIfNeeded()
        await wait(0.3)
        func tables(_ view: NSView) -> [NSTableView] { (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(tables) }
        let table = try #require(tables(host).first)
        let heights = (0..<table.numberOfRows).map { table.rect(ofRow: $0).height }
        print("SP12a List(.sidebar): \(type(of: table)), rows \(heights), role \(table.accessibilityRole()?.rawValue ?? "none"), style \(table.style.rawValue)")
        window.makeFirstResponder(table)
        table.keyDown(with: try key(125, String(UnicodeScalar(NSDownArrowFunctionKey)!), in: window))
        await wait(0.3)
        print("SP12a ↓ moved the selection to \(rows.selection ?? "nothing")")
        #expect(rows.selection == "My agents")
        let image = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: image)
        let row = table.rect(ofRow: table.selectedRow), point = table.convert(NSPoint(x: row.midX, y: row.midY), to: host)
        let scale = Double(image.pixelsWide) / host.bounds.width
        let color = image.colorAt(x: Int(point.x * scale), y: Int((host.bounds.height - point.y) * scale))
        print("SP12a selected row's colour \(color.map { "\($0.usingColorSpace(.sRGB)?.description ?? "")" } ?? "none")")
    }

    /// SP12b. Settings: an NSTabViewController in toolbar style, 720 wide, sized to each tab and drawn offscreen.
    @Test func settingsFitEachTab() async throws {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        let counts = [3, 6, 10]
        for (index, count) in counts.enumerated() {
            let page = NSHostingController(rootView: Tab(count: count))
            page.sizingOptions = [.preferredContentSize]
            let item = NSTabViewItem(viewController: page)
            (item.label, item.image) = (["General", "Interface", "Assistant"][index], NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil))
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        (window.alphaValue, window.isReleasedWhenClosed) = (0, false)
        defer { window.close() }
        window.layoutIfNeeded()
        print("SP12b toolbar: \(window.toolbar?.items.map(\.label) ?? []) style \(window.toolbarStyle.rawValue)")
        for index in counts.indices {
            tabs.selectedTabViewItemIndex = index
            window.layoutIfNeeded()
            await wait(0.6)
            let page = try #require(tabs.tabViewItems[index].viewController)
            let content = window.contentRect(forFrameRect: window.frame).size
            print("SP12b tab \(index): window content \(content), preferred \(page.preferredContentSize), fitting \(page.view.fittingSize)")
            #expect(abs(content.width - 720) < 1)
            #expect(abs(content.height - page.preferredContentSize.height) <= 1)
            let view = try #require(window.contentView)
            let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: image)
            #expect(image.pixelsWide > 0)
        }
    }

    /// SP12c. A Go menu item with mini eyes and the state word aligned right by a tab stop; the subtitle as fallback.
    @Test func goMenuItemsCarryEyesAndAStateWord() {
        func menu(stop: CGFloat, subtitle: Bool) -> NSMenu {
            let menu = NSMenu()
            for (name, state) in [("Daily brief", Sign.State.think), ("My agents", .wait), ("Logbook", .sleep)] {
                let item = NSMenuItem(title: name, action: nil, keyEquivalent: "1")
                item.image = Sign.miniEyes(state)
                if subtitle {
                    item.subtitle = state.word
                } else {
                    let style = NSMutableParagraphStyle()
                    style.tabStops = [NSTextTab(textAlignment: .right, location: stop)]
                    item.attributedTitle = NSAttributedString(string: "\(name)\t\(state.word)",
                                                              attributes: [.paragraphStyle: style, .font: NSFont.menuFont(ofSize: 0)])
                }
                menu.addItem(item)
            }
            return menu
        }
        let narrow = menu(stop: 200, subtitle: false), wide = menu(stop: 300, subtitle: false), sub = menu(stop: 0, subtitle: true)
        print("SP12c menu sizes: right tab at 200 \(narrow.size), at 300 \(wide.size), subtitle \(sub.size); title read as \"\(narrow.items[0].title)\"")
        #expect(wide.size.width - narrow.size.width >= 90, "the right tab stop sets the width")
        #expect(narrow.items[0].image?.size == NSSize(width: 16, height: 10))
    }
}
