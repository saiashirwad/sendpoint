#!/bin/bash
# Does not assemble or install the app.
set -euo pipefail
cd "$(dirname "$0")"
swift build
swift test
