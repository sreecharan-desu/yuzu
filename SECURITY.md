# Security Policy

## Supported versions

| Version | Supported |
| ------- | --------- |
| 1.0.x   | Yes       |

## Reporting a vulnerability

Please don't open a public issue for security problems. Report them privately with
[GitHub's private vulnerability reporting](https://github.com/sreecharan-desu/yuzu/security/advisories/new).

Include the Yuzu and macOS versions, steps to reproduce, and the impact you see. You should get a reply
within a week, and we'll keep you posted while a fix is prepared.

## Scope

Yuzu processes files locally and has no network code. Of particular interest are issues where a crafted
file could make Yuzu or one of the helpers it runs (ffmpeg, cwebp, exiftool, LibreOffice) write outside
the folder of the original file, overwrite an existing file, or run unexpected commands.
