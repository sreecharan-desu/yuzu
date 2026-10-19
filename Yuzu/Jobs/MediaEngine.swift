import Foundation
import AVFoundation

/// Video and audio conversion. Apple's own encoders handle MOV/MP4/M4A when the source is
/// AVFoundation-readable; everything else goes through Homebrew's ffmpeg with live progress.
enum MediaEngine {
    static func convert(_ src: URL, to t: Target, ctx: JobContext) throws -> URL {
        let dest = OutputNamer.destination(for: src, ext: t.ext)
        let partial = dest.deletingLastPathComponent()
            .appendingPathComponent(".\(dest.deletingPathExtension().lastPathComponent).yuzu-partial.\(t.ext)")
        try? FileManager.default.removeItem(at: partial)
        defer { try? FileManager.default.removeItem(at: partial) }

        if [.mov, .mp4, .m4a].contains(t), let fileType = nativeType(t) {
            do {
                try exportNatively(src, to: partial, fileType: fileType, audioOnly: t == .m4a, ctx: ctx)
                try FileManager.default.moveItem(at: partial, to: dest)
                return dest
            } catch YuzuError.cancelled {
                throw YuzuError.cancelled
            } catch {
                try? FileManager.default.removeItem(at: partial)
                if ToolLocator.ffmpeg == nil { throw error }
                // fall through to ffmpeg
            }
        }

        let ffmpeg = try ToolLocator.require("ffmpeg")
        let duration = probeDuration(src)
        var args = ["-hide_banner", "-nostdin", "-y", "-i", src.path]
        args += codecArgs(t)
        args += ["-progress", "pipe:1", "-nostats", "-loglevel", "error", partial.path]
        ctx.report(0.01)
        do {
            try ToolLocator.run(ffmpeg, args, ctx: ctx, timeout: 3600, onLine: { line in
                guard duration > 0 else { return }
                if line.hasPrefix("out_time_us="), let us = Double(line.dropFirst(12)) {
                    ctx.report(us / 1_000_000 / duration)
                } else if line.hasPrefix("out_time_ms="), let us = Double(line.dropFirst(12)) {
                    ctx.report(us / 1_000_000 / duration)
                }
            })
        } catch YuzuError.tool(let msg) {
            throw YuzuError.tool(friendly(msg))
        }
        guard FileManager.default.fileExists(atPath: partial.path) else { throw YuzuError.writeFailed(dest.lastPathComponent) }
        try FileManager.default.moveItem(at: partial, to: dest)
        ctx.report(1)
        return dest
    }

    private static func friendly(_ msg: String) -> String {
        if msg.contains("does not contain any stream") || msg.contains("matches no streams") {
            return "This file has no track that fits that format (for example no audio)."
        }
        if msg.contains("Invalid data found") { return "ffmpeg could not read this file." }
        return msg
    }

    static func codecArgs(_ t: Target) -> [String] {
        let x264 = ["-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p"]
        switch t {
        case .mp4: return ["-map", "0:v:0?", "-map", "0:a:0?"] + x264 + ["-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
        case .mov: return ["-map", "0:v:0?", "-map", "0:a:0?"] + x264 + ["-c:a", "aac", "-b:a", "192k"]
        case .mkv: return ["-map", "0:v:0?", "-map", "0:a?", "-map", "0:s?"] + x264 + ["-c:a", "aac", "-b:a", "192k", "-c:s", "copy"]
        case .webm: return ["-map", "0:v:0?", "-map", "0:a:0?", "-c:v", "libvpx-vp9", "-crf", "33", "-b:v", "0",
                            "-row-mt", "1", "-deadline", "good", "-cpu-used", "4", "-c:a", "libopus", "-b:a", "128k"]
        case .avi: return ["-map", "0:v:0?", "-map", "0:a:0?", "-c:v", "mpeg4", "-q:v", "3", "-c:a", "libmp3lame", "-q:a", "3"]
        case .wmv: return ["-map", "0:v:0?", "-map", "0:a:0?", "-c:v", "wmv2", "-q:v", "3", "-c:a", "wmav2", "-b:a", "192k"]
        case .gif: return ["-an", "-vf", "fps=12,scale='min(720,iw)':-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a",
                           "-loop", "0"]
        case .mp3: return ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]
        case .m4a: return ["-vn", "-c:a", "aac", "-b:a", "192k"]
        case .wav: return ["-vn", "-c:a", "pcm_s16le"]
        case .flac: return ["-vn", "-c:a", "flac"]
        case .ogg: return ["-vn", "-c:a", "vorbis", "-strict", "-2", "-ac", "2", "-q:a", "5"]  // native vorbis encoder is stereo-only
        case .opus: return ["-vn", "-c:a", "libopus", "-b:a", "128k"]
        case .aiff: return ["-vn", "-c:a", "pcm_s16be"]
        case .wma: return ["-vn", "-c:a", "wmav2", "-b:a", "192k"]
        default: return []
        }
    }

    private static func nativeType(_ t: Target) -> AVFileType? {
        switch t {
        case .mov: return .mov
        case .mp4: return .mp4
        case .m4a: return .m4a
        default: return nil
        }
    }

    static func probeDuration(_ url: URL) -> Double {
        let asset = AVURLAsset(url: url)
        let d = ((try? AsyncBridge.run { try await asset.load(.duration) }) ?? .zero).seconds
        if d.isFinite, d > 0 { return d }
        if let probe = ToolLocator.ffprobe,
           let r = try? ToolLocator.run(probe, ["-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", url.path]),
           let v = Double(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return v
        }
        return 0
    }

    private static func exportNatively(_ src: URL, to dest: URL, fileType: AVFileType, audioOnly: Bool, ctx: JobContext) throws {
        let asset = AVURLAsset(url: src)
        let (exportable, playable, audio) = try AsyncBridge.run {
            try await (asset.load(.isExportable), asset.load(.isPlayable), asset.loadTracks(withMediaType: .audio))
        }
        guard exportable, playable else { throw YuzuError.unsupported("Not readable by AVFoundation") }
        if audioOnly, audio.isEmpty { throw YuzuError.tool("This file has no audio track.") }
        let preset = audioOnly ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset),
              session.supportedFileTypes.contains(fileType) else {
            throw YuzuError.unsupported("No native export for this file")
        }
        session.shouldOptimizeForNetworkUse = fileType == .mp4
        nonisolated(unsafe) let s = session
        let progress = Task.detached {
            for await state in s.states(updateInterval: 0.15) {
                if case .exporting(let p) = state { ctx.report(p.fractionCompleted) }
            }
        }
        defer { progress.cancel() }
        let watcher = Task.detached {
            while !Task.isCancelled {
                if ctx.isCancelled { s.cancelExport(); return }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        defer { watcher.cancel() }
        do {
            try AsyncBridge.run { try await s.export(to: dest, as: fileType) }
        } catch {
            try ctx.checkCancelled()
            throw error
        }
        try ctx.checkCancelled()
    }
}
