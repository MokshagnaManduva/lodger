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
VERSION=$(python3 -c "import json;print(json.load(open('Packs/klien/pack.json'))['identity']['version'])" 2>/dev/null || echo 0.1.0)
OUT=${1:-build}
APP="$OUT/$NAME.app"

echo "building release binary"
(cd Engine && swift build -c release >/dev/null)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Packs"
cp Engine/.build/release/lodger "$APP/Contents/MacOS/$NAME"

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
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <!-- No Dock icon, no app switcher entry. Set here as well as at runtime so the
       bundle behaves correctly from the very first frame. -->
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <!-- Shown in the Accessibility prompt, which is requested only when the user
       drops the character onto a window. -->
  <key>NSAccessibilityUsageDescription</key>
  <string>Lodger needs Accessibility only to follow the one window you place your character on.</string>
</dict>
</plist>
PLIST

# The bundled default character. Loaded through the identical code path as an
# installed one - see CLAUDE.md 8a.
if [ -f Packs/klien/pack.json ]; then
  rsync -a --exclude 'reference' Packs/klien/ "$APP/Contents/Resources/Packs/klien/"
fi

# Ad-hoc signature so macOS will launch it. Note: an ad-hoc signature is not stable
# across rebuilds, so a granted Accessibility permission may need re-granting after
# each build. A Developer ID signature fixes that.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 \
  && echo "signed ad-hoc" || echo "could not sign (the app may refuse to launch)"

echo "built $APP"
/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP/Contents/Info.plist" >/dev/null \
  && echo "  LSUIElement set"
du -sh "$APP" | awk '{print "  bundle size: "$1}'
ls "$APP/Contents/Resources/Packs" 2>/dev/null | sed 's/^/  bundled pack: /'
