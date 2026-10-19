import SwiftUI
import AppKit
import PDFKit
import ImageIO

struct MetaTag: Identifiable, Hashable { let id = UUID(); let group: String; let name: String; let value: String }

/// Reads metadata (exiftool when present, otherwise ImageIO, PDFKit or ffprobe) and writes edits or removals to a copy.
enum MetadataEngine {
    static func read(_ url: URL) -> [MetaTag] {
        if let exif = ToolLocator.exiftool,
           let r = try? ToolLocator.run(exif, ["-j", "-G", "-struct", "-api", "LargeFileSupport=1", url.path], timeout: 30),
           let data = r.stdout.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], let dict = arr.first {
            return dict.compactMap { k, v in
                let parts = k.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2, parts[0] != "ExifTool", parts[0] != "SourceFile", k != "SourceFile" else { return nil }
                return MetaTag(group: parts[0], name: parts[1], value: "\(v)")
            }
            .sorted { ($0.group, $0.name) < ($1.group, $1.name) }
        }
        switch FileKind.of(url) {
        case .image:
            guard let s = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [String: Any] else { return [] }
            var out: [MetaTag] = []
            for (k, v) in props {
                if let d = v as? [String: Any] { for (k2, v2) in d { out.append(MetaTag(group: k.trimmingCharacters(in: CharacterSet(charactersIn: "{}")), name: k2, value: "\(v2)")) } }
                else { out.append(MetaTag(group: "File", name: k, value: "\(v)")) }
            }
            return out.sorted { ($0.group, $0.name) < ($1.group, $1.name) }
        case .pdf:
            let attrs = PDFDocument(url: url)?.documentAttributes ?? [:]
            return attrs.map { MetaTag(group: "PDF", name: "\($0.key)", value: "\($0.value)") }.sorted { $0.name < $1.name }
        default:
            guard let probe = ToolLocator.ffprobe,
                  let r = try? ToolLocator.run(probe, ["-v", "error", "-show_entries", "format_tags:format=duration,bit_rate,format_name", "-of", "json", url.path]),
                  let obj = try? JSONSerialization.jsonObject(with: Data(r.stdout.utf8)) as? [String: Any],
                  let format = obj["format"] as? [String: Any] else { return [] }
            var out = format.compactMap { k, v in k == "tags" ? nil : MetaTag(group: "Format", name: k, value: "\(v)") }
            for (k, v) in (format["tags"] as? [String: Any]) ?? [:] { out.append(MetaTag(group: "Tags", name: k, value: "\(v)")) }
            return out.sorted { ($0.group, $0.name) < ($1.group, $1.name) }
        }
    }

    /// Editable fields per kind: (label, exiftool tag, ffmpeg key).
    static func fields(for kind: FileKind) -> [(String, String, String)] {
        switch kind {
        case .pdf: return [("Title", "Title", "title"), ("Author", "Author", "author"), ("Subject", "Subject", "subject"), ("Keywords", "Keywords", "keywords")]
        case .video, .audio: return [("Title", "Title", "title"), ("Artist", "Artist", "artist"), ("Album", "Album", "album"),
                                     ("Year", "Year", "date"), ("Comment", "Comment", "comment")]
        default: return [("Title", "Title", "title"), ("Description", "Description", "description"), ("Artist", "Artist", "artist"),
                         ("Copyright", "Copyright", "copyright"), ("Keywords", "Keywords", "keywords")]
        }
    }

    static func current(_ tags: [MetaTag], name: String) -> String {
        tags.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value ?? ""
    }

    /// Writes a copy with the given field values (empty values are removed).
    static func write(_ src: URL, values: [String: String], removeLocation: Bool, ctx: JobContext) throws -> URL {
        let kind = FileKind.of(src)
        let dest = OutputNamer.destination(for: src, ext: src.pathExtension, suffix: FileTool.metadata.suffix)
        if kind == .video || kind == .audio {
            var args = ["-i", src.path, "-map", "0", "-c", "copy", "-map_metadata", "0"]
            for (_, _, key) in fields(for: kind) { args += ["-metadata", "\(key)=\(values[key] ?? "")"] }
            if removeLocation { args += ["-metadata", "location=", "-metadata", "location-eng=", "-metadata", "com.apple.quicktime.location.ISO6709="] }
            try ToolEngine.ffmpeg(args, to: dest, duration: 0, ctx: ctx)
            return dest
        }
        let exif = try ToolLocator.require("exiftool")
        var args = ["-q", "-o", dest.path]
        for (_, tag, key) in fields(for: kind) { args.append("-\(tag)=\(values[key] ?? "")") }
        if removeLocation { args.append("-gps:all=") }
        args.append(src.path)
        try ToolLocator.run(exif, args, ctx: ctx)
        return dest
    }

    static func removeAll(_ src: URL, ctx: JobContext) throws -> URL {
        switch FileKind.of(src) {
        case .image:
            return try ImageEngine.apply(.removeMetadata, to: src, settings: ctx.settings)
        case .video, .audio:
            let dest = OutputNamer.destination(for: src, ext: src.pathExtension, suffix: "No Metadata")
            try ToolEngine.ffmpeg(["-i", src.path, "-map", "0", "-c", "copy", "-map_metadata", "-1", "-map_chapters", "-1"],
                                  to: dest, duration: 0, ctx: ctx)
            return dest
        case .pdf:
            guard let doc = PDFDocument(url: src) else { throw YuzuError.unreadable(src.lastPathComponent) }
            let clean = PDFDocument()
            for i in 0..<doc.pageCount { if let p = doc.page(at: i) { clean.insert(p, at: clean.pageCount) } }
            clean.documentAttributes = [:]
            let dest = OutputNamer.destination(for: src, ext: "pdf", suffix: "No Metadata")
            guard clean.write(to: dest) else { throw YuzuError.writeFailed(dest.lastPathComponent) }
            return dest
        default:
            let exif = try ToolLocator.require("exiftool")
            let dest = OutputNamer.destination(for: src, ext: src.pathExtension, suffix: "No Metadata")
            try ToolLocator.run(exif, ["-q", "-all=", "-o", dest.path, src.path], ctx: ctx)
            return dest
        }
    }
}

