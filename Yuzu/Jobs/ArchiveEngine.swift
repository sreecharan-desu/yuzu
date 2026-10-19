import Foundation

/// Zip, tar and tar.gz using the tools built into macOS (ditto, tar). No AppleDouble files.
enum ArchiveEngine {
    static let env = ["COPYFILE_DISABLE": "1"]

    static func convert(_ src: URL, to t: Target, ctx: JobContext) throws -> URL {
        let kind = FileKind.of(src)
        if t == .extract { return try extract(src, ctx: ctx) }
        if kind == .archive {
            // Repack: extract into scratch, then archive the extracted top level.
            let dir = try Scratch.dir("repack")
            defer { Scratch.cleanup(dir) }
            try unpack(src, into: dir, ctx: ctx)
            let items = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "__MACOSX" }
            let dest = OutputNamer.destination(for: baseURL(src), ext: t.ext)
            try pack(items.map(\.lastPathComponent), in: dir, to: dest, format: t, ctx: ctx)
            return dest
        }
        let dest = OutputNamer.destination(for: src, ext: t.ext)
        if t == .zip {
            ctx.report(0.1)
            try ToolLocator.run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--noacl", "--keepParent", src.path, dest.path], ctx: ctx, env: env)
        } else {
            try pack([src.lastPathComponent], in: src.deletingLastPathComponent(), to: dest, format: t, ctx: ctx)
        }
        return dest
    }

    /// "photos.tar.gz" behaves as "photos" for naming.
    private static func baseURL(_ src: URL) -> URL {
        let name = src.lastPathComponent.lowercased()
        return name.hasSuffix(".tar.gz") || name.hasSuffix(".tar.bz2") || name.hasSuffix(".tar.xz") ? src.deletingPathExtension() : src
    }

    private static func pack(_ names: [String], in dir: URL, to dest: URL, format: Target, ctx: JobContext) throws {
        ctx.report(0.1)
        switch format {
        case .zip:
            try ToolLocator.run("/usr/bin/zip", ["-qry", dest.path] + names + ["-x", "*.DS_Store"], ctx: ctx, env: env, cwd: dir)
        case .tar:
            try ToolLocator.run("/usr/bin/tar", ["--no-mac-metadata", "-cf", dest.path, "-C", dir.path] + names, ctx: ctx, env: env)
        case .tgz:
            try ToolLocator.run("/usr/bin/tar", ["--no-mac-metadata", "-czf", dest.path, "-C", dir.path] + names, ctx: ctx, env: env)
        default:
            throw YuzuError.unsupported("\(format.title) is not an archive format.")
        }
    }

    private static func unpack(_ src: URL, into dir: URL, ctx: JobContext) throws {
        if src.pathExtension.lowercased() == "zip" {
            try ToolLocator.run("/usr/bin/ditto", ["-x", "-k", src.path, dir.path], ctx: ctx)
        } else {
            try ToolLocator.run("/usr/bin/tar", ["-xf", src.path, "-C", dir.path], ctx: ctx)
        }
    }

    /// Extracts next to the archive. A single top-level item lands directly; otherwise a folder named after the archive.
    static func extract(_ src: URL, ctx: JobContext) throws -> URL {
        let dir = try Scratch.dir("extract")
        defer { Scratch.cleanup(dir) }
        ctx.report(0.1)
        try unpack(src, into: dir, ctx: ctx)
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != "__MACOSX" && $0.lastPathComponent != ".DS_Store" }
        guard !items.isEmpty else { throw YuzuError.tool("The archive is empty.") }
        let parent = src.deletingLastPathComponent()
        if items.count == 1 {
            let item = items[0]
            var dest = parent.appendingPathComponent(item.lastPathComponent)
            var n = 2
            let stem = item.deletingPathExtension().lastPathComponent, ext = item.pathExtension
            while fm.fileExists(atPath: dest.path) {
                dest = parent.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"); n += 1
            }
            try fm.moveItem(at: item, to: dest)
            return dest
        }
        var dest = parent.appendingPathComponent(baseURL(src).deletingPathExtension().lastPathComponent, isDirectory: true)
        var n = 2
        let stem = dest.lastPathComponent
        while fm.fileExists(atPath: dest.path) { dest = parent.appendingPathComponent("\(stem) \(n)", isDirectory: true); n += 1 }
        try fm.createDirectory(at: dest, withIntermediateDirectories: false)
        for item in items { try fm.moveItem(at: item, to: dest.appendingPathComponent(item.lastPathComponent)) }
        return dest
    }
}
