<p align="center">
  <img src="docs/icon.png" width="112" height="112" alt="yuzu icon">
</p>

<h1 align="center">yuzu</h1>

<p align="center">
  convert, edit and act on files, <i>right</i> at your pointer.<br>
  drag a file, tap a key, release on what you want.
</p>

<p align="center">
  <a href="https://github.com/sreecharan-desu/yuzu/releases/latest/download/Yuzu.dmg"><img alt="download" src="https://img.shields.io/github/v/release/sreecharan-desu/yuzu?label=download&color=1d1d1f"></a>
  <a href="https://github.com/sreecharan-desu/yuzu/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/sreecharan-desu/yuzu/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-black">
  <img alt="Intel and Apple Silicon" src="https://img.shields.io/badge/Intel%20%26%20Apple%20Silicon-universal-black">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-blue"></a>
</p>

<p align="center">
  <img src="docs/hero.jpg" width="100%" alt="the convert ring open under the pointer on a quiet desktop, with a saved confirmation below">
</p>

yuzu is a small, native menu bar app for macOS 13 and later, on Intel and Apple Silicon.
while you drag any file, tap a modifier key and a ring opens under the pointer with what you
can do with that file. drop on an option and the result is saved next to the original. nothing
is uploaded anywhere.

## features

- **three rings, three keys.** shift converts, command opens tools, control runs actions. every key is
  configurable in settings with a shortcut recorder.
- **convert almost anything** (about 270 source and target pairs):
  - images: JPG, PNG, HEIC, WebP, AVIF, TIFF, GIF, BMP, PDF, SVG input
  - video: MP4, MOV, MKV, WebM, AVI, WMV, animated GIF, plus audio extraction
  - audio: MP3, M4A, WAV, FLAC, AIFF, OGG, opus, WMA
  - documents, slides and sheets: DOCX, DOC, RTF, ODT, EPUB, HTML, markdown, TXT, PDF, PPTX, ODP, XLSX, ODS, CSV, TSV
  - subtitles (SRT and VTT) and archives (ZIP, TAR, TGZ, extract)
- **26 tools.** compress, resize, half size, rotate, flip, crop, edit photo, annotate, redact, add
  background (including a screenshot mode with eight quiet backdrops and social ratios), metadata
  viewer and editor, read QR codes, make PDF, merge, split and organize PDF pages, trim, speed,
  split, mute, join, bleep, normalize, channels, crop video, and compress video, audio and PDF.
- **actions.** AirDrop, float, copy, copy path, move, open in terminal.
- **float.** a shelf for files. drop files on it, drag them out to any app, and park it on a screen
  edge as a small glass tab that opens on hover.
- **fast.** in a local benchmark on an M1 MacBook Air the ring was on screen within the first display
  refresh after the key tap (median 8.8 ms; raw output not committed yet), multi-file jobs run in parallel, and image conversions use ImageIO directly.
- **light.** about 0.1% CPU and 75 MB of memory when idle on the same machine.

<p align="center">
  <img src="docs/screenshots/ring-tools-light.jpg" width="49%" alt="tools ring in light mode">
  <img src="docs/screenshots/ring-actions-dark.jpg" width="49%" alt="actions ring in dark mode">
</p>
<p align="center">
  <img src="docs/screenshots/add-background.jpg" width="49%" alt="add background framing a screenshot on the pearl backdrop">
  <img src="docs/screenshots/float.jpg" width="49%" alt="float shelf docked to the right edge, with the parked tab on the left">
</p>

## install

1. [download **Yuzu.dmg**](https://github.com/sreecharan-desu/yuzu/releases/latest/download/Yuzu.dmg).
2. open it and drag **yuzu** into **applications**.

<p align="center"><img src="docs/screenshots/dmg-window.png" width="62%" alt="the yuzu disk image window: drag yuzu to applications"></p>

3. open yuzu from applications. it's ad-hoc signed, not notarized, so the first time macOS will say it
   can't verify the developer:
   - open **system settings > privacy & security**, scroll to the message about yuzu, click **open anyway**, and confirm.
   - or right-click yuzu in applications, choose **open**, then **open**.
4. yuzu appears in the menu bar and shows a short welcome.

you can check the download against the `Yuzu.dmg.sha256` file on the release page:

```sh
shasum -a 256 ~/Downloads/Yuzu.dmg
```


### optional helpers

images, PDFs and most tools work with nothing extra. video, audio, WebP and office formats use
well-known command line tools from [homebrew](https://brew.sh):

```sh
brew install ffmpeg webp exiftool
brew install --cask libreoffice   # optional, for Word, PowerPoint and Excel files
```

the welcome window and **settings > about** show which helpers yuzu found.

## using yuzu

| while dragging a file, tap | ring | what you get |
| --- | --- | --- |
| shift (⇧) | convert | formats the file can become |
| command (⌘) | tools | edits and tools for that kind of file |
| control (⌃) | actions | AirDrop, float, copy, move, terminal |

- keep holding the mouse button, move onto an option, release to run it. release anywhere else to cancel.
- tap a different key while the ring is open to switch rings.
- results are saved next to the original with a new name. originals are never changed.
- change the keys in **settings > shortcuts**: click a shortcut, press the modifier keys you want, release.

<p align="center"><img src="docs/screenshots/onboarding.jpg" width="80%" alt="welcome window"></p>

### permissions

yuzu watches for a modifier key tap during a file drag. it doesn't read your keystrokes and
needs no special permission for that. AirDrop and login items use the standard macOS prompts.

## privacy

everything runs on your mac. yuzu has no accounts, no analytics, no telemetry and no network code.
files are processed locally with apple frameworks (ImageIO, AVFoundation, PDFKit, vision) and the
optional helpers you install yourself.

## build from source

requirements: macOS 13 or later to run the app. building needs xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen). `scripts/build.sh` produces one universal app (Intel and Apple Silicon).

```sh
brew install xcodegen
git clone https://github.com/sreecharan-desu/yuzu.git
cd yuzu
scripts/build.sh          # universal Release build, ad-hoc signed, into dist/Yuzu.app
open dist/Yuzu.app
```

to make the disk image as well:

```sh
brew install create-dmg
scripts/make-dmg.sh       # dist/Yuzu.dmg and dist/Yuzu.dmg.sha256
```

test fixtures are generated, not stored: `scripts/make-fixtures.sh` builds one small file per
supported format (needs ffmpeg and LibreOffice), and `scripts/validate.swift` checks a batch report.

## project layout

```
Yuzu/App        app delegate, menu bar, welcome window, login item
Yuzu/Drag       drag and modifier tap detection
Yuzu/Wheel      the ring: model, view, geometry, thumbnail cache
Yuzu/Catalog    what each file kind can become or do
Yuzu/Jobs       conversion engines and the parallel job runner
Yuzu/Tools      tool panels and editors
Yuzu/Float      the Float shelf
Yuzu/HUD        progress and result toasts
Yuzu/Settings   preferences and the shortcut recorder
scripts/        build, disk image, icon and fixture scripts
```

## contributing

bug reports, ideas and pull requests are welcome. see [CONTRIBUTING.md](CONTRIBUTING.md) and the
[changelog](CHANGELOG.md). please report security issues privately as described in [SECURITY.md](SECURITY.md).

## license

[MIT](LICENSE)

---

built by [sreecharan desu](https://www.sreecharandesu.in) · [more projects](https://www.sreecharandesu.in/work)
