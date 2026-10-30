#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture="$(mktemp -d /tmp/wechatpet-v038.XXXXXX)"
trap 'rm -rf "$fixture"' EXIT
xcrun clang -fobjc-arc -fblocks -ISources -framework Foundation Sources/WPCoupleHistory.m Tests/interaction-v038-tests.m -o build/interaction-v038-tests
build/interaction-v038-tests "$fixture" > Tests/interaction-v038-report.json
cat Tests/interaction-v038-report.json
