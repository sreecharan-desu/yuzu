import Foundation

public struct Command: Equatable, Sendable {
    public var tool: String
    public var args: [String]
    public var cwd: String?
    public init(_ tool: String, _ args: [String], cwd: String? = nil) { self.tool = tool; self.args = args; self.cwd = cwd }
}

/// What it takes to make one output.
public enum Step: Equatable, Sendable {
    /// conversions done in swift (subtitles, markdown to html, csv and tsv).
    case native(Target)
    /// external commands run in order. `produced` is where the last one writes.
    case run([Command], produced: URL)
    /// soffice writes into a folder with its own name; the file is moved into place after.
    case office(Command, produced: URL)
    case missing(String)
    case unsupported(String)
}

public enum PlanError: Error, Equatable, CustomStringConvertible {
    case unsupported(String), missingTool(String), failed(String), unreadable(String)
    public var description: String {
        switch self {
        case .unsupported(let s), .failed(let s): return s
        case .missingTool(let t): return "needs \(t)" + (Tools.installHint[t].map { " (\($0))" } ?? "")
        case .unreadable(let s): return "could not read \(s)"
        }
    }
}

public enum Planner {
    /// Plans converting `src` to `t`, writing `dest`. `scratch` is a private temp folder for tools that pick their own names.
    public static func plan(_ src: URL, to t: Target, dest: URL, scratch: URL, tools: Tools) -> Step {
        let kind = Kind.of(src)
        guard Catalog.targets(for: kind, sourceExt: src.pathExtension.lowercased()).contains(t) else {
            return .unsupported("\(src.lastPathComponent) can't be converted to \(t.cliName)")
        }
        let s = src.path, d = dest.path
        switch kind {
        case .image:
            guard let im = tools.imageMagick else { return .missing("magick") }
            // flatten onto white for formats without alpha, first frame only for stills from a gif
            var args = [s + (src.pathExtension.lowercased() == "gif" && t != .gif ? "[0]" : "")]
            if t == .jpg || t == .bmp { args += ["-background", "white", "-alpha", "remove", "-alpha", "off"] }
            if t == .jpg || t == .webp || t == .avif { args += ["-quality", "88"] }
            return .run([Command(im, args + [d])], produced: dest)

        case .video, .audio:
            guard let ff = tools.path("ffmpeg") else { return .missing("ffmpeg") }
            let base = ["-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-i", s]
            let args: [String]
            switch t {
            case .gif: args = ["-vf", "fps=12,scale='min(720,iw)':-2:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse", "-loop", "0"]
            case .mp3: args = ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]
            case .m4a: args = ["-vn", "-c:a", "aac", "-b:a", "192k"]
            case .wav: args = ["-vn", "-c:a", "pcm_s16le"]
            case .flac: args = ["-vn", "-c:a", "flac"]
            case .ogg: args = ["-vn", "-c:a", "libvorbis", "-q:a", "5"]
            case .opus: args = ["-vn", "-c:a", "libopus", "-b:a", "128k"]
            case .aiff: args = ["-vn", "-c:a", "pcm_s16be"]
            case .wma: args = ["-vn", "-c:a", "wmav2", "-b:a", "192k"]
            case .webm: args = ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-c:a", "libopus"]
            case .mp4, .mov: args = ["-c:v", "libx264", "-crf", "22", "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", "aac", "-movflags", "+faststart"]
            case .mkv: args = ["-c:v", "libx264", "-crf", "22", "-c:a", "aac"]
            case .avi: args = ["-c:v", "mpeg4", "-q:v", "4", "-c:a", "libmp3lame"]
            case .wmv: args = ["-c:v", "wmv2", "-b:v", "2M", "-c:a", "wmav2"]
            default: return .unsupported("\(t.cliName) is not a media format")
            }
            return .run([Command(ff, base + args + [d])], produced: dest)

        case .pdf:
            switch t {
            case .txt:
                guard let p = tools.path("pdftotext") else { return .missing("pdftotext") }
                return .run([Command(p, ["-layout", s, d])], produced: dest)
            case .html:
                guard let p = tools.path("pdftotext") else { return .missing("pdftotext") }
                return .run([Command(p, ["-htmlmeta", s, d])], produced: dest)
            case .pngPages, .jpgPages:
                guard let p = tools.path("pdftoppm") else { return .missing("pdftoppm") }
                // dest is a folder here; pages land as "page-1.png" and so on
                let fmt = t == .pngPages ? "-png" : "-jpeg"
                return .run([Command(p, [fmt, "-r", "150", s, dest.appendingPathComponent("page").path])], produced: dest)
            case .docx:
                guard let o = tools.office else { return .missing("soffice") }
                return .office(officeCommand(o, s, filter: "docx:\"MS Word 2007 XML\"", infilter: "writer_pdf_import", scratch: scratch),
                               produced: scratch.appendingPathComponent(src.deletingPathExtension().lastPathComponent + ".docx"))
            default: return .unsupported("\(t.cliName) from pdf is not available on linux yet")
            }

        case .document:
            let ext = src.pathExtension.lowercased()
            if t == .html, ["md", "markdown"].contains(ext) { return .native(.html) }
            if t == .txt, ["md", "markdown", "txt", "text"].contains(ext) { return .native(.txt) }
            if t == .pdf || ext == "doc" || t == .odt && ext == "docx" {
                guard let o = tools.office else { return .missing("soffice") }
                return .office(officeCommand(o, s, filter: t.ext, scratch: scratch),
                               produced: scratch.appendingPathComponent(src.deletingPathExtension().lastPathComponent + "." + t.ext))
            }
            guard let p = tools.path("pandoc") else { return .missing("pandoc") }
            let to: String
            switch t {
            case .docx: to = "docx"
            case .md: to = "gfm"
            case .txt: to = "plain"
            case .html: to = "html"
            case .epub: to = "epub"
            case .rtf: to = "rtf"
            case .odt: to = "odt"
            default: return .unsupported("\(t.cliName) is not a document format")
            }
            var args = [s, "-t", to, "-o", d]
            if t == .html || t == .rtf { args.insert("-s", at: 1) }
            if t == .epub { args += ["--metadata", "title=\(src.deletingPathExtension().lastPathComponent)"] }
            return .run([Command(p, args)], produced: dest)

        case .slides, .spreadsheet:
            let ext = src.pathExtension.lowercased()
            if kind == .spreadsheet, ["csv", "tsv"].contains(ext), [.csv, .tsv].contains(t) { return .native(t) }
            guard let o = tools.office else { return .missing("soffice") }
            var filter = t.ext
            if t == .csv { filter = "csv:\"Text - txt - csv (StarCalc)\":44,34,76" }
            if t == .tsv { filter = "csv:\"Text - txt - csv (StarCalc)\":9,34,76" }
            let producedExt = t == .tsv ? "csv" : t.ext
            return .office(officeCommand(o, s, filter: filter, scratch: scratch),
                           produced: scratch.appendingPathComponent(src.deletingPathExtension().lastPathComponent + "." + producedExt))

        case .subtitle:
            return .native(t)

        case .archive:
            let ext = src.lastPathComponent.lowercased()
            if t == .extract {
                if ext.hasSuffix(".zip") {
                    guard let u = tools.path("unzip") else { return .missing("unzip") }
                    return .run([Command(u, ["-q", s, "-d", d])], produced: dest)
                }
                guard let tar = tools.path("tar") else { return .missing("tar") }
                return .run([Command("/bin/mkdir", ["-p", d]), Command(tar, ["-xf", s, "-C", d])], produced: dest)
            }
            // repack: extract to scratch, then pack that folder
            let inner = scratch.appendingPathComponent("x", isDirectory: true)
            var cmds: [Command] = [Command("/bin/mkdir", ["-p", inner.path])]
            if ext.hasSuffix(".zip") {
                guard let u = tools.path("unzip") else { return .missing("unzip") }
                cmds.append(Command(u, ["-q", s, "-d", inner.path]))
            } else {
                guard let tar = tools.path("tar") else { return .missing("tar") }
                cmds.append(Command(tar, ["-xf", s, "-C", inner.path]))
            }
            guard let pack = packCommands(folder: inner, contentsOnly: true, to: t, dest: dest, tools: tools) else { return .missing(t == .zip ? "zip" : "tar") }
            return .run(cmds + pack, produced: dest)

        case .folder:
            guard let pack = packCommands(folder: src, contentsOnly: false, to: t, dest: dest, tools: tools) else { return .missing(t == .zip ? "zip" : "tar") }
            return .run(pack, produced: dest)

        case .other:
            return .unsupported("yuzu doesn't know this kind of file")
        }
    }

    static func officeCommand(_ o: String, _ s: String, filter: String, infilter: String? = nil, scratch: URL) -> Command {
        var args = ["--headless"]
        if let i = infilter { args.append("--infilter=\(i)") }
        // a private profile so a running libreoffice window doesn't swallow the job
        args += ["-env:UserInstallation=file://\(scratch.path)/profile", "--convert-to", filter, "--outdir", scratch.path, s]
        return Command(o, args)
    }

    static func packCommands(folder: URL, contentsOnly: Bool, to t: Target, dest: URL, tools: Tools) -> [Command]? {
        let cwd = contentsOnly ? folder.path : folder.deletingLastPathComponent().path
        let item = contentsOnly ? "." : folder.lastPathComponent
        switch t {
        case .zip:
            guard let z = tools.path("zip") else { return nil }
            return [Command(z, ["-qr", "-X", dest.path, item, "-x", "*.DS_Store"], cwd: cwd)]
        case .tar, .tgz:
            guard let tar = tools.path("tar") else { return nil }
            return [Command(tar, [t == .tgz ? "-czf" : "-cf", dest.path, item], cwd: cwd)]
        default: return nil
        }
    }

    /// Where the output for `src` goes: next to it, never overwriting (shared OutputNamer).
    public static func destination(for src: URL, to t: Target) -> URL {
        switch t {
        case .extract: return OutputNamer.folder(for: src, suffix: "contents")
        case .pngPages, .jpgPages: return OutputNamer.folder(for: src, suffix: "pages")
        default: return OutputNamer.destination(for: src, ext: t.ext)
        }
    }
}
