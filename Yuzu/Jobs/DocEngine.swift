import AppKit
import CoreText
import PDFKit

/// A neutral document model so every text writer (Markdown, HTML, EPUB) shares one reading of the source.
struct DocRun { var text: String; var bold = false; var italic = false; var code = false; var link: String? }
struct DocBlock {
    enum Kind { case h1, h2, h3, p, li, oli, quote, pre }
    var kind: Kind
    var runs: [DocRun]
    var plain: String { runs.map(\.text).joined() }
}
struct DocModel { var title: String; var blocks: [DocBlock] }

enum DocEngine {
    static let officeSourceExts: Set<String> = ["doc", "docx", "odt", "rtf", "rtfd", "pages"]

    // MARK: Routing for document sources (txt, md, html, rtf, doc, docx, odt, pages, epub, webarchive)

    static func convert(_ src: URL, to t: Target, ctx: JobContext) throws -> URL {
        let ext = src.pathExtension.lowercased()
        ctx.report(0.05)
        switch t {
        case .pdf:
            if officeSourceExts.contains(ext), ToolLocator.soffice != nil {
                return try OfficeEngine.sofficeDeliver(src, to: "pdf:writer_pdf_Export", ext: "pdf", ctx: ctx)
            }
            let a = try load(src, ctx: ctx)
            let dest = OutputNamer.destination(for: src, ext: "pdf")
            try paginatePDF(a, to: dest, title: src.deletingPathExtension().lastPathComponent)
            return dest
        case .docx where ext == "pages" || ext == "doc":
            return try OfficeEngine.sofficeDeliver(src, to: "docx:MS Word 2007 XML", ext: "docx", ctx: ctx)
        case .odt where ext == "pages":
            return try OfficeEngine.sofficeDeliver(src, to: "odt", ext: "odt", ctx: ctx)
        case .pages:
            return try OfficeEngine.toIWork(src, target: .pages, ctx: ctx, intermediate: ["docx", "doc", "rtf", "txt"].contains(ext) ? nil : { s in
                let a = try load(s, ctx: ctx)
                let dir = try Scratch.dir("pages")
                let tmp = dir.appendingPathComponent(s.deletingPathExtension().lastPathComponent).appendingPathExtension("docx")
                try write(a, type: .officeOpenXML, to: tmp)
                return tmp
            })
        default: break
        }
        let a = try load(src, ctx: ctx)
        ctx.report(0.6)
        let title = src.deletingPathExtension().lastPathComponent
        let dest = OutputNamer.destination(for: src, ext: t.ext)
        try writeTarget(a, title: title, target: t, to: dest)
        ctx.report(1)
        return dest
    }

    static func writeTarget(_ a: NSAttributedString, title: String, target t: Target, to dest: URL) throws {
        switch t {
        case .docx: try write(a, type: .officeOpenXML, to: dest)
        case .odt: try write(a, type: .openDocument, to: dest)
        case .rtf: try write(a, type: .rtf, to: dest)
        case .txt: try a.string.write(to: dest, atomically: true, encoding: .utf8)
        case .md: try markdown(model(a, title: title)).write(to: dest, atomically: true, encoding: .utf8)
        case .html: try htmlDocument(model(a, title: title)).write(to: dest, atomically: true, encoding: .utf8)
        case .epub: try writeEPUB(model(a, title: title), to: dest)
        case .pdf: try paginatePDF(a, to: dest, title: title)
        default: throw YuzuError.unsupported("\(t.title) is not available for documents.")
        }
    }

    // MARK: Loading

