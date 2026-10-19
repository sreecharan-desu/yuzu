import AppKit
import SwiftUI
import os

final class WheelPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Drop target that sits behind the SwiftUI wheel and forwards drag events.
final class WheelDropView: NSView {
    weak var controller: WheelController?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        MainActor.assumeIsolated { controller?.dragMoved(sender, in: self) ?? [] }
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        MainActor.assumeIsolated { controller?.dragMoved(sender, in: self) ?? [] }
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        MainActor.assumeIsolated { controller?.dragExited() }
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        MainActor.assumeIsolated { controller?.performDrop(sender) ?? false }
    }
    override func wantsPeriodicDraggingUpdates() -> Bool { false }
}

@MainActor
final class WheelController {
    static let shared = WheelController()

    let model = WheelModel()
    private let log = Logger(subsystem: "com.sreecharan.yuzu", category: "wheel")
    private lazy var panel: WheelPanel = makePanel()
    private var center = NSPoint.zero          // wheel center in screen coordinates
    private var isShowing = false
    private var isDropping = false
    private var pendingClose: DispatchWorkItem?
    private var demoClose: DispatchWorkItem?

    private func makePanel() -> WheelPanel {
        let size = Theme.canvas
        let p = WheelPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isMovable = false
        p.animationBehavior = .none

        let drop = WheelDropView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        drop.controller = self
        drop.autoresizingMask = [.width, .height]
        let host = NSHostingView(rootView: WheelView(model: model))
        host.frame = drop.bounds
        host.autoresizingMask = [.width, .height]
        drop.addSubview(host)
        p.contentView = drop
        return p
    }

    // MARK: - Opening

    func handleTap(kind: WheelKind, items: [URL], at point: NSPoint) {
        if isShowing {
            if kind == model.kind { return }         // already showing this ring
            model.load(kind: kind, items: items.isEmpty ? model.items : items)
            Feedback.shared.bloom()
            return
        }
        open(kind: kind, items: items, at: point)
    }

    private func open(kind: WheelKind, items: [URL], at point: NSPoint) {
        pendingClose?.cancel()
        demoClose?.cancel()
        isDropping = false
        model.load(kind: kind, items: items)
        model.isOpen = false

        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        let size = Theme.canvas
        var origin = NSPoint(x: point.x - size / 2, y: point.y - size / 2)
        if let vf = screen?.frame {
            origin.x = min(max(origin.x, vf.minX - 30), vf.maxX - size + 30)
            origin.y = min(max(origin.y, vf.minY - 30), vf.maxY - size + 30)
        }
        center = NSPoint(x: origin.x + size / 2, y: origin.y + size / 2)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: size, height: size)), display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        isShowing = true
        Feedback.shared.warmUp()
        DispatchQueue.main.async {
            self.model.isOpen = true
            Feedback.shared.bloom()
        }
        log.info("Ring opened: \(kind.rawValue) with \(items.count) item(s)")
    }

    func close() {
        guard isShowing else { return }
        isShowing = false
        model.isOpen = false
        model.hoverIndex = nil
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isShowing else { return }
                self.panel.orderOut(nil)
            }
        }
        pendingClose = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: item)
    }

    /// Called when the mouse button is released anywhere. If the drop landed on us,
    /// performDrop handles closing; otherwise we close shortly after.
    func dragSessionEnded() {
        guard isShowing, demoClose == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.isDropping else { return }
            self.close()
        }
    }

    // MARK: - Drag destination

    func dragMoved(_ info: NSDraggingInfo, in view: NSView) -> NSDragOperation {
        if model.items.isEmpty {
            let urls = (info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            if !urls.isEmpty { model.load(kind: model.kind, items: urls) }
        }
        let p = view.convert(info.draggingLocation, from: nil)
        updateHover(dx: p.x - view.bounds.midX, dy: view.bounds.midY - p.y)
        return model.hoveredOption == nil ? [] : .copy
    }

    func dragExited() { setHover(nil) }

    private func updateHover(dx: CGFloat, dy: CGFloat) {
        var idx = WheelGeometry.slot(dx: dx, dy: dy, slots: model.slots)
        if let i = idx, i >= model.options.count || !model.options[i].enabled { idx = nil }
        setHover(idx)
    }

    private func setHover(_ idx: Int?) {
        guard idx != model.hoverIndex else { return }
        model.hoverIndex = idx
        if idx != nil { Feedback.shared.tick() }
    }

    func performDrop(_ info: NSDraggingInfo) -> Bool {
        guard let option = model.hoveredOption else { close(); return false }
        isDropping = true
        var urls = (info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                        options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if urls.isEmpty { urls = model.items }
        Feedback.shared.drop()
        let at = center
        close()
        log.info("Dropped \(urls.count) item(s) on \(option.id)")
        DispatchQueue.main.async { JobRunner.run(option, urls: urls, near: at) }
        return true
    }

    // MARK: - Demo / screenshots

    /// Shows the ring at the center of the main screen without a drag (menu "Try the Ring").
    func showDemo(kind: WheelKind = .convert, items: [URL]? = nil, hover: Int? = nil, duration: TimeInterval = 4) {
        let demoItems = items ?? DemoFiles.sampleImage().map { [$0] } ?? []
        let screen = NSScreen.main?.frame ?? .zero
        if isShowing { panel.orderOut(nil); isShowing = false }
        open(kind: kind, items: demoItems, at: NSPoint(x: screen.midX, y: screen.midY))
        if let hover {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self.setHover(hover) }
        }
        demoClose?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.demoClose = nil
                self?.close()
            }
        }
        demoClose = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    var panelForSnapshot: NSWindow { panel }

    /// For the hover cycle in the demo.
    func demoHover(_ idx: Int?) { setHover(idx) }
}

enum DemoFiles {
    /// A sample photo bundled with macOS, used only to preview the ring.
    static func sampleImage() -> URL? {
        let dir = URL(fileURLWithPath: "/System/Library/Desktop Pictures")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.first { ["heic", "jpg", "png"].contains($0.pathExtension.lowercased()) }
    }
}
