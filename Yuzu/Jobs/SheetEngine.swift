import Foundation

/// Spreadsheets and presentations. CSV and TSV convert natively; the rest uses LibreOffice or iWork.
enum SheetEngine {
    static func convert(_ src: URL, to t: Target, ctx: JobContext) throws -> URL {
        let ext = src.pathExtension.lowercased()
        let isText = ext == "csv" || ext == "tsv"
        let infilter: String? = isText ? (ext == "tsv" ? "CSV:9,34,76,1" : "CSV:44,34,76,1") : nil
        switch t {
        case .csv, .tsv:
            let sep = t == .tsv ? "\t" : ","
            if isText {
                let rows = parse(try readText(src), separator: ext == "tsv" ? "\t" : ",")
                let dest = OutputNamer.destination(for: src, ext: t.ext)
                try csvText(rows: rows, separator: sep).write(to: dest, atomically: true, encoding: .utf8)
                return dest
            }
            let code = t == .tsv ? 9 : 44
            let out = try OfficeEngine.soffice(src, to: "csv:Text - txt - csv (StarCalc):\(code),34,76,1", ext: "csv", ctx: ctx)
            defer { Scratch.cleanupJob(containing: out) }
            return try OutputNamer.deliver(out, for: src, ext: t.ext)
        case .xlsx: return try OfficeEngine.sofficeDeliver(src, to: "xlsx:Calc MS Excel 2007 XML", ext: "xlsx", infilter: infilter, ctx: ctx)
        case .ods: return try OfficeEngine.sofficeDeliver(src, to: "ods", ext: "ods", infilter: infilter, ctx: ctx)
        case .pdf: return try OfficeEngine.sofficeDeliver(src, to: "pdf:calc_pdf_Export", ext: "pdf", infilter: infilter, ctx: ctx)
        case .numbers:
            // Numbers opens CSV and Excel directly; ODS goes through Excel first.
            return try OfficeEngine.toIWork(src, target: .numbers, ctx: ctx, intermediate: ["csv", "xlsx", "xls", "tsv"].contains(ext) ? nil : { s in
                try OfficeEngine.soffice(s, to: "xlsx:Calc MS Excel 2007 XML", ext: "xlsx", ctx: ctx)
            })
        default: throw YuzuError.unsupported("\(t.title) is not available for spreadsheets.")
        }
    }

    static func slides(_ src: URL, to t: Target, ctx: JobContext) throws -> URL {
        let ext = src.pathExtension.lowercased()
        switch t {
        case .pdf: return try OfficeEngine.sofficeDeliver(src, to: "pdf:impress_pdf_Export", ext: "pdf", ctx: ctx)
        case .pptx: return try OfficeEngine.sofficeDeliver(src, to: "pptx:Impress MS PowerPoint 2007 XML", ext: "pptx", ctx: ctx)
        case .odp: return try OfficeEngine.sofficeDeliver(src, to: "odp", ext: "odp", ctx: ctx)
        case .pngPages, .jpgPages:
            let pdf = try OfficeEngine.soffice(src, to: "pdf:impress_pdf_Export", ext: "pdf", ctx: ctx)
            defer { Scratch.cleanupJob(containing: pdf) }
            // Render next to the original so names come from the deck, not the scratch copy.
            let named = src.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).pdf")
            try FileManager.default.moveItem(at: pdf, to: named)
            defer { try? FileManager.default.removeItem(at: named) }
            let out = try PDFEngine.renderPages(named, png: t == .pngPages, ctx: ctx)
            let isDir = (try? out.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let final = isDir ? OutputNamer.folder(for: src, suffix: "slides")
                              : OutputNamer.destination(for: src, ext: out.pathExtension)
            try FileManager.default.moveItem(at: out, to: final)
            return final
        case .key:
            return try OfficeEngine.toIWork(src, target: .key, ctx: ctx, intermediate: ["pptx", "ppt"].contains(ext) ? nil : { s in
                try OfficeEngine.soffice(s, to: "pptx:Impress MS PowerPoint 2007 XML", ext: "pptx", ctx: ctx)
            })
        default: throw YuzuError.unsupported("\(t.title) is not available for presentations.")
        }
    }

    // MARK: CSV

    static func readText(_ url: URL) throws -> String {
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        return try String(contentsOf: url, encoding: .isoLatin1)
    }

    /// RFC 4180 parser (quotes, doubled quotes, embedded separators and newlines).
    static func parse(_ text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = text.hasPrefix("\u{FEFF}") ? Substring(text.dropFirst()) : Substring(text)
        while let c = chars.first {
            chars = chars.dropFirst()
            if quoted {
                if c == "\"" {
                    if chars.first == "\"" { field.append("\""); chars = chars.dropFirst() } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" && field.isEmpty {
                quoted = true
            } else if c == separator {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field); rows.append(row); row = []; field = ""
            } else {
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    static func csvText(rows: [[String]], separator: String) -> String {
        rows.map { row in
            row.map { f in
                let needs = f.contains(separator) || f.contains("\"") || f.contains("\n") || f.contains("\r")
                return needs ? "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : f
            }.joined(separator: separator)
        }.joined(separator: "\n") + "\n"
    }
}
