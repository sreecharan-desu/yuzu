// Yuzu app icon v2 (original): a glossy whole yuzu fruit with a leaf, orbited by a soft
// conversion arc, on a deep evergreen squircle. Renders a 1024 px PNG.
import AppKit

let S: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}
func squircle(_ r: NSRect, _ k: CGFloat = 0.225) -> NSBezierPath {
    // Continuous-corner approximation: rounded rect with generous radius.
    NSBezierPath(roundedRect: r, xRadius: r.width * k, yRadius: r.height * k)
}

// 1. Tile (macOS grid: 824 body inside 1024 canvas)
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let tile = squircle(body)
ctx.saveGState()
let drop = NSShadow(); drop.shadowColor = rgb(0x000000, 0.30); drop.shadowBlurRadius = 30; drop.shadowOffset = NSSize(width: 0, height: -14); drop.set()
rgb(0x123B2C).setFill(); tile.fill()
ctx.restoreGState()
ctx.saveGState(); tile.addClip()
NSGradient(colors: [rgb(0x2E6B4F), rgb(0x174A37), rgb(0x0B2A1F)], atLocations: [0, 0.5, 1], colorSpace: .sRGB)!.draw(in: body, angle: -90)
// soft top sheen and a warm glow behind the fruit
NSGradient(colors: [rgb(0xFFFFFF, 0.16), rgb(0xFFFFFF, 0)])!.draw(in: NSRect(x: 100, y: 600, width: 824, height: 324), angle: -90)
NSGradient(colors: [rgb(0xFFD54A, 0.38), rgb(0xFFD54A, 0)])!.draw(fromCenter: NSPoint(x: 512, y: 470), radius: 0, toCenter: NSPoint(x: 512, y: 470), radius: 420, options: [])
ctx.restoreGState()
// hairline inner edge
ctx.saveGState(); rgb(0xFFFFFF, 0.14).setStroke(); let edge = squircle(body.insetBy(dx: 2, dy: 2)); edge.lineWidth = 3; edge.stroke(); ctx.restoreGState()

let c = NSPoint(x: 512, y: 488)
let R: CGFloat = 250

// 2. Orbit arc (back half, behind the fruit)
func arc(_ from: CGFloat, _ to: CGFloat, _ width: CGFloat, _ color: NSColor) {
    let p = NSBezierPath()
    p.appendArc(withCenter: .zero, radius: 330, startAngle: from, endAngle: to)
    var t = AffineTransform(translationByX: c.x, byY: c.y)
    t.rotate(byDegrees: -18)
    t.scale(x: 1, y: 0.42)
    p.transform(using: t)
    p.lineWidth = width; p.lineCapStyle = .round
    color.setStroke(); p.stroke()
}
arc(14, 166, 24, rgb(0xFFF3C4, 0.35))

// 3. Fruit
ctx.saveGState()
let fs = NSShadow(); fs.shadowColor = rgb(0x000000, 0.40); fs.shadowBlurRadius = 40; fs.shadowOffset = NSSize(width: 0, height: -22); fs.set()
let fruit = NSBezierPath(ovalIn: NSRect(x: c.x - R, y: c.y - R * 0.96, width: 2 * R, height: 2 * R * 0.96))
rgb(0xF2B705).setFill(); fruit.fill()
ctx.restoreGState()
ctx.saveGState(); fruit.addClip()
NSGradient(colors: [rgb(0xFFF08A), rgb(0xFFD21F), rgb(0xF0A800), rgb(0xB87400)], atLocations: [0, 0.35, 0.72, 1], colorSpace: .sRGB)!
    .draw(fromCenter: NSPoint(x: c.x - 80, y: c.y + 95), radius: 10, toCenter: c, radius: R * 1.05, options: [.drawsAfterEndingLocation])
// peel dimples (yuzu's bumpy rind), deterministic pattern
var seed: UInt64 = 0x9E3779B97F4A7C15
func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
for _ in 0..<170 {
    let a = rnd() * .pi * 2, r = sqrt(rnd()) * R * 0.95
    let x = c.x + cos(a) * r, y = c.y + sin(a) * r * 0.96
    let s = 7 + rnd() * 9
    rgb(0x9A5A00, 0.045 + 0.045 * (r / R)).setFill()
    NSBezierPath(ovalIn: NSRect(x: x - s / 2, y: y - s / 2, width: s, height: s)).fill()
    rgb(0xFFFBE0, 0.06).setFill()
    NSBezierPath(ovalIn: NSRect(x: x - s / 2 - 2, y: y - s / 2 + 2, width: s * 0.6, height: s * 0.6)).fill()
}
// specular highlight
NSGradient(colors: [rgb(0xFFFFFF, 0.85), rgb(0xFFFFFF, 0)])!
    .draw(fromCenter: NSPoint(x: c.x - 95, y: c.y + 120), radius: 0, toCenter: NSPoint(x: c.x - 95, y: c.y + 120), radius: 120, options: [])
