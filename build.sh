#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

CONFIGURATION="${1:-debug}"
if [ "$#" -gt 1 ] || { [ "$CONFIGURATION" != debug ] && [ "$CONFIGURATION" != release ]; }; then
    echo "usage: ./build.sh [debug|release]" >&2
    exit 1
fi

APP_NAME="Sendpoint"
BIN_DIR=$(swift build -c "$CONFIGURATION" --show-bin-path)
DIST="dist/${APP_NAME}.app"
PLIST="${DIST}/Contents/Info.plist"
ENTITLEMENTS="Resources/Sendpoint.entitlements"

# Version comes from Resources/Info.plist (release.sh bumps it). The build
# number defaults to the commit count; release.sh can override it.
APP_VERSION="${APP_VERSION:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)}"
APP_BUILD="${APP_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

echo "==> Building ${APP_VERSION} (${APP_BUILD}) — ${CONFIGURATION}"
swift build -c "$CONFIGURATION" --product "$APP_NAME"

echo "==> Assembling ${DIST}"
rm -rf "$DIST"
mkdir -p "${DIST}/Contents/MacOS" "${DIST}/Contents/Resources"
cp "${BIN_DIR}/${APP_NAME}" "${DIST}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${PLIST}"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString ${APP_VERSION}" \
    -c "Set :CFBundleVersion ${APP_BUILD}" "${PLIST}"
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${DIST}/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${PLIST}" 2>/dev/null || true
fi

# A stable signing identity keeps the Accessibility grant across rebuilds.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITIES=$(security find-identity -v -p codesigning 2>/dev/null || true)
    IDENTITY=$(printf '%s\n' "$IDENTITIES" | awk -F '"' '
        /Developer ID Application/ && !developer { developer = $2 }
        /Apple Development/ && !development { development = $2 }
        END { print developer ? developer : development }
    ')
fi

# Keep the same app identity and entitlements during development. Only release
# builds need the network timestamp required for notarization.
IDENTITY="${IDENTITY:--}"
SIGN_FLAGS=(--force --options runtime --entitlements "$ENTITLEMENTS")
if [ "$IDENTITY" = "-" ]; then
    echo "==> Signing ad-hoc"
    echo "    (macOS may ask for approval and Accessibility again)"
else
    echo "==> Signing with: ${IDENTITY}"
fi
if [ "$CONFIGURATION" = release ] && [ "$IDENTITY" != "-" ]; then
    SIGN_FLAGS+=(--timestamp)
else
    SIGN_FLAGS+=(--timestamp=none)
fi
codesign "${SIGN_FLAGS[@]}" --sign "$IDENTITY" "$DIST"

codesign --verify --verbose=1 "${DIST}"
echo
echo "Built: ${DIST}"
echo "Install with: ./install.sh"
