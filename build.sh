#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIGURATION="${1:-release}"
APP="dist/Sendpoint.app"

swift build -c "$CONFIGURATION" --product Sendpoint
BIN_DIR=$(swift build -c "$CONFIGURATION" --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Sendpoint" "$APP/Contents/MacOS/Sendpoint"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD 2>/dev/null || echo 1)" "$APP/Contents/Info.plist"

# A stable identity keeps the Accessibility grant across rebuilds; ad-hoc loses it.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F '"' '/Developer ID Application|Apple Development/ { print $2; exit }')}"
codesign --force --options runtime --timestamp=none \
    --entitlements Resources/Sendpoint.entitlements --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"
