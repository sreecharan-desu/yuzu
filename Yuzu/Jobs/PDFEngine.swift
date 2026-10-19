import AppKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers

/// PDF sources: pages to images, text formats, Word, PowerPoint, Excel, Pages.
enum PDFEngine {
    static func convert(_ src: URL, to t: Target, ctx: JobContext) throws -> URL {
        switch t {
        case .jpgPages, .pngPages:
            return try renderPages(src, png: t == .pngPages, ctx: ctx)
        case .txt:
            let a = try DocEngine.pdfText(src)
            let dest = OutputNamer.destination(for: src, ext: "txt")
            try a.string.write(to: dest, atomically: true, encoding: .utf8)
            return dest
        case .md, .epub, .html:
            let a = try DocEngine.pdfText(src)
            let m = DocEngine.model(a, title: src.deletingPathExtension().lastPathComponent, reflow: true)
            let dest = OutputNamer.destination(for: src, ext: t.ext)
            switch t {
            case .md: try DocEngine.markdown(m).write(to: dest, atomically: true, encoding: .utf8)
            case .html: try DocEngine.htmlDocument(m).write(to: dest, atomically: true, encoding: .utf8)
            default: try DocEngine.writeEPUB(m, to: dest)
            }
            return dest
        case .docx:
            let dest = OutputNamer.destination(for: src, ext: "docx")
            try DocEngine.write(reflowed(src), type: .officeOpenXML, to: dest)
            return dest
        case .pages:
            return try OfficeEngine.toIWork(src, target: .pages, ctx: ctx) { s in
                let dir = try Scratch.dir("pdf-pages")
                let tmp = dir.appendingPathComponent(s.deletingPathExtension().lastPathComponent).appendingPathExtension("docx")
                try DocEngine.write(reflowed(s), type: .officeOpenXML, to: tmp)
                return tmp
            }
        case .pptx:
            return try OfficeEngine.sofficeDeliver(src, to: "pptx:Impress MS PowerPoint 2007 XML", ext: "pptx",
                                                   infilter: "impress_pdf_import", ctx: ctx)
        case .xlsx:
            let dir = try Scratch.dir("pdf-xlsx")
            defer { Scratch.cleanup(dir) }
            let csv = dir.appendingPathComponent(src.deletingPathExtension().lastPathComponent).appendingPathExtension("csv")
            try SheetEngine.csvText(rows: tableRows(try DocEngine.pdfText(src).string), separator: ",").write(to: csv, atomically: true, encoding: .utf8)
            let out = try OfficeEngine.soffice(csv, to: "xlsx:Calc MS Excel 2007 XML", ext: "xlsx",
                                               infilter: "CSV:44,34,76,1", ctx: ctx)
            defer { Scratch.cleanupJob(containing: out) }
            return try OutputNamer.deliver(out, for: src, ext: "xlsx")
        default:
            throw YuzuError.unsupported("\(t.title) is not available for PDFs.")
        }
    }

    /// PDF text rebuilt into paragraphs, keeping fonts, for Word/Pages export.
    private static func reflowed(_ src: URL) throws -> NSAttributedString {
        let a = try DocEngine.pdfText(src)
        let html = DocEngine.htmlDocument(DocEngine.model(a, title: src.deletingPathExtension().lastPathComponent, reflow: true))
        return try DocEngine.fromHTML(Data(html.utf8))
    }

    /// Splits text lines into cells on tabs or runs of 2+ spaces, which is how PDF tables come out.
    static func tableRows(_ text: String) -> [[String]] {
        text.components(separatedBy: .newlines).compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return nil }
            return t.split(separator: /\t|\s{2,}/).map { String($0).trimmingCharacters(in: .whitespaces) }
        }
    }

    /// Renders every page at 300 DPI (capped at 6000 px). One page gives a file; more give a folder.
    static func renderPages(_ src: URL, png: Bool, ctx: JobContext, deliverTo single: URL? = nil) throws -> URL {
        guard let doc = CGPDFDocument(src as CFURL) else { throw YuzuError.unreadable(src.lastPathComponent) }
        if doc.isEncrypted && !doc.unlockWithPassword("") { throw YuzuError.unsupported("This PDF is password protected.") }
        let count = doc.numberOfPages
        guard count > 0 else { throw YuzuError.unreadable(src.lastPathComponent) }
        let ext = png ? "png" : "jpg"
        let folder: URL? = count > 1 ? OutputNamer.folder(for: src, suffix: "pages") : nil
        if let folder { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let digits = String(count).count
        var single: URL?
        for i in 1...count {
            try ctx.checkCancelled()
            guard let page = doc.page(at: i) else { continue }
            let box = page.getBoxRect(.cropBox)
            let angle = (page.rotationAngle % 360 + 360) % 360
            let size = angle == 90 || angle == 270 ? CGSize(width: box.height, height: box.width) : box.size
            var scale = 300.0 / 72.0
            scale = min(scale, 6000 / max(size.width, size.height))
            let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            guard let cg = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                     bitmapInfo: png ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)
            else { throw YuzuError.writeFailed(src.lastPathComponent) }
            if !png { cg.setFillColor(.white); cg.fill(CGRect(x: 0, y: 0, width: w, height: h)) }
            cg.interpolationQuality = .high
            cg.scaleBy(x: scale, y: scale)
            cg.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
            cg.drawPDFPage(page)
            guard let image = cg.makeImage() else { continue }
            let dest: URL
            if let folder {
                dest = folder.appendingPathComponent("page-\(String(format: "%0\(digits)d", i))").appendingPathExtension(ext)
            } else {
                dest = OutputNamer.destination(for: src, ext: ext)
                single = dest
            }
            guard let d = CGImageDestinationCreateWithURL(dest as CFURL, (png ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil)
            else { throw YuzuError.writeFailed(dest.lastPathComponent) }
            CGImageDestinationAddImage(d, image, [kCGImageDestinationLossyCompressionQuality: 0.9,
                                                  kCGImagePropertyDPIWidth: 300, kCGImagePropertyDPIHeight: 300] as CFDictionary)
            guard CGImageDestinationFinalize(d) else { throw YuzuError.writeFailed(dest.lastPathComponent) }
            ctx.report(Double(i) / Double(count))
        }
        return folder ?? single!
    }
}
