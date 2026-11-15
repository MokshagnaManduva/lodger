#!/bin/bash
# Assemble Lodger.app without Xcode.
#
# Command Line Tools has no xcodebuild, and a hand-assembled bundle is enough for
# everything that matters here: a real Info.plist (so LSUIElement is set at launch
# rather than only at runtime), a Resources/Packs directory for the bundled default
# character, and a signature so macOS will run it.
#
# Distribution still needs a Developer ID and notarisation; this is for running and
# testing the real thing locally.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME=Lodger
BUNDLE_ID=com.mokshagna.lodger
VERSION=$(tr -d '\n' < VERSION)
OUT=${1:-build}
APP="$OUT/$NAME.app"
SPARKLE_FEED_URL=${SPARKLE_FEED_URL:-}
export SPARKLE_FEED_URL

echo "building release binary"
(cd Engine && swift build -c release >/dev/null)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Packs"
cp Engine/.build/release/lodger "$APP/Contents/MacOS/$NAME"
cp LICENSE CREDITS.md "$APP/Contents/Resources/"

# Build the standard macOS icon sizes from the project-owned branding source.
ICON_SOURCE="Assets/Branding/lodger-icon.png"
ICONSET="$OUT/lodger.iconset"
if [ -f "$ICON_SOURCE" ]; then
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil --convert icns "$ICONSET" --output "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <!-- No Dock icon, no app switcher entry. Set here as well as at runtime so the
       bundle behaves correctly from the very first frame. -->
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
python3 Scripts/configure-bundle.py "$APP/Contents/Info.plist"

# The bundled default character. Loaded through the identical code path as an
# installed one - see CLAUDE.md 8a.
if [ -f Packs/klien/pack.json ]; then
  rsync -a --exclude 'reference' Packs/klien/ "$APP/Contents/Resources/Packs/klien/"
fi

# Ad-hoc signature so macOS will launch it.
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"
echo "signed ad-hoc"

echo "built $APP"
/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP/Contents/Info.plist" >/dev/null \
  && echo "  LSUIElement set"
du -sh "$APP" | awk '{print "  bundle size: "$1}'
ls "$APP/Contents/Resources/Packs" 2>/dev/null | sed 's/^/  bundled pack: /'
