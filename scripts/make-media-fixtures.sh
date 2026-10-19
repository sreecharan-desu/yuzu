#!/bin/zsh
# Demo media for tool panels: a photo slideshow with narration, a stereo speech clip, an 8-page PDF.
# Developer-only: put your own photos (dog.jpg, parrot.heic, dahlia.heic) in TestFiles/addbg first.
set -e
cd "$(dirname $0)/.." ; D=TestFiles/media; A=TestFiles/addbg
FF=$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)
T=$(mktemp -d); for n in parrot dahlia; do sips -s format jpeg $A/$n.heic --out $T/$n.jpg >/dev/null; done
say -o $D/narration.aiff "Welcome to Yuzu. Drag a file, tap a key, and drop it on the ring. This clip has three photos: a dog, a parrot, and a dahlia. Trim it, speed it up, split it, or bleep a word."
Z="scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,zoompan=z='1+0.0012*on':d=180:s=1280x720:fps=30,setsar=1"
$FF -y -loglevel error -loop 1 -t 6 -i $A/dog.jpg -loop 1 -t 6 -i $T/parrot.jpg -loop 1 -t 6 -i $T/dahlia.jpg -i $D/narration.aiff -filter_complex \
"[0]${Z}[a];[1]${Z}[b];[2]${Z}[c];[a][b]xfade=transition=fade:duration=0.8:offset=5.2[ab];[ab][c]xfade=transition=fade:duration=0.8:offset=10.4,format=yuv420p[v];[3:a]apad,atrim=0:16.4,pan=stereo|c0=c0|c1=c0[au]" \
-map "[v]" -map "[au]" -t 16.4 -c:v h264_videotoolbox -b:v 4M -c:a aac -b:a 160k $D/photos.mp4
$FF -y -loglevel error -i $D/narration.aiff -af "pan=stereo|c0=1.0*c0|c1=0.45*c0,adelay=0|180" -c:a aac -b:a 160k $D/speech.m4a
rm -f $D/narration.aiff
cat > /tmp/yuzu-pdf.swift <<'SW'
import AppKit
let url = URL(fileURLWithPath: CommandLine.arguments[1])
var box = CGRect(x: 0, y: 0, width: 612, height: 792)
let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
let titles = ["Cover", "Contents", "Introduction", "Drag and Drop", "The Ring", "Tools", "Shortcuts", "Appendix"]
let hues: [CGFloat] = [0.10, 0.55, 0.33, 0.95, 0.08, 0.62, 0.45, 0.78]
for (i, t) in titles.enumerated() {
    ctx.beginPDFPage(nil)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSColor(calibratedHue: hues[i], saturation: 0.18, brightness: 1, alpha: 1).setFill(); box.fill()
    NSColor(calibratedHue: hues[i], saturation: 0.7, brightness: 0.85, alpha: 1).setFill()
    NSRect(x: 0, y: 692, width: 612, height: 100).fill()
    (t as NSString).draw(at: NSPoint(x: 48, y: 720), withAttributes: [.font: NSFont.systemFont(ofSize: 34, weight: .bold), .foregroundColor: NSColor.white])
    ("\(i + 1)" as NSString).draw(at: NSPoint(x: 230, y: 300), withAttributes: [.font: NSFont.systemFont(ofSize: 180, weight: .heavy), .foregroundColor: NSColor(calibratedHue: hues[i], saturation: 0.6, brightness: 0.75, alpha: 0.9)])
    for l in 0..<9 { NSColor(white: 0.55, alpha: 0.35).setFill(); NSRect(x: 48, y: 620 - l * 26, width: l % 3 == 2 ? 300 : 516, height: 9).fill() }
    ctx.endPDFPage()
}
ctx.closePDF()
SW
swiftc -O /tmp/yuzu-pdf.swift -o /tmp/yuzu-pdf && /tmp/yuzu-pdf $D/handbook.pdf
ls -la $D
