#!/bin/bash
# Cut a distributable build, entirely from this Mac.
#
#   ./release.sh 1.2                         build, notarize, staple, zip
#   ./release.sh 1.2 --publish               ...then publish on GitHub
#   ./release.sh 1.2 --ad-hoc                build without notarizing
#   ./release.sh 1.2 --ad-hoc --publish      ...then publish on GitHub
#
# --ad-hoc skips notarization but still signs with whatever certificate
# build.sh finds (Developer ID, else Apple Development). A stable certificate
# keeps users' Accessibility grants across updates; a true ad-hoc signature
# is pinned to the binary's hash and breaks the grant on every release.
#
# Publishing also points the website's download button at the new zip,
# commits that with the version bump, and deploys the site with wrangler.
#
# One-time setup:
#   1. Install a "Developer ID Application" certificate in your keychain
#      (Xcode → Settings → Accounts → Manage Certificates).
#   2. Store notarization credentials, using an app-specific password from
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
while [ "$#" -gt 0 ]; do
    case "$1" in
        --publish)
            PUBLISH=true
            ;;
        --ad-hoc|--adhoc)
            AD_HOC=true
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "usage: ./release.sh VERSION [--ad-hoc] [--publish]" >&2
            exit 1
            ;;
    esac
    shift
done

if [ -z "$VERSION" ]; then
    echo "usage: ./release.sh VERSION [--ad-hoc] [--publish]" >&2
    exit 1
fi

APP_NAME="Sendpoint"
APP="dist/${APP_NAME}.app"
ARCHIVE="dist/Sendpoint-${VERSION}.zip"
CHECKSUM="${ARCHIVE}.sha256"
NOTARY_PROFILE="${NOTARY_PROFILE:-sendpoint}"

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
    if git rev-parse --verify --quiet "refs/tags/v${VERSION}" >/dev/null; then
        echo "Tag v${VERSION} already exists." >&2
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
DOWNLOAD_URL="https://github.com/saiashirwad/sendpoint/releases/download/v${VERSION}/Sendpoint-${VERSION}.zip"

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

echo "==> Archiving ${ARCHIVE}"
ditto -c -k --keepParent "$APP" "$ARCHIVE"
(
    cd dist
    shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")"
)

if [ "$PUBLISH" = true ]; then
    echo "==> Pointing the website at ${DOWNLOAD_URL}"
    sed -i '' -E "s#https://github.com/saiashirwad/sendpoint/releases/download/v[0-9.]+/Sendpoint-[0-9.]+\.zip#${DOWNLOAD_URL}#" "$SITE_PAGE"
    if ! grep -q "$DOWNLOAD_URL" "$SITE_PAGE"; then
        echo "Could not find the download link in ${SITE_PAGE}." >&2
        exit 1
    fi

    echo "==> Publishing v${VERSION}"
    git add Resources/Info.plist "$SITE_PAGE"
    git commit -m "Release ${VERSION}"
    git tag -a "v${VERSION}" -m "${APP_NAME} ${VERSION}"
    git push --atomic origin HEAD "refs/tags/v${VERSION}"

    if [ "$AD_HOC" = true ]; then
        RELEASE_NOTES=$(printf '%s\n' \
            '> [!WARNING]' \
            '> This build is not notarized by Apple.' \
            '> Only open it if you trust this repository.' \
            '' \
            'Move **Sendpoint.app** to `/Applications` and try to open it once.' \
            'If macOS blocks it, open **System Settings > Privacy & Security**, scroll to **Security**, click **Open Anyway**, then confirm **Open**.')
        gh release create "v${VERSION}" "$ARCHIVE" "$CHECKSUM" \
            --title "${APP_NAME} ${VERSION}" \
            --generate-notes \
            --notes "$RELEASE_NOTES"
    else
        gh release create "v${VERSION}" "$ARCHIVE" "$CHECKSUM" \
            --title "${APP_NAME} ${VERSION}" \
            --generate-notes
    fi

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
