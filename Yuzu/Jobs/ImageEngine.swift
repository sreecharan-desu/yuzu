import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

struct ImageSettings: Sendable {
    var quality: Double
    var compressQuality: Double
    var preserveMetadata: Bool
}

/// Native image conversions through ImageIO. WebP falls back to Homebrew's cwebp.
enum ImageEngine {
    struct Decoded {
        let image: CGImage
        let properties: [CFString: Any]
    }

    static func decode(_ url: URL, maxPixel: Int? = nil) throws -> Decoded {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(src) > 0 else { throw YuzuError.unreadable(url.lastPathComponent) }
        var props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]) ?? [:]
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        // Creating the CGImage is lazy (header only), so reading its alpha info costs no pixel decode.
        let lazy = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        if props[kCGImagePropertyHasAlpha] == nil, let lazy {
            // Thumbnails come back premultiplied even for opaque sources, so record the source's real alpha.
            props[kCGImagePropertyHasAlpha] = hasAlpha(lazy)
        }
        let fullSize = maxPixel == nil || maxPixel! >= max(w, h)
        if fullSize, orientation == 1,
           let img = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
            // Fast path: one native decode at full size, no resampling pass and no forced premultiplied alpha.
            return Decoded(image: img, properties: props)
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // bake in EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel ?? max(w, h, 1),
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            throw YuzuError.unreadable(url.lastPathComponent)
        }
        return Decoded(image: img, properties: props)
    }

    /// Metadata to carry into the new file, with orientation reset because pixels are already upright.
    static func carriedProperties(_ props: [CFString: Any], keep: Bool) -> [CFString: Any] {
        var out: [CFString: Any] = [:]
        // Read-only hint used by the PDF writer to know the source is opaque (ignored by ImageIO on write).
        if let a = props[kCGImagePropertyHasAlpha] { out[kCGImagePropertyHasAlpha] = a }
        if keep {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary,
                        kCGImagePropertyTIFFDictionary, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
                if let v = props[key] { out[key] = v }
            }
            if var tiff = out[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                out[kCGImagePropertyTIFFDictionary] = tiff
            }
        }
        out[kCGImagePropertyOrientation] = 1
        return out
    }

    static func flattened(_ image: CGImage) -> CGImage {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    static func write(_ image: CGImage, as format: ImageFormat, to dest: URL,
                      properties: [CFString: Any], quality: Double?) throws {
        switch format {
        case .pdf:
            try writePDF(image, to: dest, properties: properties)
        case .webp where !ImageFormat.imageIOWritable.contains(format.utType.identifier):
            try writeWebPWithCwebp(image, to: dest, quality: quality ?? 0.85)
        default:
            // Skip the flatten pass when the source is known to be opaque (its alpha channel is all 1).
            let sourceOpaque = (properties[kCGImagePropertyHasAlpha] as? Bool) == false
            let img = (!format.supportsAlpha && hasAlpha(image) && !sourceOpaque) ? flattened(image) : image
            guard let d = CGImageDestinationCreateWithURL(dest as CFURL, format.utType.identifier as CFString, 1, nil) else {
                throw YuzuError.writeFailed(dest.lastPathComponent)
            }
            var p = properties
            p[kCGImagePropertyHasAlpha] = nil   // read-side hint only; never let it strip alpha on write
            if let q = quality, format.isLossy { p[kCGImageDestinationLossyCompressionQuality] = q }
            if format == .png {
                // The "up" row filter measured about 40% faster than ImageIO's adaptive default and smaller files.
                p[kCGImagePropertyPNGDictionary] = [kCGImagePropertyPNGCompressionFilter: 0x20]
            }
            CGImageDestinationAddImage(d, img, p as CFDictionary)
            guard CGImageDestinationFinalize(d) else {
                try? FileManager.default.removeItem(at: dest)
                throw YuzuError.writeFailed(dest.lastPathComponent)
            }
        }
    }

    private static func writePDF(_ image: CGImage, to dest: URL, properties: [CFString: Any]) throws {
        let dpi = (properties[kCGImagePropertyDPIWidth] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? 144
        var box = CGRect(x: 0, y: 0, width: Double(image.width) * 72 / dpi, height: Double(image.height) * 72 / dpi)
        guard let ctx = CGContext(dest as CFURL, mediaBox: &box, nil) else { throw YuzuError.writeFailed(dest.lastPathComponent) }
        ctx.beginPDFPage(nil)
        let opaque = !hasAlpha(image) || (properties[kCGImagePropertyHasAlpha] as? Bool) == false
        ctx.draw(opaque ? jpegBacked(image) : image, in: box)
        ctx.endPDFPage()
        ctx.closePDF()
    }

    /// Opaque photos are embedded as JPEG (DCT) so PDFs stay small; images with alpha stay lossless.
    static func jpegBacked(_ image: CGImage) -> CGImage {
        let data = NSMutableData()
        guard let d = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return image }
        CGImageDestinationAddImage(d, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(d), let provider = CGDataProvider(data: data),
              let jpeg = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return image }
        return jpeg
    }

    private static func writeWebPWithCwebp(_ image: CGImage, to dest: URL, quality: Double) throws {
        guard let cwebp = ToolLocator.cwebp else { throw YuzuError.missingTool("webp") }
        // Uncompressed TIFF is the cheapest hand-off format (a PNG encode cost seconds on large photos).
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tiff")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try write(image, as: .tiff, to: tmp, properties: [:], quality: nil)
        try ToolLocator.run(cwebp, ["-quiet", "-mt", "-q", String(Int(quality * 100)), "-metadata", "icc", tmp.path, "-o", dest.path])
    }

    /// cwebp reads upright JPEG and PNG files itself, so those skip the decode entirely.
    private static func directCwebp(_ src: URL, to dest: URL, quality: Double) -> Bool {
        guard let cwebp = ToolLocator.cwebp, let f = ImageFormat.of(src), f == .jpeg || f == .png,
              let s = CGImageSourceCreateWithURL(src as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any],
              (p[kCGImagePropertyOrientation] as? Int ?? 1) == 1 else { return false }
        let meta = "icc"
        return (try? ToolLocator.run(cwebp, ["-quiet", "-mt", "-q", String(Int(quality * 100)), "-metadata", meta, src.path, "-o", dest.path])) != nil
    }

    // MARK: - Jobs

    static func convert(_ src: URL, to format: ImageFormat, settings: ImageSettings) throws -> URL {
        let dest = OutputNamer.destination(for: src, ext: format.ext)
        if format == .webp, !ImageFormat.imageIOWritable.contains(format.utType.identifier),
           directCwebp(src, to: dest, quality: settings.quality) {
            return dest
        }
        let decoded = try decode(src)
        try write(decoded.image, as: format, to: dest,
                  properties: carriedProperties(decoded.properties, keep: settings.preserveMetadata),
                  quality: settings.quality)
        return dest
    }

    static func apply(_ tool: ImageTool, to src: URL, settings: ImageSettings) throws -> URL {
        let format = ImageFormat.of(src) ?? .png
        let outFormat: ImageFormat = format.isAvailable && format != .pdf ? format : .png
        let dest = OutputNamer.destination(for: src, ext: outFormat.ext, suffix: tool.suffix)

        if tool == .removeMetadata, let exiftool = ToolLocator.exiftool {
            // Lossless: copy the file without any metadata, keeping the original pixels.
            try ToolLocator.run(exiftool, ["-q", "-all=", "-tagsfromfile", "@", "-orientation", "-icc_profile", "-o", dest.path, src.path])
            return dest
        }

        var decoded = try decode(src, maxPixel: nil)
        var image = decoded.image
        var props = carriedProperties(decoded.properties, keep: settings.preserveMetadata)
        var quality = settings.quality

        switch tool {
        case .compress:
            quality = settings.compressQuality
            props = carriedProperties(decoded.properties, keep: false)
            if !outFormat.isLossy {
                // Lossless formats: compress by limiting the long edge to 2560 px.
                let longEdge = max(image.width, image.height)
                if longEdge > 2560 { decoded = try decode(src, maxPixel: 2560); image = decoded.image }
            }
        case .halfSize:
            let longEdge = max(image.width, image.height)
            decoded = try decode(src, maxPixel: max(1, longEdge / 2))
            image = decoded.image
        case .rotate:
            image = try transform(image, rotate: true)
        case .flip:
            image = try transform(image, rotate: false)
        case .removeMetadata:
            props = carriedProperties(decoded.properties, keep: false)
            quality = max(quality, 0.95)
        }
        try write(image, as: outFormat, to: dest, properties: props, quality: quality)
        return dest
    }

    private static func transform(_ image: CGImage, rotate: Bool) throws -> CGImage {
        let w = image.width, h = image.height
        let (ow, oh) = rotate ? (h, w) : (w, h)
        guard let ctx = CGContext(data: nil, width: ow, height: oh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw YuzuError.writeFailed("image")
        }
        if rotate {
            // 90 degrees clockwise.
            ctx.translateBy(x: 0, y: CGFloat(oh))
            ctx.rotate(by: -.pi / 2)
        } else {
            ctx.translateBy(x: CGFloat(ow), y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { throw YuzuError.writeFailed("image") }
        return out
    }
}
