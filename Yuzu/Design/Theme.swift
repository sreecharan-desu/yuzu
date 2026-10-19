import SwiftUI
import AppKit

/// Yuzu design tokens. Original palette: a warm saffron yuzu yellow over glass.
enum Theme {
    static let accent = Color(red: 1.00, green: 0.71, blue: 0.05)        // #FFB50D
    static let accentDeep = Color(red: 0.99, green: 0.56, blue: 0.02)    // #FC8F05
    static let ink = Color(red: 0.16, green: 0.11, blue: 0.03)           // warm near-black
    static let nsAccent = NSColor(red: 1.00, green: 0.71, blue: 0.05, alpha: 1)

    // Wheel geometry (points)
    static let wheelDiameter: CGFloat = 320
    static let ringPadding: CGFloat = 8          // glass ring visible outside petals
    static let hubDiameter: CGFloat = 118
    static let hubGap: CGFloat = 8               // space between hub and petals
    static let petalGap: CGFloat = 10
    static let petalCorner: CGFloat = 24
    static let canvas: CGFloat = 400             // panel size around the wheel
    static let maxPetals = 10
    static let minSlots = 4

    // Motion
    // Tuned for v1: a quicker, slightly firmer bloom (settles in about 0.3 s with a small overshoot),
    // petals that trail the ring by a hair, and a snappy hover that does not wobble.
    static let bloom = Animation.spring(response: 0.30, dampingFraction: 0.78)
    static let petalBloom = Animation.spring(response: 0.34, dampingFraction: 0.74)
    static let hover = Animation.spring(response: 0.16, dampingFraction: 0.72)
    static let close = Animation.easeIn(duration: 0.12)

    static var outerRadius: CGFloat { wheelDiameter / 2 - ringPadding }
    static var innerRadius: CGFloat { hubDiameter / 2 + hubGap }
}
