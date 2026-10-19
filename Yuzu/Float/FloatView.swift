import AppKit
import SwiftUI

/// The Float shelf: a glass card of file tiles, or a small glass tab when parked on an edge.
struct FloatView: View {
    @ObservedObject var model: FloatModel
    let controller: FloatController

    var body: some View {
        Group {
            if model.collapsed, let edge = model.edge {
                FloatTab(model: model, edge: edge)
                    .gesture(shelfDrag)
                    .onTapGesture { controller.expand(edge) }
            } else {
                FloatCard(model: model, controller: controller, drag: shelfDrag)
            }
        }
        .onHover { controller.hoverChanged($0) }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            controller.add(files)
            return true
        } isTargeted: { controller.dropTargetChanged($0) }
    }

    private var shelfDrag: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { _ in controller.dragChanged() }
            .onEnded { _ in controller.dragEnded() }
    }
}

private struct FloatCard<G: Gesture>: View {
    @ObservedObject var model: FloatModel
    let controller: FloatController
    let drag: G
    private let columns = [GridItem(.fixed(112), spacing: 8), GridItem(.fixed(112), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.items.isEmpty {
                empty
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(model.items, id: \.self) { url in
                            FloatTile(url: url, controller: controller)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 10).padding(.bottom, 10)
                }
            }
        }
        .frame(width: FloatGeometry.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(shape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.28)))
        .glassEffect(.regular, in: shape)
        .overlay(shape.strokeBorder(model.dropTargeted ? Theme.accentDeep : Color.white.opacity(0.16),
                                    lineWidth: model.dropTargeted ? 2 : 1))
        .animation(.easeOut(duration: 0.15), value: model.dropTargeted)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 20, style: .continuous) }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "paperclip")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.accent))
            Text("Float").font(.system(size: 13, weight: .semibold, design: .rounded))
            if !model.items.isEmpty {
                Text("\(model.items.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { controller.dockNearest() } label: {
                Image(systemName: "rectangle.righthalf.inset.filled.arrow.right")
            }
            .help("Tuck against the screen edge")
            Button { controller.clear() } label: { Image(systemName: "xmark") }
                .help("Clear and close")
        }
        .buttonStyle(FloatIconButton())
        .padding(.horizontal, 12)
        .frame(height: 46)
        .contentShape(Rectangle())
        .gesture(drag)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: 22, weight: .regular))
            Text("Drop files here").font(.system(size: 12, weight: .medium))
            Text("Drag them out to any app or folder").font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])).foregroundStyle(.secondary.opacity(0.5)))
        .padding(.horizontal, 10).padding(.bottom, 10)
    }
}

private struct FloatIconButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.07)))
            .contentShape(Circle())
    }
}

/// One file: a Quick Look thumbnail that drags out as the real file.
struct FloatTile: View {
    let url: URL
    let controller: FloatController
    @State private var thumb: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumb {
                        Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().aspectRatio(contentMode: .fit)
                            .padding(10)
                    }
                }
                .frame(width: 104, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                if hovering {
                    Button { controller.remove(url) } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(.regularMaterial))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                    .help("Remove from Float")
                }
            }
            Text(url.lastPathComponent)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 108)
        }
        .padding(.vertical, 5)
        .frame(width: 112, height: 98)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(hovering ? 0.09 : 0.04)))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { controller.open(url) }
        .onDrag { NSItemProvider(object: url as NSURL) }
        .contextMenu {
            Button("Open") { controller.open(url) }
            Button("Show in Finder") { controller.reveal(url) }
            Button("Copy") { controller.copy(url) }
            Divider()
            Button("Remove from Float") { controller.remove(url) }
        }
        .help(url.path)
        .onAppear {
            ThumbnailCache.shared.thumbnail(for: url, side: 160) { thumb = $0 }
        }
    }
}

/// The parked shelf: a glass tab with a little fanned stack of what's inside and a count badge.
struct FloatTab: View {
    @ObservedObject var model: FloatModel
    let edge: FloatEdge
    @State private var thumbs: [NSImage] = []

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: edge == .left ? 6 : 18, bottomLeadingRadius: edge == .left ? 6 : 18,
            bottomTrailingRadius: edge == .left ? 18 : 6, topTrailingRadius: edge == .left ? 18 : 6, style: .continuous)
        ZStack {
            if thumbs.isEmpty {
                Image(systemName: "paperclip").font(.system(size: 20, weight: .semibold)).foregroundStyle(.secondary)
            } else {
                ForEach(Array(thumbs.prefix(3).enumerated().reversed()), id: \.offset) { i, img in
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1))
                        .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                        .rotationEffect(.degrees(Double(i) * (edge == .left ? 7 : -7)))
                        .offset(x: CGFloat(i) * 3, y: CGFloat(i) * -5)
                }
            }
            if !model.items.isEmpty {
                Text("\(model.items.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20)
                    .background(Capsule().fill(Theme.accent))
                    .offset(x: 14, y: 30)
            }
        }
        .frame(width: FloatGeometry.tab.width, height: FloatGeometry.tab.height)
        .background(shape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.28)))
        .glassEffect(.regular, in: shape)
        .overlay(shape.strokeBorder(model.dropTargeted ? Theme.accentDeep : Color.white.opacity(0.18), lineWidth: model.dropTargeted ? 2 : 1))
        .contentShape(shape)
        .onAppear(perform: load)
        .onChange(of: model.items) { _, _ in load() }
    }

    private func load() {
        thumbs = []
        for u in model.items.suffix(3).reversed() {
            ThumbnailCache.shared.thumbnail(for: u, side: 160) { img in
                if thumbs.count < 3 { thumbs.append(img) }
            }
        }
    }
}

/// Screenshot staging: a desktop-like backdrop with the tab parked left and the open shelf docked right.
struct FloatStage: View {
    @ObservedObject var model: FloatModel
    @ObservedObject var tabModel: FloatModel
    let controller: FloatController

    var body: some View {
        ZStack {
            if let bg = Backdrop.smallImage(.aurora, aspect: 760.0 / 470.0, matching: []) {
                Image(decorative: bg, scale: 1).resizable().aspectRatio(contentMode: .fill)
            }
            HStack(alignment: .center, spacing: 0) {
                FloatTab(model: tabModel, edge: .left)
                Spacer()
                FloatCard(model: model, controller: controller, drag: DragGesture())
                    .frame(height: FloatGeometry.expandedHeight(items: model.items.count))
                    .padding(.trailing, 2)
            }
        }
        .frame(width: 760, height: 470)
        .clipped()
        .ignoresSafeArea()
    }
}