struct MetadataPanel: View {
    let env: ToolEnv
    @State private var tags: [MetaTag] = []
    @State private var loading = true
    @State private var search = ""
    @State private var values: [String: String] = [:]
    @State private var removeLocation = false

    private var kind: FileKind { FileKind.of(env.urls[0]) }
    private var editable: Bool { kind == .video || kind == .audio || ToolLocator.exiftool != nil }

    var body: some View {
        ToolScaffold(env: env, primary: "Save Copy", primaryEnabled: editable && !loading, onPrimary: save) {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search \(tags.count) tags", text: $search).textFieldStyle(.plain)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                .padding(10)
                if loading {
                    ProgressView().controlSize(.small).frame(maxHeight: .infinity)
                } else {
                    Table(filtered) {
                        TableColumn("Group") { Text($0.group).foregroundStyle(.secondary) }.width(min: 60, ideal: 90, max: 130)
                        TableColumn("Tag") { Text($0.name) }.width(min: 90, ideal: 150)
                        TableColumn("Value") { t in Text(t.value).lineLimit(1).truncationMode(.middle).textSelection(.enabled) }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        } controls: {
            SectionLabel("Edit")
            ForEach(MetadataEngine.fields(for: kind), id: \.2) { f in
                VStack(alignment: .leading, spacing: 3) {
                    Text(f.0).font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField(f.0, text: Binding(get: { values[f.2] ?? "" }, set: { values[f.2] = $0 }))
                        .textFieldStyle(.roundedBorder)
                }
            }
            .disabled(!editable)
            if kind != .pdf {
                Toggle("Remove location", isOn: $removeLocation).toggleStyle(.checkbox)
            }
            if !editable {
                Text("Editing needs exiftool. \(ToolLocator.installHint["exiftool"] ?? "")").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            SectionLabel("Privacy")
            Button(role: .destructive) { removeAll() } label: { Label("Remove All Metadata", systemImage: "tag.slash") }
            Text("Saves a copy with no metadata. The original is not changed.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .onAppear(perform: load)
    }

    private var filtered: [MetaTag] {
        search.isEmpty ? tags : tags.filter { "\($0.group) \($0.name) \($0.value)".localizedCaseInsensitiveContains(search) }
    }

    private func load() {
        let url = env.urls[0], k = kind
        Task.detached(priority: .userInitiated) {
            let t = MetadataEngine.read(url)
            await MainActor.run {
                tags = t
                for f in MetadataEngine.fields(for: k) { values[f.2] = MetadataEngine.current(t, name: f.1) }
                loading = false
            }
        }
    }

    private func save() {
        let v = values, loc = removeLocation
        env.run("Saving metadata") { u, ctx in try MetadataEngine.write(u[0], values: v, removeLocation: loc, ctx: ctx) }
    }

    private func removeAll() {
        env.run("Removing metadata") { u, ctx in try MetadataEngine.removeAll(u[0], ctx: ctx) }
    }
}
