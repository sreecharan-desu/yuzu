import AppKit
import SwiftUI
import Vision

/// Finds QR codes and barcodes with Vision and shows them in a small results window.
@MainActor
enum QRReader {
    struct Found: Identifiable, Hashable, Sendable { let id = UUID(); let file: String; let symbology: String; let payload: String }
    private static var window: NSWindow?

    nonisolated static func detect(_ url: URL) throws -> [Found] {
        let img = try ImageEngine.decode(url, maxPixel: 3000).image
        let req = VNDetectBarcodesRequest()
        try VNImageRequestHandler(cgImage: img, options: [:]).perform([req])
        return (req.results ?? []).compactMap { o in
            guard let p = o.payloadStringValue, !p.isEmpty else { return nil }
            let sym = o.symbology.rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: "")
            return Found(file: url.lastPathComponent, symbology: sym, payload: p)
        }
    }

    static func run(urls: [URL], near point: NSPoint, quiet: Bool, completion: ((JobRunner.Outcome) -> Void)?) {
        if !quiet { HUDController.shared.begin(title: "Reading codes…", near: point) }
        Task.detached(priority: .userInitiated) {
            var found: [Found] = []
            var errors: [String] = []
            for u in urls {
                do { found += try detect(u) } catch { errors.append("\(u.lastPathComponent): \(error.localizedDescription)") }
            }
            let f = found, e = errors
            await MainActor.run {
                var outcome = JobRunner.Outcome()
                outcome.errors = e
                if !quiet {
                    if f.isEmpty {
                        HUDController.shared.info(e.isEmpty ? "No codes found" : "Couldn't read the image", symbol: "qrcode", near: point)
                    } else {
                        HUDController.shared.success("Found \(f.count) code\(f.count == 1 ? "" : "s")", symbol: "qrcode")
                        show(f)
                    }
                }
                lastResults = f
                completion?(outcome)
            }
        }
    }

    static var lastResults: [Found] = []
    static func closeWindow() { window?.close(); window = nil }

    static func show(_ items: [Found], background: Bool = false) {
        window?.close()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
                         styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.title = "QR Codes"
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.level = background ? .normal : .floating
        w.contentView = NSHostingView(rootView: QRResultsView(items: items) { w.close() })
        window = w
        if background {
            Offscreen.park(w)
        } else {
            w.center(); NSApp.activate(); w.makeKeyAndOrderFront(nil)
        }
        ToolPanelController.lastWindowNumber = w.windowNumber
    }
}

struct QRResultsView: View {
    let items: [QRReader.Found]
    let close: () -> Void
    @State private var copied: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "qrcode.viewfinder").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accentDeep)
                    .frame(width: 26, height: 26).background(Circle().fill(Theme.accent.opacity(0.16)))
                Text("\(items.count) code\(items.count == 1 ? "" : "s") found").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.leading, 84).padding(.trailing, 16).frame(height: 52)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.payload).font(.system(size: 12.5, weight: .medium)).textSelection(.enabled).lineLimit(3)
                                Text("\(item.symbology) · \(item.file)").font(.system(size: 10.5)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let url = URL(string: item.payload), url.scheme?.hasPrefix("http") == true {
                                Button("Open") { NSWorkspace.shared.open(url) }
                            }
                            Button(copied == item.id ? "Copied" : "Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.payload, forType: .string)
                                copied = item.id
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
        .frame(minWidth: 420, minHeight: 220)
    }
}
