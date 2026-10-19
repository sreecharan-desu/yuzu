import Foundation
import AVFoundation
import PDFKit
import ImageIO

/// The work behind the video, audio and PDF tools. Every operation writes a new file next to the source.
enum ToolEngine {
    // MARK: One-shot dispatch

    static func oneShot(_ tool: FileTool, inputs: [URL], ctx: JobContext) throws -> URL {
        let src = inputs[0]
        switch tool {
        case .mute: return try mute(src, ctx: ctx)
        case .compressVideo: return try compressVideo(src, ctx: ctx)
        case .compressAudio: return try compressAudio(src, ctx: ctx)
        case .normalize: return try normalize(src, ctx: ctx)
        case .join: return try join(inputs, ctx: ctx)
        case .compressPDF: return try compressPDF(src, ctx: ctx)
        case .merge: return try mergePDFs(inputs, ctx: ctx)
        case .makePDF: return try imagesToPDF(inputs, sameWidth: true, ctx: ctx)
        default: throw YuzuError.unsupported("\(tool.title) needs its panel.")
        }
    }

    // MARK: ffmpeg plumbing

    static func target(for src: URL) -> Target {
        let ext = src.pathExtension.lowercased()
        if let t = Target.same(as: ext), !MediaEngine.codecArgs(t).isEmpty { return t }
        return FileKind.of(src) == .audio ? .m4a : .mp4
    }

    static func isAudioOnly(_ src: URL) -> Bool { FileKind.of(src) == .audio }

    /// Runs ffmpeg into a hidden partial file, reports progress against `duration`, then moves it into place.
    static func ffmpeg(_ args: [String], to dest: URL, duration: Double, ctx: JobContext) throws {
        let ff = try ToolLocator.require("ffmpeg")
        let partial = dest.deletingLastPathComponent()
            .appendingPathComponent(".\(dest.deletingPathExtension().lastPathComponent).yuzu-partial.\(dest.pathExtension)")
        try? FileManager.default.removeItem(at: partial)
        defer { try? FileManager.default.removeItem(at: partial) }
        let full = ["-hide_banner", "-nostdin", "-y"] + args + ["-progress", "pipe:1", "-nostats", "-loglevel", "error", partial.path]
        ctx.report(0.01)
        try ToolLocator.run(ff, full, ctx: ctx, timeout: 3600, onLine: { line in
            guard duration > 0, line.hasPrefix("out_time_us="), let us = Double(line.dropFirst(12)) else { return }
            ctx.report(us / 1_000_000 / duration)
        })
        guard FileManager.default.fileExists(atPath: partial.path) else { throw YuzuError.writeFailed(dest.lastPathComponent) }
        try FileManager.default.moveItem(at: partial, to: dest)
        ctx.report(1)
    }

    static func hasAudio(_ url: URL) -> Bool {
        guard let probe = ToolLocator.ffprobe,
              let r = try? ToolLocator.run(probe, ["-v", "error", "-select_streams", "a", "-show_entries", "stream=index", "-of", "csv=p=0", url.path])
        else {
            let asset = AVURLAsset(url: url)
            return !((try? AsyncBridge.run { try await asset.loadTracks(withMediaType: .audio) }) ?? []).isEmpty
        }
        return !r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func videoSize(_ url: URL) -> (Int, Int) {
        if let probe = ToolLocator.ffprobe,
           let r = try? ToolLocator.run(probe, ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", url.path]) {
            let p = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",").compactMap { Int($0) }
            if p.count == 2 { return (p[0], p[1]) }
        }
        return (1280, 720)
    }

    /// Audio codec arguments matching the container of `t` (for filters that re-encode audio only).
    static func audioCodec(_ t: Target) -> [String] {
        switch t {
        case .webm, .opus: return ["-c:a", "libopus", "-b:a", "128k"]
        case .mp3: return ["-c:a", "libmp3lame", "-q:a", "2"]
        case .wav: return ["-c:a", "pcm_s16le"]
        case .aiff: return ["-c:a", "pcm_s16be"]
        case .flac: return ["-c:a", "flac"]
        case .ogg: return ["-c:a", "vorbis", "-strict", "-2", "-ac", "2"]
        case .wma, .wmv: return ["-c:a", "wmav2", "-b:a", "192k"]
        case .avi: return ["-c:a", "libmp3lame", "-q:a", "3"]
        default: return ["-c:a", "aac", "-b:a", "192k"]
        }
    }