// rim light at the bottom
NSGradient(colors: [rgb(0xFFE27A, 0), rgb(0xFFE27A, 0.35)])!
    .draw(fromCenter: c, radius: R * 0.75, toCenter: c, radius: R, options: [])
ctx.restoreGState()

// 4. Stem nub and leaf
rgb(0x6B4A12).setFill()
NSBezierPath(ovalIn: NSRect(x: c.x + 8, y: c.y + R * 0.9, width: 34, height: 26)).fill()
let leaf = NSBezierPath()
let base = NSPoint(x: c.x + 30, y: c.y + R * 0.95)
leaf.move(to: base)
leaf.curve(to: NSPoint(x: c.x + 250, y: c.y + R * 1.30), controlPoint1: NSPoint(x: c.x + 70, y: c.y + R * 1.42), controlPoint2: NSPoint(x: c.x + 190, y: c.y + R * 1.48))
leaf.curve(to: base, controlPoint1: NSPoint(x: c.x + 215, y: c.y + R * 1.02), controlPoint2: NSPoint(x: c.x + 110, y: c.y + R * 0.88))
ctx.saveGState()
let ls = NSShadow(); ls.shadowColor = rgb(0x000000, 0.30); ls.shadowBlurRadius = 16; ls.shadowOffset = NSSize(width: 0, height: -8); ls.set()
rgb(0x4CAF50).setFill(); leaf.fill()
ctx.restoreGState()
ctx.saveGState(); leaf.addClip()
NSGradient(colors: [rgb(0x9BE36A), rgb(0x3E9B3A), rgb(0x1F6B2A)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: leaf, angle: -35)
let vein = NSBezierPath(); vein.move(to: base)
vein.curve(to: NSPoint(x: c.x + 240, y: c.y + R * 1.30), controlPoint1: NSPoint(x: c.x + 110, y: c.y + R * 1.18), controlPoint2: NSPoint(x: c.x + 180, y: c.y + R * 1.26))
vein.lineWidth = 6; rgb(0xE8FFD0, 0.55).setStroke(); vein.stroke()
ctx.restoreGState()

// 5. Orbit arc (front half, over the fruit) with an arrowhead: the "convert" motif
arc(194, 338, 26, rgb(0xFFF7DA, 0.92))
do {
    // arrowhead at 330 degrees on the transformed ellipse
    let a: CGFloat = 338 * .pi / 180
    var t = AffineTransform(translationByX: c.x, byY: c.y); t.rotate(byDegrees: -18); t.scale(x: 1, y: 0.42)
    let p0 = t.transform(NSPoint(x: cos(a) * 330, y: sin(a) * 330))
    let p1 = t.transform(NSPoint(x: cos(a + 0.05) * 330, y: sin(a + 0.05) * 330))
    let dir = atan2(p1.y - p0.y, p1.x - p0.x)
    let head = NSBezierPath()
    let L: CGFloat = 64, W: CGFloat = 40
    let tip = NSPoint(x: p0.x + cos(dir) * L * 0.6, y: p0.y + sin(dir) * L * 0.6)
    head.move(to: tip)
    head.line(to: NSPoint(x: p0.x - cos(dir) * L * 0.4 + cos(dir + .pi / 2) * W, y: p0.y - sin(dir) * L * 0.4 + sin(dir + .pi / 2) * W))
    head.line(to: NSPoint(x: p0.x - cos(dir) * L * 0.4 - cos(dir + .pi / 2) * W, y: p0.y - sin(dir) * L * 0.4 - sin(dir + .pi / 2) * W))
    head.close(); head.lineJoinStyle = .round; head.lineWidth = 10
    rgb(0xFFF7DA, 0.95).setFill(); rgb(0xFFF7DA, 0.95).setStroke(); head.fill(); head.stroke()
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
