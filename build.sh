#!/bin/bash
set -eu
cd "$(dirname "$0")"
build=$(mktemp -d "${TMPDIR:-/tmp}/dock-signal.XXXXXX")
app="$build/Dock Signal.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$build/Signal.iconset"
cp Info.plist "$app/Contents/"
xcrun swiftc -swift-version 5 -O -target "$(uname -m)-apple-macosx14.0" Sources/*.swift -o "$app/Contents/MacOS/DockSignal"
"$app/Contents/MacOS/DockSignal" --icon "$build/icon.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$build/icon.png" --out "$build/Signal.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((2 * size))
    sips -z "$double" "$double" "$build/icon.png" --out "$build/Signal.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$build/Signal.iconset" -o "$app/Contents/Resources/Signal.icns"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
echo "$app"
