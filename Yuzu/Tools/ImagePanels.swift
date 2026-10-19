import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Crop

struct CropPanel: View {
    let env: ToolEnv
    @StateObject private var preview = PreviewLoader()
    @State private var rect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var preset: AspectPreset = .free

    var body: some View {
        ToolScaffold(env: env, primary: env.urls.count > 1 ? "Crop \(env.urls.count) Images" : "Save Cropped Copy", onPrimary: save) {
            ImageStage(image: preview.cgImage) { frame in
                CropOverlay(rect: $rect, frame: frame, aspect: normalizedAspect)
            }
        } controls: {
            SectionLabel("Aspect")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 4)], spacing: 4) {
                ForEach(AspectPreset.allCases) { p in
                    Button { preset = p; withAnimation(.snappy) { rect = CropOverlay.fitted(aspect: p.ratio(original: preview.pixelSize), imageSize: preview.pixelSize) } } label: {
                        Text(p.rawValue).font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(preset == p ? Theme.accentDeep : Theme.step200))
                            .foregroundStyle(preset == p ? Theme.onInk : Theme.ink)
                    }.buttonStyle(.plain)
                }
            }
            SectionLabel("Size")
            HStack {
                Label("\(Int(rect.width * preview.pixelSize.width))", systemImage: "arrow.left.and.right")
                Label("\(Int(rect.height * preview.pixelSize.height))", systemImage: "arrow.up.and.down")
            }
            .font(.system(size: 12).monospacedDigit())
            Text("pixels").font(.system(size: 11)).foregroundStyle(.secondary)
            if env.urls.count > 1 {
                Text("The same share of each image is cropped for every image.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Button("Reset") { preset = .free; withAnimation(.snappy) { rect = CGRect(x: 0, y: 0, width: 1, height: 1) } }
        }
        .onAppear { if let u = env.urls.first { preview.load(u) } }
    }

    private var normalizedAspect: CGFloat? {
        guard let r = preset.ratio(original: preview.pixelSize), preview.pixelSize.width > 0 else { return nil }
        return r * preview.pixelSize.height / preview.pixelSize.width
    }

    private func save() {
        let r = rect
        env.run("Cropping") { u, ctx in
            let img = try ImageEdit.full(u[0])
            guard let out = ImageEdit.crop(img, normalized: r) else { throw YuzuError.writeFailed(u[0].lastPathComponent) }
            return try ImageEdit.save(out, for: u[0], suffix: FileTool.crop.suffix, settings: ctx.settings)
        }
    }
}

// MARK: - Edit Photo

struct EditPhotoPanel: View {
    let env: ToolEnv
    @StateObject private var preview = PreviewLoader()
    @State private var adj = PhotoAdjustments()
    @State private var rendered: CGImage?
    @State private var comparing = false

    var body: some View {
        ToolScaffold(env: env, primary: env.urls.count > 1 ? "Apply to \(env.urls.count) Photos" : "Save Edited Copy",
                     primaryEnabled: !adj.isNeutral, onPrimary: save) {
            ZStack(alignment: .bottomTrailing) {
                ImageStage(image: comparing ? preview.cgImage : (rendered ?? preview.cgImage)) { _ in EmptyView() }
                Text(comparing ? "Original" : "Hold to compare")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .padding(12)
                    .onLongPressGesture(minimumDuration: 0, pressing: { comparing = $0 }, perform: {})
            }
        } controls: {
            SectionLabel("Light")
            SliderRow(label: "Exposure", value: $adj.exposure, range: -3...3, format: "%+.2f", unit: " EV")
            SliderRow(label: "Brightness", value: $adj.brightness, range: -100...100)
            SliderRow(label: "Contrast", value: $adj.contrast, range: -100...100)
            SliderRow(label: "Highlights", value: $adj.highlights, range: -100...100)
            SliderRow(label: "Shadows", value: $adj.shadows, range: -100...100)
            SliderRow(label: "Gamma", value: $adj.gamma, range: -100...100)
            SectionLabel("Color")
            SliderRow(label: "Saturation", value: $adj.saturation, range: -100...100)
            SliderRow(label: "Vibrance", value: $adj.vibrance, range: -100...100)
            SliderRow(label: "Temperature", value: $adj.temperature, range: -100...100)
            SliderRow(label: "Tint", value: $adj.tint, range: -100...100)
            SectionLabel("Detail")
            SliderRow(label: "Sharpness", value: $adj.sharpness, range: 0...100)
            Button("Reset All") { withAnimation(.snappy) { adj = PhotoAdjustments() } }.disabled(adj.isNeutral)
        }
        .onAppear { if let u = env.urls.first { preview.load(u, maxPixel: 1400) } }
        .onChange(of: adj) { _, a in render(a) }
        .onChange(of: preview.cgImage) { _, _ in render(adj) }
    }

