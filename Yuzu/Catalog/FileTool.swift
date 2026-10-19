import Foundation

/// Editing tools on the tools wheel beyond the one-shot image tools.
enum FileTool: String, CaseIterable, Sendable {
    // images
    case crop, editPhoto, annotate, redact, addBackground, resize, metadata, readQR, makePDF
    // video and audio
    case trim, cropVideo, speed, split, mute, compressVideo, join, bleep, normalize, channels, compressAudio
    // PDF
    case compressPDF, merge, splitPDF, organize

    var title: String {
        switch self {
        case .crop, .cropVideo: return "Crop"
        case .editPhoto: return "Edit Photo"
        case .annotate: return "Annotate"
        case .redact: return "Redact"
        case .addBackground: return "Add BG"
        case .resize: return "Resize"
        case .metadata: return "Metadata"
        case .readQR: return "Read QR"
        case .makePDF: return "Make PDF"
        case .trim: return "Trim"
        case .speed: return "Speed"
        case .split, .splitPDF: return "Split"
        case .mute: return "Mute"
        case .compressVideo, .compressAudio, .compressPDF: return "Compress"
        case .join: return "Join"
        case .bleep: return "Bleep"
        case .normalize: return "Normalize"
        case .channels: return "Channels"
        case .merge: return "Merge"
        case .organize: return "Organize"
        }
    }

    var symbol: String {
        switch self {
        case .crop, .cropVideo: return "crop"
        case .editPhoto: return "slider.horizontal.3"
        case .annotate: return "pencil.tip.crop.circle"
        case .redact: return "eye.slash"
        case .addBackground: return "person.crop.rectangle.stack"
        case .resize: return "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left"
        case .metadata: return "info.circle"
        case .readQR: return "qrcode.viewfinder"
        case .makePDF: return "doc.richtext"
        case .trim: return "timeline.selection"
        case .speed: return "gauge.with.dots.needle.67percent"
        case .split, .splitPDF: return "scissors"
        case .mute: return "speaker.slash"
        case .compressVideo, .compressAudio, .compressPDF: return "arrow.down.right.and.arrow.up.left"
        case .join: return "link"
        case .bleep: return "waveform.badge.exclamationmark"
        case .normalize: return "speaker.wave.2"
        case .channels: return "headphones"
        case .merge: return "doc.on.doc"
        case .organize: return "square.grid.2x2"
        }
    }

    /// Output name suffix ("photo Cropped.jpg").
    var suffix: String {
        switch self {
        case .crop, .cropVideo: return "Cropped"
        case .editPhoto: return "Edited"
        case .annotate: return "Annotated"
        case .redact: return "Redacted"
        case .addBackground: return "Background"
        case .resize: return "Resized"
        case .metadata: return "Metadata"
        case .readQR: return "QR"
        case .makePDF: return "Images"
        case .trim: return "Trimmed"
        case .speed: return "Speed"
        case .split, .splitPDF: return "Parts"
        case .mute: return "Muted"
        case .compressVideo, .compressAudio, .compressPDF: return "Compressed"
        case .join: return "Joined"
        case .bleep: return "Bleeped"
        case .normalize: return "Normalized"
        case .channels: return "Channels"
        case .merge: return "Merged"
        case .organize: return "Organized"
        }
    }

    /// Tools that open a panel for input; the rest run right away.
    var needsPanel: Bool {
        switch self {
        case .mute, .compressVideo, .join, .normalize, .compressAudio, .compressPDF, .merge, .makePDF, .readQR: return false
        default: return true
        }
    }

    /// Tools that combine several files into one output.
    var combinesFiles: Bool { [.join, .merge, .makePDF].contains(self) }

    var needsFFmpeg: Bool {
        [.trim, .cropVideo, .speed, .split, .mute, .compressVideo, .join, .bleep, .normalize, .channels, .compressAudio].contains(self)
    }
}

extension Catalog {
    static func toolOptions(for kind: FileKind, count: Int) -> [WheelOption] {
        func t(_ x: FileTool) -> WheelOption {
            WheelOption(id: "ftool.\(x.rawValue)", title: x.title, symbol: x.symbol, action: .tool(x),
                        note: x.needsFFmpeg && ToolLocator.ffmpeg == nil ? "Needs ffmpeg" : nil)
        }
        func i(_ x: ImageTool) -> WheelOption {
            WheelOption(id: "tool.\(x.rawValue)", title: x.title, symbol: x.symbol, action: .imageTool(x))
        }
        switch kind {
        case .image:
            if count > 1 {
                return [i(.compress), t(.resize), t(.crop), t(.editPhoto), t(.addBackground), t(.makePDF),
                        i(.rotate), i(.flip), i(.removeMetadata), t(.readQR)]
            }
            return [i(.compress), t(.crop), t(.editPhoto), t(.annotate), t(.redact), t(.addBackground),
                    t(.resize), t(.metadata), t(.readQR), i(.rotate)]
        case .video:
            var list = [t(.compressVideo), t(.trim), t(.cropVideo), t(.speed), t(.split), t(.mute), t(.bleep), t(.normalize), t(.metadata)]
            if count > 1 { list.insert(t(.join), at: 1) }
            return list
        case .audio:
            var list = [t(.compressAudio), t(.trim), t(.speed), t(.split), t(.bleep), t(.normalize), t(.channels), t(.metadata)]
            if count > 1 { list.insert(t(.join), at: 1) }
            return list
        case .pdf:
            var list = [t(.compressPDF), t(.splitPDF), t(.organize), t(.metadata)]
            if count > 1 { list.insert(t(.merge), at: 1) }
            return list
        default:
            return []
        }
    }
}
