#!/bin/bash
# Cut a distributable build, entirely from this Mac.
#
#   ./release.sh 1.2                         build, notarize, staple, DMG
#   ./release.sh 1.2 --publish               ...then publish on GitHub
#   ./release.sh 1.2 --ad-hoc                build without notarizing
#   ./release.sh 1.2 --ad-hoc --publish      ...then publish on GitHub
#   ./release.sh 1.2 --ad-hoc --resume-publish
#                                             resume upload/deploy after a failure
#
# --ad-hoc skips notarization and forces a true ad-hoc signature (`-`).
# Apple Development certificates only run on this Mac; other people need
# either this path or a paid Developer ID build. Ad-hoc signatures are
# pinned to the binary's hash, so Accessibility is re-prompted each release.
#
# Publishing also refreshes a hard-coded website download URL when present,
# commits it with the version bump, and deploys the site with wrangler. The
# current /download route resolves the latest GitHub DMG dynamically.
#
# One-time setup:
#   1. Sparkle's update-signing key is generated independently of Apple:
#        .build/artifacts/sparkle/Sparkle/bin/generate_keys
#      Keep the private key in Keychain and back it up securely. The matching
#      public key lives in Resources/Info.plist.
#   2. For a notarized release, install a "Developer ID Application" certificate
#      (Xcode → Settings → Accounts → Manage Certificates).
#   3. Store notarization credentials, using an app-specific password from
#      appleid.apple.com:
#        xcrun notarytool store-credentials sendpoint \
#            --apple-id you@example.com --team-id TEAMID
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${1:-}"
if [ -n "$VERSION" ]; then
    shift
fi

PUBLISH=false
AD_HOC=false
RESUME_PUBLISH=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --publish)
            PUBLISH=true
            ;;
        --ad-hoc|--adhoc)
            AD_HOC=true
            ;;
        --resume-publish)
            PUBLISH=true
            RESUME_PUBLISH=true
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "usage: ./release.sh VERSION [--ad-hoc] [--publish|--resume-publish]" >&2
            exit 1
            ;;
    esac
    shift
done

if [ -z "$VERSION" ]; then
    echo "usage: ./release.sh VERSION [--ad-hoc] [--publish|--resume-publish]" >&2
    exit 1
fi

if [ "$AD_HOC" = true ]; then
    # Public unnotarized builds must not pick up this Mac's Apple Development
    # certificate. build.sh still uses that cert for local ./build.sh installs.
    export CODESIGN_IDENTITY=-
fi

APP_NAME="Sendpoint"
APP="dist/${APP_NAME}.app"
ARCHIVE="dist/Sendpoint-${VERSION}.dmg"
LATEST_ARCHIVE="dist/Sendpoint.dmg"
CHECKSUM="${ARCHIVE}.sha256"
NOTARY_PROFILE="${NOTARY_PROFILE:-sendpoint}"
APPCAST="web/public/appcast.xml"
SPARKLE_TOOLS=".build/artifacts/sparkle/Sparkle/bin"

if [ "$AD_HOC" = false ]; then
    if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
        echo "No Developer ID Application certificate in the keychain." >&2
        echo "Use --ad-hoc now, or see the setup notes at the top of this script." >&2
        exit 1
    fi
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "No notarytool credentials under profile '${NOTARY_PROFILE}'." >&2
        echo "Create them with: xcrun notarytool store-credentials ${NOTARY_PROFILE} --apple-id you@example.com --team-id TEAMID" >&2
        exit 1
    fi
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Tracked files are not clean. Commit or stash them so the build matches a commit." >&2
    exit 1
fi
UNTRACKED_BUILD_INPUTS=$(git ls-files --others --exclude-standard -- Package.swift Package.resolved Sources Resources)
if [ -n "$UNTRACKED_BUILD_INPUTS" ]; then
    echo "Untracked app build inputs found:" >&2
    printf '%s\n' "$UNTRACKED_BUILD_INPUTS" >&2
    echo "Commit, ignore, or remove them so the build matches a commit." >&2
    exit 1
fi
if [ "$PUBLISH" = true ]; then
    if [ "$RESUME_PUBLISH" = false ] && \
       git rev-parse --verify --quiet "refs/tags/v${VERSION}" >/dev/null; then
        echo "Tag v${VERSION} already exists." >&2
        echo "Use --resume-publish only to finish a release this script already committed and tagged." >&2
        exit 1
    fi
    if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
        echo "Publishing needs an authenticated GitHub CLI (gh)." >&2
        exit 1
    fi
    # Capture first: with pipefail, grep -q closing the pipe early would
    # make a successful whoami look like a failure.
    WRANGLER_STATUS=$(cd web && npx --yes wrangler whoami 2>/dev/null || true)
    if ! grep -q "logged in" <<<"$WRANGLER_STATUS"; then
        echo "Publishing needs wrangler logged in to Cloudflare (cd web && npx wrangler login)." >&2
        exit 1
    fi
fi

SITE_PAGE="web/public/index.html"
DOWNLOAD_URL="https://github.com/saiashirwad/sendpoint/releases/download/v${VERSION}/Sendpoint-${VERSION}.dmg"

