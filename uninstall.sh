#!/bin/bash
set -euo pipefail

# Wipe the installed app and every first-run artifact so the next
# ./install.sh is a cold setup: permissions, voice model, notes, settings.

APP_NAME="Sendpoint"
BUNDLE_ID="app.sendpoint"
APP="/Applications/${APP_NAME}.app"
SUPPORT="${HOME}/Library/Application Support/${APP_NAME}"
VOICE_MODEL="${HOME}/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3"

remove() {
    local path="$1"
    if [ -e "$path" ] || [ -L "$path" ]; then
        echo "    $path"
        rm -rf "$path"
    fi
}

delete_defaults() {
    local domain="$1"
    if defaults read "$domain" >/dev/null 2>&1; then
        echo "    defaults ${domain}"
        defaults delete "$domain"
    fi
    remove "${HOME}/Library/Preferences/${domain}.plist"
    remove "${HOME}/Library/Preferences/${domain}.plist.lockfile"
}

delete_login_item() {
    local name="$1"
    osascript - "$name" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
    set itemName to item 1 of argv
    tell application "System Events"
        if exists login item itemName then
            delete login item itemName
        end if
    end tell
end run
APPLESCRIPT
}

echo "==> Quitting any running copy"
pkill -x "$APP_NAME" 2>/dev/null || true
for _ in $(seq 1 40); do
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
    sleep 0.1
done
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "    Existing copy did not quit; stopping it now"
    pkill -KILL -x "$APP_NAME"
fi

echo "==> Removing the installed app"
remove "$APP"

echo "==> Removing notes, logs, and leftover support files"
remove "$SUPPORT"
# Previous product names for this app.
remove "${HOME}/Library/Application Support/ClipboardAnnotator"
remove "${HOME}/Library/Application Support/ClipboardAnnotatorNext"

echo "==> Removing the voice model"
remove "$VOICE_MODEL"

echo "==> Removing settings"
delete_defaults "$BUNDLE_ID"
# CFBundleName domain from earlier builds.
delete_defaults "$APP_NAME"

echo "==> Removing Launch at Login"
delete_login_item "$APP_NAME"
delete_login_item "Clipboard Annotator"

echo "==> Resetting Accessibility and Microphone"
# Setup reads these; leaving a grant makes first-run look already finished.
tccutil reset All "$BUNDLE_ID" 2>/dev/null || {
    tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
    tccutil reset Microphone "$BUNDLE_ID" 2>/dev/null || true
}

echo "==> Removing caches and leftover recordings"
remove "${HOME}/Library/Caches/${BUNDLE_ID}"
remove "${HOME}/Library/Saved Application State/${BUNDLE_ID}.savedState"
remove "${HOME}/Library/HTTPStorages/${BUNDLE_ID}"
remove "${HOME}/Library/WebKit/${BUNDLE_ID}"

CACHE_DIR="$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null || true)"
TEMP_DIR="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)"
shopt -s nullglob
if [ -n "${CACHE_DIR}" ]; then
    for path in "${CACHE_DIR}${BUNDLE_ID}" "${CACHE_DIR}${BUNDLE_ID}."*; do
        remove "$path"
    done
fi
if [ -n "${TEMP_DIR}" ]; then
    for path in "${TEMP_DIR}"clipboard-note-*.caf; do
        remove "$path"
    done
fi

echo
echo "First-run state. Install with: ./install.sh"
echo "Setup will ask for Accessibility, Microphone, and the voice model."
