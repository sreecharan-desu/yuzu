import AppKit

enum Glyphs {
    /// Original menu bar glyph: a small ring of segments around a dot, drawn as a template image.
    static func menuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let c = NSPoint(x: rect.midX, y: rect.midY)
            NSColor.black.setFill()
            NSColor.black.setStroke()
            let count = 7
            let outer: CGFloat = 8.2, inner: CGFloat = 4.6
            for i in 0..<count {
                let mid = CGFloat(i) / CGFloat(count) * .pi * 2 + .pi / 2
                let half = (.pi * 2 / CGFloat(count)) / 2 - 0.20
                let p = NSBezierPath()
                p.appendArc(withCenter: c, radius: outer, startAngle: (mid - half) * 180 / .pi, endAngle: (mid + half) * 180 / .pi)
                p.appendArc(withCenter: c, radius: inner, startAngle: (mid + half) * 180 / .pi, endAngle: (mid - half) * 180 / .pi, clockwise: true)
                p.close()
                p.lineJoinStyle = .round
                p.lineWidth = 0.9
                p.fill()
                p.stroke()
            }
            NSBezierPath(ovalIn: NSRect(x: c.x - 2.1, y: c.y - 2.1, width: 4.2, height: 4.2)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Yuzu"
        return image
    }
}