    private func render(_ a: PhotoAdjustments) {
        guard let src = preview.cgImage else { return }
        rendered = a.isNeutral ? nil : ImageEdit.adjust(src, a)
    }

    private func save() {
        let a = adj
        env.run("Editing") { u, ctx in
            let img = try ImageEdit.full(u[0])
            guard let out = ImageEdit.adjust(img, a) else { throw YuzuError.writeFailed(u[0].lastPathComponent) }
            return try ImageEdit.save(out, for: u[0], suffix: FileTool.editPhoto.suffix, settings: ctx.settings)
        }
    }
}

// MARK: - Annotate

struct AnnotatePanel: View {
    let env: ToolEnv
    @StateObject private var preview = PreviewLoader()
    @State private var shapes: [AnnoShape] = []
    @State private var draft: AnnoShape?
    @State private var kind: AnnoKind = .arrow
    @State private var color = Palette.colors[0]
    @State private var width = 0.008
    @State private var text = "Look here"

    var body: some View {
        ToolScaffold(env: env, primary: "Save Annotated Copy", primaryEnabled: !shapes.isEmpty, onPrimary: save) {
            ImageStage(image: preview.cgImage) { frame in
                Canvas { ctx, _ in
                    ctx.withCGContext { cg in
                        cg.translateBy(x: frame.minX, y: frame.minY)
                        cg.clip(to: CGRect(origin: .zero, size: frame.size))
                        for s in shapes + (draft.map { [$0] } ?? []) { ImageEdit.draw(s, in: cg, size: frame.size) }
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let p = frame.normalize(v.location)
                    if draft == nil {
                        draft = AnnoShape(kind: kind, points: [frame.normalize(v.startLocation)], color: color, width: width, text: text)
                    }
                    if kind == .pen || kind == .highlight { draft?.points.append(p) }
                    else if kind != .text { draft?.points = [draft!.points[0], p] }
                }.onEnded { _ in
                    if let d = draft { shapes.append(d) }
                    draft = nil
                })
            }
        } controls: {
            SectionLabel("Tool")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(AnnoKind.allCases, id: \.self) { k in
                    Button { kind = k } label: {
                        VStack(spacing: 3) {
                            Image(systemName: Self.symbol(k)).font(.system(size: 13))
                            Text(k.rawValue.capitalized).font(.system(size: 10, weight: .medium))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(kind == k ? Theme.accentDeep : Theme.step200))
                        .foregroundStyle(kind == k ? Theme.onInk : Theme.ink)
                    }.buttonStyle(.plain)
                }
            }
            SectionLabel("Color")
            ColorSwatches(selection: $color)
            SectionLabel("Line")
            ChipPicker(options: [(0.004, "Thin"), (0.008, "Medium"), (0.014, "Bold")], selection: $width)
            if kind == .text {
                SectionLabel("Text")
                TextField("Text", text: $text).textFieldStyle(.roundedBorder)
                Text("Click the image to place it.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
                Button { _ = shapes.popLast() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }.disabled(shapes.isEmpty)
                    .keyboardShortcut("z", modifiers: .command)
                Button(role: .destructive) { shapes.removeAll() } label: { Label("Clear", systemImage: "trash") }.disabled(shapes.isEmpty)
            }
        }
        .onAppear { if let u = env.urls.first { preview.load(u) } }
    }

