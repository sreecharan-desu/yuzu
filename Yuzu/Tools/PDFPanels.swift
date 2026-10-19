import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// Page thumbnails rendered off the main thread.
@MainActor
final class PDFThumbs: ObservableObject {
    @Published var pages: [CGImage] = []
    @Published var count = 0

    func load(_ url: URL) {
        Task.detached(priority: .userInitiated) {
            guard let doc = PDFDocument(url: url) else { return }
            var out: [CGImage] = []
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                let img = page.thumbnail(of: CGSize(width: 260, height: 260), for: .cropBox)
                if let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) { out.append(cg) }
            }
            let n = doc.pageCount
            let done = out
            await MainActor.run { self.pages = done; self.count = n }
        }
    }
}

private struct PageTile: View {
    let image: CGImage?
    let label: String
    var rotation = 0
    var tint: Color? = nil
    var selected = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                if let image {
                    Image(decorative: image, scale: 2).resizable().scaledToFit()
                        .rotationEffect(.degrees(Double(rotation)))
                        .scaleEffect(rotation % 180 == 0 ? 1 : 0.76)   // a turned page still fits its tile
                        .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
                } else { RoundedRectangle(cornerRadius: 4).fill(Theme.step200) }
            }
            .frame(height: 118)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(tint?.opacity(0.18) ?? Color.clear))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.accentDeep, lineWidth: selected ? 2.5 : 0))
            Text(label).font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(tint ?? .secondary)
        }
    }
}

// MARK: - Split PDF

struct SplitPDFPanel: View {
    let env: ToolEnv
    @StateObject private var thumbs = PDFThumbs()
    @State private var mode: Mode = .every
    @State private var every = 1.0
    @State private var custom = ""
    @State private var cutsAfter: Set<Int> = []

    enum Mode: Hashable { case every, pick, ranges }
    /// Group markers: ink steps, not a rainbow.
    static let tints: [Color] = [Theme.ink, Theme.inkSoft, Theme.step300, Theme.inkMute]

