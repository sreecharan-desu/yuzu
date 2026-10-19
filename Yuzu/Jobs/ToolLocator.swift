import Foundation

/// Finds command-line engines already installed on this Mac. Nothing is bundled.
enum ToolLocator {
    static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
                              "/Applications/LibreOffice.app/Contents/MacOS"]

    /// Brew install hints shown when a tool is missing.
    static let installHint: [String: String] = [
        "ffmpeg": "brew install ffmpeg",
        "ffprobe": "brew install ffmpeg",
        "cwebp": "brew install webp",
        "exiftool": "brew install exiftool",
        "soffice": "brew install --cask libreoffice",
    ]

    /// Tools listed in the `debug.hideTools` default are treated as missing (used to test error paths).
    private static var hidden: Set<String> {
        Set((UserDefaults.standard.string(forKey: "debug.hideTools") ?? "").split(separator: ",").map(String.init))
    }

    static func path(for name: String) -> String? {
        if hidden.contains(name) { return nil }
        for dir in searchPaths {
            let p = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    static var cwebp: String? { path(for: "cwebp") }
    static var ffmpeg: String? { path(for: "ffmpeg") }
    static var ffprobe: String? { path(for: "ffprobe") }
    static var exiftool: String? { path(for: "exiftool") }
    static var soffice: String? { path(for: "soffice") }

    static func require(_ name: String) throws -> String {
        guard let p = path(for: name) else { throw YuzuError.missingTool(name) }
        return p
    }

    struct Status: Identifiable { let id: String; let path: String?; let use: String }

    static var all: [Status] {
        [Status(id: "ffmpeg", path: ffmpeg, use: "Video and audio"),
         Status(id: "cwebp", path: cwebp, use: "WebP export"),
         Status(id: "exiftool", path: exiftool, use: "Metadata"),
         Status(id: "soffice", path: soffice, use: "Office documents (LibreOffice)")]
    }

    struct Result { let status: Int32; let stdout: String; let stderr: String }

    /// Runs a tool and waits, optionally streaming stdout lines. Honors job cancellation and a timeout.
    @discardableResult
    static func run(_ tool: String, _ args: [String], ctx: JobContext? = nil, timeout: TimeInterval = 600,
                    env: [String: String] = [:], cwd: URL? = nil, onLine: (@Sendable (String) -> Void)? = nil,
                    check: Bool = true) throws -> Result {
        try ctx?.checkCancelled()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = (searchPaths + ["/bin", "/usr/sbin", "/sbin"]).joined(separator: ":")
        for (k, v) in env { environment[k] = v }
        p.environment = environment
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err

        let buffer = LineBuffer(onLine: onLine)
        out.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil } else { buffer.append(d) }
        }
        let errBuffer = LineBuffer(onLine: nil)
        err.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil } else { errBuffer.append(d) }
        }

        try p.run()
        ctx?.attach(p)
        let timer = DispatchWorkItem { if p.isRunning { buffer.timedOut = true; p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        p.waitUntilExit()
        timer.cancel()
        ctx?.detach()
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        buffer.append(out.fileHandleForReading.readDataToEndOfFile())
        errBuffer.append(err.fileHandleForReading.readDataToEndOfFile())
        buffer.flush()

        try ctx?.checkCancelled()
        let name = (tool as NSString).lastPathComponent
        if buffer.timedOut { throw YuzuError.tool("\(name) took too long and was stopped.") }
        let result = Result(status: p.terminationStatus, stdout: buffer.text, stderr: errBuffer.text)
        if check && p.terminationStatus != 0 {
            let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw YuzuError.tool("\(name) failed: \(msg.suffix(240))")
        }
        return result
    }
}

/// Thread-safe accumulator that splits streamed output into lines.
final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private var all = Data()
    private let onLine: (@Sendable (String) -> Void)?
    var timedOut = false

    init(onLine: (@Sendable (String) -> Void)?) { self.onLine = onLine }

    func append(_ d: Data) {
        guard !d.isEmpty else { return }
        var lines: [String] = []
        lock.lock()
        all.append(d)
        pending.append(d)
        while let nl = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex..<nl]
            lines.append(String(decoding: line, as: UTF8.self))
            pending.removeSubrange(pending.startIndex...nl)
        }
        lock.unlock()
        if let onLine { lines.forEach(onLine) }
    }

    func flush() {
        lock.lock(); let rest = pending; pending.removeAll(); lock.unlock()
        if !rest.isEmpty { onLine?(String(decoding: rest, as: UTF8.self)) }
    }

    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: all, as: UTF8.self) }
}

/// Shared state for one running job: settings, progress, and cancellation.
final class JobContext: @unchecked Sendable {
    let settings: ImageSettings
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?
    private weak var parent: JobContext?
    private var children: [JobContext] = []
    var onProgress: (@Sendable (Double) -> Void)?

    init(settings: ImageSettings) { self.settings = settings }

    /// A context for one unit of a parallel job: it has its own process and progress, and cancelling the
    /// parent cancels every child.
    func child() -> JobContext {
        let c = JobContext(settings: settings)
        c.parent = self
        lock.lock(); children.append(c); let dead = cancelled; lock.unlock()
        if dead { c.cancel() }
        return c
    }

    var isCancelled: Bool {
        lock.lock(); let c = cancelled; lock.unlock()
        return c || (parent?.isCancelled ?? false)
    }

    func cancel() {
        lock.lock(); cancelled = true; let p = process; let kids = children; lock.unlock()
        if let p, p.isRunning { p.terminate() }
        kids.forEach { $0.cancel() }
    }

    func attach(_ p: Process) {
        lock.lock(); process = p; let c = cancelled; lock.unlock()
        if c, p.isRunning { p.terminate() }
    }

    func detach() { lock.lock(); process = nil; lock.unlock() }
    func report(_ f: Double) { onProgress?(min(max(f, 0), 1)) }
    func checkCancelled() throws { if isCancelled { throw YuzuError.cancelled } }
}

enum YuzuError: LocalizedError {
    case unreadable(String)
    case writeFailed(String)
    case missingTool(String)
    case tool(String)
    case unsupported(String)
    case needsApp(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unreadable(let s): return "Could not read \(s)."
        case .writeFailed(let s): return "Could not save \(s)."
        case .missingTool(let s):
            let hint = ToolLocator.installHint[s] ?? "brew install \(s)"
            let label = s == "soffice" ? "LibreOffice" : s
            return "\(label) is not installed. Install it with: \(hint)"
        case .tool(let s): return s
        case .unsupported(let s): return s
        case .needsApp(let s): return s
        case .cancelled: return "Cancelled."
        }
    }
}

/// Scratch space inside Yuzu's own cache folder.
enum Scratch {
    static var root: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.sreecharan.yuzu", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func dir(_ tag: String = "job") throws -> URL {
        let d = root.appendingPathComponent("tmp", isDirectory: true).appendingPathComponent("\(tag)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    /// Removes the whole scratch job folder that contains `url` (no-op for files outside scratch).
    static func cleanupJob(containing url: URL) {
        let tmp = root.appendingPathComponent("tmp", isDirectory: true).standardizedFileURL.path
        var u = url.standardizedFileURL
        while u.path.count > tmp.count {
            let parent = u.deletingLastPathComponent()
            if parent.path == tmp { cleanup(u); return }
            u = parent
        }
    }
}
