import AppKit
import SwiftUI
import os

/// State of the Float shelf, shared by the panel and its SwiftUI content.
@MainActor
final class FloatModel: ObservableObject {
    @Published var items: [URL] = []
    @Published var edge: FloatEdge?
    @Published var collapsed = false
    @Published var dropTargeted = false
    /// Only for self-rendered screenshots: draw a glass stand-in instead of live Liquid Glass.
    @Published var staged = false
}

/// A borderless panel that floats above windows but never activates Yuzu or steals focus.
final class FloatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Float: a shelf for files. Drop files on it (or send them with the Control ring), drag them out anywhere,
/// park it on a screen edge as a small glass tab that opens on hover.
@MainActor
final class FloatController {
    static let shared = FloatController()
    let model = FloatModel()
    private let log = Logger(subsystem: "com.sreecharan.yuzu", category: "float")
    private lazy var panel: FloatPanel = makePanel()
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var pendingCollapse: DispatchWorkItem?
    private var visible: NSRect { (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero }
    private static let storeKey = "float.items"
    private(set) var isTestStaged = false

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.storeKey) ?? []
        model.items = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    var isVisible: Bool { panel.isVisible }

    private func makePanel() -> FloatPanel {
        let p = FloatPanel(contentRect: NSRect(x: 0, y: 0, width: FloatGeometry.width, height: 200),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isMovable = false
        p.becomesKeyOnlyIfNeeded = true
        p.animationBehavior = .utilityWindow
        let host = NSHostingView(rootView: FloatView(model: model, controller: self))
        host.sizingOptions = []
        p.contentView = host
        return p
    }

    // MARK: - Items

    func add(_ urls: [URL], near point: NSPoint? = nil) {
        let fresh = urls.filter { !model.items.contains($0) }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { model.items.append(contentsOf: fresh) }
        persist()
        log.info("Float: added \(fresh.count) item(s), now \(self.model.items.count)")
        if !panel.isVisible {
            // Open beside the pointer, far enough from the screen edges that it floats rather than docks.
            let p = point ?? NSEvent.mouseLocation
            let v = screen(at: p)
            let w = FloatGeometry.width, h = FloatGeometry.expandedHeight(items: model.items.count)
            var f = NSRect(x: p.x + 24, y: p.y - h / 2, width: w, height: h)
            f.origin.x = min(max(f.minX, v.minX + 40), v.maxX - w - 40)
            f.origin.y = min(max(f.minY, v.minY + FloatGeometry.margin), v.maxY - h - FloatGeometry.margin)
            model.edge = nil
            model.collapsed = false
            panel.setFrame(f, display: true)
            panel.orderFrontRegardless()
        } else if model.collapsed, let edge = model.edge {
            // Docked: peek open to show what landed, then tuck away again.
            expand(edge)
            scheduleCollapse(after: 1.6)
        } else {
            resizeForItems()
        }
    }

    func remove(_ url: URL) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { model.items.removeAll { $0 == url } }
        persist()
        if model.items.isEmpty, model.edge == nil { hide() } else if !model.collapsed { resizeForItems() }
    }

    func clear() {
        model.items.removeAll()
        persist()
        hide()
    }

    func hide() {
        panel.orderOut(nil)
        model.edge = nil
        model.collapsed = false
    }

    private func persist() {
        guard !isTestStaged else { return }
        UserDefaults.standard.set(model.items.map(\.path), forKey: Self.storeKey)
    }

    private func screen(at p: NSPoint) -> NSRect {
        (NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main)?.visibleFrame ?? .zero
    }

    private func resizeForItems() {
        guard !model.collapsed else { return }
        var f = panel.frame
        let h = FloatGeometry.expandedHeight(items: model.items.count)
        f.origin.y += f.height - h          // keep the top edge still
        f.size.height = h
        animate(to: FloatGeometry.settle(f, in: visible).edge == nil ? FloatGeometry.settle(f, in: visible).frame : f)
    }

    // MARK: - Dragging the shelf

    func dragChanged() {
        let m = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (m, panel.frame.origin) }
        guard let s = dragStart else { return }
        pendingCollapse?.cancel()
        if model.collapsed, model.edge != nil {
            // Pulling the tab away from the edge detaches it into a full shelf under the pointer.
            guard hypot(m.x - s.mouse.x, m.y - s.mouse.y) > 18 else { return }
            model.edge = nil
            model.collapsed = false
            let h = FloatGeometry.expandedHeight(items: model.items.count)
            panel.setFrame(NSRect(x: m.x - FloatGeometry.width / 2, y: m.y - 20 - h + 46, width: FloatGeometry.width, height: h), display: true)
            dragStart = (m, panel.frame.origin)
            return
        }
        model.edge = nil
        panel.setFrameOrigin(NSPoint(x: s.origin.x + m.x - s.mouse.x, y: s.origin.y + m.y - s.mouse.y))
    }

    func dragEnded() {
        dragStart = nil
        let r = FloatGeometry.settle(panel.frame, in: visible)
        if let edge = r.edge {
            dock(edge, centerY: panel.frame.midY)
        } else {
            animate(to: r.frame)
        }
    }

    // MARK: - Docking

    func dock(_ edge: FloatEdge, centerY: CGFloat? = nil) {
        model.edge = edge
        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) { model.collapsed = true }
        animate(to: FloatGeometry.docked(edge, centerY: centerY ?? panel.frame.midY, in: visible))
    }

    /// Docks to whichever edge is closer.
    func dockNearest() {
        let v = visible
        dock(panel.frame.midX < v.midX ? .left : .right)
    }

    func expand(_ edge: FloatEdge) {
        pendingCollapse?.cancel()
        guard model.collapsed else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) { model.collapsed = false }
        animate(to: FloatGeometry.expanded(from: panel.frame, edge: edge, items: model.items.count, in: visible))
    }

    func hoverChanged(_ inside: Bool) {
        guard let edge = model.edge, dragStart == nil else { return }
        if inside { expand(edge) } else if !model.dropTargeted { scheduleCollapse(after: 0.5) }
    }

    func dropTargetChanged(_ on: Bool) {
        model.dropTargeted = on
        if on, let edge = model.edge { expand(edge) }
    }

    private func scheduleCollapse(after delay: Double) {
        pendingCollapse?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let edge = self.model.edge, !self.model.collapsed, self.dragStart == nil else { return }
                if NSMouseInRect(NSEvent.mouseLocation, self.panel.frame, false) { return }
                self.dock(edge, centerY: self.panel.frame.midY)
            }
        }
        pendingCollapse = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func animate(to frame: NSRect) {
        guard !isTestStaged else { panel.setFrame(frame, display: true); return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrame(frame, display: true)
        }
    }

    // MARK: - Item actions

    func open(_ url: URL) { NSWorkspace.shared.open(url) }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }

    // MARK: - Test staging

    /// For screenshots: a separate window off screen that draws a desktop backdrop with the shelf on it,
    /// both expanded (docked right) and as a collapsed tab (docked left). Never touches the real shelf.
    func stageForScreenshot(_ urls: [URL]) -> NSWindow {
        let m = FloatModel()
        m.items = urls
        m.staged = true
        let tabModel = FloatModel()
        tabModel.items = urls
        tabModel.edge = .left
        tabModel.collapsed = true
        tabModel.staged = true
        m.edge = .right
        let view = FloatStage(model: m, tabModel: tabModel, controller: self)
        let size = NSSize(width: 760, height: 470)
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(b)?.isHidden = true }
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        w.backgroundColor = .black
        Offscreen.park(w)
        return w
    }
}