    /// Keeps video untouched and re-encodes audio through `filter`.
    private static func audioFilterArgs(_ src: URL, filter: String) -> [String] {
        let t = target(for: src)
        if isAudioOnly(src) { return ["-i", src.path, "-vn", "-af", filter] + audioCodec(t) }
        return ["-i", src.path, "-map", "0:v:0?", "-map", "0:a:0?", "-c:v", "copy", "-af", filter] + audioCodec(t)
    }

    // MARK: Video and audio

    static func trim(_ src: URL, start: Double, end: Double, ctx: JobContext) throws -> URL {
        let t = target(for: src)
        let dest = OutputNamer.destination(for: src, ext: t.ext, suffix: FileTool.trim.suffix)
        try ffmpeg(["-ss", fmt(start), "-to", fmt(end), "-i", src.path] + MediaEngine.codecArgs(t), to: dest, duration: end - start, ctx: ctx)
        return dest
    }

    static func speed(_ src: URL, factor: Double, ctx: JobContext) throws -> URL {
        let t = target(for: src)
        let dest = OutputNamer.destination(for: src, ext: t.ext, suffix: "\(trimZeros(factor))x")
        var args = ["-i", src.path]
        if !isAudioOnly(src) { args += ["-filter:v", "setpts=PTS/\(factor)"] }
        if isAudioOnly(src) || hasAudio(src) { args += ["-filter:a", atempo(factor)] }
        try ffmpeg(args + MediaEngine.codecArgs(t), to: dest, duration: MediaEngine.probeDuration(src) / factor, ctx: ctx)
        return dest
    }

    /// atempo accepts 0.5...2 per stage, so larger changes chain stages.
    static func atempo(_ f: Double) -> String {
        var stages: [Double] = []
        var r = f
        while r > 2 { stages.append(2); r /= 2 }
        while r < 0.5 { stages.append(0.5); r /= 0.5 }
        stages.append(r)
        return stages.map { "atempo=\(String(format: "%.4f", $0))" }.joined(separator: ",")
    }

    static func split(_ src: URL, at points: [Double], ctx: JobContext) throws -> URL {
        let duration = MediaEngine.probeDuration(src)
        let cuts = ([0] + points.filter { $0 > 0.05 && $0 < duration - 0.05 }.sorted() + [duration])
        let t = target(for: src)
        let folder = OutputNamer.folder(for: src, suffix: FileTool.split.suffix)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = src.deletingPathExtension().lastPathComponent
        let parts = cuts.count - 1
        for i in 0..<parts {
            try ctx.checkCancelled()
            let dest = folder.appendingPathComponent("\(base) part \(i + 1)").appendingPathExtension(t.ext)
            let sub = JobContext(settings: ctx.settings)
            sub.onProgress = { f in ctx.report((Double(i) + f) / Double(parts)) }
            try ffmpeg(["-ss", fmt(cuts[i]), "-to", fmt(cuts[i + 1]), "-i", src.path] + MediaEngine.codecArgs(t),
                       to: dest, duration: cuts[i + 1] - cuts[i], ctx: sub)
        }
        return folder
    }

    /// `rect` is normalized (0...1, origin top-left).
    static func cropVideo(_ src: URL, rect: CGRect, ctx: JobContext) throws -> URL {
        let (w, h) = videoSize(src)
        func even(_ v: Double) -> Int { max(2, Int(v) / 2 * 2) }
        let cw = even(rect.width * Double(w)), ch = even(rect.height * Double(h))
        let cx = even(rect.minX * Double(w)), cy = even(rect.minY * Double(h))
        let t = target(for: src)
        let dest = OutputNamer.destination(for: src, ext: t.ext, suffix: FileTool.cropVideo.suffix)
        try ffmpeg(["-i", src.path, "-filter:v", "crop=\(cw):\(ch):\(cx):\(cy)"] + MediaEngine.codecArgs(t),
                   to: dest, duration: MediaEngine.probeDuration(src), ctx: ctx)
        return dest
    }

