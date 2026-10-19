import AppKit
import CoreGraphics

/// Curated backgrounds drawn in code (no bitmaps shipped). Smooth content is drawn small and scaled up,
/// so any output size costs the same few milliseconds; grain is a tiled noise texture laid on top.
enum Backdrop: String, CaseIterable, Codable, Sendable, Identifiable {
    // A short, curated pack: quiet neutrals with gentle warm and cool washes. The screenshot is the hero.
    case pearl, mist, linen, haze, stone, graphite, ink
    case match

    var id: String { rawValue }

    var name: String {
        switch self {
        case .pearl: return "Pearl"
        case .mist: return "Mist"
        case .linen: return "Linen"
        case .haze: return "Haze"
        case .stone: return "Stone"
        case .graphite: return "Graphite"
        case .ink: return "Ink"
        case .match: return "Match"
        }
    }

    var isDark: Bool { [.graphite, .ink].contains(self) }

    /// Accepts current names and every name from earlier versions, so saved styles keep working.
    static func named(_ raw: String) -> Backdrop? {
        if let b = Backdrop(rawValue: raw) { return b }
        switch raw {
        case "paper", "peach", "sunset", "rose", "frostRose": return .linen
        case "cloud", "frostBlue", "ocean", "aurora": return .mist
        case "mint", "lavender", "frostSage", "lagoon": return .haze
        case "charcoal", "midnight", "dusk": return .graphite
        default: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Backdrop.named(raw) ?? .pearl
    }

    /// Base colour plus soft washes (x, y in 0...1 from top-left, radius as a share of the long side).
    /// Washes stay within a few OKLab lightness points of the base and under 0.02 chroma, so they read
    /// as light falling on a surface rather than as colour.
    struct Blob { let x, y, r: Double; let c: RGBA; var a: Double = 0.9 }

    private static func c(_ hex: UInt32, _ a: Double = 1) -> RGBA {
        RGBA(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255, a: a)
    }

    func palette(matching colours: [RGBA] = []) -> (base: RGBA, blobs: [Blob]) {
        func c(_ h: UInt32) -> RGBA { Self.c(h, 1) }
        switch self {
        case .pearl: return (c(0xF5F5F7), [Blob(x: 0.28, y: 0.08, r: 0.75, c: c(0xFFFFFF)), Blob(x: 0.92, y: 0.95, r: 0.70, c: c(0xECE8E2), a: 0.7),
                                           Blob(x: 0.02, y: 0.98, r: 0.55, c: c(0xE8ECF2), a: 0.6)])
        case .mist: return (c(0xEBEDF0), [Blob(x: 0.50, y: 0.00, r: 0.80, c: c(0xF8F9FB)), Blob(x: 0.95, y: 0.80, r: 0.65, c: c(0xDCE2EA), a: 0.7),
                                          Blob(x: 0.05, y: 0.75, r: 0.55, c: c(0xE7E5E2), a: 0.5)])
        case .linen: return (c(0xF2EFEA), [Blob(x: 0.35, y: 0.05, r: 0.75, c: c(0xFBFAF7)), Blob(x: 0.95, y: 0.95, r: 0.70, c: c(0xE7E0D5), a: 0.7),
                                           Blob(x: 0.00, y: 0.60, r: 0.50, c: c(0xF0EDE8), a: 0.5)])
        case .haze: return (c(0xE6E7E6), [Blob(x: 0.15, y: 0.10, r: 0.70, c: c(0xF4F3F0)), Blob(x: 0.90, y: 0.20, r: 0.60, c: c(0xE0E5EA), a: 0.7),
                                          Blob(x: 0.60, y: 1.00, r: 0.75, c: c(0xE4E1DA), a: 0.7)])
        case .stone: return (c(0xD9D8D5), [Blob(x: 0.30, y: 0.00, r: 0.80, c: c(0xE8E7E4)), Blob(x: 0.90, y: 1.00, r: 0.70, c: c(0xC9C8C4), a: 0.7)])
        case .graphite: return (c(0x232325), [Blob(x: 0.30, y: 0.05, r: 0.80, c: c(0x333336)), Blob(x: 0.92, y: 0.95, r: 0.70, c: c(0x18181A), a: 0.8),
                                              Blob(x: 0.05, y: 0.90, r: 0.55, c: c(0x26282C), a: 0.6)])
        case .ink: return (c(0x141415), [Blob(x: 0.40, y: 0.00, r: 0.85, c: c(0x252527)), Blob(x: 0.95, y: 1.00, r: 0.60, c: c(0x0C0C0D), a: 0.8)])
        case .match:
            let cs = colours.isEmpty ? [c(0xD9DEE6), c(0xE6E0D8), c(0xDDE3DE)] : colours
            let base = cs[0].mixed(with: cs.count > 1 ? cs[1] : cs[0], 0.5)
            let spots: [(Double, Double, Double)] = [(0.2, 0.05, 0.8), (0.95, 0.3, 0.6), (0.6, 1.0, 0.8)]
            return (base, spots.enumerated().map { i, s in Blob(x: s.0, y: s.1, r: s.2, c: cs[i % cs.count], a: 0.8) })
        }
    }

    // MARK: Drawing

    /// Draws the backdrop over `rect` of `ctx` (CG coordinates, origin bottom-left).
    func draw(in ctx: CGContext, rect: CGRect, grain: Double, matching colours: [RGBA] = []) {
        // The finished backdrop (scaled up, grain applied) is cached per size, so slider changes that keep the
        // canvas size, and switching back and forth between backdrops, cost a single 1:1 draw.
        let key = "bd|\(rawValue)|\(Int(rect.width))x\(Int(rect.height))|\(String(format: "%.2f", grain))|\(colours.map { "\($0.r),\($0.g),\($0.b)" }.joined())"
        if let hit = RenderCache.shared[key] { ctx.draw(hit, in: rect); return }
        guard let full = ImageEdit.context(Int(rect.width), Int(rect.height)) else { return }
        let r = CGRect(x: 0, y: 0, width: full.width, height: full.height)
        if let small = Self.smallImage(self, aspect: r.width / max(r.height, 1), matching: colours) {
            full.interpolationQuality = .medium     // smooth content: bilinear is indistinguishable and much cheaper
            full.draw(small, in: r)
        }
        let amount = grain * (isDark ? 0.8 : 1)
        if amount > 0.01 { Self.drawGrain(in: full, rect: r, amount: amount) }
        guard let img = full.makeImage() else { return }
        RenderCache.shared[key] = img
        ctx.draw(img, in: rect)
    }

    /// Low-resolution render of the smooth part; cached per style and aspect.
    nonisolated(unsafe) private static var cache: [String: CGImage] = [:]
    private static let lock = NSLock()

    static func smallImage(_ b: Backdrop, aspect: Double, matching colours: [RGBA]) -> CGImage? {
        let key = "\(b.rawValue)|\(String(format: "%.3f", aspect))|\(colours.map { "\($0.r),\($0.g),\($0.b)" }.joined())"
        lock.lock(); if let hit = cache[key] { lock.unlock(); return hit }; lock.unlock()
        let long = 320.0
        let w = aspect >= 1 ? long : long * aspect, h = aspect >= 1 ? long / aspect : long
        guard let ctx = ImageEdit.context(Int(w.rounded()), Int(h.rounded())) else { return nil }
        let r = CGRect(x: 0, y: 0, width: CGFloat(ctx.width), height: CGFloat(ctx.height))
        let L = max(r.width, r.height)
        let (base, blobs) = b.palette(matching: colours)
        ctx.setFillColor(base.cg); ctx.fill(r)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func blob(_ x: Double, _ y: Double, _ rad: Double, _ col: RGBA, _ alpha: Double, hard: Double = 0) {
            let center = CGPoint(x: x * r.width, y: (1 - y) * r.height)
            var c0 = col; c0.a = alpha
            var c1 = col; c1.a = 0
            let g = hard > 0
                ? CGGradient(colorsSpace: space, colors: [c0.cg, c0.cg, c1.cg] as CFArray, locations: [0, CGFloat(hard), 1])!
                : CGGradient(colorsSpace: space, colors: [c0.cg, c1.cg] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(rad) * L, options: [])
        }
        for bl in blobs { blob(bl.x, bl.y, bl.r, bl.c, bl.a) }
        // A barely-there top light, like a softbox above the desk.
        let g = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: b.isDark ? 0.03 : 0.10), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: r.height), end: CGPoint(x: 0, y: r.height * 0.4), options: [])
        guard let img = ctx.makeImage() else { return nil }
        lock.lock(); if cache.count > 64 { cache.removeAll() }; cache[key] = img; lock.unlock()
        return img
    }

    /// 256 px noise tile, made once with a fixed seed so outputs are repeatable. Light and dark specks are
    /// stored as premultiplied white or black with alpha, so drawing it is a plain (fast) source-over blend.
    static let grainTile: CGImage? = {
        let n = 256
        var px = [UInt8](repeating: 0, count: n * n * 4)
        var s: UInt64 = 0x9E3779B97F4A7C15
        for i in 0..<(n * n) {
            s ^= s << 13; s ^= s >> 7; s ^= s << 17
            // Sum of two uniforms gives a softer, film-like distribution around zero.
            let v = (Int(s & 0xFF) + Int((s >> 8) & 0xFF)) / 2 - 128
            let a = UInt8(min(255, abs(v) * 2))
            let c: UInt8 = v > 0 ? a : 0
            px[i * 4] = c; px[i * 4 + 1] = c; px[i * 4 + 2] = c; px[i * 4 + 3] = a
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }()

    static func drawGrain(in ctx: CGContext, rect: CGRect, amount: Double) {
        guard let tile = grainTile else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.setAlpha(CGFloat(min(1, amount) * 0.16))
        ctx.interpolationQuality = .none
        ctx.draw(tile, in: CGRect(x: rect.minX, y: rect.minY, width: 256, height: 256), byTiling: true)
        ctx.restoreGState()
    }

    // MARK: Dominant colours

    /// Up to three distinct colours from the image, softened into a quiet backdrop range.
    static func dominantColours(_ image: CGImage) -> [RGBA] {
        let n = 32
        guard let ctx = ImageEdit.context(n, n) else { return [] }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
        guard let data = ctx.data else { return [] }
        let p = data.bindMemory(to: UInt8.self, capacity: n * n * 4)
        var bins: [Int: (count: Double, r: Double, g: Double, b: Double)] = [:]
        for i in 0..<(n * n) {
            let a = Double(p[i * 4 + 3]) / 255
            guard a > 0.5 else { continue }
            let r = Double(p[i * 4]) / 255 / a, g = Double(p[i * 4 + 1]) / 255 / a, b = Double(p[i * 4 + 2]) / 255 / a
            let mx = max(r, g, b), mn = min(r, g, b)
            let sat = mx > 0 ? (mx - mn) / mx : 0
            let key = (Int(r * 7.99) << 6) | (Int(g * 7.99) << 3) | Int(b * 7.99)
            let w = 0.15 + sat * 2.2
            var e = bins[key] ?? (0, 0, 0, 0)
            e.count += w; e.r += r * w; e.g += g * w; e.b += b * w
            bins[key] = e
        }
        var picks: [RGBA] = []
        for e in bins.values.sorted(by: { $0.count > $1.count }) {
            let c = RGBA(r: e.r / e.count, g: e.g / e.count, b: e.b / e.count)
            if picks.allSatisfy({ $0.distance(to: c) > 0.28 }) { picks.append(c) }
            if picks.count == 3 { break }
        }
        if picks.isEmpty { return [] }
        while picks.count < 3 { picks.append(picks[picks.count - 1].hueShifted(0.08)) }
        return picks.map { $0.backdropTone() }
    }
}

