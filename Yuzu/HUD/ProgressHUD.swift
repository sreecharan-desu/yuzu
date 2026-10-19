import AppKit
import SwiftUI
import Combine

@MainActor
final class HUDModel: ObservableObject {
    enum State { case working, done, failed }
    @Published var title = ""
    @Published var detail = ""
    @Published var fraction: Double = 0
    @Published var state: State = .working
    @Published var visible = false
    var outputs: [URL] = []
}

@MainActor
final class HUDController {
    static let shared = HUDController()
    let model = HUDModel()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private let size = NSSize(width: 340, height: 104)

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        let host = NSHostingView(rootView: HUDView(model: model, onClose: { [weak self] in self?.hide() },
                                                   onReveal: { [weak self] in self?.reveal() }))
        host.frame = NSRect(origin: .zero, size: size)
        p.contentView = host
        panel = p
        return p
    }

    private func place(near point: NSPoint) {
        let p = ensurePanel()
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y + 60)
        if let vf = screen?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
            origin.y = min(max(origin.y, vf.minY + 8), vf.maxY - size.height - 8)
        }
        p.setFrameOrigin(origin)
        p.orderFrontRegardless()
    }

    func begin(title: String, detail: String, near point: NSPoint) {
        hideWork?.cancel()
        model.title = title
        model.detail = detail
        model.fraction = 0.04
        model.state = .working
        model.outputs = []
        place(near: point)
        withAnimation(Theme.bloom) { model.visible = true }
    }

    func progress(_ f: Double, detail: String?) {
        withAnimation(.easeOut(duration: 0.2)) { model.fraction = max(model.fraction, f) }
        if let detail { model.detail = detail }
    }

    func finish(success: Bool, title: String, detail: String, outputs: [URL]) {
        model.outputs = outputs
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            model.fraction = 1
            model.state = success ? .done : .failed
            model.title = title
            model.detail = detail
        }
        scheduleHide(after: success ? 2.2 : 6)
    }

    func toast(_ text: String, near point: NSPoint, success: Bool = true) {
        hideWork?.cancel()
        model.title = text
        model.detail = ""
        model.fraction = 1
        model.state = success ? .done : .failed
        model.outputs = []
        place(near: point)
        withAnimation(Theme.bloom) { model.visible = true }
        scheduleHide(after: 1.6)
    }

    private func scheduleHide(after s: TimeInterval) {
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.hide() } }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: w)
    }

    func hide() {
        withAnimation(Theme.close) { model.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !self.model.visible else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func reveal() {
        if !model.outputs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(model.outputs) }
        hide()
    }
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel
    let onClose: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if model.state == .done {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accentDeep)
                            .transition(.scale.combined(with: .opacity))
                    } else if model.state == .failed {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    Text(model.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                }
                if !model.detail.isEmpty {
                    Text(model.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.middle)
                }
                if model.state == .working {
                    ProgressBar(fraction: model.fraction)
                } else if !model.outputs.isEmpty {
                    Text("Click to show in Finder").font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onReveal)
        .scaleEffect(model.visible ? 1 : 0.92)
        .opacity(model.visible ? 1 : 0)
        .offset(y: model.visible ? 0 : -8)
        .frame(width: 340, height: 104)
    }
}

private struct ProgressBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, g.size.width * fraction))
            }
        }
        .frame(height: 5)
    }
}
