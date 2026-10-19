// The two AppKit pieces the sheets and panels share: a label that wraps at a given width, and a path on one line. The
// main window's own views are SwiftUI (Sidebar.swift, Inspector.swift) and need neither.
import AppKit

enum Style {
    /// A label that wraps at `width` points: a long sentence must not widen its window.
    static func line(_ text: String, width: CGFloat) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.preferredMaxLayoutWidth = width
        return label
    }

    /// `path` on one line, with ~ for `home`, its middle names given way to "…" until it fits `width`; the whole path
    /// shows when the pointer rests on it.
    static func path(_ path: String, home: String, width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        let font = label.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        label.stringValue = Words.path(path, home: home) { ($0 as NSString).size(withAttributes: [.font: font]).width <= width }
        label.toolTip = path
        // Even its first and last names may not fit: AppKit then cuts what is left, rather than widen the window.
        label.lineBreakMode = .byTruncatingMiddle
        label.widthAnchor.constraint(lessThanOrEqualToConstant: width).isActive = true
        return label
    }
}
