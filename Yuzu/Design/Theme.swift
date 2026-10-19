import SwiftUI
import AppKit

/// Yuzu design system.
///
/// A quiet, editorial grammar: a white canvas with charcoal ink, three neutral steps, hairline borders,
/// large radii and pill controls, neutral (untinted) glass, slow restrained hovers and blur-in reveals.
/// Dark mode is the same grammar inverted. Yuzu yellow is a whisper used for hover and selection
/// accents only, never as a fill for chrome.
enum Theme {
    // MARK: Colour — every colour in the app comes from here.

    /// Charcoal ink in light mode, pearl in dark mode. The primary "selected" and button colour.
    static let ink = adaptive(light: 0x1D1D1F, dark: 0xF5F5F7)
    /// Text or glyphs placed on top of `ink`.
    static let onInk = adaptive(light: 0xFFFFFF, dark: 0x1D1D1F)
    static let inkSoft = adaptive(light: 0x6E6E73, dark: 0xA1A1A6)
    static let inkMute = adaptive(light: 0x86868B, dark: 0x86868B)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1D1D1F)
    static let step100 = adaptive(light: 0xF5F5F7, dark: 0x2A2A2C)
    static let step200 = adaptive(light: 0xEDEDF0, dark: 0x343437)
    static let step300 = adaptive(light: 0xD2D2D7, dark: 0x48484C)
    static let line = adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.10)
    static let lineStrong = adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.16, darkAlpha: 0.18)
    /// Trust / privacy lead-ins only.
    static let trust = Color(hex: 0x1F6FE5)
    /// The whisper of yuzu. Hover and selection details only (a dot, a hairline, a glyph), never a fill.
    static let yuzu = Color(hex: 0xF3D35B)
    static let danger = adaptive(light: 0xD70015, dark: 0xFF6961)

    // Legacy names, remapped so any remaining call site reads as ink, not orange.
    static var accent: Color { ink }
    static var accentDeep: Color { ink }
    static let nsAccent = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: 0xF5F5F7) : NSColor(hex: 0x1D1D1F) }

    static let nsCanvas = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: 0x1D1D1F) : NSColor(hex: 0xFFFFFF) }

    // MARK: Spacing — 8 pt grid (4 is the only half step, for optical tweaks inside controls).
    enum Space {
        static let half: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: Radii — three, plus the pill.
    enum Radius {
        /// Controls, swatches, thumbnails, icon tiles.
        static let control: CGFloat = 12
        /// Cards and grouped content.
        static let card: CGFloat = 24
        /// Panels and windows-in-windows.
        static let panel: CGFloat = 28
    }

    // MARK: Type — SF Pro, weight ~500 for display roles, tight tracking (em × size).
    enum TypeRole {
        case display, title, headline, body, callout, caption, micro
        var size: CGFloat {
            switch self { case .display: 30; case .title: 20; case .headline: 15; case .body: 13; case .callout: 12; case .caption: 11; case .micro: 10 }
        }
        var weight: Font.Weight {
            switch self { case .display, .title, .headline: .medium; case .body, .callout, .caption: .regular; case .micro: .medium }
        }
        var trackingEm: CGFloat {
            switch self { case .display: -0.034; case .title: -0.024; case .headline: -0.014; case .body: -0.003; case .callout: 0; case .caption: 0.005; case .micro: 0.01 }
        }
        var font: Font { .system(size: size, weight: weight) }
    }

    // MARK: Shadow tokens
    struct Shadow { let color: Color; let radius: CGFloat; let y: CGFloat }
    enum Shadows {
        /// Hairline lift for cards on canvas.
        static let card = Shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        /// Floating chrome: toasts, the ring, Float.
        static let float = Shadow(color: .black.opacity(0.14), radius: 24, y: 10)
        /// Very soft, under thumbnails.
        static let soft = Shadow(color: .black.opacity(0.10), radius: 6, y: 2)
    }

    // MARK: Motion tokens
    enum Motion {
        /// House ease, cubic-bezier(0.16, 1, 0.3, 1).
        static func house(_ d: Double) -> Animation { .timingCurve(0.16, 1, 0.3, 1, duration: d) }
        /// Enter ease, cubic-bezier(0.22, 0.9, 0.28, 1).
        static func enter(_ d: Double) -> Animation { .timingCurve(0.22, 0.9, 0.28, 1, duration: d) }
        static let color = Animation.easeOut(duration: 0.2)
        static let chrome = house(0.3)
        static let glass = house(0.6)
        /// Content materialising: blur + rise to sharp.
        static let materialize = enter(1.0)
        static let materializeStagger = 0.028
        /// Primary button hover: slow, luxurious, restrained.
        static let pop = house(2.4)
        static let popOut = house(3.12)
        static let glare = Animation.timingCurve(0.32, 0.2, 0.25, 1, duration: 2.0)
        /// The ring is a tool under the pointer; it stays quick (a slow ring would feel broken).
        static let bloom = Animation.spring(response: 0.30, dampingFraction: 0.82)
        static let petalBloom = Animation.spring(response: 0.34, dampingFraction: 0.80)
        static let hover = house(0.22)
        static let close = Animation.easeIn(duration: 0.12)
    }

    // Ring motion (kept as named for existing call sites)
    static var bloom: Animation { Motion.bloom }
    static var petalBloom: Animation { Motion.petalBloom }
    static var hover: Animation { Motion.hover }
    static var close: Animation { Motion.close }

    // MARK: Ring geometry (points, on the 8 pt grid)
    static let wheelDiameter: CGFloat = 320
    static let ringPadding: CGFloat = 8
    static let hubDiameter: CGFloat = 112
    static let hubGap: CGFloat = 8
    static let petalGap: CGFloat = 8
    static let petalCorner: CGFloat = 16
    static let canvas: CGFloat = 400
    static let maxPetals = 10
    static let minSlots = 4

    static var outerRadius: CGFloat { wheelDiameter / 2 - ringPadding }
    static var innerRadius: CGFloat { hubDiameter / 2 + hubGap }

    private static func adaptive(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}
