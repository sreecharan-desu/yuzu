import AppKit
import os

/// Local developer hooks driven by `scripts/yuzuctl` (distributed notifications on this Mac only).
/// Used to preview the ring and run conversions for automated screenshots and tests.
extension Notification.Name { static let yuzuPanelSet = Notification.Name("yuzu.panelSet") }

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

    static func render(_ view: NSView, to path: String, backdrop: String?) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let size = view.bounds.size
        let scale = CGFloat(rep.pixelsWide) / max(size.width, 1)
        let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        out.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        let rect = NSRect(origin: .zero, size: size)
        if let bg = backdrop, let img = NSImage(contentsOfFile: bg) {
            // aspect-fill
            let s = max(size.width / img.size.width, size.height / img.size.height)
            let w = img.size.width * s, h = img.size.height * s
            img.draw(in: NSRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
        }
        rep.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        _ = scale
        try? out.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
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
            JobRunner.run(opt, urls: [url], near: NSPoint(x: screen.midX, y: screen.midY), reveal: false,
                          quiet: info["quiet"] == "1") { r in
                let report = (r.outputs.map { "OK \($0.path)" } + r.errors.map { "ERR \($0)" }).joined(separator: "\n")
                try? report.write(toFile: NSTemporaryDirectory() + "yuzu-last-job.txt", atomically: true, encoding: .utf8)
                self.log.info("job result: \(report, privacy: .public)")
            }
        case "snapshot":
            // Self-render of Yuzu's own window (no screen capture). Glass is approximated by the backdrop image.
            let target = info["target"] ?? "wheel"
            let path = info["path"] ?? (NSTemporaryDirectory() + "yuzu-\(target).png")
            let delay = info["delay"].flatMap(Double.init) ?? 0.8
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let window: NSWindow? = target == "settings" ? SettingsWindowController.shared.window
                    : (target == "hud" ? HUDController.shared.panelForSnapshot : WheelController.shared.panelForSnapshot)
                guard let view = window?.contentView else { return }
                let wheel = WheelController.shared.model
                if target == "wheel" {
                    wheel.snapshotBackdrop = info["bg"].flatMap { NSImage(contentsOfFile: $0) }
                    wheel.snapshotScheme = info["appearance"] == "light" ? .light : (info["appearance"] == "dark" ? .dark : nil)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    Self.render(view, to: path, backdrop: target == "wheel" ? nil : info["bg"])
                    wheel.snapshotBackdrop = nil
                    wheel.snapshotScheme = nil
                }
                self.log.info("snapshot written \(path, privacy: .public)")
            }
        case "batch":
            guard let dir = info["dir"], let out = info["out"] else { return }
            runBatch(dir: URL(fileURLWithPath: dir), report: URL(fileURLWithPath: out),
                     skipIWork: info["iwork"] != "1", only: info["only"])
        case "latency":
            // Opens and closes the ring n times through the same path a key tap uses and records latency.
            let n = Int(info["n"] ?? "10") ?? 10
            let wheel = WheelController.shared
            let f = NSScreen.main?.frame ?? .zero
            let items = DemoFiles.sampleImage().map { [$0] } ?? []
            var results: [Double] = []
            func step(_ i: Int) {
                guard i < n else {
                    wheel.onLatency = nil
                    let sorted = results.sorted()
                    let line = results.map { String(format: "%.2f", $0) }.joined(separator: ",")
                    let summary = String(format: "n=%d min=%.2f median=%.2f max=%.2f ms | %@", n, sorted.first ?? 0,
                                         sorted.isEmpty ? 0 : sorted[sorted.count / 2], sorted.last ?? 0, line)
                    try? summary.write(toFile: NSTemporaryDirectory() + "yuzu-latency.txt", atomically: true, encoding: .utf8)
                    return
                }
                wheel.onLatency = { ms in
                    results.append(ms)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        wheel.close()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { step(i + 1) }
                    }
                }
                wheel.handleTap(kind: .convert, items: items, at: NSPoint(x: f.midX, y: f.midY))
            }
            step(0)
        case "toolpanel":
            // Opens a tool panel behind other windows (no focus change) for screenshots; writes its window number.
            guard let t = FileTool(rawValue: info["tool"] ?? ""), let files = info["files"] else { return }
            let urls = files.split(separator: "|").map { URL(fileURLWithPath: String($0)) }
            if let a = info["appearance"] { NSApp.appearance = NSAppearance(named: a == "light" ? .aqua : .darkAqua) }
            ToolPanelController.closeAll()
            ToolPanelController.show(t, urls: urls, background: info["front"] != "1")
            try? "\(ToolPanelController.lastWindowNumber)".write(toFile: NSTemporaryDirectory() + "yuzu-window.txt", atomically: true, encoding: .utf8)
        case "closePanels":
            ToolPanelController.closeAll()
            NSApp.appearance = nil
        case "panelSet":
            // Drives panel state for screenshots: key=value pairs are posted to the open panel.
            NotificationCenter.default.post(name: .yuzuPanelSet, object: nil, userInfo: info)
        case "addbg":
            // Headless Add Background run with a given style (same code path as the panel's Save).
            guard let file = info["file"] else { return }
            var st = BGStyle()
            st.liftSubject = info["lift"] != "0"
            switch info["fill"] ?? "gradient" {
            case "none": st.fill = .none; st.padding = 0; st.shadow = 0
            case "blur": st.fill = .blur
            case "solid": st.fill = .solid(RGBA(r: 0.96, g: 0.94, b: 0.89))
            case "image": st.fill = .image(URL(fileURLWithPath: info["bg"] ?? ""))
            default: break
            }
            if let r = info["ratio"], let v = Double(r) { st.ratio = v }
            let src = URL(fileURLWithPath: file)
            JobRunner.execute(label: "Adding background", units: [[src]], near: .zero, reveal: false, quiet: true,
                              work: { u, ctx in try ImageEdit.addBackground(u[0], style: st, ctx: ctx) }) { r in
                let report = (r.outputs.map { "OK \($0.path) \(String(format: "%.2f", r.seconds))s" } + r.errors.map { "ERR \($0)" }).joined(separator: "\n")
                try? report.write(toFile: NSTemporaryDirectory() + "yuzu-last-job.txt", atomically: true, encoding: .utf8)
            }
        case "toast":
            let hud = HUDController.shared
            let f = NSScreen.main?.frame ?? .zero
            let pt = NSPoint(x: Double(info["x"] ?? "") ?? f.midX, y: Double(info["y"] ?? "") ?? f.midY)
            if let a = info["appearance"] { NSApp.appearance = NSAppearance(named: a == "light" ? .aqua : .darkAqua) }
            let title = info["title"] ?? "Saved photo.jpg"
            let detail = info["detail"] ?? ""
            switch info["state"] ?? "success" {
            case "working":
                hud.begin(title: title, near: pt)
                hud.progress(Double(info["fraction"] ?? "0.42") ?? 0.42, detail: detail.isEmpty ? nil : detail)
            case "error": hud.failure(title, detail: detail, near: pt)
            case "info": hud.info(title, symbol: info["symbol"] ?? "link.circle.fill", near: pt)
            default: hud.success(title, detail: detail, near: pt)
            }
            if info["hold"] == "1" { hud.hold() }
        case "hideToast":
            HUDController.shared.hide()
            NSApp.appearance = nil
        case "closeSettings":
            SettingsWindowController.shared.window?.performClose(nil)
        case "quit":
            NSApp.terminate(nil)
        default:
            break
        }
    }

    /// Runs every convert option for every file in `dir`, one after another, and writes a TSV report:
    /// source, option id, status, output path, seconds, progress event count, message.
    private func runBatch(dir: URL, report: URL, skipIWork: Bool, only: String?) {
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var queue: [(URL, WheelOption)] = []
        for f in files {
            if let only, !f.lastPathComponent.contains(only) { continue }
            for o in Catalog.options(for: .convert, items: [f]).options {
                if case .fileAction = o.action { continue }
                if skipIWork, ["file.pages", "file.key", "file.numbers"].contains(o.id) { continue }
                queue.append((f, o))
            }
        }
        var lines = ["source\toption\tstatus\toutput\tseconds\tprogress_events\tmessage"]
        let total = queue.count
        log.error("batch: \(total) jobs")
        func next() {
            guard !queue.isEmpty else {
                try? (lines.joined(separator: "\n") + "\n").write(to: report, atomically: true, encoding: .utf8)
                HUDController.shared.success("Batch finished", detail: "\(total) jobs")
                return
            }
            let (f, o) = queue.removeFirst()
            HUDController.shared.begin(title: "Batch \(total - queue.count)/\(total): \(f.lastPathComponent) → \(o.title)", near: NSPoint(x: 200, y: 200))
            JobRunner.run(o, urls: [f], near: .zero, reveal: false, quiet: true) { r in
                let ok = !r.outputs.isEmpty && r.errors.isEmpty
                let msg = r.errors.joined(separator: " | ").replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
                lines.append([f.lastPathComponent, o.id, ok ? "OK" : "ERR", r.outputs.first?.path ?? "",
                              String(format: "%.3f", r.seconds), "\(r.progressEvents)", msg].joined(separator: "\t"))
                try? (lines.joined(separator: "\n") + "\n").write(to: report, atomically: true, encoding: .utf8)
                next()
            }
        }
        next()
    }
}
