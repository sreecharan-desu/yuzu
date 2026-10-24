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
        case .tool(let t): return "\(t.title)…"
        case .fileAction(let a): return a.title
        }
    }

    static func run(_ option: WheelOption, urls: [URL], near point: NSPoint, reveal: Bool? = nil, quiet: Bool = false,
                    completion: ((Outcome) -> Void)? = nil) {
        guard !urls.isEmpty else { return }
        let label = title(for: option)
        switch option.action {
        case .fileAction(let a):
            FileActions.perform(a, urls: urls, near: point)
            completion?(Outcome())
        case .convertImage(let f):
            execute(label: label, units: urls.map { [$0] }, near: point, reveal: reveal, quiet: quiet,
                    concurrency: 4, work: { u, ctx in try ImageEngine.convert(u[0], to: f, settings: ctx.settings) }, completion: completion)
        case .imageTool(let t):
            execute(label: label, units: urls.map { [$0] }, near: point, reveal: reveal, quiet: quiet,
                    concurrency: 4, work: { u, ctx in try ImageEngine.apply(t, to: u[0], settings: ctx.settings) }, completion: completion)
        case .convertFile(let t):
            execute(label: label, units: urls.map { [$0] }, near: point, reveal: reveal, quiet: quiet,
                    concurrency: concurrency(for: urls), work: { u, ctx in try Conversions.perform(t, source: u[0], ctx: ctx) }, completion: completion)
        case .tool(let t):
            if t.needsPanel && !quiet {
                ToolPanelController.show(t, urls: urls)
                completion?(Outcome())
                return
            }
            if t == .readQR {
                QRReader.run(urls: urls, near: point, quiet: quiet, completion: completion)
                return
            }
            let units = t.combinesFiles ? [urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }]
                                        : urls.map { [$0] }
            execute(label: label, units: units, near: point, reveal: reveal, quiet: quiet,
                    concurrency: units.count > 1 ? concurrency(for: urls) : 1,
                    work: { u, ctx in try ToolEngine.oneShot(t, inputs: u, ctx: ctx) }, completion: completion)
        }
    }

    /// How many files run at once: images are cheap and parallel well, ffmpeg already uses several cores,
    /// and LibreOffice must run one conversion at a time.
    static func concurrency(for urls: [URL]) -> Int {
        let kinds = Set(urls.map(FileKind.of))
        if kinds.contains(where: { [.document, .slides, .spreadsheet].contains($0) }) { return 1 }
        if kinds.contains(where: { $0 == .video || $0 == .audio }) { return 2 }
        if kinds == [.image] { return 4 }
        return 2
    }

    /// Runs `work` once per unit (a unit is one file, or all files for combining tools) off the main thread,
    /// up to `concurrency` units at a time on GCD worker threads, with live progress, cancel and a result toast.
    /// Outputs keep the order of the inputs.
    static func execute(label: String, units: [[URL]], near point: NSPoint, reveal: Bool? = nil, quiet: Bool = false,
                        concurrency: Int = 1,
                        work: @escaping @Sendable ([URL], JobContext) throws -> URL,
                        completion: ((Outcome) -> Void)? = nil) {
        let urls = units.flatMap { $0 }
        let ctx = JobContext(settings: ImageSettings(quality: Prefs.lossyQuality, compressQuality: Prefs.compressQuality,
                                                     preserveMetadata: Prefs.preserveMetadata))
        current = ctx
        let shouldReveal = reveal ?? Prefs.reveal
        let hud = HUDController.shared
        if !quiet {
            hud.onCancel = { ctx.cancel() }
            hud.begin(title: units.count == 1 ? label : "\(label) · \(units.count) files", near: point)
        }
        let started = Date()
        let width = max(1, min(concurrency, units.count))

        DispatchQueue.global(qos: .userInitiated).async {
            let board = ProgressBoard(count: units.count)
            let counter = ProgressCounter()
            let publish: @Sendable () -> Void = {
                let overall = board.overall
                Task { @MainActor in if !quiet { hud.progress(overall) } }
            }
            let slots = DispatchSemaphore(value: width)
            let group = DispatchGroup()
            let pool = DispatchQueue(label: "com.sreecharan.yuzu.jobs", qos: .userInitiated, attributes: .concurrent)
            for (i, unit) in units.enumerated() {
                slots.wait()
                if ctx.isCancelled { slots.signal(); break }
                group.enter()
                pool.async {
                    defer { slots.signal(); group.leave() }
                    let child = ctx.child()
                    child.onProgress = { f in
                        board.set(i, f)
                        counter.bump()
                        if counter.shouldPublish() { publish() }
                    }
                    do {
                        board.finish(i, output: try work(unit, child))
                    } catch YuzuError.cancelled {
                        board.fail(i, "Cancelled")
                        ctx.cancel()
                    } catch {
                        board.fail(i, "\(unit[0].lastPathComponent): \(error.localizedDescription)")
                    }
                    publish()
                }
            }
            group.wait()
            var outcome = board.outcome(cancelled: ctx.isCancelled)
            outcome.progressEvents = counter.count
            outcome.seconds = Date().timeIntervalSince(started)
            let result = outcome
            let inBytes = SizeText.of(urls)
            let outBytes = SizeText.of(result.outputs)
            Task { @MainActor in
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

/// Per-unit progress and results for a parallel job, in input order.
final class ProgressBoard: @unchecked Sendable {
    private let lock = NSLock()
    private var fractions: [Double]
    private var outputs: [URL?]
    private var errors: [String?]
    init(count: Int) {
        fractions = Array(repeating: 0, count: count)
        outputs = Array(repeating: nil, count: count)
        errors = Array(repeating: nil, count: count)
    }
    func set(_ i: Int, _ f: Double) { lock.lock(); fractions[i] = max(fractions[i], f); lock.unlock() }
    func finish(_ i: Int, output: URL) { lock.lock(); fractions[i] = 1; outputs[i] = output; lock.unlock() }
    func fail(_ i: Int, _ e: String) { lock.lock(); fractions[i] = 1; errors[i] = e; lock.unlock() }
    var overall: Double {
        lock.lock(); defer { lock.unlock() }
        return fractions.isEmpty ? 1 : fractions.reduce(0, +) / Double(fractions.count)
    }
    func outcome(cancelled: Bool) -> JobRunner.Outcome {
        lock.lock(); defer { lock.unlock() }
        var o = JobRunner.Outcome()
        o.outputs = outputs.compactMap { $0 }
        var errs = errors.compactMap { $0 }.filter { $0 != "Cancelled" }
        if cancelled { errs = ["Cancelled"] + errs }
        o.errors = errs
        return o
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
            AppActivation.bringForward()
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
            AppActivation.bringForward()
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
            FloatController.shared.add(urls, near: point)
        }
    }
}
