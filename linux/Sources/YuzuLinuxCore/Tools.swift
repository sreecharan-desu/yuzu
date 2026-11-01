import Foundation

/// Finds command line engines on PATH. nothing is bundled, same as the mac app.
public struct Tools: Sendable {
    public var paths: [String: String]

    public init(paths: [String: String]) { self.paths = paths }

    public static let known = ["ffmpeg", "magick", "convert", "pandoc", "soffice", "libreoffice", "pdftoppm", "pdftotext", "zip", "unzip", "tar"]

    public static let installHint: [String: String] = [
        "ffmpeg": "sudo apt install ffmpeg",
        "magick": "sudo apt install imagemagick",
        "pandoc": "sudo apt install pandoc",
        "soffice": "sudo apt install libreoffice",
        "pdftoppm": "sudo apt install poppler-utils",
        "zip": "sudo apt install zip unzip",
    ]

    /// Looks every known tool up on PATH (plus /usr/bin and /usr/local/bin).
    public static func detect(env: [String: String] = ProcessInfo.processInfo.environment) -> Tools {
        let dirs = (env["PATH"] ?? "").split(separator: ":").map(String.init) + ["/usr/local/bin", "/usr/bin", "/bin"]
        var found: [String: String] = [:]
        for name in known {
            for d in dirs {
                let p = d + "/" + name
                if FileManager.default.isExecutableFile(atPath: p) { found[name] = p; break }
            }
        }
        return Tools(paths: found)
    }

    public func path(_ name: String) -> String? { paths[name] }

    /// ImageMagick 7 ships `magick`, 6 (debian, ubuntu) ships `convert`.
    public var imageMagick: String? { paths["magick"] ?? paths["convert"] }
    public var office: String? { paths["soffice"] ?? paths["libreoffice"] }
}
