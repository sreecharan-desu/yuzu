// Draws the original DMG window background (660x400 points) at 1x and 2x.
// Usage: swift scripts/make-dmg-background.swift <outdir>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/dmg"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(scale: CGFloat) -> Data {
    let w = 660 * scale, h = 400 * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 660, height: 400)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: 0, y: 0, width: 660, height: 400)

    // Warm cream to pale saffron wash.
    let base = NSGradient(colors: [NSColor(red: 1.00, green: 0.985, blue: 0.95, alpha: 1),
                                   NSColor(red: 1.00, green: 0.93, blue: 0.78, alpha: 1)])!
    base.draw(in: rect, angle: -70)
    // Soft citrus glows.
    func glow(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: NSColor) {
        let g = NSGradient(colors: [c, c.withAlphaComponent(0)])!
        g.draw(fromCenter: NSPoint(x: x, y: y), radius: 0, toCenter: NSPoint(x: x, y: y), radius: r, options: [])
    }
    glow(90, 360, 260, NSColor(red: 1.0, green: 0.78, blue: 0.25, alpha: 0.35))
    glow(600, 40, 280, NSColor(red: 0.55, green: 0.80, blue: 0.45, alpha: 0.18))

    // Dashed arc arrow from the app slot to Applications (icons sit at y = 200 from the top).
    let y: CGFloat = 400 - 200
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 252, y: y + 6))
    path.curve(to: NSPoint(x: 400, y: y + 6), controlPoint1: NSPoint(x: 295, y: y + 46), controlPoint2: NSPoint(x: 357, y: y + 46))
    path.lineWidth = 3
    path.lineCapStyle = .round
    path.setLineDash([1, 9], count: 2, phase: 0)
    NSColor(red: 0.85, green: 0.50, blue: 0.05, alpha: 0.75).setStroke()
    path.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 388, y: y + 20))
    head.line(to: NSPoint(x: 404, y: y + 5))
    head.line(to: NSPoint(x: 384, y: y + 1))
    head.lineWidth = 3
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    // Caption.
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let title: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
        .foregroundColor: NSColor(red: 0.20, green: 0.14, blue: 0.04, alpha: 0.9), .paragraphStyle: p]
    let sub: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor(red: 0.30, green: 0.22, blue: 0.08, alpha: 0.6), .paragraphStyle: p]
    NSAttributedString(string: "Drag Yuzu into Applications", attributes: title).draw(in: CGRect(x: 0, y: 72, width: 660, height: 24))
    NSAttributedString(string: "Then open it from Applications. It lives in the menu bar.", attributes: sub)
        .draw(in: CGRect(x: 0, y: 50, width: 660, height: 18))
    _ = ctx
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! render(scale: 1).write(to: URL(fileURLWithPath: "\(out)/background.png"))
try! render(scale: 2).write(to: URL(fileURLWithPath: "\(out)/background@2x.png"))
print("wrote \(out)/background.png and background@2x.png")
