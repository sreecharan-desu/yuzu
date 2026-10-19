#!/bin/bash
# Builds Yuzu/Resources/AppIcon.icns from a rendered logo master.
# Usage: scripts/icon.sh [option]   (a | b | c | cd; default cd = Ring on ink, the recommendation)
set -euo pipefail
cd "$(dirname "$0")/.."
OPT="${1:-cd}"
SRC="design/logo/icon-${OPT}-1024.png"
[ -f "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }
mkdir -p build/icon && cp "$SRC" build/icon/icon_1024.png
cd build/icon && rm -rf AppIcon.iconset && mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s icon_1024.png --out AppIcon.iconset/icon_${s}x${s}.png >/dev/null
  d=$((s*2)); sips -z $d $d icon_1024.png --out AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns AppIcon.iconset -o ../../Yuzu/Resources/AppIcon.icns
echo "icns updated from $SRC"
