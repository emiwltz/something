// The layer above the whole window's split view, for what covers the window rather than one column: the toast, the
// shortcut sheet (KeysSheet.swift), and later the palette and the sidebar shown over the space. It takes the mouse only
// on what it holds, so the columns, their dividers and the toolbar's separators under it behave as if it were not
// there, and it is hidden while it holds nothing. The glass over the center, which holds the assistant, is one too
// (Glass.swift).
import AppKit

class WindowLayer: NSView {
    /// Says `words` to VoiceOver at once, for what appears here without taking the focus. Tests replace it.
    var announce: (String) -> Void = { words in
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: words, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// Lays the layer over all of `view`, above its other subviews, following its size.
    init(over view: NSView) {
        super.init(frame: view.bounds)
        autoresizingMask = [.width, .height]
        isHidden = true
        view.addSubview(self, positioned: .above, relativeTo: nil)
    }

    required init?(coder: NSCoder) { nil }

    /// What it holds answers for itself; the layer's own empty space answers nil, so the event goes on to what is under it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    /// Shows `view` in the layer, the layer brought back above the columns, which the split view may have added after
    /// it. The layer shows first: a view added under a hidden one would stay hidden to the mouse.
    func hold(_ view: NSView) {
        isHidden = false
        if superview?.subviews.last !== self { superview?.addSubview(self, positioned: .above, relativeTo: nil) }
        addSubview(view)
    }

    override func willRemoveSubview(_ subview: NSView) { isHidden = subviews.allSatisfy { $0 === subview } }
}
