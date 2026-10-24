import SwiftUI
import AVFoundation
import PDFKit
import AVKit

// MARK: - Time helpers

/// "1:04.2" for a number of seconds.
func clock(_ s: Double) -> String {
    let t = max(0, s)
    let m = Int(t) / 60, sec = t - Double(m * 60)
    return String(format: "%d:%04.1f", m, sec)
}

/// A filmstrip of frames sampled off the main thread.
@MainActor
final class Filmstrip: ObservableObject {
    @Published var frames: [CGImage] = []
    @Published var duration: Double = 0
    @Published var size: CGSize = .zero
    @Published var failed = false
    @Published var wave: [Float] = []

    func load(_ url: URL, count: Int = 12) {
        Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let dur = (try? await asset.load(.duration).seconds) ?? MediaEngine.probeDuration(url)
            let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            var sz = CGSize(width: 1280, height: 720)
            if let t = tracks.first, let n = try? await t.load(.naturalSize), let x = try? await t.load(.preferredTransform) {
                sz = n.applying(x)
                sz = CGSize(width: abs(sz.width), height: abs(sz.height))
            }
            var imgs: [CGImage] = []
            if dur > 0, !tracks.isEmpty {
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = CGSize(width: 240, height: 240)
                let n = max(1, count)
                for i in 0..<n {
                    let at = CMTime(seconds: dur * (Double(i) + 0.5) / Double(n), preferredTimescale: 600)
                    if let cg = try? await gen.image(at: at).image { imgs.append(cg) }
                }
            }
            let w = tracks.isEmpty ? await Self.waveform(asset, bins: 220) : []
            let fsz = sz, fimgs = imgs
            await MainActor.run {
                self.duration = dur; self.size = fsz; self.frames = fimgs; self.wave = w; self.failed = dur <= 0
            }
        }
    }
}

extension Filmstrip {
    /// Peak levels (0...1) of the first audio track, read natively at 8 kHz mono.
    nonisolated static func waveform(_ asset: AVURLAsset, bins: Int) async -> [Float] {
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first, let reader = try? AVAssetReader(asset: asset) else { return [] }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false, AVNumberOfChannelsKey: 1, AVSampleRateKey: 8000])
        reader.add(out)
        guard reader.startReading() else { return [] }
        var samples: [Int16] = []
        while let sb = out.copyNextSampleBuffer(), let bb = CMSampleBufferGetDataBuffer(sb) {
            let len = CMBlockBufferGetDataLength(bb)
            var chunk = [Int16](repeating: 0, count: len / 2)
            chunk.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(bb, atOffset: 0, dataLength: len, destination: $0.baseAddress!) }
            samples += chunk
        }
        guard !samples.isEmpty else { return [] }
        let per = max(1, samples.count / bins)
        var peaks: [Float] = stride(from: 0, to: samples.count, by: per).map { i in
            Float(samples[i..<min(i + per, samples.count)].map { abs(Int($0)) }.max() ?? 0) / 32768
        }
        let top = max(peaks.max() ?? 1, 0.01)
        peaks = peaks.map { $0 / top }
        return peaks
    }
}

/// Horizontal strip of frames with a time ruler. Reports drags as a fraction 0...1.
struct FilmstripView: View {
    let frames: [CGImage]
    var wave: [Float] = []
    var overlay: AnyView? = nil
    var onDrag: ((Double) -> Void)? = nil
    var onEnd: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            Group { if frames.isEmpty && !wave.isEmpty { waveView } else { strip(geo) } }
            .overlay { overlay }
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                onDrag?(min(max(v.location.x / geo.size.width, 0), 1))
            }.onEnded { _ in onEnd?() })
        }
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
    }

    private var waveView: some View {
        Canvas { ctx, size in
            let n = wave.count, bw = size.width / CGFloat(max(n, 1))
            for (i, v) in wave.enumerated() {
                let h = max(1.5, CGFloat(v) * size.height * 0.86)
                ctx.fill(Path(roundedRect: CGRect(x: CGFloat(i) * bw + bw * 0.15, y: (size.height - h) / 2, width: bw * 0.7, height: h), cornerRadius: bw * 0.35),
                         with: .color(Theme.accent))
            }
        }
        .background(Color.primary.opacity(0.06))
    }

    private func strip(_ geo: GeometryProxy) -> some View {
            HStack(spacing: 0) {
                ForEach(0..<max(frames.count, 1), id: \.self) { i in
                    if i < frames.count {
                        Image(decorative: frames[i], scale: 1).resizable().scaledToFill()
                            .frame(width: geo.size.width / CGFloat(max(frames.count, 1)), height: geo.size.height)
                            .clipped()
                    } else { Color.primary.opacity(0.06) }
                }
            }
    }
}

