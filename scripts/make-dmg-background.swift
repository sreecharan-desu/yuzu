// Draws the DMG window background (660x400 points) at 1x and 2x.
// Quiet and editorial: a pearl canvas with a faint top light, a hairline chevron between the two icons,
// one short line with a single italic word, and a privacy line with a blue lead-in.
// Usage: swift scripts/make-dmg-background.swift <outdir>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/dmg"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func hex(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: a)
}

func render(scale: CGFloat) -> Data {
    let W: CGFloat = 660, H: CGFloat = 400
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: 0, y: 0, width: W, height: H)

    // Canvas: white to #F5F5F7, with a soft light from above.
    NSGradient(colors: [hex(0xFFFFFF), hex(0xF5F5F7)])!.draw(in: rect, angle: -90)
    let light = NSGradient(colors: [hex(0xFFFFFF, 0.9), hex(0xFFFFFF, 0)])!
    light.draw(fromCenter: NSPoint(x: W * 0.5, y: H + 40), radius: 0, toCenter: NSPoint(x: W * 0.5, y: H + 40), radius: 360, options: [])

    // Fine grain, deterministic.
    var s: UInt64 = 0x9E3779B97F4A7C15
    let n = Int(W * H * 0.18)
    for _ in 0..<n {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17
        let x = CGFloat(s % UInt64(W * 10)) / 10, y = CGFloat((s >> 20) % UInt64(H * 10)) / 10
        let dark = (s >> 40) & 1 == 0
        ctx.setFillColor((dark ? NSColor.black.withAlphaComponent(0.025) : NSColor.white.withAlphaComponent(0.05)).cgColor)
        ctx.fill(CGRect(x: x, y: y, width: 0.5, height: 0.5))
    }

    // Hairline chevron, centred between the icons (icons sit at y = 200 from the top).
    let cy = H - 200 + 8, cx = W / 2
    let chev = NSBezierPath()
    chev.move(to: NSPoint(x: cx - 5, y: cy + 10))
    chev.line(to: NSPoint(x: cx + 5, y: cy))
    chev.line(to: NSPoint(x: cx - 5, y: cy - 10))
    chev.lineWidth = 1.5
    chev.lineCapStyle = .round
    chev.lineJoinStyle = .round
    hex(0xC7C7CC).setStroke()
    chev.stroke()

    // Copy.
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let display = NSFont.systemFont(ofSize: 17, weight: .medium)
    let italic = NSFontManager.shared.convert(display, toHaveTrait: .italicFontMask)
    let line = NSMutableAttributedString(string: "Drag Yuzu to ", attributes: [.font: display, .foregroundColor: hex(0x1D1D1F), .kern: -0.4, .paragraphStyle: p])
    line.append(NSAttributedString(string: "Applications", attributes: [.font: italic, .foregroundColor: hex(0x1D1D1F), .kern: -0.4, .paragraphStyle: p]))
    line.append(NSAttributedString(string: ".", attributes: [.font: display, .foregroundColor: hex(0x1D1D1F), .paragraphStyle: p]))
    line.draw(in: CGRect(x: 0, y: 70, width: W, height: 24))

    let small = NSFont.systemFont(ofSize: 11.5, weight: .regular)
    let trust = NSMutableAttributedString(string: "Private by design. ", attributes: [.font: small, .foregroundColor: hex(0x1F6FE5), .paragraphStyle: p])
    trust.append(NSAttributedString(string: "Every file stays on your Mac.", attributes: [.font: small, .foregroundColor: hex(0x86868B), .paragraphStyle: p]))
    trust.draw(in: CGRect(x: 0, y: 46, width: W, height: 18))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! render(scale: 1).write(to: URL(fileURLWithPath: "\(out)/background.png"))
try! render(scale: 2).write(to: URL(fileURLWithPath: "\(out)/background@2x.png"))
print("wrote \(out)/background.png and background@2x.png")
