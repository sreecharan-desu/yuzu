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
    private let columns = [GridItem(.fixed(112), spacing: Theme.Space.s), GridItem(.fixed(112), spacing: Theme.Space.s)]

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.items.isEmpty {
                empty
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                        ForEach(model.items, id: \.self) { url in
                            FloatTile(url: url, controller: controller)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, Theme.Space.m - 4).padding(.bottom, Theme.Space.m - 4)
                }
            }
        }
        .frame(width: FloatGeometry.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .yuzuGlass(in: shape)
        .overlay(shape.strokeBorder(model.dropTargeted ? Theme.ink.opacity(0.5) : Theme.line, lineWidth: 1))
        .overlay(alignment: .top) {
            // drop target: a single whisper-of-yuzu hairline along the top edge
            Capsule().fill(Theme.yuzu).frame(width: 40, height: 3).padding(.top, 4)
                .opacity(model.dropTargeted ? 1 : 0)
        }
        .shadow(Theme.Shadows.float)
        .animation(Theme.Motion.chrome, value: model.dropTargeted)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous) }

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            Text("Float").type(.headline).foregroundStyle(Theme.ink)
            if !model.items.isEmpty {
                Text("\(model.items.count)")
                    .font(.system(size: 12, weight: .regular)).monospacedDigit()
                    .foregroundStyle(Theme.inkMute)
                    .yuzuNumericTransition()
            }
            Spacer(minLength: 0)
            Button { controller.dockNearest() } label: {
                Image(systemName: "rectangle.righthalf.inset.filled.arrow.right")
            }
            .help("Tuck against the screen edge")
            Button { controller.clear() } label: { Image(systemName: "xmark") }
                .help("Clear and close")
        }
        .buttonStyle(QuietIconButtonStyle(size: 24))
        .padding(.leading, Theme.Space.m).padding(.trailing, Theme.Space.m - 4)
        .frame(height: 48)
        .contentShape(Rectangle())
        .gesture(drag)
    }

    private var empty: some View {
        VStack(spacing: Theme.Space.half) {
            EmphasisText("Hold files ", "here", ".").type(.headline).foregroundStyle(Theme.ink)
            Text("Drag them out to any app or folder.").type(.caption).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card - 4, style: .continuous).fill(Theme.ink.opacity(0.04)))
        .padding(.horizontal, Theme.Space.m - 4).padding(.bottom, Theme.Space.m - 4)
        .materialize(0, rise: 8, blur: 8)
    }
}

/// One file: a Quick Look thumbnail that drags out as the real file.
struct FloatTile: View {
    let url: URL
    let controller: FloatController
    @State private var thumb: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(spacing: Theme.Space.half + 2) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumb {
                        Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().aspectRatio(contentMode: .fit)
                            .padding(Theme.Space.s)
                    }
                }
                .frame(width: 96, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control - 4, style: .continuous))
                .shadow(Theme.Shadows.soft)
                if hovering {
                    Button { controller.remove(url) } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(Theme.surface))
                            .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                    .help("Remove from Float")
                }
            }
            Text(url.lastPathComponent)
                .type(.micro).fontWeight(.regular)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 96)
        }
        .frame(width: 112, height: 104)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.control + 4, style: .continuous)
            .fill(Theme.ink.opacity(hovering ? 0.07 : 0.035)))
        .scaleEffect(hovering ? 1.01 : 1)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control + 4, style: .continuous))
        .onHover { hovering = $0 }
        .animation(Theme.Motion.house(0.6), value: hovering)
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
            topLeadingRadius: edge == .left ? 8 : Theme.Radius.card, bottomLeadingRadius: edge == .left ? 8 : Theme.Radius.card,
            bottomTrailingRadius: edge == .left ? Theme.Radius.card : 8, topTrailingRadius: edge == .left ? Theme.Radius.card : 8, style: .continuous)
        ZStack {
            if thumbs.isEmpty {
                Image(systemName: "tray").font(.system(size: 16, weight: .regular)).foregroundStyle(Theme.inkSoft)
            } else {
                ForEach(Array(thumbs.prefix(3).enumerated().reversed()), id: \.offset) { i, img in
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
                        .shadow(Theme.Shadows.soft)
                        .offset(y: CGFloat(i) * -6)
                        .scaleEffect(1 - CGFloat(i) * 0.06)
                }
            }
            if !model.items.isEmpty {
                Text("\(model.items.count)")
                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Theme.onInk)
                    .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20)
                    .background(Capsule().fill(Theme.ink))
                    .offset(y: 40)
            }
        }
        .frame(width: FloatGeometry.tab.width, height: FloatGeometry.tab.height)
        .yuzuGlass(in: shape)
        .overlay(shape.strokeBorder(model.dropTargeted ? Theme.ink.opacity(0.5) : Theme.line, lineWidth: 1))
        .contentShape(shape)
        .onAppear(perform: load)
        .whenChange(of: model.items) { _ in load() }
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
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var model: FloatModel
    @ObservedObject var tabModel: FloatModel
    let controller: FloatController

    var body: some View {
        ZStack {
            if let bg = Backdrop.smallImage(scheme == .dark ? .graphite : .pearl, aspect: 760.0 / 470.0, matching: []) {
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
