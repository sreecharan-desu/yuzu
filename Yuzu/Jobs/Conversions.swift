import Foundation

/// Routes a non-image target to the engine for the source's kind.
enum Conversions {
    static func perform(_ t: Target, source: URL, ctx: JobContext) throws -> URL {
        let kind = FileKind.of(source)
        switch kind {
        case .video, .audio: return try MediaEngine.convert(source, to: t, ctx: ctx)
        default: throw YuzuError.unsupported("This conversion is not available yet.")
        }
    }
}
