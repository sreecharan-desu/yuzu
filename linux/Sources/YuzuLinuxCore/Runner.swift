import Foundation

/// Runs one conversion end to end and returns where the result was saved.
public struct Runner: Sendable {
    public var tools: Tools
    public init(tools: Tools = .detect()) { self.tools = tools }

    public func convert(_ src: URL, to t: Target) throws -> URL {
        guard FileManager.default.isReadableFile(atPath: src.path) else { throw PlanError.unreadable(src.lastPathComponent) }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("yuzu-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let dest = Planner.destination(for: src, to: t)

        switch Planner.plan(src, to: t, dest: dest, scratch: scratch, tools: tools) {
        case .unsupported(let why): throw PlanError.unsupported(why)
        case .missing(let tool): throw PlanError.missingTool(tool)
        case .native(let target):
            try Native.convert(src, to: target, dest: dest)
            return dest
        case .run(let cmds, let produced):
            if t == .pngPages || t == .jpgPages { try FileManager.default.createDirectory(at: produced, withIntermediateDirectories: true) }
            do { for c in cmds { try run(c) } } catch { try? FileManager.default.removeItem(at: produced); throw error }
            guard FileManager.default.fileExists(atPath: produced.path) else { throw PlanError.failed("no output was written") }
            return produced
        case .office(let cmd, let produced):
            try run(cmd)
            guard FileManager.default.fileExists(atPath: produced.path) else { throw PlanError.failed("libreoffice wrote no output") }
            try FileManager.default.moveItem(at: produced, to: dest)
            return dest
        }
    }

    func run(_ c: Command) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: c.tool)
        p.arguments = c.args
        if let cwd = c.cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        try p.run()
        let data = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(decoding: data, as: UTF8.self).split(separator: "\n").suffix(3).joined(separator: " ")
            throw PlanError.failed("\((c.tool as NSString).lastPathComponent) failed: \(msg)")
        }
    }
}

/// Conversions done in swift without external tools.
public enum Native {
    public static func convert(_ src: URL, to t: Target, dest: URL) throws {
        let text = try readText(src)
        let out: String
        switch Kind.of(src) {
        case .subtitle:
            let cues = Subtitles.parse(text)
            guard !cues.isEmpty, let s = Subtitles.render(cues, as: t) else { throw PlanError.unreadable(src.lastPathComponent) }
            out = s
        case .document where t == .html:
            out = html(title: src.deletingPathExtension().lastPathComponent, body: Markdown.toHTML(text))
        case .document where t == .txt:
            out = text
        case .spreadsheet:
            out = swapDelimiter(text, from: src.pathExtension.lowercased() == "tsv" ? "\t" : ",", to: t == .tsv ? "\t" : ",")
        default: throw PlanError.unsupported("no built in conversion for \(t.cliName)")
        }
        try out.write(to: dest, atomically: true, encoding: .utf8)
    }

    static func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let s = String(data: data, encoding: .utf8) { return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        throw PlanError.unreadable(url.lastPathComponent)
    }

    public static func html(title: String, body: String) -> String {
        "<!doctype html>\n<html><head><meta charset=\"utf-8\"><title>\(Markdown.escape(title))</title></head><body>\n\(body)\n</body></html>\n"
    }

    /// CSV and TSV swap that respects quoted fields.
    public static func parseRows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var it = Array(text.replacingOccurrences(of: "\r\n", with: "\n")).makeIterator()
        var pending: Character? = nil
        while let c = pending ?? it.next() {
            pending = nil
            if quoted {
                if c == "\"" {
                    if let n = it.next() { if n == "\"" { field.append("\"") } else { quoted = false; pending = n } } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == delimiter { row.append(field); field = "" }
            else if c == "\n" { row.append(field); rows.append(row); row = []; field = "" }
            else { field.append(c) }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    public static func swapDelimiter(_ text: String, from: Character, to: Character) -> String {
        parseRows(text, delimiter: from).map { row in
            row.map { f in
                f.contains(to) || f.contains("\"") || f.contains("\n") ? "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : f
            }.joined(separator: String(to))
        }.joined(separator: "\n") + "\n"
    }
}
