#!/bin/bash
# Foundation/ImageIO protocol checks; optional first arg is a real Yue2 ZIP.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 Tests/make-v105-import-fixtures.py
mkdir -p build
COMMON=(-fobjc-arc -fblocks -Wno-deprecated-declarations -ISources -framework Foundation -framework ImageIO -framework CoreGraphics)
xcrun clang "${COMMON[@]}" Sources/WPPetImporter.m Sources/WPZipArchive.m Tests/import-tests.m -lz -o build/import-legacy-tests
xcrun clang "${COMMON[@]}" Sources/WPPetImporter.m Sources/WPZipArchive.m Tests/import-v105-tests.m -lz -o build/import-v105-tests
build/import-legacy-tests Tests/import-fixtures build/v105-import-fixtures/legacy-v4.zip > Tests/import-legacy-v110-report.json
if [[ $# -gt 0 ]]; then
  build/import-v105-tests build/v105-import-fixtures "$1" > Tests/import-v110-report.json
else
  build/import-v105-tests build/v105-import-fixtures > Tests/import-v110-report.json
fi
python3 - <<'PY'
import json
from pathlib import Path
root=Path('Tests')
legacy=json.loads((root/'import-legacy-v110-report.json').read_text())
current=json.loads((root/'import-v110-report.json').read_text())
old_cases={k:v for k,v in legacy.items() if k!='allPassed'}
print(f"Legacy import: {sum(bool(v) for v in old_cases.values())}/{len(old_cases)} passed")
print(f"v5 import: {sum(bool(v) for v in current['results'].values())}/{current['caseCount']} passed")
assert legacy['allPassed'] and current['allPassed']
PY
