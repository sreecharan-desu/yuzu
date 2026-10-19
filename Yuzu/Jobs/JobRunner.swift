import AppKit
import os

@MainActor
enum JobRunner {
    private static let log = Logger(subsystem: "com.sreecharan.yuzu", category: "jobs")

    static func run(_ option: WheelOption, urls: [URL], near point: NSPoint, reveal: Bool? = nil,
                    completion: (([URL], [String]) -> Void)? = nil) {
        guard !urls.isEmpty else { return }
        switch option.action {
        case .fileAction(let a):
            FileActions.perform(a, urls: urls, near: point)
            completion?([], [])
        case .convertImage(let f):
            process(urls, title: "Converting to \(f.title)", doneTitle: "Saved as \(f.title)", near: point,
                    reveal: reveal, completion: completion) { url, s in try ImageEngine.convert(url, to: f, settings: s) }
        case .imageTool(let t):
            process(urls, title: "\(t.title)…", doneTitle: "\(t.title) done", near: point,
                    reveal: reveal, completion: completion) { url, s in try ImageEngine.apply(t, to: url, settings: s) }
        }
    }

    private static func process(_ urls: [URL], title: String, doneTitle: String, near point: NSPoint,
                                reveal: Bool?, completion: (([URL], [String]) -> Void)?,
                                _ work: @escaping @Sendable (URL, ImageSettings) throws -> URL) {
        let settings = ImageSettings(quality: Prefs.lossyQuality, compressQuality: Prefs.compressQuality,
                                     preserveMetadata: Prefs.preserveMetadata)
        let shouldReveal = reveal ?? Prefs.reveal
        let hud = HUDController.shared
        hud.begin(title: title, detail: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files", near: point)

        Task.detached(priority: .userInitiated) {
            var outputs: [URL] = []
            var errors: [String] = []
            for (i, url) in urls.enumerated() {
                do {
                    let started = url.startAccessingSecurityScopedResource()
                    defer { if started { url.stopAccessingSecurityScopedResource() } }
                    outputs.append(try work(url, settings))
                } catch {
                    errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
                let fraction = Double(i + 1) / Double(urls.count)
                let next = i + 1 < urls.count ? urls[i + 1].lastPathComponent : nil
                await MainActor.run { hud.progress(fraction, detail: next) }
            }
            let outs = outputs, errs = errors
            await MainActor.run {
                if errs.isEmpty {
                    hud.finish(success: true, title: doneTitle,
                               detail: outs.count == 1 ? outs[0].lastPathComponent : "\(outs.count) files saved",
                               outputs: outs)
                } else {
                    hud.finish(success: false, title: outs.isEmpty ? "Couldn't finish" : "Finished with errors",
                               detail: errs.first ?? "", outputs: outs)
                }
                for e in errs { log.error("\(e, privacy: .public)") }
                if shouldReveal, !outs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(outs) }
                completion?(outs, errs)
            }
        }
    }
}

@MainActor
enum FileActions {
    static func perform(_ action: FileAction, urls: [URL], near point: NSPoint) {
        let hud = HUDController.shared
        switch action {
        case .airDrop:
            guard let s = NSSharingService(named: .sendViaAirDrop), s.canPerform(withItems: urls) else {
                hud.toast("AirDrop is unavailable", near: point, success: false); return
            }
            NSApp.activate()
            s.perform(withItems: urls)
        case .copy:
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects(urls as [NSURL])
            hud.toast(urls.count == 1 ? "Copied \(urls[0].lastPathComponent)" : "Copied \(urls.count) items", near: point)
        case .copyPath:
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            hud.toast(urls.count == 1 ? "Path copied" : "\(urls.count) paths copied", near: point)
        case .move:
            NSApp.activate()
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Move Here"
            panel.message = "Choose where to move \(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items")"
            guard panel.runModal() == .OK, let dir = panel.url else { return }
            var moved = 0
            for u in urls {
                var dest = dir.appendingPathComponent(u.lastPathComponent)
                var n = 2
                while FileManager.default.fileExists(atPath: dest.path) {
                    dest = dir.appendingPathComponent("\(u.deletingPathExtension().lastPathComponent) \(n)")
                        .appendingPathExtension(u.pathExtension)
                    n += 1
                }
                if (try? FileManager.default.moveItem(at: u, to: dest)) != nil { moved += 1 }
            }
            hud.toast(moved == urls.count ? "Moved \(moved) item\(moved == 1 ? "" : "s")" : "Moved \(moved) of \(urls.count)",
                      near: point, success: moved == urls.count)
        case .terminal:
            let first = urls[0]
            let isDir = (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let folder = isDir ? first : first.deletingLastPathComponent()
            guard let term = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
            NSWorkspace.shared.open([folder], withApplicationAt: term, configuration: NSWorkspace.OpenConfiguration())
        case .float:
            hud.toast("Float arrives in a later build", near: point, success: false)
        }
    }
}
