#!/bin/bash
# Builds Iliad.app via SwiftPM (so SwiftTerm + its Metal/resource bundles build correctly).
set -e
cd "$(dirname "$0")"

APP="Iliad.app"
CONTENTS="$APP/Contents"; MACOS="$CONTENTS/MacOS"; RES="$CONTENTS/Resources"

echo "› swift build (release)"
swift build -c release

echo "› assembling bundle"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"
BINDIR=".build/release"
cp "$BINDIR/Iliad" "$MACOS/Iliad"
# resource bundles (fonts in Iliad_Iliad.bundle, SwiftTerm metallib etc.)
cp -R "$BINDIR"/*.bundle "$RES"/ 2>/dev/null || true
cp Info.plist "$CONTENTS/Info.plist"

echo "› generating icon"
ICONSET="Iliad.iconset"; rm -rf "$ICONSET"; mkdir "$ICONSET"
SRC="Resources/icon.png"
gen() { sips -z "$1" "$1" "$SRC" --out "$ICONSET/$2" >/dev/null; }
gen 16 icon_16x16.png;     gen 32 icon_16x16@2x.png
gen 32 icon_32x32.png;     gen 64 icon_32x32@2x.png
gen 128 icon_128x128.png;  gen 256 icon_128x128@2x.png
gen 256 icon_256x256.png;  gen 512 icon_256x256@2x.png
gen 512 icon_512x512.png;  gen 1024 icon_512x512@2x.png
iconutil -c icns "$ICONSET" -o "$RES/Iliad.icns"
rm -rf "$ICONSET"

echo "› signing (ad-hoc)"
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✓ built $APP"
