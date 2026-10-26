#!/bin/bash
# Local Foundation/ImageIO import, without WeChat or a phone.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
python3 - <<'PY'
import zipfile
from pathlib import Path
with zipfile.ZipFile('build/yue-v103-fixture.zip','w',zipfile.ZIP_DEFLATED) as archive:
    for name in ('pet.json','spritesheet.png'):
        archive.write(Path('Resources/DefaultPet')/name,name)
PY
xcrun clang -fobjc-arc -fblocks -Wno-deprecated-declarations -ISources \
  -framework Foundation -framework ImageIO -framework CoreGraphics \
  Sources/WPPetImporter.m Sources/WPZipArchive.m Tests/import-tests.m -lz -o build/import-tests
build/import-tests Tests/import-fixtures build/yue-v103-fixture.zip > Tests/import-v103-report.json
python3 - <<'PY'
import json
report=json.load(open('Tests/import-v103-report.json'))
cases={key:value for key,value in report.items() if key!='allPassed'}
print(f"import-v103-report.json: {sum(bool(value) for value in cases.values())}/{len(cases)} passed")
assert len(cases)==13 and report['allPassed'] and all(cases.values())
PY
