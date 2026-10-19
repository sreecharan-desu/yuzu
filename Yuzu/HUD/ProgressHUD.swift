import AppKit
import SwiftUI
import Combine

/// One compact glass pill for progress and results: icon + one line + optional size delta.
@MainActor
final class HUDModel: ObservableObject {
    enum State: Equatable { case working, success, failure, info }
    @Published var state: State = .working
    @Published var symbol = "checkmark.circle.fill"
    @Published var title = ""
    @Published var detail = ""
    @Published var fraction: Double = 0
    @Published var visible = false
    @Published var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    @Published var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    var outputs: [URL] = []
    var fullError = ""
}

enum HUDPlacement: String { case nearPointer, topCenter }

@MainActor
final class HUDController {
    static let shared = HUDController()
    let model = HUDModel()
    var onCancel: (() -> Void)?
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private let size = NSSize(width: 520, height: 96)
    private var observers: [NSObjectProtocol] = []

    var panelForSnapshot: NSWindow? { panel }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.animationBehavior = .none
        let host = NSHostingView(rootView: HUDView(model: model,
                                                   onTap: { [weak self] in self?.tapped() },
                                                   onCancel: { [weak self] in self?.onCancel?() }))
        host.frame = NSRect(origin: .zero, size: size)
        p.contentView = host
        panel = p
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                self?.model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        })
        return p
    }

    private func place(near point: NSPoint) {
        let p = ensurePanel()
        let placement = HUDPlacement(rawValue: Prefs.d.string(forKey: Prefs.Key.hudPlacement) ?? "") ?? .nearPointer
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        var origin: NSPoint
        switch placement {
        case .topCenter: origin = NSPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 6)
        case .nearPointer: origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        }
        origin.x = min(max(origin.x, vf.minX), vf.maxX - size.width)
        origin.y = min(max(origin.y, vf.minY), vf.maxY - size.height)
        p.setFrameOrigin(origin)
        p.orderFrontRegardless()
    }

    private var spring: Animation { model.reduceMotion ? .easeOut(duration: 0.15) : Theme.Motion.house(0.6) }

    private func show(near point: NSPoint?) {
        hideWork?.cancel()
        if let point, !model.visible { place(near: point) } else if panel == nil, let point { place(near: point) }
        panel?.orderFrontRegardless()
        withAnimation(spring) { model.visible = true }
    }

    func begin(title: String, near point: NSPoint) {
        model.outputs = []
        model.fullError = ""
        withAnimation(spring) {
            model.state = .working
            model.symbol = "arrow.triangle.2.circlepath"
            model.title = title
            model.detail = ""
            model.fraction = 0
        }
        show(near: point)
    }

    func progress(_ f: Double, detail: String? = nil) {
        guard model.state == .working else { return }
        withAnimation(.linear(duration: 0.12)) { model.fraction = max(model.fraction, min(f, 1)) }
        if let detail { model.detail = detail }
    }

    func success(_ title: String, detail: String = "", symbol: String = "checkmark.circle.fill", outputs: [URL] = [], near point: NSPoint? = nil) {
        model.outputs = outputs
        withAnimation(spring) {
            model.state = .success
            model.symbol = symbol
            model.title = title
            model.detail = detail
            model.fraction = 1
        }
        show(near: point)
        scheduleHide(after: 1.8)
    }

    func failure(_ title: String, detail: String, near point: NSPoint? = nil) {
        model.outputs = []
        model.fullError = detail
        withAnimation(spring) {
            model.state = .failure
            model.symbol = "exclamationmark.triangle.fill"
            model.title = title
            model.detail = detail
        }
        show(near: point)
        scheduleHide(after: 4.5)
    }

    func info(_ title: String, symbol: String, near point: NSPoint) {
        model.outputs = []
        withAnimation(spring) {
            model.state = .info
            model.symbol = symbol
            model.title = title
            model.detail = ""
        }
        show(near: point)
        scheduleHide(after: 1.8)
    }

    private func scheduleHide(after s: TimeInterval) {
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.hide() } }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: w)
    }

    func hide() {
        hideWork?.cancel()
        withAnimation(model.reduceMotion ? .easeIn(duration: 0.12) : Theme.Motion.house(0.3)) { model.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.model.visible else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func tapped() {
        switch model.state {
        case .working: return
        case .success:
            if !model.outputs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(model.outputs) }
        default: break
        }
        hide()
    }

    /// Keeps the pill visible (for screenshots and tests).
    func hold() { hideWork?.cancel() }
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel
    let onTap: () -> Void
    let onCancel: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        pill
            .scaleEffect(model.visible ? 1 : (model.reduceMotion ? 1 : 0.96))
            .offset(y: model.visible ? 0 : (model.reduceMotion ? 0 : 12))
            .blur(radius: model.visible || model.reduceMotion ? 0 : 8)
            .opacity(model.visible ? 1 : 0)
            .frame(width: 520, height: 96)
    }

    private var tint: Color {
        switch model.state {
        case .failure: return Theme.danger
        default: return Theme.ink
        }
    }

    private var pill: some View {
        HStack(spacing: Theme.Space.s + 2) {
            leading
            Text(model.title)
                .font(.system(size: 13, weight: .medium)).tracking(-0.15)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentTransition(.opacity)
            if !model.detail.isEmpty {
                Text(model.detail)
                    .font(.system(size: 12, weight: .regular).monospacedDigit())
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.numericText())
            }
            if model.state == .working && model.fraction > 0.005 && model.detail.isEmpty {
                Text("\(Int(model.fraction * 100))%")
                    .font(.system(size: 12, weight: .regular).monospacedDigit())
                    .foregroundStyle(Theme.inkSoft)
                    .contentTransition(.numericText())
            }
            if model.state == .working {
                Button(action: onCancel) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Theme.ink.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .help("Cancel")
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.leading, Theme.Space.m - 4)
        .padding(.trailing, Theme.Space.m)
        .frame(height: 40)
        .frame(maxWidth: 480)
        .fixedSize(horizontal: true, vertical: false)
        .background(background)
        .contentShape(Capsule())
        .onTapGesture(perform: onTap)
        .help(model.fullError)
        .animation(Theme.Motion.house(0.5), value: model.state)
        .animation(Theme.Motion.house(0.5), value: model.title)
    }

    @ViewBuilder private var leading: some View {
        ZStack {
            if model.state == .working {
                Circle().stroke(Theme.ink.opacity(0.10), lineWidth: 2)
                Circle().trim(from: 0, to: max(0.04, model.fraction))
                    .stroke(Theme.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Image(systemName: model.symbol)
                    .font(.system(size: 18, weight: .regular))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Theme.onInk, tint)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(width: 20, height: 20)
    }

    @ViewBuilder private var background: some View {
        if model.reduceTransparency {
            Capsule()
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                .shadow(Theme.Shadows.float)
        } else {
            Capsule()
                .fill(Color.clear)
                .glassEffect(.regular, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                .shadow(Theme.Shadows.float)
        }
    }
}

enum SizeText {
    static func of(_ urls: [URL]) -> Int64 {
        urls.reduce(0) { total, u in
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if v?.isDirectory == true {
                let e = FileManager.default.enumerator(at: u, includingPropertiesForKeys: [.fileSizeKey])
                var s: Int64 = 0
                while let f = e?.nextObject() as? URL { s += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
                return total + s
            }
            return total + Int64(v?.fileSize ?? 0)
        }
    }

    static func format(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    /// "2.1 MB → 740 KB  −65%"
    static func delta(from a: Int64, to b: Int64) -> String {
        guard a > 0, b > 0 else { return b > 0 ? format(b) : "" }
        let pct = Int(((Double(b) - Double(a)) / Double(a) * 100).rounded())
        let sign = pct > 0 ? "+" : (pct < 0 ? "−" : "±")
        return "\(format(a)) → \(format(b))  \(sign)\(abs(pct))%"
    }
}
