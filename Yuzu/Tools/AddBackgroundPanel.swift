import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Replace or add a background: Vision subject lifting, solid colors, gradients, blur or a custom image,
/// with padding, corners, shadow and a fixed ratio.
struct AddBackgroundPanel: View {
    let env: ToolEnv
    @StateObject private var preview = PreviewLoader()
    @State private var style = BGStyle()
    @State private var subject: CGImage?
    @State private var subjectState: SubjectState = .finding
    @State private var rendered: CGImage?
    @State private var custom: CGImage?
    @State private var generation = 0
    @State private var ratioKey = "Auto"

    enum SubjectState { case finding, found, none }

    static let solids: [RGBA] = [
        RGBA(r: 1, g: 1, b: 1), RGBA(r: 0.96, g: 0.94, b: 0.89), RGBA(r: 0.11, g: 0.11, b: 0.12),
        RGBA(r: 0.99, g: 0.73, b: 0.20), RGBA(r: 0.30, g: 0.62, b: 0.47), RGBA(r: 0.33, g: 0.55, b: 0.95),
    ]
    static let gradients: [(RGBA, RGBA)] = [
        (RGBA(r: 1.0, g: 0.82, b: 0.30), RGBA(r: 0.98, g: 0.45, b: 0.18)),
        (RGBA(r: 0.55, g: 0.85, b: 0.62), RGBA(r: 0.10, g: 0.42, b: 0.33)),
        (RGBA(r: 0.62, g: 0.78, b: 1.00), RGBA(r: 0.36, g: 0.32, b: 0.88)),
        (RGBA(r: 1.00, g: 0.70, b: 0.78), RGBA(r: 0.67, g: 0.36, b: 0.92)),
        (RGBA(r: 0.98, g: 0.93, b: 0.80), RGBA(r: 0.85, g: 0.73, b: 0.55)),
        (RGBA(r: 0.24, g: 0.25, b: 0.30), RGBA(r: 0.05, g: 0.05, b: 0.07)),
    ]
    static let ratios: [(String, Double?)] = [("Auto", nil), ("1:1", 1), ("4:5", 0.8), ("16:9", 16.0 / 9), ("9:16", 9.0 / 16)]

    var body: some View {
        ToolScaffold(env: env, subtitle: subtitle, primary: "Save with Background",
                     primaryEnabled: preview.cgImage != nil, onPrimary: save) {
            ImageStage(image: rendered ?? preview.cgImage, padding: 26) { _ in EmptyView() }
                .overlay(alignment: .topLeading) {
                    if subjectState == .finding && style.liftSubject {
                        Label("Finding the subject…", systemImage: "sparkles")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(.ultraThinMaterial)).padding(12)
                    }
                }
        } controls: {
            Toggle(isOn: $style.liftSubject) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Remove background").font(.system(size: 12, weight: .medium))
                    Text(subjectNote).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch).controlSize(.small).tint(Theme.accentDeep)

