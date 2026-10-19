#!/bin/bash
# Builds a Release Yuzu.app into dist/, ad-hoc signed. Usage: scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project Yuzu.xcodeproj -scheme Yuzu -configuration Release \
  -derivedDataPath build/DerivedData -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build -quiet 2>&1 | grep -v '^$' || true
APP=build/DerivedData/Build/Products/Release/Yuzu.app
[ -d "$APP" ] || { echo "build failed"; exit 1; }
mkdir -p dist build/bin
rm -rf dist/Yuzu.app
cp -R "$APP" dist/
codesign --force --deep --options runtime --sign - dist/Yuzu.app
codesign --verify --strict dist/Yuzu.app && echo "signed: dist/Yuzu.app"
swiftc -O scripts/yuzuctl.swift -o build/bin/yuzuctl 2>/dev/null || true
