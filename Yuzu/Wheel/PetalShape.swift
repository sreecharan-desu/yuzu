import SwiftUI

/// One wheel segment: an annular sector with parallel gaps between neighbours
/// and softly rounded corners. Angles are radians, y-down (SwiftUI), 0 = right.
struct PetalShape: Shape {
    var startAngle: Double
    var endAngle: Double
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    var gap: CGFloat = Theme.petalGap
    var corner: CGFloat = Theme.petalCorner

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let d = Double(gap / 2)
        func pt(_ r: CGFloat, _ a: Double) -> CGPoint {
            CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
        }
        let ro = Double(outerRadius), ri = Double(innerRadius)
        let oS = startAngle + asin(min(1, d / ro)), oE = endAngle - asin(min(1, d / ro))
        let iS = startAngle + asin(min(1, d / ri)), iE = endAngle - asin(min(1, d / ri))

        var pts: [CGPoint] = []
        var corners = Set<Int>()
        let no = 40, ni = 22
        corners.insert(pts.count)
        for i in 0...no { pts.append(pt(outerRadius, oS + (oE - oS) * Double(i) / Double(no))) }
        corners.insert(pts.count - 1)
        corners.insert(pts.count)
        for i in 0...ni { pts.append(pt(innerRadius, iE + (iS - iE) * Double(i) / Double(ni))) }
        corners.insert(pts.count - 1)
        return Path(Self.rounded(pts, corners: corners, radius: corner, innerRadius: corner * 0.7,
                                 innerIndices: Set([no + 1, no + 1 + ni])))
    }

    static func rounded(_ pts: [CGPoint], corners: Set<Int>, radius: CGFloat,
                        innerRadius: CGFloat, innerIndices: Set<Int>) -> CGPath {
        let n = pts.count
        func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        func toward(_ from: CGPoint, _ to: CGPoint, _ l: CGFloat) -> CGPoint {
            let dd = max(dist(from, to), 0.0001)
            return CGPoint(x: from.x + (to.x - from.x) / dd * l, y: from.y + (to.y - from.y) / dd * l)
        }
        func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        var skip = Set<Int>()
        var data: [Int: (CGPoint, CGPoint)] = [:]
        for i in corners {
            let r = innerIndices.contains(i) ? innerRadius : radius
            let v = pts[i]
            var j = (i - 1 + n) % n
            while dist(pts[j], v) < r && !corners.contains(j) { skip.insert(j); j = (j - 1 + n) % n }
            var k = (i + 1) % n
            while dist(pts[k], v) < r && !corners.contains(k) { skip.insert(k); k = (k + 1) % n }
            let la = min(r, dist(pts[j], v) * 0.48), lb = min(r, dist(pts[k], v) * 0.48)
            data[i] = (toward(v, pts[j], la), toward(v, pts[k], lb))
        }
        let path = CGMutablePath()
        var started = false
        for i in 0..<n where !skip.contains(i) {
            if let (t1, t2) = data[i] {
                if started { path.addLine(to: t1) } else { path.move(to: t1); started = true }
                path.addCurve(to: t2, control1: lerp(t1, pts[i], 0.62), control2: lerp(t2, pts[i], 0.62))
            } else {
                if started { path.addLine(to: pts[i]) } else { path.move(to: pts[i]); started = true }
            }
        }
        path.closeSubpath()
        return path
    }
}

enum WheelGeometry {
    static func step(_ slots: Int) -> Double { 2 * .pi / Double(slots) }
    /// About 4 degrees of stickiness at petal edges.
    static let hysteresis = 0.07
    /// Center angle of a slot; slot 0 points straight up.
    static func midAngle(_ i: Int, _ slots: Int) -> Double { -.pi / 2 + Double(i) * step(slots) }

    /// Slot under a point given relative to the wheel center in y-down coordinates.
    /// With `current`, the highlighted petal is kept until the pointer is a few degrees past its edge, so
    /// hovering along a seam never flickers between two petals.
    static func slot(dx: CGFloat, dy: CGFloat, slots: Int, current: Int? = nil) -> Int? {
        let r = hypot(dx, dy)
        let inner = Theme.hubDiameter / 2 + (current == nil ? 2 : -4)
        let outer = Theme.canvas / 2 + (current == nil ? 40 : 56)
        guard r > inner, r < outer else { return nil }
        var a = atan2(Double(dy), Double(dx)) + .pi / 2
        while a < 0 { a += 2 * .pi }
        if let c = current, c < slots {
            var d = abs(a - Double(c) * step(slots)).truncatingRemainder(dividingBy: 2 * .pi)
            if d > .pi { d = 2 * .pi - d }
            if d < step(slots) / 2 + hysteresis { return c }
        }
        let s = Int((a / step(slots)).rounded()) % slots
        return s
    }
}
