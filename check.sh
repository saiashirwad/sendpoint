#!/bin/bash
# Does not assemble or install the app. Full output goes to .build/check.log.
set -uo pipefail
cd "$(dirname "$0")"
LOG=.build/check.log
mkdir -p .build
{ swift build && swift test; } >"$LOG" 2>&1
STATUS=$?
grep -E "error:|$(pwd)/(Sources|Tests)/.*warning:|Test Case .* failed|with [1-9][0-9]* failures?" "$LOG" | grep -v "Test Suite '.*' failed" | sort -u | head -60
SUMMARY=$(grep -A1 "Test Suite 'All tests'" "$LOG" | grep -oE "Executed [0-9]+ tests?(, with [0-9]+ tests? skipped)? and [0-9]+ failures?|Executed [0-9]+ tests?, with [0-9]+ failures?" | awk '{t+=$2; for(i=1;i<=NF;i++){if($(i+1)~/^skipped/||$(i+1)~/^tests?$/&&$(i+2)=="skipped")s+=$i; if($(i+1)~/^failures?$/)f+=$i}} END{if(NR)printf "%d tests, %d skipped, %d failures", t, s, f}')
if [ "$STATUS" -eq 0 ]; then
    echo "check passed: ${SUMMARY:-build only}"
else
    echo "check FAILED (exit $STATUS): ${SUMMARY:-build failed}. Full log: $LOG"
fi
exit "$STATUS"
