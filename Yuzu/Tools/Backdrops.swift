import AppKit
import CoreGraphics

/// Curated backgrounds drawn in code (no bitmaps shipped). Smooth content is drawn small and scaled up,
/// so any output size costs the same few milliseconds; grain is a tiled noise texture laid on top.
enum Backdrop: String, CaseIterable, Codable, Sendable, Identifiable {
    case sunset, aurora, ocean, mint, lavender, peach, midnight, graphite
    case dusk, lagoon, rose
    case frostBlue, frostRose, frostSage
    case paper, cloud, stone, charcoal, ink
    case match

    var id: String { rawValue }

    var name: String {
        switch self {
        case .sunset: return "Sunset"
        case .aurora: return "Aurora"
        case .ocean: return "Ocean"
        case .mint: return "Mint"
        case .lavender: return "Lavender"
        case .peach: return "Peach"
        case .midnight: return "Midnight"
        case .graphite: return "Graphite"
        case .dusk: return "Dusk Bokeh"
        case .lagoon: return "Lagoon Bokeh"
        case .rose: return "Rose Bokeh"
        case .frostBlue: return "Frost Blue"
        case .frostRose: return "Frost Rose"
        case .frostSage: return "Frost Sage"
        case .paper: return "Paper"
        case .cloud: return "Cloud"
        case .stone: return "Stone"
        case .charcoal: return "Charcoal"
        case .ink: return "Ink"
        case .match: return "Match Colours"
        }
    }

    enum Kind { case mesh, orbs, frost, neutral }

    var kind: Kind {
        switch self {
        case .dusk, .lagoon, .rose: return .orbs
        case .frostBlue, .frostRose, .frostSage: return .frost
        case .paper, .cloud, .stone, .charcoal, .ink: return .neutral
        default: return .mesh
        }
    }

    var isDark: Bool { [.midnight, .graphite, .dusk, .lagoon, .charcoal, .ink].contains(self) }

    /// Base colour plus soft blobs (x, y in 0...1 from top-left, radius as a share of the long side).
    struct Blob { let x, y, r: Double; let c: RGBA }

    private static func c(_ hex: UInt32, _ a: Double = 1) -> RGBA {
        RGBA(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255, a: a)
    }

