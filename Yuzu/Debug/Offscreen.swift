import AppKit

/// Test windows for automated screenshots: rendered past the right edge of every screen, behind other windows,
/// deaf to the mouse. Nothing appears on screen, nothing takes focus, and nothing can be clicked by accident.
@MainActor
enum Offscreen {
    static func park(_ window: NSWindow) {
        window.level = .normal
        window.ignoresMouseEvents = true
        let maxX = NSScreen.screens.map(\.frame.maxX).max() ?? 0
        let spot = NSPoint(x: maxX + 400, y: NSScreen.main?.frame.midY ?? 0)
        window.alphaValue = 0
        window.setFrameOrigin(spot)
        window.orderBack(nil)
        // Ordering a titled window in constrains it back onto a screen, so move it out again afterwards,
        // and only make it opaque once it is off screen.
        window.setFrameOrigin(spot)
        window.alphaValue = 1
        try? "\(window.windowNumber)".write(toFile: NSTemporaryDirectory() + "yuzu-window.txt", atomically: true, encoding: .utf8)
    }
}
