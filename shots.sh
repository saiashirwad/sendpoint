#!/bin/bash
# Renders every screen in light and dark into .build/shots.
# --diff keeps the last set and fails with a diff image for each screen that changed.
set -uo pipefail
cd "$(dirname "$0")"
SHOTS="$(pwd)/.build/shots"
DIFFS="$(pwd)/.build/shots-diff"
LOG=.build/shots.log
RECORD=all
if [ "${1:-}" = "--diff" ]; then
    RECORD=missing
else
    rm -rf "$SHOTS"
fi
rm -rf "$DIFFS"
mkdir -p "$SHOTS" "$DIFFS"
: >"$LOG"
STATUS=0
for APPEARANCE in light dark; do
    SENDPOINT_SHOTS_DIR="$SHOTS" SENDPOINT_SHOTS_APPEARANCE="$APPEARANCE" SENDPOINT_SHOTS_RECORD="$RECORD" \
        SNAPSHOT_ARTIFACTS="$DIFFS" swift test --filter SendpointScreenshotTests >>"$LOG" 2>&1 || STATUS=$?
done
grep -E "error:|Test Case .* failed" "$LOG" | sort -u | head -40
COUNT=$(find "$SHOTS" -name '*.png' | wc -l | tr -d ' ')
if [ "$STATUS" -eq 0 ]; then
    echo "shots passed: $COUNT screens in $SHOTS"
else
    echo "shots FAILED (exit $STATUS): $COUNT screens in $SHOTS, diffs in $DIFFS. Full log: $LOG"
fi
exit "$STATUS"
