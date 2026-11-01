import Foundation

/// SRT, WebVTT and plain text transcripts. same parsing rules as SubtitleEngine in the mac app.
public enum Subtitles {
    public struct Cue: Equatable, Sendable {
        public var start: Double, end: Double, text: String
        public init(start: Double, end: Double, text: String) { self.start = start; self.end = end; self.text = text }
    }

    public static func parse(_ text: String) -> [Cue] {
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

    public static func seconds(_ s: String) -> Double? {
        let parts = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0.0
        for p in parts { guard let v = Double(p) else { return nil }; total = total * 60 + v }
        return total
    }

    public static func stamp(_ t: Double, _ sep: String) -> String {
        let ms = Int((t * 1000).rounded())
        func pad(_ n: Int, _ w: Int) -> String { let s = String(n); return String(repeating: "0", count: max(0, w - s.count)) + s }
        return "\(pad(ms / 3_600_000, 2)):\(pad((ms / 60_000) % 60, 2)):\(pad((ms / 1000) % 60, 2))\(sep)\(pad(ms % 1000, 3))"
    }

    public static func render(_ cues: [Cue], as t: Target) -> String? {
        switch t {
        case .srt:
            return cues.enumerated().map { i, c in "\(i + 1)\n\(stamp(c.start, ",")) --> \(stamp(c.end, ","))\n\(c.text)\n" }
                .joined(separator: "\n")
        case .vtt:
            return "WEBVTT\n\n" + cues.map { c in "\(stamp(c.start, ".")) --> \(stamp(c.end, "."))\n\(c.text)\n" }.joined(separator: "\n")
        case .txt:
            return cues.map { $0.text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression) }
                .joined(separator: "\n") + "\n"
        default: return nil
        }
    }
}