/// Plays a file, optionally only between two times, so the preview matches the edit.
@MainActor
final class ClipPlayer: ObservableObject {
    @Published var playing = false
    let player = AVPlayer()
    private var loop: Any?
    var start: Double = 0, end: Double = 0

    func load(_ url: URL) { player.replaceCurrentItem(with: AVPlayerItem(url: url)) }

    func play(from a: Double, to b: Double) {
        start = a; end = b
        player.seek(to: CMTime(seconds: a, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
        playing = true
        loop.map { player.removeTimeObserver($0) }
        loop = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, self.playing, t.seconds >= self.end else { return }
                self.player.seek(to: CMTime(seconds: self.start, preferredTimescale: 600))
            }
        }
    }

    func toggle(from a: Double, to b: Double) { playing ? stop() : play(from: a, to: b) }
    func stop() { player.pause(); playing = false }
}

/// Shows the video, or for audio-only files a calm card with the file name instead of the system placeholder.
struct MediaSurface: View {
    let player: AVPlayer
    let isAudio: Bool
    let name: String
    var body: some View {
        if isAudio {
            VStack(spacing: 10) {
                Image(systemName: "waveform").font(.system(size: 46, weight: .medium)).foregroundStyle(Theme.accentDeep)
                Text(name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text("Audio").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        } else {
            PlayerView(player: player).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView { let v = AVPlayerView(); v.player = player; v.controlsStyle = .none; return v }
    func updateNSView(_ v: AVPlayerView, context: Context) { v.player = player }
}

extension View {
    /// Test hook: lets yuzuctl set panel state for screenshots.
    func onPanelSet(_ handle: @escaping ([String: String]) -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .yuzuPanelSet)) { handle(($0.userInfo as? [String: String]) ?? [:]) }
    }
}

func numbers(_ s: String?) -> [Double] { (s ?? "").split(separator: ",").compactMap { Double($0) } }

// MARK: - Trim

struct TrimPanel: View {
    let env: ToolEnv
    @StateObject private var strip = Filmstrip()
    @StateObject private var player = ClipPlayer()
    @State private var start = 0.0
    @State private var end = 0.0

    var body: some View {
        ToolScaffold(env: env, primary: "Save Trimmed Copy", primaryEnabled: end - start > 0.05, onPrimary: save) {
            stage
        } controls: {
            SectionLabel("Range")
            SliderRow(label: "Start", value: $start, range: 0...max(end - 0.1, 0.1), neutral: 0, display: { clock($0) })
            SliderRow(label: "End", value: $end, range: min(start + 0.1, strip.duration)...max(strip.duration, 0.2), neutral: strip.duration, display: { clock($0) })
            HStack {
                Label(clock(max(0, end - start)), systemImage: "scissors")
                Spacer()
                Text("of \(clock(strip.duration))").foregroundStyle(.secondary)
            }
            .font(.system(size: 12).monospacedDigit())
            Text("Drag the edges of the highlighted region, or use the sliders.").font(.system(size: 11)).foregroundStyle(.secondary)
            Button(player.playing ? "Stop" : "Play selection") { player.toggle(from: start, to: end) }
        }
        .onAppear { if let u = env.urls.first { strip.load(u); player.load(u) } }
        .whenChange(of: strip.duration) { d in if d > 0, end == 0 { end = d } }
        .onPanelSet { i in if let a = Double(i["start"] ?? "") { start = a }; if let b = Double(i["end"] ?? "") { end = b } }
        .onDisappear { player.stop() }
    }

    private var stage: some View {
        VStack(spacing: 12) {
            MediaSurface(player: player.player, isAudio: strip.frames.isEmpty && !strip.wave.isEmpty, name: env.urls.first?.lastPathComponent ?? "")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            FilmstripView(frames: strip.frames, wave: strip.wave, overlay: AnyView(trimOverlay))
                .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .padding(16)
    }

    private var trimOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    Color.black.opacity(0.55).frame(width: w * start / max(strip.duration, 0.01))
                    Color.clear.frame(maxWidth: .infinity)
                    Color.black.opacity(0.55).frame(width: w * (strip.duration - end) / max(strip.duration, 0.01))
                }
                RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.accentDeep, lineWidth: 3)
                    .padding(.leading, w * start / max(strip.duration, 0.01))
                    .padding(.trailing, w * (strip.duration - end) / max(strip.duration, 0.01))
                handle(w * start / max(strip.duration, 0.01))
                handle(w * end / max(strip.duration, 0.01))
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let t = v.location.x / w * strip.duration
                if abs(t - start) < abs(t - end) { start = min(max(0, t), end - 0.1) } else { end = max(min(strip.duration, t), start + 0.1) }
            })
        }
    }

    private func handle(_ x: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(Theme.accentDeep).frame(width: 6, height: 28)
            .shadow(radius: 1).offset(x: x - 3)
    }

    private func save() {
        let a = start, b = end
        env.run("Trimming") { u, ctx in try ToolEngine.trim(u[0], start: a, end: b, ctx: ctx) }
    }
}

