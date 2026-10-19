// Draws Yuzu's original app icon (a citrus cross-section echoing the ring) at 1024 px.
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

// Squircle tile on the standard macOS grid (824 pt body, 100 pt margin).
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let tile = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
ctx.saveGState()
let shadow = NSShadow(); shadow.shadowColor = rgb(0x5A3A00, 0.35); shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
rgb(0xFFD54A).setFill(); tile.fill()
ctx.restoreGState()
ctx.saveGState(); tile.addClip()
NSGradient(colors: [rgb(0xFFF1B8), rgb(0xFFD23F), rgb(0xFFA30F)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
    .draw(in: body, angle: -90)
// soft top highlight
NSGradient(colors: [rgb(0xFFFFFF, 0.55), rgb(0xFFFFFF, 0)])!.draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)
ctx.restoreGState()

// Citrus slice
let c = NSPoint(x: 512, y: 500)
func circle(_ r: CGFloat) -> NSBezierPath { NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }
ctx.saveGState()
let s2 = NSShadow(); s2.shadowColor = rgb(0x7A4300, 0.35); s2.shadowBlurRadius = 30; s2.shadowOffset = NSSize(width: 0, height: -14); s2.set()
rgb(0xF29A0B).setFill(); circle(300).fill()                  // rind
ctx.restoreGState()
NSGradient(colors: [rgb(0xFFB524), rgb(0xE97F00)])!.draw(in: circle(300), angle: -90)
rgb(0xFFF6DC).setFill(); circle(262).fill()                  // pith
let segments = 8
for i in 0..<segments {
    let mid = CGFloat(i) / CGFloat(segments) * .pi * 2 + .pi / 2
    let half = (.pi / CGFloat(segments)) - 0.075
    let p = NSBezierPath()
    p.appendArc(withCenter: c, radius: 238, startAngle: (mid - half) * 180 / .pi, endAngle: (mid + half) * 180 / .pi)
    p.appendArc(withCenter: c, radius: 62, startAngle: (mid + half) * 180 / .pi, endAngle: (mid - half) * 180 / .pi, clockwise: true)
    p.close()
    p.lineJoinStyle = .round
    ctx.saveGState(); p.addClip()
    NSGradient(colors: [rgb(0xFFE15C), rgb(0xFFB70F)])!.draw(fromCenter: c, radius: 60, toCenter: c, radius: 240, options: [])
    // juice vesicle sheen
    rgb(0xFFFFFF, 0.22).setFill()
    let hx = c.x + cos(mid) * 170, hy = c.y + sin(mid) * 170
    NSBezierPath(ovalIn: NSRect(x: hx - 26, y: hy - 18, width: 52, height: 36)).fill()
    ctx.restoreGState()
    rgb(0xFFF6DC).setStroke(); p.lineWidth = 10; p.stroke()
}
rgb(0xFFF6DC).setFill(); circle(46).fill()
// leaf
let leaf = NSBezierPath()
leaf.move(to: NSPoint(x: 640, y: 760))
leaf.curve(to: NSPoint(x: 800, y: 840), controlPoint1: NSPoint(x: 680, y: 850), controlPoint2: NSPoint(x: 760, y: 870))
leaf.curve(to: NSPoint(x: 640, y: 760), controlPoint1: NSPoint(x: 790, y: 780), controlPoint2: NSPoint(x: 700, y: 740))
NSGradient(colors: [rgb(0x7BC74D), rgb(0x3E8E2F)])!.draw(in: leaf, angle: 30)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