    static func mute(_ src: URL, ctx: JobContext) throws -> URL {
        guard !isAudioOnly(src) else { throw YuzuError.unsupported("Mute works on videos.") }
        let t = target(for: src)
        let dest = OutputNamer.destination(for: src, ext: t.ext, suffix: FileTool.mute.suffix)
        try ffmpeg(["-i", src.path, "-map", "0:v", "-c", "copy", "-an"], to: dest, duration: MediaEngine.probeDuration(src), ctx: ctx)
        return dest
    }

    static func compressVideo(_ src: URL, ctx: JobContext) throws -> URL {
        let dest = OutputNamer.destination(for: src, ext: "mp4", suffix: FileTool.compressVideo.suffix)
        try ffmpeg(["-i", src.path, "-map", "0:v:0?", "-map", "0:a:0?",
                    "-vf", "scale=-2:'min(1080,ih)'", "-c:v", "libx264", "-preset", "medium", "-crf", "27", "-pix_fmt", "yuv420p",
                    "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart"],
                   to: dest, duration: MediaEngine.probeDuration(src), ctx: ctx)
        return dest
    }

    static func compressAudio(_ src: URL, ctx: JobContext) throws -> URL {
        let mp3 = src.pathExtension.lowercased() == "mp3"
        let dest = OutputNamer.destination(for: src, ext: mp3 ? "mp3" : "m4a", suffix: FileTool.compressAudio.suffix)
        let codec = mp3 ? ["-c:a", "libmp3lame", "-b:a", "96k"] : ["-c:a", "aac", "-b:a", "96k"]
        try ffmpeg(["-i", src.path, "-vn"] + codec, to: dest, duration: MediaEngine.probeDuration(src), ctx: ctx)
        return dest
    }

    static func normalize(_ src: URL, ctx: JobContext) throws -> URL {
        let t = target(for: src)
        let dest = OutputNamer.destination(for: src, ext: t.ext, suffix: FileTool.normalize.suffix)
        try ffmpeg(audioFilterArgs(src, filter: "loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000"), to: dest,
                   duration: MediaEngine.probeDuration(src), ctx: ctx)
        return dest
    }

    /// Mutes the given ranges and plays a tone over them. `entire` bleeps the whole file.
    static func bleep(_ src: URL, ranges: [ClosedRange<Double>], entire: Bool, frequency: Double = 1000,
                      to explicitDest: URL? = nil, ctx: JobContext) throws -> URL {
        let duration = MediaEngine.probeDuration(src)
        let spans = entire ? [0...max(duration, 0.1)] : ranges
        guard !spans.isEmpty else { throw YuzuError.unsupported("Add at least one bleep range.") }
        let cond = spans.map { "between(t,\(fmt($0.lowerBound)),\(fmt($0.upperBound)))" }.joined(separator: "+")
        let t = target(for: src)
        let dest = explicitDest ?? OutputNamer.destination(for: src, ext: t.ext, suffix: FileTool.bleep.suffix)
        let graph = "[0:a]volume='if(\(cond),0,1)':eval=frame[m];" +
            // sine= starts at 1/8 full scale, so 1.6 brings the tone to about -17 dB RMS, level with normal speech.
            "sine=f=\(Int(frequency)):sample_rate=48000:d=\(fmt(duration + 0.5)),volume='if(\(cond),1.6,0)':eval=frame[b];" +
            "[m][b]amix=inputs=2:duration=first:normalize=0[out]"
        var args = ["-i", src.path, "-filter_complex", graph]
        if isAudioOnly(src) || explicitDest != nil { args += ["-map", "[out]", "-vn"] + audioCodec(explicitDest.map { Target.same(as: $0.pathExtension) ?? .m4a } ?? t) }
        else { args += ["-map", "0:v:0?", "-map", "[out]", "-c:v", "copy"] + audioCodec(t) }
        try ffmpeg(args, to: dest, duration: duration, ctx: ctx)
        return dest
    }

    static func channels(_ src: URL, mono: Bool, left: Double, right: Double, ctx: JobContext) throws -> URL {
        let filter = mono
            ? "aformat=channel_layouts=stereo,pan=mono|c0=\(fmt(0.5 * left))*c0+\(fmt(0.5 * right))*c1"
            : "aformat=channel_layouts=stereo,pan=stereo|c0=\(fmt(left))*c0|c1=\(fmt(right))*c1"
        let t = target(for: src)
        let dest = OutputNamer.destination(for: src, ext: t.ext, suffix: mono ? "Mono" : "Stereo")
        try ffmpeg(audioFilterArgs(src, filter: filter), to: dest, duration: MediaEngine.probeDuration(src), ctx: ctx)
        return dest
    }