// MARK: - Speed

struct SpeedPanel: View {
    let env: ToolEnv
    @StateObject private var strip = Filmstrip()
    @State private var factor = 1.0
    static let presets: [(Double, String)] = [(0.5, "0.5×"), (1, "1×"), (1.5, "1.5×"), (2, "2×"), (4, "4×")]

    var body: some View {
        ToolScaffold(env: env, primary: "Save at \(String(format: "%g", factor))×", primaryEnabled: factor != 1, onPrimary: save) {
            VStack(spacing: 14) {
                FilmstripView(frames: strip.frames, wave: strip.wave).padding(.horizontal, 16)
                HStack(spacing: 18) {
                    stat("Length", clock(strip.duration))
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    stat("Becomes", clock(strip.duration / max(factor, 0.01)))
                }
                .font(.system(size: 13))
                Text(factor < 1 ? "Slower, with pitch kept natural." : factor > 1 ? "Faster, with pitch kept natural." : "Original speed.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } controls: {
            SectionLabel("Speed")
            ChipPicker(options: Self.presets, selection: $factor)
            SliderRow(label: "Factor", value: $factor, range: 0.25...4, neutral: 1, display: { String(format: "%.2f×", $0) })
            Text("Audio and picture stay in sync. Very slow or fast clips chain several audio stages.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .onAppear { if let u = env.urls.first { strip.load(u) } }
        .onPanelSet { i in if let f = Double(i["factor"] ?? "") { factor = f } }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .semibold).monospacedDigit())
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func save() {
        let f = factor
        env.run("Changing speed") { u, ctx in try ToolEngine.speed(u[0], factor: f, ctx: ctx) }
    }
}

// MARK: - Split

struct SplitPanel: View {
    let env: ToolEnv
    @StateObject private var strip = Filmstrip()
    @State private var cuts: [Double] = []
    @State private var hover: Double?

    var body: some View {
        ToolScaffold(env: env, primary: cuts.isEmpty ? "Add a cut first" : "Split into \(cuts.count + 1) parts", primaryEnabled: !cuts.isEmpty, onPrimary: save) {
            VStack(spacing: 12) {
                FilmstripView(frames: strip.frames, wave: strip.wave, overlay: AnyView(cutOverlay), onDrag: { hover = $0 * strip.duration }, onEnd: { hover = nil })
                    .padding(.horizontal, 16)
                Text(hover.map { "Click to cut at \(clock($0))" } ?? "Click the strip where you want each cut.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(segments, id: \.0) { seg in
                        Text(clock(seg.1 - seg.0)).font(.system(size: 11).monospacedDigit())
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Theme.step100))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } controls: {
            SectionLabel("Cuts")
            if cuts.isEmpty {
                Text("No cuts yet.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(cuts.sorted(), id: \.self) { c in
                HStack {
                    Image(systemName: "scissors").foregroundStyle(Theme.accentDeep)
                    Text(clock(c)).font(.system(size: 12).monospacedDigit())
                    Spacer()
                    Button { cuts.removeAll { $0 == c } } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            Button("Clear all") { cuts.removeAll() }.disabled(cuts.isEmpty)
            Text("Each part is saved in a \"Parts\" folder next to the file.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .onAppear { if let u = env.urls.first { strip.load(u) } }
        .onPanelSet { i in if i["cuts"] != nil { cuts = numbers(i["cuts"]) } }
    }

    private var segments: [(Double, Double)] {
        let pts = [0] + cuts.sorted() + [strip.duration]
        return (0..<pts.count - 1).map { (pts[$0], pts[$0 + 1]) }
    }

    private var cutOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                ForEach(cuts, id: \.self) { c in
                    Rectangle().fill(Theme.accentDeep).frame(width: 2).offset(x: w * c / max(strip.duration, 0.01))
                }
                if let h = hover {
                    Rectangle().fill(Color.white.opacity(0.8)).frame(width: 1.5).offset(x: w * h / max(strip.duration, 0.01))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                let t = value.location.x / w * strip.duration
                guard t > 0.2, t < strip.duration - 0.2, cuts.allSatisfy({ abs($0 - t) > 0.3 }) else { return }
                cuts.append(t)
            })
        }
    }

    private func save() {
        let pts = cuts
        env.run("Splitting") { u, ctx in try ToolEngine.split(u[0], at: pts, ctx: ctx) }
    }
}

// MARK: - Crop video

struct CropVideoPanel: View {
    let env: ToolEnv
    @StateObject private var strip = Filmstrip()
    @State private var rect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var preset: AspectPreset = .free

    var body: some View {
        ToolScaffold(env: env, primary: "Save Cropped Video", onPrimary: save) {
            ImageStage(image: strip.frames.first) { frame in
                CropOverlay(rect: $rect, frame: frame, aspect: normalizedAspect)
            }
        } controls: {
            SectionLabel("Aspect")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 4)], spacing: 4) {
                ForEach(AspectPreset.allCases) { p in
                    Button { preset = p; withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { rect = CropOverlay.fitted(aspect: p.ratio(original: strip.size), imageSize: strip.size) } } label: {
                        Text(p.rawValue).font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(preset == p ? Theme.accentDeep : Theme.step200))
                            .foregroundStyle(preset == p ? Theme.onInk : Theme.ink)
                    }.buttonStyle(.plain)
                }
            }
            SectionLabel("Output")
            Text("\(Int(rect.width * strip.size.width)) × \(Int(rect.height * strip.size.height)) px")
                .font(.system(size: 12).monospacedDigit())
            Text("The crop is even on both axes, so it stays a valid video size.").font(.system(size: 11)).foregroundStyle(.secondary)
            Button("Reset") { preset = .free; withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { rect = CGRect(x: 0, y: 0, width: 1, height: 1) } }
        }
        .onAppear { if let u = env.urls.first { strip.load(u, count: 1) } }
        .onPanelSet { i in if let p = i["preset"].flatMap(AspectPreset.init(rawValue:)) { preset = p; rect = CropOverlay.fitted(aspect: p.ratio(original: strip.size), imageSize: strip.size) } }
    }

    private var normalizedAspect: CGFloat? {
        guard let r = preset.ratio(original: strip.size), strip.size.width > 0 else { return nil }
        return r * strip.size.height / strip.size.width
    }

    private func save() {
        let r = rect
        env.run("Cropping video") { u, ctx in try ToolEngine.cropVideo(u[0], rect: r, ctx: ctx) }
    }
}

// MARK: - Bleep

struct BleepPanel: View {
    let env: ToolEnv
    @StateObject private var strip = Filmstrip()
    @StateObject private var player = ClipPlayer()
    @State private var ranges: [ClosedRange<Double>] = []
    @State private var drag: ClosedRange<Double>?
    @State private var tone = 1000.0
    @State private var entire = false

