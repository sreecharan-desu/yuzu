import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import CoreServices

/// RGBA color that can cross threads.
struct RGBA: Hashable, Codable, Sendable {
    var r: Double, g: Double, b: Double, a: Double = 1
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    static let black = RGBA(r: 0, g: 0, b: 0)
    static let white = RGBA(r: 1, g: 1, b: 1)
}

import SwiftUI

struct PhotoAdjustments: Equatable, Sendable {
    var exposure = 0.0, brightness = 0.0, contrast = 0.0, saturation = 0.0, vibrance = 0.0
    var highlights = 0.0, shadows = 0.0, temperature = 0.0, tint = 0.0, gamma = 0.0, sharpness = 0.0
    var isNeutral: Bool { self == PhotoAdjustments() }
}

enum AnnoKind: String, CaseIterable, Sendable { case arrow, pen, highlight, rect, ellipse, text }

struct AnnoShape: Identifiable, Sendable {
    let id = UUID()
    var kind: AnnoKind
    var points: [CGPoint]          // normalized, top-left origin
    var color: RGBA
    var width: Double              // fraction of the image's shorter side
    var text: String = ""
}

enum RedactMode: String, CaseIterable, Sendable { case blur, pixelate, solid }

enum BGFill: Hashable, Codable, Sendable {
    case none
    case backdrop(Backdrop)
    case solid(RGBA)
    case gradient(RGBA, RGBA)
    case blur
    case image(URL)
}

struct BGStyle: Equatable, Codable, Sendable {
    var liftSubject = true
    var fill: BGFill = .gradient(RGBA(r: 1.0, g: 0.82, b: 0.30), RGBA(r: 0.98, g: 0.45, b: 0.18))
    var padding = 0.08          // fraction of the image's longer side (width in screenshot mode)
    var corners = 0.03          // same base as padding
    var shadow = 0.04
    var ratio: Double? = nil    // width / height, nil = auto
    var screenshot = false      // frame a screenshot: no lifting, window-like corners, layered shadow
    var border = true           // subtle inset border (screenshot mode)
    var grain = 0.5             // noise over code-drawn backdrops

    /// Defaults for a screenshot: generous padding, macOS window corners, soft layered shadow.
    static func forScreenshot(pixelScale: Double, width: Double, captureCorner: Double? = nil) -> BGStyle {
        var s = BGStyle()
        s.liftSubject = false
        s.screenshot = true
        s.fill = .backdrop(.pearl)
        s.padding = 0.08
        s.corners = captureCorner ?? (ImageEdit.windowCornerPoints * pixelScale / max(width, 1))
        s.shadow = 0.05
        return s
    }
}