    /// Joins videos (scaled and padded to the first one's size) or audio files, in Finder name order.
    static func join(_ inputs: [URL], ctx: JobContext) throws -> URL {
        guard inputs.count > 1 else { throw YuzuError.unsupported("Drop two or more files to join.") }
        let audioOnly = inputs.allSatisfy(isAudioOnly)
        let first = inputs[0]
        let total = inputs.map(MediaEngine.probeDuration).reduce(0, +)
        var args: [String] = []
        var graph = ""
        var labels = ""
        if audioOnly {
            for (i, u) in inputs.enumerated() {
                args += ["-i", u.path]
                graph += "[\(i):a]aresample=48000,aformat=channel_layouts=stereo[a\(i)];"
                labels += "[a\(i)]"
            }
            graph += "\(labels)concat=n=\(inputs.count):v=0:a=1[a]"
            let t = target(for: first)
            let dest = OutputNamer.destination(for: first, ext: t.ext, suffix: FileTool.join.suffix)
            try ffmpeg(args + ["-filter_complex", graph, "-map", "[a]"] + audioCodec(t), to: dest, duration: total, ctx: ctx)
            return dest
        }
        var (w, h) = videoSize(first)
        w = w / 2 * 2; h = h / 2 * 2
        var inputIndex = 0
        for u in inputs {
            let v = inputIndex
            args += ["-i", u.path]
            inputIndex += 1
            var a = "\(v):a"
            if !hasAudio(u) {
                args += ["-f", "lavfi", "-t", fmt(MediaEngine.probeDuration(u)), "-i", "anullsrc=r=48000:cl=stereo"]
                a = "\(inputIndex):a"
                inputIndex += 1
            }
            graph += "[\(v):v]scale=\(w):\(h):force_original_aspect_ratio=decrease,pad=\(w):\(h):(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30,format=yuv420p[v\(v)];"
            graph += "[\(a)]aresample=48000,aformat=channel_layouts=stereo[a\(v)];"
            labels += "[v\(v)][a\(v)]"
        }
        graph += "\(labels)concat=n=\(inputs.count):v=1:a=1[v][a]"
        let dest = OutputNamer.destination(for: first, ext: "mp4", suffix: FileTool.join.suffix)
        try ffmpeg(args + ["-filter_complex", graph, "-map", "[v]", "-map", "[a]", "-c:v", "libx264", "-preset", "medium", "-crf", "20",
                           "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"], to: dest, duration: total, ctx: ctx)
        return dest
    }

    // MARK: PDF

    static func compressPDF(_ src: URL, ctx: JobContext) throws -> URL {
        guard let doc = PDFDocument(url: src) else { throw YuzuError.unreadable(src.lastPathComponent) }
        let dest = OutputNamer.destination(for: src, ext: "pdf", suffix: FileTool.compressPDF.suffix)
        ctx.report(0.2)
        let ok = doc.write(to: dest, withOptions: [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true])
        guard ok else { throw YuzuError.writeFailed(dest.lastPathComponent) }
        if SizeText.of([dest]) >= SizeText.of([src]) {
            try? FileManager.default.removeItem(at: dest)
            throw YuzuError.unsupported("This PDF is already as small as Yuzu can make it.")
        }
        return dest
    }

    static func mergePDFs(_ inputs: [URL], ctx: JobContext) throws -> URL {
        guard inputs.count > 1 else { throw YuzuError.unsupported("Drop two or more PDFs to merge.") }
        let out = PDFDocument()
        for (i, u) in inputs.enumerated() {
            guard let d = PDFDocument(url: u) else { throw YuzuError.unreadable(u.lastPathComponent) }
            for p in 0..<d.pageCount { if let page = d.page(at: p) { out.insert(page, at: out.pageCount) } }
            ctx.report(Double(i + 1) / Double(inputs.count) * 0.8)
        }
        let dest = OutputNamer.destination(for: inputs[0], ext: "pdf", suffix: FileTool.merge.suffix)
        guard out.write(to: dest) else { throw YuzuError.writeFailed(dest.lastPathComponent) }
        return dest
    }

