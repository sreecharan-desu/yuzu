import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// RGBA color that can cross threads.
struct RGBA: Hashable, Sendable {
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

enum BGFill: Hashable, Sendable {
    case none
    case solid(RGBA)
    case gradient(RGBA, RGBA)
    case blur
    case image(URL)
}

struct BGStyle: Equatable, Sendable {
    var liftSubject = true
    var fill: BGFill = .gradient(RGBA(r: 1.0, g: 0.82, b: 0.30), RGBA(r: 0.98, g: 0.45, b: 0.18))
    var padding = 0.08          // fraction of the image's longer side
    var corners = 0.03          // fraction of the image's longer side (frame mode)
    var shadow = 0.04
    var ratio: Double? = nil    // width / height, nil = auto
}

enum ImageEdit {
    static let ci = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: false])

    // MARK: Saving

    /// Writes an edited image next to the source, keeping its format (PNG when transparency must survive).
    static func save(_ image: CGImage, for src: URL, suffix: String, needsAlpha: Bool = false, settings: ImageSettings) throws -> URL {
        var format = ImageFormat.of(src) ?? .png
        if !format.isAvailable || format == .pdf || format == .gif { format = .png }
        if needsAlpha { format = .png }   // cut-outs are always transparent PNGs
        let dest = OutputNamer.destination(for: src, ext: format.ext, suffix: suffix)
        let decoded = try? ImageEngine.decode(src, maxPixel: 1)
        let props = ImageEngine.carriedProperties(decoded?.properties ?? [:], keep: settings.preserveMetadata)
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

    /// Cuts the main subject out with Vision. Returns the subject on a transparent canvas, same size as `image`.
    static func liftSubject(_ image: CGImage) throws -> CGImage? {
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

    /// Composes the final picture. `subject` is the lifted cut-out when the style lifts the subject.
    static func renderBackground(image: CGImage, subject: CGImage?, style: BGStyle, customImage: CGImage? = nil) -> CGImage? {
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        let long = max(iw, ih)
        let pad = style.padding * long
        var cw = iw + pad * 2, ch = ih + pad * 2
        if let r = style.ratio {
            if cw / ch < r { cw = ch * r } else { ch = cw / r }
        }
        let W = Int(cw.rounded()), H = Int(ch.rounded())
        guard let ctx = context(W, H) else { return nil }
        let canvas = CGRect(x: 0, y: 0, width: W, height: H)
        let fg = CGRect(x: (CGFloat(W) - iw) / 2, y: (CGFloat(H) - ih) / 2, width: iw, height: ih)

        switch style.fill {
        case .none: break
        case .solid(let c): ctx.setFillColor(c.cg); ctx.fill(canvas)
        case .gradient(let a, let b):
            let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [a.cg, b.cg] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(H)), end: CGPoint(x: CGFloat(W), y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case .blur:
            let blurred = CIImage(cgImage: image).clampedToExtent().applyingGaussianBlur(sigma: Double(long) * 0.035)
                .cropped(to: CGRect(x: 0, y: 0, width: iw, height: ih))
            if let b = ci.createCGImage(blurred, from: blurred.extent) { drawFill(b, in: canvas, ctx: ctx) }
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.08)); ctx.fill(canvas)
        case .image:
            if let customImage { drawFill(customImage, in: canvas, ctx: ctx) }
        }

        let shadowBlur = style.shadow * long
        if style.liftSubject, let subject {
            ctx.saveGState()
            if shadowBlur > 0 { ctx.setShadow(offset: CGSize(width: 0, height: -shadowBlur * 0.35), blur: shadowBlur, color: CGColor(gray: 0, alpha: 0.38)) }
            ctx.draw(subject, in: fg)
            ctx.restoreGState()
        } else {
            let radius = min(style.corners * long, min(iw, ih) / 2)
            let path = CGPath(roundedRect: fg, cornerWidth: radius, cornerHeight: radius, transform: nil)
            if shadowBlur > 0 {
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: -shadowBlur * 0.35), blur: shadowBlur, color: CGColor(gray: 0, alpha: 0.42))
                ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0.5, alpha: 1)); ctx.fillPath()
                ctx.restoreGState()
            }
            ctx.saveGState()
            ctx.addPath(path); ctx.clip()
            ctx.draw(image, in: fg)
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    private static func drawFill(_ img: CGImage, in rect: CGRect, ctx: CGContext) {
        let s = max(rect.width / CGFloat(img.width), rect.height / CGFloat(img.height))
        let w = CGFloat(img.width) * s, h = CGFloat(img.height) * s
        ctx.draw(img, in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
    }

    /// Full-resolution Add Background job, shared by the panel and the test hooks.
    static func addBackground(_ src: URL, style st: BGStyle, ctx: JobContext) throws -> URL {
        let img = try full(src)
        ctx.report(0.15)
        let sub = st.liftSubject ? try liftSubject(img) : nil
        ctx.report(0.6)
        var customImage: CGImage?
        if case .image(let url) = st.fill { customImage = try? ImageEngine.decode(url, maxPixel: 6000).image }
        guard let out = renderBackground(image: img, subject: sub, style: st, customImage: customImage) else {
            throw YuzuError.writeFailed(src.lastPathComponent)
        }
        ctx.report(0.85)
        return try save(out, for: src, suffix: FileTool.addBackground.suffix, needsAlpha: styleNeedsAlpha(st), settings: ctx.settings)
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
