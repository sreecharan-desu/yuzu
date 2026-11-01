import Foundation
import XCTest
@testable import YuzuLinuxCore

final class CatalogTests: XCTestCase {
    func testKinds() {
        XCTAssertEqual(Kind.of(ext: "jpeg"), .image)
        XCTAssertEqual(Kind.of(ext: "mkv"), .video)
        XCTAssertEqual(Kind.of(ext: "flac"), .audio)
        XCTAssertEqual(Kind.of(ext: "pdf"), .pdf)
        XCTAssertEqual(Kind.of(ext: "md"), .document)
        XCTAssertEqual(Kind.of(ext: "pptx"), .slides)
        XCTAssertEqual(Kind.of(ext: "csv"), .spreadsheet)
        XCTAssertEqual(Kind.of(ext: "vtt"), .subtitle)
        XCTAssertEqual(Kind.of(ext: "tgz"), .archive)
        XCTAssertEqual(Kind.of(ext: "xyz"), .other)
    }

    func testTargetsHideSameFormat() {
        XCTAssertFalse(Catalog.targets(for: .image, sourceExt: "jpeg").contains(.jpg))
        XCTAssertFalse(Catalog.targets(for: .audio, sourceExt: "aif").contains(.aiff))
        XCTAssertFalse(Catalog.targets(for: .archive, sourceExt: "tar.gz").contains(.tgz))
        XCTAssertTrue(Catalog.targets(for: .slides, sourceExt: "ppt").contains(.pptx))
        XCTAssertEqual(Catalog.targets(for: .other, sourceExt: "xyz"), [])
    }

    func testSharedTargets() {
        let a = URL(fileURLWithPath: "/tmp/a.png"), b = URL(fileURLWithPath: "/tmp/b.jpg")
        let both = Catalog.targets(for: [a, b])
        XCTAssertFalse(both.contains(.png))
        XCTAssertFalse(both.contains(.jpg))
        XCTAssertTrue(both.contains(.webp))
        XCTAssertEqual(Catalog.targets(for: [a, URL(fileURLWithPath: "/tmp/c.mp3")]), [])
    }

    func testCliNames() {
        XCTAssertEqual(Target(cliName: "JPEG"), .jpg)
        XCTAssertEqual(Target(cliName: "png-pages"), .pngPages)
        XCTAssertEqual(Target(cliName: "tar.gz"), .tgz)
        XCTAssertNil(Target(cliName: "pages"))
        for t in Target.allCases { XCTAssertEqual(Target(cliName: t.cliName), t) }
    }
}

final class SubtitleTests: XCTestCase {
    let srt = "1\r\n00:00:01,500 --> 00:00:03,000\r\nhello\r\n\r\n2\r\n00:01:02,000 --> 00:01:04,250\r\n<i>two</i>\r\nlines\r\n"

    func testParse() {
        let cues = Subtitles.parse(srt)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0], .init(start: 1.5, end: 3, text: "hello"))
        XCTAssertEqual(cues[1].start, 62)
        XCTAssertEqual(cues[1].text, "<i>two</i>\nlines")
    }

    func testRoundTrip() {
        let vtt = Subtitles.render(Subtitles.parse(srt), as: .vtt)!
        XCTAssertTrue(vtt.hasPrefix("WEBVTT\n\n00:00:01.500 --> 00:00:03.000\nhello\n"))
        let back = Subtitles.render(Subtitles.parse(vtt), as: .srt)!
        XCTAssertEqual(Subtitles.parse(back), Subtitles.parse(srt))
        XCTAssertEqual(Subtitles.render(Subtitles.parse(srt), as: .txt), "hello\ntwo\nlines\n")
    }

    func testStamp() {
        XCTAssertEqual(Subtitles.stamp(3725.042, ","), "01:02:05,042")
        XCTAssertEqual(Subtitles.seconds("02:05.5"), 125.5)
        XCTAssertNil(Subtitles.seconds("nope"))
    }
}

final class PlannerTests: XCTestCase {
    let tools = Tools(paths: ["ffmpeg": "/usr/bin/ffmpeg", "convert": "/usr/bin/convert", "pandoc": "/usr/bin/pandoc",
                              "tar": "/usr/bin/tar", "zip": "/usr/bin/zip", "unzip": "/usr/bin/unzip"])
    let scratch = URL(fileURLWithPath: "/tmp/scratch")

