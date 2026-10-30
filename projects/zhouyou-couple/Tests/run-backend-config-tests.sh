#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
cp "${WP_BACKEND_CONFIG:-Config/backend.example.json}" build/BackendConfig.json
xcrun clang -fobjc-arc -fblocks -ISources -framework Foundation Sources/WPBackendConfiguration.m Tests/backend-config-tests.m -o build/backend-config-tests
build/backend-config-tests > Tests/backend-config-report.json
python3 - <<'PY'
import json
from pathlib import Path
report=json.loads(Path('Tests/backend-config-report.json').read_text())
assert report['allPassed']
print(f"backend-config-report.json: {report['caseCount']} passed")
PY
