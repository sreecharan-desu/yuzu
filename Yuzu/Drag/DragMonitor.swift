import AppKit
import os

/// Watches system-wide file drags without Accessibility permission:
/// - a global mouse monitor notices left-button presses and drags in other apps,
/// - the drag pasteboard's changeCount reveals when a real drag session starts,
/// - the global modifier state is polled at display rate to detect a key tap.
@MainActor
final class DragMonitor {
    var onTap: ((WheelKind, [URL], NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    private let log = Logger(subsystem: "com.sreecharan.yuzu", category: "drag")
    private var monitors: [Any] = []
    private var timer: Timer?
    private var baseChangeCount = 0
    private var isFileDrag = false
    private var items: [URL] = []
    private var lastFlags: NSEvent.ModifierFlags = []
    private let relevant: NSEvent.ModifierFlags = [.shift, .command, .control, .option]

    func start() {
        baseChangeCount = NSPasteboard(name: .drag).changeCount
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.beginSessionIfNeeded() }
        }) { monitors.append(m) }
        log.info("Monitoring drag gestures")
    }

    private func mouseDown() {
        baseChangeCount = NSPasteboard(name: .drag).changeCount
        isFileDrag = false
        items = []
        lastFlags = NSEvent.modifierFlags.intersection(relevant)
    }

    private func beginSessionIfNeeded() {
        guard timer == nil else { return }
        lastFlags = NSEvent.modifierFlags.intersection(relevant)
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func endSession() {
        timer?.invalidate()
        timer = nil
        if isFileDrag { onDragEnded?() }
        isFileDrag = false
        items = []
    }

    private func tick() {
        if NSEvent.pressedMouseButtons & 1 == 0 {
            endSession()
            return
        }
        let pb = NSPasteboard(name: .drag)
        if !isFileDrag, pb.changeCount != baseChangeCount {
            if pb.types?.contains(.fileURL) == true {
                isFileDrag = true
                items = (pb.readObjects(forClasses: [NSURL.self],
                                        options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
                log.info("File drag started with \(self.items.count) item(s)")
            } else {
                // Not a file drag (text, images from browsers, etc.). Stop watching this one.
                baseChangeCount = pb.changeCount
            }
        }

        let flags = NSEvent.modifierFlags.intersection(relevant)
        defer { lastFlags = flags }
        guard isFileDrag, flags != lastFlags, !flags.isEmpty else { return }
        // Fire on the press edge of an exact combination match.
        for kind in WheelKind.allCases where Prefs.combo(for: kind).flags == flags {
            onTap?(kind, items, NSEvent.mouseLocation)
            return
        }
    }
}