    func palette(matching colours: [RGBA] = []) -> (base: RGBA, blobs: [Blob]) {
        func c(_ h: UInt32) -> RGBA { Self.c(h, 1) }
        switch self {
        case .sunset: return (c(0xFF8A5B), [Blob(x: 0.05, y: 0.0, r: 0.75, c: c(0xFFD36E)), Blob(x: 0.95, y: 0.15, r: 0.65, c: c(0xFF5E7E)),
                                            Blob(x: 0.75, y: 1.0, r: 0.8, c: c(0x8E5CF7)), Blob(x: 0.1, y: 0.95, r: 0.55, c: c(0xFF7849))])
        case .aurora: return (c(0x0E2A47), [Blob(x: 0.15, y: 0.15, r: 0.7, c: c(0x2BE3A5)), Blob(x: 0.85, y: 0.1, r: 0.6, c: c(0x3B82F6)),
                                            Blob(x: 0.55, y: 0.95, r: 0.75, c: c(0x9D4EDD)), Blob(x: 0.0, y: 0.85, r: 0.5, c: c(0x0EA5A4))])
        case .ocean: return (c(0x1E5AA8), [Blob(x: 0.1, y: 0.05, r: 0.7, c: c(0x67D8F5)), Blob(x: 0.9, y: 0.2, r: 0.6, c: c(0x2F7DE1)),
                                           Blob(x: 0.6, y: 1.0, r: 0.8, c: c(0x143E8C)), Blob(x: 0.0, y: 0.9, r: 0.45, c: c(0x2BB6C9))])
        case .mint: return (c(0xBFF0DA), [Blob(x: 0.1, y: 0.1, r: 0.7, c: c(0xE9FFF4)), Blob(x: 0.9, y: 0.15, r: 0.6, c: c(0x8DE3C3)),
                                          Blob(x: 0.7, y: 0.95, r: 0.75, c: c(0x5CC9B0)), Blob(x: 0.05, y: 0.9, r: 0.5, c: c(0xC9F5A8))])
        case .lavender: return (c(0xCDBEF7), [Blob(x: 0.1, y: 0.1, r: 0.7, c: c(0xF1E9FF)), Blob(x: 0.9, y: 0.2, r: 0.6, c: c(0xA996F2)),
                                              Blob(x: 0.65, y: 1.0, r: 0.8, c: c(0xE3A8E6)), Blob(x: 0.0, y: 0.85, r: 0.5, c: c(0x9DB4F7))])
        case .peach: return (c(0xFFD2B8), [Blob(x: 0.1, y: 0.05, r: 0.7, c: c(0xFFF1DE)), Blob(x: 0.95, y: 0.25, r: 0.6, c: c(0xFFA98A)),
                                           Blob(x: 0.6, y: 1.0, r: 0.8, c: c(0xFFC2C7)), Blob(x: 0.0, y: 0.9, r: 0.45, c: c(0xFFCE8A))])
        case .midnight: return (c(0x0B1026), [Blob(x: 0.15, y: 0.1, r: 0.65, c: c(0x2A2F7A)), Blob(x: 0.9, y: 0.3, r: 0.55, c: c(0x4B1F6E)),
                                              Blob(x: 0.5, y: 1.05, r: 0.8, c: c(0x0F3B5F)), Blob(x: 0.0, y: 0.9, r: 0.4, c: c(0x1B1446))])
        case .graphite: return (c(0x2A2C31), [Blob(x: 0.15, y: 0.05, r: 0.7, c: c(0x4A4D55)), Blob(x: 0.9, y: 0.25, r: 0.55, c: c(0x34363C)),
                                              Blob(x: 0.6, y: 1.0, r: 0.8, c: c(0x1A1B1F)), Blob(x: 0.0, y: 0.9, r: 0.4, c: c(0x3A3D44))])
        case .dusk: return (c(0x1A1033), [Blob(x: 0.2, y: 0.2, r: 0.8, c: c(0x3B1C5A)), Blob(x: 0.9, y: 0.9, r: 0.7, c: c(0x5A1E4A))])
        case .lagoon: return (c(0x062A33), [Blob(x: 0.2, y: 0.1, r: 0.8, c: c(0x0B4F5C)), Blob(x: 0.85, y: 0.95, r: 0.7, c: c(0x0B3A5C))])
        case .rose: return (c(0xF6D5DC), [Blob(x: 0.2, y: 0.2, r: 0.8, c: c(0xFCE9EC)), Blob(x: 0.9, y: 0.9, r: 0.7, c: c(0xEFB6C6))])
        case .frostBlue: return (c(0xB9D3F5), [Blob(x: 0.1, y: 0.1, r: 0.7, c: c(0xE8F2FF)), Blob(x: 0.9, y: 0.35, r: 0.6, c: c(0x8FB3EE)),
                                               Blob(x: 0.4, y: 1.0, r: 0.7, c: c(0xA8C8F0))])
        case .frostRose: return (c(0xF3CFD8), [Blob(x: 0.1, y: 0.1, r: 0.7, c: c(0xFFF0F3)), Blob(x: 0.9, y: 0.35, r: 0.6, c: c(0xE7A9BC)),
                                               Blob(x: 0.4, y: 1.0, r: 0.7, c: c(0xF0C2D6))])
        case .frostSage: return (c(0xCFE0CF), [Blob(x: 0.1, y: 0.1, r: 0.7, c: c(0xF1F8EE)), Blob(x: 0.9, y: 0.35, r: 0.6, c: c(0xA9C7AE)),
                                               Blob(x: 0.4, y: 1.0, r: 0.7, c: c(0xC5DBC0))])
        case .paper: return (c(0xF4EFE6), [Blob(x: 0.3, y: -0.1, r: 0.9, c: c(0xFBF8F2))])
        case .cloud: return (c(0xE9ECF1), [Blob(x: 0.3, y: -0.1, r: 0.9, c: c(0xF8F9FB))])
        case .stone: return (c(0xC9C5BE), [Blob(x: 0.3, y: -0.1, r: 0.9, c: c(0xDCD8D1))])
        case .charcoal: return (c(0x26272B), [Blob(x: 0.3, y: -0.1, r: 0.9, c: c(0x3A3B40))])
        case .ink: return (c(0x0C0D10), [Blob(x: 0.3, y: -0.1, r: 0.9, c: c(0x1E2026))])
        case .match:
            let cs = colours.isEmpty ? [c(0x8FA7C9), c(0xC7A6D9), c(0x9ED0C1)] : colours
            let base = cs[0].mixed(with: cs.count > 1 ? cs[1] : cs[0], 0.5).shaded(0.82)
            let spots: [(Double, Double, Double)] = [(0.08, 0.05, 0.75), (0.95, 0.2, 0.6), (0.65, 1.0, 0.8), (0.0, 0.9, 0.5)]
            return (base, spots.enumerated().map { i, s in Blob(x: s.0, y: s.1, r: s.2, c: cs[i % cs.count]) })
        }
    }

