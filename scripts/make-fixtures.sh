#!/bin/bash
# Builds one small test file per supported source format into TestFiles/formats.
# Uses ffmpeg, textutil, LibreOffice (private profile) and zip/tar. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=TestFiles/formats
rm -rf "$OUT"; mkdir -p "$OUT"
FF=/opt/homebrew/bin/ffmpeg
SO=/opt/homebrew/bin/soffice
PROFILE="file://$PWD/build/lo-fixtures-profile"
so() { "$SO" "-env:UserInstallation=$PROFILE" --headless --norestore --nolockcheck "$@" >/dev/null 2>&1; }
export COPYFILE_DISABLE=1

# Video and audio (3 seconds)
V=(-f lavfi -i testsrc2=size=640x360:rate=30:duration=3 -f lavfi -i sine=f=523:d=3)
$FF -v error -y "${V[@]}" -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest $OUT/clip.mp4
$FF -v error -y "${V[@]}" -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest $OUT/clip-mov.mov
$FF -v error -y "${V[@]}" -c:v libx264 -c:a flac -shortest $OUT/clip-mkv.mkv
$FF -v error -y "${V[@]}" -c:v libvpx-vp9 -deadline realtime -c:a libopus -shortest $OUT/clip-webm.webm
$FF -v error -y "${V[@]}" -c:v mpeg4 -c:a libmp3lame -shortest $OUT/clip-avi.avi
A=(-f lavfi -i sine=f=440:d=3)
$FF -v error -y "${A[@]}" $OUT/tone-wav.wav
$FF -v error -y "${A[@]}" -c:a libmp3lame $OUT/tone-mp3.mp3
$FF -v error -y "${A[@]}" -c:a flac $OUT/tone-flac.flac
$FF -v error -y "${A[@]}" -c:a aac $OUT/tone-m4a.m4a
$FF -v error -y "${A[@]}" -c:a vorbis -strict -2 -ac 2 $OUT/tone-ogg.ogg
$FF -v error -y "${A[@]}" -c:a libopus $OUT/tone-opus.opus
$FF -v error -y "${A[@]}" $OUT/tone-aiff.aiff

# Documents
cat > $OUT/doc-html.html <<'H'
<!DOCTYPE html><html><head><meta charset="utf-8"><title>Yuzu field notes</title></head><body>
<h1>Yuzu field notes</h1>
<p>Yuzu is a <strong>citrus</strong> fruit with an <em>intensely fragrant</em> rind. See <a href="https://example.com/yuzu">the reference</a>.</p>
<h2>Where it grows</h2>
<ul><li>Japan, especially Kochi</li><li>Korea, where it is called yuja</li><li>China, its likely origin</li></ul>
<h2>Uses</h2>
<ol><li>Ponzu sauce</li><li>Yuzu kosho</li><li>Winter baths on the solstice</li></ol>
<p>Measured juice yield was 18% by weight, with café-style tasting notes &amp; a sharp finish.</p>
<pre>ratio = juice / weight</pre>
</body></html>
H
cat > $OUT/doc-md.md <<'M'
# Yuzu field notes

