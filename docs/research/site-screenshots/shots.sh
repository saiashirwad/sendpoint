#!/bin/bash
# Research spike; run from anywhere. Baselines belong to this checkout.
set -uo pipefail
cd "$(dirname "$0")/../../.."
ROOT="$PWD"
LOG="$ROOT/.build/site-shots.log"
MODE=all
case "${1:-}" in
  '') ;;
  --diff) MODE=none ;;
  *) echo 'usage: shots.sh [--diff]' >&2; exit 2 ;;
esac
mkdir -p .build
if [ "$MODE" = all ]; then rm -rf "$ROOT/.build/site-shots"; fi
STATUS=0
(cd docs/research/site-screenshots && bun x --no-install playwright test --update-snapshots="$MODE") >"$LOG" 2>&1 || STATUS=$?
COUNT=$(find "$ROOT/.build/site-shots" -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
if [ "$STATUS" -eq 0 ]; then
  echo "site shots passed: $COUNT screens in .build/site-shots; full log: .build/site-shots.log"
else
  grep -E 'Error:|failed|does not exist' "$LOG" | head -20
  echo "site shots FAILED (exit $STATUS): diffs in .build/site-shots-diff; full log: .build/site-shots.log"
fi
exit "$STATUS"
