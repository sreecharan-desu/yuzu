import Foundation
import AppKit

/// LibreOffice (headless, private profile) and Pages/Keynote/Numbers (Apple Events, export only).
enum OfficeEngine {
    private static let lock = NSLock()

    /// Yuzu's own LibreOffice profile so it never touches or locks Sreecharan's normal LibreOffice settings.
    static var profile: URL { Scratch.root.appendingPathComponent("libreoffice-profile", isDirectory: true) }

    /// Runs `soffice --convert-to` into a scratch folder and returns the produced file (caller delivers it).
    static func soffice(_ src: URL, to convertTo: String, ext: String, infilter: String? = nil, ctx: JobContext) throws -> URL {
        let bin = try ToolLocator.require("soffice")
        let dir = try Scratch.dir("office")
        // LibreOffice names output after the input; copy to a simple name so odd characters never trip it.
        let input = dir.appendingPathComponent("in").appendingPathExtension(src.pathExtension.isEmpty ? "dat" : src.pathExtension)
        try FileManager.default.copyItem(at: src, to: input)
        var args = ["-env:UserInstallation=\(profile.absoluteString)", "--headless", "--invisible", "--norestore",
                    "--nolockcheck", "--nodefault", "--nologo"]
        if let infilter { args.append("--infilter=\(infilter)") }
        args += ["--convert-to", convertTo, "--outdir", dir.appendingPathComponent("out").path, input.path]
        ctx.report(0.08)
        lock.lock()
        defer { lock.unlock() }
        let r = try ToolLocator.run(bin, args, ctx: ctx, timeout: 240, check: false)
        let outDir = dir.appendingPathComponent("out")
        let produced = (try? FileManager.default.contentsOfDirectory(at: outDir, includingPropertiesForKeys: nil)) ?? []
        guard let file = produced.first(where: { $0.pathExtension.lowercased() == ext.lowercased() }) else {
            let why = (r.stderr + r.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
            throw YuzuError.tool("LibreOffice could not convert \(src.lastPathComponent)\(why.isEmpty ? "." : ": \(why.suffix(160))")")
        }
        ctx.report(0.9)
        return file
    }

    static func sofficeDeliver(_ src: URL, to convertTo: String, ext: String, infilter: String? = nil, ctx: JobContext) throws -> URL {
        let file = try soffice(src, to: convertTo, ext: ext, infilter: infilter, ctx: ctx)
        defer { Scratch.cleanupJob(containing: file) }
        return try OutputNamer.deliver(file, for: src, ext: ext)
    }

    // MARK: iWork

    /// Opens `input` in Pages, Keynote or Numbers and saves it as that app's native document.
    /// Uses Apple Events to that app only; macOS asks once for Automation permission.
    static func iWorkSave(_ input: URL, app: String, dest: URL, ctx: JobContext) throws {
        guard FileManager.default.fileExists(atPath: "/Applications/\(app).app") else {
            throw YuzuError.needsApp("\(app) is not installed. Get it free from the App Store.")
        }
        try ctx.checkCancelled()
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        let source = """
        set inFile to POSIX file "\(esc(input.path))"
        set outFile to POSIX file "\(esc(dest.path))"
        tell application "\(app)"
            set theDoc to open inFile
            save theDoc in outFile
            close theDoc saving no
        end tell
        """
        ctx.report(0.3)
        var failure: String?
        var code = 0
        DispatchQueue.main.sync {
            var err: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&err)
            if let err {
                code = (err[NSAppleScript.errorNumber] as? Int) ?? 0
                failure = err[NSAppleScript.errorMessage] as? String ?? "\(app) reported an error."
            }
        }
        if code == -1743 {
            throw YuzuError.needsApp("Allow Yuzu to control \(app): System Settings > Privacy & Security > Automation > Yuzu > \(app).")
        }
        if let failure { throw YuzuError.tool("\(app): \(failure)") }
        guard FileManager.default.fileExists(atPath: dest.path) else { throw YuzuError.writeFailed(dest.lastPathComponent) }
        ctx.report(1)
    }

    /// Converts `src` to an iWork document, first making an intermediate file the app can open if needed.
    static func toIWork(_ src: URL, target: Target, ctx: JobContext,
                        intermediate: ((URL) throws -> URL)? = nil) throws -> URL {
        guard let app = target.iWorkApp else { throw YuzuError.unsupported("Not an iWork format.") }
        let dest = OutputNamer.destination(for: src, ext: target.ext)
        var input = src
        if let intermediate { input = try intermediate(src) }
        defer { if input != src { Scratch.cleanupJob(containing: input) } }
        try iWorkSave(input, app: app, dest: dest, ctx: ctx)
        return dest
    }
}