    func testImageUsesImageMagickAndFlattensJpeg() {
        let s = Planner.plan(URL(fileURLWithPath: "/x/a.png"), to: .jpg, dest: URL(fileURLWithPath: "/x/a.jpg"), scratch: scratch, tools: tools)
        guard case .run(let cmds, _) = s else { return XCTFail("\(s)") }
        XCTAssertEqual(cmds[0].tool, "/usr/bin/convert")
        XCTAssertTrue(cmds[0].args.contains("remove"))
        XCTAssertEqual(cmds[0].args.last, "/x/a.jpg")
    }

    func testMissingTool() {
        let s = Planner.plan(URL(fileURLWithPath: "/x/a.mp4"), to: .mp3, dest: URL(fileURLWithPath: "/x/a.mp3"), scratch: scratch, tools: Tools(paths: [:]))
        XCTAssertEqual(s, .missing("ffmpeg"))
        XCTAssertEqual(Planner.plan(URL(fileURLWithPath: "/x/a.pptx"), to: .pdf, dest: URL(fileURLWithPath: "/x/a.pdf"), scratch: scratch, tools: tools), .missing("soffice"))
    }

    func testNativePaths() {
        XCTAssertEqual(Planner.plan(URL(fileURLWithPath: "/x/a.srt"), to: .vtt, dest: URL(fileURLWithPath: "/x/a.vtt"), scratch: scratch, tools: tools), .native(.vtt))
        XCTAssertEqual(Planner.plan(URL(fileURLWithPath: "/x/a.md"), to: .html, dest: URL(fileURLWithPath: "/x/a.html"), scratch: scratch, tools: tools), .native(.html))
        XCTAssertEqual(Planner.plan(URL(fileURLWithPath: "/x/a.csv"), to: .tsv, dest: URL(fileURLWithPath: "/x/a.tsv"), scratch: scratch, tools: tools), .native(.tsv))
    }

    func testUnsupported() {
        if case .unsupported = Planner.plan(URL(fileURLWithPath: "/x/a.mp3"), to: .docx, dest: URL(fileURLWithPath: "/x/a.docx"), scratch: scratch, tools: tools) {} else { XCTFail() }
    }
}

final class NativeTests: XCTestCase {
    func testCSVToTSVKeepsQuotedCommas() {
        let out = Native.swapDelimiter("name,note\n\"a, b\",\"say \"\"hi\"\"\"\n", from: ",", to: "\t")
        XCTAssertEqual(out, "name\tnote\na, b\t\"say \"\"hi\"\"\"\n")
        XCTAssertEqual(Native.parseRows(out, delimiter: "\t")[1], ["a, b", "say \"hi\""])
    }

    func testSharedMarkdown() {
        XCTAssertEqual(Markdown.toHTML("# hi\n\nsome **bold** and `code`"), "<h1>hi</h1>\n<p>some <strong>bold</strong> and <code>code</code></p>")
    }

    func testSharedOutputNamerNeverOverwrites() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("yuzu-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("photo.png")
        try Data().write(to: src)
        try Data().write(to: dir.appendingPathComponent("photo.jpg"))
        XCTAssertEqual(OutputNamer.destination(for: src, ext: "jpg").lastPathComponent, "photo 2.jpg")
        XCTAssertEqual(OutputNamer.destination(for: src, ext: "jpg").lastPathComponent, "photo 3.jpg")
        XCTAssertEqual(OutputNamer.destination(for: src, ext: "png").lastPathComponent, "photo 2.png")
    }
}

final class RunnerTests: XCTestCase {
    func testEndToEndNativeSubtitle() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("yuzu-run-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("talk.srt")
        try "1\n00:00:00,000 --> 00:00:01,000\nhi\n".write(to: src, atomically: true, encoding: .utf8)
        let out = try Runner(tools: Tools(paths: [:])).convert(src, to: .vtt)
        XCTAssertEqual(out.lastPathComponent, "talk.vtt")
        XCTAssertEqual(try String(contentsOf: out, encoding: .utf8), "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nhi\n")
    }

    func testFolderToZip() throws {
        let tools = Tools.detect()
        guard tools.path("zip") != nil else { throw XCTSkip("zip not installed") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("yuzu-zip-\(UUID().uuidString)")
        let folder = dir.appendingPathComponent("stuff", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "a".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let out = try Runner(tools: tools).convert(folder, to: .zip)
        XCTAssertEqual(out.lastPathComponent, "stuff.zip")
    }
}
