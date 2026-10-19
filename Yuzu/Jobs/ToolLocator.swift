import Foundation

/// Finds command-line engines already installed on this Mac. Nothing is bundled.
enum ToolLocator {
    static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
                              "/Applications/LibreOffice.app/Contents/MacOS"]

    static func path(for name: String) -> String? {
        for dir in searchPaths {
            let p = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    static var cwebp: String? { path(for: "cwebp") }
    static var ffmpeg: String? { path(for: "ffmpeg") }
    static var exiftool: String? { path(for: "exiftool") }
    static var soffice: String? { path(for: "soffice") }

    struct Status: Identifiable { let id: String; let path: String?; let use: String }

    static var all: [Status] {
        [Status(id: "ffmpeg", path: ffmpeg, use: "Video and audio"),
         Status(id: "cwebp", path: cwebp, use: "WebP export"),
         Status(id: "exiftool", path: exiftool, use: "Metadata"),
         Status(id: "soffice", path: soffice, use: "Office documents")]
    }

    /// Runs a tool and waits. Throws with stderr text on failure.
    static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw YuzuError.tool("\((tool as NSString).lastPathComponent) failed: \(msg.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))")
        }
    }
}

enum YuzuError: LocalizedError {
    case unreadable(String)
    case writeFailed(String)
    case missingTool(String)
    case tool(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let s): return "Could not read \(s)."
        case .writeFailed(let s): return "Could not save \(s)."
        case .missingTool(let s): return "\(s) is not installed. Install it with Homebrew: brew install \(s)"
        case .tool(let s): return s
        case .unsupported(let s): return s
        }
    }
}