    static func symbol(_ k: AnnoKind) -> String {
        switch k {
        case .arrow: return "arrow.up.right"
        case .pen: return "scribble"
        case .highlight: return "highlighter"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        }
    }

    private func save() {
        let s = shapes
        env.run("Annotating") { u, ctx in
            let img = try ImageEdit.full(u[0])
            guard let out = ImageEdit.annotate(img, shapes: s) else { throw YuzuError.writeFailed(u[0].lastPathComponent) }
            return try ImageEdit.save(out, for: u[0], suffix: FileTool.annotate.suffix, settings: ctx.settings)
        }
    }
}

enum Palette {
    static let colors: [RGBA] = [
        RGBA(r: 0.99, g: 0.56, b: 0.02), RGBA(r: 0.95, g: 0.23, b: 0.23), RGBA(r: 0.20, g: 0.62, b: 0.98),
        RGBA(r: 0.20, g: 0.78, b: 0.45), RGBA(r: 1.00, g: 0.84, b: 0.10), RGBA(r: 1, g: 1, b: 1), RGBA(r: 0.08, g: 0.08, b: 0.09),
    ]
}

struct ColorSwatches: View {
    @Binding var selection: RGBA
    var body: some View {
        HStack(spacing: 7) {
            ForEach(Palette.colors, id: \.self) { c in
                Circle().fill(c.color)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(Theme.accentDeep, lineWidth: selection == c ? 2 : 0).padding(-3))
                    .onTapGesture { selection = c }
            }
        }
        .padding(.leading, 3)
    }
}

// MARK: - Redact

struct RedactPanel: View {
    let env: ToolEnv
    @StateObject private var preview = PreviewLoader()
    @State private var boxes: [CGRect] = []
    @State private var draft: CGRect?
    @State private var mode: RedactMode = .blur
    @State private var rendered: CGImage?

    var body: some View {
        ToolScaffold(env: env, primary: "Save Redacted Copy", primaryEnabled: !boxes.isEmpty, onPrimary: save) {
            ImageStage(image: rendered ?? preview.cgImage) { frame in
                ZStack(alignment: .topLeading) {
                    Color.white.opacity(0.001)
                    ForEach(Array((boxes + (draft.map { [$0] } ?? [])).enumerated()), id: \.offset) { _, b in
                        let r = frame.denormalize(b)
                        Rectangle().strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                            .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                    }
                }
                .gesture(DragGesture(minimumDistance: 2).onChanged { v in
                    draft = CGRect(p1: frame.normalize(v.startLocation), p2: frame.normalize(v.location))
                }.onEnded { _ in
                    if let d = draft, d.width > 0.005, d.height > 0.005 { boxes.append(d) }
                    draft = nil
                })
            }
        } controls: {
            SectionLabel("Style")
            ChipPicker(options: [(RedactMode.blur, "Blur"), (.pixelate, "Pixelate"), (.solid, "Solid")], selection: $mode)
            Text(mode == .solid ? "Solid fully covers sensitive information." : "Blur softens details. Use Solid for sensitive information.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            SectionLabel("Areas")
            Text(boxes.isEmpty ? "Drag over the image to add an area." : "\(boxes.count) area\(boxes.count == 1 ? "" : "s")")
                .font(.system(size: 12))
            HStack {
                Button { _ = boxes.popLast() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }.disabled(boxes.isEmpty)
                    .keyboardShortcut("z", modifiers: .command)
                Button(role: .destructive) { boxes.removeAll() } label: { Label("Clear", systemImage: "trash") }.disabled(boxes.isEmpty)
            }
        }
        .onAppear { if let u = env.urls.first { preview.load(u) } }
        .onChange(of: boxes) { _, _ in render() }
        .onChange(of: mode) { _, _ in render() }
    }

    private func render() {
        guard let p = preview.cgImage else { return }
        rendered = boxes.isEmpty ? nil : ImageEdit.redact(p, boxes: boxes, mode: mode)
    }

    private func save() {
        let b = boxes, m = mode
        env.run("Redacting") { u, ctx in
            let img = try ImageEdit.full(u[0])
            guard let out = ImageEdit.redact(img, boxes: b, mode: m) else { throw YuzuError.writeFailed(u[0].lastPathComponent) }
            return try ImageEdit.save(out, for: u[0], suffix: FileTool.redact.suffix, settings: ctx.settings)
        }
    }
}

// MARK: - Resize

struct ResizePanel: View {
    let env: ToolEnv
    @StateObject private var preview = PreviewLoader()
    @State private var percent = 50.0
    @State private var byPercent = true
    @State private var width = ""
    @State private var height = ""
    @State private var lock = true

