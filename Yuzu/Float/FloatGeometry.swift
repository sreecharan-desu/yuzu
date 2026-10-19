import AppKit

/// Where the Float shelf rests. Pure geometry so snapping can be tested without moving anything on screen.
enum FloatEdge: String, Sendable { case left, right }

enum FloatGeometry {
    static let width: CGFloat = 256
    static let tab = NSSize(width: 64, height: 124)
    static let snapDistance: CGFloat = 28
    static let margin: CGFloat = 8

    static func expandedHeight(items: Int) -> CGFloat {
        let rows = max(1, min(3, Int(ceil(Double(items) / 2))))
        return 48 + CGFloat(rows) * 112 + 4
    }

    /// After a drag ends: dock to an edge when the shelf is within `snapDistance` of it (or pushed past it),
    /// otherwise stay where it was dropped, kept fully on screen.
    static func settle(_ frame: NSRect, in visible: NSRect) -> (edge: FloatEdge?, frame: NSRect) {
        if frame.minX - visible.minX < snapDistance {
            return (.left, docked(.left, centerY: frame.midY, in: visible))
        }
        if visible.maxX - frame.maxX < snapDistance {
            return (.right, docked(.right, centerY: frame.midY, in: visible))
        }
        var f = frame
        f.origin.x = min(max(f.minX, visible.minX + margin), visible.maxX - f.width - margin)
        f.origin.y = min(max(f.minY, visible.minY + margin), visible.maxY - f.height - margin)
        return (nil, f)
    }

    /// The collapsed glass tab flush against an edge.
    static func docked(_ edge: FloatEdge, centerY: CGFloat, in visible: NSRect) -> NSRect {
        let y = min(max(centerY - tab.height / 2, visible.minY + margin), visible.maxY - tab.height - margin)
        let x = edge == .left ? visible.minX : visible.maxX - tab.width
        return NSRect(x: x, y: y, width: tab.width, height: tab.height)
    }

    /// The full shelf opened from a docked tab, growing away from the edge and centred on the tab.
    static func expanded(from tab: NSRect, edge: FloatEdge, items: Int, in visible: NSRect) -> NSRect {
        let h = expandedHeight(items: items)
        let y = min(max(tab.midY - h / 2, visible.minY + margin), visible.maxY - h - margin)
        let x = edge == .left ? visible.minX + 2 : visible.maxX - width - 2
        return NSRect(x: x, y: y, width: width, height: h)
    }
}