    /// `groups` are 0-based page indexes; each group becomes one file in a "Parts" folder.
    static func splitPDF(_ src: URL, groups: [[Int]], ctx: JobContext) throws -> URL {
        guard let doc = PDFDocument(url: src) else { throw YuzuError.unreadable(src.lastPathComponent) }
        let folder = OutputNamer.folder(for: src, suffix: FileTool.splitPDF.suffix)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = src.deletingPathExtension().lastPathComponent
        for (i, g) in groups.enumerated() {
            let part = PDFDocument()
            for idx in g where idx >= 0 && idx < doc.pageCount {
                if let page = doc.page(at: idx)?.copy() as? PDFPage { part.insert(page, at: part.pageCount) }
            }
            guard part.pageCount > 0 else { continue }
            let label = g.count == 1 ? "page \(g[0] + 1)" : "pages \(g.first! + 1)-\(g.last! + 1)"
            part.write(to: folder.appendingPathComponent("\(base) \(label).pdf"))
            ctx.report(Double(i + 1) / Double(groups.count))
        }
        return folder
    }

    /// Parses "1-3, 5, 7-9" into 0-based groups.
    static func parseRanges(_ text: String, pageCount: Int) -> [[Int]] {
        text.split(separator: ",").compactMap { part in
            let bits = part.split(separator: "-").map { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard let a = bits.first ?? nil else { return nil }
            let b = (bits.count > 1 ? bits[1] : a) ?? a
            let lo = max(1, min(a, b)), hi = min(pageCount, max(a, b))
            return lo <= hi ? Array((lo - 1)...(hi - 1)) : nil
        }
    }

    /// Writes pages in the given order with extra rotation (degrees, multiples of 90).
    static func organizePDF(_ src: URL, pages: [(index: Int, rotation: Int)], ctx: JobContext) throws -> URL {
        guard let doc = PDFDocument(url: src) else { throw YuzuError.unreadable(src.lastPathComponent) }
        let out = PDFDocument()
        for p in pages {
            guard let page = doc.page(at: p.index)?.copy() as? PDFPage else { continue }
            page.rotation = ((page.rotation + p.rotation) % 360 + 360) % 360
            out.insert(page, at: out.pageCount)
        }
        guard out.pageCount > 0 else { throw YuzuError.unsupported("Keep at least one page.") }
        let dest = OutputNamer.destination(for: src, ext: "pdf", suffix: FileTool.organize.suffix)
        guard out.write(to: dest) else { throw YuzuError.writeFailed(dest.lastPathComponent) }
        return dest
    }

    /// One page per image, in Finder name order; opaque photos embed as JPEG.
    static func imagesToPDF(_ inputs: [URL], sameWidth: Bool, ctx: JobContext) throws -> URL {
        let dest = OutputNamer.destination(for: inputs[0], ext: "pdf", suffix: inputs.count > 1 ? FileTool.makePDF.suffix : nil)
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let pdf = CGContext(dest as CFURL, mediaBox: &mediaBox, [kCGPDFContextCreator: "Yuzu"] as CFDictionary) else {
            throw YuzuError.writeFailed(dest.lastPathComponent)
        }
        var width: CGFloat?
        for (i, u) in inputs.enumerated() {
            try ctx.checkCancelled()
            let decoded = try ImageEngine.decode(u, maxPixel: 4000)
            let img = decoded.image
            let opaque = (decoded.properties[kCGImagePropertyHasAlpha] as? Bool) == false
            var w = CGFloat(img.width) * 72 / 150, h = CGFloat(img.height) * 72 / 150
            if sameWidth {
                if width == nil { width = w }
                h *= width! / w; w = width!
            }
            var box = CGRect(x: 0, y: 0, width: w, height: h)
            pdf.beginPage(mediaBox: &box)
            pdf.draw(opaque ? ImageEngine.jpegBacked(img) : img, in: box)
            pdf.endPage()
            ctx.report(Double(i + 1) / Double(inputs.count))
        }
        pdf.closePDF()
        return dest
    }

    // MARK: helpers

    static func fmt(_ v: Double) -> String { String(format: "%.3f", v) }
    static func trimZeros(_ v: Double) -> String {
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
