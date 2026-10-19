import Foundation

/// Small, dependency-free Markdown to HTML converter (CommonMark subset: headings, paragraphs,
/// lists, quotes, fenced code, rules, emphasis, code spans, links).
enum Markdown {
    static func toHTML(_ md: String) -> String {
        var out: [String] = []
        var para: [String] = []
        var list: (ordered: Bool, items: [String])?
        var inCode = false
        var code: [String] = []
        var quote: [String] = []

        func flushPara() { if !para.isEmpty { out.append("<p>\(inline(para.joined(separator: " ")))</p>"); para = [] } }
        func flushList() {
            if let l = list {
                let tag = l.ordered ? "ol" : "ul"
                out.append("<\(tag)>" + l.items.map { "<li>\(inline($0))</li>" }.joined() + "</\(tag)>")
                list = nil
            }
        }
        func flushQuote() { if !quote.isEmpty { out.append("<blockquote><p>\(inline(quote.joined(separator: " ")))</p></blockquote>"); quote = [] } }
        func flushAll() { flushPara(); flushList(); flushQuote() }

        for raw in md.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode { out.append("<pre><code>\(escape(code.joined(separator: "\n")))</code></pre>"); code = []; inCode = false }
                else { flushAll(); inCode = true }
                continue
            }
            if inCode { code.append(raw); continue }
            if trimmed.isEmpty { flushAll(); continue }
            if let m = trimmed.firstMatch(of: /^(#{1,6})\s+(.*?)\s*#*$/) {
                flushAll()
                let n = m.1.count
                out.append("<h\(n)>\(inline(String(m.2)))</h\(n)>")
                continue
            }
            if trimmed.wholeMatch(of: /(\*\s*){3,}|(-\s*){3,}|(_\s*){3,}/) != nil { flushAll(); out.append("<hr/>"); continue }
            if trimmed.hasPrefix(">") {
                flushPara(); flushList()
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            if let m = trimmed.firstMatch(of: /^([-*+])\s+(.*)$/) {
                flushPara(); flushQuote()
                if list?.ordered != false { flushList(); list = (false, []) }
                list?.items.append(String(m.2)); continue
            }
            if let m = trimmed.firstMatch(of: /^(\d+)[.)]\s+(.*)$/) {
                flushPara(); flushQuote()
                if list?.ordered != true { flushList(); list = (true, []) }
                list?.items.append(String(m.2)); continue
            }
            if list != nil, line.hasPrefix("  "), var items = list?.items, !items.isEmpty {
                items[items.count - 1] += " " + trimmed; list?.items = items; continue
            }
            flushList(); flushQuote()
            para.append(trimmed)
        }
        if inCode { out.append("<pre><code>\(escape(code.joined(separator: "\n")))</code></pre>") }
        flushAll()
        return out.joined(separator: "\n")
    }

    private static func sub(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func inline(_ s: String) -> String {
        // Protect code spans first.
        var spans: [String] = []
        var text = s.replacing(/`([^`]+)`/) { m in
            spans.append("<code>\(escape(String(m.1)))</code>")
            return "\u{1}\(spans.count - 1)\u{2}"
        }
        text = escape(text)
        text = text.replacing(/!\[([^\]]*)\]\(([^)\s]+)[^)]*\)/) { m in String(m.1) }
        text = text.replacing(/\[([^\]]+)\]\(([^)\s]+)[^)]*\)/) { m in "<a href=\"\(m.2)\">\(m.1)</a>" }
        text = text.replacing(/\*\*(.+?)\*\*|__(.+?)__/) { m in "<strong>\(m.1 ?? m.2 ?? "")</strong>" }
        text = sub(text, #"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?!\w)"#, "<em>$1</em>")
        text = sub(text, #"(?<!\w)_(?!\s)(.+?)(?<!\s)_(?!\w)"#, "<em>$1</em>")
        text = text.replacing(/\u{1}(\d+)\u{2}/) { m in spans[Int(m.1) ?? 0] }
        return text
    }
}
