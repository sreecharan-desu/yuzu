import Foundation

/// Routes a non-image target to the engine for the source's kind.
enum Conversions {
    static func perform(_ t: Target, source: URL, ctx: JobContext) throws -> URL {
        switch FileKind.of(source) {
        case .video, .audio: return try MediaEngine.convert(source, to: t, ctx: ctx)
        case .pdf: return try PDFEngine.convert(source, to: t, ctx: ctx)
        case .document: return try DocEngine.convert(source, to: t, ctx: ctx)
        case .slides: return try SheetEngine.slides(source, to: t, ctx: ctx)
        case .spreadsheet: return try SheetEngine.convert(source, to: t, ctx: ctx)
        case .subtitle: return try SubtitleEngine.convert(source, to: t, ctx: ctx)
        case .archive, .folder: return try ArchiveEngine.convert(source, to: t, ctx: ctx)
        default: throw YuzuError.unsupported("Yuzu can't convert this kind of file yet.")
        }
    }
}
