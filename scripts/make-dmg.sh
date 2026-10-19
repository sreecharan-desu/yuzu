#!/bin/bash
# Packages dist/Yuzu.app into a styled, compressed disk image.
# Usage: scripts/make-dmg.sh [output.dmg]   (default: dist/Yuzu.dmg)
# Uses create-dmg for the image, icon and Applications link, but skips its Finder AppleScript step
# (which opens a window and takes focus); the Finder layout is written directly with ds_store instead.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-dist/Yuzu.dmg}"
APP=dist/Yuzu.app
[ -d "$APP" ] || { echo "missing $APP; run scripts/build.sh first"; exit 1; }
command -v create-dmg >/dev/null || { echo "create-dmg not found: brew install create-dmg"; exit 1; }

WORK=build/dmg
mkdir -p "$WORK"
swift scripts/make-dmg-background.swift "$WORK" >/dev/null
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" >/dev/null 2>&1
[ -x build/dmgvenv/bin/python ] || { python3 -m venv build/dmgvenv && build/dmgvenv/bin/pip install -q ds_store mac_alias; }

rm -rf "$WORK/src" "$WORK/Yuzu-rw.dmg" "$WORK/Yuzu-c.dmg"
mkdir -p "$WORK/src"
cp -R "$APP" "$WORK/src/"

create-dmg --volname Yuzu --volicon "$APP/Contents/Resources/AppIcon.icns" \
  --background "$WORK/background.tiff" --window-pos 200 160 --window-size 660 400 --icon-size 112 \
  --icon Yuzu.app 170 200 --hide-extension Yuzu.app --app-drop-link 490 200 \
  --skip-jenkins --no-internet-enable "$WORK/Yuzu-c.dmg" "$WORK/src" >/dev/null
hdiutil convert "$WORK/Yuzu-c.dmg" -format UDRW -o "$WORK/Yuzu-rw.dmg" -quiet
rm -f "$WORK/Yuzu-c.dmg"

MNT=$(hdiutil attach -nobrowse -noautoopen -readwrite "$WORK/Yuzu-rw.dmg" | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)
[ -d "$MNT/.background" ] || { mkdir -p "$MNT/.background"; cp "$WORK/background.tiff" "$MNT/.background/"; }
[ -f "$MNT/.background/background.tiff" ] || cp "$WORK/background.tiff" "$MNT/.background/background.tiff"
build/dmgvenv/bin/python scripts/dmg-layout.py "$MNT" >/dev/null
SetFile -a C "$MNT" 2>/dev/null || true
sync
hdiutil detach "$MNT" -quiet || hdiutil detach "$MNT" -force -quiet

rm -f "$OUT"
hdiutil convert "$WORK/Yuzu-rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT" -quiet
rm -f "$WORK/Yuzu-rw.dmg"
shasum -a 256 "$OUT" | awk '{print $1}' > "$OUT.sha256"
echo "dmg: $OUT ($(du -h "$OUT" | cut -f1)) sha256 $(cat "$OUT.sha256")"
