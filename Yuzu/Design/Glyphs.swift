import AppKit

enum Glyphs {
    /// Template menu bar glyph matching the v2 icon: a round yuzu with a leaf and an orbit arc.
    static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            NSColor.black.setFill()
            NSColor.black.setStroke()
            // fruit
            let fruit = NSBezierPath(ovalIn: NSRect(x: 2.4, y: 1.6, width: 12.0, height: 12.0))
            fruit.fill()
            // leaf, separated from the fruit by a hairline gap
            let leaf = NSBezierPath()
            leaf.move(to: NSPoint(x: 9.2, y: 12.4))
            leaf.curve(to: NSPoint(x: 16.2, y: 15.6), controlPoint1: NSPoint(x: 10.4, y: 16.2), controlPoint2: NSPoint(x: 14.0, y: 16.8))
            leaf.curve(to: NSPoint(x: 9.2, y: 12.4), controlPoint1: NSPoint(x: 15.2, y: 12.6), controlPoint2: NSPoint(x: 11.6, y: 11.6))
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            leaf.lineWidth = 2.2
            leaf.stroke()
            ctx.restoreGState()
            leaf.fill()
            // orbit arc: cut a channel through the fruit, then draw the thin arc inside it
            let orbit = NSBezierPath()
            orbit.appendArc(withCenter: .zero, radius: 8.6, startAngle: 192, endAngle: 344)
            var t = AffineTransform(translationByX: 8.4, byY: 8.0)
            t.rotate(byDegrees: 14)
            t.scale(x: 1, y: 0.34)
            orbit.transform(using: t)
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            orbit.lineWidth = 3.0
            orbit.lineCapStyle = .round
            orbit.stroke()
            ctx.restoreGState()
            orbit.lineWidth = 1.3
            orbit.lineCapStyle = .round
            orbit.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Yuzu"
        return image
    }
}
