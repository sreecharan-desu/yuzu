import AppKit
import PDFKit
import os

/// Local developer hooks driven by `scripts/yuzuctl` (distributed notifications on this Mac only).
/// Used to preview the ring and run conversions for automated screenshots and tests.
extension Notification.Name { static let yuzuPanelSet = Notification.Name("yuzu.panelSet") }

@MainActor
final class DebugHooks {
    static let name = Notification.Name("com.sreecharan.yuzu.debug")
    private let log = Logger(subsystem: "com.sreecharan.yuzu", category: "debug")
    private weak var menuBar: MenuBarController?
    private var stagedFloat: NSWindow?
    private var token: NSObjectProtocol?

    init(menuBar: MenuBarController?) {
        self.menuBar = menuBar
        // Test automation only. Off unless the app is launched with -YuzuDebugHooks YES, so no other
        // process can drive a normal install.
        guard UserDefaults.standard.bool(forKey: "YuzuDebugHooks") else { return }
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
            // offscreen=1 opens the ring past the right edge of every screen, silently, so nothing shows.
            let off = info["offscreen"] == "1"
            let maxX = NSScreen.screens.map(\.frame.maxX).max() ?? f.maxX
            _ = maxX
            let at = NSPoint(x: f.midX, y: f.midY)
            wheel.offscreenTest = off
            let bloomBase = wheel.bloomStarts.count
            var results: [Double] = []
            func step(_ i: Int) {
                guard i < n else {
                    wheel.onLatency = nil
                    wheel.offscreenTest = false
                    let sorted = results.sorted()
                    let line = results.map { String(format: "%.2f", $0) }.joined(separator: ",")
                    let blooms = Array(wheel.bloomStarts.dropFirst(bloomBase)).sorted()
                    var summary = String(format: "n=%d min=%.2f median=%.2f max=%.2f ms | %@", n, sorted.first ?? 0,
                                         sorted.isEmpty ? 0 : sorted[sorted.count / 2], sorted.last ?? 0, line)
                    summary += "\n" + wheel.stageLog.suffix(n).joined(separator: "\n")
                    summary += String(format: "\nbloom start: median=%.2f max=%.2f ms", blooms.isEmpty ? 0 : blooms[blooms.count / 2], blooms.last ?? 0)
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
                wheel.handleTap(kind: .convert, items: items, at: at)
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
        case "qr":
            // Reads codes in a file and shows the results window behind other windows.
            guard let file = info["file"] else { return }
            let found: [QRReader.Found]
            do { found = try QRReader.detect(URL(fileURLWithPath: file)) } catch {
                try? "ERR \(error)".write(toFile: NSTemporaryDirectory() + "yuzu-window.txt", atomically: true, encoding: .utf8); return
            }
            QRReader.show(found, background: true)
            try? "\(ToolPanelController.lastWindowNumber)".write(toFile: NSTemporaryDirectory() + "yuzu-window.txt", atomically: true, encoding: .utf8)
        case "closePanels":
            QRReader.closeWindow()
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
            if info["screenshot"] == "1" {
                let img = try? ImageEdit.full(src)
                let t = img.map { ImageEdit.trimCaptureShadow($0) }
                st = BGStyle.forScreenshot(pixelScale: ImageEdit.pixelScale(src), width: Double(t?.image.width ?? 1), captureCorner: t?.corner)
            }
            if let b = info["backdrop"].flatMap(Backdrop.init(rawValue:)) { st.fill = .backdrop(b) }
            if let r = info["ratio"], let v = Double(r) { st.ratio = v }
            if info["border"] == "0" { st.border = false }
            let style = st
            JobRunner.execute(label: "Adding background", units: [[src]], near: .zero, reveal: false, quiet: true,
                              work: { u, ctx in try ImageEdit.addBackground(u[0], style: style, ctx: ctx) }) { r in
                let report = (r.outputs.map { "OK \($0.path) \(String(format: "%.2f", r.seconds))s" } + r.errors.map { "ERR \($0)" }).joined(separator: "\n")
                try? report.write(toFile: NSTemporaryDirectory() + "yuzu-last-job.txt", atomically: true, encoding: .utf8)
            }
        case "tooljob":
            // Headless run of a panel tool's Save with given settings (same engine calls as the panels).
            guard let file = info["file"], let tool = info["tool"] else { return }
            let src = URL(fileURLWithPath: file)
            func nums(_ k: String) -> [Double] { (info[k] ?? "").split(separator: ",").compactMap { Double($0) } }
            let n = nums("n")
            let opts = info
            JobRunner.execute(label: tool, units: [[src]], near: .zero, reveal: false, quiet: true, work: { u, ctx in
                switch tool {
                case "trim": return try ToolEngine.trim(u[0], start: n[0], end: n[1], ctx: ctx)
                case "speed": return try ToolEngine.speed(u[0], factor: n[0], ctx: ctx)
                case "split": return try ToolEngine.split(u[0], at: n, ctx: ctx)
                case "cropVideo": return try ToolEngine.cropVideo(u[0], rect: CGRect(x: n[0], y: n[1], width: n[2], height: n[3]), ctx: ctx)
                case "bleep": return try ToolEngine.bleep(u[0], ranges: stride(from: 0, to: n.count - 1, by: 2).map { n[$0]...n[$0 + 1] }, entire: false, ctx: ctx)
                case "channels": return try ToolEngine.channels(u[0], mono: opts["mono"] == "1", left: n[0], right: n[1], ctx: ctx)
                case "splitPDF":
                    let count = PDFDocument(url: u[0])?.pageCount ?? 0
                    return try ToolEngine.splitPDF(u[0], groups: ToolEngine.parseRanges(opts["ranges"] ?? "", pageCount: count), ctx: ctx)
                case "organize":
                    // n = page numbers in new order; rot = rotation applied to every listed page index in "rp"
                    let rp = Set((opts["rp"] ?? "").split(separator: ",").compactMap { Int($0) })
                    return try ToolEngine.organizePDF(u[0], pages: n.map { (index: Int($0) - 1, rotation: rp.contains(Int($0)) ? 90 : 0) }, ctx: ctx)
                default: throw YuzuError.unsupported(tool)
                }
            }) { r in
                let report = (r.outputs.map { "OK \($0.path) \(String(format: "%.2f", r.seconds))s" } + r.errors.map { "ERR \($0)" }).joined(separator: "\n")
                try? report.write(toFile: NSTemporaryDirectory() + "yuzu-last-job.txt", atomically: true, encoding: .utf8)
            }
        case "imgbench":
            // Times native image conversions (decode + encode) for a few sources and targets.
            guard let dir = info["dir"] else { return }
            let srcs = (info["files"] ?? "").split(separator: "|").map { URL(fileURLWithPath: String($0)) }
            let targets: [ImageFormat] = [.jpeg, .png, .heic, .tiff, .webp]
            let runs = Int(info["n"] ?? "") ?? 3
            Task.detached(priority: .userInitiated) {
                var lines: [String] = []
                let settings = ImageSettings(quality: 0.85, compressQuality: 0.6, preserveMetadata: true)
                for s in srcs {
                    let work = URL(fileURLWithPath: dir).appendingPathComponent(s.lastPathComponent)
                    try? FileManager.default.removeItem(at: work)
                    try? FileManager.default.copyItem(at: s, to: work)
                    for t in targets where ImageFormat.of(s) != t {
                        var times: [Double] = []
                        for _ in 0..<runs {
                            let t0 = CFAbsoluteTimeGetCurrent()
                            if let out = try? ImageEngine.convert(work, to: t, settings: settings) {
                                times.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
                                try? FileManager.default.removeItem(at: out)
                            }
                        }
                        times.sort()
                        lines.append(String(format: "%@\t%@\t%.0f", s.lastPathComponent, t.ext, times.isEmpty ? -1 : times[times.count / 2]))
                    }
                    try? FileManager.default.removeItem(at: work)
                }
                try? lines.joined(separator: "\n").write(toFile: NSTemporaryDirectory() + "yuzu-imgbench.txt", atomically: true, encoding: .utf8)
            }
        case "welcome":
            WelcomeController.shared.show(background: true)
        case "welcomeClose":
            WelcomeController.shared.close()
            UserDefaults.standard.removeObject(forKey: WelcomeController.doneKey)
        case "floatstage":
            let urls = (info["files"] ?? "").split(separator: "|").map { URL(fileURLWithPath: String($0)) }
            if let a = info["appearance"] { NSApp.appearance = NSAppearance(named: a == "light" ? .aqua : .darkAqua) }
            stagedFloat?.orderOut(nil)
            stagedFloat = FloatController.shared.stageForScreenshot(urls)
        case "floatstageClose":
            stagedFloat?.orderOut(nil); stagedFloat = nil
        case "floatsnap":
            // Checks edge snapping on pure geometry; nothing moves on screen.
            let v = NSRect(x: 0, y: 0, width: 1440, height: 875)
            var out: [String] = []
            let xs: [CGFloat] = [4, 20, 40, 600, 1440 - 252 - 20, 1440 - 252 - 40, 1300]
            for x in xs {
                let r = FloatGeometry.settle(NSRect(x: x, y: 300, width: 252, height: 262), in: v)
                out.append("x=\(Int(x)) -> \(r.edge?.rawValue ?? "free") \(NSStringFromRect(r.frame))")
            }
            try? out.joined(separator: "\n").write(toFile: NSTemporaryDirectory() + "yuzu-floatsnap.txt", atomically: true, encoding: .utf8)
        case "parbench":
            // Converts the same set of images sequentially, then in parallel, and records both wall times.
            guard let dir = info["dir"] else { return }
            let base = URL(fileURLWithPath: dir)
            let files = ((try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? [])
                .filter { ImageFormat.of($0) != nil }.sorted { $0.path < $1.path }
            let fmt = ImageFormat(rawValue: info["fmt"] ?? "heic") ?? .heic
            var lines: [String] = []
            func pass(_ width: Int, then: @escaping () -> Void) {
                let t0 = CFAbsoluteTimeGetCurrent()
                JobRunner.execute(label: "bench", units: files.map { [$0] }, near: .zero, reveal: false, quiet: true, concurrency: width,
                                  work: { u, ctx in try ImageEngine.convert(u[0], to: fmt, settings: ctx.settings) }) { r in
                    lines.append(String(format: "concurrency=%d files=%d outputs=%d errors=%d wall=%.0fms", width, files.count,
                                        r.outputs.count, r.errors.count, (CFAbsoluteTimeGetCurrent() - t0) * 1000))
                    for o in r.outputs { try? FileManager.default.removeItem(at: o) }
                    then()
                }
            }
            pass(1) { pass(4) {
                try? lines.joined(separator: "\n").write(toFile: NSTemporaryDirectory() + "yuzu-parbench.txt", atomically: true, encoding: .utf8)
            } }
        case "bgbench":
            // Times the panel's preview render for a screenshot on each backdrop (same size the panel uses).
            guard let file = info["file"] else { return }
            let src = URL(fileURLWithPath: file)
            let n = Int(info["n"] ?? "") ?? 15
            Task.detached(priority: .userInitiated) {
                guard let prev = try? ImageEngine.decode(src, maxPixel: 1320).image else { return }
                let t = ImageEdit.trimCaptureShadow(prev)
                let full = try? ImageEngine.decode(src, maxPixel: 1).properties
                let fw = Double(full?[kCGImagePropertyPixelWidth] as? Int ?? t.image.width)
                var lines: [String] = ["preview \(t.image.width)x\(t.image.height) corner=\(t.corner.map { String(format: "%.4f", $0) } ?? "none")"]
                let base = BGStyle.forScreenshot(pixelScale: ImageEdit.pixelScale(src), width: fw, captureCorner: t.corner)
                var variants: [(String, BGStyle)] = []
                if info["parts"] == "1" {
                    var v = base; v.fill = .none; v.shadow = 0; v.border = false; variants.append(("bare", v))
                    v.fill = .solid(.white); variants.append(("+solid", v))
                    v.fill = .backdrop(.aurora); v.grain = 0; variants.append(("+backdrop", v))
                    v.grain = 0.5; variants.append(("+grain", v))
                    v.border = true; variants.append(("+border", v))
                    v.shadow = base.shadow; variants.append(("+shadow", v))
                } else {
                    variants = Backdrop.allCases.map { b in var v = base; v.fill = .backdrop(b); return (b.rawValue, v) }
                }
                for (name, st) in variants {
                    var times: [Double] = []
                    for _ in 0..<n {
                        let t0 = CFAbsoluteTimeGetCurrent()
                        _ = ImageEdit.renderBackground(image: t.image, subject: nil, style: st)
                        times.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
                    }
                    times.sort()
                    lines.append(String(format: "%@\tfirst %.1f ms\tmedian %.1f ms\tmax %.1f ms", name, times.first ?? 0, times[times.count / 2], times.last ?? 0))
                }
                try? lines.joined(separator: "\n").write(toFile: NSTemporaryDirectory() + "yuzu-bench.txt", atomically: true, encoding: .utf8)
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
                return
            }
            let (f, o) = queue.removeFirst()
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
