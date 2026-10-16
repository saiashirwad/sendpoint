#!/bin/bash
# Build the app and run the Core tests.
set -euo pipefail
cd "$(dirname "$0")"
swift build
swift test --quiet
