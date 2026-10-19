// Validates every output listed in a batch TSV by actually opening it with the right decoder.
// Usage: swift scripts/validate.swift build/batch.tsv [report.tsv]
import Foundation
import ImageIO
import PDFKit
import AVFoundation

let args = CommandLine.arguments
let tsv = try! String(contentsOfFile: args[1], encoding: .utf8)
let outPath = args.count > 2 ? args[2] : "build/validate.tsv"
let fm = FileManager.default

func sh(_ cmd: String, _ a: [String]) -> (Int32, String) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: cmd); p.arguments = a
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
    try? p.run(); let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    return (p.terminationStatus, String(decoding: d, as: UTF8.self))
}
func size(_ p: String) -> Int { (try? fm.attributesOfItem(atPath: p)[.size] as? Int) ?? 0 }
func text(_ p: String) -> String { (try? String(contentsOfFile: p, encoding: .utf8)) ?? "" }
func zipEntries(_ p: String) -> [String] { sh("/usr/bin/unzip", ["-Z1", p]).1.split(separator: "\n").map(String.init) }
func image(_ p: String) -> String? {
    guard let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil), CGImageSourceGetCount(s) > 0,
          let props = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any],
          let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0 else { return nil }
    return "\(w)x\(h)" + (CGImageSourceGetCount(s) > 1 ? " \(CGImageSourceGetCount(s)) frames" : "")
}
func probe(_ p: String) -> String? {
    let r = sh("/opt/homebrew/bin/ffprobe", ["-v", "error", "-show_entries", "stream=codec_type,codec_name:format=duration", "-of", "compact=p=0:nk=1", p])
    guard r.0 == 0 else { return nil }
    let lines = r.1.split(separator: "\n").map(String.init)
    guard let dur = lines.last.flatMap({ Double($0) }), dur > 0.5 else { return nil }
    return lines.dropLast().joined(separator: ",") + String(format: " %.2fs", dur)
}

func check(_ path: String) -> (Bool, String) {
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return (false, "missing") }
    if isDir.boolValue {
        let items = (try? fm.subpathsOfDirectory(atPath: path)) ?? []
        guard !items.isEmpty else { return (false, "empty folder") }
        let imgs = items.filter { $0.hasSuffix(".jpg") || $0.hasSuffix(".png") }
        if !imgs.isEmpty {
            let bad = imgs.filter { image(path + "/" + $0) == nil }
            return (bad.isEmpty, "\(imgs.count) images, first \(image(path + "/" + imgs.sorted()[0]) ?? "?")")
        }
        return (true, "\(items.count) items")
    }
    let ext = (path as NSString).pathExtension.lowercased()
    let lower = path.lowercased()
    guard size(path) > 0 else { return (false, "empty file") }
    switch ext {
    case "jpg", "jpeg", "png", "heic", "webp", "tiff", "bmp", "avif":
        if let d = image(path) { return (true, d) }; return (false, "image did not decode")
    case "gif":
        if lower.contains("clip") || probe(path) != nil, let d = image(path) { return (true, d) }
        if let d = image(path) { return (true, d) }; return (false, "gif did not decode")
    case "mp4", "mov", "mkv", "webm", "avi", "wmv", "mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma":
        if let d = probe(path) { return (true, d) }; return (false, "ffprobe could not read it")
    case "pdf":
        guard let doc = PDFDocument(url: URL(fileURLWithPath: path)), doc.pageCount > 0 else { return (false, "PDF did not open") }
        let chars = (doc.string ?? "").count
        return (true, "\(doc.pageCount) pages, \(chars) chars, \(size(path) / 1024) KB")
    case "docx": let e = zipEntries(path); return (e.contains("word/document.xml"), "\(e.count) zip entries")
    case "pptx": let e = zipEntries(path); return (e.contains("ppt/presentation.xml"), "\(e.filter { $0.hasPrefix("ppt/slides/slide") }.count) slides")
    case "xlsx": let e = zipEntries(path); return (e.contains("xl/workbook.xml"), "\(e.count) zip entries")
    case "odt", "odp", "ods":
        let e = zipEntries(path); return (e.first == "mimetype" && e.contains("content.xml"), "\(e.count) zip entries")
    case "epub":
        let e = zipEntries(path)
        let mt = sh("/usr/bin/unzip", ["-p", path, "mimetype"]).1
        return (e.first == "mimetype" && mt == "application/epub+zip" && e.contains("META-INF/container.xml"), "\(e.count) entries")
    case "zip": let e = zipEntries(path); return (!e.isEmpty && !e.contains { $0.contains("__MACOSX") || $0.contains("._") }, "\(e.count) entries")
    case "tar", "gz", "tgz":
        let r = sh("/usr/bin/tar", ["-tf", path]); let n = r.1.split(separator: "\n")
        return (r.0 == 0 && !n.isEmpty && !n.contains { $0.contains("/._") }, "\(n.count) entries")
    case "rtf": return (text(path).hasPrefix("{\\rtf"), "\(size(path)) bytes")
    case "html": let t = text(path).lowercased(); return (t.contains("<html") && t.contains("</html>"), "\(t.count) chars")
    case "md": let t = text(path); return (t.contains("#") || t.count > 20, "\(t.split(separator: "\n").count) lines")
    case "txt": let t = text(path); return (t.trimmingCharacters(in: .whitespacesAndNewlines).count > 5, "\(t.count) chars")
    case "csv": let t = text(path); return (t.contains(","), "\(t.split(separator: "\n").count) lines")
    case "tsv": let t = text(path); return (t.contains("\t"), "\(t.split(separator: "\n").count) lines")
    case "srt": let t = text(path); return (t.contains(" --> ") && t.hasPrefix("1\n"), "\(t.components(separatedBy: " --> ").count - 1) cues")
    case "vtt": let t = text(path); return (t.hasPrefix("WEBVTT") && t.contains(" --> "), "\(t.components(separatedBy: " --> ").count - 1) cues")
    default: return (size(path) > 0, "\(size(path)) bytes (no specific check)")
    }
}

var rows = ["source\toption\tjob\tvalid\tseconds\tdetail"]
var ok = 0, bad = 0, failedJobs = 0
for line in tsv.split(separator: "\n").dropFirst() {
    let c = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard c.count >= 7 else { continue }
    if c[2] != "OK" { failedJobs += 1; rows.append("\(c[0])\t\(c[1])\tERR\t-\t\(c[4])\t\(c[6])"); continue }
    let (v, d) = check(c[3])
    if v { ok += 1 } else { bad += 1 }
    rows.append("\(c[0])\t\(c[1])\tOK\t\(v ? "PASS" : "FAIL")\t\(c[4])\t\(d)")
}
try! (rows.joined(separator: "\n") + "\n").write(toFile: outPath, atomically: true, encoding: .utf8)
print("validated: \(ok) pass, \(bad) fail, \(failedJobs) job errors -> \(outPath)")