    var body: some View {
        ToolScaffold(env: env, primary: entire ? "Bleep the whole clip" : "Bleep \(ranges.count) range\(ranges.count == 1 ? "" : "s")",
                     primaryEnabled: entire || !ranges.isEmpty, onPrimary: save) {
            VStack(spacing: 12) {
                MediaSurface(player: player.player, isAudio: strip.frames.isEmpty && !strip.wave.isEmpty, name: env.urls.first?.lastPathComponent ?? "")
                    .frame(maxHeight: .infinity)
                FilmstripView(frames: strip.frames, wave: strip.wave, overlay: AnyView(rangeOverlay)).padding(.horizontal, 16).padding(.bottom, 16)
            }
            .padding(16)
        } controls: {
            Toggle(isOn: $entire) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bleep everything").font(.system(size: 12, weight: .medium))
                    Text("Covers the whole clip").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(AccentSwitchStyle()).disabled(strip.duration == 0)
            SectionLabel("Ranges")
            if ranges.isEmpty && !entire { Text("Drag across the strip to mark a range.").font(.system(size: 12)).foregroundStyle(.secondary) }
            ForEach(ranges.indices, id: \.self) { i in
                HStack {
                    Text("\(clock(ranges[i].lowerBound)) – \(clock(ranges[i].upperBound))").font(.system(size: 12).monospacedDigit())
                    Spacer()
                    Button { ranges.remove(at: i) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            SliderRow(label: "Tone", value: $tone, range: 200...2000, neutral: 1000, display: { "\(Int($0)) Hz" })
            Button(player.playing ? "Stop" : "Preview") { player.toggle(from: 0, to: strip.duration) }.disabled(strip.frames.isEmpty && strip.duration == 0)
            Text("The picture is kept. Only the sound in each range is replaced by the tone.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .onAppear { if let u = env.urls.first { strip.load(u); player.load(u) } }
        .onDisappear { player.stop() }
        .onPanelSet { i in let n = numbers(i["ranges"]); if n.count >= 2 { ranges = stride(from: 0, to: n.count - 1, by: 2).map { n[$0]...n[$0 + 1] } } }
    }

    private var rangeOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width, d = max(strip.duration, 0.01)
            ZStack(alignment: .leading) {
                ForEach(ranges.indices, id: \.self) { i in
                    Rectangle().fill(Theme.accentDeep.opacity(0.45))
                        .frame(width: w * (ranges[i].upperBound - ranges[i].lowerBound) / d)
                        .offset(x: w * ranges[i].lowerBound / d)
                }
                if let g = drag {
                    Rectangle().fill(Color.white.opacity(0.35))
                        .frame(width: w * (g.upperBound - g.lowerBound) / d).offset(x: w * g.lowerBound / d)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2).onChanged { v in
                let a = min(max(v.startLocation.x, 0), w) / w * d
                let b = min(max(v.location.x, 0), w) / w * d
                drag = min(a, b)...max(a, b)
            }.onEnded { _ in
                if let g = drag, g.upperBound - g.lowerBound > 0.15 { ranges.append(g) }
                drag = nil
            })
        }
    }

    private func save() {
        let rs = ranges, all = entire, hz = tone
        env.run("Bleeping") { u, ctx in try ToolEngine.bleep(u[0], ranges: rs, entire: all, frequency: hz, ctx: ctx) }
    }
}

// MARK: - Channels

struct ChannelsPanel: View {
    let env: ToolEnv
    @State private var mono = false
    @State private var left = 1.0
    @State private var right = 1.0

    var body: some View {
        ToolScaffold(env: env, primary: mono ? "Save as Mono" : "Save Stereo Mix", onPrimary: save) {
            VStack(spacing: 22) {
                Image(systemName: mono ? "speaker.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 44)).foregroundStyle(Theme.accentDeep)
                Text(mono ? "Both ears hear the same mix." : "Left and right stay separate.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                HStack(spacing: 28) {
                    meter("Left", left)
                    if !mono { meter("Right", right) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } controls: {
            ChipPicker(options: [(false, "Stereo"), (true, "Mono")], selection: $mono)
            SectionLabel(mono ? "Mix" : "Levels")
            SliderRow(label: "Left", value: $left, range: 0...1, neutral: 1, display: { "\(Int($0 * 100))%" })
            SliderRow(label: "Right", value: $right, range: 0...1, neutral: 1, display: { "\(Int($0 * 100))%" })
            Text(mono ? "Mono blends the two sides at the levels above." : "Turn a side down to quiet it, or to zero to drop it.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .onPanelSet { i in
            if let m = i["mono"] { mono = m == "1" }
            if let l = Double(i["left"] ?? "") { left = l }
            if let r = Double(i["right"] ?? "") { right = r }
        }
    }

    private func meter(_ name: String, _ v: Double) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(Theme.accentDeep).frame(height: 90 * v)
            }
            .frame(width: 18, height: 90)
            Text(name).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func save() {
        let m = mono, l = left, r = right
        env.run("Mixing channels") { u, ctx in try ToolEngine.channels(u[0], mono: m, left: l, right: r, ctx: ctx) }
    }
}
