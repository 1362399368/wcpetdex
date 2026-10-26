#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
fixtures="$(mktemp -d "${TMPDIR:-/tmp}/wechatpet-startup-tests.XXXXXX")"
trap 'rm -rf "$fixtures"' EXIT
xcrun clang -fobjc-arc -fblocks -ISources -framework Foundation Sources/WPCoupleHistory.m Tests/startup-and-retention-tests.m -o build/startup-and-retention-tests
WP_TEST_ROOT="$fixtures" build/startup-and-retention-tests