    static func load(_ src: URL, ctx: JobContext) throws -> NSAttributedString {
        let ext = src.pathExtension.lowercased()
        switch ext {
        case "md", "markdown":
            let md = try String(contentsOf: src, encoding: .utf8)
            return try fromHTML(Data(wrapHTML(Markdown.toHTML(md), title: "").utf8))
        case "html", "htm":
            return try fromHTML(Data(contentsOf: src))
        case "webarchive":
            return try onMain {
                try NSAttributedString(url: src, options: [.documentType: NSAttributedString.DocumentType.webArchive], documentAttributes: nil)
            }
        case "txt", "text":
            let s = try (try? String(contentsOf: src, encoding: .utf8)) ?? String(contentsOf: src, encoding: .isoLatin1)
            return NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 12)])
        case "epub":
            return try fromHTML(Data(readEPUB(src, ctx: ctx).utf8))
        case "pages":
            let docx = try OfficeEngine.soffice(src, to: "docx:MS Word 2007 XML", ext: "docx", ctx: ctx)
            defer { Scratch.cleanupJob(containing: docx) }
            return try NSAttributedString(url: docx, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
        case "pdf":
            return try pdfText(src)
        default:
            do { return try NSAttributedString(url: src, options: [:], documentAttributes: nil) }
            catch { throw YuzuError.unreadable(src.lastPathComponent) }
        }
    }

    private static func onMain<T>(_ work: () throws -> T) throws -> T {
        if Thread.isMainThread { return try work() }
        var result: Result<T, Error>!
        DispatchQueue.main.sync { result = Result { try work() } }
        return try result.get()
    }

    /// HTML import uses WebKit, which must run on the main thread.
    static func fromHTML(_ data: Data) throws -> NSAttributedString {
        try onMain {
            try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html,
                                                         .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
        }
    }

    static func write(_ a: NSAttributedString, type: NSAttributedString.DocumentType, to dest: URL) throws {
        let data = try a.data(from: NSRange(location: 0, length: a.length), documentAttributes: [.documentType: type])
        try data.write(to: dest, options: .atomic)
    }

    /// Text with fonts from every page, reflowed so wrapped lines become paragraphs again.
    static func pdfText(_ src: URL) throws -> NSAttributedString {
        guard let doc = PDFDocument(url: src) else { throw YuzuError.unreadable(src.lastPathComponent) }
        if doc.isLocked { throw YuzuError.unsupported("This PDF is password protected.") }
        let out = NSMutableAttributedString()
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let s = page.attributedString else { continue }
            out.append(s)
            if i < doc.pageCount - 1 { out.append(NSAttributedString(string: "\n")) }
        }
        return out
    }

    // MARK: Model

    static func model(_ a: NSAttributedString, title: String, reflow: Bool = false) -> DocModel {
        let ns = a.string as NSString
        var sizes: [CGFloat: Int] = [:]
        a.enumerateAttribute(.font, in: NSRange(location: 0, length: a.length)) { v, r, _ in
            if let f = v as? NSFont { sizes[f.pointSize.rounded(), default: 0] += r.length }
        }
        let body = sizes.max { $0.value < $1.value }?.key ?? 12
        var blocks: [DocBlock] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { sub, range, _, _ in
            guard let sub, !sub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            var runs: [DocRun] = []
            var maxSize: CGFloat = 0
            var allBold = true, allMono = true
            a.enumerateAttributes(in: range) { attrs, r, _ in
                let t = ns.substring(with: r)
                let f = attrs[.font] as? NSFont
                let traits = f.map { NSFontManager.shared.traits(of: $0) } ?? []
                let bold = traits.contains(.boldFontMask) || (f?.fontName.localizedCaseInsensitiveContains("bold") ?? false)
                let italic = traits.contains(.italicFontMask)
                let code = f?.isFixedPitch ?? false
                let isText = !t.trimmingCharacters(in: .whitespaces).isEmpty
                if isText {
                    maxSize = max(maxSize, f?.pointSize ?? body)
                    if !bold { allBold = false }
                    if !code { allMono = false }
                }
                let link = (attrs[.link] as? URL)?.absoluteString ?? (attrs[.link] as? String)
                if var last = runs.last, last.bold == bold, last.italic == italic, last.code == code, last.link == link {
                    last.text += t; runs[runs.count - 1] = last
                } else {
                    runs.append(DocRun(text: t, bold: bold, italic: italic, code: code, link: link))
                }
            }
            var kind: DocBlock.Kind = .p
            let ratio = maxSize / max(body, 1)
            if ratio >= 1.55 { kind = .h1 } else if ratio >= 1.25 { kind = .h2 } else if ratio >= 1.08 && allBold { kind = .h3 }
            let style = range.length > 0 ? a.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle : nil
            if let list = style?.textLists.last {
                kind = list.markerFormat == .decimal || list.markerFormat == .lowercaseAlpha ? .oli : .li
            }
            if let first = runs.first, let m = first.text.firstMatch(of: /^\t?([•◦▪‣·–-]|\d+[.)]?)\t/) {
                runs[0].text.removeSubrange(first.text.startIndex..<m.range.upperBound)
                if kind == .p || kind == .li || kind == .oli { kind = m.1.first?.isNumber == true ? .oli : .li }
            } else if let first = runs.first, first.text.hasPrefix("• ") {
                runs[0].text.removeFirst(2); kind = .li
            }
            if allMono && kind == .p { kind = .pre }
            if [.h1, .h2, .h3].contains(kind) { runs = runs.map { var r = $0; r.bold = false; return r } }
            blocks.append(DocBlock(kind: kind, runs: runs))
        }
        if reflow { blocks = reflowLines(blocks) }
        return DocModel(title: title, blocks: blocks)
    }

    /// PDF text arrives one line per paragraph; join lines that do not end a sentence.
    static func reflowLines(_ blocks: [DocBlock]) -> [DocBlock] {
        var out: [DocBlock] = []
        for b in blocks {
            if b.kind == .p, var last = out.last, last.kind == .p,
               let end = last.plain.trimmingCharacters(in: .whitespaces).last, !".!?:;\"”".contains(end),
               last.plain.count > 40 {
                if last.plain.hasSuffix("-") { last.runs[last.runs.count - 1].text.removeLast() }
                else { last.runs.append(DocRun(text: " ")) }
                last.runs += b.runs
                out[out.count - 1] = last
            } else {
                out.append(b)
            }
        }
        return out
    }

    // MARK: Writers

    static func markdown(_ m: DocModel) -> String {
        func inline(_ runs: [DocRun]) -> String {
            runs.map { r -> String in
                var t = r.text.replacingOccurrences(of: "\n", with: " ")
                if r.code { return "`\(t)`" }
                t = t.replacingOccurrences(of: "*", with: "\\*").replacingOccurrences(of: "_", with: "\\_")
                let lead = t.prefix { $0 == " " }, trail = String(t.reversed().prefix { $0 == " " })
                var core = t.trimmingCharacters(in: .whitespaces)
                if core.isEmpty { return t }
                if r.bold { core = "**\(core)**" }
                if r.italic { core = "*\(core)*" }
                if let l = r.link { core = "[\(core)](\(l))" }
                return lead + core + trail
            }.joined().trimmingCharacters(in: .whitespaces)
        }
        var lines: [String] = []
        var n = 0
        var prev: DocBlock.Kind?
        for b in m.blocks {
            if b.kind != .oli { n = 0 }
            let isList = b.kind == .li || b.kind == .oli
            let sameGroup = prev == b.kind && (isList || b.kind == .pre)
            if !lines.isEmpty && !sameGroup { lines.append("") }
            switch b.kind {
            case .h1: lines.append("# " + inline(b.runs))
            case .h2: lines.append("## " + inline(b.runs))
            case .h3: lines.append("### " + inline(b.runs))
            case .li: lines.append("- " + inline(b.runs))
            case .oli: n += 1; lines.append("\(n). " + inline(b.runs))
            case .quote: lines.append("> " + inline(b.runs))
            case .pre:
                if prev == .pre, lines.last == "```" { lines.removeLast() } else { lines.append("```") }
                lines.append(b.plain); lines.append("```")
            case .p: lines.append(inline(b.runs))
            }
            prev = b.kind
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func xhtmlBody(_ m: DocModel) -> String {
        func esc(_ s: String) -> String { Markdown.escape(s) }
        func inline(_ runs: [DocRun]) -> String {
            runs.map { r in
                var t = esc(r.text.replacingOccurrences(of: "\n", with: " "))
                if r.code { t = "<code>\(t)</code>" }
                if r.bold { t = "<strong>\(t)</strong>" }
                if r.italic { t = "<em>\(t)</em>" }
                if let l = r.link { t = "<a href=\"\(esc(l))\">\(t)</a>" }
                return t
            }.joined()
        }
        var html: [String] = []
        var open: String?
        func close() { if let o = open { html.append("</\(o)>"); open = nil } }
        for b in m.blocks {
            let want: String? = b.kind == .li ? "ul" : b.kind == .oli ? "ol" : b.kind == .pre ? "pre" : nil
            if want != open { close(); if let want { html.append(want == "pre" ? "<pre>" : "<\(want)>"); open = want } }
            switch b.kind {
            case .h1: html.append("<h1>\(inline(b.runs))</h1>")
            case .h2: html.append("<h2>\(inline(b.runs))</h2>")
            case .h3: html.append("<h3>\(inline(b.runs))</h3>")
            case .li, .oli: html.append("<li>\(inline(b.runs))</li>")
            case .quote: html.append("<blockquote><p>\(inline(b.runs))</p></blockquote>")
            case .pre: html.append(esc(b.plain))
            case .p: html.append("<p>\(inline(b.runs))</p>")
            }
        }
        close()
        return html.joined(separator: "\n")
    }

    static let css = """
    body { font: 16px/1.55 -apple-system, "Helvetica Neue", Helvetica, Arial, sans-serif; color: #1d1d1f; max-width: 42em; margin: 2.5em auto; padding: 0 1.2em; }
    h1, h2, h3 { line-height: 1.2; margin: 1.4em 0 0.5em; } h1 { font-size: 1.9em; } h2 { font-size: 1.45em; } h3 { font-size: 1.15em; }
    pre, code { font-family: ui-monospace, Menlo, monospace; font-size: 0.92em; } pre { background: #f4f4f6; padding: 0.8em 1em; border-radius: 8px; overflow-x: auto; }
    blockquote { margin: 1em 0; padding-left: 1em; border-left: 3px solid #d2d2d7; color: #555; } a { color: #b66a00; }
    @media (prefers-color-scheme: dark) { body { background: #1c1c1e; color: #f2f2f7; } pre { background: #2c2c2e; } a { color: #ffb84d; } }
    """

    static func wrapHTML(_ body: String, title: String) -> String {
        "<!DOCTYPE html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"/><title>\(Markdown.escape(title))</title></head><body>\n\(body)\n</body></html>\n"
    }

    static func htmlDocument(_ m: DocModel) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <title>\(Markdown.escape(m.title))</title>
        <style>
        \(css)
        </style>
        </head>
        <body>
        <article>
        \(xhtmlBody(m))
        </article>
        </body>
        </html>

        """
    }

    // MARK: EPUB

    static func writeEPUB(_ m: DocModel, to dest: URL) throws {
        let dir = try Scratch.dir("epub")
        defer { Scratch.cleanup(dir) }
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("OEBPS"), withIntermediateDirectories: true)
        try "application/epub+zip".write(to: dir.appendingPathComponent("mimetype"), atomically: true, encoding: .ascii)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """.write(to: dir.appendingPathComponent("META-INF/container.xml"), atomically: true, encoding: .utf8)
        let title = Markdown.escape(m.title)
        let id = "urn:uuid:\(UUID().uuidString.lowercased())"
        let modified = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="bookid">\(id)</dc:identifier>
            <dc:title>\(title)</dc:title>
            <dc:language>en</dc:language>
            <meta property="dcterms:modified">\(modified)</meta>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="text" href="text.xhtml" media-type="application/xhtml+xml"/>
            <item id="css" href="style.css" media-type="text/css"/>
          </manifest>
          <spine><itemref idref="text"/></spine>
        </package>
        """.write(to: dir.appendingPathComponent("OEBPS/content.opf"), atomically: true, encoding: .utf8)

        // Give headings ids so the table of contents can link to them.
        var body = xhtmlBody(m)
        var toc: [String] = []
        var n = 0
        body = body.replacing(/<h([12])>(.*?)<\/h\1>/) { match in
            n += 1
            toc.append("<li><a href=\"text.xhtml#s\(n)\">\(match.2)</a></li>")
            return "<h\(match.1) id=\"s\(n)\">\(match.2)</h\(match.1)>"
        }
        if toc.isEmpty { toc = ["<li><a href=\"text.xhtml\">\(title)</a></li>"] }
        func page(_ t: String, _ inner: String, nav: Bool = false) -> String {
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml"\(nav ? " xmlns:epub=\"http://www.idpf.org/2007/ops\"" : "") lang="en" xml:lang="en">
            <head><meta charset="utf-8"/><title>\(t)</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
            <body>
            \(inner)
            </body>
            </html>
            """
        }
        try page(title, "<nav epub:type=\"toc\" id=\"toc\"><h1>Contents</h1><ol>\(toc.joined())</ol></nav>", nav: true)
            .write(to: dir.appendingPathComponent("OEBPS/nav.xhtml"), atomically: true, encoding: .utf8)
        try page(title, body).write(to: dir.appendingPathComponent("OEBPS/text.xhtml"), atomically: true, encoding: .utf8)
        try css.write(to: dir.appendingPathComponent("OEBPS/style.css"), atomically: true, encoding: .utf8)

        let tmp = dir.appendingPathComponent("book.epub")
        try ToolLocator.run("/usr/bin/zip", ["-X0q", tmp.path, "mimetype"], cwd: dir)
        try ToolLocator.run("/usr/bin/zip", ["-Xr9Dq", tmp.path, "META-INF", "OEBPS"], cwd: dir)
        try fm.moveItem(at: tmp, to: dest)
    }

    /// Reads an EPUB's spine into one HTML document.
    static func readEPUB(_ src: URL, ctx: JobContext) throws -> String {
        let dir = try Scratch.dir("epub-in")
        defer { Scratch.cleanup(dir) }
        try ToolLocator.run("/usr/bin/ditto", ["-x", "-k", src.path, dir.path], ctx: ctx)
        guard let container = try? XMLDocument(contentsOf: dir.appendingPathComponent("META-INF/container.xml"), options: []),
              let opfPath = (try? container.nodes(forXPath: "//*[local-name()='rootfile']/@full-path"))?.first?.stringValue,
              let opf = try? XMLDocument(contentsOf: dir.appendingPathComponent(opfPath), options: [])
        else { throw YuzuError.unreadable(src.lastPathComponent) }
        let base = dir.appendingPathComponent(opfPath).deletingLastPathComponent()
        var hrefs: [String: String] = [:]
        for item in (try? opf.nodes(forXPath: "//*[local-name()='manifest']/*[local-name()='item']")) ?? [] {
            if let e = item as? XMLElement, let id = e.attribute(forName: "id")?.stringValue, let href = e.attribute(forName: "href")?.stringValue {
                hrefs[id] = href
            }
        }
        var bodies: [String] = []
        for ref in (try? opf.nodes(forXPath: "//*[local-name()='spine']/*[local-name()='itemref']/@idref")) ?? [] {
            guard let id = ref.stringValue, let href = hrefs[id]?.removingPercentEncoding else { continue }
            let url = base.appendingPathComponent(href)
            guard let doc = try? XMLDocument(contentsOf: url, options: [.documentTidyHTML]),
                  let body = (try? doc.nodes(forXPath: "//*[local-name()='body']"))?.first as? XMLElement else { continue }
            bodies.append((body.children ?? []).map { $0.xmlString }.joined())
        }
        guard !bodies.isEmpty else { throw YuzuError.unreadable(src.lastPathComponent) }
        return wrapHTML(bodies.joined(separator: "\n<hr/>\n"), title: "")
    }

    // MARK: PDF

    /// Lays text out on A4 (Letter in the US) pages with CoreText.
    static func paginatePDF(_ a: NSAttributedString, to dest: URL, title: String) throws {
        let us = Locale.current.region?.identifier == "US"
        var box = us ? CGRect(x: 0, y: 0, width: 612, height: 792) : CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let info: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextCreator: "Yuzu"]
        guard let ctx = CGContext(dest as CFURL, mediaBox: &box, info as CFDictionary) else {
            throw YuzuError.writeFailed(dest.lastPathComponent)
        }
        let text = printable(a)
        let setter = CTFramesetterCreateWithAttributedString(text)
        let frameRect = box.insetBy(dx: 64, dy: 68)
        var location = 0
        repeat {
            ctx.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: location, length: 0), CGPath(rect: frameRect, transform: nil), nil)
            CTFrameDraw(frame, ctx)
            ctx.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length == 0 { break }
            location += visible.length
        } while location < text.length
        ctx.closePDF()
    }

    /// Dark-mode safe copy: dark text on white paper, with CoreText color attributes.
    private static func printable(_ a: NSAttributedString) -> NSAttributedString {
        if a.length == 0 { return NSAttributedString(string: " ") }
        let m = NSMutableAttributedString(attributedString: a)
        let full = NSRange(location: 0, length: m.length)
        var edits: [(NSRange, NSFont?, CGColor)] = []
        a.enumerateAttributes(in: full) { attrs, r, _ in
            var color = CGColor(gray: 0, alpha: 1)
            if let c = (attrs[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB) {
                let lum = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
                // Near-white text (from Dark Mode sources) would vanish on white paper.
                if lum < 0.85 { color = CGColor(srgbRed: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent) }
            }
            edits.append((r, attrs[.font] == nil ? NSFont.systemFont(ofSize: 12) : nil, color))
        }
        let key = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        for (r, font, color) in edits {
            if let font { m.addAttribute(.font, value: font, range: r) }
            m.addAttribute(key, value: color, range: r)
        }
        return m
    }
}
