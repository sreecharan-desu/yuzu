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

    /// Neutral solids only; colour comes from the image or the Match backdrop.
    static let solids: [RGBA] = [
        RGBA(r: 1.000, g: 1.000, b: 1.000), RGBA(r: 0.961, g: 0.961, b: 0.969), RGBA(r: 0.937, g: 0.922, b: 0.894),
        RGBA(r: 0.824, g: 0.824, b: 0.843), RGBA(r: 0.173, g: 0.173, b: 0.180), RGBA(r: 0.114, g: 0.114, b: 0.122),
    ]
    /// Gentle two-stop washes, each within a few lightness steps (no saturated pairs).
    static let gradients: [(RGBA, RGBA)] = [
        (RGBA(r: 1.000, g: 1.000, b: 1.000), RGBA(r: 0.910, g: 0.910, b: 0.925)),
        (RGBA(r: 0.969, g: 0.957, b: 0.937), RGBA(r: 0.886, g: 0.863, b: 0.824)),
        (RGBA(r: 0.949, g: 0.957, b: 0.969), RGBA(r: 0.851, g: 0.875, b: 0.906)),
        (RGBA(r: 0.227, g: 0.227, b: 0.239), RGBA(r: 0.078, g: 0.078, b: 0.082)),
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
            ImageStage(image: rendered ?? frameImage, padding: Theme.Space.l) { _ in EmptyView() }
                .overlay(alignment: .topLeading) {
                    if mode == .photo && subjectState == .finding && style.liftSubject {
                        Text("Finding the subject…")
                            .type(.caption).foregroundStyle(Theme.inkSoft)
                            .padding(.horizontal, Theme.Space.m - 4).frame(height: 24)
                            .glassEffect(.regular, in: Capsule())
                            .padding(Theme.Space.m)
                            .materialize(0, rise: 6, blur: 6)
                    }
                }
        } controls: {
            ChipPicker(options: [(Mode.photo, "Photo"), (Mode.screenshot, "Screenshot")], selection: Binding(get: { mode }, set: { switchMode($0) }))

            if mode == .screenshot { ratioSection }   // sharing sizes first: the usual first choice for screenshots

            if mode == .photo {
                Toggle(isOn: $style.liftSubject) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remove background").type(.callout).fontWeight(.medium).foregroundStyle(Theme.ink)
                        Text(subjectNote).type(.caption).foregroundStyle(Theme.inkSoft)
                    }
                }
                .toggleStyle(AccentSwitchStyle())
            }

            SectionLabel("Backdrops")
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: 4), spacing: Theme.Space.s) {
                    ForEach(Backdrop.allCases) { b in backdropTile(b) }
                }
                .padding(Theme.Space.half)
            }
            .frame(height: 128)

            if isBackdrop { SliderRow(label: "Grain", value: $style.grain, range: 0...1, neutral: 0.5, display: { "\(Int($0 * 100))%" }) }

            SectionLabel("Colours and images")
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: Theme.Space.s), count: 7), alignment: .leading, spacing: Theme.Space.s) {
                swatch(.none) { Checker().clipShape(Circle()) }
                swatch(.blur) {
                    ZStack {
                        if let p = preview.cgImage { Image(decorative: p, scale: 1).resizable().scaledToFill().blur(radius: 4) }
                    }
                    .clipShape(Circle())
                }
                ForEach(Self.solids, id: \.self) { c in swatch(.solid(c)) { Circle().fill(c.color) } }
                ForEach(0..<Self.gradients.count, id: \.self) { i in
                    let g = Self.gradients[i]
                    swatch(.gradient(g.0, g.1)) {
                        Circle().fill(LinearGradient(colors: [g.0.color, g.1.color], startPoint: .top, endPoint: .bottom))
                    }
                }
                Button(action: chooseImage) {
                    ZStack {
                        if let custom { Image(decorative: custom, scale: 1).resizable().scaledToFill() }
                        else { Theme.step200; Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft) }
                    }
                    .frame(width: 24, height: 24).clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: isCustom ? 1.5 : 0).padding(-3))
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Inset border").type(.callout).fontWeight(.medium).foregroundStyle(Theme.ink)
                        Text("A hairline edge, like a real window").type(.caption).foregroundStyle(Theme.inkSoft)
                    }
                }
                .toggleStyle(AccentSwitchStyle())
            }

            if mode == .photo { ratioSection }
            if let out = rendered {
                Text("\(outputSize(out)) · preview \(String(format: "%.0f", lastRenderMS)) ms")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.inkMute)
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: 3), spacing: Theme.Space.s) {
            ForEach(Self.ratios, id: \.key) { r in ratioChip(r) }
        }
    }

    private func backdropTile(_ b: Backdrop) -> some View {
        let selected = style.fill == .backdrop(b)
        return Button { withAnimation(Theme.Motion.house(0.3)) { style.fill = .backdrop(b) } } label: {
            VStack(spacing: Theme.Space.half + 2) {
                Color.clear
                    .frame(minWidth: 0, maxWidth: .infinity).frame(height: 40)
                    .overlay {
                        if let t = thumbs[b] { Image(decorative: t, scale: 2).resizable().scaledToFill() } else { Theme.step200 }
                    }
                    .overlay {
                        if b == .match { Image(systemName: "eyedropper").font(.system(size: 11, weight: .regular)).foregroundStyle(Theme.inkSoft) }
                    }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control + 3, style: .continuous).strokeBorder(Theme.ink, lineWidth: selected ? 1.5 : 0).padding(-3))
                Text(b.name).font(.system(size: 10, weight: selected ? .medium : .regular)).lineLimit(1)
                    .foregroundStyle(selected ? Theme.ink : Theme.inkSoft)
            }
        }
        .buttonStyle(.plain)
        .help(b.name)
    }

    private func ratioChip(_ r: RatioPreset) -> some View {
        let selected = style.ratio == r.value
        return Button { withAnimation(Theme.Motion.house(0.3)) { style.ratio = r.value } } label: {
            VStack(spacing: 0) {
                Text(r.key).font(.system(size: 11, weight: .medium)).tracking(-0.05)
                Text(r.caption).font(.system(size: 9)).opacity(0.7)
            }
            .frame(maxWidth: .infinity).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(selected ? Theme.ink : Theme.step200))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(selected ? Color.clear : Theme.line, lineWidth: 1))
            .foregroundStyle(selected ? Theme.onInk : Theme.ink)
        }
        .buttonStyle(.plain)
    }

    private func swatch<V: View>(_ fill: BGFill, @ViewBuilder content: () -> V) -> some View {
        let selected = style.fill == fill
        return Button {
            withAnimation(Theme.Motion.house(0.3)) {
                // A plain cut-out should keep the photo's own size unless padding was changed on purpose.
                if fill == .none, mode == .photo, style.padding == BGStyle().padding { style.padding = 0 }
                if fill == .none, mode == .photo, style.shadow == BGStyle().shadow { style.shadow = 0 }
                style.fill = fill
            }
        } label: {
            content()
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: selected ? 1.5 : 0).padding(-3))
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
        if let b = info["backdrop"].flatMap(Backdrop.named) { style.fill = .backdrop(b) }
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

/// A quiet ink switch (the system switch ignores tint on macOS).
struct AccentSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Space.s) {
            configuration.label
            Spacer(minLength: Theme.Space.s)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? Theme.ink : Theme.step300)
                    .overlay(Capsule().strokeBorder(Theme.line, lineWidth: configuration.isOn ? 0 : 1))
                Circle().fill(configuration.isOn ? Theme.onInk : Color.white).shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5).padding(2)
            }
            .frame(width: 32, height: 20)
            .animation(Theme.Motion.house(0.3), value: configuration.isOn)
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
