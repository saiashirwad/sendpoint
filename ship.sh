#!/bin/bash
# Builds, assembles, and installs Sendpoint. Full output goes to .build/ship.log.
set -uo pipefail
cd "$(dirname "$0")"
LOG=.build/ship.log
mkdir -p .build
{ ./build.sh "$@" && ./install.sh; } >"$LOG" 2>&1
STATUS=$?
grep -E "^==>|error:|$(pwd)/Sources/.*warning:|failed" "$LOG" | head -40
if [ "$STATUS" -eq 0 ]; then
    echo "ship passed: installed and launched"
else
    echo "ship FAILED (exit $STATUS). Full log: $LOG"
fi
exit "$STATUS"
