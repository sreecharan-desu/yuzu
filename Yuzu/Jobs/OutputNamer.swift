import Foundation

enum OutputNamer {
    /// A destination next to `source` that never overwrites anything.
    static func destination(for source: URL, ext: String, suffix: String? = nil) -> URL {
        let dir = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent
        let stem = suffix.map { "\(base) \($0)" } ?? base
        var candidate = dir.appendingPathComponent(stem).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) || candidate.standardizedFileURL == source.standardizedFileURL {
            candidate = dir.appendingPathComponent("\(stem) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }
}
