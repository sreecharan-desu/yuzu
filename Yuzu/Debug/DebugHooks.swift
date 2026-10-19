import AppKit
import os

/// Local developer hooks driven by `scripts/yuzuctl` (distributed notifications on this Mac only).
/// Used to preview the ring and run conversions for automated screenshots and tests.
@MainActor
final class DebugHooks {
    static let name = Notification.Name("com.sreecharan.yuzu.debug")
    private let log = Logger(subsystem: "com.sreecharan.yuzu", category: "debug")
    private weak var menuBar: MenuBarController?
    private var token: NSObjectProtocol?

    init(menuBar: MenuBarController?) {
        self.menuBar = menuBar
        token = DistributedNotificationCenter.default().addObserver(forName: Self.name, object: nil, queue: .main) { [weak self] note in
            let info = (note.userInfo as? [String: String]) ?? [:]
            MainActor.assumeIsolated { self?.handle(info) }
        }
    }

    private func handle(_ info: [String: String]) {
        log.info("debug command \(info["cmd"] ?? "?", privacy: .public)")
        switch info["cmd"] {
        case "preview":
            let kind = WheelKind(rawValue: info["kind"] ?? "convert") ?? .convert
            let items = info["file"].map { [URL(fileURLWithPath: $0)] }
            let hover = info["hover"].flatMap(Int.init)
            let duration = info["duration"].flatMap(Double.init) ?? 5
            WheelController.shared.showDemo(kind: kind, items: items, hover: hover, duration: duration)
        case "menu":
            menuBar?.openMenu(autoCloseAfter: info["duration"].flatMap(Double.init) ?? 4)
        case "settings":
            SettingsWindowController.shared.show()
        case "convert":
            guard let file = info["file"], let id = info["option"] else { return }
            let url = URL(fileURLWithPath: file)
            let kind = WheelKind(rawValue: info["kind"] ?? "convert") ?? .convert
            let opts = Catalog.options(for: kind, items: [url]).options
            guard let opt = opts.first(where: { $0.id == id }) else {
                log.error("no option \(id, privacy: .public); have \(opts.map(\.id).joined(separator: ","), privacy: .public)")
                return
            }
            let screen = NSScreen.main?.frame ?? .zero
            JobRunner.run(opt, urls: [url], near: NSPoint(x: screen.midX, y: screen.midY), reveal: false) { outs, errs in
                let report = (outs.map { "OK \($0.path)" } + errs.map { "ERR \($0)" }).joined(separator: "\n")
                try? report.write(toFile: NSTemporaryDirectory() + "yuzu-last-job.txt", atomically: true, encoding: .utf8)
                self.log.info("job result: \(report, privacy: .public)")
            }
        case "quit":
            NSApp.terminate(nil)
        default:
            break
        }
    }
}