publish_github_release() {
    if gh release view "v${VERSION}" >/dev/null 2>&1; then
        echo "==> Replacing assets on existing GitHub release v${VERSION}"
        gh release upload "v${VERSION}" "$ARCHIVE" "$LATEST_ARCHIVE" "$CHECKSUM" --clobber
        return
    fi

    if [ "$AD_HOC" = true ]; then
        RELEASE_NOTES=$(printf '%s\n' \
            '> [!WARNING]' \
            '> This build is not notarized by Apple.' \
            '> Only open it if you trust this repository.' \
            '' \
            'Move **Sendpoint.app** to `/Applications` and try to open it once.' \
            'If macOS blocks it, open **System Settings > Privacy & Security**, scroll to **Security**, click **Open Anyway**, then confirm **Open**.')
        gh release create "v${VERSION}" "$ARCHIVE" "$LATEST_ARCHIVE" "$CHECKSUM" \
            --title "${APP_NAME} ${VERSION}" \
            --generate-notes \
            --notes "$RELEASE_NOTES"
    else
        gh release create "v${VERSION}" "$ARCHIVE" "$LATEST_ARCHIVE" "$CHECKSUM" \
            --title "${APP_NAME} ${VERSION}" \
            --generate-notes
    fi
}

if [ "$RESUME_PUBLISH" = true ]; then
    if [ "$(git rev-parse HEAD)" != "$(git rev-list -n 1 "v${VERSION}" 2>/dev/null || true)" ]; then
        echo "Resume requires HEAD to be the commit tagged v${VERSION}." >&2
        exit 1
    fi
    if ! git ls-remote --exit-code --tags origin "refs/tags/v${VERSION}" >/dev/null 2>&1; then
        echo "==> Pushing release commit and tag"
        git push --atomic origin HEAD "refs/tags/v${VERSION}"
    fi
    for required in "$ARCHIVE" "$LATEST_ARCHIVE" "$CHECKSUM" "$APPCAST"; do
        if [ ! -f "$required" ]; then
            echo "Cannot resume: ${required} is missing." >&2
            echo "Do not rebuild an already-tagged release; publish a new version instead." >&2
            exit 1
        fi
    done
    publish_github_release
    echo "==> Deploying the website"
    (cd web && npx --yes wrangler deploy)
    echo "Release v${VERSION} is published."
    exit 0
fi

echo "==> Stamping version ${VERSION}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" Resources/Info.plist
APP_BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
if [ "$PUBLISH" = true ]; then
    APP_BUILD=$((APP_BUILD + 1))
fi

if [ "$AD_HOC" = true ]; then
    echo "==> Building an unnotarized release"
fi
APP_BUILD="$APP_BUILD" ./build.sh release

if [ "$AD_HOC" = false ]; then
    echo "==> Notarizing"
    SUBMISSION="dist/notarize-submission.zip"
    ditto -c -k --keepParent "$APP" "$SUBMISSION"
    xcrun notarytool submit "$SUBMISSION" --keychain-profile "$NOTARY_PROFILE" --wait
    rm -f "$SUBMISSION"

    echo "==> Stapling"
    xcrun stapler staple "$APP"
    spctl -a -t exec -vv "$APP"
fi

echo "==> Creating ${ARCHIVE}"
DMG_ROOT=$(mktemp -d)
trap 'rm -rf "$DMG_ROOT"' EXIT
ditto "$APP" "${DMG_ROOT}/${APP_NAME}.app"
ln -s /Applications "${DMG_ROOT}/Applications"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$ARCHIVE"
rm -rf "$DMG_ROOT"
trap - EXIT
cp "$ARCHIVE" "$LATEST_ARCHIVE"
(
    cd dist
    shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")"
)

if [ "$PUBLISH" = true ]; then
    if [ ! -x "${SPARKLE_TOOLS}/generate_appcast" ]; then
        echo "Sparkle's generate_appcast tool is missing. Run: swift package resolve" >&2
        exit 1
    fi

    echo "==> Signing update and generating appcast"
    APPCAST_WORK=$(mktemp -d)
    trap 'rm -rf "$APPCAST_WORK"' EXIT
    cp "$ARCHIVE" "$APPCAST_WORK/"
    if [ -f "$APPCAST" ]; then
        cp "$APPCAST" "$APPCAST_WORK/appcast.xml"
    fi
    "${SPARKLE_TOOLS}/generate_appcast" \
        --download-url-prefix "https://github.com/saiashirwad/sendpoint/releases/download/v${VERSION}/" \
        --link "https://sendpoint.app" \
        --maximum-deltas 0 \
        -o "$APPCAST_WORK/appcast.xml" \
        "$APPCAST_WORK"
    cp "$APPCAST_WORK/appcast.xml" "$APPCAST"

    if grep -q 'href="/download"' "$SITE_PAGE"; then
        echo "==> Website uses the dynamic /download route"
    else
        echo "==> Pointing the website at ${DOWNLOAD_URL}"
        sed -i '' -E "s#https://github.com/saiashirwad/sendpoint/releases/download/v[0-9.]+/Sendpoint-[0-9.]+\.(zip|dmg)#${DOWNLOAD_URL}#" "$SITE_PAGE"
        if ! grep -q "$DOWNLOAD_URL" "$SITE_PAGE"; then
            echo "Could not find the download link in ${SITE_PAGE}." >&2
            exit 1
        fi
    fi

    echo "==> Publishing v${VERSION}"
    git add Resources/Info.plist "$SITE_PAGE" "$APPCAST"
    git commit -m "Release ${VERSION}"
    git tag -a "v${VERSION}" -m "${APP_NAME} ${VERSION}"
    git push --atomic origin HEAD "refs/tags/v${VERSION}"

    publish_github_release

    echo "==> Deploying the website"
    (cd web && npx --yes wrangler deploy)
else
    echo
    echo "Ready: ${ARCHIVE}"
    echo "Checksum: ${CHECKSUM}"
    if [ "$AD_HOC" = true ]; then
        echo "This build is not notarized. macOS users must approve it in Privacy & Security."
    fi
    echo "Resources/Info.plist now says ${VERSION}; commit it or restore it before the next release."
fi