extension RGBA {
    func mixed(with o: RGBA, _ t: Double) -> RGBA { RGBA(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t) }
    func shaded(_ k: Double) -> RGBA { RGBA(r: r * k, g: g * k, b: b * k) }
    func distance(to o: RGBA) -> Double { ((r - o.r) * (r - o.r) + (g - o.g) * (g - o.g) + (b - o.b) * (b - o.b)).squareRoot() }
    var hsb: (h: Double, s: Double, b: Double) {
        let c = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        return (Double(c.hueComponent), Double(c.saturationComponent), Double(c.brightnessComponent))
    }
    static func hsb(_ h: Double, _ s: Double, _ b: Double) -> RGBA {
        let c = NSColor(hue: CGFloat(h), saturation: CGFloat(s), brightness: CGFloat(b), alpha: 1).usingColorSpace(.sRGB)!
        return RGBA(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }
    func hueShifted(_ d: Double) -> RGBA { let x = hsb; return .hsb((x.h + d).truncatingRemainder(dividingBy: 1), max(x.s, 0.3), x.b) }
    /// Keeps saturation moderate and brightness mid-high so the screenshot stays the hero.
    func backdropTone() -> RGBA {
        let x = hsb
        // Quiet: low saturation, high value, so the backdrop whispers the image's colour instead of shouting it.
        if x.s < 0.06 { return .hsb(x.h, x.s, min(max(x.b, 0.80), 0.95)) }
        return .hsb(x.h, min(max(x.s * 0.4, 0.06), 0.16), min(max(x.b, 0.86), 0.95))
    }
}

/// Small thread-safe cache for render intermediates (backdrops, shadows), newest kept.
final class RenderCache: @unchecked Sendable {
    static let shared = RenderCache()
    private let lock = NSLock()
    private var items: [(String, CGImage)] = []
    private let limit = 8
    subscript(key: String) -> CGImage? {
        get { lock.lock(); defer { lock.unlock() }; return items.first { $0.0 == key }?.1 }
        set {
            lock.lock(); defer { lock.unlock() }
            items.removeAll { $0.0 == key }
            if let v = newValue { items.insert((key, v), at: 0); if items.count > limit { items.removeLast() } }
        }
    }
}
