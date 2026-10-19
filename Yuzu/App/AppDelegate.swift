import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var dragMonitor: DragMonitor?
    private var debugHooks: DebugHooks?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        menuBar = MenuBarController()

        let wheel = WheelController.shared
        let monitor = DragMonitor()
        monitor.onTap = { kind, items, point in
            wheel.handleTap(kind: kind, items: items, at: point)
        }
        monitor.onDragEnded = {
            wheel.dragSessionEnded()
        }
        monitor.start()
        dragMonitor = monitor
        debugHooks = DebugHooks(menuBar: menuBar)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }
}