            SectionLabel("Background")
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 8), count: 6), alignment: .leading, spacing: 8) {
                swatch(.none) { Checker().clipShape(RoundedRectangle(cornerRadius: 8)) }
                swatch(.blur) {
                    ZStack {
                        if let p = preview.cgImage { Image(decorative: p, scale: 1).resizable().scaledToFill().blur(radius: 4) }
                        Image(systemName: "drop.halffull").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).shadow(radius: 2)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                ForEach(Self.solids, id: \.self) { c in swatch(.solid(c)) { RoundedRectangle(cornerRadius: 8).fill(c.color) } }
                ForEach(0..<Self.gradients.count, id: \.self) { i in
                    let g = Self.gradients[i]
                    swatch(.gradient(g.0, g.1)) {
                        RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [g.0.color, g.1.color], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
                Button(action: chooseImage) {
                    ZStack {
                        if let custom { Image(decorative: custom, scale: 1).resizable().scaledToFill() }
                        else { Color.primary.opacity(0.07); Image(systemName: "photo.badge.plus").font(.system(size: 13)) }
                    }
                    .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isCustom ? Theme.accentDeep : Color.primary.opacity(0.15), lineWidth: isCustom ? 2 : 0.5))
                }
                .buttonStyle(.plain).help("Use your own image")
            }

            SectionLabel("Layout")
            SliderRow(label: "Padding", value: $style.padding, range: 0...0.4, neutral: 0.08, display: px)
            SliderRow(label: "Corners", value: $style.corners, range: 0...0.12, neutral: 0.03, display: px)
                .disabled(style.liftSubject && subject != nil)
            SliderRow(label: "Shadow", value: $style.shadow, range: 0...0.12, neutral: 0.04, display: px)
            SectionLabel("Ratio")
            ChipPicker(options: Self.ratios.map { ($0.0, $0.0) }, selection: $ratioKey)
        }
        .onAppear { if let u = env.urls.first { preview.load(u, maxPixel: 1200) } }
        .onChange(of: preview.cgImage) { _, img in findSubject(img) }
        .onChange(of: style) { _, _ in render() }
        .onChange(of: ratioKey) { _, k in style.ratio = Self.ratios.first { $0.0 == k }?.1 ?? nil }
        .onReceive(NotificationCenter.default.publisher(for: .yuzuPanelSet)) { note in
            // Test hook: set the background from yuzuctl for screenshots.
            let info = (note.userInfo as? [String: String]) ?? [:]
            switch info["fill"] {
            case "none": style.fill = .none; style.padding = 0; style.shadow = 0
            case "blur": style.fill = .blur
            case let g? where g.hasPrefix("gradient"):
                let i = Int(g.dropFirst(8)) ?? 0; let c = Self.gradients[min(i, Self.gradients.count - 1)]; style.fill = .gradient(c.0, c.1)
            case let c? where c.hasPrefix("solid"):
                style.fill = .solid(Self.solids[min(Int(c.dropFirst(5)) ?? 0, Self.solids.count - 1)])
            default: break
            }
            if let r = info["ratio"] { ratioKey = r }
        }
    }

    private var subtitle: String? { nil }

    /// Layout values are fractions of the long edge; show them as pixels of the real image.
    private func px(_ v: Double) -> String { "\(Int(v * max(preview.pixelSize.width, preview.pixelSize.height))) px" }

    private var subjectNote: String {
        switch subjectState {
        case .finding: return "Finding the subject…"
        case .found: return "Subject found with Apple Vision"
        case .none: return "No clear subject. The whole image is framed."
        }
    }

    private var isCustom: Bool { if case .image = style.fill { return true }; return false }

    private func swatch<V: View>(_ fill: BGFill, @ViewBuilder content: () -> V) -> some View {
        let selected = style.fill == fill
        return Button {
            withAnimation(.snappy) {
                // A plain cut-out should keep the photo's own size unless padding was changed on purpose.
                if fill == .none, style.padding == BGStyle().padding { style.padding = 0 }
                if fill == .none, style.shadow == BGStyle().shadow { style.shadow = 0 }
                style.fill = fill
            }
        } label: {
            content()
                .frame(width: 34, height: 34)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accentDeep, lineWidth: selected ? 2 : 0).padding(-3))
        }
        .buttonStyle(.plain)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a background image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        custom = try? ImageEngine.decode(url, maxPixel: 1600).image
        style.fill = .image(url)
    }

    private func findSubject(_ img: CGImage?) {
        guard let img else { return }
        subjectState = .finding
        render()
        Task.detached(priority: .userInitiated) {
            let s = try? ImageEdit.liftSubject(img)
            await MainActor.run {
                subject = s
                subjectState = s == nil ? .none : .found
                render()
            }
        }
    }

    private func render() {
        guard let img = preview.cgImage else { return }
        generation += 1
        let gen = generation, st = style, sub = subject, cus = custom
        Task.detached(priority: .userInitiated) {
            let out = ImageEdit.renderBackground(image: img, subject: st.liftSubject ? sub : nil, style: st, customImage: cus)
            await MainActor.run { if gen == generation { rendered = out } }
        }
    }

    private func save() {
        let st = style
        env.run("Adding background") { u, ctx in try ImageEdit.addBackground(u[0], style: st, ctx: ctx) }
    }
}

struct Checker: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let s: CGFloat = 6
            for y in stride(from: 0, to: size.height, by: s) {
                for x in stride(from: 0, to: size.width, by: s) where (Int(x / s) + Int(y / s)) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(Color(white: 0.82)))
                }
            }
        }
    }
}

