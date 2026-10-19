import AppKit
import os

@MainActor
enum JobRunner {
    private static let log = Logger(subsystem: "com.sreecharan.yuzu", category: "jobs")
    private static var current: JobContext?

    struct Outcome: Sendable {
        var outputs: [URL] = []
        var errors: [String] = []
        var progressEvents = 0
        var seconds: Double = 0
    }

    static func cancelCurrent() { current?.cancel() }

    static func title(for option: WheelOption) -> String {
        switch option.action {
        case .convertImage(let f): return "Converting to \(f.title)"
        case .convertFile(let t): return t == .extract ? "Extracting" : "Converting to \(t.title)"
        case .imageTool(let t): return "\(t.title)…"
        case .fileAction(let a): return a.title
        }
    }

    static func run(_ option: WheelOption, urls: [URL], near point: NSPoint, reveal: Bool? = nil, quiet: Bool = false,
                    completion: ((Outcome) -> Void)? = nil) {
        guard !urls.isEmpty else { return }
        let work: @Sendable (URL, JobContext) throws -> URL
        switch option.action {
        case .fileAction(let a):
            FileActions.perform(a, urls: urls, near: point)
            completion?(Outcome())
            return
        case .convertImage(let f):
            work = { url, ctx in try ImageEngine.convert(url, to: f, settings: ctx.settings) }
        case .imageTool(let t):
            work = { url, ctx in try ImageEngine.apply(t, to: url, settings: ctx.settings) }
        case .convertFile(let t):
            work = { url, ctx in try Conversions.perform(t, source: url, ctx: ctx) }
        }

        let ctx = JobContext(settings: ImageSettings(quality: Prefs.lossyQuality, compressQuality: Prefs.compressQuality,
                                                     preserveMetadata: Prefs.preserveMetadata))
        current = ctx
        let shouldReveal = reveal ?? Prefs.reveal
        let hud = HUDController.shared
        let label = title(for: option)
        if !quiet {
            hud.onCancel = { ctx.cancel() }
            hud.begin(title: urls.count == 1 ? label : "\(label) · \(urls.count) files", near: point)
        }
        let total = Double(urls.count)
        let started = Date()

        Task.detached(priority: .userInitiated) {
            var outcome = Outcome()
            let counter = ProgressCounter()
            for (i, url) in urls.enumerated() {
                if ctx.isCancelled { break }
                ctx.onProgress = { f in
                    counter.bump()
                    guard counter.shouldPublish() else { return }
                    let overall = (Double(i) + f) / total
                    Task { @MainActor in if !quiet { hud.progress(overall) } }
                }
                do {
                    outcome.outputs.append(try work(url, ctx))
                } catch YuzuError.cancelled {
                    outcome.errors.append("Cancelled")
                    break
                } catch {
                    outcome.errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
                let done = Double(i + 1) / total
                Task { @MainActor in if !quiet { hud.progress(done) } }
            }
            outcome.progressEvents = counter.count
            outcome.seconds = Date().timeIntervalSince(started)
            let result = outcome
            let inBytes = SizeText.of(urls)
            let outBytes = SizeText.of(result.outputs)
            await MainActor.run {
                if current === ctx { current = nil }
                if !quiet { present(result, inputs: urls, inBytes: inBytes, outBytes: outBytes, label: label) }
                for e in result.errors { log.error("\(e, privacy: .public)") }
                if shouldReveal, !result.outputs.isEmpty, !quiet { NSWorkspace.shared.activateFileViewerSelecting(result.outputs) }
                completion?(result)
            }
        }
    }

    private static func present(_ r: Outcome, inputs: [URL], inBytes: Int64, outBytes: Int64, label: String) {
        let hud = HUDController.shared
        if r.errors == ["Cancelled"] && r.outputs.isEmpty {
            hud.info("Cancelled", symbol: "xmark.circle.fill", near: .zero)
            return
        }
        if r.errors.isEmpty {
            let title = r.outputs.count == 1 ? "Saved \(r.outputs[0].lastPathComponent)" : "Saved \(r.outputs.count) files"
            hud.success(title, detail: SizeText.delta(from: inBytes, to: outBytes), outputs: r.outputs)
        } else if r.outputs.isEmpty {
            let what = inputs.count == 1 ? inputs[0].lastPathComponent : "\(inputs.count) files"
            let reason = r.errors.first.map { $0.components(separatedBy: ": ").dropFirst().joined(separator: ": ") } ?? ""
            hud.failure("Couldn't convert \(what)", detail: reason.isEmpty ? (r.errors.first ?? "") : reason)
        } else {
            hud.failure("Saved \(r.outputs.count) of \(inputs.count)", detail: r.errors.first ?? "")
        }
    }
}

/// Throttles progress publishing to about 30 updates per second.
final class ProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast
    private(set) var count = 0
    func bump() { lock.lock(); count += 1; lock.unlock() }
    func shouldPublish() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        if now.timeIntervalSince(last) > 1.0 / 30 { last = now; return true }
        return false
    }
}

@MainActor
enum FileActions {
    static func perform(_ action: FileAction, urls: [URL], near point: NSPoint) {
        let hud = HUDController.shared
        let one = urls.count == 1
        switch action {
        case .airDrop:
            guard let s = NSSharingService(named: .sendViaAirDrop), s.canPerform(withItems: urls) else {
                hud.failure("AirDrop is unavailable", detail: "", near: point); return
            }
            NSApp.activate()
            s.perform(withItems: urls)
        case .copy:
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects(urls as [NSURL])
            hud.info(one ? "Copied \(urls[0].lastPathComponent)" : "Copied \(urls.count) items", symbol: "doc.on.doc.fill", near: point)
        case .copyPath:
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            hud.info(one ? "Path copied" : "\(urls.count) paths copied", symbol: "link.circle.fill", near: point)
        case .move:
            NSApp.activate()
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Move Here"
            panel.message = "Choose where to move \(one ? urls[0].lastPathComponent : "\(urls.count) items")"
            guard panel.runModal() == .OK, let dir = panel.url else { return }
            var moved: [URL] = []
            for u in urls {
                var dest = dir.appendingPathComponent(u.lastPathComponent)
                var n = 2
                while FileManager.default.fileExists(atPath: dest.path) {
                    dest = dir.appendingPathComponent("\(u.deletingPathExtension().lastPathComponent) \(n)")
                        .appendingPathExtension(u.pathExtension)
                    n += 1
                }
                if (try? FileManager.default.moveItem(at: u, to: dest)) != nil { moved.append(dest) }
            }
            if moved.count == urls.count {
                hud.success(one ? "Moved \(urls[0].lastPathComponent)" : "Moved \(moved.count) items", detail: "to \(dir.lastPathComponent)",
                            symbol: "folder.fill", outputs: moved, near: point)
            } else {
                hud.failure("Moved \(moved.count) of \(urls.count)", detail: "Some items could not be moved", near: point)
            }
        case .terminal:
            let first = urls[0]
            let isDir = (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let folder = isDir ? first : first.deletingLastPathComponent()
            guard let term = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
            NSWorkspace.shared.open([folder], withApplicationAt: term, configuration: NSWorkspace.OpenConfiguration())
        case .float:
            hud.info("Float arrives in a later build", symbol: "paperclip.circle.fill", near: point)
        }
    }
}
