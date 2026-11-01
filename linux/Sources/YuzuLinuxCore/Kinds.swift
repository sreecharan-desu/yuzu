import Foundation

/// File kinds, matching FileKind in the mac app (Yuzu/Catalog/Catalog.swift) by extension.
public enum Kind: String, Sendable, CaseIterable {
    case image, video, audio, pdf, document, slides, spreadsheet, subtitle, archive, folder, other

    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "avif", "tif", "tiff", "gif", "bmp", "svg"]
    static let videoExts: Set<String> = ["mp4", "m4v", "mov", "mkv", "webm", "avi", "wmv", "flv", "mpg", "mpeg", "3gp", "ts", "mts"]
    static let audioExts: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "oga", "opus", "aiff", "aif", "wma", "caf", "alac"]
    static let documentExts: Set<String> = ["docx", "doc", "rtf", "html", "htm", "txt", "text", "md", "markdown", "odt", "epub"]
    static let slidesExts: Set<String> = ["ppt", "pptx", "odp"]
    static let sheetExts: Set<String> = ["xlsx", "xls", "ods", "csv", "tsv"]
    static let subtitleExts: Set<String> = ["srt", "vtt"]
    static let archiveExts: Set<String> = ["zip", "tar", "tgz", "gz", "tbz", "bz2", "txz", "xz"]

    public static func of(_ url: URL) -> Kind {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { return .folder }
        return of(ext: url.pathExtension.lowercased())
    }

    public static func of(ext: String) -> Kind {
        if ext == "pdf" { return .pdf }
        if imageExts.contains(ext) { return .image }
        if videoExts.contains(ext) { return .video }
        if audioExts.contains(ext) { return .audio }
        if documentExts.contains(ext) { return .document }
        if slidesExts.contains(ext) { return .slides }
        if sheetExts.contains(ext) { return .spreadsheet }
        if subtitleExts.contains(ext) { return .subtitle }
        if archiveExts.contains(ext) { return .archive }
        return .other
    }
}

/// Conversion targets on linux. iWork formats (pages, key, numbers) are mac only.
public enum Target: String, Sendable, CaseIterable {
    // images
    case jpg, png, webp, avif, tiff, gif, bmp
    // media
    case mp4, mov, mkv, webm, avi, wmv, mp3, m4a, wav, flac, ogg, opus, aiff, wma
    // documents, slides, sheets
    case docx, pdf, md, txt, html, epub, rtf, odt, pptx, odp, xlsx, ods, csv, tsv, pngPages, jpgPages
    // subtitles and archives
    case srt, vtt, zip, tar, tgz, extract

    public var ext: String {
        switch self {
        case .pngPages: return "png"
        case .jpgPages: return "jpg"
        case .tgz: return "tar.gz"
        case .extract: return ""
        default: return rawValue
        }
    }

    /// Name used on the command line, e.g. `--to png-pages`.
    public var cliName: String {
        switch self {
        case .pngPages: return "png-pages"
        case .jpgPages: return "jpg-pages"
        default: return rawValue
        }
    }

    public init?(cliName: String) {
        let n = cliName.lowercased()
        if let t = Target.allCases.first(where: { $0.cliName == n }) { self = t; return }
        switch n {
        case "jpeg": self = .jpg
        case "tif": self = .tiff
        case "markdown": self = .md
        case "htm": self = .html
        case "tar.gz", "gz": self = .tgz
        case "aif": self = .aiff
        default: return nil
        }
    }

    /// Canonical target for a source extension, used to hide "convert to itself".
    static func same(as ext: String) -> Target? {
        switch ext {
        case "jpeg", "jpg": return .jpg
        case "tif", "tiff": return .tiff
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

public enum Catalog {
    /// Targets offered for a kind, in the same order the mac convert ring uses where they overlap.
    public static func targets(for kind: Kind, sourceExt: String) -> [Target] {
        let list: [Target]
        switch kind {
        case .image: list = [.jpg, .png, .webp, .avif, .tiff, .gif, .bmp, .pdf]
        case .video: list = [.mp4, .mov, .mkv, .webm, .avi, .wmv, .gif, .mp3, .m4a]
        case .audio: list = [.mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff, .wma]
        case .pdf: list = [.docx, .pngPages, .jpgPages, .txt, .html]
        case .document: list = [.docx, .pdf, .md, .txt, .html, .epub, .rtf, .odt]
        case .slides: list = [.pdf, .pptx, .odp]
        case .spreadsheet: list = [.xlsx, .csv, .tsv, .ods, .pdf]
        case .subtitle: list = [.srt, .vtt, .txt]
        case .archive: list = [.extract, .zip, .tar, .tgz]
        case .folder: list = [.zip, .tar, .tgz]
        case .other: list = []
        }
        var same = Target.same(as: sourceExt)
        if kind == .archive, ["tar.gz", "tgz", "gz"].contains(where: { sourceExt.hasSuffix($0) }) { same = .tgz }
        if kind == .slides, sourceExt == "ppt" { same = nil }
        if kind == .spreadsheet, sourceExt == "xls" { same = nil }
        return list.filter { $0 != same }
    }

    /// Targets shared by every file in a batch.
    public static func targets(for urls: [URL]) -> [Target] {
        guard let first = urls.first else { return [] }
        let kinds = Set(urls.map(Kind.of))
        guard kinds.count == 1 else { return [] }
        var common = targets(for: Kind.of(first), sourceExt: first.pathExtension.lowercased())
        for u in urls.dropFirst() {
            let t = Set(targets(for: Kind.of(u), sourceExt: u.pathExtension.lowercased()))
            common = common.filter(t.contains)
        }
        return common
    }
}
