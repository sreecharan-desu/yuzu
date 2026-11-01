#!/bin/sh
# installs yuzu for the current user into ~/.local (no sudo).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
prefix=${PREFIX:-$HOME/.local}
install -Dm755 "$here/bin/yuzu" "$prefix/bin/yuzu"
install -Dm644 "$here/share/applications/yuzu.desktop" "$prefix/share/applications/yuzu.desktop"
install -Dm644 "$here/share/icons/hicolor/512x512/apps/yuzu.png" "$prefix/share/icons/hicolor/512x512/apps/yuzu.png"
if [ -d "$HOME/.local/share/nautilus" ] || command -v nautilus >/dev/null 2>&1; then
  install -Dm755 "$here/share/yuzu/nautilus-script" "$HOME/.local/share/nautilus/scripts/Convert with Yuzu"
fi
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$prefix/share/applications" || true
echo "installed yuzu to $prefix/bin/yuzu"
case ":$PATH:" in *":$prefix/bin:"*) ;; *) echo "add $prefix/bin to PATH to run yuzu from a terminal";; esac
"$prefix/bin/yuzu" doctor || true
