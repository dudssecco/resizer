#!/bin/bash
# Builds Resizer into build/Resizer.app
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Resizer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Universal binary: runs on Apple Silicon (arm64) and Intel (x86_64) Macs
TMP=$(mktemp -d)
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library \
    -target "$ARCH-apple-macos13.0" \
    Sources/*.swift \
    -o "$TMP/Resizer-$ARCH"
done
lipo -create "$TMP/Resizer-arm64" "$TMP/Resizer-x86_64" -output "$APP/Contents/MacOS/Resizer"
rm -rf "$TMP"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Resizer</string>
  <key>CFBundleDisplayName</key><string>Resizer</string>
  <key>CFBundleIdentifier</key><string>io.github.dudssecco.Resizer</string>
  <key>CFBundleExecutable</key><string>Resizer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

[ -f Resources/AppIcon.icns ] || ./tools/make_icns.sh
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature (required for the Accessibility permission to work)
codesign --force --deep --sign - "$APP"

echo "✅ Built: $(pwd)/$APP"

# ./build.sh --install  → copies to /Applications and launches it
if [ "${1:-}" = "--install" ]; then
  pkill -f "Resizer.app/Contents/MacOS/Resizer" || true
  rm -rf /Applications/Resizer.app
  ditto "$APP" /Applications/Resizer.app
  open /Applications/Resizer.app
  echo "✅ Installed to /Applications/Resizer.app"
fi

# ./build.sh --release  → creates dist/Resizer.zip for GitHub Releases
if [ "${1:-}" = "--release" ]; then
  mkdir -p dist
  rm -f dist/Resizer.zip
  ditto -c -k --keepParent "$APP" dist/Resizer.zip
  echo "✅ dist/Resizer.zip"
fi
