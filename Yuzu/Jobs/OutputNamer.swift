import Foundation

enum OutputNamer {
    /// Names handed out in the last minute, so parallel jobs never pick the same file before either writes it.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var reserved: [String: Date] = [:]

    private static func taken(_ url: URL) -> Bool {
        if FileManager.default.fileExists(atPath: url.path) { return true }
        if let at = reserved[url.path], Date().timeIntervalSince(at) < 60 { return true }
        return false
    }

    /// A destination next to `source` that never overwrites anything.
    static func destination(for source: URL, ext: String, suffix: String? = nil) -> URL {
        lock.lock(); defer { lock.unlock() }
        if reserved.count > 512 { reserved = reserved.filter { Date().timeIntervalSince($0.value) < 60 } }
        let dir = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent
        let stem = suffix.map { "\(base) \($0)" } ?? base
        var candidate = dir.appendingPathComponent(stem).appendingPathExtension(ext)
        var n = 2
        while taken(candidate) || candidate.standardizedFileURL == source.standardizedFileURL {
            candidate = dir.appendingPathComponent("\(stem) \(n)").appendingPathExtension(ext)
            n += 1
        }
        reserved[candidate.path] = Date()
        return candidate
    }
}

extension OutputNamer {
    /// A new folder next to `source`, e.g. "report pages", never reusing an existing name.
    static func folder(for source: URL, suffix: String) -> URL {
        let dir = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent("\(base) \(suffix)", isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(suffix) \(n)", isDirectory: true)
            n += 1
        }
        return candidate
    }

    /// Moves a finished scratch file into place next to the source, never overwriting.
    static func deliver(_ produced: URL, for source: URL, ext: String) throws -> URL {
        let dest = destination(for: source, ext: ext)
        try FileManager.default.moveItem(at: produced, to: dest)
        return dest
    }
}
