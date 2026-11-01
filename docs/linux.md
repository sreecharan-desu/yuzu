# yuzu on linux

notes on how the linux build is put together and why.

## what yuzu does on the mac

yuzu is a menu bar app (LSUIElement, no dock icon). while you drag a file anywhere on screen and tap a
modifier key, a ring of options opens under the pointer. dropping on an option runs it and saves the
result next to the original, never overwriting.

- convert ring (shift): about 270 source and target pairs across images, video, audio, documents,
  slides, sheets, subtitles and archives.
- tools ring (command): 26 tools, such as compress, resize, crop, edit photo, annotate, redact, add
  background, metadata, read QR, make/merge/split/organize PDF, trim, speed, split, mute, join,
  bleep, normalize, channels, compress video and audio.
- actions ring (control): airdrop, float, copy, copy path, move, open in terminal.
- float: a shelf window for files that can park on a screen edge.
- progress HUD, welcome window, settings (shortcut recorder, login item), all local.

platform apis it leans on:

- AppKit and SwiftUI for every window: NSStatusItem (menu bar), borderless NSPanel for the ring, HUD,
  float, tool panels, settings.
- global drag and key monitoring through NSEvent monitors and the drag pasteboard (DragMonitor).
- ImageIO, CoreImage, CoreGraphics and PDFKit for images and PDFs, Vision for QR codes,
  QuickLookThumbnailing for petal thumbnails, AVFoundation for some media.
- NSSharingService for airdrop, ServiceManagement for the login item, Apple Events to drive Pages,
  Keynote and Numbers, UniformTypeIdentifiers for file types.
- external engines it finds on the mac (ffmpeg, cwebp, exiftool, soffice), nothing bundled.

## why the mac app can't just run on linux

AppKit, SwiftUI, ImageIO, CoreImage, PDFKit, Vision, QuickLook, AVFoundation and ServiceManagement are
closed apple frameworks that only ship with macOS. swift on linux comes with the standard library,
Foundation (swift-corelibs-foundation) and XCTest, nothing else. there is no NSApplication, NSPanel or
NSEvent to link against, so any file that imports AppKit or SwiftUI won't compile there. the
"drag a file, tap a key, ring under the pointer" interaction also depends on global input monitoring,
which on linux differs between X11 and wayland (wayland does not let an app watch global drags or
draw over the pointer at all), so it can't be a straight port either.

## options looked at

1. **one swift codebase: swiftpm package for the linux build, sharing foundation-only files with the
   mac app, plus a small linux front end.** keeps the language, the naming rules and the catalog in one
   repo. no new runtime. the mac project (project.yml) is untouched.
2. **a separate port** in tauri/rust or python+gtk that copies the behaviour. better gui options on
   linux, but it is a second codebase where every format table, naming rule and bug fix has to be done
   twice, in a different language, with a second toolchain in ci.
3. **a full gtk front end in swift** (for example through a gtk4 or appindicator binding). possible,
   but the swift gtk bindings are small community projects, a tray icon behaves differently on every
   desktop (gnome needs an extension for appindicator), and the ring interaction can't work on wayland
   anyway. too much risk for a first release.

chosen: option 1. it keeps one codebase, does not change the mac app, and is realistic to ship and keep
working. a gui ring can come later on top of the same core if it proves worth it.

## how it is laid out

- `Package.swift` (repo root): swiftpm package used only by the linux build. xcodegen and
  `scripts/build.sh` ignore it; the mac app is still built from `project.yml`.
- `linux/Sources/YuzuLinuxCore/Shared/`: symlinks to `Yuzu/Jobs/OutputNamer.swift` and
  `Yuzu/Jobs/Markdown.swift`. both only import Foundation, so the mac app and the linux build compile
  the exact same files (never-overwrite naming, markdown to html).
- `linux/Sources/YuzuLinuxCore/`: file kinds and targets mirroring `Yuzu/Catalog/Catalog.swift`,
  subtitle parsing with the same rules as `SubtitleEngine`, a planner that turns (file, target) into
  the external command to run, and a runner.
- `linux/Sources/yuzu/`: the `yuzu` command (`convert`, `targets`, `pick`, `doctor`).
- `linux/Tests/`: xctest tests for the core, run with `swift test` on linux (and on the mac).
- `linux/packaging/`: desktop entry (shows yuzu in "open with" for supported types), a nautilus
  script, an icon and a per-user `install.sh`.
- `scripts/build-linux.sh`: tests, builds a release binary with the swift runtime statically linked,
  and writes `dist/yuzu-<version>-linux-<arch>.tar.gz`, `dist/yuzu_<version>_<arch>.deb` and
  `dist/yuzu-linux.sha256`.

engines on linux come from the distro, same idea as homebrew on the mac: ffmpeg (video and audio),
imagemagick (images), pandoc (documents), libreoffice (office files and pdf export), poppler-utils
(pdf to text and page images), zip, unzip and tar. subtitles, markdown to html and csv/tsv are done in
swift with no tools at all. `yuzu doctor` lists what was found.

## front end

- `yuzu convert <files> --to <format>` for terminals and scripts.
- `yuzu pick <files>` opens a zenity (gnome) or kdialog (kde) list of formats the files share, runs
  the conversion, and posts a desktop notification with notify-send.
- the desktop entry runs `yuzu pick %F`, so "open with > yuzu" in any file manager works, and the
  nautilus script adds "scripts > convert with yuzu" to the right click menu in gnome files.

## known limits

- no drag ring, no menu bar or tray icon, no float shelf, no HUD. linux gets conversions only.
- no tools ring yet (crop, annotate, trim and so on). the planner is the place to add the
  non-interactive ones (compress, mute, normalize, rotate) next.
- no actions ring (airdrop is mac only; copy and move are already the file manager's job).
- iWork formats (pages, keynote, numbers) are mac only. heic input needs an imagemagick built with
  libheif. pdf to docx goes through libreoffice and is rough. pdf to pptx, xlsx, epub and md are not
  offered.
- the release binary needs glibc at least as new as the ci runner's (ubuntu-latest). older distros
  should build from source.
- not tested on arm64 linux yet; ci builds x86_64 only.
