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

enum OptionAction: Sendable, Equatable {
    case convertImage(ImageFormat)
    case imageTool(ImageTool)
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
        guard let t = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return t.conforms(to: .image) && !t.conforms(to: .pdf)
    }

    /// Returns options for the wheel, or a message explaining why there are none.
    static func options(for kind: WheelKind, items: [URL]) -> (options: [WheelOption], message: String?) {
        switch kind {
        case .actions:
            guard !items.isEmpty else { return ([], "Drop to see actions") }
            let opts = FileAction.allCases.map { a in
                WheelOption(id: "action.\(a.rawValue)", title: a.title, symbol: a.symbol,
                            action: .fileAction(a), enabled: a != .float,
                            note: a == .float ? "Soon" : nil)
            }
            return (opts, nil)

        case .convert:
            guard !items.isEmpty else { return ([], "Reading file…") }
            guard items.allSatisfy(isImage) else {
                return ([], items.count > 1 ? "No shared formats" : "No formats yet")
            }
            let sources = Set(items.compactMap(ImageFormat.of))
            let opts = ImageFormat.allCases
                .filter { $0.isAvailable }
                .filter { !(sources.count == 1 && sources.contains($0)) }
                .prefix(Theme.maxPetals)
                .map { WheelOption(id: "convert.\($0.rawValue)", title: $0.title, symbol: nil, action: .convertImage($0)) }
            return (Array(opts), nil)

        case .tools:
            guard !items.isEmpty else { return ([], "Reading file…") }
            guard items.allSatisfy(isImage) else {
                return ([], items.count > 1 ? "No shared tools" : "No tools yet")
            }
            let opts = ImageTool.allCases.map {
                WheelOption(id: "tool.\($0.rawValue)", title: $0.title, symbol: $0.symbol, action: .imageTool($0))
            }
            return (opts, nil)
        }
    }
}