    var body: some View {
        ToolScaffold(env: env, primary: env.urls.count > 1 ? "Resize \(env.urls.count) Images" : "Save Resized Copy", onPrimary: save) {
            ImageStage(image: preview.cgImage) { frame in
                Text(outputLabel)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .position(x: frame.midX, y: frame.maxY - 18)
            }
        } controls: {
            SectionLabel("Mode")
            ChipPicker(options: [(true, "Percent"), (false, "Pixels")], selection: $byPercent)
            if byPercent {
                SliderRow(label: "Scale", value: $percent, range: 5...200, neutral: 100, format: "%.0f", unit: "%")
                ChipPicker(options: [(25.0, "25%"), (50.0, "50%"), (75.0, "75%"), (200.0, "200%")], selection: $percent)
            } else {
                HStack {
                    TextField("Width", text: $width).textFieldStyle(.roundedBorder)
                        .onChange(of: width) { _, w in syncHeight(w) }
                    Text("×").foregroundStyle(.secondary)
                    TextField("Height", text: $height).textFieldStyle(.roundedBorder)
                        .onChange(of: height) { _, h in syncWidth(h) }
                }
                Toggle("Keep proportions", isOn: $lock).toggleStyle(.checkbox)
            }
            Text("Original \(Int(preview.pixelSize.width)) × \(Int(preview.pixelSize.height)) px")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .onAppear { if let u = env.urls.first { preview.load(u, maxPixel: 1400) } }
        .onChange(of: preview.pixelSize) { _, s in
            width = "\(Int(s.width / 2))"; height = "\(Int(s.height / 2))"
        }
    }

    private var outputLabel: String {
        let s = target(for: preview.pixelSize)
        return "\(s.0) × \(s.1) px"
    }

    private func target(for size: CGSize) -> (Int, Int) {
        if byPercent { return (max(1, Int(size.width * percent / 100)), max(1, Int(size.height * percent / 100))) }
        return (Int(width) ?? Int(size.width), Int(height) ?? Int(size.height))
    }

    private func syncHeight(_ w: String) {
        guard lock, let v = Double(w), preview.pixelSize.width > 0 else { return }
        let h = "\(Int((v * preview.pixelSize.height / preview.pixelSize.width).rounded()))"
        if h != height { height = h }
    }
    private func syncWidth(_ h: String) {
        guard lock, let v = Double(h), preview.pixelSize.height > 0 else { return }
        let w = "\(Int((v * preview.pixelSize.width / preview.pixelSize.height).rounded()))"
        if w != width { width = w }
    }

    private func save() {
        let pct = byPercent ? percent : nil
        let fixed = target(for: preview.pixelSize)
        env.run("Resizing") { u, ctx in
            let img = try ImageEdit.full(u[0])
            let size = pct.map { (max(1, Int(Double(img.width) * $0 / 100)), max(1, Int(Double(img.height) * $0 / 100))) } ?? fixed
            guard let out = ImageEdit.resize(img, width: size.0, height: size.1) else { throw YuzuError.writeFailed(u[0].lastPathComponent) }
            return try ImageEdit.save(out, for: u[0], suffix: FileTool.resize.suffix, settings: ctx.settings)
        }
    }
}