Yuzu is a **citrus** fruit with an *intensely fragrant* rind. See [the reference](https://example.com/yuzu).

## Where it grows

- Japan, especially Kochi
- Korea, where it is called yuja
- China, its likely origin

## Uses

1. Ponzu sauce
2. Yuzu kosho

> Picked in late autumn.

```
ratio = juice / weight
```
M
printf 'Yuzu field notes\n\nYuzu is a citrus fruit with an intensely fragrant rind.\nIt grows in Japan, Korea and China.\n' > $OUT/doc-txt.txt
textutil -convert rtf $OUT/doc-html.html -output $OUT/doc-rtf.rtf
textutil -convert docx $OUT/doc-html.html -output $OUT/doc-docx.docx
textutil -convert odt $OUT/doc-html.html -output $OUT/doc-odt.odt
textutil -convert doc $OUT/doc-html.html -output $OUT/doc-doc.doc
# EPUB, built by hand with zip so the fixture does not depend on Yuzu itself
E=$(mktemp -d "$PWD/build/epub.XXXX"); mkdir -p $E/META-INF $E/OEBPS
printf 'application/epub+zip' > $E/mimetype
cat > $E/META-INF/container.xml <<'X'
<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
X
cat > $E/OEBPS/book.opf <<'X'
<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">yuzu-fixture</dc:identifier><dc:title>Yuzu fixture</dc:title><dc:language>en</dc:language><meta property="dcterms:modified">2026-10-19T00:00:00Z</meta></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/><item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/><itemref idref="c2"/></spine></package>
X
for i in 1 2; do cat > $E/OEBPS/c$i.xhtml <<X
<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter $i</title></head><body><h1>Chapter $i</h1><p>Yuzu chapter $i text with <strong>bold</strong> words.</p></body></html>
X
done
cat > $E/OEBPS/nav.xhtml <<'X'
<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Nav</title></head><body><nav epub:type="toc"><ol><li><a href="c1.xhtml">Chapter 1</a></li><li><a href="c2.xhtml">Chapter 2</a></li></ol></nav></body></html>
X
(cd $E && zip -X0q book.epub mimetype && zip -Xr9Dq book.epub META-INF OEBPS); mv $E/book.epub $OUT/doc-epub.epub; rm -rf $E

# PDF (multi-page) via LibreOffice from a long document
L=$(mktemp -d "$PWD/build/long.XXXX")
{ echo '<html><body><h1>Yuzu report</h1>'; for i in $(seq 1 60); do echo "<p>Paragraph $i. Yuzu juice is tart and aromatic, and the peel is used for zest, marmalade and seasoning. This line exists to fill the page.</p>"; done; echo '</body></html>'; } > $L/report.html
textutil -convert docx $L/report.html -output $L/report.docx
so --convert-to pdf --outdir $L $L/report.docx
cp $L/report.pdf $OUT/report-pdf.pdf

# Slides from the PDF
so --infilter=impress_pdf_import --convert-to odp --outdir $L $L/report.pdf
so --convert-to "pptx:Impress MS PowerPoint 2007 XML" --outdir $L $L/report.odp
cp $L/report.odp $OUT/deck-odp.odp; cp $L/report.pptx $OUT/deck-pptx.pptx
rm -rf $L

# Spreadsheets
printf 'fruit,origin,price,note\nyuzu,Kochi,4.50,"tart, aromatic"\nsudachi,Tokushima,3.20,"says ""zing"""\nkabosu,Oita,2.90,"two\nlines"\n' > $OUT/table-csv.csv
printf 'fruit\torigin\tprice\nyuzu\tKochi\t4.50\nsudachi\tTokushima\t3.20\n' > $OUT/table-tsv.tsv
S=$(mktemp -d "$PWD/build/sheet.XXXX"); cp $OUT/table-csv.csv $S/table.csv
so --infilter=CSV:44,34,76,1 --convert-to "xlsx:Calc MS Excel 2007 XML" --outdir $S $S/table.csv
so --infilter=CSV:44,34,76,1 --convert-to ods --outdir $S $S/table.csv
cp $S/table.xlsx $OUT/table-xlsx.xlsx; cp $S/table.ods $OUT/table-ods.ods; rm -rf $S

# Subtitles
printf '1\n00:00:01,000 --> 00:00:02,500\nHello from Yuzu.\n\n2\n00:00:03,000 --> 00:00:05,250\n<i>Second</i> line\nwith two rows.\n' > $OUT/subs-srt.srt
printf 'WEBVTT\n\n00:00:01.000 --> 00:00:02.500\nHello from Yuzu.\n\n00:03.000 --> 00:05.250 align:start\nSecond cue.\n' > $OUT/subs-vtt.vtt

# Folder and archives
F="$OUT/sample folder"; mkdir -p "$F/inner"
echo "alpha" > "$F/a.txt"; echo "beta" > "$F/b.txt"; echo "gamma" > "$F/inner/c.txt"
(cd "$OUT" && ditto -c -k --sequesterRsrc --keepParent "sample folder" bundle-zip.zip && tar --no-mac-metadata -cf bundle-tar.tar "sample folder" && tar --no-mac-metadata -czf bundle-tgz.tar.gz "sample folder")

ls -1 "$OUT" | wc -l | tr -d ' ' | xargs -I{} echo "{} fixtures in $OUT"
