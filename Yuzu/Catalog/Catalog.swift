import Foundation
import UniformTypeIdentifiers
import ImageIO

enum ImageFormat: String, CaseIterable, Sendable {
    case jpeg, png, heic, webp, pdf, tiff, avif, gif, bmp

    var title: String {
        switch self {
        case .jpeg: return "JPG"
        case .webp: return "WebP"
        default: return rawValue.uppercased()
        }
    }

    var ext: String { self == .jpeg ? "jpg" : rawValue }

    var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png: return .png
        case .heic: return .heic
        case .webp: return .webP
        case .pdf: return .pdf
        case .tiff: return .tiff
        case .avif: return UTType("public.avif") ?? .image
        case .gif: return .gif
        case .bmp: return .bmp
        }
    }

    var isLossy: Bool { [.jpeg, .heic, .webp, .avif].contains(self) }
    var supportsAlpha: Bool { ![.jpeg, .bmp].contains(self) }

    static func of(_ url: URL) -> ImageFormat? {
        guard let t = UTType(filenameExtension: url.pathExtension.lowercased()) else { return nil }
        return allCases.first { t == $0.utType || ($0 == .jpeg && t.conforms(to: .jpeg)) }
    }

    /// Formats ImageIO can write on this Mac, plus WebP through cwebp when ImageIO cannot.
    static let imageIOWritable: Set<String> = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])

    var isAvailable: Bool {
        switch self {
        case .pdf: return true
        case .webp: return Self.imageIOWritable.contains(utType.identifier) || ToolLocator.cwebp != nil
        default: return Self.imageIOWritable.contains(utType.identifier)
        }
    }
}

enum ImageTool: String, CaseIterable, Sendable {
    case compress, halfSize, rotate, flip, removeMetadata

    var title: String {
        switch self {
        case .compress: return "Compress"
        case .halfSize: return "Half Size"
        case .rotate: return "Rotate"
        case .flip: return "Flip"
        case .removeMetadata: return "Remove Meta"
        }
    }

    var symbol: String {
        switch self {
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .halfSize: return "arrow.down.left.and.arrow.up.right.square"
        case .rotate: return "rotate.right"
        case .flip: return "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .removeMetadata: return "tag.slash"
        }
    }

    var suffix: String {
        switch self {
        case .compress: return "Compressed"
        case .halfSize: return "Half Size"
        case .rotate: return "Rotated"
        case .flip: return "Flipped"
        case .removeMetadata: return "No Metadata"
        }
    }
}

enum FileAction: String, CaseIterable, Sendable {
    case airDrop, float, copy, move, copyPath, terminal

    var title: String {
        switch self {
        case .airDrop: return "AirDrop"
        case .float: return "Float"
        case .copy: return "Copy"
        case .move: return "Move"
        case .copyPath: return "Copy Path"
        case .terminal: return "Terminal"
        }
    }

    var symbol: String {
        switch self {
        case .airDrop: return "dot.radiowaves.left.and.right"
        case .float: return "paperclip"
        case .copy: return "doc.on.doc"
        case .move: return "folder"
        case .copyPath: return "link"
        case .terminal: return "terminal"
        }
    }
}

enum FileKind: String, Sendable {
    case image, video, audio, pdf, document, slides, spreadsheet, subtitle, archive, folder, other

