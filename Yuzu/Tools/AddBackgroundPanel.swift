import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Replace or add a background. Photo mode lifts the subject with Vision; Screenshot mode frames a capture
/// on a curated backdrop with window corners, a layered shadow and an optional inset border.
struct AddBackgroundPanel: View {
    let env: ToolEnv
    @StateObject private var preview = PreviewLoader()
    @State private var mode: Mode = .photo
    @State private var style = BGStyle()
    @State private var frameImage: CGImage?          // preview, trimmed of macOS's capture shadow in screenshot mode
    @State private var captureCorner: Double?
    @State private var pixelScale = 1.0
    @State private var subject: CGImage?
    @State private var subjectState: SubjectState = .finding
    @State private var rendered: CGImage?
    @State private var custom: CGImage?
    @State private var thumbs: [Backdrop: CGImage] = [:]
    @State private var generation = 0
    @State private var lastRenderMS: Double = 0
    @State private var ready = false

    enum Mode: String { case photo = "Photo", screenshot = "Screenshot" }
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
    struct RatioPreset { let key: String; let value: Double?; let caption: String }
    static let ratios: [RatioPreset] = [
        RatioPreset(key: "Auto", value: nil, caption: "Fit"), RatioPreset(key: "16:9", value: 16.0 / 9, caption: "Twitter / X"),
        RatioPreset(key: "4:3", value: 4.0 / 3, caption: "Dribbble"), RatioPreset(key: "1:1", value: 1, caption: "Square"),
        RatioPreset(key: "4:5", value: 0.8, caption: "Portrait"), RatioPreset(key: "9:16", value: 9.0 / 16, caption: "Story"),
    ]

