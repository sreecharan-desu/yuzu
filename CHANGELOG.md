# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- New identity: the Ring mark, in ink and pearl, with a matching menu bar glyph.
- A design system for every surface: ink on white (inverted in dark mode), three neutral steps,
  hairline borders, an 8 pt grid, three radii plus pills, one type scale, shadow and motion tokens.
- The ring, toasts, tool panels, Add Background, Float, the welcome window and Settings now use it.
  Yuzu yellow appears only as a small hover or selection detail.
- Primary buttons are ink pills with a slow, restrained hover; panel content arrives with a short
  blur-to-sharp reveal (off when Reduce Motion is on).
- Backdrops: a curated set of eight (Pearl, Mist, Linen, Haze, Stone, Graphite, Ink, Match) replaces
  the 19 mesh, bokeh and frost styles. Saved styles that used a removed backdrop map to the closest one.
- Quieter colour swatches and gradients in Add Background, and a minimal disk image background.

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
