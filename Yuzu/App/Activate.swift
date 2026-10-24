import AppKit

enum AppActivation {
    /// Brings Yuzu forward. `activate()` needs macOS 14; earlier systems use the older call.
    static func bringForward() {
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