    var body: some View {
        ToolScaffold(env: env, subtitle: subtitle, primary: mode == .screenshot ? "Save PNG" : "Save with Background",
                     primaryEnabled: frameImage != nil, onPrimary: save) {
            ImageStage(image: rendered ?? frameImage, padding: 26) { _ in EmptyView() }
                .overlay(alignment: .topLeading) {
                    if mode == .photo && subjectState == .finding && style.liftSubject {
                        Label("Finding the subject…", systemImage: "sparkles")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(.ultraThinMaterial)).padding(12)
                    }
                }
        } controls: {
            ChipPicker(options: [(Mode.photo, "Photo"), (Mode.screenshot, "Screenshot")], selection: Binding(get: { mode }, set: { switchMode($0) }))

            if mode == .screenshot { ratioSection }   // sharing sizes first: the usual first choice for screenshots

            if mode == .photo {
                Toggle(isOn: $style.liftSubject) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Remove background").font(.system(size: 12, weight: .medium))
                        Text(subjectNote).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(AccentSwitchStyle())
            }

            SectionLabel("Backdrops")
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
                    ForEach(Backdrop.allCases) { b in backdropTile(b) }
                }
                .padding(4)
            }
            .frame(height: 150)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))

            if isBackdrop { SliderRow(label: "Grain", value: $style.grain, range: 0...1, neutral: 0.5, display: { "\(Int($0 * 100))%" }) }

            SectionLabel("Colours and images")
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(25), spacing: 5), count: 8), alignment: .leading, spacing: 6) {
                swatch(.none) { Checker().clipShape(RoundedRectangle(cornerRadius: 6)) }
                swatch(.blur) {
                    ZStack {
                        if let p = preview.cgImage { Image(decorative: p, scale: 1).resizable().scaledToFill().blur(radius: 4) }
                        Image(systemName: "drop.halffull").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).shadow(radius: 2)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                ForEach(Self.solids, id: \.self) { c in swatch(.solid(c)) { RoundedRectangle(cornerRadius: 6).fill(c.color) } }
                ForEach(0..<Self.gradients.count, id: \.self) { i in
                    let g = Self.gradients[i]
                    swatch(.gradient(g.0, g.1)) {
                        RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [g.0.color, g.1.color], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
                Button(action: chooseImage) {
                    ZStack {
                        if let custom { Image(decorative: custom, scale: 1).resizable().scaledToFill() }
                        else { Color.primary.opacity(0.07); Image(systemName: "photo.badge.plus").font(.system(size: 12)) }
                    }
                    .frame(width: 25, height: 25).clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.accentDeep, lineWidth: isCustom ? 2 : 0).padding(-3))
                }
                .buttonStyle(.plain).help("Use your own image")
            }

            SectionLabel("Layout")
            SliderRow(label: "Padding", value: $style.padding, range: 0...0.3, neutral: mode == .screenshot ? 0.08 : BGStyle().padding, display: px)
            SliderRow(label: "Corners", value: $style.corners, range: 0...(mode == .screenshot ? 0.05 : 0.12), neutral: defaultCorners,
                      display: mode == .screenshot ? pt : px)
                .disabled(mode == .photo && style.liftSubject && subject != nil)
            SliderRow(label: "Shadow", value: $style.shadow, range: 0...0.12, neutral: mode == .screenshot ? 0.05 : BGStyle().shadow,
                      display: { $0 == 0 ? "Off" : "\(Int(($0 / 0.12 * 100).rounded()))%" })
            if mode == .screenshot {
                Toggle(isOn: $style.border) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Inset border").font(.system(size: 12, weight: .medium))
                        Text("A hairline edge, like a real window").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(AccentSwitchStyle())
            }

            if mode == .photo { ratioSection }
            if let out = rendered {
                Text("\(outputSize(out)) · preview \(String(format: "%.0f", lastRenderMS)) ms")
                    .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: start)
        .onChange(of: preview.cgImage) { _, img in prepare(img) }
        .onChange(of: style) { _, s in render(); if ready { BGMemory.save(s, for: mode) } }
        .onReceive(NotificationCenter.default.publisher(for: .yuzuPanelSet)) { note in applyTestSetting((note.userInfo as? [String: String]) ?? [:]) }
    }

    // MARK: Pieces

    @ViewBuilder private var ratioSection: some View {
        SectionLabel("Ratio")
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
            ForEach(Self.ratios, id: \.key) { r in ratioChip(r) }
        }
    }

    private func backdropTile(_ b: Backdrop) -> some View {
        let selected = style.fill == .backdrop(b)
        return Button { withAnimation(.snappy) { style.fill = .backdrop(b) } } label: {
            VStack(spacing: 4) {
                ZStack {
                    if let t = thumbs[b] { Image(decorative: t, scale: 2).resizable().scaledToFill() } else { Color.primary.opacity(0.06) }
                    if b == .match { Image(systemName: "eyedropper.halffull").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).shadow(radius: 2) }
                }
                .frame(height: 44).frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.accentDeep, lineWidth: selected ? 2 : 0).padding(-3))
                Text(b.name).font(.system(size: 10, weight: selected ? .semibold : .regular)).lineLimit(1)
                    .foregroundStyle(selected ? Theme.accentDeep : .secondary)
            }
        }
        .buttonStyle(.plain)
        .help(b.name)
    }

    private func ratioChip(_ r: RatioPreset) -> some View {
        let selected = style.ratio == r.value
        return Button { withAnimation(.snappy) { style.ratio = r.value } } label: {
            VStack(spacing: 0) {
                Text(r.key).font(.system(size: 11, weight: .semibold))
                Text(r.caption).font(.system(size: 9)).opacity(0.75)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? Theme.accentDeep : Color.primary.opacity(0.07)))
            .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func swatch<V: View>(_ fill: BGFill, @ViewBuilder content: () -> V) -> some View {
        let selected = style.fill == fill
        return Button {
            withAnimation(.snappy) {
                // A plain cut-out should keep the photo's own size unless padding was changed on purpose.
                if fill == .none, mode == .photo, style.padding == BGStyle().padding { style.padding = 0 }
                if fill == .none, mode == .photo, style.shadow == BGStyle().shadow { style.shadow = 0 }
                style.fill = fill
            }
        } label: {
            content()
                .frame(width: 25, height: 25)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.accentDeep, lineWidth: selected ? 2 : 0).padding(-3))
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String? {
        guard let u = env.urls.first else { return nil }
        let size = SizeText.format(SizeText.of([u]))
        return mode == .screenshot ? "\(u.lastPathComponent) · \(size) · screenshot @\(Int(pixelScale))x" : nil
    }

    private var isBackdrop: Bool { if case .backdrop = style.fill { return true }; return false }
    private var isCustom: Bool { if case .image = style.fill { return true }; return false }

    private var fullWidth: Double {
        // Width of the image that will be framed at full size (after trimming the capture shadow).
        guard let f = frameImage, let p = preview.cgImage, p.width > 0 else { return preview.pixelSize.width }
        return preview.pixelSize.width * Double(f.width) / Double(p.width)
    }

    private var defaultCorners: Double {
        mode == .screenshot ? (captureCorner ?? ImageEdit.windowCornerPoints * pixelScale / max(fullWidth, 1)) : BGStyle().corners
    }

    /// Layout values are fractions of the base edge; show them as real pixels (or points for screenshots).
    private func px(_ v: Double) -> String {
        let base = mode == .screenshot ? fullWidth : max(preview.pixelSize.width, preview.pixelSize.height)
        return "\(Int(v * base)) px"
    }
    private func pt(_ v: Double) -> String { "\(Int((v * fullWidth / pixelScale).rounded())) pt" }

    private func outputSize(_ out: CGImage) -> String {
        guard let f = frameImage, f.width > 0 else { return "" }
        let k = fullWidth / Double(f.width)
        return "\(Int((Double(out.width) * k).rounded())) × \(Int((Double(out.height) * k).rounded())) px"
    }

    private var subjectNote: String {
        switch subjectState {
        case .finding: return "Finding the subject…"
        case .found: return "Subject found with Apple Vision"
        case .none: return "No clear subject. The whole image is framed."
        }
    }

    // MARK: Flow

    private func start() {
        guard let u = env.urls.first else { return }
        let shot = ImageEdit.isScreenshot(u)
        pixelScale = ImageEdit.pixelScale(u)
        mode = shot ? .screenshot : .photo
        preview.load(u, maxPixel: shot ? 1320 : 1200)
    }

    private func prepare(_ img: CGImage?) {
        guard let img else { return }
        if mode == .screenshot || ImageEdit.isScreenshot(env.urls.first ?? URL(fileURLWithPath: "/")) {
            let t = ImageEdit.trimCaptureShadow(img)
            frameImage = t.image; captureCorner = t.corner
        } else {
            frameImage = img
        }
        style = BGMemory.load(for: mode) ?? defaultStyle(for: mode)
        if mode == .screenshot, let c = captureCorner { style.corners = c }   // match a captured window's own corners
        ready = true
        makeThumbs()
        if mode == .photo { findSubject(img) }
        render()
    }

    private func defaultStyle(for m: Mode) -> BGStyle {
        m == .screenshot ? BGStyle.forScreenshot(pixelScale: pixelScale, width: fullWidth, captureCorner: captureCorner) : BGStyle()
    }

    private func switchMode(_ m: Mode) {
        guard m != mode, let img = preview.cgImage else { return }
        mode = m
        ready = false
        if m == .screenshot { let t = ImageEdit.trimCaptureShadow(img); frameImage = t.image; captureCorner = t.corner } else { frameImage = img }
        style = BGMemory.load(for: m) ?? defaultStyle(for: m)
        if m == .screenshot { style.liftSubject = false; if let c = captureCorner { style.corners = c } }
        ready = true
        if m == .photo && subject == nil { findSubject(img) }
    }

    private func makeThumbs() {
        guard let img = frameImage else { return }
        Task.detached(priority: .userInitiated) {
            let colours = Backdrop.dominantColours(img)
            var out: [Backdrop: CGImage] = [:]
            for b in Backdrop.allCases {
                guard let ctx = ImageEdit.context(176, 88) else { continue }
                b.draw(in: ctx, rect: CGRect(x: 0, y: 0, width: 176, height: 88), grain: 0.5, matching: b == .match ? colours : [])
                out[b] = ctx.makeImage()
            }
            let done = out
            await MainActor.run { thumbs = done }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a background image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        custom = try? ImageEngine.decode(url, maxPixel: 1600).image
        style.fill = .image(url)
    }

    private func findSubject(_ img: CGImage) {
        subjectState = .finding
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
        guard let img = frameImage else { return }
        generation += 1
        let gen = generation, st = style, sub = mode == .photo ? subject : nil, cus = custom
        Task.detached(priority: .userInitiated) {
            let t0 = CFAbsoluteTimeGetCurrent()
            let out = ImageEdit.renderBackground(image: img, subject: st.liftSubject ? sub : nil, style: st, customImage: cus)
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            await MainActor.run { if gen == generation { rendered = out; lastRenderMS = ms } }
        }
    }

    private func save() {
        var st = style
        if mode == .screenshot { st.screenshot = true; st.liftSubject = false } else { st.screenshot = false }
        BGMemory.save(st, for: mode)
        let style = st
        env.run("Adding background") { u, ctx in try ImageEdit.addBackground(u[0], style: style, ctx: ctx) }
    }

    /// Test hook: drive the panel from yuzuctl for screenshots.
    private func applyTestSetting(_ info: [String: String]) {
        if let m = info["mode"], let mm = Mode(rawValue: m.capitalized) { switchMode(mm) }
        switch info["fill"] {
        case "none": style.fill = .none; if mode == .photo { style.padding = 0; style.shadow = 0 }
        case "blur": style.fill = .blur
        case let g? where g.hasPrefix("gradient"):
            let i = Int(g.dropFirst(8)) ?? 0; let c = Self.gradients[min(i, Self.gradients.count - 1)]; style.fill = .gradient(c.0, c.1)
        case let c? where c.hasPrefix("solid"):
            style.fill = .solid(Self.solids[min(Int(c.dropFirst(5)) ?? 0, Self.solids.count - 1)])
        default: break
        }
        if let b = info["backdrop"].flatMap(Backdrop.init(rawValue:)) { style.fill = .backdrop(b) }
        if let r = info["ratio"] { style.ratio = Self.ratios.first { $0.key == r }?.value }
        if let v = info["border"] { style.border = v == "1" }
    }
}

/// Remembers the last background and layout per mode.
enum BGMemory {
    private static func key(_ m: AddBackgroundPanel.Mode) -> String { "addBackground.last.\(m.rawValue)" }
    static func load(for m: AddBackgroundPanel.Mode) -> BGStyle? {
        guard let d = UserDefaults.standard.data(forKey: key(m)) else { return nil }
        return try? JSONDecoder().decode(BGStyle.self, from: d)
    }
    static func save(_ s: BGStyle, for m: AddBackgroundPanel.Mode) {
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: key(m)) }
    }
}

/// A switch drawn in Yuzu's accent colour (the system switch ignores tint on macOS).
struct AccentSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Spacer(minLength: 8)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? Theme.accentDeep : Color.primary.opacity(0.16))
                    .overlay(Capsule().strokeBorder(Color.black.opacity(configuration.isOn ? 0 : 0.08), lineWidth: 0.5))
                Circle().fill(.white).shadow(color: .black.opacity(0.25), radius: 1, y: 0.5).padding(2)
            }
            .frame(width: 34, height: 20)
            .animation(.snappy(duration: 0.18), value: configuration.isOn)
            .accessibilityElement()
            .accessibilityLabel("Switch")
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(configuration.isOn ? "On" : "Off")
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
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