    /// Orb layout for bokeh styles (x, y, radius as share of long side, colour, opacity).
    private var orbs: [(Double, Double, Double, RGBA, Double)] {
        func c(_ h: UInt32) -> RGBA { Self.c(h, 1) }
        switch self {
        case .dusk: return [(0.18, 0.28, 0.20, c(0xFF7AB6), 0.55), (0.72, 0.18, 0.26, c(0xFFB36B), 0.45), (0.86, 0.72, 0.18, c(0x9B6BFF), 0.55),
                            (0.35, 0.82, 0.24, c(0x6B8BFF), 0.40), (0.55, 0.50, 0.10, c(0xFFD27A), 0.50), (0.05, 0.75, 0.12, c(0xFF8A8A), 0.45)]
        case .lagoon: return [(0.2, 0.3, 0.22, c(0x3FE0C5), 0.45), (0.75, 0.2, 0.25, c(0x4FA8FF), 0.40), (0.85, 0.75, 0.16, c(0x7CF29C), 0.40),
                              (0.35, 0.8, 0.24, c(0x2BC4E8), 0.38), (0.58, 0.52, 0.09, c(0xBFFFF0), 0.45), (0.04, 0.7, 0.12, c(0x5AD1FF), 0.40)]
        case .rose: return [(0.2, 0.3, 0.22, c(0xFFFFFF), 0.65), (0.75, 0.2, 0.25, c(0xF59AB4), 0.45), (0.85, 0.75, 0.16, c(0xFFD6A8), 0.55),
                            (0.35, 0.8, 0.24, c(0xE9A7E0), 0.40), (0.58, 0.52, 0.09, c(0xFFFFFF), 0.60), (0.04, 0.7, 0.12, c(0xFFC4CF), 0.55)]
        default: return []
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
        let amount = grain * (kind == .frost ? 1.3 : 1) * (isDark ? 0.8 : 1)
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
        let long = b.kind == .orbs ? 480.0 : 320.0
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
        for bl in blobs { blob(bl.x, bl.y, bl.r, bl.c, 0.95) }
        switch b.kind {
        case .orbs:
            for o in b.orbs { blob(o.0, o.1, o.2, o.3, o.4, hard: 0.72) }
            // A second, larger and fainter pass reads as out-of-focus depth.
            for o in b.orbs { blob(1 - o.0 * 0.8, o.1 * 0.9 + 0.05, o.2 * 0.55, o.3, o.4 * 0.35, hard: 0.65) }
        case .frost:
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.22)); ctx.fill(r)
            // Two diagonal light bands, like glass catching light.
            for (pos, a) in [(0.32, 0.20), (0.62, 0.12)] {
                let g = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: a), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 0.5, 1])!
                let p = CGFloat(pos)
                ctx.drawLinearGradient(g, start: CGPoint(x: r.width * (p - 0.12), y: r.height), end: CGPoint(x: r.width * (p + 0.12), y: r.height * 0.6),
                                       options: [])
            }
        case .neutral:
            let g = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: b.isDark ? 0.04 : 0.18), CGColor(gray: 0, alpha: b.isDark ? 0.18 : 0.05)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: r.height), end: .zero, options: [])
        case .mesh: break
        }
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

    /// Up to three distinct, lively colours from the image, nudged into a pleasant backdrop range.
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
        if x.s < 0.12 { return .hsb(x.h, x.s, min(max(x.b, 0.35), 0.9)) }
        return .hsb(x.h, min(max(x.s, 0.35), 0.62), min(max(x.b, 0.6), 0.93))
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