    static let videoExts: Set<String> = ["mp4", "m4v", "mov", "mkv", "webm", "avi", "wmv", "flv", "mpg", "mpeg", "3gp", "ts", "mts"]
    static let audioExts: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "oga", "opus", "aiff", "aif", "wma", "caf", "alac"]
    static let documentExts: Set<String> = ["docx", "doc", "rtf", "rtfd", "html", "htm", "txt", "text", "md", "markdown", "odt", "pages", "epub", "textclipping", "webarchive"]
    static let slidesExts: Set<String> = ["ppt", "pptx", "key", "odp"]
    static let sheetExts: Set<String> = ["xlsx", "xls", "ods", "csv", "tsv", "numbers"]
    static let subtitleExts: Set<String> = ["srt", "vtt"]
    static let archiveExts: Set<String> = ["zip", "tar", "tgz", "gz", "tbz", "bz2", "txz", "xz"]

    static func of(_ url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]))
        if isDir?.isDirectory == true && isDir?.isPackage != true && ext != "rtfd" { return .folder }
        if ext == "pdf" { return .pdf }
        if videoExts.contains(ext) { return .video }
        if audioExts.contains(ext) { return .audio }
        if documentExts.contains(ext) { return .document }
        if slidesExts.contains(ext) { return .slides }
        if sheetExts.contains(ext) { return .spreadsheet }
        if subtitleExts.contains(ext) { return .subtitle }
        if archiveExts.contains(ext) { return .archive }
        if ext == "svg" { return .image }
        if Catalog.isImage(url) { return .image }
        return .other
    }
}

/// Non-image conversion targets.
enum Target: String, CaseIterable, Sendable {
    // media
    case mp4, mov, mkv, webm, avi, wmv, gif, mp3, m4a, wav, flac, ogg, opus, aiff, wma
    // documents and PDF
    case docx, pages, pptx, xlsx, jpgPages, pngPages, epub, txt, md, html, rtf, pdf, odt
    // slides and sheets
    case key, odp, ods, csv, tsv, numbers
    // subtitles and archives
    case srt, vtt, zip, tar, tgz, extract

    var title: String {
        switch self {
        case .jpgPages: return "JPG"
        case .pngPages: return "PNG"
        case .webm: return "WebM"
        case .opus: return "Opus"
        case .md: return "MD"
        case .pages: return "Pages"
        case .key: return "Keynote"
        case .numbers: return "Numbers"
        case .tgz: return "GZIP"
        case .extract: return "Extract"
        default: return rawValue.uppercased()
        }
    }

    var ext: String {
        switch self {
        case .jpgPages: return "jpg"
        case .pngPages: return "png"
        case .tgz: return "tar.gz"
        case .extract: return ""
        default: return rawValue
        }
    }

    var symbol: String? { self == .extract ? "arrow.up.bin" : nil }

    /// The iWork app that must save this format, if any.
    var iWorkApp: String? {
        switch self {
        case .pages: return "Pages"
        case .key: return "Keynote"
        case .numbers: return "Numbers"
        default: return nil
        }
    }

    /// Canonical target for a source extension, used to hide "convert to itself".
    static func same(as ext: String) -> Target? {
        switch ext {
        case "htm", "html": return .html
        case "markdown", "md": return .md
        case "text", "txt": return .txt
        case "aif", "aiff": return .aiff
        case "oga", "ogg": return .ogg
        case "m4v": return .mp4
        case "gz", "tgz": return .tgz
        default: return Target(rawValue: ext)
        }
    }
}

enum OptionAction: Sendable, Equatable {
    case convertImage(ImageFormat)
    case convertFile(Target)
    case imageTool(ImageTool)
    case tool(FileTool)
    case fileAction(FileAction)
}

struct WheelOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let symbol: String?
    let action: OptionAction
    var enabled: Bool = true
    var note: String? = nil
}

enum Catalog {
    static func isImage(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "svg" { return true }
        guard let t = UTType(filenameExtension: ext) else { return false }
        return t.conforms(to: .image) && !t.conforms(to: .pdf)
    }

