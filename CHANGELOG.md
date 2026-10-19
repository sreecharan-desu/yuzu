# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned for 1.1
- More conversion paths: image to DOCX, Pages, Keynote and Numbers export, RAR extraction.
- Collage, video snapshot, export GIF tool, audio visualizer and trim silence.
- Dragging several Float items out at once, rubber-band selection and Quick Look in Float.

## [1.0.0] - 2026-10-19

### Added
- Convert, Tools and Actions rings that open at the pointer when a modifier key is tapped during a file drag.
- About 270 conversion paths across images, video, audio, documents, slides, sheets, subtitles and archives.
- 26 tools, including crop, edit photo, annotate, redact, add background with a screenshot mode and
  20 original backdrops, metadata, read QR, make, merge, split and organize PDF, trim, speed, split,
  mute, join, bleep, normalize, channels, crop video and compress.
- Actions: AirDrop, Float, Copy, Copy Path, Move and Open in Terminal.
- Float, a shelf for files that snaps to screen edges as a glass tab and lets you drag files out.
- A short welcome window that explains the three keys and checks the optional Homebrew helpers.
- A shortcut recorder for each ring in Settings.
- Parallel multi-file jobs (images 4 at a time, media 2, Office files 1) with ordered results and cancel.
- A styled disk image with an Applications shortcut.

### Performance
- The ring is on screen within the first display refresh after the key tap (median 8.8 ms on an M1 MacBook Air).
- Native image output decodes once and skips needless flattening: large JPEG to HEIC about 2x faster,
  HEIC to JPEG about 4x faster, WebP about 2x faster.
- Quick Look thumbnails are cached.

[Unreleased]: https://github.com/sreecharan-desu/yuzu/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/sreecharan-desu/yuzu/releases/tag/v1.0.0
