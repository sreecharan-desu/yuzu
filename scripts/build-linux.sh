#!/bin/bash
# builds the linux cli (yuzu) and packs dist/yuzu-<version>-linux-<arch>.tar.gz and a .deb.
# usage: scripts/build-linux.sh [--skip-tests]
# needs a swift toolchain (swiftly or swift.org tarball). the mac app uses scripts/build.sh instead.
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
arch=$(uname -m)
debarch=$([ "$arch" = x86_64 ] && echo amd64 || echo arm64)

[ "${1:-}" = "--skip-tests" ] || swift test
swift build -c release --static-swift-stdlib --product yuzu
bin=$(swift build -c release --show-bin-path)/yuzu
strip "$bin" 2>/dev/null || true

stage=build/linux/yuzu-$version-linux-$arch
rm -rf build/linux && mkdir -p "$stage/bin" "$stage/share/applications" "$stage/share/icons/hicolor/512x512/apps" "$stage/share/yuzu" dist
cp "$bin" "$stage/bin/yuzu"
cp linux/packaging/yuzu.desktop "$stage/share/applications/"
cp linux/packaging/yuzu.png "$stage/share/icons/hicolor/512x512/apps/yuzu.png"
cp linux/packaging/nautilus-script "$stage/share/yuzu/"
cp linux/packaging/install.sh LICENSE "$stage/"
"$stage/bin/yuzu" --version

tarball=dist/yuzu-$version-linux-$arch.tar.gz
tar -C build/linux -czf "$tarball" "yuzu-$version-linux-$arch"

if command -v dpkg-deb >/dev/null 2>&1; then
  deb=build/linux/deb
  mkdir -p "$deb/DEBIAN" "$deb/usr/bin" "$deb/usr/share/applications" "$deb/usr/share/icons/hicolor/512x512/apps" "$deb/usr/share/yuzu"
  cp "$bin" "$deb/usr/bin/yuzu"
  cp linux/packaging/yuzu.desktop "$deb/usr/share/applications/"
  cp linux/packaging/yuzu.png "$deb/usr/share/icons/hicolor/512x512/apps/"
  cp linux/packaging/nautilus-script "$deb/usr/share/yuzu/"
  cat > "$deb/DEBIAN/control" <<CTL
Package: yuzu
Version: $version
Architecture: $debarch
Maintainer: Sreecharan Desu <noreply@github.com>
Depends: libc6, libstdc++6
Recommends: ffmpeg, imagemagick, pandoc, poppler-utils, zip, unzip, zenity | kdialog, libnotify-bin
Suggests: libreoffice-core
Section: utils
Priority: optional
Homepage: https://github.com/sreecharan-desu/yuzu
Description: convert files and save the result next to the original
 command line and file manager front end for yuzu on linux.
CTL
  dpkg-deb --root-owner-group --build "$deb" "dist/yuzu_${version}_${debarch}.deb" >/dev/null
fi

(cd dist && sha256sum yuzu-*.tar.gz yuzu_*.deb 2>/dev/null > yuzu-linux.sha256 || true)
ls -l dist/
