#!/bin/bash
# Real settings buttons, delayed preview notification and renderer integration.
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${1:-WeChatPet-Preview}"
BUNDLE=dev.zhour.wechatpet.preview
./build.sh preview personal
APP="$(cat build/preview-signed-path.txt)"
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null
xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
xcrun simctl uninstall "$DEVICE" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$DEVICE" "$APP"
DATA="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" data)/Library/Application Support/WeChatPet"
xcrun simctl launch "$DEVICE" "$BUNDLE" --local-preview-self-test >/dev/null
for _ in $(seq 1 90); do [[ -f "$DATA/local-preview-report.json" ]] && break; sleep 1; done
[[ -f "$DATA/local-preview-report.json" ]] || { echo 'Local preview checks did not finish' >&2; exit 1; }
cp "$DATA/local-preview-report.json" Tests/local-preview-v110-report.json
mkdir -p Tests/ui-v110
cp "$DATA"/*-local-preview-*.png Tests/ui-v110/ 2>/dev/null || true
python3 - <<'PY'
import json
report=json.load(open('Tests/local-preview-v110-report.json'))
failed=[name for name,value in report['results'].items() if not value]
print(f"local-preview-v110-report.json: {report['caseCount']-len(failed)}/{report['caseCount']} passed")
if failed: print('Failed: '+', '.join(failed))
assert report['finished'] and report['allPassed'] and not failed
PY
