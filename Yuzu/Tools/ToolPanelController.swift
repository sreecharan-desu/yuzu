import AppKit
import SwiftUI

/// Hands panels what they need to finish: close the window, or close and run a job with a toast.
@MainActor
final class ToolEnv {
    let tool: FileTool
    let urls: [URL]
    weak var window: NSWindow?
    var onClose: (() -> Void)?

    init(tool: FileTool, urls: [URL]) { self.tool = tool; self.urls = urls }

    var anchor: NSPoint {
        guard let f = window?.frame else { return NSEvent.mouseLocation }
        return NSPoint(x: f.midX, y: f.midY)
    }

    func close() {
        window?.close()
        onClose?()
    }

    /// Closes the panel, then runs `work` per file (or once for all files) with progress and a result toast.
    func run(_ label: String, combined: Bool = false, work: @escaping @Sendable ([URL], JobContext) throws -> URL) {
        let point = anchor
        let units = combined ? [urls] : urls.map { [$0] }
        close()
        JobRunner.execute(label: label, units: units, near: point, work: work)
    }
}

@MainActor
final class ToolPanelController: NSObject, NSWindowDelegate {
    private static var live: [ToolPanelController] = []
    static var lastWindowNumber = 0
    let window: NSWindow
    let env: ToolEnv

    @discardableResult
    static func show(_ tool: FileTool, urls: [URL], background: Bool = false) -> ToolPanelController {
        let c = ToolPanelController(tool: tool, urls: urls)
        live.append(c)
        c.present(background: background)
        return c
    }

    static func closeAll() { live.forEach { $0.window.close() } }

    private init(tool: FileTool, urls: [URL]) {
        env = ToolEnv(tool: tool, urls: urls)
        let size = Self.size(for: tool)
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "\(tool.title) – \(urls.first?.lastPathComponent ?? "")"
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        w.minSize = NSSize(width: 640, height: 440)
        w.isMovableByWindowBackground = false
        w.backgroundColor = .windowBackgroundColor
        window = w
        super.init()
        w.delegate = self
        env.window = w
        let root = ToolRoot(env: env).environment(\.colorScheme, NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
        w.contentView = NSHostingView(rootView: root)
    }

    static func size(for tool: FileTool) -> NSSize {
        switch tool {
        case .metadata: return NSSize(width: 760, height: 560)
        case .addBackground: return NSSize(width: 980, height: 730)
        case .trim, .speed, .split, .bleep, .channels: return NSSize(width: 860, height: 560)
        case .organize: return NSSize(width: 900, height: 620)
        default: return NSSize(width: 940, height: 640)
        }
    }

    private func present(background: Bool) {
        if background {
            // For automated screenshots: render behind other windows without taking focus.
            // Placed past the right edge of all screens and deaf to the mouse: nothing appears or can be clicked.
            Offscreen.park(window)
        } else {
            window.center()
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
        Self.lastWindowNumber = window.windowNumber
    }

    func windowWillClose(_ notification: Notification) {
        Self.live.removeAll { $0 === self }
    }
}

/// Picks the panel for a tool.
struct ToolRoot: View {
    let env: ToolEnv

    var body: some View {
        Group {
            switch env.tool {
            case .crop: CropPanel(env: env)
            case .editPhoto: EditPhotoPanel(env: env)
            case .annotate: AnnotatePanel(env: env)
            case .redact: RedactPanel(env: env)
            case .addBackground: AddBackgroundPanel(env: env)
            case .resize: ResizePanel(env: env)
            case .metadata: MetadataPanel(env: env)
            case .trim: TrimPanel(env: env)
            case .speed: SpeedPanel(env: env)
            case .split: SplitPanel(env: env)
            case .cropVideo: CropVideoPanel(env: env)
            case .bleep: BleepPanel(env: env)
            case .channels: ChannelsPanel(env: env)
            case .splitPDF: SplitPDFPanel(env: env)
            case .organize: OrganizePanel(env: env)
            default: Text("\(env.tool.title) runs without a panel.").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
    }
}

// MARK: - Shared chrome

struct ToolScaffold<Stage: View, Controls: View>: View {
    let env: ToolEnv
    var subtitle: String? = nil
    let primary: String
    var primaryEnabled = true
    let onPrimary: () -> Void
    @ViewBuilder var stage: () -> Stage
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: env.tool.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accentDeep)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.accent.opacity(0.16)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(env.tool == .addBackground ? "Add Background" : env.tool.title).font(.system(size: 13, weight: .semibold))
                    Text(subtitle ?? fileLine).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
            .frame(height: 52)

            HStack(spacing: 0) {
                stage()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(StageBackground())
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.leading, 14).padding(.bottom, 14).padding(.trailing, 4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) { controls() }
                        .padding(.horizontal, 16).padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 272)
            }

            HStack {
                if env.urls.count > 1 {
                    Text("Applies to all \(env.urls.count) files").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { env.close() }.keyboardShortcut(.cancelAction).controlSize(.large)
                Button(primary, action: onPrimary)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentDeep)
                    .controlSize(.large)
                    .disabled(!primaryEnabled)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(.bar)
        }
    }