enum ImageEdit {
    static let ci = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: false])

    // MARK: Saving

    /// Writes an edited image next to the source, keeping its format (PNG when transparency must survive).
    static func save(_ image: CGImage, for src: URL, suffix: String, needsAlpha: Bool = false, forcePNG: Bool = false,
                     dpi: Double? = nil, settings: ImageSettings) throws -> URL {
        var format = ImageFormat.of(src) ?? .png
        if !format.isAvailable || format == .pdf || format == .gif { format = .png }
        if needsAlpha || forcePNG { format = .png }   // cut-outs are always transparent PNGs
        let dest = OutputNamer.destination(for: src, ext: format.ext, suffix: suffix)
        let decoded = try? ImageEngine.decode(src, maxPixel: 1)
        var props = ImageEngine.carriedProperties(decoded?.properties ?? [:], keep: settings.preserveMetadata)
        if let dpi { props[kCGImagePropertyDPIWidth] = dpi; props[kCGImagePropertyDPIHeight] = dpi }
        try ImageEngine.write(image, as: format, to: dest, properties: props, quality: max(settings.quality, 0.9))
        return dest
    }

    static func full(_ src: URL) throws -> CGImage { try ImageEngine.decode(src).image }

    static func context(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    // MARK: Crop and resize

    static func crop(_ image: CGImage, normalized r: CGRect) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let px = CGRect(x: r.minX * w, y: r.minY * h, width: r.width * w, height: r.height * h).integral
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        return image.cropping(to: px)
    }

    static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let ctx = context(max(1, width), max(1, height)) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    // MARK: Photo adjustments

    static func adjust(_ input: CIImage, _ a: PhotoAdjustments) -> CIImage {
        var img = input
        if a.exposure != 0 { let f = CIFilter.exposureAdjust(); f.inputImage = img; f.ev = Float(a.exposure); img = f.outputImage ?? img }
        if a.highlights != 0 || a.shadows != 0 {
            let f = CIFilter.highlightShadowAdjust(); f.inputImage = img
            f.highlightAmount = Float(1 - max(0, -a.highlights) / 100 * 0.9 + max(0, a.highlights) / 100 * 0.0)
            f.shadowAmount = Float(a.shadows / 100)
            img = f.outputImage ?? img
            if a.highlights > 0 { let e = CIFilter.exposureAdjust(); e.inputImage = img; e.ev = Float(a.highlights / 100 * 0.35); img = e.outputImage ?? img }
        }
        if a.brightness != 0 || a.contrast != 0 || a.saturation != 0 {
            let f = CIFilter.colorControls(); f.inputImage = img
            f.brightness = Float(a.brightness / 100 * 0.3)
            f.contrast = Float(1 + a.contrast / 100 * 0.5)
            f.saturation = Float(1 + a.saturation / 100)
            img = f.outputImage ?? img
        }
        if a.vibrance != 0 { let f = CIFilter.vibrance(); f.inputImage = img; f.amount = Float(a.vibrance / 100); img = f.outputImage ?? img }
        if a.temperature != 0 || a.tint != 0 {
            let f = CIFilter.temperatureAndTint(); f.inputImage = img
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 - a.temperature * 30, y: a.tint)
            img = f.outputImage ?? img
        }
        if a.gamma != 0 { let f = CIFilter.gammaAdjust(); f.inputImage = img; f.power = Float(pow(2, -a.gamma / 100)); img = f.outputImage ?? img }
        if a.sharpness != 0 { let f = CIFilter.sharpenLuminance(); f.inputImage = img; f.sharpness = Float(a.sharpness / 100); img = f.outputImage ?? img }
        return img.cropped(to: input.extent)
    }

    static func adjust(_ image: CGImage, _ a: PhotoAdjustments) -> CGImage? {
        let out = adjust(CIImage(cgImage: image), a)
        return ci.createCGImage(out, from: out.extent, format: .RGBA8, colorSpace: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!)
    }

    // MARK: Annotation

    static func annotate(_ image: CGImage, shapes: [AnnoShape]) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = context(w, h) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Draw in top-left coordinates to match the editor.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        let size = CGSize(width: w, height: h)
        for s in shapes { draw(s, in: ctx, size: size) }
        return ctx.makeImage()
    }

    static func draw(_ s: AnnoShape, in ctx: CGContext, size: CGSize) {
        let pts = s.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        guard let first = pts.first else { return }
        let lw = max(1, s.width * min(size.width, size.height))
        ctx.saveGState()
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.setStrokeColor(s.color.cg); ctx.setFillColor(s.color.cg)
        ctx.setLineWidth(lw)
        let last = pts.last ?? first
        switch s.kind {
        case .pen:
            ctx.addLines(between: pts); ctx.strokePath()
        case .highlight:
            ctx.setBlendMode(.multiply)
            ctx.setStrokeColor(s.color.cg.copy(alpha: 0.45) ?? s.color.cg)
            ctx.setLineWidth(lw * 3.2); ctx.setLineCap(.square)
            ctx.addLines(between: pts); ctx.strokePath()
        case .rect:
            ctx.stroke(CGRect(p1: first, p2: last), width: lw)
        case .ellipse:
            ctx.strokeEllipse(in: CGRect(p1: first, p2: last))
        case .arrow:
            let angle = atan2(last.y - first.y, last.x - first.x)
            let head = max(lw * 4.2, 10)
            let base = CGPoint(x: last.x - cos(angle) * head * 0.8, y: last.y - sin(angle) * head * 0.8)
            ctx.move(to: first); ctx.addLine(to: base); ctx.strokePath()
            ctx.move(to: last)
            ctx.addLine(to: CGPoint(x: last.x - cos(angle - 0.45) * head, y: last.y - sin(angle - 0.45) * head))
            ctx.addLine(to: CGPoint(x: last.x - cos(angle + 0.45) * head, y: last.y - sin(angle + 0.45) * head))
            ctx.closePath(); ctx.fillPath()
        case .text:
            let fontSize = lw * 7
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: NSColor(cgColor: s.color.cg) ?? .black,
            ]
            let str = NSAttributedString(string: s.text.isEmpty ? "Text" : s.text, attributes: attrs)
            let line = CTLineCreateWithAttributedString(str)
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            ctx.textPosition = CGPoint(x: first.x, y: first.y + fontSize * 0.8)
            CTLineDraw(line, ctx)
        }
        ctx.restoreGState()
    }

    // MARK: Redaction

    static func redact(_ image: CGImage, boxes: [CGRect], mode: RedactMode) -> CGImage? {
        let base = CIImage(cgImage: image)
        let W = CGFloat(image.width), H = CGFloat(image.height)
        var out = base
        for n in boxes {
            // CoreImage uses bottom-left origin.
            let r = CGRect(x: n.minX * W, y: (1 - n.maxY) * H, width: n.width * W, height: n.height * H).integral
            let patch: CIImage
            switch mode {
            case .solid:
                patch = CIImage(color: CIColor(red: 0.07, green: 0.07, blue: 0.08)).cropped(to: r)
            case .blur:
                let radius = max(12, min(r.width, r.height) * 0.22)
                patch = base.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: r)
            case .pixelate:
                let f = CIFilter.pixellate(); f.inputImage = base.clampedToExtent()
                f.scale = Float(max(10, min(r.width, r.height) / 6)); f.center = CGPoint(x: r.minX, y: r.minY)
                patch = (f.outputImage ?? base).cropped(to: r)
            }
            out = patch.composited(over: out)
        }
        return ci.createCGImage(out.cropped(to: base.extent), from: base.extent)
    }

    // MARK: Add background

    /// Foreground instance masks need macOS 14. Photo mode explains this and stays off on earlier systems.
    static var canLiftSubject: Bool {
        if #available(macOS 14, *) { return true }
        return false
    }

    /// Cuts the main subject out with Vision. Returns the subject on a transparent canvas, same size as `image`.
    /// Returns nil on macOS 13 and earlier, where the request does not exist.
    static func liftSubject(_ image: CGImage) throws -> CGImage? {
        guard #available(macOS 14, *) else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
        let mask = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        let maskImage = CIImage(cvPixelBuffer: mask)
        let src = CIImage(cgImage: image)
        let sx = src.extent.width / maskImage.extent.width, sy = src.extent.height / maskImage.extent.height
        let f = CIFilter.blendWithMask()
        f.inputImage = src
        f.backgroundImage = CIImage.empty()
        f.maskImage = maskImage.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        guard let out = f.outputImage else { return nil }
        return ci.createCGImage(out, from: src.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }

    /// Corner radius of a standard macOS window, in points.
    static let windowCornerPoints = 16.0

    /// Composes the final picture. `subject` is the lifted cut-out when the style lifts the subject.
    static func renderBackground(image: CGImage, subject: CGImage?, style: BGStyle, customImage: CGImage? = nil) -> CGImage? {
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        let base = style.screenshot ? iw : max(iw, ih)
        let pad = style.padding * base
        var cw = iw + pad * 2, ch = ih + pad * 2
        if let r = style.ratio {
            if cw / ch < r { cw = ch * r } else { ch = cw / r }
        }
        let W = Int(cw.rounded()), H = Int(ch.rounded())
        guard let ctx = context(W, H) else { return nil }
        let canvas = CGRect(x: 0, y: 0, width: W, height: H)
        let fg = CGRect(x: ((CGFloat(W) - iw) / 2).rounded(), y: ((CGFloat(H) - ih) / 2).rounded(), width: iw, height: ih)
        var darkBackdrop = false

        switch style.fill {
        case .none: break
        case .backdrop(let b):
            darkBackdrop = b.isDark
            b.draw(in: ctx, rect: canvas, grain: style.grain, matching: b == .match ? Backdrop.dominantColours(image) : [])
        case .solid(let c): ctx.setFillColor(c.cg); ctx.fill(canvas)
        case .gradient(let a, let b):
            let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [a.cg, b.cg] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(H)), end: CGPoint(x: CGFloat(W), y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case .blur:
            // Blur a small copy: same look, a fraction of the cost.
            let k = min(1, 360 / max(iw, ih))
            let small = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: k, y: k))
            let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: Double(max(iw, ih) * k) * 0.035).cropped(to: small.extent)
            if let b = ci.createCGImage(blurred, from: blurred.extent) { ctx.interpolationQuality = .high; drawFill(b, in: canvas, ctx: ctx) }
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.08)); ctx.fill(canvas)
        case .image:
            if let customImage { drawFill(customImage, in: canvas, ctx: ctx) }
        }

        let strength = style.shadow * base
        if style.liftSubject, let subject {
            ctx.saveGState()
            if strength > 0 { ctx.setShadow(offset: CGSize(width: 0, height: -strength * 0.35), blur: strength, color: CGColor(gray: 0, alpha: 0.38)) }
            ctx.draw(subject, in: fg)
            ctx.restoreGState()
            return ctx.makeImage()
        }

        let radius = min(style.corners * base, min(iw, ih) / 2)
        let path = CGPath(roundedRect: fg, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if strength > 0 {
            drawLayeredShadow(ctx, canvas: canvas.size, rect: fg, radius: radius, strength: strength, darkBackdrop: darkBackdrop)
        }
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        ctx.interpolationQuality = .none     // 1:1 pixels keep text crisp
        ctx.draw(image, in: fg)
        if style.screenshot && style.border {
            let lw = max(1, iw / 1440)
            ctx.addPath(CGPath(roundedRect: fg.insetBy(dx: lw / 2, dy: lw / 2), cornerWidth: max(0, radius - lw / 2), cornerHeight: max(0, radius - lw / 2), transform: nil))
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.16)); ctx.setLineWidth(lw); ctx.strokePath()
        }
        ctx.restoreGState()
        if style.screenshot && style.border {
            let lw = max(1, iw / 1440)
            ctx.addPath(CGPath(roundedRect: fg.insetBy(dx: -lw / 2, dy: -lw / 2), cornerWidth: radius + lw / 2, cornerHeight: radius + lw / 2, transform: nil))
            ctx.setStrokeColor(CGColor(gray: 0, alpha: darkBackdrop ? 0.35 : 0.10)); ctx.setLineWidth(lw); ctx.strokePath()
        }
        return ctx.makeImage()
    }

    /// Three-layer shadow (ambient, key, contact). The wide soft layers are drawn at quarter size and scaled up,
    /// which looks identical and keeps the preview fast; the tight contact layer is drawn at full size.
    static func drawLayeredShadow(_ ctx: CGContext, canvas: CGSize, rect: CGRect, radius: CGFloat, strength: CGFloat, darkBackdrop: Bool) {
        let key = String(format: "sh|%.0fx%.0f|%.1f,%.1f,%.1f,%.1f|%.2f|%.2f|%d", canvas.width, canvas.height, rect.minX, rect.minY, rect.width, rect.height,
                         radius, strength, darkBackdrop ? 1 : 0)
        let full = CGRect(origin: .zero, size: canvas)
        if let hit = RenderCache.shared[key] { ctx.draw(hit, in: full); return }
        let boost: CGFloat = darkBackdrop ? 1.7 : 1
        // Wide layers (ambient, key) at 1/8 size, tight contact layer at 1/4: blurred shapes scale up cleanly.
        func layer(_ k: CGFloat, _ specs: [(blur: CGFloat, dy: CGFloat, a: CGFloat)]) -> CGImage? {
            guard let s = context(Int(canvas.width * k) + 1, Int(canvas.height * k) + 1) else { return nil }
            let r = CGRect(x: rect.minX * k, y: rect.minY * k, width: rect.width * k, height: rect.height * k)
            let p = CGPath(roundedRect: r, cornerWidth: radius * k, cornerHeight: radius * k, transform: nil)
            for l in specs {
                s.saveGState()
                s.setShadow(offset: CGSize(width: 0, height: -strength * l.dy * k), blur: max(0.6, strength * l.blur * k),
                            color: CGColor(gray: 0, alpha: min(0.9, l.a * boost)))
                s.addPath(p); s.setFillColor(CGColor(gray: 0, alpha: 1)); s.fillPath()
                s.restoreGState()
            }
            s.setBlendMode(.clear); s.addPath(p); s.fillPath()
            return s.makeImage()
        }
        guard let out = context(Int(canvas.width), Int(canvas.height)) else { return }
        out.interpolationQuality = .medium
        if let wide = layer(0.125, [(1.6, 0.42, 0.13), (0.65, 0.16, 0.17)]) {
            out.draw(wide, in: CGRect(x: 0, y: 0, width: CGFloat(wide.width) / 0.125, height: CGFloat(wide.height) / 0.125))
        }
        if let tight = layer(0.25, [(0.06, 0.025, 0.22)]) {
            out.draw(tight, in: CGRect(x: 0, y: 0, width: CGFloat(tight.width) / 0.25, height: CGFloat(tight.height) / 0.25))
        }
        // Keep the area under the screenshot clear so scaled-up edges never darken it.
        out.setBlendMode(.clear)
        out.addPath(CGPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerWidth: radius, cornerHeight: radius, transform: nil)); out.fillPath()
        guard let img = out.makeImage() else { return }
        RenderCache.shared[key] = img
        ctx.draw(img, in: full)
    }

    private static func drawFill(_ img: CGImage, in rect: CGRect, ctx: CGContext) {
        let s = max(rect.width / CGFloat(img.width), rect.height / CGFloat(img.height))
        let w = CGFloat(img.width) * s, h = CGFloat(img.height) * s
        ctx.draw(img, in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
    }

    // MARK: Screenshots

    /// A file named like a macOS screenshot, or one Spotlight marks as a screen capture.
    static func isScreenshot(_ url: URL) -> Bool {
        let n = url.lastPathComponent.lowercased()
        if n.hasPrefix("screenshot") || n.hasPrefix("screen shot") { return true }
        if let item = MDItemCreateWithURL(nil, url as CFURL),
           let v = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? Bool { return v }
        return false
    }

    /// 2 for Retina captures (144 dpi), 1 otherwise.
    static func pixelScale(_ url: URL) -> Double {
        let props = (try? ImageEngine.decode(url, maxPixel: 1))?.properties ?? [:]
        let dpi = props[kCGImagePropertyDPIWidth] as? Double ?? 72
        return max(1, (dpi / 72).rounded())
    }

    /// Window captures carry macOS's own shadow in a transparent margin. Crops to the window body and
    /// measures its corner radius (as a share of the width), so our frame matches it exactly.
    static func trimCaptureShadow(_ img: CGImage) -> (image: CGImage, corner: Double?) {
        switch img.alphaInfo { case .none, .noneSkipLast, .noneSkipFirst: return (img, nil); default: break }
        let w = img.width, h = img.height
        guard let ctx = context(w, h), let data = ctx.data else { return (img, nil) }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let p = data.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * h)
        let bpr = ctx.bytesPerRow
        @inline(__always) func a(_ x: Int, _ y: Int) -> UInt8 { p[y * bpr + x * 4 + 3] }
        // Scan the middle row and column for the opaque body; window bodies are solid there.
        let my = h / 2, mx = w / 2
        guard let x0 = (0..<w).first(where: { a($0, my) >= 250 }), let x1 = (0..<w).last(where: { a($0, my) >= 250 }),
              let y0 = (0..<h).first(where: { a(mx, $0) >= 250 }), let y1 = (0..<h).last(where: { a(mx, $0) >= 250 }) else { return (img, nil) }
        let hasMargin = x0 > 2 || y0 > 2 || x1 < w - 3 || y1 < h - 3
        // No shadow margin: still a window capture if its corners are transparent (captured without shadow).
        if !hasMargin && a(0, 0) >= 128 { return (img, nil) }
        let box = hasMargin ? CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1) : CGRect(x: 0, y: 0, width: w, height: h)
        guard box.width > 32, box.height > 32, let cropped = hasMargin ? img.cropping(to: box) : img else { return (img, nil) }
        // Along the top-left diagonal, the arc of radius r starts at t = r(1 - 1/sqrt 2).
        var t = 0
        while t < Int(box.width / 2), t < Int(box.height / 2), a(x0 + t, y0 + t) < 128 { t += 1 }
        let radius = Double(t) / (1 - 1 / 2.0.squareRoot())
        return (cropped, radius > 2 ? radius / Double(box.width) : nil)
    }

    /// Full-resolution Add Background job, shared by the panel and the test hooks.
    static func addBackground(_ src: URL, style st: BGStyle, ctx: JobContext) throws -> URL {
        var img = try full(src)
        ctx.report(0.15)
        if st.screenshot { img = trimCaptureShadow(img).image }
        let sub = st.liftSubject && !st.screenshot ? try liftSubject(img) : nil
        ctx.report(0.6)
        var customImage: CGImage?
        if case .image(let url) = st.fill { customImage = try? ImageEngine.decode(url, maxPixel: 6000).image }
        guard let out = renderBackground(image: img, subject: sub, style: st, customImage: customImage) else {
            throw YuzuError.writeFailed(src.lastPathComponent)
        }
        ctx.report(0.85)
        // Screenshots stay PNG at their own scale (144 dpi for Retina), so they look crisp when shared.
        return try save(out, for: src, suffix: FileTool.addBackground.suffix, needsAlpha: styleNeedsAlpha(st),
                        forcePNG: st.screenshot, dpi: st.screenshot ? 72 * pixelScale(src) : nil, settings: ctx.settings)
    }

    static func styleNeedsAlpha(_ s: BGStyle) -> Bool {
        if case .none = s.fill { return true }
        return false
    }
}

extension CGRect {
    init(p1: CGPoint, p2: CGPoint) {
        self.init(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p1.x - p2.x), height: abs(p1.y - p2.y))
    }
}
