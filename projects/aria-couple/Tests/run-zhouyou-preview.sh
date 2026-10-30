#!/bin/bash
# Functional checks in the iOS simulator preview host. No WeChat or device is involved.
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
rm -f "$DATA/zhouyou-report.json"
xcrun simctl launch "$DEVICE" "$BUNDLE" --zhouyou-self-test >/dev/null
for _ in $(seq 1 45); do
  [[ -f "$DATA/zhouyou-report.json" ]] && break
  sleep 1
done
if [[ ! -f "$DATA/zhouyou-report.json" ]]; then
  echo 'Preview did not finish the 周游 functional checks' >&2
  exit 1
fi
cp "$DATA/zhouyou-report.json" Tests/zhouyou-v110-report.json
python3 - <<'PY'
import json
report=json.load(open('Tests/zhouyou-v110-report.json'))
failed=[name for name,passed in report['results'].items() if not passed]
print(f"zhouyou-v110-report.json: {report['caseCount']-len(failed)}/{report['caseCount']} passed")
if failed: print('Failed: '+', '.join(failed))
assert report['finished'] and report['allPassed'] and not failed
PY