    var body: some View {
        ToolScaffold(env: env, primary: "Split into \(groups.count) PDF\(groups.count == 1 ? "" : "s")", primaryEnabled: groups.count > 1, onPrimary: save) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 14)], spacing: 16) {
                    ForEach(0..<thumbs.pages.count, id: \.self) { i in
                        let g = groupIndex(of: i)
                        PageTile(image: thumbs.pages[i], label: g.map { "Page \(i + 1) · Part \($0 + 1)" } ?? "Page \(i + 1) · skipped",
                                 tint: g.map { Self.tints[$0 % Self.tints.count] })
                            .onTapGesture { if mode == .pick { toggleCut(after: i) } }
                    }
                }
                .padding(18)
            }
        } controls: {
            SectionLabel("Split")
            ChipPicker(options: [(Mode.every, "Every N"), (Mode.pick, "Pick"), (Mode.ranges, "Ranges")], selection: $mode)
            switch mode {
            case .every:
                SliderRow(label: "Pages per file", value: $every, range: 1...Double(max(thumbs.count - 1, 1)), neutral: 1, display: { "\(Int($0))" })
            case .pick:
                Text("Click a page to start a new file after it. Click again to undo.").font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Clear") { cutsAfter.removeAll() }.disabled(cutsAfter.isEmpty)
            case .ranges:
                TextField("1-3, 4, 5-8", text: $custom).textFieldStyle(.roundedBorder)
                Text("Each range becomes one file. Pages outside every range are skipped.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            SectionLabel("Result")
            ForEach(Array(groups.enumerated()), id: \.offset) { i, g in
                HStack(spacing: 6) {
                    Circle().fill(Self.tints[i % Self.tints.count]).frame(width: 8, height: 8)
                    Text("Part \(i + 1)").font(.system(size: 12))
                    Spacer()
                    Text(g.count == 1 ? "page \(g[0] + 1)" : "pages \(g.first! + 1)–\(g.last! + 1)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { if let u = env.urls.first { thumbs.load(u) } }
        .onReceive(NotificationCenter.default.publisher(for: .yuzuPanelSet)) { n in
            let info = (n.userInfo as? [String: String]) ?? [:]
            if let e = info["every"].flatMap(Double.init) { mode = .every; every = e }
            if let r = info["ranges"] { mode = .ranges; custom = r }
            if let p = info["pick"] { mode = .pick; cutsAfter = Set(p.split(separator: ",").compactMap { Int($0).map { $0 - 1 } }) }
        }
    }

    private var groups: [[Int]] {
        let n = thumbs.count
        guard n > 0 else { return [] }
        switch mode {
        case .every:
            let k = max(1, Int(every))
            return stride(from: 0, to: n, by: k).map { Array($0..<min($0 + k, n)) }
        case .pick:
            var out: [[Int]] = [], cur: [Int] = []
            for i in 0..<n { cur.append(i); if cutsAfter.contains(i) { out.append(cur); cur = [] } }
            if !cur.isEmpty { out.append(cur) }
            return out
        case .ranges:
            return ToolEngine.parseRanges(custom, pageCount: n)
        }
    }

    private func groupIndex(of page: Int) -> Int? { groups.firstIndex { $0.contains(page) } }

    private func toggleCut(after i: Int) {
        guard i < thumbs.count - 1 else { return }
        if cutsAfter.contains(i) { cutsAfter.remove(i) } else { cutsAfter.insert(i) }
    }

    private func save() {
        let g = groups
        env.run("Splitting PDF") { u, ctx in try ToolEngine.splitPDF(u[0], groups: g, ctx: ctx) }
    }
}

// MARK: - Organize

struct OrganizePanel: View {
    let env: ToolEnv
    @StateObject private var thumbs = PDFThumbs()
    @State private var pages: [Item] = []
    @State private var selection: Set<UUID> = []

    struct Item: Identifiable, Equatable { let id = UUID(); let index: Int; var rotation = 0 }

    var body: some View {
        ToolScaffold(env: env, primary: "Save Organized Copy", primaryEnabled: !pages.isEmpty && changed, onPrimary: save) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 14)], spacing: 16) {
                    ForEach(pages) { p in
                        PageTile(image: p.index < thumbs.pages.count ? thumbs.pages[p.index] : nil,
                                 label: "\((pages.firstIndex(of: p) ?? 0) + 1)  ·  p.\(p.index + 1)", rotation: p.rotation,
                                 selected: selection.contains(p.id))
                            .onTapGesture { toggle(p.id) }
                            .draggable(p.id.uuidString)
                            .dropDestination(for: String.self) { items, _ in move(items.first, before: p.id); return true }
                    }
                }
                .padding(18)
                .animation(.snappy, value: pages)
            }
        } controls: {
            SectionLabel("Pages")
            Text("\(pages.count) pages · \(selection.count) selected").font(.system(size: 12).monospacedDigit())
            Text("Click to select. Drag pages to reorder.").font(.system(size: 11)).foregroundStyle(.secondary)
            SectionLabel("Selected")
            HStack(spacing: 6) {
                tool("rotate.left", "Rotate left") { rotate(-90) }
                tool("rotate.right", "Rotate right") { rotate(90) }
                tool("plus.square.on.square", "Duplicate") { duplicate() }
                tool("trash", "Delete") { pages.removeAll { selection.contains($0.id) }; selection.removeAll() }
            }
            SectionLabel("All pages")
            HStack(spacing: 6) {
                Button("Reverse") { pages.reverse() }
                Button("Select All") { selection = Set(pages.map(\.id)) }
                Button("Reset") { reset() }
            }
            .controlSize(.small)
        }
        .onAppear { if let u = env.urls.first { thumbs.load(u) } }
        .onChange(of: thumbs.count) { _, _ in reset() }
        .onReceive(NotificationCenter.default.publisher(for: .yuzuPanelSet)) { n in
            let info = (n.userInfo as? [String: String]) ?? [:]
            // e.g. select=2,5 rotate=90 then move=8:1 (page 8 to the front)
            if let s = info["select"] { selection = Set(s.split(separator: ",").compactMap { Int($0) }.compactMap { k in pages.first { $0.index == k - 1 }?.id }) }
            if let r = info["rotate"].flatMap(Int.init) { rotate(r) }
            if let m = info["move"] {
                let p = m.split(separator: ":").compactMap { Int($0) }
                if p.count == 2, let from = pages.firstIndex(where: { $0.index == p[0] - 1 }) {
                    let item = pages.remove(at: from); pages.insert(item, at: max(0, min(p[1] - 1, pages.count)))
                }
            }
        }
    }

    private var changed: Bool { pages.map(\.index) != Array(0..<thumbs.count) || pages.contains { $0.rotation != 0 } }

    private func tool(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 30, height: 22) }
            .disabled(selection.isEmpty).help(help)
    }

    private func reset() { pages = (0..<thumbs.count).map { Item(index: $0) }; selection.removeAll() }
    private func toggle(_ id: UUID) { if selection.contains(id) { selection.remove(id) } else { selection.insert(id) } }
    private func rotate(_ d: Int) { for i in pages.indices where selection.contains(pages[i].id) { pages[i].rotation = (pages[i].rotation + d + 360) % 360 } }

    private func duplicate() {
        var out: [Item] = []
        for p in pages { out.append(p); if selection.contains(p.id) { out.append(Item(index: p.index, rotation: p.rotation)) } }
        pages = out
    }

    private func move(_ idString: String?, before target: UUID) {
        guard let s = idString, let id = UUID(uuidString: s), id != target,
              let from = pages.firstIndex(where: { $0.id == id }) else { return }
        let item = pages.remove(at: from)
        let to = pages.firstIndex(where: { $0.id == target }) ?? pages.count
        pages.insert(item, at: to)
    }

    private func save() {
        let list = pages.map { (index: $0.index, rotation: $0.rotation) }
        env.run("Organizing PDF") { u, ctx in try ToolEngine.organizePDF(u[0], pages: list, ctx: ctx) }
    }
}