    private var fileLine: String {
        guard let first = env.urls.first else { return "" }
        let size = SizeText.format(SizeText.of([first]))
        return env.urls.count > 1 ? "\(first.lastPathComponent) and \(env.urls.count - 1) more" : "\(first.lastPathComponent) · \(size)"
    }
}

struct StageBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        // Soft checkerboard so transparent areas read as transparent.
        Canvas { ctx, size in
            let s: CGFloat = 10
            let a = scheme == .dark ? Color.white.opacity(0.035) : Color.black.opacity(0.04)
            for y in stride(from: 0, to: size.height, by: s) {
                for x in stride(from: 0, to: size.width, by: s) where (Int(x / s) + Int(y / s)) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(a))
                }
            }
        }
        .background(scheme == .dark ? Color.black.opacity(0.28) : Color.black.opacity(0.05))
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
    }
}

/// Slider with a value readout and a reset arrow, as one row.
struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var neutral: Double = 0
    var format: String = "%.0f"
    var unit: String = ""
    var display: ((Double) -> String)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 12))
                Spacer()
                Text(display?(value) ?? (String(format: format, value) + unit)).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                Button { withAnimation(.snappy) { value = neutral } } label: {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(value == neutral ? Color.secondary.opacity(0.35) : Theme.accentDeep)
                .disabled(value == neutral)
                .help("Reset")
            }
            Slider(value: $value, in: range).controlSize(.small).tint(Theme.accentDeep)
        }
    }
}

/// Segmented choice built from plain buttons so it tints with the accent.
struct ChipPicker<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { opt in
                Button { withAnimation(.snappy) { selection = opt.0 } } label: {
                    Text(opt.1).font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selection == opt.0 ? Theme.accentDeep : Color.primary.opacity(0.07)))
                        .foregroundStyle(selection == opt.0 ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Loads a downsampled preview of an image off the main thread.
@MainActor
final class PreviewLoader: ObservableObject {
    @Published var cgImage: CGImage?
    @Published var pixelSize: CGSize = .zero
    @Published var failed = false

    func load(_ url: URL, maxPixel: Int = 1800) {
        Task.detached(priority: .userInitiated) {
            let full = (try? ImageEngine.decode(url, maxPixel: 1))?.properties
            let w = full?[kCGImagePropertyPixelWidth] as? Int ?? 0, h = full?[kCGImagePropertyPixelHeight] as? Int ?? 0
            let img = try? ImageEngine.decode(url, maxPixel: maxPixel).image
            await MainActor.run {
                self.cgImage = img
                self.failed = img == nil
                if let img {
                    // Full size respects orientation the same way the preview does.
                    let swap = (img.width > img.height) != (w > h) && w > 0
                    self.pixelSize = w > 0 ? CGSize(width: swap ? h : w, height: swap ? w : h) : CGSize(width: img.width, height: img.height)
                }
            }
        }
    }
}

/// Shows an image fitted in the stage and gives overlays the fitted rect.
struct ImageStage<Overlay: View>: View {
    let image: CGImage?
    var padding: CGFloat = 22
    @ViewBuilder var overlay: (CGRect) -> Overlay

    var body: some View {
        GeometryReader { geo in
            if let image {
                let rect = fit(CGSize(width: image.width, height: image.height), in: geo.size)
                ZStack(alignment: .topLeading) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: rect.width, height: rect.height)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                        .offset(x: rect.minX, y: rect.minY)
                    overlay(rect)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func fit(_ s: CGSize, in box: CGSize) -> CGRect {
        let avail = CGSize(width: max(1, box.width - padding * 2), height: max(1, box.height - padding * 2))
        let k = min(avail.width / s.width, avail.height / s.height)
        let w = s.width * k, h = s.height * k
        return CGRect(x: (box.width - w) / 2, y: (box.height - h) / 2, width: w, height: h)
    }
}

extension CGRect {
    /// Converts a normalized rect (0...1, top-left origin) into this rect's space.
    func denormalize(_ n: CGRect) -> CGRect {
        CGRect(x: minX + n.minX * width, y: minY + n.minY * height, width: n.width * width, height: n.height * height)
    }
    func normalize(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max((p.x - minX) / width, 0), 1), y: min(max((p.y - minY) / height, 0), 1))
    }
    func denormalize(_ p: CGPoint) -> CGPoint { CGPoint(x: minX + p.x * width, y: minY + p.y * height) }
}
