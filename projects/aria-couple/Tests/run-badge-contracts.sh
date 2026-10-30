#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
fixtures="$(mktemp -d "${TMPDIR:-/tmp}/wechatpet-badge-tests.XXXXXX")"
trap 'rm -rf "$fixtures"' EXIT
xcrun clang -fobjc-arc -fblocks -ISources -framework Foundation Sources/WPCoupleHistory.m Tests/history-tests.m -o build/history-tests
build/history-tests "$fixtures" > Tests/history-v033-report.json
xcrun clang -fobjc-arc -fblocks -ISources -framework Foundation Sources/WPCoupleHistory.m Tests/badge-clear-tests.m -o build/badge-v033-tests
build/badge-v033-tests "$fixtures" > Tests/badge-v033-report.json
xcrun clang -fobjc-arc -fblocks -ISources -framework Foundation -framework CoreGraphics Sources/WPCoupleHistory.m Sources/WPShakeDetector.m Tests/interaction-v035-tests.m -o build/interaction-v035-tests
build/interaction-v035-tests "$fixtures" > Tests/interaction-v035-report.json
python3 - <<'PY'
import json
from pathlib import Path
for name in ('history-v033-report.json', 'badge-v033-report.json', 'interaction-v035-report.json'):
    result = json.loads((Path('Tests') / name).read_text())
    assert result['allPassed'], name
    print(f"{name}: {result['caseCount']} passed")
PY
