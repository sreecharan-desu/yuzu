import Foundation

/// SRT, WebVTT and plain text transcripts.
enum SubtitleEngine {
    struct Cue { var start: Double; var end: Double; var text: String }

    static func convert(_ src: URL, to t: Target, ctx: JobContext) throws -> URL {
        let cues = parse(try SheetEngine.readText(src))
        guard !cues.isEmpty else { throw YuzuError.unreadable(src.lastPathComponent) }
        let out: String
        switch t {
        case .srt:
            out = cues.enumerated().map { i, c in "\(i + 1)\n\(stamp(c.start, ",")) --> \(stamp(c.end, ","))\n\(c.text)\n" }
                .joined(separator: "\n")
        case .vtt:
            out = "WEBVTT\n\n" + cues.map { c in "\(stamp(c.start, ".")) --> \(stamp(c.end, "."))\n\(c.text)\n" }.joined(separator: "\n")
        case .txt:
            out = cues.map { $0.text.replacing(/<[^>]+>/, with: "") }.joined(separator: "\n") + "\n"
        default: throw YuzuError.unsupported("\(t.title) is not available for subtitles.")
        }
        let dest = OutputNamer.destination(for: src, ext: t.ext)
        try out.write(to: dest, atomically: true, encoding: .utf8)
        return dest
    }

    static func parse(_ text: String) -> [Cue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var cues: [Cue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard let idx = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[idx].components(separatedBy: "-->")
            guard parts.count == 2, let a = seconds(parts[0]),
                  let b = seconds(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? "") else { continue }
            let body = lines[(idx + 1)...].joined(separator: "\n")
            if !body.isEmpty { cues.append(Cue(start: a, end: b, text: body)) }
        }
        return cues
    }

    static func seconds(_ s: String) -> Double? {
        let parts = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0.0
        for p in parts { guard let v = Double(p) else { return nil }; total = total * 60 + v }
        return total
    }

    static func stamp(_ t: Double, _ sep: String) -> String {
        let ms = Int((t * 1000).rounded())
        return String(format: "%02d:%02d:%02d\(sep)%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }
}