    static func targets(for kind: FileKind, sourceExt: String) -> [Target] {
        let list: [Target]
        switch kind {
        case .video: list = [.mp4, .mov, .mkv, .webm, .avi, .wmv, .gif, .mp3, .m4a]
        case .audio: list = [.mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff, .wma]
        case .pdf: list = [.docx, .pages, .pptx, .xlsx, .jpgPages, .pngPages, .epub, .txt, .md]
        case .document: list = [.docx, .pdf, .pages, .md, .txt, .html, .epub, .rtf, .odt]
        case .slides: list = [.pdf, .pngPages, .jpgPages, .pptx, .key, .odp]
        case .spreadsheet: list = [.xlsx, .csv, .tsv, .ods, .pdf, .numbers]
        case .subtitle: list = [.srt, .vtt, .txt]
        case .archive: list = [.extract, .zip, .tar, .tgz]
        case .folder: list = [.zip, .tar, .tgz]
        default: list = []
        }
        var same = Target.same(as: sourceExt)
        if kind == .archive, ["tar.gz", "tgz", "gz"].contains(where: { sourceExt.hasSuffix($0) }) { same = .tgz }
        if kind == .slides, sourceExt == "ppt" { same = nil }
        return list.filter { $0 != same }
    }

    /// Tool notes for a target so the petal can say what it relies on.
    static func requirementNote(_ t: Target, kind: FileKind) -> String? {
        if let app = t.iWorkApp {
            return FileManager.default.fileExists(atPath: "/Applications/\(app).app") ? "via \(app)" : "Needs \(app)"
        }
        switch kind {
        case .video, .audio:
            if ToolLocator.ffmpeg == nil, ![.mov, .mp4, .m4a].contains(t) { return "Needs ffmpeg" }
        case .slides:
            if ToolLocator.soffice == nil { return "Needs LibreOffice" }
        case .spreadsheet:
            if ToolLocator.soffice == nil, !(t == .csv || t == .tsv) { return "Needs LibreOffice" }
        case .pdf:
            if ToolLocator.soffice == nil, [.pptx, .xlsx].contains(t) { return "Needs LibreOffice" }
        default: break
        }
        return nil
    }

    /// Returns options for the wheel, or a message explaining why there are none.
    static func options(for kind: WheelKind, items: [URL]) -> (options: [WheelOption], message: String?) {
        switch kind {
        case .actions:
            guard !items.isEmpty else { return ([], "Drop to see actions") }
            let opts = FileAction.allCases.map { a in
                WheelOption(id: "action.\(a.rawValue)", title: a.title, symbol: a.symbol,
                            action: .fileAction(a))
            }
            return (opts, nil)

        case .convert:
            guard !items.isEmpty else { return ([], "Reading file…") }
            let kinds = Set(items.map(FileKind.of))
            guard kinds.count == 1, let fileKind = kinds.first, fileKind != .other else {
                return ([], kinds.count > 1 ? "No shared formats" : "No formats yet")
            }
            if fileKind == .image {
                let sources = Set(items.compactMap(ImageFormat.of))
                let opts = ImageFormat.allCases
                    .filter { $0.isAvailable }
                    .filter { !(sources.count == 1 && sources.contains($0)) }
                    .prefix(Theme.maxPetals)
                    .map { WheelOption(id: "convert.\($0.rawValue)", title: $0.title, symbol: nil, action: .convertImage($0)) }
                return (Array(opts), nil)
            }
            let exts = Set(items.map { $0.pathExtension.lowercased() })
            let sourceExt = exts.count == 1 ? exts.first! : ""
            let opts = targets(for: fileKind, sourceExt: sourceExt).prefix(Theme.maxPetals).map { t in
                WheelOption(id: "file.\(t.rawValue)", title: t.title, symbol: t.symbol,
                            action: .convertFile(t), note: requirementNote(t, kind: fileKind))
            }
            return (Array(opts), opts.isEmpty ? "No formats yet" : nil)

        case .tools:
            guard !items.isEmpty else { return ([], "Reading file…") }
            let kinds = Set(items.map(FileKind.of))
            guard kinds.count == 1, let fileKind = kinds.first else { return ([], "No shared tools") }
            let opts = toolOptions(for: fileKind, count: items.count)
            return (opts, opts.isEmpty ? "No tools for this type" : nil)
        }
    }
}
