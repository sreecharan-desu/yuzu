import AppKit

enum Glyphs {
    /// Template menu bar glyph matching the Ring mark: seven petals and a hub, the eighth petal lifted out.
    static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let ro: CGFloat = 7.6, ri: CGFloat = 4.0, gap: CGFloat = 1.6, n = 8
            let step = 2 * Double.pi / Double(n)
            NSColor.black.setFill()
            for i in 0..<n {
                let a0 = -Double.pi / 2 + Double(i) * step, a1 = a0 + step
                var center = c
                var outer = ro
                if i == 0 {   // the chosen petal, nudged outward
                    let mid = (a0 + a1) / 2
                    center = CGPoint(x: c.x + 1.3 * CGFloat(cos(mid)), y: c.y + 1.3 * CGFloat(sin(mid)))
                    outer = ro + 0.4
                }
                let shape = PetalShape(startAngle: a0, endAngle: a1, innerRadius: ri, outerRadius: outer, gap: gap, corner: 0.9)
                let side = outer * 2 + 2
                let p = shape.path(in: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side))
                let bp = NSBezierPath(yuzuCGPath: p.cgPath)
                bp.fill()
            }
            NSBezierPath(ovalIn: NSRect(x: c.x - 1.9, y: c.y - 1.9, width: 3.8, height: 3.8)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Yuzu"
        return image
    }
}

extension NSBezierPath {
    /// `NSBezierPath(cgPath:)` needs macOS 14. Earlier systems walk the path elements.
    convenience init(yuzuCGPath path: CGPath) {
        if #available(macOS 14, *) {
            self.init(cgPath: path)
            return
        }
        self.init()
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint:
                self.move(to: e.points[0])
            case .addLineToPoint:
                self.line(to: e.points[0])
            case .addQuadCurveToPoint:
                let current = self.currentPoint
                let control = e.points[0]
                let end = e.points[1]
                let c1 = CGPoint(x: current.x + (2.0 / 3.0) * (control.x - current.x),
                                 y: current.y + (2.0 / 3.0) * (control.y - current.y))
                let c2 = CGPoint(x: end.x + (2.0 / 3.0) * (control.x - end.x),
                                 y: end.y + (2.0 / 3.0) * (control.y - end.y))
                self.curve(to: end, controlPoint1: c1, controlPoint2: c2)
            case .addCurveToPoint:
                self.curve(to: e.points[2], controlPoint1: e.points[0], controlPoint2: e.points[1])
            case .closeSubpath:
                self.close()
            @unknown default:
                break
            }
        }
    }
}
