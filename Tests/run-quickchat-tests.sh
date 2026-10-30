#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
# The geometry is compiled from the shipping source, not a copy.
{
  echo '#define WP_GEOMETRY_TEST 1'
  sed -n '/WP_GEOMETRY_BEGIN/,/WP_GEOMETRY_END/p' Sources/WPRadialMenu.m
} > build/radial-geometry.inc
grep -q 'WPComputeFanLayout' build/radial-geometry.inc
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Wno-unused-function -ISources -Ibuild -framework Foundation -framework CoreGraphics \
  Sources/WPQuickChatModel.m Tests/quickchat-tests.m -o build/quickchat-tests
build/quickchat-tests > Tests/quickchat-v040-report.json
python3 - <<'PY'
import json
result = json.load(open('Tests/quickchat-v040-report.json'))
assert result['allPassed'], 'quickchat-v040-report.json'
print(f"quickchat-v040-report.json: {result['caseCount']} passed")
PY
