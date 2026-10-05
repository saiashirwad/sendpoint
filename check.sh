#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")"
exec python3 scripts/verification.py check "$@"
