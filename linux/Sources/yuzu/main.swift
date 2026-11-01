import Foundation
import YuzuLinuxCore

let version = "1.2.0-linux"
let usage = """
yuzu \(version), convert files and save the result next to the original.

usage:
  yuzu convert <file>... --to <format>   convert one or more files
  yuzu targets <file>...                 list formats these files can become
  yuzu pick <file>...                    choose a format in a dialog (zenity or kdialog)
  yuzu doctor                            show which engines are installed
  yuzu --version

nothing is uploaded. engines (ffmpeg, imagemagick, pandoc, libreoffice, poppler) come from your system.
"""

func fail(_ msg: String, _ code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data(("yuzu: " + msg + "\n").utf8))
    exit(code)
}

func urls(_ args: ArraySlice<String>) -> [URL] {
    args.map { URL(fileURLWithPath: $0).standardizedFileURL }
}

/// Converts in parallel like the mac app's job runner, printing one line per file.
func convertAll(_ files: [URL], to t: Target, runner: Runner) -> (ok: [URL], failed: [String]) {
    let lock = NSLock()
    var ok: [URL] = [], failed: [String] = []
    DispatchQueue.concurrentPerform(iterations: files.count) { i in
        let f = files[i]
        do {
            let out = try runner.convert(f, to: t)
            lock.lock(); ok.append(out); print("saved \(out.path)"); lock.unlock()
        } catch {
            lock.lock(); failed.append("\(f.lastPathComponent): \(error)"); lock.unlock()
        }
    }
    return (ok, failed)
}

func which(_ name: String) -> String? {
    for d in (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin").split(separator: ":") {
        let p = "\(d)/\(name)"
        if FileManager.default.isExecutableFile(atPath: p) { return p }
    }
    return nil
}

func capture(_ tool: String, _ args: [String]) -> (Int32, String) {
    let p = Process(), out = Pipe()
    p.executableURL = URL(fileURLWithPath: tool); p.arguments = args; p.standardOutput = out
    guard (try? p.run()) != nil else { return (-1, "") }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}

func notify(_ title: String, _ body: String) {
    if let n = which("notify-send") { _ = capture(n, ["-a", "Yuzu", title, body]) }
}

var args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { print(usage); exit(0) }

switch cmd {
case "--version", "-v", "version":
    print("yuzu \(version)")

case "-h", "--help", "help":
    print(usage)

case "doctor":
    let tools = Tools.detect()
    for name in ["ffmpeg", "magick", "convert", "pandoc", "soffice", "pdftoppm", "pdftotext", "zip", "unzip", "tar"] {
        if let p = tools.path(name) { print("ok       \(name)  \(p)") }
        else { print("missing  \(name)" + (Tools.installHint[name].map { "  (\($0))" } ?? "")) }
    }

case "targets":
    let files = urls(args.dropFirst())
    guard !files.isEmpty else { fail("targets needs at least one file") }
    let list = Catalog.targets(for: files)
    if list.isEmpty { fail("no shared formats for these files") }
    print(list.map(\.cliName).joined(separator: "\n"))

case "convert":
    guard let i = args.firstIndex(where: { $0 == "--to" || $0 == "-t" }), i + 1 < args.count else { fail("convert needs --to <format>") }
    guard let t = Target(cliName: args[i + 1]) else { fail("unknown format \(args[i + 1])") }
    args.removeSubrange(i...(i + 1))
    let files = urls(args.dropFirst())
    guard !files.isEmpty else { fail("convert needs at least one file") }
    let r = convertAll(files, to: t, runner: Runner())
    for f in r.failed { FileHandle.standardError.write(Data(("failed " + f + "\n").utf8)) }
    exit(r.failed.isEmpty ? 0 : 1)

case "pick":
    let files = urls(args.dropFirst())
    guard !files.isEmpty else { fail("pick needs at least one file") }
    let list = Catalog.targets(for: files)
    guard !list.isEmpty else { notify("Yuzu", "no shared formats for these files"); fail("no shared formats") }
    let title = files.count == 1 ? files[0].lastPathComponent : "\(files.count) files"
    var choice: String?
    if let z = which("zenity") {
        let (st, out) = capture(z, ["--list", "--title=Yuzu", "--text=convert \(title) to", "--column=format",
                                    "--height=420", "--width=280"] + list.map(\.cliName))
        if st == 0, !out.isEmpty { choice = out }
    } else if let k = which("kdialog") {
        let (st, out) = capture(k, ["--title", "Yuzu", "--radiolist", "convert \(title) to"] + list.flatMap { [$0.cliName, $0.cliName, "off"] })
        if st == 0, !out.isEmpty { choice = out }
    } else {
        fail("pick needs zenity or kdialog; use yuzu convert instead")
    }
    guard let c = choice, let t = Target(cliName: c) else { exit(0) }
    let r = convertAll(files, to: t, runner: Runner())
    if r.failed.isEmpty { notify("Saved", r.ok.count == 1 ? r.ok[0].lastPathComponent : "\(r.ok.count) files") }
    else { notify("Yuzu could not convert", r.failed.joined(separator: "\n")) }
    exit(r.failed.isEmpty ? 0 : 1)

default:
    fail("unknown command \(cmd)\n\n\(usage)", 2)
}
